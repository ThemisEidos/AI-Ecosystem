[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$StandardPath = Join-Path $Root "Docs\Workflow_Evidence_Standard.md"
$CatalogPath = Join-Path $Root "06_Automation & Workflow Catalog.md"
$FixtureRoot = Join-Path $Root "Tests\Fixtures\Workflow_Evidence"
$InvalidRoot = Join-Path $FixtureRoot "Invalid"

$CompletionFixturePath = Join-Path $FixtureRoot "workflow_completion_WF-002_20260622T000000Z-test.json"
$ApprovalFixturePath = Join-Path $FixtureRoot "approval_lifecycle_AP-20260622-000001.json"

$MissingApprovalCompletionPath = Join-Path $InvalidRoot "workflow_completion_WF-002_20260622T000100Z-missing-approval.json"
$MismatchedWorkflowCompletionPath = Join-Path $InvalidRoot "workflow_completion_WF-002_20260622T000200Z-mismatched-workflow.json"
$MismatchedApprovalPath = Join-Path $InvalidRoot "approval_lifecycle_AP-20260622-000002-mismatched-workflow.json"
$MismatchedApprovalIdCompletionPath = Join-Path $InvalidRoot "workflow_completion_WF-002_20260622T000250Z-mismatched-approval-id.json"
$MismatchedApprovalIdPath = Join-Path $InvalidRoot "approval_lifecycle_AP-20260622-000005-mismatched-approval-id.json"
$IncompatibleStatusCompletionPath = Join-Path $InvalidRoot "workflow_completion_WF-002_20260622T000300Z-incompatible-status.json"
$IncompatibleStatusApprovalPath = Join-Path $InvalidRoot "approval_lifecycle_AP-20260622-000003-incompatible-status.json"

$Issues = New-Object System.Collections.Generic.List[string]

function Add-Issue {
    param([Parameter(Mandatory = $true)][string]$Message)

    [void]$Issues.Add($Message)
}

function Read-JsonFixture {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $Raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        return [pscustomobject]@{
            raw = $Raw
            record = ($Raw | ConvertFrom-Json -ErrorAction Stop)
            path = $Path
        }
    }
    catch {
        Add-Issue "Invalid JSON fixture: $Path"
        return $null
    }
}

function Test-IsCompletionPassCompatible {
    param(
        [Parameter(Mandatory = $true)][string]$WorkflowStatus,
        [Parameter(Mandatory = $true)][string]$ApprovalStatus
    )

    switch ($WorkflowStatus) {
        "pass" { return $ApprovalStatus -eq "completed" }
        "blocked" { return $ApprovalStatus -in @("blocked", "stale") }
        "fail" { return $ApprovalStatus -in @("completed", "blocked", "rejected") }
        "unknown" { return $false }
        default { return $false }
    }
}

function Get-ApprovalLinkIssues {
    param(
        [Parameter(Mandatory = $true)]$CompletionRecord,
        [Parameter(Mandatory = $false)]$ApprovalRecord = $null,
        [Parameter(Mandatory = $true)][string]$CompletionPath,
        [Parameter(Mandatory = $false)][string]$ApprovalPath = ""
    )

    $Issues = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace([string]$CompletionRecord.approval_id)) {
        if ($null -ne $ApprovalRecord) {
            [void]$Issues.Add("Completion record unexpectedly lacks approval_id for linked fixture: $CompletionPath")
        }
        return @($Issues)
    }

    if ($null -eq $ApprovalRecord) {
        [void]$Issues.Add("Missing approval lifecycle record for completion record: $CompletionPath")
        return @($Issues)
    }

    if ([string]$CompletionRecord.approval_id -ne [string]$ApprovalRecord.approval_id) {
        [void]$Issues.Add("approval_id mismatch between completion and approval records: $CompletionPath vs $ApprovalPath")
    }
    if ([string]$CompletionRecord.workflow_id -ne [string]$ApprovalRecord.workflow_id) {
        [void]$Issues.Add("workflow_id mismatch between completion and approval records: $CompletionPath vs $ApprovalPath")
    }
    if (-not (Test-IsCompletionPassCompatible -WorkflowStatus ([string]$CompletionRecord.status) -ApprovalStatus ([string]$ApprovalRecord.status))) {
        [void]$Issues.Add("Incompatible workflow/approval status pairing: workflow=$([string]$CompletionRecord.status) approval=$([string]$ApprovalRecord.status)")
    }

    return @($Issues)
}

function Assert-FailingLinkCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$CompletionRecord,
        [Parameter(Mandatory = $false)]$ApprovalRecord = $null,
        [Parameter(Mandatory = $true)][string]$CompletionPath,
        [Parameter(Mandatory = $false)][string]$ApprovalPath = ""
    )

    $Issues = Get-ApprovalLinkIssues -CompletionRecord $CompletionRecord -ApprovalRecord $ApprovalRecord -CompletionPath $CompletionPath -ApprovalPath $ApprovalPath
    if ($Issues.Count -eq 0) {
        Add-Issue "$Name should fail link validation."
    }
}

