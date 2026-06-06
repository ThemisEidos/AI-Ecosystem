[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ConfigPath = Join-Path $Root "litellm\litellm_config.yaml"
$ComposePath = Join-Path $Root "PDA-Runtime\docker-compose.yml"
$Endpoint = "http://localhost:4000/v1/models"

function Get-PDARequiredEnvironmentVariable {
    param([Parameter(Mandatory = $true)][string]$Name)

    $Value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        throw "LITELLM_MASTER_KEY is not set. Configure it in the approved runtime secret source."
    }

    return [string]$Value
}

$MasterKey = Get-PDARequiredEnvironmentVariable -Name "LITELLM_MASTER_KEY"

$ExpectedProviders = @(
    [pscustomobject]@{
        name = "openai"
        model_name = "openai"
        env_name = "OPENAI_API_KEY"
        api_provider = "openai/gpt-4o-mini"
        requires_api_key = $true
    }
    [pscustomobject]@{
        name = "claude"
        model_name = "claude"
        env_name = "ANTHROPIC_API_KEY"
        api_provider = "anthropic/claude-sonnet-4-5-20250929"
        requires_api_key = $true
    }
    [pscustomobject]@{
        name = "gemini"
        model_name = "gemini"
        env_name = "GEMINI_API_KEY"
        api_provider = "gemini/gemini-2.0-flash"
        requires_api_key = $true
    }
    [pscustomobject]@{
        name = "openrouter"
        model_name = "openrouter"
        env_name = "OPENROUTER_API_KEY"
        api_provider = "openrouter/openai/gpt-4o-mini"
        requires_api_key = $true
    }
    [pscustomobject]@{
        name = "local-llama"
        model_name = "local-llama"
        env_name = ""
        api_provider = "ollama/llama3.2"
        requires_api_key = $false
    }
)

