Set-StrictMode -Version Latest

function Get-AIECServices {
    @(
        [pscustomobject]@{
            Name             = "Open WebUI"
            Url              = "http://localhost:3000"
            Port             = 3000
            ComposeService   = "open-webui"
            ContainerNames   = @("pda-open-webui", "open-webui")
            Optional         = $false
            StartupTimeout   = 120
            LogTail          = 30
        },
        [pscustomobject]@{
            Name             = "LiteLLM"
            Url              = "http://localhost:4000/v1/models"
            Port             = 4000
            ComposeService   = "litellm"
            ContainerNames   = @("pda-litellm", "litellm")
            Optional         = $false
            StartupTimeout   = 120
            LogTail          = 30
            AcceptStatusCodes = @(200, 401)
        },
        [pscustomobject]@{
            Name             = "n8n"
            Url              = "http://localhost:5678"
            Port             = 5678
            ComposeService   = "n8n"
            ContainerNames   = @("pda-n8n", "n8n")
            Optional         = $false
            StartupTimeout   = 120
            LogTail          = 30
            AcceptStatusCodes = @(200)
        },
        [pscustomobject]@{
            Name             = "Ollama"
            Url              = "http://localhost:11434/api/tags"
            Port             = 11434
            ComposeService   = "ollama"
            ContainerNames   = @("pda-ollama", "ollama")
            Optional         = $true
            StartupTimeout   = 30
            LogTail          = 20
            AcceptStatusCodes = @(200)
        }
    )
}

function Get-AIECHttpStatusCode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [int]$TimeoutSeconds = 5
    )

    try {
        $Response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSeconds
        return [int]$Response.StatusCode
    }
    catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            return [int]$_.Exception.Response.StatusCode.value__
        }

        return $null
    }
}

function Write-AIECLine {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("OK", "WARN", "ERROR", "INFO")]
        [string]$Level,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $Color = switch ($Level) {
        "OK" { "Green" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        default { "Cyan" }
    }

    Write-Host ("[{0}] {1}" -f $Level, $Message) -ForegroundColor $Color
}

function Get-AIECRepoRoot {
    param([string]$RepoRoot)

    if ($RepoRoot) {
        return (Resolve-Path -LiteralPath $RepoRoot).Path
    }

    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}

function Get-AIECComposeFile {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $Candidates = @(
        (Join-Path $RepoRoot "PDA-Runtime\docker-compose.yml"),
        (Join-Path $RepoRoot "docker-compose.yml"),
        (Join-Path $RepoRoot "compose.yml")
    )

    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate) {
            return $Candidate
        }
    }

    return $null
}

