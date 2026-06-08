[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$Roots = @(),

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [object]$FilesystemInventory = $null,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PDA_Environment.ps1")

$Result = Get-PDAFileOrganizationRecommendation -Roots $Roots -Root $Root -FilesystemInventory $FilesystemInventory

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 30
    if (-not $NoThrow -and $Result.status -eq "error") {
        throw "File organization recommendation failed."
    }
    return
}

Write-Host "[PDA FILE ORGANIZATION RECOMMENDATION]"
Write-Host ("Status       : {0}" -f $Result.status)
Write-Host ("Model        : {0}" -f $Result.recommended_model)
Write-Host ("Roots        : {0}" -f @($Result.roots).Count)
