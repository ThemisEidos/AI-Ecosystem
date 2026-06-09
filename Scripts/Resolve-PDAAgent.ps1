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
    [string]$RestrictedLocalOnly = "",

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow,

    [Parameter(Mandatory = $false)]
    [string]$CapabilityRegistryPath = "",

    [Parameter(Mandatory = $false)]
    [string]$AgentRegistryPath = ""
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ResolvedCapabilityRegistryPath = if (-not [string]::IsNullOrWhiteSpace($CapabilityRegistryPath)) {
    $CapabilityRegistryPath
} else {
    Join-Path $PSScriptRoot "PDA_CapabilityRegistry.json"
}
$ResolvedAgentRegistryPath = if (-not [string]::IsNullOrWhiteSpace($AgentRegistryPath)) {
    $AgentRegistryPath
} else {
    Join-Path $PSScriptRoot "PDA_AgentProfileRegistry.json"
}

function ConvertTo-PDARouteBoolean {
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

function Normalize-PDARouteToken {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return (($Value.ToLowerInvariant()) -replace "[^a-z0-9]+", "")
}

function Get-PDARegistryLoadResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$RegistryName
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            status = "fail"
            error = "$RegistryName not found."
            path = $Path
            registry = $null
        }
    }

    try {
        $Raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $Registry = $Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return [pscustomobject]@{
            status = "fail"
            error = $_.Exception.Message
            path = $Path
            registry = $null
        }
    }

    return [pscustomobject]@{
        status = "pass"
        error = ""
        path = $Path
        registry = $Registry
    }
}

function Get-PDAAgentLookup {
    param([Parameter(Mandatory = $true)]$Profiles)

    $Lookup = @{}
    foreach ($Profile in @($Profiles)) {
        if (-not $Profile) { continue }
        foreach ($Key in @([string]$Profile.agent_id, [string]$Profile.display_name)) {
            if ([string]::IsNullOrWhiteSpace($Key)) { continue }
            $Lookup[(Normalize-PDARouteToken -Value $Key)] = $Profile
        }
    }

    return $Lookup
}

