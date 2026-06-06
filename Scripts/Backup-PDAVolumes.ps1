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
    throw "Unattended Docker volume backup is disabled in PDA Nightly Build Orchestrator v1."
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $Root "PDA-Backups\nightly-build\$(Get-Date -Format 'yyyyMMdd-HHmmss')"
}

$ManifestDir = Join-Path $OutputRoot "manifests"
$ManifestPath = Join-Path $ManifestDir "volume-backup-manifest.json"
New-Item -ItemType Directory -Force -Path $ManifestDir | Out-Null

function Get-PDAVolumeTargets {
    param([string]$RootPath)

    return @(
        [pscustomobject]@{
            volume_name   = "open-webui"
            service_name   = "open-webui"
            mount_path     = "/app/backend/data"
            backup_format  = "tar"
            is_external    = $true
        }
        [pscustomobject]@{
            volume_name   = "n8n-data"
            service_name   = "n8n"
            mount_path     = "/home/node/.n8n"
            backup_format  = "tar"
            is_external    = $false
        }
    )
}

$DockerAvailable = [bool](Get-Command docker -ErrorAction SilentlyContinue)
$DetectedVolumes = @()
if ($DockerAvailable) {
    try {
        $ExistingVolumes = @(& docker volume ls --format "{{.Name}}" 2>$null)
        $DetectedVolumes = Get-PDAVolumeTargets -RootPath $Root | ForEach-Object {
            $VolumeName = [string]$_.volume_name
            $_ | Add-Member NoteProperty exists ($ExistingVolumes -contains $VolumeName) -Force
            $_ | Add-Member NoteProperty planned_backup_path (Join-Path $OutputRoot ("volume-" + $VolumeName + ".tar")) -Force
            $_
        }
    }
    catch {
        $DetectedVolumes = Get-PDAVolumeTargets -RootPath $Root | ForEach-Object {
            $_ | Add-Member NoteProperty exists $false -Force
            $_ | Add-Member NoteProperty planned_backup_path (Join-Path $OutputRoot ("volume-" + [string]$_.volume_name + ".tar")) -Force
            $_
        }
    }
}
else {
    $DetectedVolumes = Get-PDAVolumeTargets -RootPath $Root | ForEach-Object {
        $_ | Add-Member NoteProperty exists "unknown" -Force
        $_ | Add-Member NoteProperty planned_backup_path (Join-Path $OutputRoot ("volume-" + [string]$_.volume_name + ".tar")) -Force
        $_
    }
}

$Manifest = [pscustomobject]@{
    status              = "pass"
    backup_type         = "docker_volume"
    dry_run             = $true
    created_at          = (Get-Date).ToUniversalTime().ToString("o")
    root_path           = $Root
    output_root         = $OutputRoot
    manifest_path       = $ManifestPath
    docker_available    = $DockerAvailable
    volume_count        = @($DetectedVolumes).Count
    volumes             = @($DetectedVolumes)
    stop_conditions     = @(
        "No writes in dry-run mode",
        "No secrets",
        "No volume deletion",
        "No auto-approval"
    )
}

$Manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $ManifestPath -Encoding UTF8

if ($AsJson) {
    $Manifest | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] Docker volume backup manifest created:"
Write-Host $ManifestPath
Write-Host ("Volume count    : {0}" -f $Manifest.volume_count)
Write-Host ("Docker available: {0}" -f $DockerAvailable)
