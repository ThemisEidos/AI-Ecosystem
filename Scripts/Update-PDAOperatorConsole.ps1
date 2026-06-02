$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$DashboardPath = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\PDA Operator Console.md"
$TelemetryPath = Join-Path $Root "PDA-Logs\telemetry\pda-queue-telemetry.json"
$RegistryPath = Join-Path $Root "Scripts\PDA_WorkerRegistry.json"

pwsh -NoProfile -File (Join-Path $PSScriptRoot "Get-PDAQueueTelemetry.ps1") | Out-Null

$Telemetry = Get-Content $TelemetryPath -Raw | ConvertFrom-Json

$RegistryText = ""
if (Test-Path $RegistryPath) {
    try {
        $Registry = Get-Content $RegistryPath -Raw | ConvertFrom-Json

        $Workers = if ($Registry.workers) { $Registry.workers } else { $Registry }

        $Rows = foreach ($w in $Workers) {
            "| $($w.command) | $($w.worker_name) | $($w.status) | $($w.routing_surface) | $($w.accepted_input_modes -join ', ') |"
        }

        $RegistryText = @"
## Worker Registry

| Command | Worker | Status | Routing Surface | Input Modes |
|---|---|---|---|---|
$($Rows -join "`n")
"@
    } catch {
        $RegistryText = "## Worker Registry`n`nRegistry parse failed: $($_.Exception.Message)"
    }
}

$LatestCompleted = if ($Telemetry.latest.completed) { $Telemetry.latest.completed.name } else { "None" }
$LatestFailed = if ($Telemetry.latest.failed) { $Telemetry.latest.failed.name } else { "None" }
$LatestResult = if ($Telemetry.latest.result) { $Telemetry.latest.result.name } else { "None" }

$Content = @"
# PDA Operator Console

Generated: $($Telemetry.generated_at)

## Queue Status

| Queue | Count |
|---|---:|
| Pending | $($Telemetry.counts.pending) |
| Running | $($Telemetry.counts.running) |
| Completed | $($Telemetry.counts.completed) |
| Failed | $($Telemetry.counts.failed) |
| Results | $($Telemetry.counts.results) |

## Latest Activity

| Type | Latest |
|---|---|
| Completed Task | $LatestCompleted |
| Failed Task | $LatestFailed |
| Result | $LatestResult |

$RegistryText

## Operator Commands

```powershell
pwsh -File Scripts\Get-PDAStatus.ps1
pwsh -File Scripts\Get-PDAWorkerStatus.ps1
pwsh -File Scripts\Get-PDAQueueTelemetry.ps1
pwsh -File Scripts\Update-PDAOperatorConsole.ps1
pwsh -File Scripts\Start-PDAWorker.ps1
pwsh -File Scripts\Stop-PDAWorker.ps1
```

## Safety Notes

- Category 2 tasks must remain local-only.
- Do not commit runtime data, logs, secrets, or restricted files.
- `/execute` remains dry-run/no-op unless explicitly approved.
- Fabric Category 2 tasks must use local-only model routing.

## Next Improvements

- Retry policy
- Dead-letter queue
- Worker heartbeat details
- Artifact index
- Web dashboard later
"@

$Content | Set-Content $DashboardPath -Encoding UTF8

Write-Host "[OK] PDA Operator Console updated:"
Write-Host $DashboardPath