function Test-MissingApprovalCase {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$MissingApprovalId
    )

    $Record = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ([string]$Record.approval_id -ne $MissingApprovalId) {
        Add-Issue "Missing-approval fixture does not reference the expected approval id: $Path"
    }
    if (Test-Path -LiteralPath (Join-Path $FixtureRoot "approval_lifecycle_$MissingApprovalId.json") -PathType Leaf) {
        Add-Issue "Missing-approval fixture unexpectedly has a matching approval record on disk: $Path"
    }
}

if (-not (Test-Path -LiteralPath $StandardPath -PathType Leaf)) {
    throw "Workflow evidence standard is missing: $StandardPath"
}
if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
    throw "Workflow catalog is missing: $CatalogPath"
}
if (-not (Test-Path -LiteralPath $FixtureRoot -PathType Container)) {
    throw "Workflow evidence fixture folder is missing: $FixtureRoot"
}

$CatalogText = Get-Content -LiteralPath $CatalogPath -Raw -ErrorAction Stop
if ($CatalogText -notmatch '(?s)## WF-002 Codex Task Generator.*?Approval Requirement: required') {
    Add-Issue "WF-002 approval requirement is not documented in the catalog."
}

$CompletionBundle = Read-JsonFixture -Path $CompletionFixturePath
$ApprovalBundle = Read-JsonFixture -Path $ApprovalFixturePath

if ($CompletionBundle -and $ApprovalBundle) {
    $PositiveLinkIssues = Get-ApprovalLinkIssues -CompletionRecord $CompletionBundle.record -ApprovalRecord $ApprovalBundle.record -CompletionPath $CompletionFixturePath -ApprovalPath $ApprovalFixturePath
    if ($PositiveLinkIssues.Count -gt 0) {
        foreach ($Issue in $PositiveLinkIssues) {
            Add-Issue $Issue
        }
    }
}

foreach ($Path in @(
    $MissingApprovalCompletionPath,
    $MismatchedWorkflowCompletionPath,
    $MismatchedApprovalPath,
    $MismatchedApprovalIdCompletionPath,
    $MismatchedApprovalIdPath,
    $IncompatibleStatusCompletionPath,
    $IncompatibleStatusApprovalPath
)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Issue "Missing invalid workflow evidence fixture: $Path"
    }
}

if (Test-Path -LiteralPath $MissingApprovalCompletionPath -PathType Leaf) {
    Test-MissingApprovalCase -Path $MissingApprovalCompletionPath -MissingApprovalId "AP-20260622-999999"
}

if ((Test-Path -LiteralPath $MismatchedWorkflowCompletionPath -PathType Leaf) -and (Test-Path -LiteralPath $MismatchedApprovalPath -PathType Leaf)) {
    $MismatchedCompletion = Get-Content -LiteralPath $MismatchedWorkflowCompletionPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $MismatchedApproval = Get-Content -LiteralPath $MismatchedApprovalPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    Assert-FailingLinkCase -Name "workflow_id mismatch pair" -CompletionRecord $MismatchedCompletion -ApprovalRecord $MismatchedApproval -CompletionPath $MismatchedWorkflowCompletionPath -ApprovalPath $MismatchedApprovalPath
}

if ((Test-Path -LiteralPath $MismatchedApprovalIdCompletionPath -PathType Leaf) -and (Test-Path -LiteralPath $MismatchedApprovalIdPath -PathType Leaf)) {
    $MismatchedApprovalIdCompletion = Get-Content -LiteralPath $MismatchedApprovalIdCompletionPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $MismatchedApprovalIdApproval = Get-Content -LiteralPath $MismatchedApprovalIdPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    Assert-FailingLinkCase -Name "approval_id mismatch pair" -CompletionRecord $MismatchedApprovalIdCompletion -ApprovalRecord $MismatchedApprovalIdApproval -CompletionPath $MismatchedApprovalIdCompletionPath -ApprovalPath $MismatchedApprovalIdPath
}

if ((Test-Path -LiteralPath $IncompatibleStatusCompletionPath -PathType Leaf) -and (Test-Path -LiteralPath $IncompatibleStatusApprovalPath -PathType Leaf)) {
    $IncompatibleCompletion = Get-Content -LiteralPath $IncompatibleStatusCompletionPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $IncompatibleApproval = Get-Content -LiteralPath $IncompatibleStatusApprovalPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    Assert-FailingLinkCase -Name "incompatible status pair" -CompletionRecord $IncompatibleCompletion -ApprovalRecord $IncompatibleApproval -CompletionPath $IncompatibleStatusCompletionPath -ApprovalPath $IncompatibleStatusApprovalPath
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    issues = @($Issues)
    source_of_truth = "Docs/Workflow_Evidence_Standard.md"
}

Write-Host "[*] COOPER workflow evidence link validation"
Write-Host ("Status   : {0}" -f $Report.status)
Write-Host ("Fixtures : {0}" -f 5)

if ($Report.status -ne "pass") {
    foreach ($Issue in @($Report.issues)) {
        Write-Host ("[FAIL] {0}" -f $Issue)
    }
    exit 1
}

Write-Host "[PASS] Workflow evidence links validated."
exit 0
