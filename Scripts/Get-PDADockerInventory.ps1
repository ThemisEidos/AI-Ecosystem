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

$Result = Get-PDADockerInventory -Root $Root

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Result.status -eq "error") {
        throw "Docker inventory failed."
    }
    return
}

Write-Host "[PDA DOCKER INVENTORY]"
Write-Host ("Status       : {0}" -f $Result.status)
Write-Host ("Containers   : {0}" -f $Result.total_count)
Write-Host ("Running      : {0}" -f $Result.running_count)
Write-Host ("Compose proj : {0}" -f @($Result.compose_projects).Count)
