$Scripts = @(
    "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\watch-pda-queue.ps1",
    "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Start-GeminiWorker.ps1",
    "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Start-ResearchWorker.ps1",
    "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Start-PlannerWorker.ps1"
)

foreach ($Script in $Scripts) {
    Start-Process pwsh -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$Script`"" -WindowStyle Minimized
}

Write-Host "PDA background workers launched."
