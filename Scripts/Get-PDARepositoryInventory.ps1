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

$Result = Get-PDARepositoryInventory -Roots $Roots -Root $Root

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Result.status -eq "error") {
        throw "Repository inventory failed."
    }
    return
}

Write-Host "[PDA REPOSITORY INVENTORY]"
Write-Host ("Status       : {0}" -f $Result.status)
Write-Host ("Repositories : {0}" -f $Result.repo_count)
Write-Host ("Active       : {0}" -f @($Result.active_projects).Count)
Write-Host ("Archived     : {0}" -f @($Result.archived_projects).Count)
