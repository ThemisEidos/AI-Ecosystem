[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$StatusScript = Join-Path $PSScriptRoot "Get-COOPEROperationalStatus.ps1"
$NoteCreationScript = Join-Path $PSScriptRoot "Invoke-COOPERNoteCreationCommand.ps1"
$PrivateAnalysisScript = Join-Path $PSScriptRoot "Invoke-COOPERPrivateLocalAnalysis.ps1"

if (-not (Test-Path -LiteralPath $StatusScript -PathType Leaf)) {
    throw "WF-004 operational status helper is missing: $StatusScript"
}

$TempRoot = Join-Path $Root "tmp\cooper-operational-status-tests"
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$Issues = New-Object System.Collections.Generic.List[string]

if (Test-Path -LiteralPath $PrivateAnalysisScript -PathType Leaf) {
    $PrivateAnalysisResult = & $PrivateAnalysisScript -Text "Verify the private local analysis workflow and confirm the restricted DMZ boundary." -Approved -WorkshopMode "Private Workshop" -Root $Root
    if ([bool]$PrivateAnalysisResult.success -ne $true) {
        $Issues.Add("WF-007 private local analysis workflow did not succeed before status verification.")
    }
}
else {
    $Issues.Add("WF-007 private local analysis workflow script is missing.")
}

if (Test-Path -LiteralPath $NoteCreationScript -PathType Leaf) {
    $NoteCreationResult = & $NoteCreationScript -Text "Verify the WF-005 note creation status evidence and canonical operational reporting." -Approved -Root $Root
    if ([bool]$NoteCreationResult.success -ne $true) {
        $Issues.Add("WF-005 note creation workflow did not succeed before status verification.")
    }
}
else {
    $Issues.Add("WF-005 note creation workflow script is missing.")
}

$Success = & $StatusScript -Root $Root -WorkshopMode "Open Workshop"

if ([string]$Success.status -ne "pass") {
    $Issues.Add("Operational status helper did not pass on the current repository state.")
}
if ([bool]$Success.review_passed -ne $true) {
    $Issues.Add("Operational status helper did not mark the report as reviewed.")
}
foreach ($Field in @(
    "current_phase",
    "operational_workflows",
    "workflow_statuses",
    "operational_chains",
    "known_capabilities",
    "known_issues",
    "known_limitations",
    "approval_health",
    "recent_activity",
    "approval_or_pending_action_status",
    "recommended_next_action",
    "workflow_definitions",
    "project_memory",
    "skill_state",
    "last_successful_workflow",
    "last_failed_workflow",
    "response_text",
    "status_lines",
    "review_reason",
    "status_source"
)) {
    if ($Success.PSObject.Properties.Name -notcontains $Field) {
        $Issues.Add("Operational status helper is missing '$Field'.")
    }
}

if ([string]$Success.current_phase -notmatch '^Phase 6 - Private Workshop Hardening$') {
    $Issues.Add("Operational status helper did not report the current roadmap phase.")
}
if ([string]$Success.status -ne "pass") {
    $Issues.Add("WF-004 did not report pass after generating the operational status summary.")
}

$WorkflowIds = @($Success.operational_workflows | ForEach-Object { [string]$_.workflow_id })
foreach ($WorkflowId in @("WF-001", "WF-002", "WF-004", "WF-005", "WF-006", "WF-007")) {
    if ($WorkflowIds -notcontains $WorkflowId) {
        $Issues.Add("Operational workflow list is missing $WorkflowId.")
    }
}

$CanonicalChain = "WF-001 $([char]0x2192) WF-006"
$ChainStrings = @($Success.operational_chains | ForEach-Object { [string]$_ })
if ($ChainStrings.Count -ne 1 -or $ChainStrings[0] -ne $CanonicalChain) {
    $Issues.Add("Operational chains were not deduplicated to a single normalized $CanonicalChain entry.")
}

$DefinitionIds = @($Success.workflow_definitions | ForEach-Object { [string]$_.workflow_id })
if ($DefinitionIds -notcontains "WF-004") {
    $Issues.Add("Workflow definitions do not include WF-004.")
}
else {
    $WF004Definition = @($Success.workflow_definitions | Where-Object { [string]$_.workflow_id -eq "WF-004" } | Select-Object -First 1)
    if ($WF004Definition.Count -gt 0 -and [string]$WF004Definition[0].status -ne "operational") {
        $Issues.Add("WF-004 is not marked operational in the workflow definitions summary.")
    }
}

if ([string]$Success.response_text -notmatch '(?i)Current Phase:|Approval / Pending Action|Operational Workflow Status|Operational Workflows|Operational Chains|Known Capabilities|Known Issues|Recent Activity|Recommended Next Action') {
    $Issues.Add("Operational status response text is missing one or more expected sections.")
}
if ([string]$Success.response_text -notmatch '(?i)WF-002 Codex Task Generator \| status:|WF-004 Operational Status \| status:|WF-001 Research Summary \| status:|WF-005 Note Creation \| status:|WF-006 Knowledge Collection Import Draft \| status:') {
    $Issues.Add("Operational status response text is missing the workflow status summary.")
}
if ((@($Success.summary_lines | Where-Object { [string]$_ -like '- Recent decision:*' }) | Select-Object -Unique).Count -ne @($Success.summary_lines | Where-Object { [string]$_ -like '- Recent decision:*' }).Count) {
    $Issues.Add("Operational status response text repeated recent decision lines.")
}

if ($Success.workflow_statuses.Count -lt 5) {
    $Issues.Add("Operational status helper did not return per-workflow status entries.")
}
else {
    $WorkflowStatusMap = @{}
    foreach ($Entry in @($Success.workflow_statuses)) {
        $WorkflowStatusMap[[string]$Entry.workflow_id] = [string]$Entry.status
        if ([string]$Entry.status -notin @("pass", "fail", "unknown")) {
            $Issues.Add("Workflow $([string]$Entry.workflow_id) returned an invalid status '$([string]$Entry.status)'.")
        }
    }
    foreach ($WorkflowId in @("WF-001", "WF-002", "WF-004", "WF-005", "WF-006", "WF-007")) {
        if (-not $WorkflowStatusMap.ContainsKey($WorkflowId)) {
            $Issues.Add("Workflow status summary is missing $WorkflowId.")
        }
    }
    if ($WorkflowStatusMap["WF-001"] -ne "pass") {
        $Issues.Add("WF-001 did not report pass after a successful research workflow record was present.")
    }
    if ($WorkflowStatusMap["WF-005"] -ne "pass") {
        $Issues.Add("WF-005 did not report pass after a successful note creation workflow record was present.")
    }
    if ($WorkflowStatusMap["WF-004"] -ne "pass") {
        $Issues.Add("WF-004 did not report pass after the status report was generated.")
    }
    if ($WorkflowStatusMap["WF-007"] -ne "pass") {
        $Issues.Add("WF-007 did not report pass after the private local analysis workflow completed.")
    }
    $WF001Status = @($Success.workflow_statuses | Where-Object { [string]$_.workflow_id -eq "WF-001" } | Select-Object -First 1)
    if ($WF001Status.Count -eq 0 -or [string]$WF001Status[0].last_run_artifact_path -eq "") {
        $Issues.Add("WF-001 did not report a last run artifact path.")
    }
    $WF005Status = @($Success.workflow_statuses | Where-Object { [string]$_.workflow_id -eq "WF-005" } | Select-Object -First 1)
    if ($WF005Status.Count -eq 0 -or [string]$WF005Status[0].last_run_artifact_path -eq "") {
        $Issues.Add("WF-005 did not report a last run artifact path.")
    }
    $WF007Status = @($Success.workflow_statuses | Where-Object { [string]$_.workflow_id -eq "WF-007" } | Select-Object -First 1)
    if ($WF007Status.Count -eq 0 -or [string]$WF007Status[0].last_run_artifact_path -eq "") {
        $Issues.Add("WF-007 did not report a last run artifact path.")
    }
}

if ([string]$Success.approval_or_pending_action_status -notmatch '(?i)pending:\s*\d+\s*\|\s*completed:\s*\d+\s*\|\s*stale:\s*\d+\s*\|\s*blocked:\s*\d+') {
    $Issues.Add("Operational status helper did not categorize approval lifecycle counts.")
}
if (-not $Success.PSObject.Properties.Name.Contains("approval_health")) {
    $Issues.Add("Operational status helper did not expose approval_health.")
}
elseif ([string]$Success.approval_health.pending_approval -ne [string]$Success.approval_health.pending) {
    $Issues.Add("Operational status helper approval counts are inconsistent.")
}
elseif ([int]$Success.approval_health.completed -lt 1) {
    $Issues.Add("Operational status helper did not report any completed approvals.")
}

if ([string]$Success.status_source -match 'Get-COOPERRuntimeStatus\.ps1') {
    $Issues.Add("Operational status helper used the legacy runtime status helper as source of truth.")
}

$MissingWorkflowDefinitionsPath = Join-Path $TempRoot "missing-workflows.yaml"
$WorkflowFailure = & $StatusScript -Root $Root -WorkshopMode "Open Workshop" -WorkflowDefinitionsPath $MissingWorkflowDefinitionsPath
if ([string]$WorkflowFailure.status -ne "fail") {
    $Issues.Add("Operational status helper did not fail when workflow definitions were missing.")
}
if ([bool]$WorkflowFailure.review_passed -ne $false) {
    $Issues.Add("Operational status helper incorrectly passed with no workflow definitions.")
}
if ([string]$WorkflowFailure.review_reason -notmatch 'no workflow data found') {
    $Issues.Add("Missing workflow definitions did not produce the expected review reason.")
}

$PhaseRoadmapPath = Join-Path $TempRoot "missing-roadmap.md"
$PhaseMemoryPath = Join-Path $TempRoot "missing-memory.json"
@{} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $PhaseMemoryPath -Encoding UTF8
$PhaseFailure = & $StatusScript -Root $Root -WorkshopMode "Open Workshop" -RoadmapPath $PhaseRoadmapPath -ProjectMemoryPath $PhaseMemoryPath -WorkflowDefinitionsPath (Join-Path $Root "Config\workflows.yaml")
if ([string]$PhaseFailure.status -ne "fail") {
    $Issues.Add("Operational status helper did not fail when phase data was missing.")
}
if ([bool]$PhaseFailure.review_passed -ne $false) {
    $Issues.Add("Operational status helper incorrectly passed with no phase data.")
}
if ($PhaseFailure.review_reason -notmatch 'no phase data found') {
    $Issues.Add("Missing phase data did not produce the expected review reason.")
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    success = $Success
    workflow_failure = $WorkflowFailure
    phase_failure = $PhaseFailure
    issues = @($Issues)
}

Write-Host "[*] COOPER WF-004 operational status workflow"
Write-Host ("Status   : {0}" -f $Report.status)
Write-Host ("Phase    : {0}" -f $Success.current_phase)
Write-Host ("Workflows: {0}" -f (@($Success.operational_workflows | ForEach-Object { $_.workflow_id }) -join ", "))
Write-Host ("Chains   : {0}" -f (@($Success.operational_chains) -join ", "))

if ($Report.status -ne "pass") {
    foreach ($Issue in @($Report.issues)) {
        Write-Host ("[FAIL] {0}" -f $Issue)
    }
    exit 1
}

Write-Host "[PASS] WF-004 operational status summary validated."
exit 0
