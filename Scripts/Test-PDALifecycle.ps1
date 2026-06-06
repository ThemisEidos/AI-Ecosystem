[CmdletBinding()]
param(
    [switch]$AsJson,
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_Lifecycle.ps1")
. (Join-Path $PSScriptRoot "PDA_Retrieval.ps1")

function New-PDALifecycleSandbox {
    param([string]$SourceRoot)

    $RunId = Get-Date -Format "yyyyMMdd-HHmmssfff"
    $SandboxRoot = Join-Path $SourceRoot "PDA-Tasks\temp\lifecycle-tests\$RunId\repo"
    $ScriptsDir = Join-Path $SandboxRoot "Scripts"
    $AssetsDir = Join-Path $SandboxRoot "PDA-Tasks\temp\lifecycle-tests\$RunId\assets"
    New-Item -ItemType Directory -Force -Path $ScriptsDir, $AssetsDir | Out-Null

    foreach ($Path in @(
        "Scripts\PDA_LifecyclePolicy.json",
        "Scripts\PDA_LifecyclePolicy.schema.json",
        "Scripts\PDA_MemoryTaxonomy.json",
        "Scripts\PDA_MemoryTaxonomy.schema.json",
        "Scripts\PDA_MemoryTaxonomy.ps1",
        "PDA_ArtifactIndex.json",
        "PDA_MemoryIndex.json"
    )) {
        $Source = Join-Path $SourceRoot $Path
        if (Test-Path $Source -PathType Leaf) {
            Copy-Item -Path $Source -Destination (Join-Path $SandboxRoot $Path) -Force
        }
    }

    $MemoryIndexPath = Join-Path $SandboxRoot "PDA_MemoryIndex.json"
    if (Test-Path $MemoryIndexPath -PathType Leaf) {
        $MemoryIndex = Get-Content -Path $MemoryIndexPath -Raw | ConvertFrom-Json
        foreach ($Memory in @($MemoryIndex.memories)) {
            if (-not ($Memory.PSObject.Properties.Name -contains "source_path")) {
                continue
            }

            $SourcePath = [string]$Memory.source_path
            if ([string]::IsNullOrWhiteSpace($SourcePath)) {
                continue
            }

            if ([System.IO.Path]::IsPathRooted($SourcePath)) {
                if (Test-Path -Path $SourcePath -PathType Leaf) {
                    $LocalSourcePath = Join-Path $AssetsDir ("{0}-source.md" -f $Memory.memory_id)
                    Copy-Item -Path $SourcePath -Destination $LocalSourcePath -Force
                    $Memory.source_path = ("PDA-Tasks\temp\lifecycle-tests\$RunId\assets\{0}-source.md" -f $Memory.memory_id)
                }
            }
            else {
                $ResolvedSource = Join-Path $SourceRoot $SourcePath
                if (Test-Path -Path $ResolvedSource -PathType Leaf) {
                    $TargetSource = Join-Path $SandboxRoot $SourcePath
                    $TargetParent = Split-Path -Parent $TargetSource
                    New-Item -ItemType Directory -Force -Path $TargetParent | Out-Null
                    Copy-Item -Path $ResolvedSource -Destination $TargetSource -Force
                }
            }
        }

        $MemoryIndex | ConvertTo-Json -Depth 20 | Set-Content -Path $MemoryIndexPath -Encoding UTF8
    }

    return [pscustomobject]@{
        root = $SandboxRoot
        artifact_index_path = Join-Path $SandboxRoot "PDA_ArtifactIndex.json"
        memory_index_path = Join-Path $SandboxRoot "PDA_MemoryIndex.json"
    }
}

function Invoke-PwshScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Script,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $Output = & pwsh -NoProfile -File (Join-Path $PSScriptRoot $Script) @Arguments 2>$null
    return [pscustomobject]@{
        output = $Output
        exit_code = $LASTEXITCODE
    }
}

function Get-PDARecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet("artifact", "memory")]
        [string]$RecordType
    )

    $Index = Get-Content -Path $Path -Raw | ConvertFrom-Json
    if ($RecordType -eq "artifact") {
        return @($Index.artifacts)
    }

    return @($Index.memories)
}

$Sandbox = New-PDALifecycleSandbox -SourceRoot $Root
$ArtifactRecords = @(Get-PDARecords -Path $Sandbox.artifact_index_path -RecordType artifact)
$MemoryRecords = @(Get-PDARecords -Path $Sandbox.memory_index_path -RecordType memory)

