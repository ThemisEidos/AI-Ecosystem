$QueueRoot = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Tasks"

$PendingPath   = Join-Path $QueueRoot "pending"
$RunningPath   = Join-Path $QueueRoot "running"
$CompletedPath = Join-Path $QueueRoot "completed"
$FailedPath    = Join-Path $QueueRoot "failed"

$Dispatcher = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\dispatch-pda-command.ps1"

$Tasks = Get-ChildItem $PendingPath -Filter *.json

foreach ($TaskFile in $Tasks) {

    $RunningTask = Join-Path $RunningPath $TaskFile.Name

    try {
        $Task = Get-Content $TaskFile.FullName | ConvertFrom-Json
        $Task | Add-Member -NotePropertyName status -NotePropertyValue "running" -Force
        $Task | ConvertTo-Json -Depth 10 | Set-Content $TaskFile.FullName -Encoding UTF8

        Move-Item $TaskFile.FullName $RunningTask -Force

        pwsh $Dispatcher -TaskFile $RunningTask

        $Task = Get-Content $RunningTask | ConvertFrom-Json
        $Task | Add-Member -NotePropertyName status -NotePropertyValue "completed" -Force
        $Task | ConvertTo-Json -Depth 10 | Set-Content $RunningTask -Encoding UTF8

        Move-Item $RunningTask (Join-Path $CompletedPath $TaskFile.Name) -Force
    }
    catch {
        if (Test-Path $RunningTask) {
            $Task = Get-Content $RunningTask | ConvertFrom-Json
            $Task | Add-Member -NotePropertyName status -NotePropertyValue "failed" -Force
            $Task | Add-Member -NotePropertyName error -NotePropertyValue $_.Exception.Message -Force
            $Task | ConvertTo-Json -Depth 10 | Set-Content $RunningTask -Encoding UTF8
            Move-Item $RunningTask (Join-Path $FailedPath $TaskFile.Name) -Force
        }
    }
}


pwsh "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Update-PDAArtifactIndex.ps1"
Write-Host "Queue processing complete."

