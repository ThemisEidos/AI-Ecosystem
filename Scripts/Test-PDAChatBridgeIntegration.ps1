<#
.SYNOPSIS
Runs the slow PDA chat bridge integration suite.

.DESCRIPTION
This is the explicit entry point for integration coverage. The default
Test-PDAChatBridge.ps1 command stays fast; this wrapper forwards to the
same script with -IncludeSlowIntegration enabled.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ChatBridgeTestScript = Join-Path $PSScriptRoot "Test-PDAChatBridge.ps1"
if (-not (Test-Path -LiteralPath $ChatBridgeTestScript -PathType Leaf)) {
    throw "PDA chat bridge test script is missing: $ChatBridgeTestScript"
}

& $ChatBridgeTestScript -IncludeSlowIntegration
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
