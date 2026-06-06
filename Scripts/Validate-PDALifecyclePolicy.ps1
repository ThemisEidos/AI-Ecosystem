[CmdletBinding()]
param(
    [switch]$AsJson,
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "PDA_Lifecycle.ps1")

$Report = Test-PDALifecyclePolicyContract -Root (Split-Path -Parent $PSScriptRoot)

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and -not $Report.valid) {
        throw "PDA lifecycle policy validation failed."
    }
    return
}

Write-Host "[*] PDA lifecycle policy validation"
Write-Host ("Policy path      : {0}" -f $Report.policy_path)
Write-Host ("Schema path      : {0}" -f $Report.schema_path)
Write-Host ("Issue count      : {0}" -f $Report.issue_count)
Write-Host ("Status           : {0}" -f ($(if ($Report.valid) { "pass" } else { "fail" })))

if (-not $NoThrow -and -not $Report.valid) {
    throw "PDA lifecycle policy validation failed."
}
