[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$RoadmapPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\PDA-Roadmap.json"),

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$NoDryRun,

    [Parameter(Mandatory = $false)]
    [switch]$PrepareExecution,

    [Parameter(Mandatory = $false)]
    [switch]$ExecutePreparedTask,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$Orchestrator = Join-Path $PSScriptRoot "Invoke-PDABuildOrchestrator.ps1"
if (-not (Test-Path -Path $Orchestrator -PathType Leaf)) {
    throw "Build orchestrator missing: $Orchestrator"
}

$Args = @(
    "-Root", $Root,
    "-RoadmapPath", $RoadmapPath
)

if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) {
    $Args += @("-OutputRoot", $OutputRoot)
}

if ($PSBoundParameters.ContainsKey("DryRun")) {
    $Args += "-DryRun"
}
elseif ($ExecutePreparedTask) {
    $Args += "-ExecutePreparedTask"
}
elseif ($NoDryRun) {
    $Args += "-PrepareExecution"
}
elseif ($PrepareExecution) {
    $Args += "-PrepareExecution"
}
else {
    $Args += "-DryRun"
}

if ($AsJson) {
    $Args += "-AsJson"
}

& pwsh -NoProfile -File $Orchestrator @Args