function Resolve-PDAAgentSelection {
    param(
        [Parameter(Mandatory = $true)]$Capability,
        [Parameter(Mandatory = $true)]$Profiles,
        [Parameter(Mandatory = $false)][string]$Category = "",
        [Parameter(Mandatory = $false)][string]$Agent = "",
        [Parameter(Mandatory = $false)][string]$Tool = "",
        [Parameter(Mandatory = $false)][Nullable[bool]]$ApprovalRequired,
        [Parameter(Mandatory = $false)][Nullable[bool]]$RestrictedLocalOnly
    )

    $CapabilityId = [string]$Capability.capability_id
    $CapabilityCategoryAllowed = @($Capability.category_allowed | ForEach-Object { [string]$_ })
    $CapabilityApprovedAgents = @($Capability.approved_agents | ForEach-Object { [string]$_ })
    $CapabilityApprovedTools = @($Capability.approved_tools | ForEach-Object { [string]$_ })
    $CapabilityRestrictedLocalOnly = [bool]$Capability.restricted_local_only
    $CapabilityApprovalRequired = [bool]$Capability.approval_required
    $AgentLookup = Get-PDAAgentLookup -Profiles $Profiles

    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        if (-not @($CapabilityCategoryAllowed | Where-Object { $_ -ieq $Category }).Count) {
            return [pscustomobject]@{
                status = "blocked"
                selected_agent = ""
                selected_agent_display_name = ""
                candidate_agents = @()
                candidate_agent_details = @()
                routing_reason = "Capability '$CapabilityId' is not allowed for category '$Category'."
                restricted_local_only = $CapabilityRestrictedLocalOnly
                approval_required = $CapabilityApprovalRequired
                capability = $CapabilityId
                category = $Category
                blocked_reason = "Capability is not authorized for the requested category."
            }
        }
    }

    $Candidates = @(
        $Profiles | Where-Object {
            $ProfileCapabilities = @($_.approved_capabilities | ForEach-Object { [string]$_ })
            if (-not (@($ProfileCapabilities | Where-Object { $_ -ieq $CapabilityId }).Count -gt 0)) {
                return $false
            }
            if (-not [string]::IsNullOrWhiteSpace($Category)) {
                $AllowedCategories = @($_.category_allowed | ForEach-Object { [string]$_ })
                if (-not (@($AllowedCategories | Where-Object { $_ -ieq $Category }).Count -gt 0)) {
                    return $false
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($Tool)) {
                $AllowedTools = @($_.approved_tools | ForEach-Object { [string]$_ })
                if (-not (@($AllowedTools | Where-Object { $_ -ieq $Tool }).Count -gt 0)) {
                    return $false
                }
            }
            if ($null -ne $ApprovalRequired) {
                if ([bool]$_.approval_required_default -ne [bool]$ApprovalRequired) {
                    return $false
                }
            }
            if ($null -ne $RestrictedLocalOnly) {
                if ([bool]$_.restricted_local_only -ne [bool]$RestrictedLocalOnly) {
                    return $false
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($Agent)) {
                if (-not (
                    [string]$_.agent_id -ieq $Agent -or
                    [string]$_.display_name -ieq $Agent
                )) {
                    return $false
                }
            }
            return $true
        }
    )

    if ($CapabilityRestrictedLocalOnly) {
        $Candidates = @($Candidates | Where-Object { [bool]$_.restricted_local_only })
    }

    $ApprovedOrder = @{}
    for ($Index = 0; $Index -lt @($CapabilityApprovedAgents).Count; $Index++) {
        $ApprovedOrder[(Normalize-PDARouteToken -Value $CapabilityApprovedAgents[$Index])] = $Index
    }

    $Ranked = foreach ($Candidate in $Candidates) {
        $NormalizedId = Normalize-PDARouteToken -Value ([string]$Candidate.agent_id)
        $NormalizedDisplay = Normalize-PDARouteToken -Value ([string]$Candidate.display_name)
        $ApprovedIndex = [int]::MaxValue
        if ($ApprovedOrder.ContainsKey($NormalizedId)) {
            $ApprovedIndex = [int]$ApprovedOrder[$NormalizedId]
        }
        elseif ($ApprovedOrder.ContainsKey($NormalizedDisplay)) {
            $ApprovedIndex = [int]$ApprovedOrder[$NormalizedDisplay]
        }

        $RiskLevelToken = ([string]$Candidate.risk_level).ToLowerInvariant()
        [pscustomobject]@{
            profile = $Candidate
            approved_index = $ApprovedIndex
            approval_default = [bool]$Candidate.approval_required_default
            restricted_local_only = [bool]$Candidate.restricted_local_only
            risk_level = switch ($RiskLevelToken) {
                "low" { 0 }
                "medium" { 1 }
                "high" { 2 }
                default { 3 }
            }
            agent_id = [string]$Candidate.agent_id
            display_name = [string]$Candidate.display_name
        }
    }

    $Sorted = @(
        $Ranked | Sort-Object -Property @{
            Expression = { if ($_.approved_index -eq [int]::MaxValue) { 1 } else { 0 } }
        }, @{
            Expression = { $_.approved_index }
        }, @{
            Expression = { $_.risk_level }
        }, @{
            Expression = { if ($_.approval_default) { 1 } else { 0 } }
        }, @{
            Expression = { $_.agent_id }
        }
    )

    $CandidateAgentIds = @($Sorted | ForEach-Object { [string]$_.agent_id })
    $CandidateDetails = @(
        $Sorted | ForEach-Object {
            [pscustomobject]@{
                agent_id = [string]$_.agent_id
                display_name = [string]$_.display_name
                approval_required_default = [bool]$_.approval_default
                restricted_local_only = [bool]$_.restricted_local_only
                approved_index = [int]$_.approved_index
                risk_level = switch ($_.risk_level) {
                    0 { "low" }
                    1 { "medium" }
                    2 { "high" }
                    default { "unknown" }
                }
            }
        }
    )

    if ($CandidateAgentIds.Count -eq 0) {
        return [pscustomobject]@{
            status = "blocked"
            selected_agent = ""
            selected_agent_display_name = ""
            candidate_agents = @()
            candidate_agent_details = @()
            routing_reason = "No registered agent matched capability '$CapabilityId'."
            restricted_local_only = $CapabilityRestrictedLocalOnly
            approval_required = $CapabilityApprovalRequired
            capability = $CapabilityId
            category = $Category
            blocked_reason = "No registered agent matched the capability."
        }
    }

    $Selected = $Sorted | Select-Object -First 1
    $Reason = if ($CapabilityRestrictedLocalOnly) {
        "Restricted local capability '$CapabilityId' must route to the restricted agent."
    }
    elseif ($Selected.approved_index -ne [int]::MaxValue) {
        "Capability '$CapabilityId' prefers approved agent '$($Selected.display_name)' by registry order."
    }
    else {
        "Capability '$CapabilityId' matched agent '$($Selected.display_name)' by deterministic fallback."
    }

    return [pscustomobject]@{
        status = "pass"
        selected_agent = [string]$Selected.agent_id
        selected_agent_display_name = [string]$Selected.display_name
        candidate_agents = $CandidateAgentIds
        candidate_agent_details = $CandidateDetails
        routing_reason = $Reason
        restricted_local_only = $CapabilityRestrictedLocalOnly
        approval_required = $CapabilityApprovalRequired
        capability = $CapabilityId
        category = $Category
        source_of_truth = "Scripts/Resolve-PDAAgent.ps1"
    }
}

$CapabilityLoad = Get-PDARegistryLoadResult -Path $ResolvedCapabilityRegistryPath -RegistryName "Capability registry"
$AgentLoad = Get-PDARegistryLoadResult -Path $ResolvedAgentRegistryPath -RegistryName "Agent profile registry"

if ($CapabilityLoad.status -ne "pass") {
    $Result = [pscustomobject]@{
        status = "fail"
        capability = $CapabilityId
        selected_agent = ""
        candidate_agents = @()
        routing_reason = $CapabilityLoad.error
        restricted_local_only = $false
        approval_required = $false
        candidate_agent_details = @()
        blocked_reason = $CapabilityLoad.error
        capability_registry_path = $ResolvedCapabilityRegistryPath
        agent_registry_path = $ResolvedAgentRegistryPath
        source_of_truth = "Scripts/Resolve-PDAAgent.ps1"
    }
    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        if (-not $NoThrow) { throw $Result.blocked_reason }
        return
    }
    Write-Host "[ERROR] $($Result.blocked_reason)"
    if (-not $NoThrow) { throw $Result.blocked_reason }
    return
}

