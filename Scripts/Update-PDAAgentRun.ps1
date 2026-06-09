[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $true)]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [ValidateSet("pending_approval", "ready_for_action", "running", "reviewing", "completed", "blocked", "failed")]
    [string]$Status,

    [Parameter(Mandatory = $false)]
    [ValidateSet("pending", "approved", "rejected", "blocked")]
    [string]$ApprovalStatus,

    [Parameter(Mandatory = $false)]
    [string]$AssignedTool,

    [Parameter(Mandatory = $false)]
    [int]$CurrentStepIndex = -1,

    [Parameter(Mandatory = $false)]
    [string]$ActionRequestText,

    [Parameter(Mandatory = $false)]
    [string]$ResultText,

    [Parameter(Mandatory = $false)]
    [string]$ReviewText,

    [Parameter(Mandatory = $false)]
    [string]$NextAction,

    [Parameter(Mandatory = $false)]
    [string]$StopReason,

    [Parameter(Mandatory = $false)]
    [int]$IterationCount = -1,

    [Parameter(Mandatory = $false)]
    [int]$MaxIterations = -1,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$HelperPath = Join-Path $PSScriptRoot "PDA_AgentLoop.ps1"
if (-not (Test-Path -LiteralPath $HelperPath -PathType Leaf)) {
    throw "Agent loop helper missing: $HelperPath"
}
. $HelperPath

$Run = Get-PDAAgentRunRecord -RunId $RunId -Root $Root
if (-not $Run) {
    throw "Agent run not found: $RunId"
}

$Changed = $false

if ($PSBoundParameters.ContainsKey("Status") -and -not [string]::IsNullOrWhiteSpace($Status)) {
    $Run.status = $Status
    $Changed = $true
}

if ($PSBoundParameters.ContainsKey("ApprovalStatus") -and -not [string]::IsNullOrWhiteSpace($ApprovalStatus)) {
    $Run.approval_status = $ApprovalStatus
    if ($ApprovalStatus -eq "approved" -and -not $PSBoundParameters.ContainsKey("Status")) {
        $Run.status = "ready_for_action"
    }
    elseif ($ApprovalStatus -eq "rejected" -and -not $PSBoundParameters.ContainsKey("Status")) {
        $Run.status = "blocked"
    }
    $Run.approval_history = @($Run.approval_history) + @([pscustomobject]@{
        approval_status = $ApprovalStatus
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
    })
    $Changed = $true
}

if ($PSBoundParameters.ContainsKey("AssignedTool") -and -not [string]::IsNullOrWhiteSpace($AssignedTool)) {
    $Run.assigned_tool = $AssignedTool
    $Changed = $true
}

if ($CurrentStepIndex -ge 0) {
    $Run.current_step_index = [int]$CurrentStepIndex
    $Changed = $true
}

if ($PSBoundParameters.ContainsKey("ActionRequestText") -and -not [string]::IsNullOrWhiteSpace($ActionRequestText)) {
    if ((-not ($Run.PSObject.Properties.Name -contains "action_request")) -or (-not $Run.action_request)) {
        $Run.action_request = [pscustomobject]@{}
    }
    $Run.action_request | Add-Member -NotePropertyName action_request -NotePropertyValue $ActionRequestText -Force
    $Changed = $true
}

if ($PSBoundParameters.ContainsKey("ResultText") -and -not [string]::IsNullOrWhiteSpace($ResultText)) {
    $Run.result = [pscustomobject]@{
        text = $ResultText
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
    }
    $Run.result_history = @($Run.result_history) + @($Run.result)
    $Run.iteration_count = [int]$Run.iteration_count + 1
    $Run.review = if ($PSBoundParameters.ContainsKey("ReviewText") -and -not [string]::IsNullOrWhiteSpace($ReviewText)) {
        [pscustomobject]@{
            text = $ReviewText
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
        }
    }
    else {
        [pscustomobject]@{
            text = ""
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
        }
    }
    $Run.review_history = @($Run.review_history) + @($Run.review)

    $Steps = @()
    if ($Run.PSObject.Properties.Name -contains "plan" -and $Run.plan -and $Run.plan.PSObject.Properties.Name -contains "subtasks") {
        $Steps = @($Run.plan.subtasks)
    }
    $NextIndex = [int]$Run.current_step_index + 1
    if ($Steps.Count -gt 0 -and $NextIndex -lt $Steps.Count) {
        $Run.current_step_index = $NextIndex
        $Run.current_step = ConvertTo-PDAAgentHashtable -Value $Steps[$NextIndex]
        $Run.assigned_tool = if ($Steps[$NextIndex].PSObject.Properties.Name -contains "recommended_executor") { [string]$Steps[$NextIndex].recommended_executor } else { [string]$Run.assigned_tool }
        $Run.action_request = ConvertTo-PDAAgentHashtable -Value (New-PDAAgentActionRequest -Run ([pscustomobject]$Run) -Step $Steps[$NextIndex])
        $Run.status = "pending_approval"
        $Run.approval_status = "pending"
        $Run.next_action = Get-PDAAgentNextAction -Run ([pscustomobject]$Run)
    }
    else {
        $Run.status = "completed"
        $Run.next_action = "Agent run complete."
    }
    $Changed = $true
}

if ($PSBoundParameters.ContainsKey("NextAction") -and -not [string]::IsNullOrWhiteSpace($NextAction)) {
    $Run.next_action = $NextAction
    $Changed = $true
}

if ($PSBoundParameters.ContainsKey("StopReason") -and -not [string]::IsNullOrWhiteSpace($StopReason)) {
    $Run.stop_reason = $StopReason
    $Changed = $true
}

if ($IterationCount -ge 0) {
    $Run.iteration_count = [int]$IterationCount
    $Changed = $true
}

if ($MaxIterations -ge 0) {
    $Run.max_iterations = [int]$MaxIterations
    $Changed = $true
}

if ((-not ($Run.PSObject.Properties.Name -contains "next_action")) -or [string]::IsNullOrWhiteSpace([string]$Run.next_action)) {
    $Run.next_action = Get-PDAAgentNextAction -Run ([pscustomobject]$Run)
}

if ([int]$Run.iteration_count -ge [int]$Run.max_iterations -and [string]$Run.status -notin @("completed", "blocked", "failed")) {
    $Run.status = "blocked"
    if ([string]::IsNullOrWhiteSpace([string]$Run.stop_reason)) {
        $Run.stop_reason = "Maximum iteration count reached."
    }
    $Run.next_action = $Run.stop_reason
}

$Run.updated_at = (Get-Date).ToUniversalTime().ToString("o")
$RunObject = [pscustomobject]$Run
$RunPath = Get-PDAAgentRunPath -RunId $RunId -Root $Root
$MarkdownPath = Get-PDAAgentRunMarkdownPath -RunId $RunId -Root $Root
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
    status = "pass"
    run_id = $RunId
    run_path = $RunPath
    markdown_path = $MarkdownPath
    run = $RunObject
    changed = [bool]$Changed
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 30
    return
}

Write-Host "[PDA AGENT RUN UPDATED]"
Write-Host ("Run ID      : {0}" -f $Report.run_id)
Write-Host ("Status      : {0}" -f $RunObject.status)
Write-Host ("Next action : {0}" -f $RunObject.next_action)
