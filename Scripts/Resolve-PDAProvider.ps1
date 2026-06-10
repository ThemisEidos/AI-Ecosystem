[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CapabilityId = "",

    [Parameter(Mandatory = $false)]
    [string]$SelectedAgent = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("category_1", "category_2")]
    [string]$Category = "",

    [Parameter(Mandatory = $false)]
    [string]$RequestedProvider = "",

    [Parameter(Mandatory = $false)]
    [string[]]$ApprovedProviders = @(),

    [Parameter(Mandatory = $false)]
    [string[]]$PreferredProviders = @(),

    [Parameter(Mandatory = $false)]
    [string[]]$FallbackProviders = @(),

    [Parameter(Mandatory = $false)]
    [string]$RestrictedLocalOnly = "",

    [Parameter(Mandatory = $false)]
    [Nullable[double]]$LocalConfidence = $null,

    [Parameter(Mandatory = $false)]
    [double]$ConfidenceThreshold = 0.65,

    [Parameter(Mandatory = $false)]
    [string]$CapabilityRegistryPath = "",

    [Parameter(Mandatory = $false)]
    [string]$AgentRegistryPath = "",

    [Parameter(Mandatory = $false)]
    [string]$PolicyPath = "",

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$ResolvedPolicyPath = if (-not [string]::IsNullOrWhiteSpace($PolicyPath)) {
    $PolicyPath
}
else {
    Join-Path $PSScriptRoot "PDA_ProviderRoutingPolicy.json"
}
$ResolvedCapabilityRegistryPath = if (-not [string]::IsNullOrWhiteSpace($CapabilityRegistryPath)) {
    $CapabilityRegistryPath
}
else {
    Join-Path $PSScriptRoot "PDA_CapabilityRegistry.json"
}
$ResolvedAgentRegistryPath = if (-not [string]::IsNullOrWhiteSpace($AgentRegistryPath)) {
    $AgentRegistryPath
}
else {
    Join-Path $PSScriptRoot "PDA_AgentProfileRegistry.json"
}

