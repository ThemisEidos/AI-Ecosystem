[CmdletBinding()]
param(
    [switch]$AsJson,
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_MemoryTaxonomy.ps1")

function New-PDALegacyMemoryRepairSandbox {
    param([string]$SourceRoot)

    $RunId = Get-Date -Format "yyyyMMdd-HHmmssfff"
    $SandboxRoot = Join-Path $SourceRoot "PDA-Tasks\temp\legacy-memory-repair-tests\$RunId\repo"
    $ScriptsDir = Join-Path $SandboxRoot "Scripts"
    $AssetsDir = Join-Path $SourceRoot "PDA-Tasks\temp\legacy-memory-repair-tests\$RunId\assets"
    New-Item -ItemType Directory -Force -Path $ScriptsDir, $AssetsDir | Out-Null

    foreach ($Path in @(
        "Scripts\PDA_MemoryTaxonomy.json",
        "Scripts\PDA_MemoryTaxonomy.schema.json",
        "Scripts\PDA_MemoryTaxonomy.ps1",
        "Scripts\Repair-PDALegacyMemoryRecord.ps1",
        "Scripts\PDA_LegacyMemoryRepairAllowlist.json",
        "PDA_MemoryIndex.json",
        "PDA_ArtifactIndex.json"
    )) {
        $Source = Join-Path $SourceRoot $Path
        if (Test-Path $Source -PathType Leaf) {
            Copy-Item -Path $Source -Destination (Join-Path $SandboxRoot $Path) -Force
        }
    }

    $PrimaryRepairSource = Join-Path $AssetsDir "legacy-memory-source.md"
    $OverrideRepairSource = Join-Path $AssetsDir "override-memory-source.md"
    @"
# Legacy Memory Repair Source

Synthetic source artifact used for explicit legacy repair testing.
"@ | Set-Content -Path $PrimaryRepairSource -Encoding UTF8
    @"
# Override Memory Repair Source

Synthetic source artifact used to verify explicit override behavior.
"@ | Set-Content -Path $OverrideRepairSource -Encoding UTF8

    $ArtifactIndexPath = Join-Path $SandboxRoot "PDA_ArtifactIndex.json"
    $ArtifactIndex = Get-Content -Path $ArtifactIndexPath -Raw | ConvertFrom-Json
    if ($null -eq $ArtifactIndex.artifacts -or $ArtifactIndex.artifacts -isnot [System.Array]) {
        throw "Sandbox artifact index is invalid."
    }

    $PrimaryArtifactId = "artifact-legacy-repair-001"
    $OverrideArtifactId = "artifact-legacy-repair-override-001"

    $ArtifactIndex.artifacts = @($ArtifactIndex.artifacts | Where-Object {
        [string]$_.artifact_id -notin @($PrimaryArtifactId, $OverrideArtifactId)
    })
    $ArtifactIndex.artifacts += [pscustomobject]@{
        artifact_id    = $PrimaryArtifactId
        created_at     = "2026-06-03T12:30:00Z"
        artifact_path  = $PrimaryRepairSource
        source_task_id = "task-legacy-repair-001"
        worker_name    = "planner-worker"
        command        = "/planner"
        category       = "category_1"
        artifact_type  = "memory-source-markdown"
        tags           = @("memory", "repair", "legacy")
        summary        = "Synthetic source artifact for legacy memory repair testing"
    }
    $ArtifactIndex.artifacts += [pscustomobject]@{
        artifact_id    = $OverrideArtifactId
        created_at     = "2026-06-03T12:30:01Z"
        artifact_path  = $OverrideRepairSource
        source_task_id = "task-legacy-repair-override-001"
        worker_name    = "planner-worker"
        command        = "/planner"
        category       = "category_1"
        artifact_type  = "memory-source-markdown"
        tags           = @("memory", "repair", "override")
        summary        = "Synthetic source artifact for legacy memory repair override testing"
    }
    $ArtifactIndex.updated_at = "2026-06-03T12:30:02Z"
    $ArtifactIndex | ConvertTo-Json -Depth 20 | Set-Content -Path $ArtifactIndexPath -Encoding UTF8

    return [pscustomobject]@{
        root                = $SandboxRoot
        assets_dir          = $AssetsDir
        primary_artifact_id = $PrimaryArtifactId
        primary_source_path = $PrimaryRepairSource
        override_artifact_id = $OverrideArtifactId
        override_source_path = $OverrideRepairSource
    }
}

function Invoke-PDACmd {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Script,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $Output = & pwsh -NoProfile -File (Join-Path $PSScriptRoot $Script) @Arguments 2>$null
    $ExitCode = $LASTEXITCODE
    return [pscustomobject]@{
        output = $Output
        exit_code = $ExitCode
    }
}

function Get-PDAMemoryRecords {
    param([string]$Path)
    (Get-Content -Path $Path -Raw | ConvertFrom-Json).memories
}

$Sandbox = New-PDALegacyMemoryRepairSandbox -SourceRoot $Root
$Taxonomy = Import-PDAMemoryTaxonomy -Root $Sandbox.root
$SandboxMemoryIndexPath = Join-Path $Sandbox.root "PDA_MemoryIndex.json"

$InitialHash = (Get-FileHash -Path $SandboxMemoryIndexPath -Algorithm SHA256).Hash
$InitialRecords = @(Get-PDAMemoryRecords -Path $SandboxMemoryIndexPath)
$AllowlistedLegacyId = "memory-7d41a212-3f98-4a48-8e1a-45fd67203375"
$NonAllowlistedId = "memory-not-allowlisted-001"

$DryRunResult = Invoke-PDACmd -Script "Repair-PDALegacyMemoryRecord.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-MemoryId", $AllowlistedLegacyId,
    "-Status", "test",
    "-Confidence", "0.5",
    "-Sensitivity", "test",
    "-SourceType", "artifact",
    "-LifecycleState", "test",
    "-Tags", "legacy,memory,repair,test",
    "-SourceArtifactId", $Sandbox.primary_artifact_id,
    "-SourcePath", $Sandbox.primary_source_path,
    "-WhatIf"
)
$PostDryRunHash = (Get-FileHash -Path $SandboxMemoryIndexPath -Algorithm SHA256).Hash
$DryRunUnchanged = $InitialHash -eq $PostDryRunHash

