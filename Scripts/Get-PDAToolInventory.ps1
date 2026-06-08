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

$Result = Get-PDAToolInventory -Root $Root

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Result.status -eq "error") {
        throw "Tool inventory failed."
    }
    return
}

Write-Host "[PDA TOOL INVENTORY]"
Write-Host ("Status       : {0}" -f $Result.status)
Write-Host ("Available    : {0}" -f $Result.available_count)
Write-Host ("Tools        : {0}" -f @($Result.tools).Count)
