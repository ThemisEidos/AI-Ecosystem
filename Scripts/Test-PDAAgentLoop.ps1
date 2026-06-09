[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$LoopScript = Join-Path $PSScriptRoot "Invoke-PDAAgentLoop.ps1"
$CreateScript = Join-Path $PSScriptRoot "New-PDAAgentRun.ps1"
$GetScript = Join-Path $PSScriptRoot "Get-PDAAgentRun.ps1"
$UpdateScript = Join-Path $PSScriptRoot "Update-PDAAgentRun.ps1"
$DashboardStatusScript = Join-Path $PSScriptRoot "Get-PDADashboardStatus.ps1"
$DashboardUpdateScript = Join-Path $PSScriptRoot "Update-PDADashboard.ps1"
$ChatBridgeTestScript = Join-Path $PSScriptRoot "Test-PDAChatBridge.ps1"
$DecisionTestScript = Join-Path $PSScriptRoot "Test-PDACommanderDecisionEngine.ps1"
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

$Issues = New-Object System.Collections.Generic.List[string]
$GoalText = "Validate first 10 website links in XLSX and write Markdown report to Obsidian."

foreach ($Required in @($LoopScript, $CreateScript, $GetScript, $UpdateScript)) {
    Assert-PDACondition -Condition (Test-Path -LiteralPath $Required -PathType Leaf) -Message "Required agent loop script missing: $Required" -Issues $Issues | Out-Null
}

$CreateResult = Invoke-PDAJsonScript -Path $LoopScript -Arguments @("-Root", $Root, "-Goal", $GoalText, "-MaxIterations", "3", "-AsJson")
Assert-PDACondition -Condition ([string]$CreateResult.status -eq "pass") -Message "Agent loop create request failed." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$CreateResult.operation -eq "create") -Message "Agent loop did not report create operation." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (-not [string]::IsNullOrWhiteSpace([string]$CreateResult.run_id)) -Message "Agent run id was not created." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($CreateResult.run.PSObject.Properties.Name -contains "plan") -Message "Agent run did not persist the plan." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($CreateResult.run.PSObject.Properties.Name -contains "current_step") -Message "Agent run did not persist the current step." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($CreateResult.run.PSObject.Properties.Name -contains "action_request") -Message "Agent run did not create an action request." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$CreateResult.run.status -eq "pending_approval") -Message "Agent run should start pending approval." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([bool]$CreateResult.run.approval_required) -Message "Agent run should require approval." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (-not [string]::IsNullOrWhiteSpace([string]$CreateResult.run.assigned_tool)) -Message "Agent run did not assign a tool." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (-not [string]::IsNullOrWhiteSpace([string]$CreateResult.next_action)) -Message "Agent run did not generate a next action." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (($CreateResult.run.tool_registry.PSObject.Properties.Name -contains "tool_count") -and ([int]$CreateResult.run.tool_registry.tool_count -ge 8)) -Message "Agent tool registry was not loaded." -Issues $Issues | Out-Null

$RunId = [string]$CreateResult.run_id
$StoredRun = Invoke-PDAJsonScript -Path $GetScript -Arguments @("-Root", $Root, "-RunId", $RunId, "-AsJson")
Assert-PDACondition -Condition ([string]$StoredRun.status -eq "pass") -Message "Stored agent run could not be retrieved." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$StoredRun.run.run_id -eq $RunId) -Message "Stored run id mismatch." -Issues $Issues | Out-Null

$ApprovedResult = Invoke-PDAJsonScript -Path $UpdateScript -Arguments @("-Root", $Root, "-RunId", $RunId, "-ApprovalStatus", "approved", "-AsJson")
Assert-PDACondition -Condition ([string]$ApprovedResult.run.status -eq "ready_for_action") -Message "Approved run should be ready for action." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$ApprovedResult.run.approval_status -eq "approved") -Message "Approved run should record approval status." -Issues $Issues | Out-Null