$MissingIdBlocked = $false
try {
    $MissingIdResult = Invoke-PDACmd -Script "Repair-PDALegacyMemoryRecord.ps1" -Arguments @(
        "-Root", $Sandbox.root,
        "-MemoryId", "memory-does-not-exist",
        "-Status", "test",
        "-Confidence", "0.5",
        "-Sensitivity", "test",
        "-SourceType", "artifact",
        "-LifecycleState", "test",
        "-Tags", "legacy,memory,repair,test",
        "-SourceArtifactId", $Sandbox.primary_artifact_id,
        "-SourcePath", $Sandbox.primary_source_path
    )
    if ($MissingIdResult.exit_code -ne 0) {
        $MissingIdBlocked = $true
    }
}
catch {
    $MissingIdBlocked = $true
}

$AllowlistBlocked = $false
try {
    $AllowlistResult = Invoke-PDACmd -Script "Repair-PDALegacyMemoryRecord.ps1" -Arguments @(
        "-Root", $Sandbox.root,
        "-MemoryId", $NonAllowlistedId,
        "-Status", "test",
        "-Confidence", "0.5",
        "-Sensitivity", "test",
        "-SourceType", "artifact",
        "-LifecycleState", "test",
        "-Tags", "legacy,memory,repair,test",
        "-SourceArtifactId", $Sandbox.primary_artifact_id,
        "-SourcePath", $Sandbox.primary_source_path
    )
    if ($AllowlistResult.exit_code -ne 0) {
        $AllowlistBlocked = $true
    }
}
catch {
    $AllowlistBlocked = $true
}

$InvalidEnumBlocked = $false
try {
    $InvalidEnumResult = Invoke-PDACmd -Script "Repair-PDALegacyMemoryRecord.ps1" -Arguments @(
        "-Root", $Sandbox.root,
        "-MemoryId", $AllowlistedLegacyId,
        "-Status", "bogus",
        "-Confidence", "0.5",
        "-Sensitivity", "test",
        "-SourceType", "artifact",
        "-LifecycleState", "test",
        "-SourceArtifactId", $Sandbox.primary_artifact_id,
        "-SourcePath", $Sandbox.primary_source_path
    )
    if ($InvalidEnumResult.exit_code -ne 0) {
        $InvalidEnumBlocked = $true
    }
}
catch {
    $InvalidEnumBlocked = $true
}

