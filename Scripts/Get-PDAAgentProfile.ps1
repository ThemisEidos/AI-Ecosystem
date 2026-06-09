[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AgentId = "",

    [Parameter(Mandatory = $false)]
    [string]$Capability = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("category_1", "category_2")]
    [string]$Category = "",

    [Parameter(Mandatory = $false)]
    [string]$Tool = "",

    [Parameter(Mandatory = $false)]
    [string]$Provider = "",

    [Parameter(Mandatory = $false)]
    [string]$ApprovalRequiredDefault = "",

    [Parameter(Mandatory = $false)]
    [string]$RestrictedLocalOnly = "",

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow,

    [Parameter(Mandatory = $false)]
    [string]$RegistryPath = ""
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ResolvedRegistryPath = if (-not [string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath
} else {
    Join-Path $PSScriptRoot "PDA_AgentProfileRegistry.json"
}

function ConvertTo-PDAAgentBoolean {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    switch ($Value.Trim().ToLowerInvariant()) {
        "true" { return $true }
        "false" { return $false }
        default { throw "Boolean filter must be true or false." }
    }
}

function Test-PDAAgentProfileMatch {
    param(
        [Parameter(Mandatory = $true)]
        $Profile,

        [Parameter(Mandatory = $false)]
        [string]$Capability = "",

        [Parameter(Mandatory = $false)]
        [string]$Category = "",

        [Parameter(Mandatory = $false)]
        [string]$Tool = "",

        [Parameter(Mandatory = $false)]
        [string]$Provider = "",

        [Parameter(Mandatory = $false)]
        [Nullable[bool]]$ApprovalRequiredDefault,

        [Parameter(Mandatory = $false)]
        [Nullable[bool]]$RestrictedLocalOnly
    )

    if (-not [string]::IsNullOrWhiteSpace($Capability)) {
        $Capabilities = @($Profile.approved_capabilities | ForEach-Object { [string]$_ })
        if (-not (@($Capabilities | Where-Object { $_ -ieq $Capability }).Count -gt 0)) {
            return $false
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        $AllowedCategories = @($Profile.category_allowed | ForEach-Object { [string]$_ })
        if (-not (@($AllowedCategories | Where-Object { $_ -ieq $Category }).Count -gt 0)) {
            return $false
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Tool)) {
        $AllowedTools = @($Profile.approved_tools | ForEach-Object { [string]$_ })
        if (-not (@($AllowedTools | Where-Object { $_ -ieq $Tool }).Count -gt 0)) {
            return $false
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Provider)) {
        $Providers = @($Profile.preferred_providers + $Profile.fallback_providers | ForEach-Object { [string]$_ })
        if (-not (@($Providers | Where-Object { $_ -ieq $Provider }).Count -gt 0)) {
            return $false
        }
    }

    if ($null -ne $ApprovalRequiredDefault) {
        if ([bool]$Profile.approval_required_default -ne [bool]$ApprovalRequiredDefault) {
            return $false
        }
    }

    if ($null -ne $RestrictedLocalOnly) {
        if ([bool]$Profile.restricted_local_only -ne [bool]$RestrictedLocalOnly) {
            return $false
        }
    }

    return $true
}

if (-not (Test-Path -LiteralPath $ResolvedRegistryPath -PathType Leaf)) {
    $Result = [pscustomobject]@{
        status = "fail"
        registry_path = $ResolvedRegistryPath
        error = "Agent profile registry not found."
        count = 0
        filters = [pscustomobject]@{
            agent_id = $AgentId
            capability = $Capability
            category = $Category
            tool = $Tool
            provider = $Provider
            approval_required_default = $ApprovalRequiredDefault
            restricted_local_only = $RestrictedLocalOnly
        }
        agent_profiles = @()
    }

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        if (-not $NoThrow) { throw $Result.error }
        return
    }

    Write-Host "[ERROR] $($Result.error)"
    if (-not $NoThrow) { throw $Result.error }
    return
}

try {
    $Raw = Get-Content -LiteralPath $ResolvedRegistryPath -Raw -ErrorAction Stop
    $Registry = $Raw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    $Result = [pscustomobject]@{
        status = "fail"
        registry_path = $ResolvedRegistryPath
        error = $_.Exception.Message
        count = 0
        filters = [pscustomobject]@{
            agent_id = $AgentId
            capability = $Capability
            category = $Category
            tool = $Tool
            provider = $Provider
            approval_required_default = $ApprovalRequiredDefault
            restricted_local_only = $RestrictedLocalOnly
        }
        agent_profiles = @()
    }

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        if (-not $NoThrow) { throw $Result.error }
        return
    }

    Write-Host "[ERROR] $($Result.error)"
    if (-not $NoThrow) { throw $Result.error }
    return
}

