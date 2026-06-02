Write-Host "=== PDA STACK HEALTH CHECK ==="

$Checks = @(
    @{ Name = "Open WebUI"; Url = "http://localhost:3000" },
    @{ Name = "n8n"; Url = "http://localhost:5678" },
    @{ Name = "LiteLLM"; Url = "http://localhost:4000/v1/models" },
    @{ Name = "Ollama"; Url = "http://localhost:11434/api/tags" }
)

foreach ($Check in $Checks) {
    $Healthy = $false
    for ($Attempt = 1; $Attempt -le 10; $Attempt++) {
        try {
            Invoke-WebRequest -Uri $Check.Url -UseBasicParsing -TimeoutSec 5 | Out-Null
            Write-Host "[OK] $($Check.Name)"
            $Healthy = $true
            break
        }
        catch {
            if ($Attempt -lt 10) {
                Start-Sleep -Seconds 2
            }
        }
    }
    if (-not $Healthy) {
        Write-Host "[FAIL] $($Check.Name)"
    }
}

Write-Host ""
Write-Host "=== CONTAINERS ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