function Get-AIECDockerDesktopPath {
    $Candidates = @(
        (Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"),
        "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    )

    foreach ($Candidate in $Candidates) {
        if ($Candidate -and (Test-Path -LiteralPath $Candidate)) {
            return $Candidate
        }
    }

    return $null
}

function Test-AIECDockerEngine {
    try {
        & docker info *> $null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Start-AIECDockerDesktop {
    $DockerDesktopPath = Get-AIECDockerDesktopPath
    if (-not $DockerDesktopPath) {
        Write-AIECLine -Level ERROR -Message "Docker Desktop executable not found."
        return $false
    }

    $Process = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Process) {
        Write-AIECLine -Level INFO -Message "Docker Desktop process already present."
        return $true
    }

    Write-AIECLine -Level INFO -Message "Starting Docker Desktop."
    Start-Process -FilePath $DockerDesktopPath
    return $true
}

function Wait-AIECDockerEngine {
    param([int]$TimeoutSeconds = 240)

    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $Attempt = 0

    while ($Stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $Attempt++
        if (Test-AIECDockerEngine) {
            Write-AIECLine -Level OK -Message "Docker engine is ready."
            return $true
        }

        if ($Attempt -eq 1 -or ($Attempt % 5) -eq 0) {
            Write-AIECLine -Level INFO -Message ("Waiting for Docker engine ({0:n0}s elapsed)." -f $Stopwatch.Elapsed.TotalSeconds)
        }

        Start-Sleep -Seconds 3
    }

    Write-AIECLine -Level ERROR -Message ("Docker engine did not become ready within {0} seconds." -f $TimeoutSeconds)
    return $false
}

function Test-AIECDockerComposeAvailable {
    try {
        & docker compose version *> $null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Invoke-AIECComposeUp {
    param(
        [Parameter(Mandatory = $true)][string]$ComposeFile,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    if (-not (Test-AIECDockerComposeAvailable)) {
        Write-AIECLine -Level WARN -Message "docker compose is not available; using container fallback."
        return $false
    }

    Write-AIECLine -Level INFO -Message ("Starting stack with compose file: {0}" -f $ComposeFile)
    Push-Location $RepoRoot
    try {
        $Output = & docker compose -f $ComposeFile up -d 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-AIECLine -Level OK -Message "docker compose up completed."
            return $true
        }

        Write-AIECLine -Level WARN -Message "docker compose up failed; falling back to docker start."
        foreach ($Line in @($Output) | Select-Object -Last 8) {
            $Text = if ($Line -is [string]) { $Line } else { $Line.ToString() }
            if (-not [string]::IsNullOrWhiteSpace($Text)) {
                Write-Host ("    {0}" -f $Text)
            }
        }

        return $false
    }
    finally {
        Pop-Location
    }
}

function Get-AIECAllContainerNames {
    try {
        return @(& docker ps -a --format "{{.Names}}" 2>$null)
    }
    catch {
        return @()
    }
}

function Resolve-AIECContainerName {
    param([Parameter(Mandatory = $true)]$Service)

    $AllNames = Get-AIECAllContainerNames
    foreach ($Candidate in @($Service.ContainerNames) + @($Service.ComposeService)) {
        if ($AllNames -contains $Candidate) {
            return $Candidate
        }
    }

    return $null
}

function Test-AIECContainerRunning {
    param([string]$ContainerName)

    if (-not $ContainerName) {
        return $false
    }

    try {
        $Running = (& docker inspect -f "{{.State.Running}}" $ContainerName 2>$null)
        return (($LASTEXITCODE -eq 0) -and (($Running | Select-Object -First 1) -eq "true"))
    }
    catch {
        return $false
    }
}

function Start-AIECFallbackContainers {
    param([Parameter(Mandatory = $true)]$Services)

    $StartedAny = $false
    foreach ($Service in $Services) {
        $ContainerName = Resolve-AIECContainerName -Service $Service
        if (-not $ContainerName) {
            if ($Service.Optional) {
                Write-AIECLine -Level WARN -Message ("Optional container missing for {0}." -f $Service.Name)
            }
            else {
                Write-AIECLine -Level WARN -Message ("No existing container found for {0}." -f $Service.Name)
            }

            continue
        }

        if (Test-AIECContainerRunning -ContainerName $ContainerName) {
            Write-AIECLine -Level OK -Message ("Container already running: {0}" -f $ContainerName)
            $StartedAny = $true
            continue
        }

        Write-AIECLine -Level INFO -Message ("Starting container: {0}" -f $ContainerName)
        & docker start $ContainerName *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-AIECLine -Level OK -Message ("Container started: {0}" -f $ContainerName)
            $StartedAny = $true
        }
        else {
            Write-AIECLine -Level WARN -Message ("docker start failed for {0}" -f $ContainerName)
        }
    }

    return $StartedAny
}

function Wait-AIECService {
    param(
        [Parameter(Mandatory = $true)]$Service,
        [int]$TimeoutSeconds = 60
    )

    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $AcceptStatusCodes = if ($Service.PSObject.Properties.Name -contains "AcceptStatusCodes" -and $Service.AcceptStatusCodes) {
        @($Service.AcceptStatusCodes)
    }
    else {
        @(200)
    }

    while ($Stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $StatusCode = Get-AIECHttpStatusCode -Url $Service.Url -TimeoutSeconds 5
        if ($null -ne $StatusCode -and $AcceptStatusCodes -contains $StatusCode) {
            if ($StatusCode -eq 200) {
                Write-AIECLine -Level OK -Message ("{0} reachable at {1}" -f $Service.Name, $Service.Url)
            }
            else {
                Write-AIECLine -Level OK -Message ("{0} reachable at {1} (HTTP {2})" -f $Service.Name, $Service.Url, $StatusCode)
            }

            return $true
        }

        Start-Sleep -Seconds 3
    }

    if ($Service.Optional) {
        Write-AIECLine -Level WARN -Message ("Optional service {0} did not respond at {1}" -f $Service.Name, $Service.Url)
    }
    else {
        Write-AIECLine -Level ERROR -Message ("Service {0} did not respond at {1}" -f $Service.Name, $Service.Url)
    }

    return $false
}

function Get-AIECPDAWebhookServer {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $LogDir = Join-Path $RepoRoot "PDA-Logs"
    [pscustomobject]@{
        Name           = "PDA Webhook Server"
        Url            = "http://localhost:8788/pda-chat-bridge"
        HealthUrl      = "http://localhost:8788/pda-chat-bridge/healthz"
        Port           = 8788
        StartupTimeout = 30
        ScriptPath     = Join-Path $RepoRoot "Scripts\Start-PDAWebhookServer.ps1"
        StdOutLogPath  = Join-Path $LogDir "PDAWebhookServer.stdout.log"
        StdErrLogPath  = Join-Path $LogDir "PDAWebhookServer.stderr.log"
        ServerLogPath  = Join-Path $LogDir "PDAWebhookServer.log"
        LogTail        = 20
    }
}

function Test-AIECPDAWebhookServer {
    param(
        [Parameter(Mandatory = $true)]$WebhookServer,
        [int]$TimeoutSeconds = 5
    )

    $Payload = @{
        user_message       = "health check"
        confirm_dispatch   = $false
        conversation_id    = "aiec-health"
        session_id         = "aiec-health"
        user_id            = "aiec-health"
        conversation_title = "AI Ecosystem Health Check"
    } | ConvertTo-Json -Depth 5

    try {
        $Parsed = Invoke-RestMethod -Uri $WebhookServer.HealthUrl -Method GET -TimeoutSec $TimeoutSeconds
        return [pscustomobject]@{
            Reachable = ($Parsed -and $Parsed.PSObject.Properties.Name -contains "status" -and [string]$Parsed.status -eq "ok")
            StatusCode = 200
            Parsed = $Parsed
            Error = $null
        }
    }
    catch {
        $StatusCode = $null
        if ($_.Exception.PSObject.Properties.Name -contains "Response" -and $_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $StatusCode = [int]$_.Exception.Response.StatusCode.value__
        }

        return [pscustomobject]@{
            Reachable = $false
            StatusCode = $StatusCode
            Parsed = $null
            Error = $_.Exception.Message
        }
    }
}

function Start-AIECPDAWebhookServer {
    param(
        [Parameter(Mandatory = $true)]$WebhookServer
    )

    if (-not (Test-Path -LiteralPath $WebhookServer.ScriptPath)) {
        Write-AIECLine -Level ERROR -Message ("PDA webhook server script not found: {0}" -f $WebhookServer.ScriptPath)
        return $false
    }

    $Probe = Test-AIECPDAWebhookServer -WebhookServer $WebhookServer -TimeoutSeconds 3
    if ($Probe.Reachable) {
        Write-AIECLine -Level OK -Message ("{0} already healthy at {1}" -f $WebhookServer.Name, $WebhookServer.HealthUrl)
        return $true
    }

    $Listener = Get-AIECListeningProcess -Port $WebhookServer.Port
    if ($Listener) {
        Write-AIECLine -Level WARN -Message ("Port {0} is already in use by {1} (PID {2}); not launching a duplicate webhook server." -f $WebhookServer.Port, $Listener.ProcessName, $Listener.ProcessId)
        return $false
    }

    $LogDir = Split-Path -Parent $WebhookServer.StdOutLogPath
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

    Write-AIECLine -Level INFO -Message ("Starting {0}." -f $WebhookServer.Name)
    $EscapedScriptPath = $WebhookServer.ScriptPath.Replace("'", "''")
    $CommandText = "& '$EscapedScriptPath'"
    $EncodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($CommandText))
    $ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $EncodedCommand)
    Start-Process -FilePath "pwsh" -ArgumentList $ArgumentList -WindowStyle Hidden -RedirectStandardOutput $WebhookServer.StdOutLogPath -RedirectStandardError $WebhookServer.StdErrLogPath | Out-Null
    return $true
}

function Wait-AIECPDAWebhookServer {
    param(
        [Parameter(Mandatory = $true)]$WebhookServer,
        [int]$TimeoutSeconds = 30
    )

    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($Stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $Probe = Test-AIECPDAWebhookServer -WebhookServer $WebhookServer -TimeoutSeconds 3
        if ($Probe.Reachable) {
            Write-AIECLine -Level OK -Message ("{0} reachable at {1}" -f $WebhookServer.Name, $WebhookServer.HealthUrl)
            return $true
        }

        Start-Sleep -Seconds 2
    }

    Write-AIECLine -Level ERROR -Message ("{0} did not become ready at {1}" -f $WebhookServer.Name, $WebhookServer.HealthUrl)
    return $false
}

function Get-AIECListeningProcess {
    param([int]$Port)

    try {
        $Connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop |
            Select-Object -First 1
        if (-not $Connection) {
            return $null
        }

        $Process = Get-Process -Id $Connection.OwningProcess -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            Port        = $Port
            ProcessId   = $Connection.OwningProcess
            ProcessName = if ($Process) { $Process.ProcessName } else { "(unknown)" }
        }
    }
    catch {
        return $null
    }
}

function Redact-AIECLogLine {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $Line
    }

    $Redacted = $Line -replace '(?i)(authorization\s*[:=]\s*bearer\s+)[^\s"]+', '$1[REDACTED]'
    $Redacted = $Redacted -replace '(?i)\b(api[_-]?key|token|secret|password)\b(\s*[:=]\s*)[^\s"]+', '$1$2[REDACTED]'
    $Redacted = $Redacted -replace 'sk-[A-Za-z0-9_\-]+', 'sk-[REDACTED]'
    return $Redacted
}

