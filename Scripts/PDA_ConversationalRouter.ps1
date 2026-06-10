[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Text,

    [Parameter(Mandatory = $false)]
    [string]$Root,

    [Parameter(Mandatory = $false)]
    [Alias("AsJson")]
    [switch]$OutputJson
)

$ErrorActionPreference = "Stop"

$TargetScript = Join-Path $PSScriptRoot "COOPER_ConversationalRouter.ps1"

if (-not (Test-Path -LiteralPath $TargetScript -PathType Leaf)) {
    throw "COOPER conversational router missing: $TargetScript"
}

if ($PSBoundParameters.ContainsKey("Text")) {
    & $TargetScript @PSBoundParameters
    return
}

. $TargetScript
