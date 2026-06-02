param(
    [int]$ShutdownWaitSeconds = 10
)

$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"
$WorkerRoot = Join-Path $Root "PDA-Logs\workers"
$ControlLogFile = Join-Path $WorkerRoot "pda-worker-control.log"
$LogFile = Join-Path $WorkerRoot "pda-worker.log"
$IntakeLogFile = Join-Path $WorkerRoot "pda-reporter-intake.log"
$MultiAgentLogFile = Join-Path $WorkerRoot "pda-multiagent-intake.log"
$PidFile = Join-Path $WorkerRoot "pda-worker.pid"
$IntakePidFile = Join-Path $WorkerRoot "pda-reporter-intake.pid"
$MultiAgentPidFile = Join-Path $WorkerRoot "pda-multiagent-intake.pid"
$StateFile = Join-Path $WorkerRoot "pda-worker-state.json"
$IntakeStateFile = Join-Path $WorkerRoot "pda-reporter-intake-state.json"
$MultiAgentStateFile = Join-Path $WorkerRoot "pda-multiagent-intake-state.json"
$ScriptMarker = "Start-PDAQueueWorker.ps1"
$IntakeScriptMarker = "Start-PDAReporterIntakeWatcher.ps1"
$MultiAgentScriptMarker = "Start-PDAMultiAgentIntakeWatcher.ps1"

New-Item -ItemType Directory -Force -Path $WorkerRoot | Out-Null

function Write-WorkerLog {
    param([string]$Message)

    $Line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $ControlLogFile -Value $Line -Encoding UTF8
    Write-Host $Line
}

function Set-StateProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Get-TrackedWorkerProcesses {
    param([string]$TrackedPidFile, [string]$Marker)

    $Processes = @()

    if (Test-Path $TrackedPidFile) {
        $StoredPidText = (Get-Content $TrackedPidFile -Raw).Trim()
        if ($StoredPidText -match '^\d+$') {
            $PidProcess = Get-Process -Id ([int]$StoredPidText) -ErrorAction SilentlyContinue
            if ($PidProcess) {
                $Processes += $PidProcess
            }
        }
    }

    $ScriptPattern = "(-File\s+|/File\s+).*$([regex]::Escape($Marker))"

    $Matches = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -in @("pwsh.exe", "powershell.exe") -and
            $_.CommandLine -match $ScriptPattern
        }

    foreach ($Match in $Matches) {
        try {
            $Processes += Get-Process -Id $Match.ProcessId -ErrorAction SilentlyContinue
        }
        catch {}
    }

    $Processes | Where-Object { $_ } | Sort-Object Id -Unique
}

Write-WorkerLog "Persistent PDA worker stop requested."

$QueueProcesses = Get-TrackedWorkerProcesses -TrackedPidFile $PidFile -Marker $ScriptMarker
$IntakeProcesses = Get-TrackedWorkerProcesses -TrackedPidFile $IntakePidFile -Marker $IntakeScriptMarker
$MultiAgentProcesses = Get-TrackedWorkerProcesses -TrackedPidFile $MultiAgentPidFile -Marker $MultiAgentScriptMarker
$Processes = @()
$Processes += @($QueueProcesses)
$Processes += @($IntakeProcesses)
$Processes += @($MultiAgentProcesses)
$Processes = $Processes | Where-Object { $_ } | Sort-Object Id -Unique

if (-not $Processes) {
    Write-WorkerLog "No running worker process found."

    if (Test-Path $PidFile) {
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $IntakePidFile) {
        Remove-Item $IntakePidFile -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $MultiAgentPidFile) {
        Remove-Item $MultiAgentPidFile -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $StateFile) {
        $State = Get-Content $StateFile -Raw | ConvertFrom-Json
        Set-StateProperty $State "status" "stopped"
        Set-StateProperty $State "stopped_at" ((Get-Date).ToUniversalTime().ToString("o"))
        Set-StateProperty $State "control_log" $ControlLogFile
        $State | ConvertTo-Json -Depth 6 | Set-Content -Path $StateFile -Encoding UTF8
    }
    if (Test-Path $IntakeStateFile) {
        $State = Get-Content $IntakeStateFile -Raw | ConvertFrom-Json
        Set-StateProperty $State "status" "stopped"
        Set-StateProperty $State "stopped_at" ((Get-Date).ToUniversalTime().ToString("o"))
        $State | ConvertTo-Json -Depth 6 | Set-Content -Path $IntakeStateFile -Encoding UTF8
    }
    if (Test-Path $MultiAgentStateFile) {
        $State = Get-Content $MultiAgentStateFile -Raw | ConvertFrom-Json
        Set-StateProperty $State "status" "stopped"
        Set-StateProperty $State "stopped_at" ((Get-Date).ToUniversalTime().ToString("o"))
        $State | ConvertTo-Json -Depth 6 | Set-Content -Path $MultiAgentStateFile -Encoding UTF8
    }

    Write-Host "[OK] Worker already stopped."
    exit 0
}

foreach ($Process in $Processes) {
    Write-WorkerLog "Stopping PID $($Process.Id)."
    Stop-Process -Id $Process.Id -ErrorAction SilentlyContinue
}

$Deadline = (Get-Date).AddSeconds($ShutdownWaitSeconds)
while ((Get-TrackedWorkerProcesses).Count -gt 0 -and (Get-Date) -lt $Deadline) {
    Start-Sleep -Seconds 1
}

$Remaining = Get-TrackedWorkerProcesses
if ($Remaining) {
    foreach ($Process in $Remaining) {
        Write-WorkerLog "Force-stopping PID $($Process.Id)."
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    }
}

if (Test-Path $PidFile) {
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}
if (Test-Path $IntakePidFile) {
    Remove-Item $IntakePidFile -Force -ErrorAction SilentlyContinue
}
if (Test-Path $MultiAgentPidFile) {
    Remove-Item $MultiAgentPidFile -Force -ErrorAction SilentlyContinue
}

if (Test-Path $StateFile) {
    $State = Get-Content $StateFile -Raw | ConvertFrom-Json
    Set-StateProperty $State "status" "stopped"
    Set-StateProperty $State "stopped_at" ((Get-Date).ToUniversalTime().ToString("o"))
    Set-StateProperty $State "control_log" $ControlLogFile
    $State | ConvertTo-Json -Depth 6 | Set-Content -Path $StateFile -Encoding UTF8
}
if (Test-Path $IntakeStateFile) {
    $State = Get-Content $IntakeStateFile -Raw | ConvertFrom-Json
    Set-StateProperty $State "status" "stopped"
    Set-StateProperty $State "stopped_at" ((Get-Date).ToUniversalTime().ToString("o"))
    $State | ConvertTo-Json -Depth 6 | Set-Content -Path $IntakeStateFile -Encoding UTF8
}
if (Test-Path $MultiAgentStateFile) {
    $State = Get-Content $MultiAgentStateFile -Raw | ConvertFrom-Json
    Set-StateProperty $State "status" "stopped"
    Set-StateProperty $State "stopped_at" ((Get-Date).ToUniversalTime().ToString("o"))
    $State | ConvertTo-Json -Depth 6 | Set-Content -Path $MultiAgentStateFile -Encoding UTF8
}

Write-WorkerLog "Persistent PDA worker stopped."
Write-Host "[OK] Worker stopped."
