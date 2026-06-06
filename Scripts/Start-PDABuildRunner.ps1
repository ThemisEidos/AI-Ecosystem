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
    [switch]$ExecuteCodexTask,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCodexExecutionPrompt,

    [Parameter(Mandatory = $false)]
    [int]$MaxTasks,

    [Parameter(Mandatory = $false)]
    [int]$MaxRuntimeMinutes,

    [Parameter(Mandatory = $false)]
    [switch]$StopOnFailure,

    [Parameter(Mandatory = $false)]
    [string]$RunReport,

    [Parameter(Mandatory = $false)]
    [string]$CodexExecutable,

    [Parameter(Mandatory = $false)]
    [string]$CodexArguments,

    [Parameter(Mandatory = $false)]
    [switch]$Unattended,

    [Parameter(Mandatory = $false)]
    [switch]$Monitor,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
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
elseif ($ExecuteCodexTask) {
    $Args += "-ExecuteCodexTask"
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

if ($PSBoundParameters.ContainsKey("MaxTasks")) {
    $Args += @("-MaxTasks", [string]$MaxTasks)
}

if ($PSBoundParameters.ContainsKey("MaxRuntimeMinutes")) {
    $Args += @("-MaxRuntimeMinutes", [string]$MaxRuntimeMinutes)
}

if ($PSBoundParameters.ContainsKey("StopOnFailure")) {
    $Args += "-StopOnFailure"
}

if (-not [string]::IsNullOrWhiteSpace($RunReport)) {
    $Args += @("-RunReport", $RunReport)
}

if (-not [string]::IsNullOrWhiteSpace($CodexExecutable)) {
    $Args += @("-CodexExecutable", $CodexExecutable)
}

if (-not [string]::IsNullOrWhiteSpace($CodexArguments)) {
    $Args += @("-CodexArguments", $CodexArguments)
}

if ($Unattended) {
    $Args += "-Unattended"
}

if ($Monitor) {
    $Args += "-Monitor"
}

if ($AsJson) {
    $Args += "-AsJson"
}

if ($NoThrow) {
    $Args += "-NoThrow"
}

& pwsh -NoProfile -File $Runner @Args
