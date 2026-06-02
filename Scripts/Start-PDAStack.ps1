Write-Host ""
Write-Host "=== STARTING PDA STACK ===" -ForegroundColor Cyan
Write-Host ""

docker start open-webui
docker start n8n
docker start litellm
docker start ollama

function Wait-ForService {
    param(
        [string]$Name,
        [string]$Url,
        [int]$TimeoutSeconds = 5,
        [int]$MaxAttempts = 20,
        [int]$SleepSeconds = 3
    )

    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        try {
            Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSeconds | Out-Null
            Write-Host "[OK] $Name"
            return $true
        }
        catch {
            Write-Host "[WAIT] $Name ($Attempt/$MaxAttempts)"
            Start-Sleep -Seconds $SleepSeconds
        }
    }

    Write-Host "[WARN] $Name did not become ready."
    return $false
}

Write-Host ""
Write-Host "=== WAITING FOR SERVICES ===" -ForegroundColor Yellow
Wait-ForService -Name "Open WebUI" -Url "http://localhost:3000" | Out-Null
Wait-ForService -Name "LiteLLM" -Url "http://localhost:4000/v1/models" | Out-Null
Wait-ForService -Name "n8n" -Url "http://localhost:5678" | Out-Null
Wait-ForService -Name "Ollama" -Url "http://localhost:11434/api/tags" | Out-Null

Write-Host ""
Write-Host "=== SERVICE STATUS ===" -ForegroundColor Green
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Write-Host ""
Write-Host "=== OPENING INTERFACES ===" -ForegroundColor Cyan

Start-Process "http://localhost:3000"
Start-Process "http://localhost:5678"

Write-Host ""
Write-Host "=== PDA STACK READY ===" -ForegroundColor Green