$BrokenReferenceBlocked = $false
try {
    $BrokenReferenceResult = Invoke-PDACmd -Script "Repair-PDALegacyMemoryRecord.ps1" -Arguments @(
        "-Root", $Sandbox.root,
        "-MemoryId", $AllowlistedLegacyId,
        "-Status", "test",
        "-Confidence", "0.5",
        "-Sensitivity", "test",
        "-SourceType", "artifact",
        "-LifecycleState", "test",
        "-Tags", "legacy,memory,repair,test",
        "-SourceArtifactId", "artifact-missing-override-target",
        "-SourcePath", $Sandbox.primary_source_path
    )
    if ($BrokenReferenceResult.exit_code -ne 0) {
        $BrokenReferenceBlocked = $true
    }
}
catch {
    $BrokenReferenceBlocked = $true
}

$OverrideResult = Invoke-PDACmd -Script "Repair-PDALegacyMemoryRecord.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-MemoryId", $AllowlistedLegacyId,
    "-Status", "test",
    "-Confidence", "0.5",
    "-Sensitivity", "test",
    "-SourceType", "artifact",
    "-LifecycleState", "test",
    "-Tags", "legacy,memory,repair,test",
    "-SourceArtifactId", "artifact-missing-override-target",
    "-SourcePath", $Sandbox.primary_source_path,
    "-AllowBrokenSourceReference"
)
$PostOverrideRecords = @(Get-PDAMemoryRecords -Path $SandboxMemoryIndexPath)
$OverrideRecord = $PostOverrideRecords | Where-Object { [string]$_.memory_id -eq $AllowlistedLegacyId } | Select-Object -First 1
$PreRepairHash = (Get-FileHash -Path $SandboxMemoryIndexPath -Algorithm SHA256).Hash

$RepairResult = Invoke-PDACmd -Script "Repair-PDALegacyMemoryRecord.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-MemoryId", $AllowlistedLegacyId,
    "-Status", "test",
    "-Confidence", "0.5",
    "-Sensitivity", "test",
    "-SourceType", "artifact",
    "-LifecycleState", "test",
    "-Tags", "legacy,memory,repair,test",
    "-SourceArtifactId", $Sandbox.primary_artifact_id,
    "-SourcePath", $Sandbox.primary_source_path
)
$PostRepairRecords = @(Get-PDAMemoryRecords -Path $SandboxMemoryIndexPath)
$RepairedRecord = $PostRepairRecords | Where-Object { [string]$_.memory_id -eq $AllowlistedLegacyId } | Select-Object -First 1

$BackupRoot = Join-Path $Sandbox.root "PDA-Backups\legacy-memory-repairs"
$BackupDirectories = @()
if (Test-Path -Path $BackupRoot) {
    $BackupDirectories = @(Get-ChildItem -Path $BackupRoot -Directory -ErrorAction SilentlyContinue)
}
$BackupCreated = $BackupDirectories.Count -gt 0
$BackupFileValid = $false
if ($BackupCreated) {
    $LatestBackup = $BackupDirectories | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $BackupFilePath = Join-Path $LatestBackup.FullName "PDA_MemoryIndex.json.bak"
    if (Test-Path -Path $BackupFilePath -PathType Leaf) {
        $BackupFileValid = ((Get-FileHash -Path $BackupFilePath -Algorithm SHA256).Hash -eq $PreRepairHash)
    }
}

$ReplicaArtifactLookup = @{}
$ReplicaArtifactLookup[[string]$Sandbox.primary_artifact_id] = [pscustomobject]@{
    artifact_id   = $Sandbox.primary_artifact_id
    artifact_path = $Sandbox.primary_source_path
}
$ReplicaArtifactLookup[[string]$Sandbox.override_artifact_id] = [pscustomobject]@{
    artifact_id   = $Sandbox.override_artifact_id
    artifact_path = $Sandbox.override_source_path
}
$ReplicaValidation = Assert-PDAMemoryRecordTaxonomyWritable -Record $RepairedRecord -Taxonomy $Taxonomy -ArtifactLookup $ReplicaArtifactLookup -Root $Sandbox.root

