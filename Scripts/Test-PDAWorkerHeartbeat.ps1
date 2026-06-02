$ErrorActionPreference = "Stop"

Write-Host "[*] Testing PDA worker heartbeat..."

pwsh -NoProfile -File (Join-Path $PSScriptRoot "Write-PDAWorkerHeartbeat.ps1") -WorkerName "test-worker" -Status "running"
pwsh -NoProfile -File (Join-Path $PSScriptRoot "Get-PDAWorkerHeartbeatStatus.ps1")

Write-Host "[OK] Heartbeat test completed."
