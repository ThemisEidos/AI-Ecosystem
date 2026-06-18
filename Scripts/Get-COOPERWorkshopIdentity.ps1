[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("", "Open Workshop", "Private Workshop")]
    [string]$WorkshopMode = "",

    [Parameter(Mandatory = $false)]
    [string]$ModelIdentity = "",

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
$ResolvedWorkshopMode = [string]$WorkshopMode
if ([string]::IsNullOrWhiteSpace($ResolvedWorkshopMode) -and -not [string]::IsNullOrWhiteSpace([string]$ModelIdentity)) {
    $NormalizedModelIdentity = [string]$ModelIdentity.Trim().ToLowerInvariant()
    switch ($NormalizedModelIdentity) {
        { $_ -in @("cooper - private", "cooper private", "pda_chat_bridge.cooper_private", "pda_chat_bridge.cooper-private", "cooper_private") } {
            $ResolvedWorkshopMode = "Private Workshop"
            break
        }
        { $_ -in @("cooper", "pda_chat_bridge.cooper") } {
            $ResolvedWorkshopMode = "Open Workshop"
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($ResolvedWorkshopMode)) {
    $ResolvedWorkshopMode = "Open Workshop"
}

$WorkshopEntry = $Config.workshops | Where-Object {
    [string]$_.workshop_label -eq $ResolvedWorkshopMode -or
    ([string]$_.model_identity -and [string]$_.model_identity -eq $ModelIdentity)
} | Select-Object -First 1
if ($null -eq $WorkshopEntry) {
    throw "Workshop mode '$ResolvedWorkshopMode' was not found in $ConfigPath."
}

$RegistryPath = Join-Path $Root ([string]$WorkshopEntry.registry)

[pscustomobject]@{
    status = "pass"
    display_name = [string]$WorkshopEntry.display_name
    model_identity = if ($WorkshopEntry.PSObject.Properties.Name -contains "model_identity" -and -not [string]::IsNullOrWhiteSpace([string]$WorkshopEntry.model_identity)) { [string]$WorkshopEntry.model_identity } else { [string]$WorkshopEntry.display_name }
    workshop_label = [string]$WorkshopEntry.workshop_label
    workshop = [string]$WorkshopEntry.workshop
    default_model = [string]$WorkshopEntry.default_model
    registry = [string]$WorkshopEntry.registry
    registry_path = $RegistryPath
    cloud_allowed = [bool]$WorkshopEntry.cloud_allowed
    source_of_truth = $ConfigPath
}
