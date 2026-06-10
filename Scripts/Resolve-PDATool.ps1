[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Capability = "",

    [Parameter(Mandatory = $false)]
    [string]$Agent = "",

    [Parameter(Mandatory = $false)]
    [string]$Provider = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("category_1", "category_2")]
    [string]$Category = "",

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
}
else {
    Join-Path $PSScriptRoot "PDA_ToolRegistry.json"
}

function Normalize-PDAToolToken {
    param([Parameter(Mandatory = $false)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return (([string]$Value).Trim().ToLowerInvariant()) -replace "[^a-z0-9]+", ""
}

function Get-PDAToolRegistryLoadResult {
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

function Get-PDAToolPriorityMap {
    return [ordered]@{
        research = @("browser", "lite_llm", "gemini_cli", "powershell", "python")
        sourcediscovery = @("browser", "lite_llm", "gemini_cli", "powershell", "python")
        largecontextanalysis = @("browser", "lite_llm", "gemini_cli", "powershell", "python")
        reportwriting = @("open_webui", "fabric", "browser", "powershell", "python")
        reportreview = @("codex", "browser", "lite_llm", "powershell", "python")
        codeimplementation = @("claude_code", "codex", "file_system", "powershell", "python")
        codereview = @("codex", "claude_code", "browser", "powershell", "python")
        repomodification = @("file_system", "claude_code", "codex", "powershell", "python")
        automationdesign = @("n8n", "claude_code", "powershell", "python", "file_system")
        n8nworkflowdesign = @("n8n", "claude_code", "powershell", "python", "file_system")
        localrestrictedanalysis = @("local_llm", "file_system", "powershell", "python", "obsidian")
        fileprocessing = @("file_system", "powershell", "python", "obsidian")
        dashboardstatusgeneration = @("powershell", "file_system", "obsidian", "python")
        memorysummarization = @("obsidian", "local_llm", "powershell", "python")
        skillpromotionreview = @("fabric", "browser", "codex", "powershell", "python")
    }
}

function Get-PDAToolDisplayName {
    param(
        [Parameter(Mandatory = $true)]$Tool
    )

    if ($Tool.PSObject.Properties.Name -contains "display_name" -and -not [string]::IsNullOrWhiteSpace([string]$Tool.display_name)) {
        return [string]$Tool.display_name
    }

    return [string]$Tool.tool_id
}

function Resolve-PDAToolSelection {
    param(
        [Parameter(Mandatory = $true)]$Registry,
        [Parameter(Mandatory = $true)][string]$Capability,
        [Parameter(Mandatory = $false)][string]$Agent = "",
        [Parameter(Mandatory = $false)][string]$Provider = "",
        [Parameter(Mandatory = $false)][string]$Category = ""
    )

    if ([string]::IsNullOrWhiteSpace($Capability)) {
        return [pscustomobject]@{
            status = "fail"
            blocked_reason = "Capability is required."
            selected_tool = ""
            selected_tool_display_name = ""
            candidate_tools = @()
            candidate_tool_details = @()
            routing_reason = "Capability is required."
            approval_required = $false
            restricted_local_only = $false
        }
    }

    $NormalizedCapability = Normalize-PDAToolToken -Value $Capability
    $NormalizedAgent = Normalize-PDAToolToken -Value $Agent
    $NormalizedProvider = Normalize-PDAToolToken -Value $Provider
    $ResolvedCategory = if ([string]::IsNullOrWhiteSpace($Category)) { "category_1" } else { [string]$Category.Trim().ToLowerInvariant() }
    $RestrictedLocalOnly = $ResolvedCategory -eq "category_2"

    $PriorityMap = Get-PDAToolPriorityMap
    $CapabilityTools = @($Registry.tools | Where-Object {
        $SupportedCapabilities = @($_.supported_capabilities | ForEach-Object { Normalize-PDAToolToken -Value ([string]$_) })
        $SupportedAgents = @($_.supported_agents | ForEach-Object { Normalize-PDAToolToken -Value ([string]$_) })
        $CapabilityMatch = $SupportedCapabilities -contains $NormalizedCapability
        if (-not $CapabilityMatch) {
            return $false
        }

        if ($RestrictedLocalOnly -and -not [bool]$_.local_only) {
            return $false
        }

        if ($ResolvedCategory -and @($_.category_allowed) -notcontains $ResolvedCategory) {
            return $false
        }

        if (-not [string]::IsNullOrWhiteSpace($NormalizedAgent) -and $SupportedAgents.Count -gt 0) {
            return ($SupportedAgents -contains $NormalizedAgent)
        }

        return $true
    })

    if ($CapabilityTools.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($NormalizedAgent)) {
        $CapabilityTools = @($Registry.tools | Where-Object {
            $SupportedCapabilities = @($_.supported_capabilities | ForEach-Object { Normalize-PDAToolToken -Value ([string]$_) })
            if (-not ($SupportedCapabilities -contains $NormalizedCapability)) {
                return $false
            }
            if ($RestrictedLocalOnly -and -not [bool]$_.local_only) {
                return $false
            }
            if ($ResolvedCategory -and @($_.category_allowed) -notcontains $ResolvedCategory) {
                return $false
            }
            return $true
        })
    }

    if ($CapabilityTools.Count -eq 0) {
        return [pscustomobject]@{
            status = "fail"
            blocked_reason = "No registered tool matched capability '$Capability'."
            selected_tool = ""
            selected_tool_display_name = ""
            candidate_tools = @()
            candidate_tool_details = @()
            routing_reason = "No registered tool matched capability '$Capability'."
            approval_required = $false
            restricted_local_only = $RestrictedLocalOnly
            source_of_truth = "Scripts/Resolve-PDATool.ps1"
        }
    }

    $OrderedCandidates = @()
    $AddedToolIds = @()
    $Priorities = @()
    if ($PriorityMap.Contains($NormalizedCapability)) {
        $Priorities = @($PriorityMap[$NormalizedCapability])
    }

    foreach ($ToolId in @($Priorities)) {
        $NormalizedToolId = Normalize-PDAToolToken -Value $ToolId
        $Match = @($CapabilityTools | Where-Object { (Normalize-PDAToolToken -Value ([string]$_.tool_id)) -eq $NormalizedToolId } | Select-Object -First 1)[0]
        if ($Match -and -not ($AddedToolIds -contains [string]$Match.tool_id)) {
            $OrderedCandidates += $Match
            $AddedToolIds += [string]$Match.tool_id
        }
    }

    foreach ($Tool in @($CapabilityTools)) {
        if (-not ($AddedToolIds -contains [string]$Tool.tool_id)) {
            $OrderedCandidates += $Tool
            $AddedToolIds += [string]$Tool.tool_id
        }
    }

    $SelectedTool = @($OrderedCandidates)[0]
    $SelectedDisplayName = Get-PDAToolDisplayName -Tool $SelectedTool
    $CandidateDetails = @(
        $OrderedCandidates | ForEach-Object {
            [pscustomobject]@{
                tool_id = [string]$_.tool_id
                display_name = Get-PDAToolDisplayName -Tool $_
                local_only = [bool]$_.local_only
                approval_required = [bool]$_.approval_required
                risk_level = [string]$_.risk_level
            }
        }
    )

    $RoutingParts = New-Object System.Collections.Generic.List[string]
    $RoutingParts.Add(("Capability '{0}'" -f $Capability)) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($Agent)) {
        $RoutingParts.Add(("agent '{0}'" -f $Agent)) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($Provider)) {
        $RoutingParts.Add(("provider '{0}'" -f $Provider)) | Out-Null
    }
    $RoutingParts.Add(("selected '{0}'" -f $SelectedDisplayName)) | Out-Null

    if ($RestrictedLocalOnly) {
        $RoutingReason = "Category 2 requires local-only tools; selected '$SelectedDisplayName'. Context: " + ($RoutingParts -join ", ") + "."
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Agent)) {
        $RoutingReason = "Capability-first selection matched agent-compatible tool '$SelectedDisplayName'. Context: " + ($RoutingParts -join ", ") + "."
    }
    else {
        $RoutingReason = "Capability-first selection chose '$SelectedDisplayName'. Context: " + ($RoutingParts -join ", ") + "."
    }

    return [pscustomobject]@{
        status = "pass"
        selected_tool = [string]$SelectedTool.tool_id
        selected_tool_display_name = $SelectedDisplayName
        candidate_tools = @($OrderedCandidates | ForEach-Object { [string]$_.tool_id })
        candidate_tool_details = @($CandidateDetails)
        routing_reason = [string]$RoutingReason
        approval_required = [bool]$SelectedTool.approval_required
        restricted_local_only = [bool]$RestrictedLocalOnly
        selected_tool_record = $SelectedTool
        source_of_truth = "Scripts/Resolve-PDATool.ps1"
    }
}

$RegistryLoad = Get-PDAToolRegistryLoadResult -Path $ResolvedRegistryPath -RegistryName "PDA tool registry"
if ($RegistryLoad.status -ne "pass") {
    $Result = [pscustomobject]@{
        status = "fail"
        blocked_reason = $RegistryLoad.error
        selected_tool = ""
        selected_tool_display_name = ""
        candidate_tools = @()
        candidate_tool_details = @()
        routing_reason = $RegistryLoad.error
        approval_required = $false
        restricted_local_only = $false
        tool_registry_path = $ResolvedRegistryPath
        source_of_truth = "Scripts/Resolve-PDATool.ps1"
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

$Selection = Resolve-PDAToolSelection -Registry $RegistryLoad.registry -Capability $Capability -Agent $Agent -Provider $Provider -Category $Category

$Result = [pscustomobject]@{
    status = $Selection.status
    blocked_reason = if ($Selection.PSObject.Properties.Name -contains "blocked_reason") { [string]$Selection.blocked_reason } else { "" }
    tool_registry_path = $ResolvedRegistryPath
    selected_tool = [string]$Selection.selected_tool
    selected_tool_display_name = [string]$Selection.selected_tool_display_name
    candidate_tools = @($Selection.candidate_tools)
    candidate_tool_details = @($Selection.candidate_tool_details)
    routing_reason = [string]$Selection.routing_reason
    approval_required = [bool]$Selection.approval_required
    restricted_local_only = [bool]$Selection.restricted_local_only
    source_of_truth = "Scripts/Resolve-PDATool.ps1"
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    if ($Result.status -ne "pass" -and -not $NoThrow) {
        throw $Result.blocked_reason
    }
    return
}

if ($Result.status -eq "pass") {
    Write-Host "[OK] PDA tool resolution"
    Write-Host ("Capability      : {0}" -f $(if ($Capability) { $Capability } else { "(none)" }))
    Write-Host ("Selected tool   : {0}" -f $Result.selected_tool_display_name)
    Write-Host ("Candidates      : {0}" -f $(if ($Result.candidate_tools.Count -gt 0) { $Result.candidate_tools -join ", " } else { "(none)" }))
    Write-Host ("Local-only      : {0}" -f $Result.restricted_local_only)
    Write-Host ("Approval req'd  : {0}" -f $Result.approval_required)
    Write-Host ("Reason          : {0}" -f $Result.routing_reason)
    return
}

Write-Host "[ERROR] $($Result.blocked_reason)"
if (-not $NoThrow) {
    throw $Result.blocked_reason
}
