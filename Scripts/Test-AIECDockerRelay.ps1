[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "AIEcosystem.Commands.ps1")

Test-AIECDockerRelay -AsJson:$AsJson -NoThrow:$NoThrow
