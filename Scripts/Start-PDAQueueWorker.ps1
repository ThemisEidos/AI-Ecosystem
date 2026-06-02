$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"

$QueueRoot = Join-Path $Root "PDA-Tasks"

# Deprecated legacy queue root:
# Tasks\queued / Tasks\running / Tasks\completed / Tasks\failed / Tasks\results
# are retained only for read-only migration support and should not be written
# to by canonical queue processing.
$LegacyQueueRoot = Join-Path $Root "Tasks"

$Queued    = Join-Path $QueueRoot "pending"
$Running   = Join-Path $QueueRoot "running"
$Completed = Join-Path $QueueRoot "completed"
$Failed    = Join-Path $QueueRoot "failed"
$Results   = Join-Path $QueueRoot "results"

New-Item -ItemType Directory -Force -Path $Queued,$Running,$Completed,$Failed,$Results | Out-Null

$TranscriptPath = $env:PDA_QUEUE_WORKER_LOG
$TranscriptStarted = $false
if ($TranscriptPath) {
    try {
        Start-Transcript -Path $TranscriptPath -Append | Out-Null
        $TranscriptStarted = $true
    }
    catch {}
}

function Set-JsonProperty {
    param([object]$Object,[string]$Name,[object]$Value)

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

Write-Host "=== PDA QUEUE WORKER ACTIVE ==="

try {
    while ($true) {
        $TaskFile = Get-ChildItem $Queued -Filter *.json -ErrorAction SilentlyContinue |
            Sort-Object CreationTime |
            Select-Object -First 1

        if (-not $TaskFile) {
            Start-Sleep -Seconds 3
            continue
        }

        $RunningPath = $null

        try {
            $RunningPath = Join-Path $Running $TaskFile.Name
            Move-Item $TaskFile.FullName $RunningPath -Force

            $Task = Get-Content $RunningPath -Raw | ConvertFrom-Json

            Set-JsonProperty $Task "status" "running"
            Set-JsonProperty $Task "started" ((Get-Date).ToUniversalTime().ToString("o"))

            $Task | ConvertTo-Json -Depth 20 | Set-Content $RunningPath -Encoding UTF8

            Write-Host "`n[RUNNING] $($Task.task_id)"
            Write-Host "Command: $($Task.command)"
            Write-Host "Worker:  $($Task.assigned_worker)"

            $ResultJson = & "$Root\Scripts\Invoke-PDAWorker.ps1" -TaskPath $RunningPath
            $Result = $ResultJson | ConvertFrom-Json

            $ResultPath = Join-Path $Results "$($Task.task_id)-result.json"
            $Result | ConvertTo-Json -Depth 20 | Set-Content $ResultPath -Encoding UTF8

            Set-JsonProperty $Task "status" $Result.status
            Set-JsonProperty $Task "completed" ((Get-Date).ToUniversalTime().ToString("o"))
            Set-JsonProperty $Task "result_path" $ResultPath

            $Task | ConvertTo-Json -Depth 20 | Set-Content $RunningPath -Encoding UTF8

            if ($Result.status -eq "success") {
                Move-Item $RunningPath (Join-Path $Completed $TaskFile.Name) -Force
                Write-Host "[COMPLETED] $($Task.task_id)"
            } else {
                Move-Item $RunningPath (Join-Path $Failed $TaskFile.Name) -Force
                Write-Host "[FAILED] $($Task.task_id)"
            }
        }
        catch {
            Write-Host "[FAILED] $($TaskFile.Name)"
            Write-Host $_.Exception.Message

            if ($RunningPath -and (Test-Path $RunningPath)) {
                Move-Item $RunningPath (Join-Path $Failed $TaskFile.Name) -Force
            }
        }
    }
}
finally {
    if ($TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {}
    }
}