function Show-AIECDiagnostics {
    param(
        [Parameter(Mandatory = $true)]$Service,
        [string]$ComposeFile
    )

    Write-Host ""
    Write-Host ("Troubleshooting: {0}" -f $Service.Name) -ForegroundColor Yellow

    if ($ComposeFile -and (Test-Path -LiteralPath $ComposeFile)) {
        Write-AIECLine -Level OK -Message ("Compose file found: {0}" -f $ComposeFile)
    }
    else {
        Write-AIECLine -Level ERROR -Message "Compose file not found."
    }

    if (-not (Test-AIECDockerEngine)) {
        Write-AIECLine -Level WARN -Message "Docker engine is offline; container inspection skipped."
    }
    else {
        $ContainerName = Resolve-AIECContainerName -Service $Service
        if ($ContainerName) {
            Write-AIECLine -Level OK -Message ("Container exists: {0}" -f $ContainerName)
            if (Test-AIECContainerRunning -ContainerName $ContainerName) {
                Write-AIECLine -Level OK -Message ("Container running: {0}" -f $ContainerName)
            }
            else {
                Write-AIECLine -Level WARN -Message ("Container not running: {0}" -f $ContainerName)
            }

            $Logs = @(& docker logs --tail $Service.LogTail $ContainerName 2>&1)
            if ($Logs.Count -gt 0) {
                Write-Host "Recent logs:"
                foreach ($Line in $Logs | Select-Object -Last $Service.LogTail) {
                    $Text = if ($Line -is [string]) { $Line } else { $Line.ToString() }
                    Write-Host ("    {0}" -f (Redact-AIECLogLine -Line $Text))
                }
            }
            else {
                Write-AIECLine -Level WARN -Message "No recent container logs available."
            }
        }
        else {
            if ($Service.Optional) {
                Write-AIECLine -Level WARN -Message ("No container found for optional service {0}." -f $Service.Name)
            }
            else {
                Write-AIECLine -Level ERROR -Message ("No container found for {0}." -f $Service.Name)
            }
        }
    }

    $Listener = Get-AIECListeningProcess -Port $Service.Port
    if ($Listener) {
        Write-AIECLine -Level INFO -Message ("Port {0} listener: {1} (PID {2})" -f $Listener.Port, $Listener.ProcessName, $Listener.ProcessId)
    }
    else {
        Write-AIECLine -Level WARN -Message ("No process is listening on port {0}." -f $Service.Port)
    }
}

