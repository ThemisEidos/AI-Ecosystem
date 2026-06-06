[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ComposePath = Join-Path $Root "PDA-Runtime\docker-compose.yml"
$EnvPath = Join-Path $Root "litellm\.env.local"
$ExamplePath = Join-Path $Root "litellm\.env.local.example"

$RequiredKeys = @(
    "LITELLM_MASTER_KEY",
    "OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
    "GEMINI_API_KEY",
    "OPENROUTER_API_KEY"
)

function Read-PDAEnvFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Entries = [ordered]@{}
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return $Entries
    }

    foreach ($Line in Get-Content -Path $Path -ErrorAction Stop) {
        $Trimmed = [string]$Line
        if ([string]::IsNullOrWhiteSpace($Trimmed)) {
            continue
        }
        if ($Trimmed.TrimStart().StartsWith("#")) {
            continue
        }
        if ($Trimmed -notmatch '^\s*([^=\s]+)\s*=\s*(.*)\s*$') {
            continue
        }

        $Key = $Matches[1]
        $Value = $Matches[2]
        $Entries[$Key] = $Value
    }

    return $Entries
}

$Issues = New-Object System.Collections.Generic.List[string]

$ComposeText = if (Test-Path -Path $ComposePath -PathType Leaf) { Get-Content -Path $ComposePath -Raw } else { "" }
$EnvEntries = Read-PDAEnvFile -Path $EnvPath
$ExampleText = if (Test-Path -Path $ExamplePath -PathType Leaf) { Get-Content -Path $ExamplePath -Raw } else { "" }
$GitIgnoreText = if (Test-Path -Path (Join-Path $Root ".gitignore") -PathType Leaf) { Get-Content -Path (Join-Path $Root ".gitignore") -Raw } else { "" }

$ComposeHasEnvFile = [bool]([regex]::IsMatch($ComposeText, [regex]::Escape("../litellm/.env.local")))
$GitIgnoreProtectsEnv = [bool]([regex]::IsMatch($GitIgnoreText, '(?m)^\s*litellm/\.env\.local\s*$'))
$GitIgnoreAllowsExample = [bool]([regex]::IsMatch($GitIgnoreText, '(?m)^\s*!\s*litellm/\.env\.local\.example\s*$'))

if (-not (Test-Path -Path $EnvPath -PathType Leaf)) {
    $Issues.Add(".env.local is missing.")
}
if (-not (Test-Path -Path $ExamplePath -PathType Leaf)) {
    $Issues.Add(".env.local.example is missing.")
}
if (-not $ComposeHasEnvFile) {
    $Issues.Add("docker-compose.yml does not reference ../litellm/.env.local.")
}
if (-not $GitIgnoreProtectsEnv) {
    $Issues.Add(".gitignore does not explicitly protect litellm/.env.local.")
}
if (-not $GitIgnoreAllowsExample) {
    $Issues.Add(".gitignore does not explicitly allow litellm/.env.local.example.")
}

$LoadedKeys = @()
$MissingKeys = @()
$BlankKeys = @()
foreach ($Key in $RequiredKeys) {
    if ($EnvEntries.Contains($Key)) {
        $LoadedKeys += $Key
        if ([string]::IsNullOrWhiteSpace([string]$EnvEntries[$Key])) {
            $BlankKeys += $Key
        }
    }
    else {
        $MissingKeys += $Key
    }
}

$ExampleHasPlaceholders = $false
if ($ExampleText) {
    $ExampleHasPlaceholders = @(
        "LITELLM_MASTER_KEY=YOUR_LITELLM_MASTER_KEY",
        "OPENAI_API_KEY=YOUR_OPENAI_API_KEY",
        "ANTHROPIC_API_KEY=YOUR_ANTHROPIC_API_KEY",
        "GEMINI_API_KEY=YOUR_GEMINI_API_KEY",
        "OPENROUTER_API_KEY=YOUR_OPENROUTER_API_KEY"
    ) | ForEach-Object {
        [bool]([regex]::IsMatch($ExampleText, [regex]::Escape($_)))
    } | Where-Object { -not $_ } | Measure-Object | Select-Object -ExpandProperty Count
    $ExampleHasPlaceholders = ($ExampleHasPlaceholders -eq 0)
}

if (-not $ExampleHasPlaceholders) {
    $Issues.Add(".env.local.example does not contain the expected placeholders.")
}

$Status = if ($Issues.Count -eq 0) { "pass" } elseif ($MissingKeys.Count -gt 0) { "fail" } else { "warn" }

$Report = [pscustomobject]@{
    status = $Status
    compose_path = $ComposePath
    env_path = $EnvPath
    example_path = $ExamplePath
    compose_has_env_file = $ComposeHasEnvFile
    gitignore_protects_env = $GitIgnoreProtectsEnv
    gitignore_allows_example = $GitIgnoreAllowsExample
    required_keys = @($RequiredKeys)
    loaded_key_count = @($LoadedKeys).Count
    blank_key_count = @($BlankKeys).Count
    missing_key_count = @($MissingKeys).Count
    loaded_keys = @($LoadedKeys)
    blank_keys = @($BlankKeys)
    missing_keys = @($MissingKeys)
    example_has_placeholders = $ExampleHasPlaceholders
    issues = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -eq "fail") {
        throw "LiteLLM env validation failed."
    }
    return
}

Write-Host "[*] LiteLLM env validation"
Write-Host ("Status     : {0}" -f $Report.status)
Write-Host ("Loaded     : {0}" -f $Report.loaded_key_count)
Write-Host ("Blank      : {0}" -f $Report.blank_key_count)
Write-Host ("Missing    : {0}" -f $Report.missing_key_count)

if (-not $NoThrow -and $Report.status -eq "fail") {
    throw "LiteLLM env validation failed."
}