if ($ArtifactRecords.Count -lt 2 -or $MemoryRecords.Count -lt 2) {
    throw "Lifecycle test sandbox requires at least two artifact and two memory records."
}

$ArtifactA = [string]$ArtifactRecords[0].artifact_id
$ArtifactB = [string]$ArtifactRecords[1].artifact_id
$MemoryA = [string]$MemoryRecords[0].memory_id
$MemoryB = [string]$MemoryRecords[1].memory_id

$PolicyCheck = Test-PDALifecyclePolicyContract -Root $Sandbox.root

$ArtifactBeforeA = $ArtifactRecords | Where-Object { [string]$_.artifact_id -eq $ArtifactA } | Select-Object -First 1
$ArtifactBeforeB = $ArtifactRecords | Where-Object { [string]$_.artifact_id -eq $ArtifactB } | Select-Object -First 1
$MemoryBeforeA = $MemoryRecords | Where-Object { [string]$_.memory_id -eq $MemoryA } | Select-Object -First 1
$MemoryBeforeB = $MemoryRecords | Where-Object { [string]$_.memory_id -eq $MemoryB } | Select-Object -First 1

$InitialArtifactHash = (Get-FileHash -Path $Sandbox.artifact_index_path -Algorithm SHA256).Hash
$ArtifactDryRun = Invoke-PwshScript -Script "Set-PDAArtifactLifecycle.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-ArtifactId", $ArtifactA,
    "-LifecycleState", "archived",
    "-Reason", "dry-run verification",
    "-WhatIf",
    "-AsJson"
)
$ArtifactDryRunUnchanged = $InitialArtifactHash -eq (Get-FileHash -Path $Sandbox.artifact_index_path -Algorithm SHA256).Hash
$ArtifactDryRunSucceeded = ($ArtifactDryRun.exit_code -eq 0)

$InitialMemoryHash = (Get-FileHash -Path $Sandbox.memory_index_path -Algorithm SHA256).Hash
$MemoryDryRun = Invoke-PwshScript -Script "Set-PDAMemoryLifecycle.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-MemoryId", $MemoryA,
    "-LifecycleState", "archived",
    "-Reason", "dry-run verification",
    "-WhatIf",
    "-AsJson"
)
$MemoryDryRunUnchanged = $InitialMemoryHash -eq (Get-FileHash -Path $Sandbox.memory_index_path -Algorithm SHA256).Hash
$MemoryDryRunSucceeded = ($MemoryDryRun.exit_code -eq 0)

$ArtifactInvalid = Invoke-PwshScript -Script "Set-PDAArtifactLifecycle.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-ArtifactId", $ArtifactB,
    "-LifecycleState", "retired"
)
$MemoryInvalid = Invoke-PwshScript -Script "Set-PDAMemoryLifecycle.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-MemoryId", $MemoryB,
    "-LifecycleState", "retired"
)

$ArtifactPromote = Invoke-PwshScript -Script "Set-PDAArtifactLifecycle.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-ArtifactId", $ArtifactA,
    "-LifecycleState", "promoted",
    "-Reason", "promote for lifecycle test",
    "-Actor", "test-harness",
    "-AsJson"
)
$ArtifactPromoteReport = $ArtifactPromote.output | ConvertFrom-Json
$ArtifactPromoted = @(Get-PDAArtifacts -Root $Sandbox.root -LifecycleState "promoted")

$ArtifactArchive = Invoke-PwshScript -Script "Set-PDAArtifactLifecycle.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-ArtifactId", $ArtifactA,
    "-LifecycleState", "archived",
    "-Reason", "archive after promotion",
    "-Actor", "test-harness",
    "-AsJson"
)
$ArtifactArchiveReport = $ArtifactArchive.output | ConvertFrom-Json
$ArtifactArchived = @(Get-PDAArtifacts -Root $Sandbox.root -LifecycleState "archived")

$MemoryArchive = Invoke-PwshScript -Script "Set-PDAMemoryLifecycle.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-MemoryId", $MemoryA,
    "-LifecycleState", "archived",
    "-Reason", "archive memory",
    "-Actor", "test-harness",
    "-AsJson"
)
$MemoryArchiveReport = $MemoryArchive.output | ConvertFrom-Json
$MemoryArchived = @(Get-PDAMemory -Root $Sandbox.root -LifecycleState "archived")

