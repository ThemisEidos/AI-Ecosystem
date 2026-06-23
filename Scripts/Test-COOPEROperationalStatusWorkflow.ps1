[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$StatusScript = Join-Path $PSScriptRoot "Get-COOPEROperationalStatus.ps1"
$WriterScript = Join-Path $PSScriptRoot "Write-COOPERWorkflowEvidence.ps1"
$TempRoot = Join-Path $Root "tmp\cooper-operational-status-tests"
$OpenArtifactRoot = Join-Path $TempRoot "open-artifacts"
$PrivateArtifactRoot = Join-Path $Root "Restricted DMZ Workspace\temp\cooper-operational-status-tests"

New-Item -ItemType Directory -Force -Path $TempRoot, $OpenArtifactRoot, $PrivateArtifactRoot | Out-Null

$Issues = New-Object System.Collections.Generic.List[string]
$CreatedPaths = New-Object System.Collections.Generic.List[string]

function Add-Issue {
    param([Parameter(Mandatory = $true)][string]$Message)
    $Issues.Add($Message) | Out-Null
}

function Remove-IfExists {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if (Test-Path -LiteralPath $Path) {
        try {
            Remove-Item -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue
        }
        catch {}
    }
}

function New-TestArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $false)][string]$Content = ""
    )

    $Parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null
    if ([string]::IsNullOrEmpty($Content)) {
        New-Item -ItemType File -Force -Path $Path | Out-Null
    }
    else {
        Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
    }

    [void]$CreatedPaths.Add($Path)
    return $Path
}

function Invoke-EvidenceWriter {
    param(
        [Parameter(Mandatory = $true)][string]$WorkshopId,
        [Parameter(Mandatory = $true)][string]$WorkflowId,
        [Parameter(Mandatory = $true)][string]$WorkflowName,
        [Parameter(Mandatory = $true)][string]$ExecutionId,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$CompletionTime,
        [Parameter(Mandatory = $true)][object[]]$ArtifactPaths,
        [Parameter(Mandatory = $true)][string]$Notes,
        [Parameter(Mandatory = $true)][string]$ReviewStatus,
        [Parameter(Mandatory = $false)][bool]$UserAccepted = $false
    )

    $WriterArgs = @{
        Root           = $Root
        RecordType     = "completion"
        WorkshopId     = $WorkshopId
        WorkshopName   = if ($WorkshopId -eq "private") { "Private Workshop" } else { "Open Workshop" }
        WorkflowId     = $WorkflowId
        WorkflowName   = $WorkflowName
        ExecutionId    = $ExecutionId
        Status         = $Status
        CompletionTime = $CompletionTime
        ArtifactPaths  = $ArtifactPaths
        ReviewStatus   = $ReviewStatus
        UserAccepted   = $UserAccepted
        Notes          = $Notes
    }

    return (& $WriterScript @WriterArgs)
}

