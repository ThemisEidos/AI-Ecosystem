[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$Roots = @(),

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PDA_Environment.ps1")

$Result = Get-PDAFilesystemInventory -Roots $Roots -Root $Root

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Result.status -eq "error") {
        throw "Filesystem inventory failed."
    }
    return
}

Write-Host "[PDA FILESYSTEM INVENTORY]"
Write-Host ("Status       : {0}" -f $Result.status)
Write-Host ("Roots        : {0}" -f @($Result.roots).Count)
Write-Host ("Projects     : {0}" -f @($Result.project_candidates).Count)
Write-Host ("Archives     : {0}" -f @($Result.archive_candidates).Count)
