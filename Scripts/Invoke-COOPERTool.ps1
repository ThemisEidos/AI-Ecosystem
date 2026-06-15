[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ToolId = "",

    [Parameter(Mandatory = $false)]
    [string]$Drawer = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("Open Workshop", "Private Workshop")]
    [string]$Workshop = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("Open Workshop", "Private Workshop")]
    [string]$WorkshopMode,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [string]$GeneralRegistryPath = "",

    [Parameter(Mandatory = $false)]
    [string]$PrivateRegistryPath = ""
)

$ErrorActionPreference = "Stop"

$ResolvedGeneralRegistryPath = if ([string]::IsNullOrWhiteSpace($GeneralRegistryPath)) {
    Join-Path $PSScriptRoot "..\Config\general_tool_registry.yaml"
}
else {
    $GeneralRegistryPath
}

$ResolvedPrivateRegistryPath = if ([string]::IsNullOrWhiteSpace($PrivateRegistryPath)) {
    Join-Path $PSScriptRoot "..\Config\private_tool_registry.yaml"
}
else {
    $PrivateRegistryPath
}

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

if ([string]::IsNullOrWhiteSpace($WorkshopMode)) {
    return [pscustomobject]@{
        status = "fail"
        blocked_reason = "WorkshopMode is required."
        selected_tool = ""
        execution_allowed = $false
    }
}

$WorkshopIdentityScript = Join-Path $PSScriptRoot "Get-COOPERWorkshopIdentity.ps1"
if (-not (Test-Path -LiteralPath $WorkshopIdentityScript -PathType Leaf)) {
    throw "Workshop identity resolver missing: $WorkshopIdentityScript"
}

function Read-COOPERYamlFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found: $Path"
    }

    $Parser = @'
import json
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
data = yaml.safe_load(path.read_text(encoding='utf-8'))
print(json.dumps(data, ensure_ascii=False, default=str))
'@

    $Output = & python -c $Parser $Path 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to parse YAML file '$Path': $($Output -join [Environment]::NewLine)"
    }

    return ($Output -join [Environment]::NewLine).Trim() | ConvertFrom-Json
}

function Test-COOPERToolEntry {
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

    if ($RegistryName -eq "Private registry") {
        if ([int]$Tool.permission_level -eq 3) {
            $script:Issues.Add("Private registry tool '$ToolId' may not use permission_level 3.")
        }

        if ($ExternalExecutorTypes -contains [string]$Tool.executor_type) {
            $script:Issues.Add("Private registry tool '$ToolId' may not use external executor_type '$([string]$Tool.executor_type)'.")
        }
    }
}

function Select-COOPERTool {
    param(
        [Parameter(Mandatory = $true)]
        $Registry,

        [Parameter(Mandatory = $false)]
        [string]$ToolId = "",

        [Parameter(Mandatory = $false)]
        [string]$Drawer = "",

        [Parameter(Mandatory = $false)]
        [string]$Workshop = ""
    )

    $TargetWorkshop = [string]$Workshop
    $Candidates = @()

    $Candidates = @($Registry.tools)

    if (-not [string]::IsNullOrWhiteSpace($ToolId)) {
        $Candidates = @($Candidates | Where-Object { [string]$_.id -eq $ToolId })
    }

    if (-not [string]::IsNullOrWhiteSpace($Drawer)) {
        $Candidates = @($Candidates | Where-Object { [string]$_.drawer -eq $Drawer })
    }

    if ($Candidates.Count -eq 0) {
        return [pscustomobject]@{
            status = "fail"
            blocked_reason = if (-not [string]::IsNullOrWhiteSpace($ToolId)) {
                "No tool matched tool id '$ToolId'."
            }
            elseif (-not [string]::IsNullOrWhiteSpace($Drawer)) {
                "No tool matched drawer '$Drawer'."
            }
            elseif (-not [string]::IsNullOrWhiteSpace($TargetWorkshop)) {
                "No tool matched workshop '$TargetWorkshop'."
            }
            else {
                "No tool criteria were provided."
            }
            selected_tool = ""
            execution_allowed = $false
        }
    }

    if ($Candidates.Count -gt 1) {
        $CandidateList = @($Candidates | ForEach-Object { [string]$_.id }) -join ", "
        return [pscustomobject]@{
            status = "fail"
            blocked_reason = "Lookup is ambiguous. Matching tools: $CandidateList"
            selected_tool = ""
            execution_allowed = $false
        }
    }

    $Selected = $Candidates[0]
    $SelectedWorkshop = [string]$Selected.workshop
    $SelectedPermissionLevel = [int]$Selected.permission_level
    $SelectedExecutorType = [string]$Selected.executor_type

    if ($SelectedWorkshop -eq "Private Workshop") {
        if ($SelectedPermissionLevel -eq 3) {
            return [pscustomobject]@{
                status = "fail"
                blocked_reason = "Private Workshop rejected tool '$([string]$Selected.id)' because it uses permission_level 3."
                selected_tool = [string]$Selected.id
                execution_allowed = $false
            }
        }

        if ($ExternalExecutorTypes -contains $SelectedExecutorType) {
            return [pscustomobject]@{
                status = "fail"
                blocked_reason = "Private Workshop rejected tool '$([string]$Selected.id)' because it uses external executor_type '$SelectedExecutorType'."
                selected_tool = [string]$Selected.id
                execution_allowed = $false
            }
        }
    }

    $ExecutionAllowed = [bool]$Selected.enabled -and (
        $SelectedWorkshop -eq "Open Workshop" -or
        ($SelectedWorkshop -eq "Private Workshop" -and $SelectedPermissionLevel -le 4 -and $ExternalExecutorTypes -notcontains $SelectedExecutorType)
    )

    return [pscustomobject]@{
        status = "pass"
        dry_run = [bool]$DryRun
        selected_tool = [string]$Selected.id
        id = [string]$Selected.id
        name = [string]$Selected.name
        drawer = [string]$Selected.drawer
        workshop = $SelectedWorkshop
        description = [string]$Selected.description
        permission_level = $SelectedPermissionLevel
        approval_required = [bool]$Selected.approval_required
        executor_type = $SelectedExecutorType
        enabled = [bool]$Selected.enabled
        inputs = @($Selected.inputs)
        outputs = @($Selected.outputs)
        notes = [string]$Selected.notes
        execution_allowed = $ExecutionAllowed
        report = if ($DryRun) {
            "Dry run only. Execution would $(
                if ($ExecutionAllowed) { 'be allowed' } else { 'not be allowed' }
            )."
        }
        else {
            "Lookup complete. No execution performed."
        }
    }
}

