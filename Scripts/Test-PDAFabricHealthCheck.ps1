[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Health = & pwsh -NoProfile -File (Join-Path $PSScriptRoot "Invoke-PDAFabricHealthCheck.ps1") -AsJson -NoThrow | ConvertFrom-Json

$MissingPatterns = @()
foreach ($PatternCheck in @($Health.pda_patterns)) {
    if (-not [bool]$PatternCheck.exists) {
        $MissingPatterns += [string]$PatternCheck.alias
    }
}

$Result = [pscustomobject]@{
    status          = if ($Health.status -eq "pass" -and $MissingPatterns.Count -eq 0) { "pass" } elseif ($Health.status -eq "warning" -and $MissingPatterns.Count -eq 0) { "warning" } else { "fail" }
    fabric_status   = [string]$Health.status
    message         = [string]$Health.message
    executable_path = [string]$Health.executable_path
    version         = [string]$Health.version
    pattern_count   = [int]$Health.pattern_count
    missing_patterns = @($MissingPatterns)
    available_patterns = @($Health.available_patterns)
    pda_pattern_count = [int]$Health.pda_pattern_count
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 8
    return
}

Write-Host "[*] Fabric health check validation"
Write-Host ("Status          : {0}" -f $Result.status)
Write-Host ("Fabric status   : {0}" -f $Result.fabric_status)
Write-Host ("Executable path : {0}" -f $Result.executable_path)
Write-Host ("Version         : {0}" -f $Result.version)
Write-Host ("Pattern count   : {0}" -f $Result.pattern_count)
Write-Host ("PDA pattern cnt : {0}" -f $Result.pda_pattern_count)
Write-Host ("Missing patterns: {0}" -f ($Result.missing_patterns -join ', '))

if ($Result.status -eq "fail" -and -not $NoThrow) {
    throw "Fabric health check validation failed."
}
