$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"

$Required = @(
    "workers.json",
    "Scripts\PDA_WorkerContract.schema.json",
    "Scripts\PDA_TaskRequest.schema.json",
    "Scripts\PDA_MultiAgentTask.schema.json",
    "Scripts\New-PDATask.ps1",
    "Scripts\Get-PDATaskStatus.ps1",
    "Scripts\Invoke-PDAReporterWorker.ps1",
    "Scripts\Start-PDAMultiAgentIntakeWatcher.ps1",
    "Scripts\Process-PDACommandStagedTasks.ps1",
    "Scripts\Invoke-PDAResearchWorker.ps1",
    "Scripts\Invoke-PDAExecuteWorker.ps1",
    "PDA-Tasks\pending",
    "PDA-Tasks\running",
    "PDA-Tasks\completed",
    "PDA-Tasks\failed",
    "PDA-Tasks\results"
)

# Deprecated legacy queue directories are not required for a passing check.
$LegacyOptional = @(
    "Tasks\queued",
    "Tasks\running",
    "Tasks\completed",
    "Tasks\failed",
    "Tasks\results"
)

foreach ($Item in $Required) {
    $Path = Join-Path $Root $Item
    if (Test-Path $Path) {
        Write-Host "[OK] $Item"
    } else {
        Write-Host "[MISSING] $Item"
    }
}

Write-Host ""
Write-Host "Optional legacy queue paths:"
foreach ($Item in $LegacyOptional) {
    $Path = Join-Path $Root $Item
    if (Test-Path $Path) {
        Write-Host "[LEGACY] $Item"
    }
}
