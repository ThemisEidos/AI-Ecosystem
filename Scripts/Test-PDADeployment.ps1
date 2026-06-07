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
$EnvExamplePath = Join-Path $Root "PDA-Runtime\.env.example"
$LiteLLMEnvExamplePath = Join-Path $Root "litellm\.env.local.example"
$LiteLLMEnvPath = Join-Path $Root "litellm\.env.local"
$ObsidianVaultPath = Join-Path $Root "Obsidian Vault"
$RequiredFolders = @(
    "PDA-Runtime",
    "PDA-Runtime\configs",
    "PDA-Runtime\data",
    "PDA-Runtime\logs",
    "PDA-Backups",
    "PDA-Backups\notebooklm",
    "PDA-Backups\build-runner",
    "PDA-Backups\build-runner\logs",
    "PDA-Backups\build-runner\reports",
    "Roadmap\work-packets",
    "Roadmap\codex-prompts"
)

$RequiredScripts = @(
    "Scripts\Install-PDAEcosystem.ps1",
    "Scripts\Invoke-PDAFabricHealthCheck.ps1",
    "Scripts\Invoke-PDAFabric.ps1",
    "Scripts\PDA_CapabilityRouter.ps1",
    "Scripts\PDA_CapabilityMatrix.json",
    "Scripts\New-PDANotebookLMPackage.ps1",
    "Scripts\Invoke-PDANotebookLMCommand.ps1",
    "Scripts\Test-PDANotebookLMCommand.ps1",
    "Scripts\Test-PDAFabricHealthCheck.ps1",
    "Scripts\Test-PDACapabilityRouter.ps1"
)

function Get-PDACommandStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Probe,

        [string]$FallbackPath = ""
    )

    $Result = [ordered]@{
        name = $Name
        status = "missing"
        version = ""
        path = ""
        detail = ""
    }

    try {
        $Value = & $Probe
        if ($Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)) {
            $Result.status = "ok"
            $Result.version = [string]$Value
        }
    }
    catch {
        $Result.detail = $_.Exception.Message
    }

    if ($Result.status -ne "ok" -and -not [string]::IsNullOrWhiteSpace($FallbackPath) -and (Test-Path -LiteralPath $FallbackPath -PathType Leaf)) {
        $Result.status = "found_by_path"
        $Result.path = $FallbackPath
        try {
            $PathValue = & $FallbackPath --version 2>$null
            if ($PathValue) {
                $Result.version = [string]($PathValue -join " ").Trim()
            }
        }
        catch {
            if ([string]::IsNullOrWhiteSpace($Result.detail)) {
                $Result.detail = $_.Exception.Message
            }
        }
    }

    if ($Result.status -eq "missing" -and -not [string]::IsNullOrWhiteSpace($FallbackPath) -and (Test-Path -LiteralPath $FallbackPath -PathType Leaf)) {
        $Result.status = "found_by_path"
        $Result.path = $FallbackPath
    }

    return [pscustomobject]$Result
}

function Test-PDAServiceDefinition {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    return [bool]([regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline))
}

function Get-PDAEnvSummary {
    param([string]$Path)

    $Summary = [ordered]@{
        path = $Path
        exists = $false
        line_count = 0
        placeholders = 0
        secrets_detected = 0
    }

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $Summary.exists = $true
        $Lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop)
        $Summary.line_count = $Lines.Count
        foreach ($Line in $Lines) {
            if ($Line -match 'YOUR_[A-Z0-9_]+') { $Summary.placeholders++ }
            if ($Line -match '^(?!\s*#).*(?:api[_-]?key|secret|token|password)\s*=\s*(?!YOUR_).+') { $Summary.secrets_detected++ }
        }
    }

    return [pscustomobject]$Summary
}

$ComposeText = if (Test-Path -LiteralPath $ComposePath -PathType Leaf) { Get-Content -LiteralPath $ComposePath -Raw } else { "" }
$ComposeServices = @(
    [pscustomobject]@{
        name = "open-webui"
        present = Test-PDAServiceDefinition -Text $ComposeText -Pattern '(?m)^\s*open-webui:\s*$'
    }
    [pscustomobject]@{
        name = "n8n"
        present = Test-PDAServiceDefinition -Text $ComposeText -Pattern '(?m)^\s*n8n:\s*$'
    }
    [pscustomobject]@{
        name = "litellm"
        present = Test-PDAServiceDefinition -Text $ComposeText -Pattern '(?m)^\s*litellm:\s*$'
    }
)

$ComposeHasEnvFile = [bool]([regex]::IsMatch($ComposeText, [regex]::Escape("../litellm/.env.local")))
$ComposeHasOpenWebUI = [bool]($ComposeServices | Where-Object { $_.name -eq "open-webui" -and $_.present })
$ComposeHasN8n = [bool]($ComposeServices | Where-Object { $_.name -eq "n8n" -and $_.present })
$ComposeHasLiteLLM = [bool]($ComposeServices | Where-Object { $_.name -eq "litellm" -and $_.present })

