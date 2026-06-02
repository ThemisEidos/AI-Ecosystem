param(
    [Parameter(Mandatory=$true)]
    [string]$WorkerName,

    [Parameter(Mandatory=$false)]
    [int]$ProcessId = $PID,

    [Parameter(Mandatory=$false)]
    [string]$Status = "running"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$HeartbeatDir = Join-Path $Root "PDA-Logs\heartbeats"
New-Item -ItemType Directory -Force -Path $HeartbeatDir | Out-Null

$HeartbeatPath = Join-Path $HeartbeatDir "$WorkerName-heartbeat.json"

$Heartbeat = [pscustomobject]@{
    worker_name = $WorkerName
    process_id = $ProcessId
    status = $Status
    heartbeat_at = (Get-Date).ToString("s")
    host = $env:COMPUTERNAME
    user = $env:USERNAME
}

$Heartbeat | ConvertTo-Json -Depth 6 | Set-Content $HeartbeatPath -Encoding UTF8

Write-Host "[OK] Heartbeat written: $HeartbeatPath"
