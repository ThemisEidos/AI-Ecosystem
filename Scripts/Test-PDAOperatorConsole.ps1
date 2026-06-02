$ErrorActionPreference = "Stop"

Write-Host "[*] Testing PDA Operator Console..."

$Root = Split-Path $PSScriptRoot -Parent
$DashboardPath = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\PDA Operator Console.md"
$TelemetryPath = Join-Path $Root "PDA-Logs\telemetry\pda-queue-telemetry.json"

pwsh -NoProfile -File (Join-Path $PSScriptRoot "Get-PDAQueueTelemetry.ps1")
pwsh -NoProfile -File (Join-Path $PSScriptRoot "Update-PDAOperatorConsole.ps1")

if (-not (Test-Path $TelemetryPath)) {
    throw "Telemetry file missing: $TelemetryPath"
}

if (-not (Test-Path $DashboardPath)) {
    throw "Operator console missing: $DashboardPath"
}

Write-Host "[OK] Operator console test passed."
Write-Host $DashboardPath