$WorkshopIdentity = & $WorkshopIdentityScript -WorkshopMode $WorkshopMode -Root (Split-Path -Parent $PSScriptRoot)

$EffectiveWorkshopMode = [string]$WorkshopIdentity.workshop_label
$EffectiveWorkshop = if ([string]::IsNullOrWhiteSpace($Workshop)) {
    $EffectiveWorkshopMode
}
else {
    [string]$Workshop
}

if (-not [string]::IsNullOrWhiteSpace($Workshop) -and [string]$Workshop -ne $EffectiveWorkshopMode) {
    return [pscustomobject]@{
        status = "fail"
        blocked_reason = "Workshop '$Workshop' does not match selected workshop mode '$WorkshopMode'."
        selected_tool = ""
        execution_allowed = $false
    }
}

$ActiveRegistryPath = if ($EffectiveWorkshopMode -eq "Open Workshop") {
    if (-not [string]::IsNullOrWhiteSpace($GeneralRegistryPath)) {
        $ResolvedGeneralRegistryPath
    }
    else {
        [string]$WorkshopIdentity.registry_path
    }
}
elseif ($EffectiveWorkshopMode -eq "Private Workshop") {
    if (-not [string]::IsNullOrWhiteSpace($PrivateRegistryPath)) {
        $ResolvedPrivateRegistryPath
    }
    else {
        [string]$WorkshopIdentity.registry_path
    }
}
else {
    [string]$WorkshopIdentity.registry_path
}

$ActiveRegistry = Read-COOPERYamlFile -Path $ActiveRegistryPath

$Issues = New-Object System.Collections.Generic.List[string]

foreach ($Tool in @($ActiveRegistry.tools)) {
    Test-COOPERToolEntry -Tool $Tool -RegistryName "Active registry" -ExpectedWorkshop $EffectiveWorkshopMode
}

if ($Issues.Count -gt 0) {
    return [pscustomobject]@{
        status = "fail"
        blocked_reason = ($Issues -join " ")
        selected_tool = ""
        execution_allowed = $false
    }
}

$Selection = Select-COOPERTool -Registry $ActiveRegistry -ToolId $ToolId -Drawer $Drawer -Workshop $EffectiveWorkshop

if ($Selection.status -eq "pass") {
    $Selection | Add-Member -NotePropertyName workshop_mode -NotePropertyValue $WorkshopMode -Force
    $Selection | Add-Member -NotePropertyName workshop_identity -NotePropertyValue $WorkshopIdentity -Force
    $Selection | Add-Member -NotePropertyName registry_path -NotePropertyValue $ActiveRegistryPath -Force
    $Selection | Add-Member -NotePropertyName cloud_allowed -NotePropertyValue [bool]$WorkshopIdentity.cloud_allowed -Force
}

return $Selection
