[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$RoadmapPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\PDA-Roadmap.json"),

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$NoDryRun,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$IsDryRun = if ($PSBoundParameters.ContainsKey("DryRun")) { $DryRun.IsPresent } elseif ($NoDryRun) { $false } else { $true }
if (-not $IsDryRun) {
    throw "Unattended orchestration is disabled in PDA Nightly Build Orchestrator v1."
}

if (-not (Test-Path -Path $RoadmapPath -PathType Leaf)) {
    throw "Roadmap not found: $RoadmapPath"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $Root ("PDA-Backups\nightly-build\" + (Get-Date -Format "yyyyMMdd-HHmmss"))
}

$ScriptsRoot = Join-Path $Root "Scripts"
$RepoBackupScript = Join-Path $ScriptsRoot "Backup-PDARepo.ps1"
$VolumeBackupScript = Join-Path $ScriptsRoot "Backup-PDAVolumes.ps1"
$NightlyDir = $OutputRoot
New-Item -ItemType Directory -Force -Path $NightlyDir | Out-Null

function Get-PDARoadmap {
    param([string]$Path)
    return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
}

function Test-PDATaskDependenciesSatisfied {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)]$Roadmap
    )

    $Dependencies = @($Task.dependencies) | ForEach-Object { [string]$_ }
    if ($Dependencies.Count -eq 0) {
        return $true
    }

    $Completed = @($Roadmap.completed_task_ids) | ForEach-Object { [string]$_ }
    foreach ($Dependency in $Dependencies) {
        if ($Completed -notcontains $Dependency) {
            return $false
        }
    }

    return $true
}

function Get-PDANextEligibleTask {
    param([Parameter(Mandatory = $true)]$Roadmap)

    $EligibleStatuses = @("backlog", "eligible")
    foreach ($Task in @($Roadmap.tasks)) {
        if ($EligibleStatuses -contains [string]$Task.status -and (Test-PDATaskDependenciesSatisfied -Task $Task -Roadmap $Roadmap)) {
            return $Task
        }
    }

    return $null
}

function Invoke-PDAJsonScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $Raw = & pwsh -NoProfile -File $Path @Arguments -AsJson 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $Path"
    }

    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Command returned empty output: $Path"
    }

    return $Text | ConvertFrom-Json
}

$Roadmap = Get-PDARoadmap -Path $RoadmapPath
$SelectedTask = Get-PDANextEligibleTask -Roadmap $Roadmap

$SelectedTaskId = if ($SelectedTask) { [string]$SelectedTask.id } else { "" }
$SelectedTaskTitle = if ($SelectedTask) { [string]$SelectedTask.title } else { "" }
$SelectedTaskObjective = if ($SelectedTask) { [string]$SelectedTask.objective } else { "" }
$BranchName = if ($SelectedTaskId) { "codex/nightly-$($SelectedTaskId)-$(Get-Date -Format 'yyyyMMdd-HHmmss')" } else { "codex/nightly-idle-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }

$RepoBackup = Invoke-PDAJsonScript -Path $RepoBackupScript -Arguments @(
    "-Root", $Root,
    "-OutputRoot", $NightlyDir,
    "-DryRun"
)

$VolumeBackup = Invoke-PDAJsonScript -Path $VolumeBackupScript -Arguments @(
    "-Root", $Root,
    "-OutputRoot", $NightlyDir,
    "-DryRun"
)

$WorkPacket = [pscustomobject]@{
    schema_version          = "1.0"
    generated_at            = (Get-Date).ToUniversalTime().ToString("o")
    mode                    = "dry-run"
    root_path               = $Root
    roadmap_path            = $RoadmapPath
    roadmap_name            = [string]$Roadmap.roadmap_name
    selected_task           = $SelectedTask
    branch_name             = $BranchName
    repo_backup_manifest    = $RepoBackup
    volume_backup_manifest   = $VolumeBackup
    required_tests          = if ($SelectedTask) { @($SelectedTask.required_tests) } else { @() }
    stop_conditions         = if ($SelectedTask) { @($SelectedTask.stop_conditions) } else { @() }
    safety_gates            = @(
        "Dry-run only",
        "No secrets",
        "No auto-approval",
        "No auto-push",
        "No queue deletion"
    )
    next_action             = "Human review required before branch creation or execution."
}

$WorkPacketPath = Join-Path $NightlyDir "work-packet.json"
$SummaryPath = Join-Path $NightlyDir "summary.md"
$WorkPacket | ConvertTo-Json -Depth 30 | Set-Content -Path $WorkPacketPath -Encoding UTF8

$SummaryLines = @(
    "# PDA Nightly Build Orchestrator Summary"
    ""
    "- Mode: dry-run"
    "- Roadmap: $RoadmapPath"
    "- Selected task: $(if ($SelectedTaskId) { "$SelectedTaskId - $SelectedTaskTitle" } else { '(none)' })"
    "- Proposed branch: $BranchName"
    "- Repo backup manifest: $($RepoBackup.manifest_path)"
    "- Volume backup manifest: $($VolumeBackup.manifest_path)"
    "- Work packet: $WorkPacketPath"
    "- Next action: Human review required before branch creation or execution."
)
$SummaryLines | Set-Content -Path $SummaryPath -Encoding UTF8

$Result = [pscustomobject]@{
    status                  = "pass"
    mode                    = "dry-run"
    roadmap_path            = $RoadmapPath
    roadmap_name            = [string]$Roadmap.roadmap_name
    selected_task           = $SelectedTask
    selected_task_id        = $SelectedTaskId
    selected_task_title     = $SelectedTaskTitle
    branch_name             = $BranchName
    repo_backup_manifest    = $RepoBackup
    volume_backup_manifest  = $VolumeBackup
    work_packet_path        = $WorkPacketPath
    summary_path            = $SummaryPath
    next_action             = "Human review required before branch creation or execution."
    safety_gates            = @(
        "Dry-run only",
        "No secrets",
        "No auto-approval",
        "No auto-push",
        "No queue deletion"
    )
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 30
    return
}

Write-Host "[OK] PDA nightly build orchestrator dry-run complete."
Write-Host ("Selected task   : {0}" -f $(if ($SelectedTaskId) { "$SelectedTaskId - $SelectedTaskTitle" } else { "(none)" }))
Write-Host ("Branch          : {0}" -f $BranchName)
Write-Host ("Work packet     : {0}" -f $WorkPacketPath)
Write-Host ("Summary         : {0}" -f $SummaryPath)
Write-Host ("Repo manifest   : {0}" -f $RepoBackup.manifest_path)
Write-Host ("Volume manifest : {0}" -f $VolumeBackup.manifest_path)
