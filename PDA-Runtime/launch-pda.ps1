# launch-pda.ps1

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "        Starting PDA Ecosystem"
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

function Wait-ForService {
    param (
        [string]$Url,
        [string]$Name,
        [int]$TimeoutSeconds = 90
    )

    Write-Host "[*] Waiting for $Name..." -ForegroundColor Yellow

    $start = Get-Date
    do {
        Start-Sleep -Seconds 2
        try {
            Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5 | Out-Null
            Write-Host "[OK] $Name online." -ForegroundColor Green
            return $true
        }
        catch {
            $elapsed = ((Get-Date) - $start).TotalSeconds
        }
    } until ($elapsed -ge $TimeoutSeconds)

    Write-Host "[WARN] $Name did not respond at $Url" -ForegroundColor Yellow
    return $false
}

Write-Host "[*] Checking Docker..." -ForegroundColor Yellow

try {
    docker info | Out-Null
    Write-Host "[OK] Docker already running." -ForegroundColor Green
}
catch {
    Write-Host "[*] Starting Docker Desktop..." -ForegroundColor Yellow

    $dockerPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"

    if (Test-Path $dockerPath) {
        Start-Process $dockerPath
    }
    else {
        Write-Host "[ERROR] Docker Desktop not found at expected path." -ForegroundColor Red
        exit 1
    }

    do {
        Start-Sleep -Seconds 5
        try {
            docker info | Out-Null
            $dockerReady = $true
        }
        catch {
            $dockerReady = $false
        }
    } until ($dockerReady)

    Write-Host "[OK] Docker is running." -ForegroundColor Green
}

$composeFile = Join-Path $PSScriptRoot "docker-compose.yml"

if (!(Test-Path $composeFile)) {
    Write-Host "[ERROR] docker-compose.yml not found in runtime folder:" -ForegroundColor Red
    Write-Host $composeFile
    exit 1
}

Write-Host ""
Write-Host "[*] Starting containers..." -ForegroundColor Yellow

Push-Location $PSScriptRoot
docker compose up -d
Pop-Location

Write-Host ""

$openWebUI = "http://localhost:3000"
$n8n      = "http://localhost:5678"
$liteLLM  = "http://localhost:4000"
$ollama   = "http://localhost:11434"

Wait-ForService -Url $openWebUI -Name "Open WebUI" | Out-Null
Wait-ForService -Url $n8n -Name "n8n" | Out-Null
Wait-ForService -Url $liteLLM -Name "LiteLLM" -TimeoutSeconds 30 | Out-Null
Wait-ForService -Url $ollama -Name "Ollama API" -TimeoutSeconds 30 | Out-Null

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "              PDA READY"
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Open WebUI : $openWebUI" -ForegroundColor Green
Write-Host "n8n        : $n8n" -ForegroundColor Green
Write-Host "LiteLLM    : $liteLLM" -ForegroundColor Green
Write-Host "Ollama API : $ollama" -ForegroundColor Green
Write-Host ""

Write-Host "[*] Opening browser tabs..." -ForegroundColor Yellow
Start-Process $openWebUI
Start-Process $n8n

Write-Host ""
Write-Host "[OK] PDA startup complete." -ForegroundColor Green
