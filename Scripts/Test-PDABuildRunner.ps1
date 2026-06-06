[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$NightlyTest = Join-Path $PSScriptRoot "Test-PDANightlyAutomation.ps1"
if (-not (Test-Path -LiteralPath $NightlyTest -PathType Leaf)) {
    throw "Build runner validation test missing: $NightlyTest"
}

$Args = @()
if ($AsJson) {
    $Args += "-AsJson"
}
if ($NoThrow) {
    $Args += "-NoThrow"
}

$Raw = & pwsh -NoProfile -File $NightlyTest @Args 2>&1
$Text = [string]($Raw -join "`n").Trim()
if ([string]::IsNullOrWhiteSpace($Text)) {
    throw "Build runner validation returned empty output."
}

if ($AsJson) {
    $Text
    return
}

Write-Host "[OK] PDA build runner validation delegated to the compatibility automation test."
Write-Host $Text