function Show-AIECPDAWebhookDiagnostics {
    param(
        [Parameter(Mandatory = $true)]$WebhookServer,
        [string]$ComposeFile
    )

    Write-Host ""
    Write-Host ("Troubleshooting: {0}" -f $WebhookServer.Name) -ForegroundColor Yellow

    if ($ComposeFile -and (Test-Path -LiteralPath $ComposeFile)) {
        Write-AIECLine -Level OK -Message ("Compose file found: {0}" -f $ComposeFile)
    }
    else {
        Write-AIECLine -Level ERROR -Message "Compose file not found."
    }

    if (Test-Path -LiteralPath $WebhookServer.ScriptPath) {
        Write-AIECLine -Level OK -Message ("Webhook server script found: {0}" -f $WebhookServer.ScriptPath)
    }
    else {
        Write-AIECLine -Level ERROR -Message ("Webhook server script missing: {0}" -f $WebhookServer.ScriptPath)
    }

    $Listener = Get-AIECListeningProcess -Port $WebhookServer.Port
    if ($Listener) {
        Write-AIECLine -Level INFO -Message ("Port {0} listener: {1} (PID {2})" -f $Listener.Port, $Listener.ProcessName, $Listener.ProcessId)
    }
    else {
        Write-AIECLine -Level WARN -Message ("No process is listening on port {0}." -f $WebhookServer.Port)
    }

    $Probe = Test-AIECPDAWebhookServer -WebhookServer $WebhookServer -TimeoutSeconds 3
    if ($Probe.Reachable) {
        Write-AIECLine -Level OK -Message ("{0} responded with valid bridge JSON." -f $WebhookServer.Name)
    }
    elseif ($Probe.StatusCode) {
        Write-AIECLine -Level WARN -Message ("{0} returned HTTP {1}." -f $WebhookServer.Name, $Probe.StatusCode)
    }
    elseif ($Probe.Error) {
        Write-AIECLine -Level WARN -Message ("{0} probe error: {1}" -f $WebhookServer.Name, $Probe.Error)
    }

    $LogPaths = @($WebhookServer.ServerLogPath, $WebhookServer.StdOutLogPath, $WebhookServer.StdErrLogPath)
    foreach ($LogPath in $LogPaths) {
        if (-not (Test-Path -LiteralPath $LogPath)) {
            continue
        }

        Write-Host ("Recent logs: {0}" -f $LogPath)
        foreach ($Line in Get-Content -LiteralPath $LogPath -Tail $WebhookServer.LogTail -ErrorAction SilentlyContinue) {
            Write-Host ("    {0}" -f (Redact-AIECLogLine -Line $Line))
        }
    }
}

