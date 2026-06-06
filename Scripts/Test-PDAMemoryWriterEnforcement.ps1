[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_MemoryTaxonomy.ps1")

function New-PDAMemoryWriterSandbox {
    param([string]$SourceRoot)

    $RunId = Get-Date -Format "yyyyMMdd-HHmmssfff"
    $SandboxRoot = Join-Path $SourceRoot "PDA-Tasks\temp\memory-writer-tests\$RunId\repo"
    $ScriptsDir = Join-Path $SandboxRoot "Scripts"
    $AssetsDir = Join-Path $SourceRoot "PDA-Tasks\temp\memory-writer-tests\$RunId\assets"
    New-Item -ItemType Directory -Force -Path $ScriptsDir, $AssetsDir | Out-Null

    foreach ($Path in @(
        "Scripts\PDA_MemoryTaxonomy.json",
        "Scripts\PDA_MemoryTaxonomy.schema.json",
        "PDA_MemoryIndex.json",
        "PDA_ArtifactIndex.json"
    )) {
        $Source = Join-Path $SourceRoot $Path
        if (Test-Path $Source -PathType Leaf) {
            Copy-Item -Path $Source -Destination (Join-Path $SandboxRoot $Path) -Force
        }
    }

    $SeedArtifactPath = Join-Path $AssetsDir "seed-writer-source.md"
    $LegacySourcePath = Join-Path $AssetsDir "memory-validation-note.md"
    @"
# PDA Memory Writer Seed

Synthetic source artifact used for deterministic memory writer enforcement tests.
"@ | Set-Content -Path $SeedArtifactPath -Encoding UTF8
    @"
# PDA Legacy Memory Source

Synthetic source artifact used to repair a legacy memory record during tests.
"@ | Set-Content -Path $LegacySourcePath -Encoding UTF8

    $ArtifactIndexPath = Join-Path $SandboxRoot "PDA_ArtifactIndex.json"
    $ArtifactIndex = Get-Content -Path $ArtifactIndexPath -Raw | ConvertFrom-Json
    if ($null -eq $ArtifactIndex.artifacts -or $ArtifactIndex.artifacts -isnot [System.Array]) {
        throw "Sandbox artifact index is invalid."
    }

    $SeedArtifactId = "artifact-seeded-memory-writer-001"
    $LegacyArtifactId = "artifact-test-0001"

    $ArtifactIndex.artifacts = @($ArtifactIndex.artifacts | Where-Object { [string]$_.artifact_id -ne $SeedArtifactId -and [string]$_.artifact_id -ne $LegacyArtifactId })
    $ArtifactIndex.artifacts += [pscustomobject]@{
        artifact_id    = $SeedArtifactId
        created_at     = "2026-06-03T12:10:00Z"
        artifact_path  = $SeedArtifactPath
        source_task_id = "task-seeded-memory-writer-001"
        worker_name    = "planner-worker"
        command        = "/planner"
        category       = "category_1"
        artifact_type  = "memory-source-markdown"
        tags           = @("memory", "writer", "seed")
        summary        = "Synthetic source artifact for memory writer enforcement tests"
    }
    $ArtifactIndex.artifacts += [pscustomobject]@{
        artifact_id    = $LegacyArtifactId
        created_at     = "2026-06-03T12:10:01Z"
        artifact_path  = $LegacySourcePath
        source_task_id = "task-test-memory-legacy-0001"
        worker_name    = "planner-worker"
        command        = "/planner"
        category       = "test"
        artifact_type  = "test-note"
        tags           = @("test", "legacy", "memory")
        summary        = "Synthetic source artifact for legacy memory repair tests"
    }
    $ArtifactIndex.updated_at = "2026-06-03T12:10:02Z"
    $ArtifactIndex | ConvertTo-Json -Depth 20 | Set-Content -Path $ArtifactIndexPath -Encoding UTF8

    return [pscustomobject]@{
        root              = $SandboxRoot
        assets_dir        = $AssetsDir
        seed_artifact_id  = $SeedArtifactId
        seed_artifact_path = $SeedArtifactPath
        legacy_artifact_id = $LegacyArtifactId
        legacy_source_path = $LegacySourcePath
    }
}

function Invoke-PDACmd {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Script,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & pwsh -NoProfile -File (Join-Path $PSScriptRoot $Script) @Arguments 2>$null
    return $LASTEXITCODE
}

function Get-PDAMemoryRecords {
    param([string]$Path)

    (Get-Content -Path $Path -Raw | ConvertFrom-Json).memories
}

$Sandbox = New-PDAMemoryWriterSandbox -SourceRoot $Root
$Taxonomy = Import-PDAMemoryTaxonomy -Root $Sandbox.root

$WriterScripts = @(
    "Register-PDAMemory.ps1",
    "Promote-PDAArtifactToMemory.ps1",
    "Update-PDAMemoryRecord.ps1",
    "Repair-PDALegacyMemoryRecord.ps1"
)

$WriterCount = $WriterScripts.Count
$CompliantWriterCount = 0
foreach ($Writer in $WriterScripts) {
    $Content = Get-Content -Path (Join-Path $PSScriptRoot $Writer) -Raw
    if ($Content -match 'PDA_MemoryTaxonomy|Assert-PDAMemoryRecordTaxonomyWritable|Test-PDAMemoryRecordAgainstTaxonomy|Get-PDAMemoryTaxonomyDefaults|Register-PDAMemory\.ps1') {
        $CompliantWriterCount++
    }
}

$SandboxMemoryIndexPath = Join-Path $Sandbox.root "PDA_MemoryIndex.json"
$SandboxArtifactIndexPath = Join-Path $Sandbox.root "PDA_ArtifactIndex.json"
$InitialRecords = @(Get-PDAMemoryRecords -Path $SandboxMemoryIndexPath)
$InitialCount = $InitialRecords.Count

$ValidRegisterExit = Invoke-PDACmd -Script "Register-PDAMemory.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-MemoryType", "promoted-artifact",
    "-Title", "Writer enforcement seed memory",
    "-Summary", "Synthetic memory record created for enforcement testing.",
    "-Category", "category_1",
    "-SourceArtifactId", $Sandbox.seed_artifact_id
)
$PostRegisterRecords = @(Get-PDAMemoryRecords -Path $SandboxMemoryIndexPath)
$RegisteredRecord = $PostRegisterRecords[-1]
$RegisteredLookup = @{}
foreach ($Artifact in @(Get-Content -Path $SandboxArtifactIndexPath -Raw | ConvertFrom-Json).artifacts) {
    if ($Artifact.PSObject.Properties.Name -contains "artifact_id" -and -not [string]::IsNullOrWhiteSpace([string]$Artifact.artifact_id)) {
        $RegisteredLookup[[string]$Artifact.artifact_id] = $Artifact
    }
}
$RegisteredValidation = Assert-PDAMemoryRecordTaxonomyWritable -Record $RegisteredRecord -Taxonomy $Taxonomy -ArtifactLookup $RegisteredLookup -Root $Sandbox.root

