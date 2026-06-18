[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$WorkerName,

    [Parameter(Mandatory = $false)]
    [string]$TaskType,

    [Parameter(Mandatory = $false)]
    [string]$Command,

    [Parameter(Mandatory = $false)]
    [string]$Category,

    [Parameter(Mandatory = $false)]
    [string]$Sensitivity = "standard",

    [Parameter(Mandatory = $false)]
    [string]$PolicyPath,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$ResolvedPolicyPath = if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    Join-Path $PSScriptRoot "PDA_ModelRouting.json"
}
else {
    $PolicyPath
}

function ConvertTo-PDAHashtable {
    param([Parameter(Mandatory = $true)]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [hashtable] -or $Value -is [System.Collections.IDictionary]) {
        $Copy = @{}
        foreach ($Key in $Value.Keys) {
            $Copy[$Key] = ConvertTo-PDAHashtable -Value $Value[$Key]
        }
        return $Copy
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $List = @()
        foreach ($Item in $Value) {
            $List += ,(ConvertTo-PDAHashtable -Value $Item)
        }
        return $List
    }

    if ($Value -is [psobject] -and $Value.PSObject.Properties.Name.Count -gt 0) {
        $Copy = @{}
        foreach ($Prop in $Value.PSObject.Properties) {
            $Copy[$Prop.Name] = ConvertTo-PDAHashtable -Value $Prop.Value
        }
        return $Copy
    }

    return $Value
}

function Load-PDAModelRoutingPolicy {
    if (-not (Test-Path -LiteralPath $ResolvedPolicyPath -PathType Leaf)) {
        throw "Model routing policy not found: $ResolvedPolicyPath"
    }

    $Raw = Get-Content -LiteralPath $ResolvedPolicyPath -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Raw)) {
        throw "Model routing policy is empty: $ResolvedPolicyPath"
    }

    $Policy = $Raw | ConvertFrom-Json
    $Policy = ConvertTo-PDAHashtable -Value $Policy
    if (-not $Policy.command_routes) {
        throw "Model routing policy is missing command_routes."
    }
    if (-not $Policy.category_routes) {
        throw "Model routing policy is missing category_routes."
    }

    return $Policy
}

function Normalize-PDACategory {
    param(
        [string]$CategoryValue,
        [string]$SensitivityValue
    )

    $CategoryText = ([string]$CategoryValue).Trim().ToLowerInvariant()
    $SensitivityText = ([string]$SensitivityValue).Trim().ToLowerInvariant()

    if ($CategoryText -eq "category_2") {
        return "category_2"
    }
    if ($SensitivityText -in @("restricted_local", "sensitive", "local", "local_only", "category_2")) {
        return "restricted_local"
    }

    return "category_1"
}

function Normalize-PDACommand {
    param(
        [hashtable]$Policy,
        [string]$CommandValue
    )

    $Text = ([string]$CommandValue).Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    if ($Text.StartsWith("/")) {
        $Text = $Text.ToLowerInvariant()
    }
    else {
        $Text = $Text.ToLowerInvariant()
    }

    if ($Policy.command_aliases.ContainsKey($Text)) {
        return [string]$Policy.command_aliases[$Text]
    }

    if (-not $Text.StartsWith("/")) {
        $SlashText = "/$Text"
        if ($Policy.command_aliases.ContainsKey($SlashText)) {
            return [string]$Policy.command_aliases[$SlashText]
        }
    }

    return ""
}

function Resolve-PDACommandFromContext {
    param(
        [hashtable]$Policy,
        [string]$ExplicitCommand,
        [string]$TaskTypeValue,
        [string]$WorkerNameValue
    )

    $Resolved = Normalize-PDACommand -Policy $Policy -CommandValue $ExplicitCommand
    if (-not [string]::IsNullOrWhiteSpace($Resolved)) {
        return [pscustomobject]@{
            command = $Resolved
            source = "explicit_command"
        }
    }

    $Resolved = Normalize-PDACommand -Policy $Policy -CommandValue $TaskTypeValue
    if (-not [string]::IsNullOrWhiteSpace($Resolved)) {
        return [pscustomobject]@{
            command = $Resolved
            source = "task_type"
        }
    }

    $WorkerKey = ([string]$WorkerNameValue).Trim().ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($WorkerKey) -and $Policy.worker_command_map.ContainsKey($WorkerKey)) {
        return [pscustomobject]@{
            command = [string]$Policy.worker_command_map[$WorkerKey]
            source = "worker_map"
        }
    }

    return [pscustomobject]@{
        command = ""
        source = "unresolved"
    }
}

