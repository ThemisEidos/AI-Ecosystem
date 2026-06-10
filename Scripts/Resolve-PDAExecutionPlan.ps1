[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CapabilityId = "",

    [Parameter(Mandatory = $false)]
    [string]$SelectedAgent = "",

    [Parameter(Mandatory = $false)]
    [string]$SelectedProvider = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("category_1", "category_2")]
    [string]$Category = "",

    [Parameter(Mandatory = $false)]
    [string]$RestrictedLocalOnly = "",

    [Parameter(Mandatory = $false)]
    [string]$RegistryPath = "",

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$ResolvedRegistryPath = if (-not [string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath
} else {
    Join-Path $PSScriptRoot "PDA_ExecutionPlanRegistry.json"
}

function ConvertTo-PDAExecutionPlanBoolean {
    param([Parameter(Mandatory = $false)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    switch ($Value.Trim().ToLowerInvariant()) {
        "true" { return $true }
        "false" { return $false }
        "1" { return $true }
        "0" { return $false }
        "yes" { return $true }
        "no" { return $false }
        default { throw "Boolean filter must be true or false." }
    }
}

function Normalize-PDAExecutionPlanToken {
    param([Parameter(Mandatory = $false)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return (([string]$Value).Trim().ToLowerInvariant()) -replace "[^a-z0-9]+", ""
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

function Get-PDAExecutionPlanEntry {
    param(
        [Parameter(Mandatory = $true)]$Registry,
        [Parameter(Mandatory = $true)][string]$CapabilityId
    )

    $Plans = @($Registry.execution_plans)
    if ($Plans.Count -eq 0) {
        return $null
    }

    $NormalizedCapability = Normalize-PDAExecutionPlanToken -Value $CapabilityId
    foreach ($Plan in $Plans) {
        if (-not $Plan) {
            continue
        }
        if ((Normalize-PDAExecutionPlanToken -Value ([string]$Plan.capability_id)) -eq $NormalizedCapability) {
            return $Plan
        }
    }

    return $null
}

function Get-PDAExecutionPlanSelection {
    param(
        [Parameter(Mandatory = $true)]$Registry,
        [Parameter(Mandatory = $true)][string]$CapabilityId,
        [Parameter(Mandatory = $false)][string]$SelectedAgent = "",
        [Parameter(Mandatory = $false)][string]$SelectedProvider = "",
        [Parameter(Mandatory = $false)][string]$Category = "",
        [Parameter(Mandatory = $false)]$RestrictedLocalOnly = $null
    )

    if ([string]::IsNullOrWhiteSpace($CapabilityId)) {
        return [pscustomobject]@{
            status = "fail"
            blocked_reason = "CapabilityId is required."
            execution_plan_id = ""
            execution_steps = @()
            approval_required = $false
            restricted_local_only = $false
            estimated_complexity = ""
            estimated_steps = 0
            success_criteria = @()
            outputs = @()
            routing_reason = "CapabilityId is required."
            provider_strategy = $null
            candidate_providers = @()
        }
    }

    $Plan = Get-PDAExecutionPlanEntry -Registry $Registry -CapabilityId $CapabilityId
    if (-not $Plan) {
        return [pscustomobject]@{
            status = "fail"
            blocked_reason = "Capability '$CapabilityId' does not have a registered execution plan."
            execution_plan_id = ""
            execution_steps = @()
            approval_required = $false
            restricted_local_only = $false
            estimated_complexity = ""
            estimated_steps = 0
            success_criteria = @()
            outputs = @()
            routing_reason = "Capability '$CapabilityId' was not found in the execution plan registry."
            provider_strategy = $null
            candidate_providers = @()
        }
    }

    $ResolvedCategory = ([string]$Category).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($ResolvedCategory)) {
        $ResolvedCategory = ""
    }

    $RestrictedInputProvided = $false
    $ResolvedRestrictedLocalOnly = $false
    if ($null -ne $RestrictedLocalOnly) {
        $ResolvedRestrictedLocalOnly = [bool]$RestrictedLocalOnly
        $RestrictedInputProvided = $true
    }

    if ($ResolvedCategory -eq "category_2") {
        $ResolvedRestrictedLocalOnly = $true
    }
    if ([bool]$Plan.restricted_local_only) {
        $ResolvedRestrictedLocalOnly = $true
    }

    if ($ResolvedCategory -eq "category_2" -and -not [bool]$Plan.restricted_local_only) {
        return [pscustomobject]@{
            status = "fail"
            blocked_reason = "Capability '$CapabilityId' does not have a local-only execution plan for Category 2."
            execution_plan_id = [string]$Plan.execution_plan_id
            execution_steps = @()
            approval_required = [bool]$Plan.approval_required
            restricted_local_only = $false
            estimated_complexity = [string]$Plan.estimated_complexity
            estimated_steps = [int]$Plan.estimated_steps
            success_criteria = @()
            outputs = @()
            routing_reason = "Category 2 requires a local-only execution plan, but '$([string]$Plan.execution_plan_id)' is not local-only."
            provider_strategy = $Plan.provider_strategy
            candidate_providers = @()
        }
    }

    if ($ResolvedRestrictedLocalOnly -and -not [bool]$Plan.restricted_local_only) {
        return [pscustomobject]@{
            status = "fail"
            blocked_reason = "Capability '$CapabilityId' does not have a local-only execution plan."
            execution_plan_id = [string]$Plan.execution_plan_id
            execution_steps = @()
            approval_required = [bool]$Plan.approval_required
            restricted_local_only = $false
            estimated_complexity = [string]$Plan.estimated_complexity
            estimated_steps = [int]$Plan.estimated_steps
            success_criteria = @()
            outputs = @()
            routing_reason = "Restricted-local routing requires a local-only plan."
            provider_strategy = $Plan.provider_strategy
            candidate_providers = @()
        }
    }

    $ProviderStrategy = $Plan.provider_strategy
    $DefaultProvider = if ($ProviderStrategy -and $ProviderStrategy.PSObject.Properties.Name -contains "default_provider" -and -not [string]::IsNullOrWhiteSpace([string]$ProviderStrategy.default_provider)) {
        [string]$ProviderStrategy.default_provider
    } else {
        "local-llama"
    }

    $PreferredProviders = @()
    if ($ProviderStrategy -and $ProviderStrategy.PSObject.Properties.Name -contains "preferred_providers") {
        $PreferredProviders = @($ProviderStrategy.preferred_providers | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $FallbackProviders = @()
    if ($ProviderStrategy -and $ProviderStrategy.PSObject.Properties.Name -contains "fallback_providers") {
        $FallbackProviders = @($ProviderStrategy.fallback_providers | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $CandidateProviders = New-Object System.Collections.Generic.List[string]
    foreach ($Provider in @(@($DefaultProvider) + @($PreferredProviders) + @($FallbackProviders))) {
        if (-not [string]::IsNullOrWhiteSpace($Provider) -and -not $CandidateProviders.Contains([string]$Provider)) {
            $CandidateProviders.Add([string]$Provider) | Out-Null
        }
    }

    $RequestedProvider = ([string]$SelectedProvider).Trim()
    if ([string]::IsNullOrWhiteSpace($RequestedProvider)) {
        $RequestedProvider = $DefaultProvider
    }

    $EscalationRequired = $RequestedProvider -ne $DefaultProvider
    $DefaultedToLocal = $RequestedProvider -eq $DefaultProvider
    $CloudAllowed = -not $ResolvedRestrictedLocalOnly
    $ApprovalRequired = [bool]$Plan.approval_required

    $ContextParts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($SelectedAgent)) {
        $ContextParts.Add(("agent={0}" -f $SelectedAgent)) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($SelectedProvider)) {
        $ContextParts.Add(("provider={0}" -f $SelectedProvider)) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($ResolvedCategory)) {
        $ContextParts.Add(("category={0}" -f $ResolvedCategory)) | Out-Null
    }
    if ($RestrictedInputProvided) {
        $ContextParts.Add(("restricted_local_only={0}" -f $ResolvedRestrictedLocalOnly)) | Out-Null
    }

    if ($ResolvedRestrictedLocalOnly) {
        $RoutingReason = "Restricted-local routing selected '$([string]$Plan.execution_plan_id)' and enforced local-llama."
    }
    elseif ($RequestedProvider -eq $DefaultProvider) {
        $RoutingReason = "Capability '$CapabilityId' resolved to '$([string]$Plan.execution_plan_id)' with the local-first default provider '$DefaultProvider'."
    }
    elseif (@($PreferredProviders) -contains $RequestedProvider) {
        $RoutingReason = "Capability '$CapabilityId' resolved to '$([string]$Plan.execution_plan_id)' and escalated to preferred provider '$RequestedProvider'."
    }
    elseif (@($FallbackProviders) -contains $RequestedProvider) {
        $RoutingReason = "Capability '$CapabilityId' resolved to '$([string]$Plan.execution_plan_id)' and used fallback provider '$RequestedProvider'."
    }
    else {
        $RoutingReason = "Capability '$CapabilityId' resolved to '$([string]$Plan.execution_plan_id)' with provider context '$RequestedProvider'."
    }

    if ($ContextParts.Count -gt 0) {
        $RoutingReason = "{0} Context: {1}." -f $RoutingReason, ($ContextParts -join "; ")
    }

    return [pscustomobject]@{
        status = "pass"
        execution_plan_id = [string]$Plan.execution_plan_id
        capability = [string]$Plan.capability_id
        selected_agent = [string]$SelectedAgent
        selected_provider = [string]$RequestedProvider
        category = [string]$ResolvedCategory
        execution_steps = @($Plan.execution_steps)
        approval_required = [bool]$ApprovalRequired
        restricted_local_only = [bool]$ResolvedRestrictedLocalOnly
        estimated_complexity = [string]$Plan.estimated_complexity
        estimated_steps = [int]$Plan.estimated_steps
        success_criteria = @($Plan.success_criteria)
        outputs = @($Plan.outputs)
        routing_reason = [string]$RoutingReason
        defaulted_to_local = [bool]$DefaultedToLocal
        escalation_required = [bool]$EscalationRequired
        cloud_allowed = [bool]$CloudAllowed
        provider_strategy = $ProviderStrategy
        candidate_providers = @($CandidateProviders)
        source_of_truth = "Scripts/Resolve-PDAExecutionPlan.ps1"
    }
}

$RegistryLoad = Get-PDARegistryLoadResult -Path $ResolvedRegistryPath -RegistryName "Execution plan registry"
if ($RegistryLoad.status -ne "pass") {
    $Result = [pscustomobject]@{
        status = "fail"
        blocked_reason = $RegistryLoad.error
        execution_plan_id = ""
        execution_steps = @()
        approval_required = $false
        restricted_local_only = $false
        estimated_complexity = ""
        estimated_steps = 0
        success_criteria = @()
        outputs = @()
        routing_reason = $RegistryLoad.error
        defaulted_to_local = $false
        escalation_required = $false
        cloud_allowed = $false
        provider_strategy = $null
        candidate_providers = @()
        source_of_truth = "Scripts/Resolve-PDAExecutionPlan.ps1"
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

$Registry = $RegistryLoad.registry
$Selection = Get-PDAExecutionPlanSelection -Registry $Registry -CapabilityId $CapabilityId -SelectedAgent $SelectedAgent -SelectedProvider $SelectedProvider -Category $Category -RestrictedLocalOnly (ConvertTo-PDAExecutionPlanBoolean -Value $RestrictedLocalOnly)

$Result = [pscustomobject]@{
    status = $Selection.status
    blocked_reason = if ($Selection.PSObject.Properties.Name -contains "blocked_reason") { [string]$Selection.blocked_reason } else { "" }
    execution_plan_registry_path = $ResolvedRegistryPath
    execution_plan_id = [string]$Selection.execution_plan_id
    capability = [string]$Selection.capability
    selected_agent = [string]$Selection.selected_agent
    selected_provider = [string]$Selection.selected_provider
    category = [string]$Selection.category
    execution_steps = @($Selection.execution_steps)
    approval_required = [bool]$Selection.approval_required
    restricted_local_only = [bool]$Selection.restricted_local_only
    estimated_complexity = [string]$Selection.estimated_complexity
    estimated_steps = [int]$Selection.estimated_steps
    success_criteria = @($Selection.success_criteria)
    outputs = @($Selection.outputs)
    routing_reason = [string]$Selection.routing_reason
    defaulted_to_local = [bool]$Selection.defaulted_to_local
    escalation_required = [bool]$Selection.escalation_required
    cloud_allowed = [bool]$Selection.cloud_allowed
    provider_strategy = $Selection.provider_strategy
    candidate_providers = @($Selection.candidate_providers)
    source_of_truth = "Scripts/Resolve-PDAExecutionPlan.ps1"
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    if ($Result.status -ne "pass" -and -not $NoThrow) {
        throw $Result.blocked_reason
    }
    return
}

if ($Result.status -eq "pass") {
    Write-Host "[OK] PDA execution plan resolution"
    Write-Host ("Capability      : {0}" -f $Result.capability)
    Write-Host ("Execution plan  : {0}" -f $Result.execution_plan_id)
    Write-Host ("Agent           : {0}" -f $(if ($Result.selected_agent) { $Result.selected_agent } else { "(none)" }))
    Write-Host ("Provider        : {0}" -f $Result.selected_provider)
    Write-Host ("Category        : {0}" -f $(if ($Result.category) { $Result.category } else { "(none)" }))
    Write-Host ("Local-only      : {0}" -f $Result.restricted_local_only)
    Write-Host ("Approval req'd  : {0}" -f $Result.approval_required)
    Write-Host ("Reason          : {0}" -f $Result.routing_reason)
    return
}

Write-Host "[ERROR] $($Result.blocked_reason)"
if (-not $NoThrow) {
    throw $Result.blocked_reason
}