function Get-ModelIds {
    param([object]$Payload)

    $Models = @()
    if ($null -eq $Payload) {
        return @()
    }

    if ($Payload.data) {
        $Models = @($Payload.data)
    }
    elseif ($Payload.models) {
        $Models = @($Payload.models)
    }
    elseif ($Payload -is [System.Collections.IEnumerable] -and -not ($Payload -is [string])) {
        $Models = @($Payload)
    }

    return @($Models | ForEach-Object {
        if ($_.id) { [string]$_.id }
        elseif ($_.model_name) { [string]$_.model_name }
        elseif ($_.name) { [string]$_.name }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-ProviderBlock {
    param(
        [string]$Text,
        [string]$ModelName
    )

    $Pattern = "(?ms)^\s*-\s*model_name:\s*$([regex]::Escape($ModelName))\s*(.*?)(?=^\s*-\s*model_name:|\z)"
    $Match = [regex]::Match($Text, $Pattern)
    if ($Match.Success) {
        return $Match.Value
    }

    return ""
}

function Test-EnvKeyReference {
    param(
        [string]$Text,
        [string]$EnvName
    )

    $Pattern = [regex]::Escape("os.environ/$EnvName")
    return [bool]([regex]::IsMatch($Text, $Pattern))
}

$ConfigText = if (Test-Path $ConfigPath) { Get-Content -Path $ConfigPath -Raw } else { "" }
$ComposeText = if (Test-Path $ComposePath) { Get-Content -Path $ComposePath -Raw } else { "" }

$Issues = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
    $Issues.Add("LiteLLM config missing: $ConfigPath")
}
if (-not (Test-Path -Path $ComposePath -PathType Leaf)) {
    $Issues.Add("Docker Compose file missing: $ComposePath")
}

$ConfigChecks = @()
foreach ($Provider in $ExpectedProviders) {
    $Configured = $false
    $EnvReferenceOk = $false
    $HostEnvPresent = $true
    $LiveAvailable = $false
    $ProviderIssues = New-Object System.Collections.Generic.List[string]
    $ProviderBlock = ""

    if ($ConfigText) {
        $ProviderBlock = Get-ProviderBlock -Text $ConfigText -ModelName $Provider.model_name
        $Configured = -not [string]::IsNullOrWhiteSpace($ProviderBlock)
        if ($Provider.requires_api_key) {
            $EnvReferenceOk = Test-EnvKeyReference -Text $ProviderBlock -EnvName $Provider.env_name
            if (-not $EnvReferenceOk) {
                $ProviderIssues.Add("Config does not reference $($Provider.env_name) via os.environ.")
            }
        }
        else {
            $EnvReferenceOk = -not ([regex]::IsMatch($ProviderBlock, "(?m)^\s*api_key:\s*"))
        }
    }

    if ($Provider.requires_api_key) {
        $HostEnvPresent = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($Provider.env_name))
    }

    $ConfigChecks += [pscustomobject]@{
        name = $Provider.name
        model_name = $Provider.model_name
        api_provider = $Provider.api_provider
        env_name = $Provider.env_name
        configured = $Configured
        env_reference_ok = $EnvReferenceOk
        host_env_present = $HostEnvPresent
        live_available = $LiveAvailable
        issues = @($ProviderIssues)
    }
}

$LiveModels = @()
$EndpointReachable = $false
try {
    $Response = Invoke-WebRequest -Uri $Endpoint -UseBasicParsing -TimeoutSec 10 -Headers @{ Authorization = "Bearer $MasterKey" }
    $EndpointReachable = $true
    $Body = if ([string]::IsNullOrWhiteSpace($Response.Content)) { $null } else { $Response.Content | ConvertFrom-Json }
    $LiveModels = Get-ModelIds -Payload $Body
}
catch {
    $Issues.Add("LiteLLM endpoint unavailable at ${Endpoint}: $($_.Exception.Message)")
}

foreach ($Provider in $ConfigChecks) {
    $Provider.live_available = [bool]($LiveModels -contains $Provider.model_name)
    if (-not $Provider.live_available) {
        $ProviderIssues = @($Provider.issues)
        $ProviderIssues += "Model '$($Provider.model_name)' not present in live /v1/models response."
        $Provider.issues = $ProviderIssues
    }
}

$SecretPatterns = @(
    "sk-[A-Za-z0-9_-]{8,}",
    "AIza[0-9A-Za-z_-]{8,}",
    "xox[baprs]-[A-Za-z0-9-]{8,}",
    "ghp_[A-Za-z0-9]{8,}",
    "Bearer\s+[A-Za-z0-9._-]{8,}"
)

$SecretHits = @()
if ($ConfigText) {
    foreach ($Pattern in $SecretPatterns) {
        $Matches = [regex]::Matches($ConfigText, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($Match in $Matches) {
            $SecretHits += [pscustomobject]@{
                pattern = $Pattern
                value = $Match.Value
            }
        }
    }
}

if ($SecretHits.Count -gt 0) {
    $Issues.Add("Potential secret-like literals found in LiteLLM config.")
}

$ComposeHasConfigMount = [bool]([regex]::IsMatch($ComposeText, [regex]::Escape("../litellm/litellm_config.yaml:/app/config.yaml:ro")))
$ComposeHasCommand = [bool]([regex]::IsMatch($ComposeText, "--config\s+/app/config\.yaml"))
$ComposeHasEnvFile = [bool]([regex]::IsMatch($ComposeText, [regex]::Escape("../litellm/.env.local")))

if (-not $ComposeHasConfigMount) {
    $Issues.Add("docker-compose.yml does not mount litellm_config.yaml into /app/config.yaml.")
}
if (-not $ComposeHasCommand) {
    $Issues.Add("docker-compose.yml does not pass --config /app/config.yaml to LiteLLM.")
}
if (-not $ComposeHasEnvFile) {
    $Issues.Add("docker-compose.yml does not reference ../litellm/.env.local.")
}

$ProviderRows = @($ConfigChecks)
$ProviderPassCount = @($ProviderRows | Where-Object { $_.configured -and $_.live_available -and $_.env_reference_ok -and $_.issues.Count -eq 0 }).Count
$ProviderFailCount = @($ProviderRows).Count - $ProviderPassCount

$Status = if ($Issues.Count -eq 0 -and $ProviderFailCount -eq 0) { "pass" } else { "fail" }

$Report = [pscustomobject]@{
    status = $Status
    endpoint = $Endpoint
    config_path = $ConfigPath
    compose_path = $ComposePath
    endpoint_reachable = $EndpointReachable
    compose_has_env_file = $ComposeHasEnvFile
    live_model_ids = @($LiveModels)
    provider_count = @($ProviderRows).Count
    passed_count = $ProviderPassCount
    failed_count = $ProviderFailCount
    secret_scan = [pscustomobject]@{
        status = if ($SecretHits.Count -eq 0) { "pass" } else { "fail" }
        hit_count = $SecretHits.Count
        hits = @($SecretHits)
    }
    providers = @($ProviderRows)
    issues = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "LiteLLM provider validation failed."
    }
    return
}

Write-Host "[*] LiteLLM provider validation"
Write-Host ("Endpoint   : {0}" -f $Report.endpoint)
Write-Host ("Providers  : {0}" -f $Report.provider_count)
Write-Host ("Passed     : {0}" -f $Report.passed_count)
Write-Host ("Failed     : {0}" -f $Report.failed_count)
Write-Host ("Secrets    : {0}" -f $Report.secret_scan.status)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "LiteLLM provider validation failed."
}