$InvalidRegisterBlocked = $false
try {
    $InvalidExit = Invoke-PDACmd -Script "Register-PDAMemory.ps1" -Arguments @(
        "-Root", $Sandbox.root,
        "-MemoryType", "promoted-artifact",
        "-Title", "Invalid writer seed",
        "-Summary", "This should fail closed.",
        "-Category", "category_1",
        "-SourceArtifactId", $Sandbox.seed_artifact_id,
        "-Status", "bogus"
    )
    if ($InvalidExit -ne 0) {
        $InvalidRegisterBlocked = $true
    }
}
catch {
    $InvalidRegisterBlocked = $true
}

$PromoteExit = Invoke-PDACmd -Script "Promote-PDAArtifactToMemory.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-ArtifactId", $Sandbox.seed_artifact_id,
    "-MemoryType", "promoted-artifact",
    "-Title", "Promoted writer enforcement memory",
    "-Summary", "Synthetic promotion used to verify taxonomy-compliant creation."
)
$PostPromoteRecords = @(Get-PDAMemoryRecords -Path $SandboxMemoryIndexPath)
$PromotedRecord = $PostPromoteRecords[-1]
$PromotedValidation = Assert-PDAMemoryRecordTaxonomyWritable -Record $PromotedRecord -Taxonomy $Taxonomy -ArtifactLookup $RegisteredLookup -Root $Sandbox.root

