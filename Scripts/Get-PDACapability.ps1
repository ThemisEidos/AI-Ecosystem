[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CapabilityId = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("category_1", "category_2")]
    [string]$Category = "",

    [Parameter(Mandatory = $false)]
    [string]$Agent = "",

    [Parameter(Mandatory = $false)]
    [string]$Tool = "",

    [Parameter(Mandatory = $false)]
    [string]$ApprovalRequired = "",

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
    Join-Path $PSScriptRoot "PDA_CapabilityRegistry.json"
}

function ConvertTo-PDACapabilityBoolean {
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
        default { throw "ApprovalRequired filter must be true or false." }
    }
}

function Test-PDACapabilityMatch {
    param(
        [Parameter(Mandatory = $true)]
        $Capability,

        [Parameter(Mandatory = $false)]
        [string]$Category = "",

        [Parameter(Mandatory = $false)]
        [string]$Agent = "",

        [Parameter(Mandatory = $false)]
        [string]$Tool = "",

        [Parameter(Mandatory = $false)]
        [Nullable[bool]]$ApprovalRequired
    )

    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        if (-not @($Capability.category_allowed | ForEach-Object { [string]$_ }).Contains($Category)) {
            return $false
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Agent)) {
        $AllowedAgents = @($Capability.approved_agents | ForEach-Object { [string]$_ })
        if (-not @($AllowedAgents | Where-Object { $_ -ieq $Agent }).Count -gt 0) {
            return $false
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Tool)) {
        $AllowedTools = @($Capability.approved_tools | ForEach-Object { [string]$_ })
        if (-not @($AllowedTools | Where-Object { $_ -ieq $Tool }).Count -gt 0) {
            return $false
        }
    }

    if ($null -ne $ApprovalRequired) {
        $CapabilityApproval = [bool]$Capability.approval_required
        if ($CapabilityApproval -ne [bool]$ApprovalRequired) {
            return $false
        }
    }

    return $true
}

if (-not (Test-Path -LiteralPath $ResolvedRegistryPath -PathType Leaf)) {
    $Result = [pscustomobject]@{
        status = "fail"
        registry_path = $ResolvedRegistryPath
        error = "Capability registry not found."
        count = 0
        filters = [pscustomobject]@{
            capability_id = $CapabilityId
            category = $Category
            agent = $Agent
            tool = $Tool
            approval_required = $ApprovalRequired
        }
        capabilities = @()
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
            capability_id = $CapabilityId
            category = $Category
            agent = $Agent
            tool = $Tool
            approval_required = $ApprovalRequired
        }
        capabilities = @()
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

if ($null -eq $Registry -or -not ($Registry.PSObject.Properties.Name -contains "capabilities")) {
    $Result = [pscustomobject]@{
        status = "fail"
        registry_path = $ResolvedRegistryPath
        error = "Capability registry is missing 'capabilities'."
        count = 0
        filters = [pscustomobject]@{
            capability_id = $CapabilityId
            category = $Category
            agent = $Agent
            tool = $Tool
            approval_required = $ApprovalRequired
        }
        capabilities = @()
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

$ApprovalRequiredValue = $null
if (-not [string]::IsNullOrWhiteSpace($ApprovalRequired)) {
    $ApprovalRequiredValue = ConvertTo-PDACapabilityBoolean -Value $ApprovalRequired
}

$Capabilities = @($Registry.capabilities)
if (-not [string]::IsNullOrWhiteSpace($CapabilityId)) {
    $Capabilities = @($Capabilities | Where-Object { [string]$_.capability_id -ieq $CapabilityId })
}

$Capabilities = @(
    $Capabilities | Where-Object {
        Test-PDACapabilityMatch -Capability $_ -Category $Category -Agent $Agent -Tool $Tool -ApprovalRequired $ApprovalRequiredValue
    }
)

$Report = [pscustomobject]@{
    status = "pass"
    registry_path = $ResolvedRegistryPath
    registry = [pscustomobject]@{
        schema_version = [string]$Registry.schema_version
        policy_name = if ($Registry.PSObject.Properties.Name -contains "policy_name") { [string]$Registry.policy_name } else { "PDA Capability Registry" }
        policy_version = if ($Registry.PSObject.Properties.Name -contains "policy_version") { [string]$Registry.policy_version } else { "1.0" }
        updated_at = if ($Registry.PSObject.Properties.Name -contains "updated_at") { [string]$Registry.updated_at } else { "" }
    }
    count = @($Capabilities).Count
    filters = [pscustomobject]@{
        capability_id = $CapabilityId
        category = $Category
        agent = $Agent
        tool = $Tool
        approval_required = $ApprovalRequired
    }
    capabilities = $Capabilities
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] Capability lookup"
Write-Host ("Registry path : {0}" -f $Report.registry_path)
Write-Host ("Count         : {0}" -f $Report.count)
if ($Report.count -eq 0) {
    Write-Host "No capabilities matched the current filters."
    return
}

$Report.capabilities |
    Select-Object capability_id, display_name, category_allowed, approved_agents, preferred_providers, restricted_local_only, approval_required, risk_level |
    Format-Table -AutoSize