$ArtifactDeprecated = Invoke-PwshScript -Script "Set-PDAArtifactLifecycle.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-ArtifactId", $ArtifactB,
    "-LifecycleState", "deprecated",
    "-Reason", "deprecate for retirement",
    "-Actor", "test-harness",
    "-AsJson"
)
$ArtifactDeprecatedReport = $ArtifactDeprecated.output | ConvertFrom-Json
$ArtifactRetire = Invoke-PwshScript -Script "Set-PDAArtifactLifecycle.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-ArtifactId", $ArtifactB,
    "-LifecycleState", "retired",
    "-Reason", "retire after deprecation",
    "-Actor", "test-harness",
    "-AsJson"
)
$ArtifactRetireReport = $ArtifactRetire.output | ConvertFrom-Json
$ArtifactRetired = @(Get-PDAArtifacts -Root $Sandbox.root -LifecycleState "retired")

$MemoryDeprecated = Invoke-PwshScript -Script "Set-PDAMemoryLifecycle.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-MemoryId", $MemoryB,
    "-LifecycleState", "deprecated",
    "-Reason", "deprecate memory",
    "-Actor", "test-harness",
    "-AsJson"
)
$MemoryDeprecatedReport = $MemoryDeprecated.output | ConvertFrom-Json
$MemoryRetire = Invoke-PwshScript -Script "Set-PDAMemoryLifecycle.ps1" -Arguments @(
    "-Root", $Sandbox.root,
    "-MemoryId", $MemoryB,
    "-LifecycleState", "retired",
    "-Reason", "retire memory",
    "-Actor", "test-harness",
    "-AsJson"
)
$MemoryRetireReport = $MemoryRetire.output | ConvertFrom-Json
$MemoryRetired = @(Get-PDAMemory -Root $Sandbox.root -LifecycleState "retired")

$ArtifactBackupExists = (-not [string]::IsNullOrWhiteSpace([string]$ArtifactArchiveReport.backup_path)) -and (Test-Path $ArtifactArchiveReport.backup_path)
$MemoryBackupExists = (-not [string]::IsNullOrWhiteSpace([string]$MemoryArchiveReport.backup_path)) -and (Test-Path $MemoryArchiveReport.backup_path)

$ArtifactLineagePreserved = ([string]$ArtifactBeforeA.source_task_id -eq [string]((Get-PDARecords -Path $Sandbox.artifact_index_path -RecordType artifact | Where-Object { [string]$_.artifact_id -eq $ArtifactA } | Select-Object -First 1).source_task_id)) -and
    ([string]$ArtifactBeforeA.artifact_path -eq [string]((Get-PDARecords -Path $Sandbox.artifact_index_path -RecordType artifact | Where-Object { [string]$_.artifact_id -eq $ArtifactA } | Select-Object -First 1).artifact_path))
$MemoryLineagePreserved = ([string]$MemoryBeforeA.source_artifact_id -eq [string]((Get-PDARecords -Path $Sandbox.memory_index_path -RecordType memory | Where-Object { [string]$_.memory_id -eq $MemoryA } | Select-Object -First 1).source_artifact_id)) -and
    ([string]$MemoryBeforeA.source_path -eq [string]((Get-PDARecords -Path $Sandbox.memory_index_path -RecordType memory | Where-Object { [string]$_.memory_id -eq $MemoryA } | Select-Object -First 1).source_path))

