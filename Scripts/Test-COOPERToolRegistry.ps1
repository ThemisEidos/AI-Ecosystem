[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$GeneralRegistryPath = Join-Path $PSScriptRoot "..\Config\general_tool_registry.yaml"
$PrivateRegistryPath = Join-Path $PSScriptRoot "..\Config\private_tool_registry.yaml"

$RequiredFields = @(
    "id",
    "name",
    "drawer",
    "workshop",
    "description",
    "permission_level",
    "approval_required",
    "executor_type",
    "enabled",
    "inputs",
    "outputs",
    "notes"
)

$ExternalExecutorTypes = @(
    "browser",
    "llm_api",
    "cloud_service",
    "web_api",
    "webhook",
    "image_provider",
    "research_api",
    "third_party_provider"
)

function Read-YamlFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found: $Path"
    }

    $Python = "python"
    $Parser = @'
import json
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
data = yaml.safe_load(path.read_text(encoding='utf-8'))
print(json.dumps(data, ensure_ascii=False, default=str))
'@

    $Output = & $Python -c $Parser $Path 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to parse YAML file '$Path': $($Output -join [Environment]::NewLine)"
    }

    return ($Output -join [Environment]::NewLine).Trim() | ConvertFrom-Json
}

function Test-ToolEntry {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Tool,

        [Parameter(Mandatory = $true)]
        [string]$RegistryName,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedWorkshop
    )

    $ToolId = [string]$Tool.id

    foreach ($Field in $RequiredFields) {
        if ($Tool.PSObject.Properties.Name -notcontains $Field) {
            $script:Issues.Add("$RegistryName tool '$ToolId' is missing required field '$Field'.")
        }
    }

    if ($Tool.PSObject.Properties.Name -contains "workshop" -and [string]$Tool.workshop -ne $ExpectedWorkshop) {
        $script:Issues.Add("$RegistryName tool '$ToolId' must use workshop '$ExpectedWorkshop' but found '$([string]$Tool.workshop)'.")
    }

    if ($Tool.PSObject.Properties.Name -contains "permission_level") {
        if ($null -eq $Tool.permission_level -or [int]$Tool.permission_level -lt 0 -or [int]$Tool.permission_level -gt 5) {
            $script:Issues.Add("$RegistryName tool '$ToolId' has invalid permission_level '$([string]$Tool.permission_level)'.")
        }
    }

    foreach ($BoolField in @("approval_required", "enabled")) {
        if ($Tool.PSObject.Properties.Name -contains $BoolField -and $Tool.$BoolField -isnot [bool]) {
            $script:Issues.Add("$RegistryName tool '$ToolId' field '$BoolField' must be boolean.")
        }
    }

    foreach ($ArrayField in @("inputs", "outputs")) {
        if ($Tool.PSObject.Properties.Name -contains $ArrayField -and $Tool.$ArrayField -isnot [array]) {
            $script:Issues.Add("$RegistryName tool '$ToolId' field '$ArrayField' must be an array.")
        }
    }

    if ($RegistryName -eq "Private registry") {
        if ([int]$Tool.permission_level -eq 3) {
            $script:Issues.Add("Private registry tool '$ToolId' may not use permission_level 3.")
        }

        if (($ExternalExecutorTypes -contains [string]$Tool.executor_type)) {
            $script:Issues.Add("Private registry tool '$ToolId' may not use external executor_type '$([string]$Tool.executor_type)'.")
        }
    }
}

$Issues = New-Object System.Collections.Generic.List[string]
$General = Read-YamlFile -Path $GeneralRegistryPath
$Private = Read-YamlFile -Path $PrivateRegistryPath

foreach ($TopLevel in @(
    [pscustomobject]@{ Name = "General registry"; Data = $General; Path = $GeneralRegistryPath; ExpectedWorkshop = "Open Workshop" },
    [pscustomobject]@{ Name = "Private registry"; Data = $Private; Path = $PrivateRegistryPath; ExpectedWorkshop = "Private Workshop" }
)) {
    if ($null -eq $TopLevel.Data) {
        $Issues.Add("$($TopLevel.Name) at '$($TopLevel.Path)' is empty or invalid.")
        continue
    }

    if ($TopLevel.Data.PSObject.Properties.Name -notcontains "tools") {
        $Issues.Add("$($TopLevel.Name) at '$($TopLevel.Path)' is missing top-level 'tools'.")
        continue
    }

    if ($TopLevel.Data.tools.Count -eq 0) {
        $Issues.Add("$($TopLevel.Name) at '$($TopLevel.Path)' contains no tools.")
        continue
    }

    foreach ($Tool in @($TopLevel.Data.tools)) {
        Test-ToolEntry -Tool $Tool -RegistryName $TopLevel.Name -ExpectedWorkshop $TopLevel.ExpectedWorkshop
    }
}

$CombinedIds = @{}
foreach ($Tool in @($General.tools) + @($Private.tools)) {
    if ($null -eq $Tool.id) {
        continue
    }

    $ToolId = [string]$Tool.id
    if ($CombinedIds.ContainsKey($ToolId)) {
        $Issues.Add("Duplicate tool id '$ToolId' found across registries.")
    }
    else {
        $CombinedIds[$ToolId] = $true
    }
}

if ($Issues.Count -eq 0) {
    Write-Host "[PASS] COOPER tool registry validation passed."
    Write-Host "[PASS] Loaded $(@($General.tools).Count) Open Workshop tools and $(@($Private.tools).Count) Private Workshop tools."
    exit 0
}

Write-Host "[FAIL] COOPER tool registry validation failed."
foreach ($Issue in $Issues) {
    Write-Host "[FAIL] $Issue"
}
Write-Host "[FAIL] Loaded $(@($General.tools).Count) Open Workshop tools and $(@($Private.tools).Count) Private Workshop tools."
exit 1
