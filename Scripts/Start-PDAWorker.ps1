param(
    [int]$StartupWaitSeconds = 8,
    [int]$ReporterIntakeStartupWaitSeconds = 8,
    [int]$MultiAgentIntakeStartupWaitSeconds = 8
)

$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"
$WorkerRoot = Join-Path $Root "PDA-Logs\workers"
$ControlLogFile = Join-Path $WorkerRoot "pda-worker-control.log"
$LogFile = Join-Path $WorkerRoot "pda-worker.log"
$PidFile = Join-Path $WorkerRoot "pda-worker.pid"
$StateFile = Join-Path $WorkerRoot "pda-worker-state.json"
$IntakeControlLogFile = Join-Path $WorkerRoot "pda-reporter-intake-control.log"
$IntakeLogFile = Join-Path $WorkerRoot "pda-reporter-intake.log"
$IntakePidFile = Join-Path $WorkerRoot "pda-reporter-intake.pid"
$IntakeStateFile = Join-Path $WorkerRoot "pda-reporter-intake-state.json"
$MultiAgentControlLogFile = Join-Path $WorkerRoot "pda-multiagent-intake-control.log"
$MultiAgentLogFile = Join-Path $WorkerRoot "pda-multiagent-intake.log"
$MultiAgentPidFile = Join-Path $WorkerRoot "pda-multiagent-intake.pid"
$MultiAgentStateFile = Join-Path $WorkerRoot "pda-multiagent-intake-state.json"
$QueueWorkerScript = Join-Path $Root "Scripts\Start-PDAQueueWorker.ps1"
$IntakeWatcherScript = Join-Path $Root "Scripts\Start-PDAReporterIntakeWatcher.ps1"
$MultiAgentWatcherScript = Join-Path $Root "Scripts\Start-PDAMultiAgentIntakeWatcher.ps1"

New-Item -ItemType Directory -Force -Path $WorkerRoot | Out-Null

function Write-WorkerLog {
    param([string]$Message)

    $Line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $ControlLogFile -Value $Line -Encoding UTF8
    Write-Host $Line
}

function Get-TrackedWorkerProcess {
    param(
        [int]$ProcessId = 0,
        [string]$ScriptMarker = ""
    )

    if ($ProcessId -gt 0) {
        $Process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($Process) {
            return $Process
        }
    }

    if ([string]::IsNullOrWhiteSpace($ScriptMarker)) {
        return $null
    }

    $ScriptPattern = "(-File\s+|/File\s+).*$([regex]::Escape($ScriptMarker))"

    $Matches = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -in @("pwsh.exe", "powershell.exe") -and
            $_.CommandLine -match $ScriptPattern
        } |
        Sort-Object CreationDate -Descending

    if ($Matches) {
        return $Matches[0]
    }

    return $null
}

Write-WorkerLog "Persistent PDA worker start requested."

