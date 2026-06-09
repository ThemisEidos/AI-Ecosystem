[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $true)]
    [string]$Goal,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10)]
    [int]$MaxIterations = 3,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$HelperPath = Join-Path $PSScriptRoot "PDA_AgentLoop.ps1"
if (-not (Test-Path -LiteralPath $HelperPath -PathType Leaf)) {
    throw "Agent loop helper missing: $HelperPath"
}
. $HelperPath

$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
if ((Test-Path -LiteralPath $ParserPath -PathType Leaf) -and -not (Get-Command -Name ConvertFrom-PDAMixedJson -ErrorAction SilentlyContinue)) {
    . $ParserPath
}

function Invoke-PDAJsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$SourceName
    )

    $Raw = & pwsh -NoProfile -File $Path @Arguments 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "$SourceName returned empty output."
    }

    return ConvertFrom-PDAMixedJson -Text $Text -SourceName $SourceName
}

$GoalPlanScript = Join-Path $PSScriptRoot "Get-PDAGoalPlan.ps1"
if (-not (Test-Path -LiteralPath $GoalPlanScript -PathType Leaf)) {
    throw "Goal planning script missing: $GoalPlanScript"
}

$GoalPlan = Invoke-PDAJsonScript -Path $GoalPlanScript -Arguments @("-Text", $Goal, "-Root", $Root, "-Persist", "-AsJson") -SourceName "PDA goal planning"
if ([string]$GoalPlan.status -ne "pass") {
    throw "Goal planning failed for agent run creation."
}

$RunRoot = Get-PDAAgentRunRoot -Root $Root
New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null

$RunId = if ($GoalPlan.PSObject.Properties.Name -contains "plan_id" -and -not [string]::IsNullOrWhiteSpace([string]$GoalPlan.plan_id)) {
    [string]$GoalPlan.plan_id
}
else {
    "agent-run-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
}

$RunPath = Get-PDAAgentRunPath -RunId $RunId -Root $Root
$MarkdownPath = Get-PDAAgentRunMarkdownPath -RunId $RunId -Root $Root

$PlanObject = [pscustomobject]@{
    plan_id              = [string]$GoalPlan.plan_id
    goal                 = [string]$GoalPlan.goal
    goal_type            = [string]$GoalPlan.goal_type
    category             = [string]$GoalPlan.category
    complexity           = [string]$GoalPlan.complexity
    approval_required    = [bool]$GoalPlan.approval_required
    deliverables         = @($GoalPlan.deliverables)
    subtasks             = @($GoalPlan.subtasks)
    recommended_executor_chain = @($GoalPlan.recommended_executor_chain)
    execution_plan       = $GoalPlan.execution_plan
    source_of_truth      = "Scripts/Get-PDAGoalPlan.ps1"
}

$CurrentStep = [pscustomobject]@{}
if (@($PlanObject.subtasks).Count -gt 0) {
    $CurrentStep = @($PlanObject.subtasks)[0]
}

$AssignedTool = if ($CurrentStep.PSObject.Properties.Name -contains "recommended_executor") { [string]$CurrentStep.recommended_executor } else { "" }
$ToolCheck = if (-not [string]::IsNullOrWhiteSpace($AssignedTool)) {
    Test-PDAAgentToolAllowedForCategory -ToolName $AssignedTool -Category ([string]$PlanObject.category) -RequiresLocalOnly:([string]$PlanObject.category -in @("category_2", "restricted_local")) -Root $Root
}
else {
    [pscustomobject]@{
        status = "blocked"
        allowed = $false
        blocked_reason = "No tool could be assigned."
    }
}

