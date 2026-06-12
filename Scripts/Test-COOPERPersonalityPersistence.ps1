[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$TestScript = Join-Path $PSScriptRoot "Test-COOPERPersonalityV2.ps1"

if (-not (Test-Path -LiteralPath $TestScript -PathType Leaf)) {
    throw "COOPER personality v2 test script missing: $TestScript"
}

$Args = @()
if ($AsJson) { $Args += "-AsJson" }
if ($NoThrow) { $Args += "-NoThrow" }

& pwsh -NoProfile -File $TestScript @Args
