[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ToolId = "",

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

function Get-PDAToolRegistryEntry {
    param(
        [Parameter(Mandatory = $true)]$Registry,
        [Parameter(Mandatory = $true)][string]$ToolId
    )

    $NormalizedToolId = Normalize-PDAToolToken -Value $ToolId
    foreach ($Tool in @($Registry.tools)) {
        if (-not $Tool) {
            continue
        }

        if ((Normalize-PDAToolToken -Value ([string]$Tool.tool_id)) -eq $NormalizedToolId) {
            return $Tool
        }
    }

    return $null
}

$RegistryLoad = Get-PDAToolRegistryLoadResult -Path $ResolvedRegistryPath -RegistryName "PDA tool registry"
if ($RegistryLoad.status -ne "pass") {
    $Result = [pscustomobject]@{
        status = "fail"
        blocked_reason = $RegistryLoad.error
        registry_path = $ResolvedRegistryPath
        tool_count = 0
        local_only_count = 0
        cloud_capable_count = 0
        requires_approval_count = 0
        category_1_count = 0
        category_2_count = 0
        tools = @()
        tool = $null
        source_of_truth = "Scripts/Get-PDATool.ps1"
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
$Tools = @($Registry.tools)
$Summary = [pscustomobject]@{
    status = "pass"
    registry_path = $ResolvedRegistryPath
    schema_version = if ($Registry.PSObject.Properties.Name -contains "schema_version") { [string]$Registry.schema_version } else { "1.0" }
    registry_name = if ($Registry.PSObject.Properties.Name -contains "registry_name") { [string]$Registry.registry_name } else { "PDA Runtime Tool Registry" }
    generated_at = if ($Registry.PSObject.Properties.Name -contains "generated_at") { [string]$Registry.generated_at } else { "" }
    tool_count = @($Tools).Count
    local_only_count = @($Tools | Where-Object { [bool]$_.local_only }).Count
    cloud_capable_count = @($Tools | Where-Object { -not [bool]$_.local_only }).Count
    requires_approval_count = @($Tools | Where-Object { [bool]$_.approval_required }).Count
    category_1_count = @($Tools | Where-Object { @($_.category_allowed) -contains "category_1" }).Count
    category_2_count = @($Tools | Where-Object { @($_.category_allowed) -contains "category_2" }).Count
    tools = @($Tools)
    source_of_truth = "Scripts/Get-PDATool.ps1"
}

if (-not [string]::IsNullOrWhiteSpace($ToolId)) {
    $Tool = Get-PDAToolRegistryEntry -Registry $Registry -ToolId $ToolId
    if (-not $Tool) {
        $Result = [pscustomobject]@{
            status = "fail"
            blocked_reason = "Tool '$ToolId' was not found in the registry."
            registry_path = $ResolvedRegistryPath
            tool = $null
            source_of_truth = "Scripts/Get-PDATool.ps1"
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

    $Result = [pscustomobject]@{
        status = "pass"
        registry_path = $ResolvedRegistryPath
        tool_id = [string]$Tool.tool_id
        tool = $Tool
        source_of_truth = "Scripts/Get-PDATool.ps1"
    }

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        return
    }

    Write-Host "[OK] PDA tool lookup"
    Write-Host ("Tool            : {0}" -f $Tool.display_name)
    Write-Host ("Tool ID         : {0}" -f $Tool.tool_id)
    Write-Host ("Local only      : {0}" -f [bool]$Tool.local_only)
    Write-Host ("Approval req'd  : {0}" -f [bool]$Tool.approval_required)
    return
}

if ($AsJson) {
    $Summary | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] PDA tool registry"
Write-Host ("Tools           : {0}" -f $Summary.tool_count)
Write-Host ("Local only      : {0}" -f $Summary.local_only_count)
Write-Host ("Cloud capable   : {0}" -f $Summary.cloud_capable_count)
Write-Host ("Approval req'd  : {0}" -f $Summary.requires_approval_count)