$OtherRecord = $PostRepairRecords | Where-Object { [string]$_.memory_id -ne $AllowlistedLegacyId } | Select-Object -First 1
$OtherRecordUnchanged = $true
if ($InitialRecords.Count -gt 1 -and $null -ne $OtherRecord) {
    $InitialOtherRecord = $InitialRecords | Where-Object { [string]$_.memory_id -eq [string]$OtherRecord.memory_id } | Select-Object -First 1
    $OtherRecordUnchanged = ((ConvertTo-Json $InitialOtherRecord -Depth 20) -eq (ConvertTo-Json $OtherRecord -Depth 20))
}

$LiveTaxonomyJson = & pwsh -NoProfile -File (Join-Path $PSScriptRoot "Test-PDAMemoryTaxonomy.ps1") -NoThrow -AsJson
$LiveTaxonomy = $LiveTaxonomyJson | ConvertFrom-Json

$Report = [pscustomobject]@{
    status                       = if ($DryRunUnchanged -and $MissingIdBlocked -and $AllowlistBlocked -and $InvalidEnumBlocked -and $BrokenReferenceBlocked -and $OverrideResult.exit_code -eq 0 -and $RepairResult.exit_code -eq 0 -and $BackupCreated -and $BackupFileValid -and $ReplicaValidation.valid -and $OtherRecordUnchanged) { "pass" } else { "fail" }
    sandbox_root                 = $Sandbox.root
    allowlisted_memory_id        = $AllowlistedLegacyId
    dry_run_unchanged            = [bool]$DryRunUnchanged
    missing_memory_id_blocked    = [bool]$MissingIdBlocked
    allowlist_blocked            = [bool]$AllowlistBlocked
    invalid_enum_blocked         = [bool]$InvalidEnumBlocked
    broken_reference_blocked     = [bool]$BrokenReferenceBlocked
    override_exit_code           = [int]$OverrideResult.exit_code
    repair_exit_code             = [int]$RepairResult.exit_code
    backup_created               = [bool]$BackupCreated
    backup_file_valid            = [bool]$BackupFileValid
    patched_record_valid         = [bool]$ReplicaValidation.valid
    patched_record_issue_count    = [int]$ReplicaValidation.issue_count
    other_record_unchanged       = [bool]$OtherRecordUnchanged
    live_taxonomy_status          = [string]$LiveTaxonomy.status
    live_taxonomy_invalid_count   = [int]$LiveTaxonomy.invalid_record_count
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA legacy memory repair test failed."
    }
    return
}

Write-Host "[*] PDA legacy memory repair"
Write-Host ("Sandbox root              : {0}" -f $Sandbox.root)
Write-Host ("Dry run unchanged         : {0}" -f $Report.dry_run_unchanged)
Write-Host ("Missing memory id blocked : {0}" -f $Report.missing_memory_id_blocked)
Write-Host ("Allowlist blocked         : {0}" -f $Report.allowlist_blocked)
Write-Host ("Invalid enum blocked      : {0}" -f $Report.invalid_enum_blocked)
Write-Host ("Broken ref blocked        : {0}" -f $Report.broken_reference_blocked)
Write-Host ("Override exit code        : {0}" -f $Report.override_exit_code)
Write-Host ("Repair exit code          : {0}" -f $Report.repair_exit_code)
Write-Host ("Backup created            : {0}" -f $Report.backup_created)
Write-Host ("Backup file valid         : {0}" -f $Report.backup_file_valid)
Write-Host ("Patched record valid      : {0}" -f $Report.patched_record_valid)
Write-Host ("Other record unchanged    : {0}" -f $Report.other_record_unchanged)
Write-Host ("Live taxonomy status      : {0}" -f $Report.live_taxonomy_status)
Write-Host ("Live invalid count        : {0}" -f $Report.live_taxonomy_invalid_count)
Write-Host ("Status                    : {0}" -f $Report.status)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA legacy memory repair test failed."
}