$LegacyRecord = $PostRegisterRecords | Where-Object { [string]$_.memory_id -eq "memory-7d41a212-3f98-4a48-8e1a-45fd67203375" } | Select-Object -First 1
if (-not $LegacyRecord) {
    throw "Legacy memory record not found in sandbox."
}

$RepairExit = Invoke-PDACmd -Script "Update-PDAMemoryRecord.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-MemoryId", [string]$LegacyRecord.memory_id,
    "-SourceArtifactId", $Sandbox.legacy_artifact_id,
    "-SourcePath", $Sandbox.legacy_source_path,
    "-Status", "test",
    "-Confidence", "0.5",
    "-Sensitivity", "test",
    "-SourceType", "artifact",
    "-LifecycleState", "test"
)
$PostRepairRecords = @(Get-PDAMemoryRecords -Path $SandboxMemoryIndexPath)
$RepairedRecord = $PostRepairRecords | Where-Object { [string]$_.memory_id -eq [string]$LegacyRecord.memory_id } | Select-Object -First 1
$RepairedLookup = @{}
foreach ($Artifact in @(Get-Content -Path $SandboxArtifactIndexPath -Raw | ConvertFrom-Json).artifacts) {
    if ($Artifact.PSObject.Properties.Name -contains "artifact_id" -and -not [string]::IsNullOrWhiteSpace([string]$Artifact.artifact_id)) {
        $RepairedLookup[[string]$Artifact.artifact_id] = $Artifact
    }
}
$RepairedValidation = Assert-PDAMemoryRecordTaxonomyWritable -Record $RepairedRecord -Taxonomy $Taxonomy -ArtifactLookup $RepairedLookup -Root $Sandbox.root

$LiveTaxonomyJson = & pwsh -NoProfile -File (Join-Path $PSScriptRoot "Test-PDAMemoryTaxonomy.ps1") -NoThrow -AsJson
$LiveTaxonomy = $LiveTaxonomyJson | ConvertFrom-Json
$LiveIndexClean = $LiveTaxonomy.status -eq "pass" -and $LiveTaxonomy.invalid_record_count -eq 0

$Report = [pscustomobject]@{
    status = if ($InvalidRegisterBlocked -and $RegisteredValidation.valid -and $PromotedValidation.valid -and $RepairedValidation.valid -and $LiveIndexClean) { "pass" } else { "fail" }
    writer_count = $WriterCount
    taxonomy_compliant_writer_count = $CompliantWriterCount
    live_total_record_count = [int]$LiveTaxonomy.total_record_count
    live_valid_record_count = [int]$LiveTaxonomy.valid_record_count
    live_invalid_record_count = [int]$LiveTaxonomy.invalid_record_count
    repair_needed_count = [int]$LiveTaxonomy.invalid_record_count
    valid_new_record_pass = [bool]$RegisteredValidation.valid
    invalid_new_record_blocked = [bool]$InvalidRegisterBlocked
    promotion_compliant = [bool]$PromotedValidation.valid
    update_repair_compliant = [bool]$RepairedValidation.valid
    live_index_clean = [bool]$LiveIndexClean
    sandbox_root = $Sandbox.root
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA memory writer enforcement validation failed."
    }
    return
}

Write-Host "[*] PDA memory writer enforcement"
Write-Host ("Sandbox root                : {0}" -f $Sandbox.root)
Write-Host ("Writer count                : {0}" -f $Report.writer_count)
Write-Host ("Taxonomy-compliant writers  : {0}" -f $Report.taxonomy_compliant_writer_count)
Write-Host ("Live total records          : {0}" -f $Report.live_total_record_count)
Write-Host ("Live valid records          : {0}" -f $Report.live_valid_record_count)
Write-Host ("Live invalid records        : {0}" -f $Report.live_invalid_record_count)
Write-Host ("Repair needed count         : {0}" -f $Report.repair_needed_count)
Write-Host ("Valid new record pass       : {0}" -f $Report.valid_new_record_pass)
Write-Host ("Invalid new record blocked  : {0}" -f $Report.invalid_new_record_blocked)
Write-Host ("Promotion compliant         : {0}" -f $Report.promotion_compliant)
Write-Host ("Update repair compliant      : {0}" -f $Report.update_repair_compliant)
Write-Host ("Live index clean            : {0}" -f $Report.live_index_clean)
Write-Host ("Status                      : {0}" -f $Report.status)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA memory writer enforcement validation failed."
}
