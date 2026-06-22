[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$StandardPath = Join-Path $Root "Docs\Workflow_Evidence_Standard.md"
$FixtureRoot = Join-Path $Root "Tests\Fixtures\Workflow_Evidence"
$CompletionFixturePath = Join-Path $FixtureRoot "workflow_completion_WF-002_20260622T000000Z-test.json"
$ApprovalFixturePath = Join-Path $FixtureRoot "approval_lifecycle_AP-20260622-000001.json"

$Issues = New-Object System.Collections.Generic.List[string]

function Add-Issue {
    param([Parameter(Mandatory = $true)][string]$Message)

    [void]$Issues.Add($Message)
}

function Test-Iso8601Utc {
    param([Parameter(Mandatory = $true)]$Value)

    return ([string]$Value) -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$'
}

function Get-JsonRecord {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Add-Issue "File is not valid JSON: $Path"
        return $null
    }
}

function Assert-RequiredFields {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][string[]]$RequiredFields,
        [Parameter(Mandatory = $true)][string]$Path
    )

    foreach ($Field in $RequiredFields) {
        if ($Record.PSObject.Properties.Name -notcontains $Field) {
            Add-Issue "Missing required field '$Field': $Path"
        }
    }
}

function Assert-NoPlaceholderSecrets {
    param(
        [Parameter(Mandatory = $true)][string]$RawText,
        [Parameter(Mandatory = $true)][string]$Path
    )

    foreach ($SecretNeedle in @("api_key", "password", "secret", "token", "private_key")) {
        if ($RawText -match "(?i)\b$([regex]::Escape($SecretNeedle))\b") {
            Add-Issue "Fixture contains placeholder secret marker '$SecretNeedle': $Path"
        }
    }
}

