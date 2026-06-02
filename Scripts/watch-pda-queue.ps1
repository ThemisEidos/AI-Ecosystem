# PDA Queue Watcher

$QueueScript = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\process-pda-queue.ps1"

$PendingPath = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Tasks\pending"

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
