[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_Fabric.ps1")

$Health = & pwsh -NoProfile -File (Join-Path $PSScriptRoot "Invoke-PDAFabricHealthCheck.ps1") -AsJson -NoThrow | ConvertFrom-Json

$Result = [pscustomobject]@{
    status           = if (-not [string]::IsNullOrWhiteSpace([string]$Health.executable_path) -and -not [string]::IsNullOrWhiteSpace([string]$Health.version)) { "pass" } else { "fail" }
    executable_path  = [string]$Health.executable_path
    version          = [string]$Health.version
    config_path      = [string]$Health.config_path
    config_exists    = [bool]$Health.config_exists
    pattern_count    = [int]$Health.pattern_count
    message          = [string]$Health.message
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 8
    return
}

Write-Host "[*] Fabric install verification"
Write-Host ("Status          : {0}" -f $Result.status)
Write-Host ("Executable path : {0}" -f $Result.executable_path)
Write-Host ("Version         : {0}" -f $Result.version)
Write-Host ("Config path     : {0}" -f $Result.config_path)
Write-Host ("Pattern count   : {0}" -f $Result.pattern_count)

if ($Result.status -ne "pass" -and -not $NoThrow) {
    throw "Fabric install verification failed."
}