function Assert-JsonUtcField {
    param(
        [Parameter(Mandatory = $true)][string]$RawText,
        [Parameter(Mandatory = $true)][string]$FieldName,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $Pattern = '(?ms)"' + [regex]::Escape($FieldName) + '"\s*:\s*"(?<value>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)"'
    if ($RawText -notmatch $Pattern) {
        Add-Issue "$FieldName must be an ISO 8601 UTC string ending in Z: $Path"
    }
}

if (-not (Test-Path -LiteralPath $StandardPath -PathType Leaf)) {
    throw "Workflow evidence standard is missing: $StandardPath"
}

if (-not (Test-Path -LiteralPath $FixtureRoot -PathType Container)) {
    throw "Workflow evidence fixture folder is missing: $FixtureRoot"
}

foreach ($Path in @($CompletionFixturePath, $ApprovalFixturePath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Issue "Missing workflow evidence fixture: $Path"
    }
}

$CompletionRaw = if (Test-Path -LiteralPath $CompletionFixturePath -PathType Leaf) {
    Get-Content -LiteralPath $CompletionFixturePath -Raw -ErrorAction Stop
}
else {
    ""
}
$ApprovalRaw = if (Test-Path -LiteralPath $ApprovalFixturePath -PathType Leaf) {
    Get-Content -LiteralPath $ApprovalFixturePath -Raw -ErrorAction Stop
}
else {
    ""
}

Assert-NoPlaceholderSecrets -RawText $CompletionRaw -Path $CompletionFixturePath
Assert-NoPlaceholderSecrets -RawText $ApprovalRaw -Path $ApprovalFixturePath

$CompletionRecord = if ($CompletionRaw) { $CompletionRaw | ConvertFrom-Json -ErrorAction Stop } else { $null }
$ApprovalRecord = if ($ApprovalRaw) { $ApprovalRaw | ConvertFrom-Json -ErrorAction Stop } else { $null }

if ($null -ne $CompletionRecord) {
    if ($CompletionRecord -is [array]) {
        Add-Issue "Completion fixture must contain a single JSON object: $CompletionFixturePath"
    }
    else {
        Assert-RequiredFields -Record $CompletionRecord -RequiredFields @(
            "workflow_id",
            "workflow_name",
            "execution_id",
            "status",
            "completion_time",
            "workshop_id",
            "workshop_name",
            "approval_id",
            "artifact_paths",
            "review_status",
            "user_accepted",
            "notes"
        ) -Path $CompletionFixturePath

        if ($CompletionFixturePath -notmatch '^.*workflow_completion_(?<workflow_id>WF-\d+)_(?<execution_id>[^.]+)\.json$') {
            Add-Issue "Completion fixture filename does not match the canonical pattern: $CompletionFixturePath"
        }
        elseif ([string]$CompletionRecord.workflow_id -ne $Matches.workflow_id) {
            Add-Issue "Completion fixture workflow_id does not match the filename: $CompletionFixturePath"
        }
        elseif ([string]$CompletionRecord.execution_id -ne $Matches.execution_id) {
            Add-Issue "Completion fixture execution_id does not match the filename: $CompletionFixturePath"
        }

        if ([string]$CompletionRecord.workflow_id -notmatch '^WF-\d+$') {
            Add-Issue "Completion fixture workflow_id is invalid: $CompletionFixturePath"
        }
        if ([string]$CompletionRecord.status -notin @("pass", "fail", "blocked", "unknown")) {
            Add-Issue "Completion fixture status is invalid: $CompletionFixturePath"
        }
        if ([string]$CompletionRecord.review_status -notin @("pass", "fail", "blocked", "unknown")) {
            Add-Issue "Completion fixture review_status is invalid: $CompletionFixturePath"
        }
        Assert-JsonUtcField -RawText $CompletionRaw -FieldName "completion_time" -Path $CompletionFixturePath
        if ($null -eq $CompletionRecord.artifact_paths -or $CompletionRecord.artifact_paths -isnot [array]) {
            Add-Issue "Completion fixture artifact_paths must be an array: $CompletionFixturePath"
        }
        if ($null -eq $CompletionRecord.user_accepted -or $CompletionRecord.user_accepted.GetType().FullName -ne "System.Boolean") {
            Add-Issue "Completion fixture user_accepted must be boolean: $CompletionFixturePath"
        }
        foreach ($ArtifactPath in @($CompletionRecord.artifact_paths)) {
            if ([string]$ArtifactPath -match '(?i)Restricted DMZ Workspace') {
                Add-Issue "Open Workshop sample artifact path must not point into Restricted DMZ Workspace: $CompletionFixturePath"
            }
        }
    }
}

if ($null -ne $ApprovalRecord) {
    if ($ApprovalRecord -is [array]) {
        Add-Issue "Approval fixture must contain a single JSON object: $ApprovalFixturePath"
    }
    else {
        Assert-RequiredFields -Record $ApprovalRecord -RequiredFields @(
            "approval_id",
            "workflow_id",
            "status",
            "requested_time",
            "approved_time",
            "completed_time",
            "blocked_time",
            "stale_time",
            "expiration_time",
            "reason",
            "notes"
        ) -Path $ApprovalFixturePath

        if ($ApprovalFixturePath -notmatch '^.*approval_lifecycle_(?<approval_id>[^.]+)\.json$') {
            Add-Issue "Approval fixture filename does not match the canonical pattern: $ApprovalFixturePath"
        }
        elseif ([string]$ApprovalRecord.approval_id -ne $Matches.approval_id) {
            Add-Issue "Approval fixture approval_id does not match the filename: $ApprovalFixturePath"
        }

        if ([string]$ApprovalRecord.workflow_id -notmatch '^WF-\d+$') {
            Add-Issue "Approval fixture workflow_id is invalid: $ApprovalFixturePath"
        }
        if ([string]$ApprovalRecord.status -notin @("pending", "approved", "completed", "stale", "blocked", "rejected")) {
            Add-Issue "Approval fixture status is invalid: $ApprovalFixturePath"
        }
        foreach ($Field in @("requested_time", "approved_time", "completed_time", "blocked_time", "stale_time", "expiration_time")) {
            Assert-JsonUtcField -RawText $ApprovalRaw -FieldName $Field -Path $ApprovalFixturePath
        }
    }
}

$StandardText = Get-Content -LiteralPath $StandardPath -Raw -ErrorAction Stop
foreach ($Needle in @(
    "State/Workflow_Evidence/completion/",
    "State/Workflow_Evidence/approval/",
    "State/Workflow_Evidence/archive/",
    "Restricted DMZ Workspace/State/Workflow_Evidence/completion/",
    "Restricted DMZ Workspace/State/Workflow_Evidence/approval/",
    "Restricted DMZ Workspace/State/Workflow_Evidence/archive/",
    "workflow_completion_<workflow_id>_<execution_id>.json",
    "approval_lifecycle_<approval_id>.json"
)) {
    if ($StandardText -notmatch [regex]::Escape($Needle)) {
        Add-Issue "Workflow evidence standard is missing '$Needle'."
    }
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    issues = @($Issues)
    fixtures = @(
        $CompletionFixturePath,
        $ApprovalFixturePath
    )
    source_of_truth = "Docs/Workflow_Evidence_Standard.md"
}

Write-Host "[*] COOPER workflow evidence schema validation"
Write-Host ("Status   : {0}" -f $Report.status)
Write-Host ("Fixtures : {0}" -f (@($Report.fixtures) -join ", "))

if ($Report.status -ne "pass") {
    foreach ($Issue in @($Report.issues)) {
        Write-Host ("[FAIL] {0}" -f $Issue)
    }
    exit 1
}

Write-Host "[PASS] Workflow evidence schemas validated."
exit 0
