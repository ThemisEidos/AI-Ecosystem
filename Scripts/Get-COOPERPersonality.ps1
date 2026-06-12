[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "COOPER_PersonalityEngine.ps1")

$Result = Get-COOPERPersonality -Root $Root
if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] COOPER personality"
Write-Host ("Profile : {0}" -f $Result.personality.profile)
Write-Host ("Humor   : {0}" -f $Result.personality.humor)
Write-Host ("Sarcasm : {0}" -f $Result.personality.sarcasm)
Write-Host ("Pro     : {0}" -f $Result.personality.professionalism)
Write-Host ("Brevity : {0}" -f $Result.personality.brevity)
Write-Host ("Init    : {0}" -f $Result.personality.initiative)
Write-Host ("Risk    : {0}" -f $Result.personality.risk_awareness)