try {
    if (-not (Test-Path -LiteralPath $StatusScript -PathType Leaf)) {
        throw "WF-004 operational status helper is missing: $StatusScript"
    }
    if (-not (Test-Path -LiteralPath $WriterScript -PathType Leaf)) {
        throw "WF-004 evidence writer helper is missing: $WriterScript"
    }

    $RunTag = [guid]::NewGuid().ToString("N").Substring(0, 8)

    $WF001OldArtifact = New-TestArtifact -Path (Join-Path $OpenArtifactRoot "wf-001-research-summary-old.md") -Content "# WF-001 older fixture"
    $WF001NewArtifact = New-TestArtifact -Path (Join-Path $OpenArtifactRoot "wf-001-research-summary-new.md") -Content "# WF-001 newer fixture"
    $WF002Artifact = New-TestArtifact -Path (Join-Path $OpenArtifactRoot "wf-002-task-package.md") -Content "# WF-002 fixture"
    $WF005Artifact = New-TestArtifact -Path (Join-Path $OpenArtifactRoot "wf-005-note.md") -Content "# WF-005 fixture"
    $WF006Artifact = New-TestArtifact -Path (Join-Path $OpenArtifactRoot "wf-006-import-draft.md") -Content "# WF-006 fixture"
    $PrivateArtifact = New-TestArtifact -Path (Join-Path $PrivateArtifactRoot "wf-007-private-analysis.md") -Content "# WF-007 private fixture"

    $WF001Old = Invoke-EvidenceWriter -WorkshopId "open" -WorkflowId "WF-001" -WorkflowName "Research Summary" -ExecutionId "20990101T090000Z-$RunTag-old" -Status "fail" -CompletionTime "2099-01-01T09:00:00Z" -ArtifactPaths @($WF001OldArtifact) -ReviewStatus "unknown" -UserAccepted $false -Notes "WF-001 older canonical evidence fixture."
    $WF001New = Invoke-EvidenceWriter -WorkshopId "open" -WorkflowId "WF-001" -WorkflowName "Research Summary" -ExecutionId "20990101T100000Z-$RunTag-new" -Status "pass" -CompletionTime "2099-01-01T10:00:00Z" -ArtifactPaths @($WF001NewArtifact) -ReviewStatus "unknown" -UserAccepted $false -Notes "WF-001 newer canonical evidence fixture."
    $WF002 = Invoke-EvidenceWriter -WorkshopId "open" -WorkflowId "WF-002" -WorkflowName "Codex Task Generator" -ExecutionId "20990101T110000Z-$RunTag" -Status "pass" -CompletionTime "2099-01-01T11:00:00Z" -ArtifactPaths @($WF002Artifact) -ReviewStatus "unknown" -UserAccepted $false -Notes "WF-002 canonical evidence fixture."
    $WF005 = Invoke-EvidenceWriter -WorkshopId "open" -WorkflowId "WF-005" -WorkflowName "Note Creation" -ExecutionId "20990101T120000Z-$RunTag" -Status "pass" -CompletionTime "2099-01-01T12:00:00Z" -ArtifactPaths @($WF005Artifact) -ReviewStatus "unknown" -UserAccepted $false -Notes "WF-005 canonical evidence fixture."
    $WF006 = Invoke-EvidenceWriter -WorkshopId "open" -WorkflowId "WF-006" -WorkflowName "Knowledge Collection Import Draft" -ExecutionId "20990101T130000Z-$RunTag" -Status "pass" -CompletionTime "2099-01-01T13:00:00Z" -ArtifactPaths @($WF006Artifact) -ReviewStatus "unknown" -UserAccepted $false -Notes "WF-006 canonical evidence fixture."
    $WF007 = Invoke-EvidenceWriter -WorkshopId "private" -WorkflowId "WF-007" -WorkflowName "Private Local Analysis" -ExecutionId "20990101T140000Z-$RunTag" -Status "pass" -CompletionTime "2099-01-01T14:00:00Z" -ArtifactPaths @($PrivateArtifact) -ReviewStatus "unknown" -UserAccepted $false -Notes "WF-007 canonical private evidence fixture."

    foreach ($Path in @(
        $WF001Old.path,
        $WF001New.path,
        $WF002.path,
        $WF005.path,
        $WF006.path,
        $WF007.path
    )) {
        [void]$CreatedPaths.Add($Path)
    }

    $MalformedEvidencePath = Join-Path (Join-Path $Root "State\Workflow_Evidence\completion") "workflow_completion_WF-006_20990101T150000Z-$RunTag-malformed.json"
    Set-Content -LiteralPath $MalformedEvidencePath -Value '{ "workflow_id": "WF-006",' -Encoding UTF8
    [void]$CreatedPaths.Add($MalformedEvidencePath)

    $Result = & $StatusScript -Root $Root -WorkshopMode "Open Workshop"

    if ([string]$Result.status -ne "pass") {
        Add-Issue "Operational status helper did not pass with canonical evidence fixtures."
    }
    if ([bool]$Result.review_passed -ne $true) {
        Add-Issue "Operational status helper did not mark the report as reviewed."
    }
    if ([string]$Result.current_phase -ne "Phase 7E - Roadmap / Current-State Reader") {
        Add-Issue "Operational status helper did not read the current Phase 7E roadmap entry."
    }
    if ($Result.PSObject.Properties.Name -notcontains "evidence_warnings") {
        Add-Issue "Operational status helper did not expose evidence warnings."
    }
    elseif (@($Result.evidence_warnings).Count -lt 1) {
        Add-Issue "Malformed evidence was not reported as a warning."
    }

    $WorkflowStatusMap = @{}
    foreach ($Entry in @($Result.workflow_statuses)) {
        $WorkflowStatusMap[[string]$Entry.workflow_id] = $Entry
        foreach ($Field in @("canonical_evidence_status", "canonical_evidence_path", "canonical_evidence_timestamp", "canonical_artifact_paths", "evidence_source")) {
            if ($Entry.PSObject.Properties.Name -notcontains $Field) {
                Add-Issue "Workflow $([string]$Entry.workflow_id) is missing canonical field '$Field'."
            }
        }
    }

    foreach ($WorkflowId in @("WF-001", "WF-002", "WF-004", "WF-005", "WF-006", "WF-007")) {
        if (-not $WorkflowStatusMap.ContainsKey($WorkflowId)) {
            Add-Issue "Workflow status summary is missing $WorkflowId."
        }
    }

    if ($WorkflowStatusMap["WF-001"].status -ne "pass") {
        Add-Issue "WF-001 did not resolve to the latest canonical pass record."
    }
    if ([string]$WorkflowStatusMap["WF-001"].canonical_evidence_path -ne [string]$WF001New.path) {
        Add-Issue "WF-001 canonical evidence path did not point to the latest record."
    }
    if (@($WorkflowStatusMap["WF-001"].canonical_artifact_paths).Count -eq 0 -or @($WorkflowStatusMap["WF-001"].canonical_artifact_paths)[0] -ne [string]$WF001NewArtifact) {
        Add-Issue "WF-001 canonical artifact path did not come from the latest evidence record."
    }

    foreach ($WorkflowId in @("WF-002", "WF-005", "WF-006")) {
        if ($WorkflowStatusMap[$WorkflowId].status -ne "pass") {
            Add-Issue "$WorkflowId did not resolve from canonical open evidence."
        }
        if ([string]$WorkflowStatusMap[$WorkflowId].canonical_evidence_path -notmatch '\\State\\Workflow_Evidence\\completion\\workflow_completion_') {
            Add-Issue "$WorkflowId did not report an open canonical evidence path."
        }
        if (@($WorkflowStatusMap[$WorkflowId].canonical_artifact_paths).Count -eq 0) {
            Add-Issue "$WorkflowId did not expose artifact paths from canonical evidence."
        }
    }

    if ($WorkflowStatusMap["WF-007"].status -ne "pass") {
        Add-Issue "WF-007 did not resolve from canonical private evidence."
    }
    if ([string]$WorkflowStatusMap["WF-007"].canonical_evidence_path -notmatch '\\Restricted DMZ Workspace\\State\\Workflow_Evidence\\completion\\workflow_completion_') {
        Add-Issue "WF-007 canonical evidence path is not inside Restricted DMZ Workspace."
    }
    if (@($WorkflowStatusMap["WF-007"].canonical_artifact_paths).Count -eq 0 -or @($WorkflowStatusMap["WF-007"].canonical_artifact_paths)[0] -ne [string]$PrivateArtifact) {
        Add-Issue "WF-007 canonical artifact path did not remain private."
    }

    $OpenCounterpartPath = Join-Path (Join-Path $Root "State\Workflow_Evidence\completion") (Split-Path -Leaf $WF007.path)
    if (Test-Path -LiteralPath $OpenCounterpartPath) {
        Add-Issue "WF-007 private evidence was also written to the open completion folder."
    }

    if ($WorkflowStatusMap["WF-004"].status -ne "pass") {
        Add-Issue "WF-004 did not fall back to legacy status behavior when no canonical evidence existed."
    }
    if ([string]$WorkflowStatusMap["WF-004"].canonical_evidence_path -ne "") {
        Add-Issue "WF-004 should not report canonical evidence when no completion record exists."
    }
    if ([string]$WorkflowStatusMap["WF-004"].evidence_source -ne "legacy") {
        Add-Issue "WF-004 did not identify legacy fallback behavior."
    }

    if ($Result.response_text -notmatch 'Current Phase: Phase 7E - Roadmap / Current-State Reader') {
        Add-Issue "Operational status response text did not include the Phase 7E roadmap entry."
    }
    if ($Result.response_text -notmatch 'WF-001 Research Summary \| status: pass') {
        Add-Issue "Operational status response text did not include the canonical WF-001 status."
    }
    if ($Result.response_text -notmatch 'WF-007 Private Local Analysis \| status: pass') {
        Add-Issue "Operational status response text did not include the canonical WF-007 status."
    }

    $Report = [pscustomobject]@{
        status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
        result = $Result
        issues = @($Issues)
    }

    Write-Host "[*] COOPER WF-004 operational status workflow"
    Write-Host ("Status   : {0}" -f $Report.status)
    Write-Host ("Phase    : {0}" -f $Result.current_phase)
    Write-Host ("Workflows: {0}" -f (@($Result.workflow_statuses | ForEach-Object { $_.workflow_id }) -join ", "))
    Write-Host ("Warnings : {0}" -f (@($Result.evidence_warnings) -join " | "))

    if ($Report.status -ne "pass") {
        foreach ($Issue in @($Report.issues)) {
            Write-Host ("[FAIL] {0}" -f $Issue)
        }
        exit 1
    }

    Write-Host "[PASS] WF-004 operational status summary validated."
    exit 0
}
finally {
    foreach ($Path in @($CreatedPaths)) {
        Remove-IfExists -Path $Path
    }

    foreach ($Path in @(
        $PrivateArtifactRoot,
        $OpenArtifactRoot,
        $TempRoot
    )) {
        if (Test-Path -LiteralPath $Path) {
            try {
                Remove-Item -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue
            }
            catch {}
        }
    }
}