$Run = [ordered]@{
    run_id            = $RunId
    created_at        = (Get-Date).ToUniversalTime().ToString("o")
    updated_at        = (Get-Date).ToUniversalTime().ToString("o")
    goal              = [string]$PlanObject.goal
    goal_type         = [string]$PlanObject.goal_type
    category          = [string]$PlanObject.category
    status            = $(if ($ToolCheck.allowed) { "pending_approval" } else { "blocked" })
    approval_status   = $(if ($ToolCheck.allowed) { "pending" } else { "blocked" })
    approval_required = [bool]$PlanObject.approval_required
    iteration_count   = 0
    max_iterations    = [int]$MaxIterations
    current_step_index = 0
    current_step      = $(if (@($PlanObject.subtasks).Count -gt 0) { ConvertTo-PDAAgentHashtable -Value $CurrentStep } else { $null })
    assigned_tool     = [string]$AssignedTool
    action_request    = $null
    result            = $null
    review            = $null
    next_action       = ""
    stop_reason       = ""
    completion_criteria = @($PlanObject.deliverables)
    plan              = ConvertTo-PDAAgentHashtable -Value $PlanObject
    execution_plan    = ConvertTo-PDAAgentHashtable -Value $PlanObject.execution_plan
    approval_history  = @()
    action_history    = @()
    result_history    = @()
    review_history    = @()
    tool_registry_path = Get-PDAAgentToolRegistryPath -Root $Root
    tool_registry     = ConvertTo-PDAAgentHashtable -Value (Get-PDAAgentToolRegistry -Root $Root)
}

if (-not $ToolCheck.allowed) {
    $Run.stop_reason = [string]$ToolCheck.blocked_reason
    $Run.next_action = [string]$ToolCheck.blocked_reason
    $Run.action_request = [pscustomobject]@{
        action_id = "$RunId-step-01"
        status = "blocked"
        assigned_tool = [string]$AssignedTool
        approval_required = $true
        dispatch_ready = $false
        next_action = [string]$ToolCheck.blocked_reason
    }
}
else {
    $ActionRequest = New-PDAAgentActionRequest -Run ([pscustomobject]$Run) -Step $CurrentStep
    $Run.action_request = ConvertTo-PDAAgentHashtable -Value $ActionRequest
    $Run.next_action = Get-PDAAgentNextAction -Run ([pscustomobject]$Run)
}

$RunObject = [pscustomobject]$Run
$RunObject | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $RunPath -Encoding UTF8
Write-PDAAgentRunMarkdown -Run $RunObject -Path $MarkdownPath

$Index = Get-PDAAgentRunIndex -Root $Root
$Index.runs = @(
    @($Index.runs | Where-Object { [string]$_.run_id -ne $RunId }) +
    @((Get-PDAAgentRunSummary -Run $RunObject))
)
$Index.run_count = @($Index.runs).Count
$Index.active_run_count = @($Index.runs | Where-Object { [string]$_.status -in @("pending_approval", "ready_for_action", "running", "reviewing") }).Count
$Index.pending_approval_count = @($Index.runs | Where-Object { [string]$_.status -eq "pending_approval" -or [string]$_.approval_status -eq "pending" }).Count
$Index.completed_count = @($Index.runs | Where-Object { [string]$_.status -eq "completed" }).Count
$Index.blocked_count = @($Index.runs | Where-Object { [string]$_.status -eq "blocked" }).Count
Save-PDAAgentRunIndex -Index $Index -Root $Root | Out-Null

$Report = [pscustomobject]@{
    status           = "pass"
    operation        = "create"
    run_id           = $RunId
    run_path         = $RunPath
    markdown_path    = $MarkdownPath
    approval_required = [bool]$RunObject.approval_required
    next_action      = [string]$RunObject.next_action
    action_request   = $RunObject.action_request
    run              = $RunObject
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 30
    return
}

Write-Host "[PDA AGENT RUN CREATED]"
Write-Host ("Run ID        : {0}" -f $Report.run_id)
Write-Host ("Goal          : {0}" -f $RunObject.goal)
Write-Host ("Status        : {0}" -f $RunObject.status)
Write-Host ("Next action   : {0}" -f $RunObject.next_action)