$ObservedTools = @()
$ObservedTools += Get-PDACommandStatus -Name "PowerShell 7" -Probe { (pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()').Trim() }
$ObservedTools += Get-PDACommandStatus -Name "Git" -Probe { (git --version).Trim() }
$ObservedTools += Get-PDACommandStatus -Name "Docker" -Probe { (docker --version).Trim() }
$ObservedTools += Get-PDACommandStatus -Name "Python" -Probe { (python --version 2>&1).Trim() }
$ObservedTools += Get-PDACommandStatus -Name "Fabric CLI" -Probe {
    if (Get-Command fabric -ErrorAction SilentlyContinue) {
        (fabric --version).Trim()
    }
} -FallbackPath (Join-Path $env:USERPROFILE '.local\bin\fabric.exe')
$ObservedTools += Get-PDACommandStatus -Name "Ollama" -Probe {
    if (Get-Command ollama -ErrorAction SilentlyContinue) {
        (ollama --version).Trim()
    }
}
$ObservedTools += Get-PDACommandStatus -Name "Obsidian" -Probe {
    $Candidates = @(
        (Join-Path $env:LocalAppData 'Programs\Obsidian\Obsidian.exe'),
        (Join-Path $env:ProgramFiles 'Obsidian\Obsidian.exe')
    )
    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) { return $Candidate }
    }
}

$MissingFolders = @()
foreach ($Folder in $RequiredFolders) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $Folder) -PathType Container)) {
        $MissingFolders += $Folder
    }
}

$MissingScripts = @()
foreach ($Script in $RequiredScripts) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $Script) -PathType Leaf)) {
        $MissingScripts += $Script
    }
}

$EnvExample = Get-PDAEnvSummary -Path $EnvExamplePath
$LiteLLMEnvExample = Get-PDAEnvSummary -Path $LiteLLMEnvExamplePath
$LiteLLMEnv = Get-PDAEnvSummary -Path $LiteLLMEnvPath

$Issues = New-Object System.Collections.Generic.List[string]
if (-not (Test-Path -LiteralPath $ComposePath -PathType Leaf)) { $Issues.Add("PDA-Runtime/docker-compose.yml is missing.") }
if (-not $ComposeHasOpenWebUI) { $Issues.Add("open-webui service is not configured in docker-compose.yml.") }
if (-not $ComposeHasN8n) { $Issues.Add("n8n service is not configured in docker-compose.yml.") }
if (-not $ComposeHasLiteLLM) { $Issues.Add("litellm service is not configured in docker-compose.yml.") }
if (-not $ComposeHasEnvFile) { $Issues.Add("docker-compose.yml does not reference ../litellm/.env.local.") }
if (-not $EnvExample.exists) { $Issues.Add("PDA-Runtime/.env.example is missing.") }
if (-not $LiteLLMEnvExample.exists) { $Issues.Add("litellm/.env.local.example is missing.") }
if ($MissingFolders.Count -gt 0) { $Issues.Add("Missing folders: $($MissingFolders -join ', ').") }
if ($MissingScripts.Count -gt 0) { $Issues.Add("Missing scripts: $($MissingScripts -join ', ').") }
if ($EnvExample.secrets_detected -gt 0) { $Issues.Add("PDA-Runtime/.env.example contains non-placeholder secret-like values.") }

$Status = if ($Issues.Count -eq 0) { "pass" } elseif ($MissingFolders.Count -gt 0 -or $MissingScripts.Count -gt 0 -or -not $ComposeHasOpenWebUI -or -not $ComposeHasN8n -or -not $ComposeHasLiteLLM -or -not $EnvExample.exists) { "fail" } else { "warn" }

$Report = [pscustomobject]@{
    status = $Status
    repo_root = $Root
    compose_path = $ComposePath
    compose_has_open_webui = $ComposeHasOpenWebUI
    compose_has_n8n = $ComposeHasN8n
    compose_has_litellm = $ComposeHasLiteLLM
    compose_has_env_file = $ComposeHasEnvFile
    folder_count = $RequiredFolders.Count
    missing_folder_count = $MissingFolders.Count
    missing_folders = @($MissingFolders)
    script_count = $RequiredScripts.Count
    missing_script_count = $MissingScripts.Count
    missing_scripts = @($MissingScripts)
    env_template = $EnvExample
    litellm_env_template = $LiteLLMEnvExample
    local_env = $LiteLLMEnv
    tools = @($ObservedTools)
    issues = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 12
    if (-not $NoThrow -and $Report.status -eq "fail") {
        throw "PDA deployment validation failed."
    }
    return
}

Write-Host "=== PDA DEPLOYMENT VALIDATION ==="
Write-Host ("Status : {0}" -f $Report.status)
Write-Host ("Repo   : {0}" -f $Report.repo_root)
Write-Host ("Compose: {0}" -f $Report.compose_path)
Write-Host ""
Write-Host "Tools"
foreach ($Tool in $Report.tools) {
    Write-Host ("- {0}: {1} ({2})" -f $Tool.name, $Tool.status, $Tool.version)
}
Write-Host ""
Write-Host "Folders"
foreach ($Folder in $RequiredFolders) {
    $Exists = Test-Path -LiteralPath (Join-Path $Root $Folder) -PathType Container
    Write-Host ("- {0}: {1}" -f $Folder, ($(if ($Exists) { "present" } else { "missing" })))
}

if ($Report.issues.Count -gt 0) {
    Write-Host ""
    Write-Host "Issues"
    foreach ($Issue in $Report.issues) {
        Write-Host ("- {0}" -f $Issue)
    }
}

if (-not $NoThrow -and $Report.status -eq "fail") {
    throw "PDA deployment validation failed."
}
