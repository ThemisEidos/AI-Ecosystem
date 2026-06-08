[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$GoalPlanScript = Join-Path $PSScriptRoot "Get-PDAGoalPlan.ps1"
$ExecutionPlanScript = Join-Path $PSScriptRoot "Get-PDAExecutionPlan.ps1"
$BridgeScript = Join-Path $PSScriptRoot "Invoke-PDAChatBridge.ps1"
$DashboardStatusScript = Join-Path $PSScriptRoot "Get-PDADashboardStatus.ps1"
$UpdateDashboardScript = Join-Path $PSScriptRoot "Update-PDADashboard.ps1"
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
if (Test-Path -LiteralPath $ParserPath -PathType Leaf) {
    . $ParserPath
}

function Invoke-PDAJsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $Raw = & pwsh -NoProfile -File $Path @Arguments 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Script returned empty output: $Path"
    }

    return ConvertFrom-PDAMixedJson -Text $Text -SourceName $Path
}

function Assert-PDACondition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][System.Collections.Generic.List[string]]$Issues
    )

    if (-not $Condition -and $Issues) {
        $Issues.Add($Message)
    }

    return $Condition
}

function Format-PDAJsonFence {
    param([Parameter(Mandatory = $true)][string]$JsonText)

    return @('```json', $JsonText, '```') -join [Environment]::NewLine
}

$Issues = New-Object System.Collections.Generic.List[string]
$GoalText = "I want to start reading classic literature. Can you search the internet, create a list of top books from famous authors, write a report, include links and synopses, and make it a PDF?"

$GoalPlan = Invoke-PDAJsonScript -Path $GoalPlanScript -Arguments @("-Text", $GoalText, "-Root", $Root, "-Persist", "-AsJson")
Assert-PDACondition -Condition ([string]$GoalPlan.goal_type -eq "research_report_pdf") -Message "Goal plan did not classify the classic literature request as research_report_pdf." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$GoalPlan.category -eq "category_1") -Message "Goal plan should be Category 1 for the classic literature request." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($GoalPlan.approval_required) -Message "Goal plan should require approval before dispatch preparation." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (@($GoalPlan.deliverables) -contains "reading list") -Message "Goal plan did not include a reading list deliverable." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (@($GoalPlan.deliverables) -contains "written report") -Message "Goal plan did not include a report deliverable." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (@($GoalPlan.deliverables) -contains "PDF export") -Message "Goal plan did not include a PDF deliverable." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (@($GoalPlan.subtasks).Count -ge 3) -Message "Goal plan did not generate enough subtasks." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($GoalPlan.execution_plan.PSObject.Properties.Name -contains "executor_chain") -Message "Goal plan did not include an execution plan." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (@($GoalPlan.execution_plan.executor_chain).Count -ge 3) -Message "Execution plan did not include enough executor steps." -Issues $Issues | Out-Null

$ExecutionPlan = Invoke-PDAJsonScript -Path $ExecutionPlanScript -Arguments @("-GoalPlanJson", (($GoalPlan | ConvertTo-Json -Depth 30 -Compress)), "-AsJson")
Assert-PDACondition -Condition (@($ExecutionPlan.subtasks).Count -ge 3) -Message "Execution plan did not retain subtasks." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (@($ExecutionPlan.recommended_executors) -contains "gemini-cli") -Message "Execution plan did not recommend gemini-cli for research work." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (@($ExecutionPlan.recommended_executors) -contains "reporter-worker") -Message "Execution plan did not recommend reporter-worker for reporting work." -Issues $Issues | Out-Null

$ExecutionPlanFenced = Invoke-PDAJsonScript -Path $ExecutionPlanScript -Arguments @("-GoalPlanJson", (Format-PDAJsonFence -JsonText (($GoalPlan | ConvertTo-Json -Depth 30 -Compress))), "-AsJson")
Assert-PDACondition -Condition ([string]$ExecutionPlanFenced.status -eq "pass") -Message "Execution plan did not accept fenced JSON input." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (@($ExecutionPlanFenced.subtasks).Count -ge 3) -Message "Execution plan fenced input did not retain subtasks." -Issues $Issues | Out-Null

$BridgeResult = Invoke-PDAJsonScript -Path $BridgeScript -Arguments @("-Message", $GoalText, "-AsJson")
Assert-PDACondition -Condition ([string]$BridgeResult.handoff_status -eq "goal_planning") -Message "Chat bridge did not route the goal prompt to goal planning." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$BridgeResult.dispatch_status -eq "not_applicable") -Message "Goal planning should not dispatch work." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($BridgeResult.PSObject.Properties.Name -contains "goal_plan") -Message "Chat bridge did not return the goal plan payload." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($BridgeResult.PSObject.Properties.Name -contains "execution_plan") -Message "Chat bridge did not return the execution plan payload." -Issues $Issues | Out-Null

$DashboardBefore = Invoke-PDAJsonScript -Path $DashboardStatusScript -Arguments @("-AsJson", "-NoThrow")
Assert-PDACondition -Condition ($DashboardBefore.PSObject.Properties.Name -contains "commander_planning") -Message "Dashboard status did not expose commander planning data." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([int]$DashboardBefore.commander_planning.plan_count -ge 1) -Message "Dashboard planning count should be at least one after persistence." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([int]$DashboardBefore.commander_planning.pending_plan_count -ge 1) -Message "Dashboard planning should show at least one pending plan." -Issues $Issues | Out-Null

$DashboardUpdate = & pwsh -NoProfile -File $UpdateDashboardScript -NoThrow 2>&1
if ($LASTEXITCODE -ne 0) {
    $Issues.Add("Dashboard update failed.")
}

$DashboardPath = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\PDA Dashboard.md"
Assert-PDACondition -Condition (Test-Path -LiteralPath $DashboardPath -PathType Leaf) -Message "Dashboard file was not created." -Issues $Issues | Out-Null
if (Test-Path -LiteralPath $DashboardPath -PathType Leaf) {
    $DashboardText = Get-Content -LiteralPath $DashboardPath -Raw
    Assert-PDACondition -Condition ($DashboardText -match '(?m)^## Commander Planning$') -Message "Dashboard markdown did not include the Commander Planning section." -Issues $Issues | Out-Null
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    goal_plan = $GoalPlan
    execution_plan = $ExecutionPlan
    bridge = $BridgeResult
    dashboard = $DashboardBefore
    issues = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 30
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA goal planning validation failed."
    }
    return
}

Write-Host "[*] PDA goal planning tests"
Write-Host ("Status     : {0}" -f $Report.status)
Write-Host ("Issues     : {0}" -f @($Report.issues).Count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA goal planning validation failed."
}
