param(
    [Parameter(Mandatory=$false)]
    [int]$StaleMinutes = 5
)

$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$HeartbeatDir = Join-Path $Root "PDA-Logs\heartbeats"

Write-Host "[PDA WORKER HEARTBEATS]"

if (-not (Test-Path $HeartbeatDir)) {
    Write-Host "No heartbeat directory found."
    exit 0
}

$Now = Get-Date
$Files = Get-ChildItem $HeartbeatDir -File -Filter "*-heartbeat.json" -ErrorAction SilentlyContinue
$Rows = @()

if ($Files.Count -eq 0) {
    Write-Host "No heartbeat files found."
    exit 0
}

foreach ($file in $Files) {
    try {
        $hb = Get-Content $file.FullName -Raw | ConvertFrom-Json
        $hbTime = [datetime]$hb.heartbeat_at
        $Age = New-TimeSpan -Start $hbTime -End $Now
        $State = if ($Age.TotalMinutes -gt $StaleMinutes) { "STALE" } else { "OK" }

        $ProcessLive = $false
        if ($hb.process_id) {
            $ProcessLive = $null -ne (Get-Process -Id $hb.process_id -ErrorAction SilentlyContinue)
        }

        $Rows += [pscustomobject]@{
            Worker = $hb.worker_name
            Status = $hb.status
            PID = $hb.process_id
            ProcessLive = $ProcessLive
            HeartbeatAgeMinutes = [math]::Round($Age.TotalMinutes, 2)
            State = $State
            LastHeartbeat = $hb.heartbeat_at
        }
    } catch {
        $Rows += [pscustomobject]@{
            Worker = $file.BaseName
            Status = "parse-error"
            PID = ""
            ProcessLive = $false
            HeartbeatAgeMinutes = ""
            State = "ERROR"
            LastHeartbeat = ""
        }
    }
}

$Rows | Format-Table -AutoSize
