[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$RegistryPath = Join-Path $PSScriptRoot "PDA_AgentProfileRegistry.json"
$CapabilityRegistryPath = Join-Path $PSScriptRoot "PDA_CapabilityRegistry.json"
$AgentProfileScript = Join-Path $PSScriptRoot "Get-PDAAgentProfile.ps1"
$RequiredAgentIds = @(
    "research_agent",
    "reporting_agent",
    "review_agent",
    "build_agent",
    "automation_agent",
    "restricted_agent"
)

$CloudProviderNames = @("Gemini", "Claude", "Claude Code", "Codex", "OpenAI", "Perplexity", "OpenRouter")
$RequiredFields = @(
    "agent_id",
    "display_name",
    "mission",
    "responsibilities",
    "approved_capabilities",
    "approved_tools",
    "preferred_providers",
    "fallback_providers",
    "category_allowed",
    "approval_required_default",
    "restricted_local_only",
    "output_types",
    "risk_level",
    "notes"
)

$Issues = New-Object System.Collections.Generic.List[string]
$Registry = $null
$CapabilityRegistry = $null
$GetAll = $null
$GetOne = $null
$GetJson = $null

if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) {
    $Issues.Add("Agent profile registry file not found: $RegistryPath")
}
else {
    try {
        $Registry = Get-Content -LiteralPath $RegistryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $Issues.Add("Agent profile registry JSON could not be parsed: $($_.Exception.Message)")
    }
}

if (-not (Test-Path -LiteralPath $CapabilityRegistryPath -PathType Leaf)) {
    $Issues.Add("Capability registry file not found: $CapabilityRegistryPath")
}
else {
    try {
        $CapabilityRegistry = Get-Content -LiteralPath $CapabilityRegistryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $Issues.Add("Capability registry JSON could not be parsed: $($_.Exception.Message)")
    }
}

$CapabilityIds = @()
if ($CapabilityRegistry -and ($CapabilityRegistry.PSObject.Properties.Name -contains "capabilities") -and $CapabilityRegistry.capabilities) {
    $CapabilityIds = @($CapabilityRegistry.capabilities | ForEach-Object { [string]$_.capability_id })
}

if ($null -ne $Registry) {
    if (-not ($Registry.PSObject.Properties.Name -contains "agent_profiles")) {
        $Issues.Add("Agent profile registry missing 'agent_profiles'.")
    }
    elseif ($null -eq $Registry.agent_profiles -or $Registry.agent_profiles -isnot [System.Array]) {
        $Issues.Add("Agent profile registry 'agent_profiles' must be an array.")
    }
    else {
        $Profiles = @($Registry.agent_profiles)
        foreach ($AgentId in $RequiredAgentIds) {
            if (-not (@($Profiles | Where-Object { [string]$_.agent_id -ieq $AgentId }).Count -gt 0)) {
                $Issues.Add("Missing required agent id: $AgentId")
            }
        }

        foreach ($Profile in $Profiles) {
            foreach ($Field in $RequiredFields) {
                if (-not ($Profile.PSObject.Properties.Name -contains $Field)) {
                    $Issues.Add("Agent profile '$([string]$Profile.agent_id)' missing required field '$Field'.")
                }
            }

            if ($Profile.PSObject.Properties.Name -contains "approval_required_default" -and ($Profile.approval_required_default -isnot [bool])) {
                $Issues.Add("Agent profile '$([string]$Profile.agent_id)' approval_required_default must be boolean.")
            }

            $ApprovedCapabilities = @($Profile.approved_capabilities | ForEach-Object { [string]$_ })
            foreach ($CapabilityId in $ApprovedCapabilities) {
                if ($CapabilityIds.Count -gt 0 -and -not ($CapabilityIds -contains $CapabilityId)) {
                    $Issues.Add("Agent profile '$([string]$Profile.agent_id)' references unknown capability '$CapabilityId'.")
                }
            }

            if ([string]$Profile.agent_id -eq "restricted_agent") {
                if (-not [bool]$Profile.restricted_local_only) {
                    $Issues.Add("restricted_agent must be restricted_local_only.")
                }

                foreach ($FieldName in @("preferred_providers", "fallback_providers")) {
                    $Providers = @($Profile.$FieldName | ForEach-Object { [string]$_ })
                    if (@($Providers | Where-Object { $CloudProviderNames -contains $_ }).Count -gt 0) {
                        $Issues.Add("restricted_agent contains cloud providers in $FieldName.")
                    }
                }
            }
        }
    }
}