function Show-AIECContainerSummary {
    if (-not (Test-AIECDockerEngine)) {
        Write-AIECLine -Level WARN -Message "Skipping container summary because Docker is offline."
        return
    }

    try {
        Write-Host ""
        Write-Host "Containers" -ForegroundColor Cyan
        $Output = & docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-AIECLine -Level WARN -Message "Could not query docker container status."
            foreach ($Line in @($Output) | Select-Object -Last 5) {
                $Text = if ($Line -is [string]) { $Line } else { $Line.ToString() }
                Write-Host ("    {0}" -f $Text)
            }
            return
        }

        foreach ($Line in @($Output)) {
            Write-Host $Line
        }
    }
    catch {
        Write-AIECLine -Level WARN -Message "Could not query docker container status."
    }
}

function Show-AIECDuplicateContainerWarnings {
    param([Parameter(Mandatory = $true)]$Services)

    if (-not (Test-AIECDockerEngine)) {
        return
    }

    $AllNames = Get-AIECAllContainerNames
    foreach ($Service in $Services) {
        $Matches = @($Service.ContainerNames + @($Service.ComposeService) | Where-Object { $AllNames -contains $_ } | Select-Object -Unique)
        if ($Matches.Count -gt 1) {
            Write-AIECLine -Level WARN -Message ("Multiple containers detected for {0}: {1}" -f $Service.Name, ($Matches -join ", "))
        }
    }
}

