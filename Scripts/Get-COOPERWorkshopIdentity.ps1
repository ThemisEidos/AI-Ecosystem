[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Open Workshop", "Private Workshop")]
    [string]$WorkshopMode,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "",

    [Parameter(Mandatory = $false)]
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot "..\Config\cooper_workshop_identities.yaml"
}

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

function ConvertFrom-COOPERYamlText {
    param([Parameter(Mandatory = $true)][string]$Path)

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
        throw "Failed to parse workshop identity config '$Path': $($Output -join [Environment]::NewLine)"
    }

    return ($Output -join [Environment]::NewLine).Trim() | ConvertFrom-Json
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Workshop identity config not found: $ConfigPath"
}

$Config = ConvertFrom-COOPERYamlText -Path $ConfigPath
$WorkshopEntry = $Config.workshops | Where-Object { [string]$_.workshop_label -eq $WorkshopMode } | Select-Object -First 1
if ($null -eq $WorkshopEntry) {
    throw "Workshop mode '$WorkshopMode' was not found in $ConfigPath."
}

$RegistryPath = Join-Path $Root ([string]$WorkshopEntry.registry)

[pscustomobject]@{
    status = "pass"
    display_name = [string]$WorkshopEntry.display_name
    workshop_label = [string]$WorkshopEntry.workshop_label
    workshop = [string]$WorkshopEntry.workshop
    default_model = [string]$WorkshopEntry.default_model
    registry = [string]$WorkshopEntry.registry
    registry_path = $RegistryPath
    cloud_allowed = [bool]$WorkshopEntry.cloud_allowed
    source_of_truth = $ConfigPath
}