if (Test-Path -LiteralPath $AgentProfileScript -PathType Leaf) {
    try {
        $GetAllJson = & pwsh -NoProfile -File $AgentProfileScript -AsJson -NoThrow
        $GetAll = if ($GetAllJson -is [string]) { $GetAllJson | ConvertFrom-Json } else { ($GetAllJson | Out-String) | ConvertFrom-Json }
    }
    catch {
        $Issues.Add("Get-PDAAgentProfile.ps1 list-all invocation failed: $($_.Exception.Message)")
    }

    try {
        $GetOneJson = & pwsh -NoProfile -File $AgentProfileScript -AgentId research_agent -AsJson -NoThrow
        $GetOne = if ($GetOneJson -is [string]) { $GetOneJson | ConvertFrom-Json } else { ($GetOneJson | Out-String) | ConvertFrom-Json }
    }
    catch {
        $Issues.Add("Get-PDAAgentProfile.ps1 profile retrieval failed: $($_.Exception.Message)")
    }

    try {
        $GetJsonOutput = & pwsh -NoProfile -File $AgentProfileScript -Capability code_implementation -AsJson -NoThrow
        $GetJson = if ($GetJsonOutput -is [string]) { $GetJsonOutput | ConvertFrom-Json } else { ($GetJsonOutput | Out-String) | ConvertFrom-Json }
    }
    catch {
        $Issues.Add("Get-PDAAgentProfile.ps1 -AsJson invocation failed: $($_.Exception.Message)")
    }
}
else {
    $Issues.Add("Get-PDAAgentProfile.ps1 not found at $AgentProfileScript")
}

$Status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
$Report = [pscustomobject]@{
    status = $Status
    registry_path = $RegistryPath
    capability_registry_path = $CapabilityRegistryPath
    agent_profile_script = $AgentProfileScript
    agent_count = if ($Registry -and ($Registry.PSObject.Properties.Name -contains "agent_profiles") -and $Registry.agent_profiles) { @($Registry.agent_profiles).Count } else { 0 }
    required_agent_count = $RequiredAgentIds.Count
    issues = @($Issues)
    registry = $Registry
    capability_registry = $CapabilityRegistry
    get_all = $GetAll
    get_one = $GetOne
    get_json = $GetJson
    tests = [pscustomobject]@{
        registry_exists = (Test-Path -LiteralPath $RegistryPath -PathType Leaf)
        json_valid = ($null -ne $Registry)
        required_ids_present = ($Issues | Where-Object { $_ -like "Missing required agent id:*" }).Count -eq 0
        required_fields_present = ($Issues | Where-Object { $_ -like "Agent profile '*' missing required field*" }).Count -eq 0
        capabilities_exist = ($Issues | Where-Object { $_ -like "*references unknown capability*" }).Count -eq 0
        restricted_local_only_valid = ($Issues | Where-Object { $_ -like "restricted_agent must be restricted_local_only*" }).Count -eq 0
        category2_cloud_free = ($Issues | Where-Object { $_ -like "restricted_agent contains cloud providers*" }).Count -eq 0
        approval_boolean_valid = ($Issues | Where-Object { $_ -like "*approval_required_default must be boolean*" }).Count -eq 0
        get_all_supported = ($null -ne $GetAll -and $GetAll.status -eq "pass")
        get_one_supported = ($null -ne $GetOne -and $GetOne.status -eq "pass")
        as_json_supported = ($null -ne $GetJson -and $GetJson.status -eq "pass")
    }
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Status -ne "pass") {
        throw "PDA agent profile registry validation failed."
    }
    return
}

Write-Host "[*] PDA agent profile registry validation"
Write-Host ("Registry path   : {0}" -f $RegistryPath)
Write-Host ("Agent count     : {0}" -f $Report.agent_count)
Write-Host ("Status          : {0}" -f $Status)
if ($Issues.Count -gt 0) {
    Write-Host ""
    Write-Host "Issues:"
    foreach ($Issue in $Issues) {
        Write-Host ("- {0}" -f $Issue)
    }
}

if (-not $NoThrow -and $Status -ne "pass") {
    throw "PDA agent profile registry validation failed."
}
