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
$QueueRoot = Join-Path $Root "PDA-Tasks"
$RegistryPath = Join-Path $Root "Scripts\PDA_WorkerRegistry.json"

function Get-TrackedWorkerProcess {
    param([int]$ProcessId = 0, [string]$ScriptMarker = "")

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

function Get-QueueCount {
    param([string]$Path)

    if (Test-Path $Path) {
        return @(Get-ChildItem $Path -Filter *.json -ErrorAction SilentlyContinue).Count
    }

    return 0
}

$State = $null
if (Test-Path $StateFile) {
    try {
        $State = Get-Content $StateFile -Raw | ConvertFrom-Json
    }
    catch {}
}

$TrackedProcess = $null
if ($State -and $State.pid) {
    $TrackedProcess = Get-TrackedWorkerProcess -ProcessId ([int]$State.pid) -ScriptMarker "Start-PDAQueueWorker.ps1"
}
if (-not $TrackedProcess) {
    $TrackedProcess = Get-TrackedWorkerProcess -ScriptMarker "Start-PDAQueueWorker.ps1"
}

$Status = if ($TrackedProcess) { "running" } elseif ($State -and $State.status) { $State.status } else { "stopped" }
$WorkerPid = if ($TrackedProcess) {
    if ($TrackedProcess.PSObject.Properties.Name -contains 'Id') { $TrackedProcess.Id } else { $TrackedProcess.ProcessId }
} elseif ($State -and $State.pid) {
    $State.pid
} else {
    $null
}

$QueueCounts = [ordered]@{
    pending   = Get-QueueCount (Join-Path $QueueRoot "pending")
    running   = Get-QueueCount (Join-Path $QueueRoot "running")
    completed = Get-QueueCount (Join-Path $QueueRoot "completed")
    failed    = Get-QueueCount (Join-Path $QueueRoot "failed")
    results   = Get-QueueCount (Join-Path $QueueRoot "results")
}

$IntakeState = $null
if (Test-Path $IntakeStateFile) {
    try {
        $IntakeState = Get-Content $IntakeStateFile -Raw | ConvertFrom-Json
    }
    catch {}
}

$IntakeProcess = $null
if ($IntakeState -and $IntakeState.pid) {
    $IntakeProcess = Get-TrackedWorkerProcess -ProcessId ([int]$IntakeState.pid) -ScriptMarker "Start-PDAReporterIntakeWatcher.ps1"
}
if (-not $IntakeProcess) {
    $IntakeProcess = Get-TrackedWorkerProcess -ScriptMarker "Start-PDAReporterIntakeWatcher.ps1"
}

$IntakeStatus = if ($IntakeProcess) { "running" } elseif ($IntakeState -and $IntakeState.status) { $IntakeState.status } else { "stopped" }
$IntakePid = if ($IntakeProcess) {
    if ($IntakeProcess.PSObject.Properties.Name -contains 'Id') { $IntakeProcess.Id } else { $IntakeProcess.ProcessId }
} elseif ($IntakeState -and $IntakeState.pid) {
    $IntakeState.pid
} else {
    $null
}

$MultiAgentState = $null
if (Test-Path $MultiAgentStateFile) {
    try {
        $MultiAgentState = Get-Content $MultiAgentStateFile -Raw | ConvertFrom-Json
    }
    catch {}
}

$MultiAgentProcess = $null
if ($MultiAgentState -and $MultiAgentState.pid) {
    $MultiAgentProcess = Get-TrackedWorkerProcess -ProcessId ([int]$MultiAgentState.pid) -ScriptMarker "Start-PDAMultiAgentIntakeWatcher.ps1"
}
if (-not $MultiAgentProcess) {
    $MultiAgentProcess = Get-TrackedWorkerProcess -ScriptMarker "Start-PDAMultiAgentIntakeWatcher.ps1"
}

$MultiAgentStatus = if ($MultiAgentProcess) { "running" } elseif ($MultiAgentState -and $MultiAgentState.status) { $MultiAgentState.status } else { "stopped" }
$MultiAgentPid = if ($MultiAgentProcess) {
    if ($MultiAgentProcess.PSObject.Properties.Name -contains 'Id') { $MultiAgentProcess.Id } else { $MultiAgentProcess.ProcessId }
} elseif ($MultiAgentState -and $MultiAgentState.pid) {
    $MultiAgentState.pid
} else {
    $null
}

Write-Host "=== PDA PERSISTENT WORKER STATUS ==="
Write-Host ""
Write-Host ("Status      : {0}" -f $Status)
Write-Host ("PID         : {0}" -f ($WorkerPid ?? "n/a"))
Write-Host ("Script      : {0}" -f (Join-Path $Root "Scripts\Start-PDAQueueWorker.ps1"))
Write-Host ("Log file    : {0}" -f $LogFile)
Write-Host ("Control log : {0}" -f $ControlLogFile)
if ($State -and $State.started_at) {
    Write-Host ("Started at  : {0}" -f $State.started_at)
}
if ($State -and $State.stopped_at) {
    Write-Host ("Stopped at  : {0}" -f $State.stopped_at)
}
Write-Host ""
Write-Host "=== REPORTER INTAKE WATCHER ==="
Write-Host ("Status      : {0}" -f $IntakeStatus)
Write-Host ("PID         : {0}" -f ($IntakePid ?? "n/a"))
Write-Host ("Log file    : {0}" -f $IntakeLogFile)
if ($IntakeState -and $IntakeState.started_at) {
    Write-Host ("Started at  : {0}" -f $IntakeState.started_at)
}
if ($IntakeState -and $IntakeState.stopped_at) {
    Write-Host ("Stopped at  : {0}" -f $IntakeState.stopped_at)
}

Write-Host ""
Write-Host "=== MULTI-AGENT INTAKE WATCHER ==="
Write-Host ("Status      : {0}" -f $MultiAgentStatus)
Write-Host ("PID         : {0}" -f ($MultiAgentPid ?? "n/a"))
Write-Host ("Log file    : {0}" -f $MultiAgentLogFile)
if ($MultiAgentState -and $MultiAgentState.started_at) {
    Write-Host ("Started at  : {0}" -f $MultiAgentState.started_at)
}
if ($MultiAgentState -and $MultiAgentState.stopped_at) {
    Write-Host ("Stopped at  : {0}" -f $MultiAgentState.stopped_at)
}

Write-Host ""
Write-Host "=== PDA-Tasks QUEUE COUNTS ==="
foreach ($Key in $QueueCounts.Keys) {
    Write-Host ("{0,-10}: {1}" -f $Key, $QueueCounts[$Key])
}

if (Test-Path $LogFile) {
    Write-Host ""
    Write-Host "=== RECENT LOG ==="
    Get-Content $LogFile -Tail 12 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
}

if (Test-Path $IntakeLogFile) {
    Write-Host ""
    Write-Host "=== INTAKE LOG ==="
    Get-Content $IntakeLogFile -Tail 12 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
}

if (Test-Path $MultiAgentLogFile) {
    Write-Host ""
    Write-Host "=== MULTI-AGENT INTAKE LOG ==="
    Get-Content $MultiAgentLogFile -Tail 12 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
}

if (Test-Path $ControlLogFile) {
    Write-Host ""
    Write-Host "=== CONTROL LOG ==="
    Get-Content $ControlLogFile -Tail 12 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
}

$Registry = $null
if (Test-Path $RegistryPath) {
    try {
        $Registry = Get-Content $RegistryPath -Raw | ConvertFrom-Json
    }
    catch {}
}

if ($Registry -and $Registry.workers) {
    Write-Host ""
    Write-Host "=== WORKER REGISTRY ==="
    foreach ($Worker in $Registry.workers) {
        $Command = if ($Worker.command) { $Worker.command } else { "internal" }
        $Modes = if ($Worker.accepted_input_modes) { ($Worker.accepted_input_modes -join ", ") } else { "n/a" }
        $Surface = if ($Worker.routing_surface) { $Worker.routing_surface } else { "n/a" }
        $Categories = if ($Worker.category_support) { ($Worker.category_support -join ", ") } else { "n/a" }
        Write-Host ("{0,-12} {1,-18} {2,-12} {3,-14} {4} | {5}" -f $Command, $Worker.worker_name, $Worker.status, $Surface, $Categories, $Modes)
    }
}