function New-PDARouteResult {
    param(
        [string]$Status,
        [string]$ResolvedCommand,
        [string]$CommandSource,
        [string]$ResolvedCategory,
        [hashtable]$Rule,
        [string]$RouteSource,
        [string]$RoutingReason,
        [string]$Message
    )

    $FallbackChain = @()
    if ($Rule -and $Rule.ContainsKey("fallback_chain") -and $Rule.fallback_chain) {
        $FallbackChain = @($Rule.fallback_chain | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
    }

    $PrimaryModel = if ($Rule -and $Rule.ContainsKey("primary_model")) { [string]$Rule.primary_model } else { "" }
    $CloudAllowed = if ($Rule -and $Rule.ContainsKey("cloud_allowed")) { [bool]$Rule.cloud_allowed } else { $false }

    return [pscustomobject]@{
        status = $Status
        policy_path = $ResolvedPolicyPath
        routing_gateway = "litellm"
        worker_name = $WorkerName
        task_type = $TaskType
        command = $ResolvedCommand
        command_source = $CommandSource
        category = $ResolvedCategory
        sensitivity = if ($ResolvedCategory -in @("category_2", "restricted_local")) { "restricted_local" } else { "standard" }
        route_source = $RouteSource
        primary_model = $PrimaryModel
        selected_model = $PrimaryModel
        fallback_chain = @($FallbackChain)
        model_candidates = @($PrimaryModel) + @($FallbackChain)
        provider_families = if ($Rule -and $Rule.ContainsKey("provider_families")) { @($Rule.provider_families) } else { @() }
        routing_surface = if ($Rule -and $Rule.ContainsKey("routing_surface")) { [string]$Rule.routing_surface } else { "local-only" }
        cloud_allowed = $CloudAllowed
        via_litellm = $true
        routing_reason = $RoutingReason
        reason = $RoutingReason
        message = $Message
    }
}

$Policy = Load-PDAModelRoutingPolicy
$ResolvedCategory = Normalize-PDACategory -CategoryValue $Category -SensitivityValue $Sensitivity
$ResolvedCommandContext = Resolve-PDACommandFromContext -Policy $Policy -ExplicitCommand $Command -TaskTypeValue $TaskType -WorkerNameValue $WorkerName
$ResolvedCommand = [string]$ResolvedCommandContext.command
$CommandSource = [string]$ResolvedCommandContext.source

$RouteResult = $null
if ($ResolvedCategory -in @("category_2", "restricted_local")) {
    $CategoryRuleKey = if ($ResolvedCategory -eq "category_2") { "category_2" } else { "restricted_local" }
    $Rule = $Policy.category_routes[$CategoryRuleKey]
    $RouteResult = New-PDARouteResult `
        -Status "pass" `
        -ResolvedCommand $ResolvedCommand `
        -CommandSource $CommandSource `
        -ResolvedCategory $ResolvedCategory `
        -Rule $Rule `
        -RouteSource "category_override" `
        -RoutingReason ([string]$Rule.reason) `
        -Message "Restricted routing override applied."
}
elseif ([string]::IsNullOrWhiteSpace($ResolvedCommand)) {
    $RouteResult = New-PDARouteResult `
        -Status "fail" `
        -ResolvedCommand "" `
        -CommandSource $CommandSource `
        -ResolvedCategory $ResolvedCategory `
        -Rule $null `
        -RouteSource "unresolved" `
        -RoutingReason "No governed route matched the requested command, task type, or worker." `
        -Message "Missing route."
}
elseif (-not $Policy.command_routes.ContainsKey($ResolvedCommand)) {
    $RouteResult = New-PDARouteResult `
        -Status "fail" `
        -ResolvedCommand $ResolvedCommand `
        -CommandSource $CommandSource `
        -ResolvedCategory $ResolvedCategory `
        -Rule $null `
        -RouteSource "unknown_command" `
        -RoutingReason ("No governed route exists for command '{0}'." -f $ResolvedCommand) `
        -Message "Unknown command."
}
else {
    $Rule = $Policy.command_routes[$ResolvedCommand]
    $RouteResult = New-PDARouteResult `
        -Status "pass" `
        -ResolvedCommand $ResolvedCommand `
        -CommandSource $CommandSource `
        -ResolvedCategory $ResolvedCategory `
        -Rule $Rule `
        -RouteSource "command_route" `
        -RoutingReason ([string]$Rule.reason) `
        -Message "Command route resolved."
}

if ($AsJson) {
    $RouteResult | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $RouteResult.status -ne "pass") {
        throw $RouteResult.routing_reason
    }
    return
}

Write-Host "[PDA MODEL ROUTE]"
Write-Host ("Worker         : {0}" -f $(if ($WorkerName) { $WorkerName } else { "(none)" }))
Write-Host ("Task type      : {0}" -f $(if ($TaskType) { $TaskType } else { "(none)" }))
Write-Host ("Command        : {0}" -f $(if ($RouteResult.command) { $RouteResult.command } else { "(unresolved)" }))
Write-Host ("Category       : {0}" -f $RouteResult.category)
Write-Host ("Selected model : {0}" -f $(if ($RouteResult.selected_model) { $RouteResult.selected_model } else { "(none)" }))
Write-Host ("Fallback chain : {0}" -f $(if ($RouteResult.fallback_chain.Count -gt 0) { $RouteResult.fallback_chain -join ", " } else { "(none)" }))
Write-Host ("Cloud allowed  : {0}" -f $RouteResult.cloud_allowed)
Write-Host ("Reason         : {0}" -f $RouteResult.routing_reason)

if (-not $NoThrow -and $RouteResult.status -ne "pass") {
    throw $RouteResult.routing_reason
}