$Report = [pscustomobject]@{
    status = if (
        $PolicyCheck.valid -and
        $ArtifactDryRunUnchanged -and
        $MemoryDryRunUnchanged -and
        $ArtifactDryRunSucceeded -and
        $MemoryDryRunSucceeded -and
        ($ArtifactInvalid.exit_code -ne 0) -and
        ($MemoryInvalid.exit_code -ne 0) -and
        ($ArtifactPromoteReport.history_count -eq 1) -and
        ($ArtifactArchiveReport.history_count -eq 2) -and
        ($MemoryArchiveReport.history_count -eq 1) -and
        ($ArtifactDeprecatedReport.history_count -eq 1) -and
        ($ArtifactRetireReport.history_count -eq 2) -and
        ($MemoryDeprecatedReport.history_count -eq 1) -and
        ($MemoryRetireReport.history_count -eq 2) -and
        $ArtifactPromoteReport.validation_valid -and
        $ArtifactArchiveReport.validation_valid -and
        $MemoryArchiveReport.validation_valid -and
        $ArtifactDeprecatedReport.validation_valid -and
        $ArtifactRetireReport.validation_valid -and
        $MemoryDeprecatedReport.validation_valid -and
        $MemoryRetireReport.validation_valid -and
        $ArtifactBackupExists -and
        $MemoryBackupExists -and
        $ArtifactLineagePreserved -and
        $MemoryLineagePreserved -and
        (@($ArtifactPromoted) | Where-Object { [string]$_.artifact_id -eq $ArtifactA }).Count -gt 0 -and
        (@($ArtifactArchived) | Where-Object { [string]$_.artifact_id -eq $ArtifactA }).Count -gt 0 -and
        (@($ArtifactRetired) | Where-Object { [string]$_.artifact_id -eq $ArtifactB }).Count -gt 0 -and
        (@($MemoryArchived) | Where-Object { [string]$_.memory_id -eq $MemoryA }).Count -gt 0 -and
        (@($MemoryRetired) | Where-Object { [string]$_.memory_id -eq $MemoryB }).Count -gt 0
    ) { "pass" } else { "fail" }
    policy_valid = [bool]$PolicyCheck.valid
    artifact_dry_run_unchanged = [bool]$ArtifactDryRunUnchanged
    memory_dry_run_unchanged = [bool]$MemoryDryRunUnchanged
    artifact_dry_run_succeeded = [bool]$ArtifactDryRunSucceeded
    memory_dry_run_succeeded = [bool]$MemoryDryRunSucceeded
    artifact_invalid_blocked = [bool]($ArtifactInvalid.exit_code -ne 0)
    memory_invalid_blocked = [bool]($MemoryInvalid.exit_code -ne 0)
    artifact_backup_exists = [bool]$ArtifactBackupExists
    memory_backup_exists = [bool]$MemoryBackupExists
    artifact_lineage_preserved = [bool]$ArtifactLineagePreserved
    memory_lineage_preserved = [bool]$MemoryLineagePreserved
    artifact_promote_history_count = [int]$ArtifactPromoteReport.history_count
    artifact_archive_history_count = [int]$ArtifactArchiveReport.history_count
    memory_archive_history_count = [int]$MemoryArchiveReport.history_count
    artifact_deprecated_history_count = [int]$ArtifactDeprecatedReport.history_count
    artifact_retire_history_count = [int]$ArtifactRetireReport.history_count
    memory_deprecated_history_count = [int]$MemoryDeprecatedReport.history_count
    memory_retire_history_count = [int]$MemoryRetireReport.history_count
    artifact_promoted_count = @($ArtifactPromoted).Count
    artifact_archived_count = @($ArtifactArchived).Count
    artifact_retired_count = @($ArtifactRetired).Count
    memory_archived_count = @($MemoryArchived).Count
    memory_retired_count = @($MemoryRetired).Count
    sandbox_root = $Sandbox.root
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA lifecycle validation failed."
    }
    return
}

Write-Host "[*] PDA artifact and memory lifecycle"
Write-Host ("Sandbox root              : {0}" -f $Sandbox.root)
Write-Host ("Policy valid              : {0}" -f $Report.policy_valid)
Write-Host ("Artifact dry-run unchanged : {0}" -f $Report.artifact_dry_run_unchanged)
Write-Host ("Memory dry-run unchanged   : {0}" -f $Report.memory_dry_run_unchanged)
Write-Host ("Artifact invalid blocked   : {0}" -f $Report.artifact_invalid_blocked)
Write-Host ("Memory invalid blocked     : {0}" -f $Report.memory_invalid_blocked)
Write-Host ("Artifact backup exists     : {0}" -f $Report.artifact_backup_exists)
Write-Host ("Memory backup exists       : {0}" -f $Report.memory_backup_exists)
Write-Host ("Artifact lineage preserved : {0}" -f $Report.artifact_lineage_preserved)
Write-Host ("Memory lineage preserved   : {0}" -f $Report.memory_lineage_preserved)
Write-Host ("Artifact promoted count    : {0}" -f $Report.artifact_promoted_count)
Write-Host ("Artifact archived count    : {0}" -f $Report.artifact_archived_count)
Write-Host ("Artifact retired count     : {0}" -f $Report.artifact_retired_count)
Write-Host ("Memory archived count      : {0}" -f $Report.memory_archived_count)
Write-Host ("Memory retired count       : {0}" -f $Report.memory_retired_count)
Write-Host ("Status                     : {0}" -f $Report.status)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA lifecycle validation failed."
}