if ($AgentLoad.status -ne "pass") {
    $Result = [pscustomobject]@{
        status = "fail"
        capability = $CapabilityId
        selected_agent = ""
        candidate_agents = @()
        routing_reason = $AgentLoad.error
        restricted_local_only = $false
        approval_required = $false
        candidate_agent_details = @()
        blocked_reason = $AgentLoad.error
        capability_registry_path = $ResolvedCapabilityRegistryPath
        agent_registry_path = $ResolvedAgentRegistryPath
        source_of_truth = "Scripts/Resolve-PDAAgent.ps1"
    }
    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        if (-not $NoThrow) { throw $Result.blocked_reason }
        return
    }
    Write-Host "[ERROR] $($Result.blocked_reason)"
    if (-not $NoThrow) { throw $Result.blocked_reason }
    return
}

$CapabilityRegistry = $CapabilityLoad.registry
$AgentRegistry = $AgentLoad.registry
$Capabilities = @($CapabilityRegistry.capabilities)
$Profiles = @($AgentRegistry.agent_profiles)

if ([string]::IsNullOrWhiteSpace($CapabilityId)) {
    $Result = [pscustomobject]@{
        status = "fail"
        capability = ""
        selected_agent = ""
        candidate_agents = @()
        candidate_agent_details = @()
        routing_reason = "CapabilityId is required."
        restricted_local_only = $false
        approval_required = $false
        blocked_reason = "CapabilityId is required."
        capability_registry_path = $ResolvedCapabilityRegistryPath
        agent_registry_path = $ResolvedAgentRegistryPath
        capability_registry_count = @($Capabilities).Count
        agent_profile_count = @($Profiles).Count
        source_of_truth = "Scripts/Resolve-PDAAgent.ps1"
    }
    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        if (-not $NoThrow) { throw $Result.blocked_reason }
        return
    }
    Write-Host "[ERROR] $($Result.blocked_reason)"
    if (-not $NoThrow) { throw $Result.blocked_reason }
    return
}

