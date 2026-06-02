# stop-pda.ps1

Write-Host ""
Write-Host "Stopping PDA containers..." -ForegroundColor Yellow

Push-Location $PSScriptRoot
docker compose down
Pop-Location

Write-Host ""
Write-Host "[OK] PDA stopped." -ForegroundColor Green
