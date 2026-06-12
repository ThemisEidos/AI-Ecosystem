$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$QueueRoot = Join-Path $Root "PDA-Tasks"
$PendingPath   = Join-Path $QueueRoot "pending"
$RunningPath   = Join-Path $QueueRoot "running"
$CompletedPath = Join-Path $QueueRoot "completed"
$FailedPath    = Join-Path $QueueRoot "failed"
$Dispatcher = Join-Path $Root "Scripts\dispatch-pda-command.ps1"

. (Join-Path $Root "Scripts\PDA_TaskOntology.ps1")

New-Item -ItemType Directory -Force -Path $PendingPath, $RunningPath, $CompletedPath, $FailedPath | Out-Null

$Tasks = Get-ChildItem $PendingPath -Filter *.json

foreach ($TaskFile in $Tasks) {
    $RunningTask = Join-Path $RunningPath $TaskFile.Name

    try {
        $Task = Get-Content $TaskFile.FullName -Raw | ConvertFrom-Json
        $Command = if ($Task.PSObject.Properties['command']) { [string]$Task.command } else { "" }
        $Classification = if ($Task.PSObject.Properties['classification'] -and -not [string]::IsNullOrWhiteSpace([string]$Task.classification)) {
            [string]$Task.classification
        }
        elseif ($Task.PSObject.Properties['category'] -and -not [string]::IsNullOrWhiteSpace([string]$Task.category)) {
            [string]$Task.category
        }
        else {
            "category_1"
        }
        $Approved = if ($Task.PSObject.Properties['approved']) { [bool]$Task.approved } else { $true }

        $DispatchContext = Resolve-PDATaskDispatchContext -Root $Root -Task $Task -Command $Command -Classification $Classification -Approved $Approved

        if (-not $Task.PSObject.Properties['task_id'] -or [string]::IsNullOrWhiteSpace([string]$Task.task_id)) {
            $Task | Add-Member -NotePropertyName task_id -NotePropertyValue ([guid]::NewGuid().ToString()) -Force
        }

        $Task | Add-Member -NotePropertyName assigned_worker -NotePropertyValue $DispatchContext.assigned_worker -Force
        $Task | Add-Member -NotePropertyName routing_surface -NotePropertyValue $DispatchContext.routing_surface -Force
        $Task | Add-Member -NotePropertyName task_type -NotePropertyValue $DispatchContext.task_type -Force
        $Task | Add-Member -NotePropertyName intent -NotePropertyValue $DispatchContext.intent -Force
        $Task | Add-Member -NotePropertyName status -NotePropertyValue "running" -Force

        $Task | ConvertTo-Json -Depth 10 | Set-Content -Path $TaskFile.FullName -Encoding UTF8
        Move-Item $TaskFile.FullName $RunningTask -Force

        & pwsh -NoProfile -File $Dispatcher -TaskFile $RunningTask

        $Task = Get-Content $RunningTask -Raw | ConvertFrom-Json
        $Task | Add-Member -NotePropertyName status -NotePropertyValue "completed" -Force
        $Task | ConvertTo-Json -Depth 10 | Set-Content -Path $RunningTask -Encoding UTF8

        Move-Item $RunningTask (Join-Path $CompletedPath $TaskFile.Name) -Force
    }
    catch {
        if (Test-Path $RunningTask) {
            $Task = Get-Content $RunningTask -Raw | ConvertFrom-Json
            $Task | Add-Member -NotePropertyName status -NotePropertyValue "failed" -Force
            $Task | Add-Member -NotePropertyName error -NotePropertyValue $_.Exception.Message -Force
            $Task | ConvertTo-Json -Depth 10 | Set-Content -Path $RunningTask -Encoding UTF8
            Move-Item $RunningTask (Join-Path $FailedPath $TaskFile.Name) -Force
        }
        elseif (Test-Path $TaskFile.FullName) {
            $Task = Get-Content $TaskFile.FullName -Raw | ConvertFrom-Json
            $Task | Add-Member -NotePropertyName status -NotePropertyValue "failed" -Force
            $Task | Add-Member -NotePropertyName error -NotePropertyValue $_.Exception.Message -Force
            $Task | ConvertTo-Json -Depth 10 | Set-Content -Path $TaskFile.FullName -Encoding UTF8
            Move-Item $TaskFile.FullName (Join-Path $FailedPath $TaskFile.Name) -Force
        }
    }
}

& pwsh -NoProfile -File (Join-Path $Root "Scripts\Update-PDAArtifactIndex.ps1")
Write-Host "Queue processing complete."
