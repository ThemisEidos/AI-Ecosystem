$Root = Split-Path $PSScriptRoot -Parent

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

. (Join-Path $Root "Scripts\PDA_TaskOntology.ps1")

New-Item -ItemType Directory -Force -Path $Queued, $Running, $Completed, $Failed, $Results | Out-Null

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
    param([object]$Object, [string]$Name, [object]$Value)

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    }
    else {
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

            $RunningPath = Join-Path $Running $TaskFile.Name
            Move-Item $TaskFile.FullName $RunningPath -Force

            $Task = Get-Content $RunningPath -Raw | ConvertFrom-Json
            Set-JsonProperty $Task "status" "running"
            Set-JsonProperty $Task "started" ((Get-Date).ToUniversalTime().ToString("o"))
            Set-JsonProperty $Task "assigned_worker" $DispatchContext.assigned_worker
            Set-JsonProperty $Task "routing_surface" $DispatchContext.routing_surface
            Set-JsonProperty $Task "task_type" $DispatchContext.task_type
            Set-JsonProperty $Task "intent" $DispatchContext.intent
            $Task | ConvertTo-Json -Depth 20 | Set-Content -Path $RunningPath -Encoding UTF8

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

            $Task | ConvertTo-Json -Depth 20 | Set-Content -Path $RunningPath -Encoding UTF8

            if ($Result.status -eq "success") {
                Move-Item $RunningPath (Join-Path $Completed $TaskFile.Name) -Force
                Write-Host "[COMPLETED] $($Task.task_id)"
            }
            else {
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
            elseif (Test-Path $TaskFile.FullName) {
                Move-Item $TaskFile.FullName (Join-Path $Failed $TaskFile.Name) -Force
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
