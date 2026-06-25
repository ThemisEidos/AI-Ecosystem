[CmdletBinding()]
param(
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
$ScriptPath = Join-Path $PSScriptRoot "Start-PDAStack.ps1"

if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    throw "Open stack start script not found: $ScriptPath"
}

& $ScriptPath @PSBoundParameters
