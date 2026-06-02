$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$QueueRoot = Join-Path $Root "PDA-Tasks"
$ResultsDir = Join-Path $QueueRoot "results"
$TelemetryDir = Join-Path $Root "PDA-Logs\telemetry"
New-Item -ItemType Directory -Force -Path $TelemetryDir | Out-Null

$Folders = @{
    pending = Join-Path $QueueRoot "pending"
    running = Join-Path $QueueRoot "running"
    completed = Join-Path $QueueRoot "completed"
    failed = Join-Path $QueueRoot "failed"
    results = $ResultsDir
}

$Counts = @{}
foreach ($key in $Folders.Keys) {
    $path = $Folders[$key]
    if (Test-Path $path) {
        $Counts[$key] = @(Get-ChildItem $path -File -ErrorAction SilentlyContinue).Count
    } else {
        $Counts[$key] = 0
    }
}

function Get-LatestFileInfo {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return $null }

    $file = Get-ChildItem $Path -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $file) { return $null }

    return [pscustomobject]@{
        name = $file.Name
        path = $file.FullName
        last_write = $file.LastWriteTime.ToString("s")
    }
}

$Latest = @{
    pending = Get-LatestFileInfo $Folders.pending
    running = Get-LatestFileInfo $Folders.running
    completed = Get-LatestFileInfo $Folders.completed
    failed = Get-LatestFileInfo $Folders.failed
    result = Get-LatestFileInfo $Folders.results
}

$WorkerStatus = $null
$WorkerStatusPath = Join-Path $Root "PDA-Logs\workers\pda-worker-state.json"
if (Test-Path $WorkerStatusPath) {
    try {
        $WorkerStatus = Get-Content $WorkerStatusPath -Raw | ConvertFrom-Json
    } catch {
        $WorkerStatus = $null
    }
}

$Telemetry = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    queue_root = $QueueRoot
    counts = $Counts
    latest = $Latest
    worker_state = $WorkerStatus
}

$OutPath = Join-Path $TelemetryDir "pda-queue-telemetry.json"
$Telemetry | ConvertTo-Json -Depth 12 | Set-Content $OutPath -Encoding UTF8

Write-Host "[PDA QUEUE TELEMETRY]"
Write-Host "pending   : $($Counts.pending)"
Write-Host "running   : $($Counts.running)"
Write-Host "completed : $($Counts.completed)"
Write-Host "failed    : $($Counts.failed)"
Write-Host "results   : $($Counts.results)"
Write-Host ""
Write-Host "[OK] Telemetry written:"
Write-Host $OutPath