$Capability = @($Capabilities | Where-Object { [string]$_.capability_id -ieq $CapabilityId } | Select-Object -First 1)
if (-not $Capability) {
    $Result = [pscustomobject]@{
        status = "fail"
        capability = $CapabilityId
        selected_agent = ""
        candidate_agents = @()
        candidate_agent_details = @()
        routing_reason = "Capability '$CapabilityId' was not found in the registry."
        restricted_local_only = $false
        approval_required = $false
        blocked_reason = "Capability '$CapabilityId' was not found in the registry."
        capability_registry_path = $ResolvedCapabilityRegistryPath
        agent_registry_path = $ResolvedAgentRegistryPath
        capability_registry_count = @($Capabilities).Count
        agent_profile_count = @($Profiles).Count
        source_of_truth = "Scripts/Resolve-PDAAgent.ps1"
    }
    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        if (-not $NoThrow) { throw $Result.blocked_reason }
        return
    }
    Write-Host "[ERROR] $($Result.blocked_reason)"
    if (-not $NoThrow) { throw $Result.blocked_reason }
    return
}

$ApprovalValue = $null
if (-not [string]::IsNullOrWhiteSpace($ApprovalRequired)) {
    $ApprovalValue = ConvertTo-PDARouteBoolean -Value $ApprovalRequired
}

$RestrictedValue = $null
if (-not [string]::IsNullOrWhiteSpace($RestrictedLocalOnly)) {
    $RestrictedValue = ConvertTo-PDARouteBoolean -Value $RestrictedLocalOnly
}

$Selection = Resolve-PDAAgentSelection -Capability $Capability -Profiles $Profiles -Category $Category -Agent $Agent -Tool $Tool -ApprovalRequired $ApprovalValue -RestrictedLocalOnly $RestrictedValue

$Result = [pscustomobject]@{
    status = $Selection.status
    capability = [string]$Selection.capability
    selected_agent = [string]$Selection.selected_agent
    selected_agent_display_name = [string]$Selection.selected_agent_display_name
    candidate_agents = @($Selection.candidate_agents)
    candidate_agent_details = @($Selection.candidate_agent_details)
    routing_reason = [string]$Selection.routing_reason
    restricted_local_only = [bool]$Selection.restricted_local_only
    approval_required = [bool]$Selection.approval_required
    blocked_reason = if ($Selection.PSObject.Properties.Name -contains "blocked_reason") { [string]$Selection.blocked_reason } else { "" }
    capability_registry_path = $ResolvedCapabilityRegistryPath
    agent_registry_path = $ResolvedAgentRegistryPath
    capability_registry_count = @($Capabilities).Count
    agent_profile_count = @($Profiles).Count
    source_of_truth = "Scripts/Resolve-PDAAgent.ps1"
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    return
}

if ($Result.status -eq "pass") {
    Write-Host "[OK] Capability to agent resolution"
    Write-Host ("Capability      : {0}" -f $Result.capability)
    Write-Host ("Selected agent  : {0}" -f $Result.selected_agent)
    Write-Host ("Candidates      : {0}" -f ($(if ($Result.candidate_agents.Count -gt 0) { $Result.candidate_agents -join ", " } else { "(none)" })))
    Write-Host ("Reason          : {0}" -f $Result.routing_reason)
    Write-Host ("Approval req'd  : {0}" -f $Result.approval_required)
    Write-Host ("Local-only      : {0}" -f $Result.restricted_local_only)
    return
}

Write-Host "[ERROR] $($Result.blocked_reason)"
if (-not $NoThrow) {
    throw $Result.blocked_reason
}
