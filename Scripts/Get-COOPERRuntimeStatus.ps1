[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$IdentityScript = Join-Path $PSScriptRoot "Get-COOPERIdentity.ps1"
if (Test-Path -LiteralPath $IdentityScript -PathType Leaf) {
    . $IdentityScript
}

function Get-COOPERRuntimeProviderProfile {
    param([Parameter(Mandatory = $true)][string]$ModelName)

    switch ([string]$ModelName) {
        "qwen2.5:7b" {
            return [pscustomobject]@{
                provider = "Ollama"
                gateway = "LiteLLM"
                interface = "Open WebUI"
                backend = "ollama/qwen2.5:7b"
                provider_family = "local"
            }
        }
        "mistral" {
            return [pscustomobject]@{
                provider = "Ollama"
                gateway = "LiteLLM"
                interface = "Open WebUI"
                backend = "ollama/mistral"
                provider_family = "local"
            }
        }
        "local-llama" {
            return [pscustomobject]@{
                provider = "Ollama"
                gateway = "LiteLLM"
                interface = "Open WebUI"
                backend = "ollama/llama3.2"
                provider_family = "local"
            }
        }
        "openai" {
            return [pscustomobject]@{
                provider = "OpenAI"
                gateway = "LiteLLM"
                interface = "Open WebUI"
                backend = "openai/gpt-4o-mini"
                provider_family = "openai"
            }
        }
        "claude" {
            return [pscustomobject]@{
                provider = "Anthropic"
                gateway = "LiteLLM"
                interface = "Open WebUI"
                backend = "anthropic/claude-sonnet-4-5-20250929"
                provider_family = "anthropic"
            }
        }
        "gemini" {
            return [pscustomobject]@{
                provider = "Google"
                gateway = "LiteLLM"
                interface = "Open WebUI"
                backend = "gemini/gemini-2.5-flash"
                provider_family = "google"
            }
        }
        "gemini-pro" {
            return [pscustomobject]@{
                provider = "Google"
                gateway = "LiteLLM"
                interface = "Open WebUI"
                backend = "gemini/gemini-2.5-pro"
                provider_family = "google"
            }
        }
        "openrouter" {
            return [pscustomobject]@{
                provider = "OpenRouter"
                gateway = "LiteLLM"
                interface = "Open WebUI"
                backend = "openrouter/openai/gpt-4o-mini"
                provider_family = "openrouter"
            }
        }
        default {
            return [pscustomobject]@{
                provider = "Local"
                gateway = "LiteLLM"
                interface = "Open WebUI"
                backend = $ModelName
                provider_family = "local"
            }
        }
    }
}

function Get-COOPERRuntimeStatus {
    <#
    Deprecated legacy helper.
    Not authoritative for /cooper status.
    Governed COOPER status must use the identity -> registry -> router -> approval -> workbench chain.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Identity = $null
    if (Get-Command -Name Get-COOPERIdentity -ErrorAction SilentlyContinue) {
        try {
            $Identity = Get-COOPERIdentity -Root $Root
        }
        catch {
            $Identity = $null
        }
    }

    $DisplayName = if ($Identity -and $Identity.PSObject.Properties.Name -contains "display_name") { [string]$Identity.display_name } else { "COOPER" }
    $OfficialName = if ($Identity -and $Identity.PSObject.Properties.Name -contains "official_name") { [string]$Identity.official_name } else { "Command Operations Orchestrator for Planning, Execution, and Reporting" }
    $Tagline = if ($Identity -and $Identity.PSObject.Properties.Name -contains "tagline") { [string]$Identity.tagline } else { "Chief Officer of Preventing Everything from Randomly Exploding" }
    $IdentityNote = if ($Identity -and $Identity.PSObject.Properties.Name -contains "identity_note") { [string]$Identity.identity_note } else { "TARS-inspired, not copyrighted imitation" }
    $Personality = if ($Identity -and $Identity.PSObject.Properties.Name -contains "personality") { $Identity.personality } else { $null }
    $RuntimeLayers = if ($Identity -and $Identity.PSObject.Properties.Name -contains "runtime_layers") { $Identity.runtime_layers } else { $null }

    $CurrentModel = if ($Identity -and $Identity.PSObject.Properties.Name -contains "default_model" -and -not [string]::IsNullOrWhiteSpace([string]$Identity.default_model)) {
        [string]$Identity.default_model
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$env:COOPER_DEFAULT_MODEL)) {
        [string]$env:COOPER_DEFAULT_MODEL
    }
    else {
        "qwen2.5:7b"
    }

    $Profile = Get-COOPERRuntimeProviderProfile -ModelName $CurrentModel
    $CurrentExplosions = 0

    $SummaryLines = @(
        "COOPER Status"
        ("Current Model: {0}" -f $CurrentModel)
        ("Provider: {0}" -f $Profile.provider)
        ("Gateway: {0}" -f $Profile.gateway)
        ("Backend: {0}" -f $Profile.backend)
        ("Interface: {0}" -f $Profile.interface)
        ("Assistant Identity: {0}" -f $DisplayName)
        ("Current Explosions: {0}" -f $CurrentExplosions)
    )

    return [pscustomobject]@{
        status = $(if ($Identity -and [string]$Identity.status -eq "error") { "warning" } else { "pass" })
        assistant_identity = $DisplayName
        official_name = $OfficialName
        tagline = $Tagline
        identity_note = $IdentityNote
        current_model = $CurrentModel
        provider = $Profile.provider
        gateway = $Profile.gateway
        interface = $Profile.interface
        backend = $Profile.backend
        provider_family = $Profile.provider_family
        current_explosions = $CurrentExplosions
        personality = $Personality
        runtime_layers = $RuntimeLayers
        summary_lines = $SummaryLines
        runtime_origin = "AI Ecosystem workspace"
        source_of_truth = "Scripts/Get-COOPERRuntimeStatus.ps1"
    }
}
