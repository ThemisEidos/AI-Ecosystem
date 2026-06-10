Write-Host ""
Write-Host "========================================="
Write-Host "        Starting PDA Ecosystem"
Write-Host "========================================="
Write-Host ""

$DockerDesktop = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"

function Wait-ForService {
    param(
        [string]$Name,
        [string[]]$Urls,
        [string[]]$ContainerNames = @(),
        [int]$TimeoutSeconds = 5,
        [int]$MaxAttempts = 20,
        [int]$SleepSeconds = 3
    )

    function Get-HttpStatusCode {
        param(
            [string]$Url,
            [int]$TimeoutSeconds = 5
        )

        try {
            $InvokeParams = @{
                Uri             = $Url
                UseBasicParsing = $true
                TimeoutSec      = $TimeoutSeconds
                ErrorAction     = "Stop"
            }

            $Command = Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue
            if ($Command -and $Command.Parameters.ContainsKey("NoProxy")) {
                $InvokeParams.NoProxy = $true
            }

            $Response = Invoke-WebRequest @InvokeParams
            return [int]$Response.StatusCode
        }
        catch {
            $Response = $null
            if ($_.Exception -and ($_.Exception.PSObject.Properties.Name -contains "Response")) {
                $Response = $_.Exception.Response
            }

            if ($Response -and $Response.StatusCode) {
                return [int]$Response.StatusCode.value__
            }

            return $null
        }
    }

    function Test-ContainerRunning {
        param([string]$ContainerName)
        try {
            $Running = (& docker inspect -f "{{.State.Running}}" $ContainerName 2>$null)
            return (($LASTEXITCODE -eq 0) -and (($Running | Select-Object -First 1) -eq "true"))
        }
        catch {
            return $false
        }
    }

    $AcceptedStatusCodes = @(200, 301, 302, 303, 307, 308, 401, 403)

    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        foreach ($Url in @($Urls)) {
            $StatusCode = Get-HttpStatusCode -Url $Url -TimeoutSeconds $TimeoutSeconds
            if ($null -ne $StatusCode -and $AcceptedStatusCodes -contains $StatusCode) {
                if ($StatusCode -eq 200) {
                    Write-Host "[OK] $Name"
                }
                else {
                    Write-Host "[OK] $Name (HTTP $StatusCode)"
                }

                return $true
            }
        }

        foreach ($ContainerName in @($ContainerNames)) {
            if (Test-ContainerRunning -ContainerName $ContainerName) {
                Write-Host "[OK] $Name (container running: $ContainerName)"
                return $true
            }
        }

        Write-Host "[WAIT] $Name ($Attempt/$MaxAttempts)"
        Start-Sleep -Seconds $SleepSeconds
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

function Resolve-ContainerName {
    param([string[]]$Candidates)

    $AllContainers = @(& docker ps -a --format "{{.Names}}" 2>$null)
    foreach ($Candidate in $Candidates) {
        if ($AllContainers -contains $Candidate) {
            return $Candidate
        }
    }

    return $null
}

foreach ($CandidateSet in @(
    @("pda-open-webui", "open-webui"),
    @("pda-n8n", "n8n"),
    @("pda-litellm", "litellm"),
    @("pda-ollama", "ollama")
)) {
    $ContainerName = Resolve-ContainerName -Candidates $CandidateSet
    if ($ContainerName) {
        docker start $ContainerName *> $null
    }
}

Write-Host ""
Write-Host "[*] Waiting for service readiness..."
Wait-ForService -Name "Open WebUI" -Urls @("http://localhost:3000/health", "http://localhost:3000/api/models", "http://localhost:3000") -ContainerNames @("open-webui", "pda-open-webui") | Out-Null
Wait-ForService -Name "LiteLLM" -Urls @("http://localhost:4000/v1/models") -ContainerNames @("litellm", "pda-litellm") | Out-Null
Wait-ForService -Name "n8n" -Urls @("http://localhost:5678/healthz", "http://localhost:5678/rest/settings", "http://localhost:5678") -ContainerNames @("n8n", "pda-n8n") | Out-Null
Wait-ForService -Name "Ollama" -Urls @("http://localhost:11434/api/tags") -ContainerNames @("ollama", "pda-ollama") | Out-Null

Write-Host ""
Write-Host "[*] Container status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Write-Host ""
Write-Host "[*] Opening interfaces..."
Start-Process "http://localhost:3000"
Start-Process "http://localhost:5678"

Write-Host ""
Write-Host "[OK] PDA Ecosystem ready."