function ConvertTo-PDAProviderBoolean {
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

function Normalize-PDAProviderToken {
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

function Get-PDAProviderCatalog {
    param([Parameter(Mandatory = $true)]$Policy)

    $AliasLookup = @{}
    $CatalogLookup = @{}
    $Catalog = @()

    foreach ($Entry in @($Policy.provider_catalog)) {
        if (-not $Entry) {
            continue
        }

        $ProviderId = [string]$Entry.provider_id
        if ([string]::IsNullOrWhiteSpace($ProviderId)) {
            continue
        }

        $NormalizedId = Normalize-PDAProviderToken -Value $ProviderId
        $CatalogLookup[$NormalizedId] = $Entry
        $AliasLookup[$NormalizedId] = $ProviderId

        foreach ($Alias in @($Entry.aliases)) {
            $AliasToken = Normalize-PDAProviderToken -Value ([string]$Alias)
            if (-not [string]::IsNullOrWhiteSpace($AliasToken)) {
                $AliasLookup[$AliasToken] = $ProviderId
            }
        }

        $Catalog += [pscustomobject]@{
            provider_id = $ProviderId
            display_name = [string]$Entry.display_name
            provider_family = [string]$Entry.provider_family
            cloud_allowed = [bool]$Entry.cloud_allowed
            local_only = [bool]$Entry.local_only
            default = [bool]$Entry.default
            notes = [string]$Entry.notes
        }
    }

    return [pscustomobject]@{
        alias_lookup = $AliasLookup
        catalog_lookup = $CatalogLookup
        catalog = @($Catalog)
    }
}

function Resolve-PDAProviderId {
    param(
        [Parameter(Mandatory = $false)][string]$Value,
        [Parameter(Mandatory = $true)][hashtable]$AliasLookup
    )

    $Token = Normalize-PDAProviderToken -Value $Value
    if ([string]::IsNullOrWhiteSpace($Token)) {
        return ""
    }

    if ($AliasLookup.ContainsKey($Token)) {
        return [string]$AliasLookup[$Token]
    }

    return ""
}

function Get-PDARecordValueList {
    param(
        [Parameter(Mandatory = $false)]$Record,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    if (-not $Record -or -not ($Record.PSObject.Properties.Name -contains $PropertyName)) {
        return @()
    }

    return @($Record.$PropertyName | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Add-PDAProviderCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$ProviderId,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][object]$Details,
        [Parameter(Mandatory = $true)][object]$OrderedProviders,
        [Parameter(Mandatory = $true)][hashtable]$CatalogLookup
    )

    if ([string]::IsNullOrWhiteSpace($ProviderId)) {
        return
    }

    $DetailTarget = $Details -as [System.Collections.IList]
    $OrderedTarget = $OrderedProviders -as [System.Collections.IList]
    if (-not $OrderedTarget) {
        return
    }

    if ($OrderedTarget.Contains($ProviderId)) {
        return
    }

    $OrderedTarget.Add($ProviderId) | Out-Null

    $CatalogEntry = $null
    if ($CatalogLookup.ContainsKey((Normalize-PDAProviderToken -Value $ProviderId))) {
        $CatalogEntry = $CatalogLookup[(Normalize-PDAProviderToken -Value $ProviderId)]
    }

    if ($DetailTarget) {
        $DetailTarget.Add([pscustomobject]@{
            provider_id = $ProviderId
            display_name = if ($CatalogEntry) { [string]$CatalogEntry.display_name } else { $ProviderId }
            provider_family = if ($CatalogEntry) { [string]$CatalogEntry.provider_family } else { "" }
            cloud_allowed = if ($CatalogEntry) { [bool]$CatalogEntry.cloud_allowed } else { $true }
            local_only = if ($CatalogEntry) { [bool]$CatalogEntry.local_only } else { $false }
            source = $Source
        }) | Out-Null
    }
}

function Get-PDAProviderDisplayName {
    param(
        [Parameter(Mandatory = $true)][string]$ProviderId,
        [Parameter(Mandatory = $true)][hashtable]$CatalogLookup
    )

    $Normalized = Normalize-PDAProviderToken -Value $ProviderId
    if ($CatalogLookup.ContainsKey($Normalized)) {
        return [string]$CatalogLookup[$Normalized].display_name
    }

    return $ProviderId
}

function Resolve-PDAProviderSelection {
    param(
        [Parameter(Mandatory = $false)]$Capability,
        [Parameter(Mandatory = $false)]$AgentProfile,
        [Parameter(Mandatory = $false)]$Policy,
        [Parameter(Mandatory = $true)][hashtable]$CatalogLookup,
        [Parameter(Mandatory = $true)][hashtable]$AliasLookup,
        [Parameter(Mandatory = $false)][string]$CapabilityId = "",
        [Parameter(Mandatory = $false)][string]$SelectedAgent = "",
        [Parameter(Mandatory = $false)][string]$Category = "",
        [Parameter(Mandatory = $false)][string]$RequestedProvider = "",
        [Parameter(Mandatory = $false)][string[]]$ApprovedProviders = @(),
        [Parameter(Mandatory = $false)][string[]]$PreferredProviders = @(),
        [Parameter(Mandatory = $false)][string[]]$FallbackProviders = @(),
        [Parameter(Mandatory = $false)]$RestrictedLocalOnly = $null,
        [Parameter(Mandatory = $false)]$LocalConfidence = $null,
        [Parameter(Mandatory = $false)][double]$ConfidenceThreshold = 0.65
    )

    $CapabilityPreferred = @(Get-PDARecordValueList -Record $Capability -PropertyName "preferred_providers")
    $CapabilityFallback = @(Get-PDARecordValueList -Record $Capability -PropertyName "fallback_providers")
    $AgentPreferred = @(Get-PDARecordValueList -Record $AgentProfile -PropertyName "preferred_providers")
    $AgentFallback = @(Get-PDARecordValueList -Record $AgentProfile -PropertyName "fallback_providers")

    $CapabilityApprovalRequired = if ($Capability) { [bool]$Capability.approval_required } else { $false }
    $AgentApprovalRequired = if ($AgentProfile -and $AgentProfile.PSObject.Properties.Name -contains "approval_required_default") { [bool]$AgentProfile.approval_required_default } else { $false }
    $CapabilityRestricted = if ($Capability) { [bool]$Capability.restricted_local_only } else { $false }
    $AgentRestricted = if ($AgentProfile) { [bool]$AgentProfile.restricted_local_only } else { $false }

    $ResolvedCategory = ([string]$Category).Trim().ToLowerInvariant()
    if ($ResolvedCategory -eq "category_2") {
        $ResolvedCategory = "category_2"
    }
    elseif ($ResolvedCategory -in @("restricted_local", "local", "local_only", "local-only", "sensitive")) {
        $ResolvedCategory = "restricted_local"
    }
    else {
        $ResolvedCategory = "category_1"
    }

    $ResolvedRestrictedLocalOnly = $false
    if ($null -ne $RestrictedLocalOnly) {
        $ResolvedRestrictedLocalOnly = [bool]$RestrictedLocalOnly
    }
    if ($ResolvedCategory -in @("category_2", "restricted_local")) {
        $ResolvedRestrictedLocalOnly = $true
    }
    if ($CapabilityRestricted -or $AgentRestricted) {
        $ResolvedRestrictedLocalOnly = $true
    }

    $CloudAllowed = -not $ResolvedRestrictedLocalOnly
    $ApprovalRequired = [bool]($CapabilityApprovalRequired -or $AgentApprovalRequired)

    $ApprovedProviderIds = New-Object System.Collections.Generic.List[string]
    foreach ($Value in @($ApprovedProviders)) {
        $ProviderId = Resolve-PDAProviderId -Value $Value -AliasLookup $AliasLookup
        if (-not [string]::IsNullOrWhiteSpace($ProviderId) -and -not $ApprovedProviderIds.Contains($ProviderId)) {
            $ApprovedProviderIds.Add($ProviderId) | Out-Null
        }
    }

    $PreferredProviderIds = New-Object System.Collections.Generic.List[string]
    foreach ($Value in @($PreferredProviders + $CapabilityPreferred + $AgentPreferred)) {
        $ProviderId = Resolve-PDAProviderId -Value $Value -AliasLookup $AliasLookup
        if (-not [string]::IsNullOrWhiteSpace($ProviderId) -and -not $PreferredProviderIds.Contains($ProviderId)) {
            $PreferredProviderIds.Add($ProviderId) | Out-Null
        }
    }

    $FallbackProviderIds = New-Object System.Collections.Generic.List[string]
    foreach ($Value in @($FallbackProviders + $CapabilityFallback + $AgentFallback + @($Policy.cloud_fallback_provider_order))) {
        $ProviderId = Resolve-PDAProviderId -Value $Value -AliasLookup $AliasLookup
        if (-not [string]::IsNullOrWhiteSpace($ProviderId) -and -not $FallbackProviderIds.Contains($ProviderId)) {
            $FallbackProviderIds.Add($ProviderId) | Out-Null
        }
    }

    $DefaultProvider = Resolve-PDAProviderId -Value ([string]$Policy.local_first_default_provider) -AliasLookup $AliasLookup
    if ([string]::IsNullOrWhiteSpace($DefaultProvider)) {
        $DefaultProvider = "local-llama"
    }

    if ($ResolvedRestrictedLocalOnly) {
        # Restricted-local routes are forced to the default local provider.
    }

    $RequestedProviderId = Resolve-PDAProviderId -Value $RequestedProvider -AliasLookup $AliasLookup
    $RequestedProviderAllowed = $false
    if (-not [string]::IsNullOrWhiteSpace($RequestedProviderId)) {
        if ($ResolvedRestrictedLocalOnly) {
            $RequestedProviderAllowed = $RequestedProviderId -eq $DefaultProvider
        }
        elseif ($ApprovedProviderIds.Count -gt 0) {
            $RequestedProviderAllowed = $ApprovedProviderIds.Contains($RequestedProviderId)
        }
        else {
            $RequestedProviderAllowed = $true
        }
    }

    $SelectedProvider = ""
    $SelectionSource = ""
    $OverrideAccepted = $false
    $OverrideBlocked = $false

    if ($ResolvedRestrictedLocalOnly) {
        $SelectedProvider = $DefaultProvider
        $SelectionSource = "restricted_local"
        if (-not [string]::IsNullOrWhiteSpace($RequestedProviderId) -and $RequestedProviderId -ne $DefaultProvider) {
            $OverrideBlocked = $true
        }
    }
    elseif ($RequestedProviderAllowed) {
        $SelectedProvider = $RequestedProviderId
        $SelectionSource = "user_override"
        $OverrideAccepted = $true
    }
    else {
        $PreferredAllowed = @($PreferredProviderIds | Where-Object {
            if ($_ -eq $DefaultProvider) {
                return $true
            }
            if ($ApprovedProviderIds.Count -gt 0) {
                return $ApprovedProviderIds.Contains($_)
            }
            return $true
        })

        $PreferredNonLocal = @($PreferredAllowed | Where-Object { $_ -ne $DefaultProvider })

        if ($PreferredNonLocal.Count -gt 0) {
            $SelectedProvider = [string]$PreferredNonLocal[0]
            $SelectionSource = "capability_or_agent_preference"
        }
        elseif ($null -ne $LocalConfidenceValue -and -not [double]::IsNaN($LocalConfidenceValue) -and $LocalConfidenceValue -lt $ConfidenceThreshold) {
            $FallbackAllowed = @($FallbackProviderIds | Where-Object {
                if ($_ -eq $DefaultProvider) {
                    return $false
                }
                if ($ApprovedProviderIds.Count -gt 0) {
                    return $ApprovedProviderIds.Contains($_)
                }
                return $true
            })
            if ($FallbackAllowed.Count -gt 0) {
                $SelectedProvider = [string]$FallbackAllowed[0]
                $SelectionSource = "confidence_escalation"
            }
        }

        if ([string]::IsNullOrWhiteSpace($SelectedProvider)) {
            $SelectedProvider = $DefaultProvider
            $SelectionSource = "local_default"
        }
    }

    if ([string]::IsNullOrWhiteSpace($SelectedProvider)) {
        $SelectedProvider = $DefaultProvider
        $SelectionSource = "local_default"
    }

    $CandidateProviders = New-Object System.Collections.Generic.List[string]
    $CandidateDetails = New-Object System.Collections.Generic.List[object]

    Add-PDAProviderCandidate -ProviderId $SelectedProvider -Source $SelectionSource -Details $CandidateDetails -OrderedProviders $CandidateProviders -CatalogLookup $CatalogLookup
    if ($SelectedProvider -ne $DefaultProvider) {
        Add-PDAProviderCandidate -ProviderId $DefaultProvider -Source "local_default" -Details $CandidateDetails -OrderedProviders $CandidateProviders -CatalogLookup $CatalogLookup
    }
    foreach ($ProviderId in @($PreferredProviderIds)) {
        Add-PDAProviderCandidate -ProviderId $ProviderId -Source "preferred" -Details $CandidateDetails -OrderedProviders $CandidateProviders -CatalogLookup $CatalogLookup
    }
    foreach ($ProviderId in @($FallbackProviderIds)) {
        Add-PDAProviderCandidate -ProviderId $ProviderId -Source "fallback" -Details $CandidateDetails -OrderedProviders $CandidateProviders -CatalogLookup $CatalogLookup
    }

    if ($ResolvedRestrictedLocalOnly) {
        $CandidateProviders = New-Object System.Collections.Generic.List[string]
        $CandidateDetails = New-Object System.Collections.Generic.List[object]
        Add-PDAProviderCandidate -ProviderId $DefaultProvider -Source "restricted_local" -Details $CandidateDetails -OrderedProviders $CandidateProviders -CatalogLookup $CatalogLookup
    }

    $EscalationRequired = $SelectedProvider -ne $DefaultProvider
    $DefaultedToLocal = -not $EscalationRequired -and -not $OverrideAccepted
    $EscalationReason = ""
    $LocalConfidenceValue = $null
    if ($null -ne $LocalConfidence) {
        try {
            $LocalConfidenceValue = [double]$LocalConfidence
        }
        catch {
            $LocalConfidenceValue = $null
        }
    }
    if ($ResolvedRestrictedLocalOnly) {
        $EscalationReason = "Cloud escalation is blocked by category 2 or restricted-local policy."
    }
    elseif ($OverrideAccepted) {
        $EscalationReason = "User requested '$([string](Get-PDAProviderDisplayName -ProviderId $SelectedProvider -CatalogLookup $CatalogLookup))' and the route allows cloud escalation."
    }
    elseif ($SelectionSource -eq "confidence_escalation" -and $null -ne $LocalConfidenceValue) {
        $EscalationReason = "Local confidence $($LocalConfidenceValue) is below the threshold $ConfidenceThreshold."
    }
    elseif ($EscalationRequired) {
        $EscalationReason = [string]$Policy.escalation_reasons.$CapabilityId
        if ([string]::IsNullOrWhiteSpace($EscalationReason)) {
            $EscalationReason = "Capability or agent preference selected '$([string](Get-PDAProviderDisplayName -ProviderId $SelectedProvider -CatalogLookup $CatalogLookup))'."
        }
    }
    elseif ($null -ne $LocalConfidenceValue -and -not [double]::IsNaN($LocalConfidenceValue) -and $LocalConfidenceValue -lt $ConfidenceThreshold) {
        $EscalationReason = "Local confidence $($LocalConfidenceValue) is below the threshold $ConfidenceThreshold."
    }
    else {
        $EscalationReason = "No escalation required; local-llama remains the default provider."
    }

    $RoutingReason = ""
    if ($ResolvedRestrictedLocalOnly) {
        $RoutingReason = "Restricted-local policy forced local-llama."
    }
    elseif ($OverrideAccepted) {
        $RoutingReason = "User override selected '$([string](Get-PDAProviderDisplayName -ProviderId $SelectedProvider -CatalogLookup $CatalogLookup))'."
    }
    elseif ($SelectionSource -eq "confidence_escalation" -and $null -ne $LocalConfidenceValue) {
        $RoutingReason = "Local confidence $($LocalConfidenceValue) is below the threshold $ConfidenceThreshold; escalating to '$([string](Get-PDAProviderDisplayName -ProviderId $SelectedProvider -CatalogLookup $CatalogLookup))'."
    }
    elseif ($EscalationRequired) {
        $RoutingReason = "Capability or agent preference escalated from local-llama to '$([string](Get-PDAProviderDisplayName -ProviderId $SelectedProvider -CatalogLookup $CatalogLookup))'."
    }
    else {
        $RoutingReason = "Local-first default resolved to local-llama."
    }

    if ($OverrideBlocked) {
        $RoutingReason = "Cloud override '$RequestedProvider' was blocked by restricted-local policy."
    }

    $SelectedProviderCatalogEntry = $null
    $SelectedProviderToken = Normalize-PDAProviderToken -Value $SelectedProvider
    if ($CatalogLookup.ContainsKey($SelectedProviderToken)) {
        $SelectedProviderCatalogEntry = $CatalogLookup[$SelectedProviderToken]
    }

    return [pscustomobject]@{
        status = "pass"
        provider_policy_path = $ResolvedPolicyPath
        capability_registry_path = $ResolvedCapabilityRegistryPath
        agent_registry_path = $ResolvedAgentRegistryPath
        capability = [string]$CapabilityId
        selected_agent = [string]$SelectedAgent
        category = $ResolvedCategory
        requested_provider = [string]$RequestedProvider
        override_accepted = [bool]$OverrideAccepted
        override_blocked = [bool]$OverrideBlocked
        selected_provider = [string]$SelectedProvider
        selected_provider_display_name = [string](Get-PDAProviderDisplayName -ProviderId $SelectedProvider -CatalogLookup $CatalogLookup)
        selected_provider_family = if ($SelectedProviderCatalogEntry) { [string]$SelectedProviderCatalogEntry.provider_family } else { "" }
        candidate_providers = @($CandidateProviders)
        candidate_provider_details = @($CandidateDetails)
        routing_reason = $RoutingReason
        defaulted_to_local = [bool]$DefaultedToLocal
        escalation_required = [bool]$EscalationRequired
        escalation_reason = [string]$EscalationReason
        cloud_allowed = [bool]$CloudAllowed
        restricted_local_only = [bool]$ResolvedRestrictedLocalOnly
        approval_required = [bool]$ApprovalRequired
        local_confidence = $LocalConfidence
        confidence_threshold = $ConfidenceThreshold
        source_of_truth = "Scripts/Resolve-PDAProvider.ps1"
    }
}

function Get-PDAProviderSelectionFallback {
    param(
        [Parameter(Mandatory = $true)][hashtable]$SelectionArgs,
        [Parameter(Mandatory = $true)]$Policy,
        [Parameter(Mandatory = $true)][hashtable]$CatalogLookup,
        [Parameter(Mandatory = $true)][hashtable]$AliasLookup
    )

    $Capability = $SelectionArgs.Capability
    $AgentProfile = $SelectionArgs.AgentProfile
    $CapabilityId = [string]$SelectionArgs.CapabilityId
    $SelectedAgent = [string]$SelectionArgs.SelectedAgent
    $Category = [string]$SelectionArgs.Category
    $RequestedProvider = [string]$SelectionArgs.RequestedProvider
    $ConfidenceThreshold = if ($SelectionArgs.ContainsKey("ConfidenceThreshold")) { [double]$SelectionArgs.ConfidenceThreshold } else { 0.65 }

    $CapabilityPreferred = @(Get-PDARecordValueList -Record $Capability -PropertyName "preferred_providers")
    $CapabilityFallback = @(Get-PDARecordValueList -Record $Capability -PropertyName "fallback_providers")
    $AgentPreferred = @(Get-PDARecordValueList -Record $AgentProfile -PropertyName "preferred_providers")
    $AgentFallback = @(Get-PDARecordValueList -Record $AgentProfile -PropertyName "fallback_providers")

    $CapabilityApprovalRequired = if ($Capability) { [bool]$Capability.approval_required } else { $false }
    $AgentApprovalRequired = if ($AgentProfile -and $AgentProfile.PSObject.Properties.Name -contains "approval_required_default") { [bool]$AgentProfile.approval_required_default } else { $false }
    $CapabilityRestricted = if ($Capability) { [bool]$Capability.restricted_local_only } else { $false }
    $AgentRestricted = if ($AgentProfile) { [bool]$AgentProfile.restricted_local_only } else { $false }

    $ResolvedCategory = ([string]$Category).Trim().ToLowerInvariant()
    if ($ResolvedCategory -eq "category_2") {
        $ResolvedCategory = "category_2"
    }
    elseif ($ResolvedCategory -in @("restricted_local", "local", "local_only", "local-only", "sensitive")) {
        $ResolvedCategory = "restricted_local"
    }
    else {
        $ResolvedCategory = "category_1"
    }

    $ResolvedRestrictedLocalOnly = [bool]$SelectionArgs.RestrictedLocalOnly
    if ($ResolvedCategory -in @("category_2", "restricted_local")) {
        $ResolvedRestrictedLocalOnly = $true
    }
    if ($CapabilityRestricted -or $AgentRestricted) {
        $ResolvedRestrictedLocalOnly = $true
    }

    $CloudAllowed = -not $ResolvedRestrictedLocalOnly
    $ApprovalRequired = [bool]($CapabilityApprovalRequired -or $AgentApprovalRequired)

    function Add-UniqueValue {
        param(
            [Parameter(Mandatory = $true)][object]$List,
            [Parameter(Mandatory = $false)][object]$Value
        )

        $CurrentList = @($List)
        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
            return @($CurrentList)
        }
        $ValueText = [string]$Value
        if ($CurrentList -contains $ValueText) {
            return @($CurrentList)
        }
        return @($CurrentList + $ValueText)
    }

    $ApprovedProviderIds = @()
    foreach ($Value in @($SelectionArgs.ApprovedProviders)) {
        $ProviderId = Resolve-PDAProviderId -Value $Value -AliasLookup $AliasLookup
        $ApprovedProviderIds = Add-UniqueValue -List $ApprovedProviderIds -Value $ProviderId
    }

    $PreferredProviderIds = @()
    foreach ($Value in @($SelectionArgs.PreferredProviders + $CapabilityPreferred + $AgentPreferred)) {
        $ProviderId = Resolve-PDAProviderId -Value $Value -AliasLookup $AliasLookup
        $PreferredProviderIds = Add-UniqueValue -List $PreferredProviderIds -Value $ProviderId
    }

    $FallbackProviderIds = @()
    foreach ($Value in @($SelectionArgs.FallbackProviders + $CapabilityFallback + $AgentFallback + @($Policy.cloud_fallback_provider_order))) {
        $ProviderId = Resolve-PDAProviderId -Value $Value -AliasLookup $AliasLookup
        $FallbackProviderIds = Add-UniqueValue -List $FallbackProviderIds -Value $ProviderId
    }

    $DefaultProvider = Resolve-PDAProviderId -Value ([string]$Policy.local_first_default_provider) -AliasLookup $AliasLookup
    if ([string]::IsNullOrWhiteSpace($DefaultProvider)) {
        $DefaultProvider = "local-llama"
    }

    $RequestedProviderId = Resolve-PDAProviderId -Value $RequestedProvider -AliasLookup $AliasLookup
    $RequestedProviderAllowed = $false
    if (-not [string]::IsNullOrWhiteSpace($RequestedProviderId)) {
        if ($ResolvedRestrictedLocalOnly) {
            $RequestedProviderAllowed = $RequestedProviderId -eq $DefaultProvider
        }
        elseif ($ApprovedProviderIds.Count -gt 0) {
            $RequestedProviderAllowed = $ApprovedProviderIds -contains $RequestedProviderId
        }
        else {
            $RequestedProviderAllowed = $true
        }
    }

    $SelectedProvider = $DefaultProvider
    $SelectionSource = "local_default"
    $OverrideAccepted = $false
    $OverrideBlocked = $false

    $LocalConfidenceValue = $null
    if ($SelectionArgs.ContainsKey("LocalConfidence") -and $null -ne $SelectionArgs.LocalConfidence) {
        try {
            $LocalConfidenceValue = [double]$SelectionArgs.LocalConfidence
        }
        catch {
            $LocalConfidenceValue = $null
        }
    }

    if ($ResolvedRestrictedLocalOnly) {
        $SelectionSource = "restricted_local"
        if (-not [string]::IsNullOrWhiteSpace($RequestedProviderId) -and $RequestedProviderId -ne $DefaultProvider) {
            $OverrideBlocked = $true
        }
    }
    elseif ($RequestedProviderAllowed) {
        $SelectedProvider = $RequestedProviderId
        $SelectionSource = "user_override"
        $OverrideAccepted = $true
    }
    else {
        $PreferredAllowed = @($PreferredProviderIds | Where-Object {
            if ($_ -eq $DefaultProvider) {
                return $true
            }
            if ($ApprovedProviderIds.Count -gt 0) {
                return $ApprovedProviderIds -contains $_
            }
            return $true
        })
        $PreferredNonLocal = @($PreferredAllowed | Where-Object { $_ -ne $DefaultProvider })
        if ($PreferredNonLocal.Count -gt 0) {
            $SelectedProvider = [string]$PreferredNonLocal[0]
            $SelectionSource = "capability_or_agent_preference"
        }
        elseif ($null -ne $LocalConfidenceValue -and -not [double]::IsNaN($LocalConfidenceValue) -and $LocalConfidenceValue -lt $ConfidenceThreshold) {
            $FallbackAllowed = @($FallbackProviderIds | Where-Object {
                if ($_ -eq $DefaultProvider) {
                    return $false
                }
                if ($ApprovedProviderIds.Count -gt 0) {
                    return $ApprovedProviderIds -contains $_
                }
                return $true
            })
            if ($FallbackAllowed.Count -gt 0) {
                $SelectedProvider = [string]$FallbackAllowed[0]
                $SelectionSource = "confidence_escalation"
            }
        }
    }

    if (-not $ResolvedRestrictedLocalOnly -and -not $OverrideAccepted -and $SelectedProvider -ne $DefaultProvider -and $null -ne $LocalConfidenceValue -and -not [double]::IsNaN($LocalConfidenceValue) -and $LocalConfidenceValue -lt $ConfidenceThreshold) {
        $SelectionSource = "confidence_escalation"
    }

    $CandidateProviders = @()
    foreach ($ProviderId in @($SelectedProvider, $(if ($SelectedProvider -ne $DefaultProvider) { $DefaultProvider } else { $null }), $PreferredProviderIds, $FallbackProviderIds)) {
        foreach ($Entry in @($ProviderId)) {
            if ([string]::IsNullOrWhiteSpace([string]$Entry)) {
                continue
            }
            $EntryText = [string]$Entry
            if (-not ($CandidateProviders -contains $EntryText)) {
                $CandidateProviders += $EntryText
            }
        }
    }

    if ($ResolvedRestrictedLocalOnly) {
        $CandidateProviders = @($DefaultProvider)
    }

    $CandidateDetails = @()
    foreach ($ProviderId in $CandidateProviders) {
        $CatalogEntry = $null
        $ProviderToken = Normalize-PDAProviderToken -Value $ProviderId
        if ($CatalogLookup.ContainsKey($ProviderToken)) {
            $CatalogEntry = $CatalogLookup[$ProviderToken]
        }
        $CandidateDetails += [pscustomobject]@{
            provider_id = $ProviderId
            display_name = if ($CatalogEntry) { [string]$CatalogEntry.display_name } else { $ProviderId }
            provider_family = if ($CatalogEntry) { [string]$CatalogEntry.provider_family } else { "" }
            cloud_allowed = if ($CatalogEntry) { [bool]$CatalogEntry.cloud_allowed } else { $true }
            local_only = if ($CatalogEntry) { [bool]$CatalogEntry.local_only } else { $false }
            source = if ($ProviderId -eq $SelectedProvider) { $SelectionSource } elseif ($ProviderId -eq $DefaultProvider) { "local_default" } elseif ($PreferredProviderIds -contains $ProviderId) { "preferred" } else { "fallback" }
        }
    }

    $EscalationRequired = $SelectedProvider -ne $DefaultProvider
    $DefaultedToLocal = -not $EscalationRequired -and -not $OverrideAccepted
    if ($ResolvedRestrictedLocalOnly) {
        $EscalationReason = "Cloud escalation is blocked by category 2 or restricted-local policy."
    }
    elseif ($OverrideAccepted) {
        $EscalationReason = "User requested '$([string](Get-PDAProviderDisplayName -ProviderId $SelectedProvider -CatalogLookup $CatalogLookup))' and the route allows cloud escalation."
    }
    elseif ($SelectionSource -eq "confidence_escalation" -and $null -ne $LocalConfidenceValue) {
        $EscalationReason = "Local confidence $($LocalConfidenceValue) is below the threshold $ConfidenceThreshold."
    }
    elseif ($EscalationRequired) {
        $EscalationReason = [string]$Policy.escalation_reasons.$CapabilityId
        if ([string]::IsNullOrWhiteSpace($EscalationReason)) {
            $EscalationReason = "Capability or agent preference selected '$([string](Get-PDAProviderDisplayName -ProviderId $SelectedProvider -CatalogLookup $CatalogLookup))'."
        }
    }
    elseif ($null -ne $LocalConfidenceValue -and -not [double]::IsNaN($LocalConfidenceValue) -and $LocalConfidenceValue -lt $ConfidenceThreshold) {
        $EscalationReason = "Local confidence $($LocalConfidenceValue) is below the threshold $ConfidenceThreshold."
    }
    else {
        $EscalationReason = "No escalation required; local-llama remains the default provider."
    }

    $RoutingReason = ""
    if ($ResolvedRestrictedLocalOnly) {
        $RoutingReason = "Restricted-local policy forced local-llama."
    }
    elseif ($OverrideAccepted) {
        $RoutingReason = "User override selected '$([string](Get-PDAProviderDisplayName -ProviderId $SelectedProvider -CatalogLookup $CatalogLookup))'."
    }
    elseif ($SelectionSource -eq "confidence_escalation" -and $null -ne $LocalConfidenceValue) {
        $RoutingReason = "Local confidence $($LocalConfidenceValue) is below the threshold $ConfidenceThreshold; escalating to '$([string](Get-PDAProviderDisplayName -ProviderId $SelectedProvider -CatalogLookup $CatalogLookup))'."
    }
    elseif ($EscalationRequired) {
        $RoutingReason = "Capability or agent preference escalated from local-llama to '$([string](Get-PDAProviderDisplayName -ProviderId $SelectedProvider -CatalogLookup $CatalogLookup))'."
    }
    else {
        $RoutingReason = "Local-first default resolved to local-llama."
    }

    if ($OverrideBlocked) {
        $RoutingReason = "Cloud override '$RequestedProvider' was blocked by restricted-local policy."
    }

    $SelectedProviderCatalogEntry = $null
    $SelectedProviderToken = Normalize-PDAProviderToken -Value $SelectedProvider
    if ($CatalogLookup.ContainsKey($SelectedProviderToken)) {
        $SelectedProviderCatalogEntry = $CatalogLookup[$SelectedProviderToken]
    }

    return [pscustomobject]@{
        status = "pass"
        provider_policy_path = [string]$SelectionArgs.PolicyPath
        capability_registry_path = [string]$SelectionArgs.CapabilityRegistryPath
        agent_registry_path = [string]$SelectionArgs.AgentRegistryPath
        capability = [string]$CapabilityId
        selected_agent = [string]$SelectedAgent
        category = $ResolvedCategory
        requested_provider = [string]$RequestedProvider
        override_accepted = [bool]$OverrideAccepted
        override_blocked = [bool]$OverrideBlocked
        selected_provider = [string]$SelectedProvider
        selected_provider_display_name = [string](Get-PDAProviderDisplayName -ProviderId $SelectedProvider -CatalogLookup $CatalogLookup)
        selected_provider_family = if ($SelectedProviderCatalogEntry) { [string]$SelectedProviderCatalogEntry.provider_family } else { "" }
        candidate_providers = @($CandidateProviders)
        candidate_provider_details = @($CandidateDetails)
        routing_reason = $RoutingReason
        defaulted_to_local = [bool]$DefaultedToLocal
        escalation_required = [bool]$EscalationRequired
        escalation_reason = [string]$EscalationReason
        cloud_allowed = [bool]$CloudAllowed
        restricted_local_only = [bool]$ResolvedRestrictedLocalOnly
        approval_required = [bool]$ApprovalRequired
        local_confidence = $LocalConfidenceValue
        confidence_threshold = $ConfidenceThreshold
        source_of_truth = "Scripts/Resolve-PDAProvider.ps1"
    }
}

$PolicyLoad = Get-PDARegistryLoadResult -Path $ResolvedPolicyPath -RegistryName "Provider routing policy"
$CapabilityLoad = Get-PDARegistryLoadResult -Path $ResolvedCapabilityRegistryPath -RegistryName "Capability registry"
$AgentLoad = Get-PDARegistryLoadResult -Path $ResolvedAgentRegistryPath -RegistryName "Agent profile registry"

if ($PolicyLoad.status -ne "pass") {
    $Result = [pscustomobject]@{
        status = "fail"
        blocked_reason = $PolicyLoad.error
        provider_policy_path = $ResolvedPolicyPath
        capability_registry_path = $ResolvedCapabilityRegistryPath
        agent_registry_path = $ResolvedAgentRegistryPath
        selected_provider = ""
        candidate_providers = @()
        candidate_provider_details = @()
        routing_reason = $PolicyLoad.error
        defaulted_to_local = $false
        escalation_required = $false
        escalation_reason = $PolicyLoad.error
        cloud_allowed = $false
        restricted_local_only = $false
        approval_required = $false
        source_of_truth = "Scripts/Resolve-PDAProvider.ps1"
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

if ($CapabilityLoad.status -ne "pass") {
    $Result = [pscustomobject]@{
        status = "fail"
        blocked_reason = $CapabilityLoad.error
        provider_policy_path = $ResolvedPolicyPath
        capability_registry_path = $ResolvedCapabilityRegistryPath
        agent_registry_path = $ResolvedAgentRegistryPath
        selected_provider = ""
        candidate_providers = @()
        candidate_provider_details = @()
        routing_reason = $CapabilityLoad.error
        defaulted_to_local = $false
        escalation_required = $false
        escalation_reason = $CapabilityLoad.error
        cloud_allowed = $false
        restricted_local_only = $false
        approval_required = $false
        source_of_truth = "Scripts/Resolve-PDAProvider.ps1"
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
        blocked_reason = $AgentLoad.error
        provider_policy_path = $ResolvedPolicyPath
        capability_registry_path = $ResolvedCapabilityRegistryPath
        agent_registry_path = $ResolvedAgentRegistryPath
        selected_provider = ""
        candidate_providers = @()
        candidate_provider_details = @()
        routing_reason = $AgentLoad.error
        defaulted_to_local = $false
        escalation_required = $false
        escalation_reason = $AgentLoad.error
        cloud_allowed = $false
        restricted_local_only = $false
        approval_required = $false
        source_of_truth = "Scripts/Resolve-PDAProvider.ps1"
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

$Policy = $PolicyLoad.registry
$CapabilityRegistry = $CapabilityLoad.registry
$AgentRegistry = $AgentLoad.registry
$Capabilities = @($CapabilityRegistry.capabilities)
$AgentProfiles = @($AgentRegistry.agent_profiles)
$Capability = $null
if (-not [string]::IsNullOrWhiteSpace($CapabilityId)) {
    $Capability = $Capabilities | Where-Object { [string]$_.capability_id -ieq $CapabilityId } | Select-Object -First 1
}
$AgentProfile = $null
if (-not [string]::IsNullOrWhiteSpace($SelectedAgent)) {
    $AgentProfile = $AgentProfiles | Where-Object {
        [string]$_.agent_id -ieq $SelectedAgent -or [string]$_.display_name -ieq $SelectedAgent
    } | Select-Object -First 1
}

$Catalog = Get-PDAProviderCatalog -Policy $Policy
$SelectionArgs = @{
    Capability = $Capability
    AgentProfile = $AgentProfile
    Policy = $Policy
    CatalogLookup = $Catalog.catalog_lookup
    AliasLookup = $Catalog.alias_lookup
    PolicyPath = $ResolvedPolicyPath
    CapabilityRegistryPath = $ResolvedCapabilityRegistryPath
    AgentRegistryPath = $ResolvedAgentRegistryPath
    CapabilityId = $CapabilityId
    SelectedAgent = $SelectedAgent
    Category = $Category
    RequestedProvider = $RequestedProvider
    ConfidenceThreshold = $ConfidenceThreshold
}
if ($ApprovedProviders.Count -gt 0) {
    $SelectionArgs.ApprovedProviders = $ApprovedProviders
}
if ($PreferredProviders.Count -gt 0) {
    $SelectionArgs.PreferredProviders = $PreferredProviders
}
if ($FallbackProviders.Count -gt 0) {
    $SelectionArgs.FallbackProviders = $FallbackProviders
}
$RestrictedLocalOnlyValue = ConvertTo-PDAProviderBoolean -Value $RestrictedLocalOnly
if ($null -ne $RestrictedLocalOnlyValue) {
    $SelectionArgs.RestrictedLocalOnly = $RestrictedLocalOnlyValue
}
if ($null -ne $LocalConfidence) {
    $SelectionArgs.LocalConfidence = $LocalConfidence
}
$Selection = Get-PDAProviderSelectionFallback -SelectionArgs $SelectionArgs -Policy $Policy -CatalogLookup $Catalog.catalog_lookup -AliasLookup $Catalog.alias_lookup

if ([string]::IsNullOrWhiteSpace([string]$Selection.capability) -and -not [string]::IsNullOrWhiteSpace($CapabilityId)) {
    $Selection | Add-Member -NotePropertyName capability -NotePropertyValue $CapabilityId -Force
}

if ($AsJson) {
    $Selection | ConvertTo-Json -Depth 20
    return
}

if ($Selection.status -eq "pass") {
    Write-Host "[OK] PDA provider resolution"
    Write-Host ("Capability      : {0}" -f $(if ($Selection.capability) { $Selection.capability } else { "(none)" }))
    Write-Host ("Agent           : {0}" -f $(if ($Selection.selected_agent) { $Selection.selected_agent } else { "(none)" }))
    Write-Host ("Selected prov.  : {0}" -f $Selection.selected_provider)
    Write-Host ("Candidates      : {0}" -f $(if ($Selection.candidate_providers.Count -gt 0) { $Selection.candidate_providers -join ", " } else { "(none)" }))
    Write-Host ("Defaulted local : {0}" -f $Selection.defaulted_to_local)
    Write-Host ("Escalation req. : {0}" -f $Selection.escalation_required)
    Write-Host ("Cloud allowed   : {0}" -f $Selection.cloud_allowed)
    Write-Host ("Approval req'd  : {0}" -f $Selection.approval_required)
    Write-Host ("Reason          : {0}" -f $Selection.routing_reason)
    return
}

Write-Host "[ERROR] $($Selection.blocked_reason)"
if (-not $NoThrow) {
    throw $Selection.blocked_reason
}
