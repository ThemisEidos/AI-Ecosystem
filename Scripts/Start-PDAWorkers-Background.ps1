$Scripts = @(
    (Join-Path $PSScriptRoot "watch-pda-queue.ps1"),
    (Join-Path $PSScriptRoot "Start-GeminiWorker.ps1"),
    (Join-Path $PSScriptRoot "Start-ResearchWorker.ps1"),
    (Join-Path $PSScriptRoot "Start-PlannerWorker.ps1")
)

foreach ($Script in $Scripts) {
    Start-Process pwsh -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$Script`"" -WindowStyle Minimized
}

Write-Host "PDA background workers launched."
