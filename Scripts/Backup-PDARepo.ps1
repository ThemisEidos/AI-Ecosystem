[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

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
    throw "Unattended repo backup is disabled in PDA Nightly Build Orchestrator v1."
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $Root "PDA-Backups\nightly-build\$(Get-Date -Format 'yyyyMMdd-HHmmss')"
}

$ManifestDir = Join-Path $OutputRoot "manifests"
$ManifestPath = Join-Path $ManifestDir "repo-backup-manifest.json"
New-Item -ItemType Directory -Force -Path $ManifestDir | Out-Null

$GitBranch = ""
$GitCommit = ""
$WorktreeStatus = @()
try {
    $GitBranch = [string](& git -C $Root branch --show-current 2>$null).Trim()
    $GitCommit = [string](& git -C $Root rev-parse HEAD 2>$null).Trim()
    $WorktreeStatus = @(& git -C $Root status --short 2>$null)
}
catch {
    $GitBranch = ""
    $GitCommit = ""
    $WorktreeStatus = @()
}

$TrackedFiles = @()
try {
    $TrackedFiles = @(& git -C $Root ls-files 2>$null)
}
catch {
    $TrackedFiles = @()
}

$Manifest = [pscustomobject]@{
    status                = "pass"
    backup_type           = "repo"
    dry_run               = $true
    created_at            = (Get-Date).ToUniversalTime().ToString("o")
    root_path             = $Root
    output_root           = $OutputRoot
    manifest_path         = $ManifestPath
    source_branch         = $GitBranch
    source_commit         = $GitCommit
    worktree_clean        = (@($WorktreeStatus).Count -eq 0)
    tracked_file_count    = @($TrackedFiles).Count
    worktree_status_lines  = @($WorktreeStatus)
    planned_archive_path   = Join-Path $OutputRoot "repo-backup.zip"
    included_paths        = @(
        "Roadmap/PDA-Roadmap.json",
        "Scripts/Invoke-PDABuildOrchestrator.ps1",
        "Scripts/Start-PDANightlyBuild.ps1",
        "Scripts/Backup-PDARepo.ps1",
        "Scripts/Backup-PDAVolumes.ps1",
        "Scripts/Test-PDABuildOrchestrator.ps1"
    )
    stop_conditions        = @(
        "No writes in dry-run mode",
        "No secrets",
        "No auto-commit",
        "No auto-push"
    )
}

$Manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $ManifestPath -Encoding UTF8

if ($AsJson) {
    $Manifest | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] Repo backup manifest created:"
Write-Host $ManifestPath
Write-Host ("Branch          : {0}" -f $(if ($GitBranch) { $GitBranch } else { "(unknown)" }))
Write-Host ("Commit          : {0}" -f $(if ($GitCommit) { $GitCommit } else { "(unknown)" }))
Write-Host ("Tracked files   : {0}" -f $Manifest.tracked_file_count)
Write-Host ("Worktree clean  : {0}" -f $Manifest.worktree_clean)
