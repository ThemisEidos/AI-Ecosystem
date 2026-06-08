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

$Result = Get-PDAEnvironmentSummary -Roots $Roots -Root $Root

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 30
    if (-not $NoThrow -and $Result.status -eq "error") {
        throw "Environment summary failed."
    }
    return
}

Write-Host "[PDA ENVIRONMENT SUMMARY]"
Write-Host ("Status       : {0}" -f $Result.status)
Write-Host ("Repositories : {0}" -f $Result.counts.repositories)
Write-Host ("Containers   : {0}" -f $Result.counts.containers)
Write-Host ("Services     : {0}" -f $Result.counts.services_online)
Write-Host ("Tools        : {0}" -f $Result.counts.tools_available)
