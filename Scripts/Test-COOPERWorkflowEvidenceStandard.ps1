[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$StandardPath = Join-Path $Root "Docs\Workflow_Evidence_Standard.md"
$RoadmapPath = Join-Path $Root "07_Implementation Roadmap.md"
$CatalogPath = Join-Path $Root "06_Automation & Workflow Catalog.md"
$PolicyPath = Join-Path $Root "04_Security & Compartmentalization Policy.md"
$SpecificationPath = Join-Path $Root "02_COOPER System Specification.md"

$Issues = New-Object System.Collections.Generic.List[string]

function Add-Issue {
    param([Parameter(Mandatory = $true)][string]$Message)

    [void]$Issues.Add($Message)
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Text -notmatch [regex]::Escape($Needle)) {
        Add-Issue $Message
    }
}

function Assert-Regex {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Text -notmatch $Pattern) {
        Add-Issue $Message
    }
}

function Test-Iso8601Utc {
    param([Parameter(Mandatory = $true)]$Value)

    if ($null -eq $Value) {
        return $false
    }

    $Text = [string]$Value
    return $Text -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$'
}

function Get-CanonicalEvidenceFiles {
    param(
        [Parameter(Mandatory = $true)][string[]]$Roots
    )

    foreach ($EvidenceRoot in $Roots) {
        if (Test-Path -LiteralPath $EvidenceRoot -PathType Container) {
            Get-ChildItem -LiteralPath $EvidenceRoot -Recurse -File -ErrorAction SilentlyContinue
        }
    }
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $BaseFull = [System.IO.Path]::GetFullPath($BasePath.TrimEnd('\') + '\')
    $TargetFull = [System.IO.Path]::GetFullPath($TargetPath)
    if ($TargetFull.StartsWith($BaseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $TargetFull.Substring($BaseFull.Length)
    }

    return $TargetFull
}

function Validate-CompletionRecord {
    param(
        [Parameter(Mandatory = $true)]$File,
        [Parameter(Mandatory = $true)][string]$WorkshopId,
        [Parameter(Mandatory = $true)][string]$WorkshopName,
        [Parameter(Mandatory = $true)][string]$EvidenceRoot
    )

    $ExpectedPrefix = "workflow_completion_"
    if ($File.Name -notmatch '^workflow_completion_(?<workflow_id>WF-\d+)_(?<execution_id>[^.]+)\.json$') {
        Add-Issue "Completion record filename does not match the canonical pattern: $($File.FullName)"
        return
    }

    try {
        $Record = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Add-Issue "Completion record is not valid JSON: $($File.FullName)"
        return
    }

    if ($Record -is [array]) {
        Add-Issue "Completion record must be a single JSON object per file: $($File.FullName)"
        return
    }

    $RequiredFields = @(
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
    )

    foreach ($Field in $RequiredFields) {
        if ($Record.PSObject.Properties.Name -notcontains $Field) {
            Add-Issue "Completion record is missing required field '$Field': $($File.FullName)"
        }
    }

    if ([string]$Record.workflow_id -ne [string]$Matches.workflow_id) {
        Add-Issue "Completion record workflow_id does not match the filename: $($File.FullName)"
    }
    if ([string]$Record.execution_id -ne [string]$Matches.execution_id) {
        Add-Issue "Completion record execution_id does not match the filename: $($File.FullName)"
    }
    if ([string]$Record.workshop_id -ne $WorkshopId) {
        Add-Issue "Completion record workshop_id does not match its evidence path: $($File.FullName)"
    }
    if ([string]$Record.workshop_name -ne $WorkshopName) {
        Add-Issue "Completion record workshop_name does not match the expected workshop: $($File.FullName)"
    }
    if ([string]$Record.status -notin @("pass", "fail", "blocked", "unknown")) {
        Add-Issue "Completion record status is invalid: $($File.FullName)"
    }
    if ([string]$Record.review_status -notin @("pass", "fail", "blocked", "unknown")) {
        Add-Issue "Completion record review_status is invalid: $($File.FullName)"
    }
    if (-not (Test-Iso8601Utc -Value $Record.completion_time)) {
        Add-Issue "Completion record completion_time is not ISO 8601 UTC: $($File.FullName)"
    }
    if ($null -eq $Record.user_accepted -or ($Record.user_accepted.GetType().FullName -ne "System.Boolean")) {
        Add-Issue "Completion record user_accepted must be boolean: $($File.FullName)"
    }
    if ($Record.artifact_paths -is [string] -or $null -eq $Record.artifact_paths) {
        Add-Issue "Completion record artifact_paths must be a JSON array: $($File.FullName)"
    }
    foreach ($PropertyName in @($Record.PSObject.Properties.Name)) {
        if ([string]$PropertyName -match '[A-Z]') {
            Add-Issue "Completion record field names must remain snake_case: $($File.FullName)"
            break
        }
    }

    $EvidencePrefix = [System.IO.Path]::GetFullPath($EvidenceRoot.TrimEnd('\') + '\')
    $RecordPath = [System.IO.Path]::GetFullPath($File.FullName)
    if (-not $RecordPath.StartsWith($EvidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Issue "Completion record is not stored under the expected evidence root: $($File.FullName)"
    }
}

function Validate-ApprovalRecord {
    param(
        [Parameter(Mandatory = $true)]$File,
        [Parameter(Mandatory = $true)][string]$WorkshopId,
        [Parameter(Mandatory = $true)][string]$WorkshopName,
        [Parameter(Mandatory = $true)][string]$EvidenceRoot
    )

    if ($File.Name -notmatch '^approval_lifecycle_(?<approval_id>[^.]+)\.json$') {
        Add-Issue "Approval record filename does not match the canonical pattern: $($File.FullName)"
        return
    }

    try {
        $Record = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Add-Issue "Approval record is not valid JSON: $($File.FullName)"
        return
    }

    if ($Record -is [array]) {
        Add-Issue "Approval record must be a single JSON object per file: $($File.FullName)"
        return
    }

    $RequiredFields = @(
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
    )

    foreach ($Field in $RequiredFields) {
        if ($Record.PSObject.Properties.Name -notcontains $Field) {
            Add-Issue "Approval record is missing required field '$Field': $($File.FullName)"
        }
    }

    if ([string]$Record.approval_id -ne [string]$Matches.approval_id) {
        Add-Issue "Approval record approval_id does not match the filename: $($File.FullName)"
    }
    if ([string]$Record.status -notin @("pending", "approved", "completed", "stale", "blocked", "rejected")) {
        Add-Issue "Approval record status is invalid: $($File.FullName)"
    }
    foreach ($Field in @("requested_time", "approved_time", "completed_time", "blocked_time", "stale_time", "expiration_time")) {
        if ($Record.PSObject.Properties.Name -contains $Field) {
            $Value = $Record.$Field
            if ($null -ne $Value -and -not (Test-Iso8601Utc -Value $Value)) {
                Add-Issue "Approval record $Field is not ISO 8601 UTC when present: $($File.FullName)"
            }
        }
    }
    foreach ($PropertyName in @($Record.PSObject.Properties.Name)) {
        if ([string]$PropertyName -match '[A-Z]') {
            Add-Issue "Approval record field names must remain snake_case: $($File.FullName)"
            break
        }
    }
    if ([string]$Record.workshop_id -and [string]$Record.workshop_id -ne $WorkshopId) {
        Add-Issue "Approval record workshop_id does not match its evidence path: $($File.FullName)"
    }
    if ([string]$Record.workshop_name -and [string]$Record.workshop_name -ne $WorkshopName) {
        Add-Issue "Approval record workshop_name does not match the expected workshop: $($File.FullName)"
    }

    $EvidencePrefix = [System.IO.Path]::GetFullPath($EvidenceRoot.TrimEnd('\') + '\')
    $RecordPath = [System.IO.Path]::GetFullPath($File.FullName)
    if (-not $RecordPath.StartsWith($EvidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Issue "Approval record is not stored under the expected evidence root: $($File.FullName)"
    }
}

if (-not (Test-Path -LiteralPath $StandardPath -PathType Leaf)) {
    throw "Workflow evidence standard is missing: $StandardPath"
}

$StandardText = Get-Content -LiteralPath $StandardPath -Raw -ErrorAction Stop
$RoadmapText = Get-Content -LiteralPath $RoadmapPath -Raw -ErrorAction Stop
$CatalogText = Get-Content -LiteralPath $CatalogPath -Raw -ErrorAction Stop
$PolicyText = Get-Content -LiteralPath $PolicyPath -Raw -ErrorAction Stop
$SpecificationText = Get-Content -LiteralPath $SpecificationPath -Raw -ErrorAction Stop
$GovernanceText = @($StandardText, $RoadmapText, $CatalogText, $PolicyText, $SpecificationText) -join "`n`n"

Assert-Contains $StandardText "It is a file-based standard only." "Workflow evidence standard must remain file-based only."
Assert-Contains $StandardText 'Canonical machine-readable format: `JSON`' "Workflow completion records must be declared as canonical JSON."
Assert-Contains $StandardText "Each record must be a single JSON object per file" "Canonical records must be single JSON objects."

foreach ($PathNeedle in @(
    "State/Workflow_Evidence/completion/",
    "State/Workflow_Evidence/approval/",
    "State/Workflow_Evidence/archive/",
    "Restricted DMZ Workspace/State/Workflow_Evidence/completion/",
    "Restricted DMZ Workspace/State/Workflow_Evidence/approval/",
    "Restricted DMZ Workspace/State/Workflow_Evidence/archive/"
)) {
    Assert-Contains $StandardText $PathNeedle "Workflow evidence standard is missing path definition: $PathNeedle"
}

foreach ($FilenameNeedle in @(
    "workflow_completion_<workflow_id>_<execution_id>.json",
    "approval_lifecycle_<approval_id>.json"
)) {
    Assert-Contains $StandardText $FilenameNeedle "Workflow evidence standard is missing filename pattern: $FilenameNeedle"
}

Assert-Contains $StandardText "ISO 8601 UTC" "Workflow evidence standard must require ISO 8601 UTC timestamps."
Assert-Regex $StandardText '(?s)### Workflow Status Values.*?pass.*?fail.*?blocked.*?unknown' "Workflow status values are not defined in the canonical section."
Assert-Regex $StandardText '(?s)### Approval Status Values.*?pending.*?approved.*?completed.*?stale.*?blocked.*?rejected' "Approval status values are not defined in the canonical section."

Assert-Contains $StandardText "WF-004 should eventually use canonical workflow completion records and approval lifecycle records as the primary source of truth." "WF-004 consumption rules are missing."
Assert-Contains $StandardText "evidence conflict" "Evidence conflict behavior is missing."
Assert-Contains $StandardText "approval/evidence mismatch" "Approval/evidence mismatch behavior is missing."
Assert-Contains $StandardText "retention and archival rules" "Retention/archive rules are not documented."
Assert-Contains $StandardText "Open Workshop and Private Workshop evidence remain separated" "Open/Private evidence separation is missing."

Assert-Contains $StandardText "It does not introduce a database." "The standard must explicitly reject databases."
Assert-Contains $StandardText "It does not introduce an event bus." "The standard must explicitly reject event buses."
Assert-Contains $StandardText "It does not introduce agents or new orchestration." "The standard must explicitly reject agents and orchestration."
Assert-Contains $RoadmapText "no database, queue, event bus, or orchestration system is introduced" "The roadmap must reject queues and orchestration systems for Phase 7A."
Assert-Contains $RoadmapText "no database, event bus, agent framework, or orchestration layer introduced" "The roadmap must reject databases, event buses, agents, and orchestration layers for Phase 7A."
Assert-Contains $SpecificationText "Folder-based state is preferred over introducing databases, queues, event buses, or orchestration layers" "The system specification must reject queues and orchestration layers."

Assert-Contains $CatalogText "WF-004 should eventually treat canonical workflow evidence records as the primary source of truth" "WF-004 should reference the evidence standard in the catalog."
Assert-Contains $CatalogText "Private Workshop local-only execution" "WF-007 private evidence separation must remain documented in the catalog."
Assert-Contains $PolicyText "Private Workshop is local-only." "Private Workshop evidence separation must remain local-only."

$EvidenceRoots = @(
    (Join-Path $Root "State\Workflow_Evidence"),
    (Join-Path $Root "Restricted DMZ Workspace\State\Workflow_Evidence")
)

$EvidenceFiles = @(
    Get-CanonicalEvidenceFiles -Roots $EvidenceRoots
)

foreach ($File in $EvidenceFiles) {
    $RelativePath = Get-RelativePath -BasePath $Root -TargetPath $File.FullName
    if ($RelativePath -match '^State\\Workflow_Evidence\\') {
        $WorkshopId = "open"
        $WorkshopName = "Open Workshop"
        $EvidenceRoot = Join-Path $Root "State\Workflow_Evidence"
    }
    elseif ($RelativePath -match '^Restricted DMZ Workspace\\State\\Workflow_Evidence\\') {
        $WorkshopId = "private"
        $WorkshopName = "Private Workshop"
        $EvidenceRoot = Join-Path $Root "Restricted DMZ Workspace\State\Workflow_Evidence"
    }
    else {
        Add-Issue "Evidence file is outside the canonical open/private evidence roots: $($File.FullName)"
        continue
    }

    switch -Wildcard ($File.Name) {
        'workflow_completion_*.json' {
            Validate-CompletionRecord -File $File -WorkshopId $WorkshopId -WorkshopName $WorkshopName -EvidenceRoot $EvidenceRoot
            continue
        }
        'approval_lifecycle_*.json' {
            Validate-ApprovalRecord -File $File -WorkshopId $WorkshopId -WorkshopName $WorkshopName -EvidenceRoot $EvidenceRoot
            continue
        }
        default {
            continue
        }
    }
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    evidence_files_scanned = @($EvidenceFiles).Count
    issues = @($Issues)
    source_of_truth = "Docs/Workflow_Evidence_Standard.md"
}

Write-Host '[*] COOPER workflow evidence standard validation'
Write-Host ("Status   : {0}" -f $Report.status)
Write-Host ("Scanned  : {0}" -f $Report.evidence_files_scanned)

if ($Report.status -ne "pass") {
    foreach ($Issue in @($Report.issues)) {
        Write-Host ('[FAIL] {0}' -f $Issue)
    }
    exit 1
}

Write-Host '[PASS] Workflow evidence standard validated.'
exit 0
