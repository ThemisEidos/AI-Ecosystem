Write-Host "=== PDA WEBHOOK DIAGNOSTIC ==="

Write-Host ""
Write-Host "1. Sender URL:"
$Sender = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Send-PDACommand.ps1"
Select-String -Path $Sender -Pattern "WebhookUrl" -Context 0,1

Write-Host ""
Write-Host "2. n8n container logs mentioning pda-command-router:"
docker logs n8n --tail 200 | Select-String "pda-command-router|webhook|error|Workflow"

Write-Host ""
Write-Host "3. Test both possible URLs:"
$Body = @{
    command="/planner"
    message="diagnostic test"
} | ConvertTo-Json

$Urls = @(
    "http://localhost:5678/webhook-test/pda-command-router",
    "http://localhost:5678/webhook/pda-command-router"
)

foreach ($Url in $Urls) {
    Write-Host ""
    Write-Host "Testing: $Url"
    try {
        $Result = Invoke-WebRequest -Uri $Url -Method Post -ContentType "application/json" -Body $Body -UseBasicParsing -TimeoutSec 10
        Write-Host "[OK] $($Result.StatusCode)"
        Write-Host $Result.Content
    }
    catch {
        Write-Host "[FAIL]"
        Write-Host $_.Exception.Message
    }
}
