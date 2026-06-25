[CmdletBinding()]
param(
    [switch]$AsJson,
    [switch]$NoThrow,
    [switch]$ValidateWF007
)

$ErrorActionPreference = "Stop"

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

function Invoke-ContainerProbe {
    param(
        [Parameter(Mandatory = $true)][string]$ContainerName,
        [Parameter(Mandatory = $true)][string]$CommandText
    )

    $Raw = @(& docker exec $ContainerName sh -lc $CommandText 2>&1)
    [pscustomobject]@{
        passed = ($LASTEXITCODE -eq 0)
        output = [string]($Raw -join "`n").Trim()
    }
}

$Checks = @(
    [pscustomobject]@{
        name = "Private Ollama"
        urls = @(
            "http://127.0.0.1:11435/api/tags"
        )
        container = "pda-private-ollama"
        container_probe = "/bin/ollama list"
        accept = @(200)
    }
    [pscustomobject]@{
        name = "Private Open WebUI"
        urls = @(
            "http://127.0.0.1:3001/health",
            "http://127.0.0.1:3001/api/models",
            "http://127.0.0.1:3001"
        )
        container = "pda-private-open-webui"
        container_probe = "wget -qO- http://127.0.0.1:8080/health || curl -fsS http://127.0.0.1:8080/health"
        accept = @(200, 301, 302, 303, 307, 308, 401, 403)
    }
)

$Results = @()
$Issues = New-Object System.Collections.Generic.List[string]

foreach ($Check in $Checks) {
    $Passed = $false
    $StatusCode = $null
    $SelectedUrl = $null
    foreach ($Url in @($Check.urls)) {
        $StatusCode = Get-HttpStatusCode -Url $Url -TimeoutSeconds 5
        if ($null -ne $StatusCode -and @($Check.accept) -contains $StatusCode) {
            $Passed = $true
            $SelectedUrl = $Url
            break
        }
    }

    if (-not $Passed -and $Check.PSObject.Properties.Name -contains "container" -and $Check.container) {
        $ContainerProbe = Invoke-ContainerProbe -ContainerName $Check.container -CommandText $Check.container_probe
        if ($ContainerProbe.passed) {
            $Passed = $true
            $SelectedUrl = "container://$($Check.container)"
        }
    }

    if (-not $Passed) {
        $Issues.Add("$($Check.name) is not healthy.")
    }

    $Results += [pscustomobject]@{
        name = $Check.name
        passed = $Passed
        status_code = $StatusCode
        url = $SelectedUrl
    }
}

$EnvRaw = @(& docker inspect -f "{{range .Config.Env}}{{println .}}{{end}}" pda-private-open-webui 2>$null)
$EnvText = [string]($EnvRaw -join "`n")
$OllamaWired = ($EnvText -match '(?m)^OLLAMA_BASE_URL=http://private-ollama:11434$')
if (-not $OllamaWired) {
    $Issues.Add("Private Open WebUI is not pinned to Private Ollama.")
}
$Results += [pscustomobject]@{
    name = "Private Open WebUI -> Private Ollama wiring"
    passed = $OllamaWired
    status_code = $null
    url = "env://pda-private-open-webui/OLLAMA_BASE_URL"
}

$BadCloudEnv = @($EnvText -split "`r?`n" | Where-Object {
    $_ -match '^(OPENAI_API_BASE_URL|OPENAI_API_KEY|OPENROUTER_API_KEY|ANTHROPIC_API_KEY|GEMINI_API_KEY)=.+' -and $_ -notmatch '=$'
})
$NoCloudFallback = ($BadCloudEnv.Count -eq 0)
if (-not $NoCloudFallback) {
    $Issues.Add("Private Open WebUI exposes cloud fallback environment variables.")
}
$Results += [pscustomobject]@{
    name = "No cloud fallback env"
    passed = $NoCloudFallback
    status_code = $null
    url = "env://pda-private-open-webui"
}

$OllamaEnvRaw = @(& docker inspect -f "{{range .Config.Env}}{{println .}}{{end}}" pda-private-ollama 2>$null)
$OllamaEnvText = [string]($OllamaEnvRaw -join "`n")
$OllamaCloudDisabled = ($OllamaEnvText -match '(?m)^OLLAMA_NO_CLOUD=true$')
if (-not $OllamaCloudDisabled) {
    $Issues.Add("Private Ollama does not explicitly disable cloud access.")
}
$Results += [pscustomobject]@{
    name = "Private Ollama cloud disabled"
    passed = $OllamaCloudDisabled
    status_code = $null
    url = "env://pda-private-ollama/OLLAMA_NO_CLOUD"
}

$WF007 = $null
if ($ValidateWF007) {
    $ScriptPath = Join-Path $PSScriptRoot "Test-COOPERPrivateLocalAnalysisWorkflow.ps1"
    $Output = @(& $ScriptPath 2>&1)
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -ne 0) {
        $Issues.Add("WF-007 readiness validation failed.")
    }
    $WF007 = [pscustomobject]@{
        exit_code = $ExitCode
        output = @($Output)
    }
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    results = @($Results)
    wf_007 = $WF007
    issues = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 15
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "Private stack health validation failed."
    }
    return
}

Write-Host "=== PRIVATE STACK HEALTH CHECK ==="
foreach ($Result in $Results) {
    if ($Result.passed) {
        Write-Host ("[OK] {0}" -f $Result.name) -ForegroundColor Green
    }
    else {
        Write-Host ("[FAIL] {0}" -f $Result.name) -ForegroundColor Red
    }
}

if ($ValidateWF007 -and $WF007) {
    if ($WF007.exit_code -eq 0) {
        Write-Host "[OK] WF-007 readiness" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] WF-007 readiness" -ForegroundColor Red
    }
}

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "Private stack health validation failed."
}