function Invoke-AIECStart {
    [CmdletBinding()]
    param(
        [string]$RepoRoot,
        [switch]$NoBrowser
    )

    $ResolvedRepoRoot = Get-AIECRepoRoot -RepoRoot $RepoRoot
    $ComposeFile = Get-AIECComposeFile -RepoRoot $ResolvedRepoRoot
    $Services = Get-AIECServices
    $WebhookServer = Get-AIECPDAWebhookServer -RepoRoot $ResolvedRepoRoot

    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "       Starting AI Ecosystem Stack" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""

    if (Test-AIECDockerEngine) {
        Write-AIECLine -Level OK -Message "Docker engine already online."
    }
    else {
        if (-not (Start-AIECDockerDesktop)) {
            return 1
        }

        if (-not (Wait-AIECDockerEngine)) {
            return 1
        }
    }

    $ComposeStarted = $false
    if ($ComposeFile) {
        $ComposeStarted = Invoke-AIECComposeUp -ComposeFile $ComposeFile -RepoRoot $ResolvedRepoRoot
    }
    else {
        Write-AIECLine -Level WARN -Message "No compose file found; using container fallback."
    }

    if (-not $ComposeStarted) {
        [void](Start-AIECFallbackContainers -Services $Services)
    }

    $Failures = 0
    foreach ($Service in $Services) {
        $Healthy = Wait-AIECService -Service $Service -TimeoutSeconds $Service.StartupTimeout
        if (-not $Healthy) {
            Show-AIECDiagnostics -Service $Service -ComposeFile $ComposeFile
            if (-not $Service.Optional) {
                $Failures++
            }
        }
    }

    if ($Failures -eq 0) {
        $WebhookStarted = Start-AIECPDAWebhookServer -WebhookServer $WebhookServer
        if ($WebhookStarted) {
            if (-not (Wait-AIECPDAWebhookServer -WebhookServer $WebhookServer -TimeoutSeconds $WebhookServer.StartupTimeout)) {
                Show-AIECPDAWebhookDiagnostics -WebhookServer $WebhookServer -ComposeFile $ComposeFile
                $Failures++
            }
        }
        else {
            Show-AIECPDAWebhookDiagnostics -WebhookServer $WebhookServer -ComposeFile $ComposeFile
            $Failures++
        }
    }
    else {
        Write-AIECLine -Level WARN -Message ("Skipping {0} startup because required Docker services are not healthy." -f $WebhookServer.Name)
    }

    Show-AIECContainerSummary
    Show-AIECDuplicateContainerWarnings -Services $Services

    if (-not $NoBrowser) {
        foreach ($Url in @("http://localhost:3000", "http://localhost:5678")) {
            try {
                Start-Process $Url | Out-Null
            }
            catch {
                Write-AIECLine -Level WARN -Message ("Could not open browser for {0}" -f $Url)
            }
        }
    }

    Write-Host ""
    if ($Failures -gt 0) {
        Write-AIECLine -Level ERROR -Message ("AI Ecosystem startup finished with {0} required service failure(s)." -f $Failures)
        return 1
    }

    Write-AIECLine -Level OK -Message "AI Ecosystem startup complete."
    return 0
}

function Invoke-AIECStatus {
    [CmdletBinding()]
    param([string]$RepoRoot)

    $ResolvedRepoRoot = Get-AIECRepoRoot -RepoRoot $RepoRoot
    $ComposeFile = Get-AIECComposeFile -RepoRoot $ResolvedRepoRoot
    $Services = Get-AIECServices
    $WebhookServer = Get-AIECPDAWebhookServer -RepoRoot $ResolvedRepoRoot

    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "        AI Ecosystem Status Check" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""

    if (Test-AIECDockerEngine) {
        Write-AIECLine -Level OK -Message "Docker engine online."
    }
    else {
        Write-AIECLine -Level ERROR -Message "Docker engine offline."
    }

    if ($ComposeFile) {
        Write-AIECLine -Level OK -Message ("Compose file found: {0}" -f $ComposeFile)
    }
    else {
        Write-AIECLine -Level ERROR -Message "Compose file not found."
    }

    Show-AIECContainerSummary
    Show-AIECDuplicateContainerWarnings -Services $Services

    Write-Host ""
    Write-Host "Services" -ForegroundColor Cyan
    foreach ($Service in $Services) {
        $Healthy = Wait-AIECService -Service $Service -TimeoutSeconds 3
        if (-not $Healthy) {
            Show-AIECDiagnostics -Service $Service -ComposeFile $ComposeFile
        }
    }

    $WebhookHealthy = Wait-AIECPDAWebhookServer -WebhookServer $WebhookServer -TimeoutSeconds 3
    if (-not $WebhookHealthy) {
        Show-AIECPDAWebhookDiagnostics -WebhookServer $WebhookServer -ComposeFile $ComposeFile
    }
}