$ResultText = "Validated the first 10 links and captured the result in Markdown."
$ReviewedResult = Invoke-PDAJsonScript -Path $UpdateScript -Arguments @("-Root", $Root, "-RunId", $RunId, "-ResultText", $ResultText, "-ReviewText", "First step completed successfully.", "-AsJson")
Assert-PDACondition -Condition (-not [string]::IsNullOrWhiteSpace([string]$ReviewedResult.run.next_action)) -Message "Agent run did not generate a follow-up next action." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($ReviewedResult.run.result_history.Count -ge 1) -Message "Agent run did not record the result history." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($ReviewedResult.run.review_history.Count -ge 1) -Message "Agent run did not record the review history." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([int]$ReviewedResult.run.iteration_count -ge 1) -Message "Agent run did not increment iteration count." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([int]$ReviewedResult.run.current_step_index -ge 1 -or [string]$ReviewedResult.run.status -eq "completed") -Message "Agent run did not advance or complete after result recording." -Issues $Issues | Out-Null

$DashboardStatus = Invoke-PDAJsonScript -Path $DashboardStatusScript -Arguments @("-RootPath", $Root, "-AsJson", "-NoThrow")
Assert-PDACondition -Condition ($DashboardStatus.PSObject.Properties.Name -contains "commander_agent_loop") -Message "Dashboard status did not expose the agent loop section." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([int]$DashboardStatus.commander_agent_loop.run_count -ge 1) -Message "Dashboard agent loop run count should be at least one." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([int]$DashboardStatus.commander_agent_loop.pending_approval_count -ge 0) -Message "Dashboard agent loop pending approval count missing." -Issues $Issues | Out-Null

$DashboardUpdate = & pwsh -NoProfile -File $DashboardUpdateScript -RootPath $Root -NoThrow 2>&1
if ($LASTEXITCODE -ne 0) {
    $Issues.Add("Dashboard update failed for the agent loop run.")
}

$DashboardPath = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\PDA Dashboard.md"
Assert-PDACondition -Condition (Test-Path -LiteralPath $DashboardPath -PathType Leaf) -Message "Dashboard markdown file missing." -Issues $Issues | Out-Null
if (Test-Path -LiteralPath $DashboardPath -PathType Leaf) {
    $DashboardText = Get-Content -LiteralPath $DashboardPath -Raw
    Assert-PDACondition -Condition ($DashboardText -match '(?m)^## Commander Agent Loop$') -Message "Dashboard markdown did not include the Commander Agent Loop section." -Issues $Issues | Out-Null
}

$ChatBridgeResult = & pwsh -NoProfile -File $ChatBridgeTestScript -AsJson -NoThrow -SkipDispatch -DashboardMode 2>&1
$ChatBridgeText = [string]($ChatBridgeResult -join "`n").Trim()
if (-not [string]::IsNullOrWhiteSpace($ChatBridgeText)) {
    $ChatBridgeReport = ConvertFrom-PDAMixedJson -Text $ChatBridgeText -SourceName $ChatBridgeTestScript
    Assert-PDACondition -Condition ([string]$ChatBridgeReport.status -eq "pass") -Message "Chat bridge regression test failed during agent loop validation." -Issues $Issues | Out-Null
}

$DecisionResult = Invoke-PDAJsonScript -Path $DecisionTestScript -Arguments @("-AsJson", "-NoThrow")
Assert-PDACondition -Condition ([string]$DecisionResult.status -eq "pass") -Message "Decision engine regression test failed during agent loop validation." -Issues $Issues | Out-Null

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    goal = $GoalText
    create = $CreateResult
    stored_run = $StoredRun
    approval = $ApprovedResult
    result = $ReviewedResult
    dashboard = $DashboardStatus
    issues = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 30
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA agent loop validation failed."
    }
    return
}

Write-Host "[*] PDA agent loop tests"
Write-Host ("Status     : {0}" -f $Report.status)
Write-Host ("Issues     : {0}" -f @($Report.issues).Count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA agent loop validation failed."
}