function Start-TrackedWorker {
    param(
        [string]$Label,
        [string]$ScriptPath,
        [string]$ScriptMarker,
        [string]$LogPath,
        [string]$PidPath,
        [string]$StatePath,
        [string]$LogEnvName,
        [int]$WaitSeconds
    )

    $ExistingProcess = $null
    if (Test-Path $PidPath) {
        $StoredPidText = (Get-Content $PidPath -Raw).Trim()
        if ($StoredPidText -match '^\d+$') {
            $ExistingProcess = Get-TrackedWorkerProcess -ProcessId ([int]$StoredPidText) -ScriptMarker $ScriptMarker
        }
    }

    if (-not $ExistingProcess) {
        $ExistingProcess = Get-TrackedWorkerProcess -ScriptMarker $ScriptMarker
    }

    if ($ExistingProcess) {
        $ExistingPid = if ($ExistingProcess.PSObject.Properties.Name -contains 'Id') { $ExistingProcess.Id } else { $ExistingProcess.ProcessId }
        Write-WorkerLog "$Label already running with PID $ExistingPid."

        $State = [ordered]@{
            status = "running"
            pid = $ExistingPid
            started_at = if ($ExistingProcess.PSObject.Properties.Name -contains 'StartTime') { $ExistingProcess.StartTime.ToUniversalTime().ToString("o") } else { $null }
            control_log = $ControlLogFile
            log_file = $LogPath
            pid_file = $PidPath
            script = $ScriptPath
        }
        $State | ConvertTo-Json -Depth 6 | Set-Content -Path $StatePath -Encoding UTF8
        Set-Content -Path $PidPath -Value $ExistingPid -Encoding UTF8

        return [ordered]@{
            label = $Label
            status = "running"
            pid = $ExistingPid
            log = $LogPath
        }
    }

    Write-WorkerLog "Launching $Label."
    Set-Item -Path ("Env:{0}" -f $LogEnvName) -Value $LogPath
    $Process = Start-Process -FilePath "pwsh.exe" `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptPath`"") `
        -WindowStyle Hidden `
        -WorkingDirectory $Root `
        -PassThru
    Remove-Item ("Env:{0}" -f $LogEnvName) -ErrorAction SilentlyContinue

    Start-Sleep -Seconds $WaitSeconds

    $LaunchConfirmed = [bool](Get-TrackedWorkerProcess -ProcessId $Process.Id -ScriptMarker $ScriptMarker)

    $State = [ordered]@{
        status = if ($LaunchConfirmed) { "running" } else { "starting" }
        pid = $Process.Id
        started_at = (Get-Date).ToUniversalTime().ToString("o")
        control_log = $ControlLogFile
        log_file = $LogPath
        pid_file = $PidPath
        script = $ScriptPath
    }

    $State | ConvertTo-Json -Depth 6 | Set-Content -Path $StatePath -Encoding UTF8
    Set-Content -Path $PidPath -Value $Process.Id -Encoding UTF8

    if ($LaunchConfirmed) {
        Write-WorkerLog "$Label started with PID $($Process.Id)."
    } else {
        Write-WorkerLog "$Label PID $($Process.Id) recorded; confirmation deferred to status check."
    }

    return [ordered]@{
        label = $Label
        status = if ($LaunchConfirmed) { "running" } else { "starting" }
        pid = $Process.Id
        log = $LogPath
    }
}

$QueueResult = Start-TrackedWorker -Label "Queue worker" -ScriptPath $QueueWorkerScript -ScriptMarker "Start-PDAQueueWorker.ps1" -LogPath $LogFile -PidPath $PidFile -StatePath $StateFile -LogEnvName "PDA_QUEUE_WORKER_LOG" -WaitSeconds $StartupWaitSeconds
$ReporterIntakeResult = Start-TrackedWorker -Label "Reporter intake watcher" -ScriptPath $IntakeWatcherScript -ScriptMarker "Start-PDAReporterIntakeWatcher.ps1" -LogPath $IntakeLogFile -PidPath $IntakePidFile -StatePath $IntakeStateFile -LogEnvName "PDA_REPORTER_INTAKE_LOG" -WaitSeconds $ReporterIntakeStartupWaitSeconds
$MultiAgentResult = Start-TrackedWorker -Label "Multi-agent intake watcher" -ScriptPath $MultiAgentWatcherScript -ScriptMarker "Start-PDAMultiAgentIntakeWatcher.ps1" -LogPath $MultiAgentLogFile -PidPath $MultiAgentPidFile -StatePath $MultiAgentStateFile -LogEnvName "PDA_MULTIAGENT_INTAKE_LOG" -WaitSeconds $MultiAgentIntakeStartupWaitSeconds

Write-Host "Queue PID: $($QueueResult.pid)"
Write-Host "Queue Log: $LogFile"
Write-Host "Reporter Intake PID: $($ReporterIntakeResult.pid)"
Write-Host "Intake Log: $IntakeLogFile"
Write-Host "Multi-Agent Intake PID: $($MultiAgentResult.pid)"
Write-Host "Multi-Agent Intake Log: $MultiAgentLogFile"
