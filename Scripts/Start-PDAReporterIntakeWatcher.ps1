param(
    [int]$PollIntervalSeconds = 3
)

$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"
$WorkerRoot = Join-Path $Root "PDA-Logs\workers"
$LogFile = Join-Path $WorkerRoot "pda-reporter-intake.log"
$PidFile = Join-Path $WorkerRoot "pda-reporter-intake.pid"
$StateFile = Join-Path $WorkerRoot "pda-reporter-intake-state.json"
$ProcessorScript = Join-Path $Root "Scripts\Process-PDAReporterStagedTasks.ps1"
$StagingRoot = Join-Path $Root "PDA-Tasks\staging\n8n-reporter"

New-Item -ItemType Directory -Force -Path $WorkerRoot, $StagingRoot | Out-Null

function Write-State {
    param([string]$Status)

    $State = [ordered]@{
        status = $Status
        pid = $PID
        started_at = if (Test-Path $PidFile) { (Get-Date).ToUniversalTime().ToString("o") } else { (Get-Date).ToUniversalTime().ToString("o") }
        stopped_at = if ($Status -eq "stopped") { (Get-Date).ToUniversalTime().ToString("o") } else { $null }
        log_file = $LogFile
        pid_file = $PidFile
        script = $PSCommandPath
        staging_root = $StagingRoot
        poll_interval_seconds = $PollIntervalSeconds
    }

    $State | ConvertTo-Json -Depth 6 | Set-Content -Path $StateFile -Encoding UTF8
}

$TranscriptStarted = $false
try {
    Start-Transcript -Path $LogFile -Append | Out-Null
    $TranscriptStarted = $true
}
catch {}

Set-Content -Path $PidFile -Value $PID -Encoding UTF8
Write-State -Status "running"

Write-Host "=== PDA REPORTER INTAKE WATCHER ACTIVE ==="
Write-Host "PID: $PID"
Write-Host "Staging root: $StagingRoot"
Write-Host "Processor: $ProcessorScript"

try {
    while ($true) {
        $StagedFiles = Get-ChildItem -Path $StagingRoot -Filter *.json -ErrorAction SilentlyContinue
        if ($StagedFiles.Count -gt 0) {
            Write-Host ""
            Write-Host "[INTAKE] Reporter staging files detected: $($StagedFiles.Count)"
            Write-Host "[INTAKE] Running staged intake processor..."
            & $ProcessorScript
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }
}
finally {
    Write-State -Status "stopped"
    if (Test-Path $PidFile) {
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    }

    if ($TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {}
    }
}
