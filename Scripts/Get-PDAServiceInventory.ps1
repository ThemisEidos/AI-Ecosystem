[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PDA_Environment.ps1")

$Result = Get-PDAServiceInventory -Root $Root

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Result.status -eq "error") {
        throw "Service inventory failed."
    }
    return
}

Write-Host "[PDA SERVICE INVENTORY]"
Write-Host ("Status       : {0}" -f $Result.status)
Write-Host ("Online       : {0}" -f $Result.online_count)
Write-Host ("Offline      : {0}" -f $Result.offline_count)
Write-Host ("Services     : {0}" -f @($Result.services).Count)
