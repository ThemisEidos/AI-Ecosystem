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
    [switch]$ExportCodexExecutionPrompt,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$Runner = Join-Path $PSScriptRoot "Invoke-PDABuildRunner.ps1"
if (-not (Test-Path -LiteralPath $Runner -PathType Leaf)) {
    throw "Build runner entrypoint missing: $Runner"
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

if ($ExportCodexExecutionPrompt) {
    $Args += "-ExportCodexExecutionPrompt"
}

if ($AsJson) {
    $Args += "-AsJson"
}

& pwsh -NoProfile -File $Runner @Args