if ($null -eq $Registry -or -not ($Registry.PSObject.Properties.Name -contains "agent_profiles")) {
    $Result = [pscustomobject]@{
        status = "fail"
        registry_path = $ResolvedRegistryPath
        error = "Agent profile registry is missing 'agent_profiles'."
        count = 0
        filters = [pscustomobject]@{
            agent_id = $AgentId
            capability = $Capability
            category = $Category
            tool = $Tool
            provider = $Provider
            approval_required_default = $ApprovalRequiredDefault
            restricted_local_only = $RestrictedLocalOnly
        }
        agent_profiles = @()
    }

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        if (-not $NoThrow) { throw $Result.error }
        return
    }

    Write-Host "[ERROR] $($Result.error)"
    if (-not $NoThrow) { throw $Result.error }
    return
}

$ApprovalValue = $null
if (-not [string]::IsNullOrWhiteSpace($ApprovalRequiredDefault)) {
    $ApprovalValue = ConvertTo-PDAAgentBoolean -Value $ApprovalRequiredDefault
}

$RestrictedValue = $null
if (-not [string]::IsNullOrWhiteSpace($RestrictedLocalOnly)) {
    $RestrictedValue = ConvertTo-PDAAgentBoolean -Value $RestrictedLocalOnly
}

$Profiles = @($Registry.agent_profiles)
if (-not [string]::IsNullOrWhiteSpace($AgentId)) {
    $Profiles = @($Profiles | Where-Object { [string]$_.agent_id -ieq $AgentId })
}

$Profiles = @(
    $Profiles | Where-Object {
        Test-PDAAgentProfileMatch -Profile $_ -Capability $Capability -Category $Category -Tool $Tool -Provider $Provider -ApprovalRequiredDefault $ApprovalValue -RestrictedLocalOnly $RestrictedValue
    }
)

$Report = [pscustomobject]@{
    status = "pass"
    registry_path = $ResolvedRegistryPath
    registry = [pscustomobject]@{
        schema_version = [string]$Registry.schema_version
        policy_name = if ($Registry.PSObject.Properties.Name -contains "policy_name") { [string]$Registry.policy_name } else { "PDA Agent Profile Registry" }
        policy_version = if ($Registry.PSObject.Properties.Name -contains "policy_version") { [string]$Registry.policy_version } else { "1.0" }
        updated_at = if ($Registry.PSObject.Properties.Name -contains "updated_at") { [string]$Registry.updated_at } else { "" }
    }
    count = @($Profiles).Count
    filters = [pscustomobject]@{
        agent_id = $AgentId
        capability = $Capability
        category = $Category
        tool = $Tool
        provider = $Provider
        approval_required_default = $ApprovalRequiredDefault
        restricted_local_only = $RestrictedLocalOnly
    }
    agent_profiles = $Profiles
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] Agent profile lookup"
Write-Host ("Registry path : {0}" -f $Report.registry_path)
Write-Host ("Count         : {0}" -f $Report.count)
if ($Report.count -eq 0) {
    Write-Host "No agent profiles matched the current filters."
    return
}

$Report.agent_profiles |
    Select-Object agent_id, display_name, approved_capabilities, approved_tools, preferred_providers, approval_required_default, restricted_local_only, risk_level |
    Format-Table -AutoSize
