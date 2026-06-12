# PDA Queue Watcher

$QueueScript = Join-Path $PSScriptRoot "process-pda-queue.ps1"

$PendingPath = Join-Path (Split-Path $PSScriptRoot -Parent) "PDA-Tasks\pending"

Write-Host ""
Write-Host "=== PDA QUEUE WATCHER ACTIVE ==="
Write-Host ""

while ($true) {

    $Tasks = Get-ChildItem $PendingPath -Filter *.json

    if ($Tasks.Count -gt 0) {

        Write-Host ""
        Write-Host "Tasks detected..."
        Write-Host ""

        pwsh $QueueScript
    }

    Start-Sleep -Seconds 10
}
