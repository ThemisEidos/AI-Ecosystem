Write-Host "=== START DOCKER THEN PDA ==="

$DockerDesktop = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"

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
            Write-Host "Waiting for $Name... $Attempt/$MaxAttempts"
            Start-Sleep -Seconds $SleepSeconds
        }
    }

    Write-Host "[WARN] $Name did not become ready."
    return $false
}

if (-not (Test-Path $DockerDesktop)) {
    Write-Host "Docker Desktop not found at:"
    Write-Host $DockerDesktop
    exit 1
}

Write-Host "Starting Docker Desktop..."
Start-Process $DockerDesktop

Write-Host "Waiting for Docker daemon..."
$Ready = $false

for ($i = 1; $i -le 60; $i++) {
    try {
        docker info *> $null
        if ($LASTEXITCODE -eq 0) {
            $Ready = $true
            break
        }
    }
    catch {}

    Write-Host "Waiting... $i"
    Start-Sleep -Seconds 3
}

if (-not $Ready) {
    Write-Host "Docker daemon did not become ready."
    exit 1
}

Write-Host "Docker daemon is ready."

Write-Host "Starting PDA containers..."
docker start open-webui n8n litellm ollama

Write-Host ""
Write-Host "Waiting for services..."
Wait-ForService -Name "Open WebUI" -Url "http://localhost:3000" | Out-Null
Wait-ForService -Name "LiteLLM" -Url "http://localhost:4000/v1/models" | Out-Null
Wait-ForService -Name "n8n" -Url "http://localhost:5678" | Out-Null
Wait-ForService -Name "Ollama" -Url "http://localhost:11434/api/tags" | Out-Null

Write-Host ""
Write-Host "Container status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Start-Process "http://localhost:3000"
Start-Process "http://localhost:5678"

Write-Host ""
Write-Host "PDA stack started."
