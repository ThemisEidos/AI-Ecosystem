[CmdletBinding()]
param(
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$ComposeFile = Join-Path $Root "PDA-Runtime\docker-compose.private.yml"
$DockerDesktop = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"

if (-not (Test-Path -LiteralPath $ComposeFile -PathType Leaf)) {
    throw "Private compose file not found: $ComposeFile"
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
        throw "Docker Desktop not found at: $DockerDesktop"
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
    throw "Docker daemon did not become ready."
}

function Get-HttpStatusCode {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutSeconds = 5
    )

    try {
        $Params = @{
            Uri             = $Url
            UseBasicParsing = $true
            TimeoutSec      = $TimeoutSeconds
            ErrorAction     = "Stop"
        }
        $Command = Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue
        if ($Command -and $Command.Parameters.ContainsKey("NoProxy")) {
            $Params.NoProxy = $true
        }
        $Response = Invoke-WebRequest @Params
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

function Wait-ForPrivateService {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Urls,
        [string]$ContainerName,
        [string]$ContainerProbeCommand,
        [int[]]$AcceptStatusCodes = @(200, 301, 302, 303, 307, 308, 401, 403),
        [int]$MaxAttempts = 25
    )

    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        foreach ($Url in $Urls) {
            $StatusCode = Get-HttpStatusCode -Url $Url -TimeoutSeconds 5
            if ($null -ne $StatusCode -and $AcceptStatusCodes -contains $StatusCode) {
                Write-Host ("[OK] {0} ({1})" -f $Name, $Url) -ForegroundColor Green
                return $true
            }
        }

        if ($ContainerName -and $ContainerProbeCommand) {
            $ProbeRaw = @(& docker exec $ContainerName sh -lc $ContainerProbeCommand 2>&1)
            $ProbeText = [string]($ProbeRaw -join "`n").Trim()
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($ProbeText)) {
                Write-Host ("[OK] {0} (container probe: {1})" -f $Name, $ContainerName) -ForegroundColor Green
                return $true
            }
        }

        Write-Host ("[WAIT] {0} ({1}/{2})" -f $Name, $Attempt, $MaxAttempts) -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }

    Write-Host ("[WARN] {0} did not become ready." -f $Name) -ForegroundColor Yellow
    return $false
}

Push-Location $Root
try {
    Write-Host ""
    Write-Host "=== STARTING PRIVATE STACK ===" -ForegroundColor Cyan
    # docker compose writes benign warnings (e.g. volume/project-name mismatches) to stderr;
    # with $ErrorActionPreference = "Stop", merging that into the success stream via 2>&1 would
    # turn each warning line into a terminating error regardless of exit code. Relax locally.
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $Output = & docker compose -f $ComposeFile up -d 2>&1
    $ErrorActionPreference = $PreviousErrorActionPreference
    if ($LASTEXITCODE -ne 0) {
        throw ("docker compose failed for private stack:`n{0}" -f (($Output | Out-String).Trim()))
    }

    Wait-ForPrivateService -Name "Private Ollama" -Urls @(
        "http://127.0.0.1:11435/api/tags"
    ) -ContainerName "pda-private-ollama" -ContainerProbeCommand "/bin/ollama list" -AcceptStatusCodes @(200) | Out-Null

    Wait-ForPrivateService -Name "Private Open WebUI" -Urls @(
        "http://127.0.0.1:3001/health",
        "http://127.0.0.1:3001/api/models",
        "http://127.0.0.1:3001"
    ) -ContainerName "pda-private-open-webui" -ContainerProbeCommand "wget -qO- http://127.0.0.1:8080/health || curl -fsS http://127.0.0.1:8080/health" | Out-Null

    Write-Host ""
    Write-Host "=== PRIVATE STACK STATUS ===" -ForegroundColor Green
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter "label=ai.ecosystem.stack=private"

    if (-not $NoBrowser) {
        Write-Host ""
        Write-Host "=== OPENING PRIVATE INTERFACES ===" -ForegroundColor Cyan
        Start-Process "http://127.0.0.1:3001"
    }
}
finally {
    Pop-Location
}
