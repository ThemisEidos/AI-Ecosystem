Write-Host ""
Write-Host "========================================="
Write-Host "        Starting PDA Ecosystem"
Write-Host "========================================="
Write-Host ""

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
            Write-Host "[WAIT] $Name ($Attempt/$MaxAttempts)"
            Start-Sleep -Seconds $SleepSeconds
        }
    }

    Write-Host "[WARN] $Name did not become ready."
    return $false
}

Write-Host "[*] Checking Docker daemon..."
try {
    docker info *> $null
    $DockerReady = ($LASTEXITCODE -eq 0)
}
catch {
    $DockerReady = $false
}

if (-not $DockerReady) {
    Write-Host "[*] Docker daemon not running. Starting Docker Desktop..."

    if (-not (Test-Path $DockerDesktop)) {
        Write-Host "[ERROR] Docker Desktop not found at: $DockerDesktop"
        exit 1
    }

    Start-Process $DockerDesktop

    for ($i = 1; $i -le 60; $i++) {
        docker info *> $null
        if ($LASTEXITCODE -eq 0) {
            $DockerReady = $true
            break
        }

        Write-Host "[*] Waiting for Docker daemon... $i/60"
        Start-Sleep -Seconds 3
    }
}

if (-not $DockerReady) {
    Write-Host "[ERROR] Docker daemon did not become ready."
    exit 1
}

Write-Host "[OK] Docker daemon running."
Write-Host ""
Write-Host "[*] Starting containers..."

docker start open-webui n8n litellm ollama *> $null

Write-Host ""
Write-Host "[*] Waiting for service readiness..."
Wait-ForService -Name "Open WebUI" -Url "http://localhost:3000" | Out-Null
Wait-ForService -Name "LiteLLM" -Url "http://localhost:4000/v1/models" | Out-Null
Wait-ForService -Name "n8n" -Url "http://localhost:5678" | Out-Null
Wait-ForService -Name "Ollama" -Url "http://localhost:11434/api/tags" | Out-Null

Write-Host ""
Write-Host "[*] Container status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Write-Host ""
Write-Host "[*] Opening interfaces..."
Start-Process "http://localhost:3000"
Start-Process "http://localhost:5678"

Write-Host ""
Write-Host "[OK] PDA Ecosystem ready."

