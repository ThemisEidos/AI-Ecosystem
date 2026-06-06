[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PDA_OutputParsing.ps1")

$Root = Split-Path -Parent $PSScriptRoot
$RoadmapPath = Join-Path $Root "Roadmap\PDA-Roadmap.json"
$HelperScript = Join-Path $PSScriptRoot "PDA_NightlyAutomation.ps1"
$StateScript = Join-Path $PSScriptRoot "Get-PDANightlyTaskState.ps1"
$UpdateScript = Join-Path $PSScriptRoot "Update-PDARoadmapStatus.ps1"
$PacketScript = Join-Path $PSScriptRoot "Generate-PDACodexWorkPacket.ps1"
$MorningScript = Join-Path $PSScriptRoot "Generate-PDAMorningReport.ps1"
$OrchestratorScript = Join-Path $PSScriptRoot "Invoke-PDABuildOrchestrator.ps1"
$StartScript = Join-Path $PSScriptRoot "Start-PDANightlyBuild.ps1"

foreach ($Path in @($RoadmapPath, $HelperScript, $StateScript, $UpdateScript, $PacketScript, $MorningScript, $OrchestratorScript, $StartScript)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file missing: $Path"
    }
}

function Invoke-PDAJsonScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $Raw = & pwsh -NoProfile -File $Path @Arguments -AsJson 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Command returned empty output: $Path"
    }
    $Result = ConvertFrom-PDAMixedJson -Text $Text -SourceName $Path
    if ($LASTEXITCODE -ne 0 -and (-not $Result.PSObject.Properties.Name -contains "status" -or [string]$Result.status -ne "pass")) {
        throw "Command failed: $Path"
    }

    return $Result
}

function Initialize-PDATempRepo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot,

        [Parameter(Mandatory = $true)]
        [string]$SourceRoot
    )

    New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null
    foreach ($Folder in @("Roadmap", "Scripts")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $DestinationRoot $Folder) | Out-Null
    }

    & git init $DestinationRoot | Out-Null
    & git -C $DestinationRoot config user.name "Codex Test" | Out-Null
    & git -C $DestinationRoot config user.email "codex@example.com" | Out-Null
    & git -C $DestinationRoot commit --allow-empty -m "seed" | Out-Null
    & git -C $DestinationRoot branch -M main | Out-Null

    foreach ($Path in @(
        "Roadmap\PDA-Roadmap.json",
        "Scripts\PDA_OutputParsing.ps1",
        "Scripts\PDA_NightlyAutomation.ps1",
        "Scripts\Get-PDANightlyTaskState.ps1",
        "Scripts\Update-PDARoadmapStatus.ps1",
        "Scripts\Generate-PDACodexWorkPacket.ps1",
        "Scripts\Generate-PDAMorningReport.ps1",
        "Scripts\Invoke-PDAQueueBacklogAudit.ps1",
        "Scripts\Test-PDAQueueBacklogAudit.ps1",
        "Scripts\Invoke-PDABuildOrchestrator.ps1",
        "Scripts\Start-PDANightlyBuild.ps1",
        "Scripts\Backup-PDARepo.ps1",
        "Scripts\Backup-PDAVolumes.ps1",
        "Scripts\Test-PDANightlyAutomation.ps1"
    )) {
        Copy-Item -Force (Join-Path $SourceRoot $Path) (Join-Path $DestinationRoot $Path)
    }

    $ExcludePath = Join-Path $DestinationRoot ".git\info\exclude"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ExcludePath) | Out-Null
    @(
        "Roadmap/",
        "Roadmap/work-packets/",
        "PDA-Tasks/",
        "PDA-Backups/",
        "Scripts/PDA_OutputParsing.ps1",
        "Scripts/PDA_NightlyAutomation.ps1",
        "Scripts/Get-PDANightlyTaskState.ps1",
        "Scripts/Update-PDARoadmapStatus.ps1",
        "Scripts/Generate-PDACodexWorkPacket.ps1",
        "Scripts/Generate-PDAMorningReport.ps1",
        "Scripts/Invoke-PDAQueueBacklogAudit.ps1",
        "Scripts/Test-PDAQueueBacklogAudit.ps1",
        "Scripts/Invoke-PDABuildOrchestrator.ps1",
        "Scripts/Start-PDANightlyBuild.ps1",
        "Scripts/Backup-PDARepo.ps1",
        "Scripts/Backup-PDAVolumes.ps1",
        "Scripts/Test-PDANightlyAutomation.ps1"
    ) | Add-Content -Path $ExcludePath
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pda-nightly-auto-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$TempRepoRoot = Join-Path $TempRoot "repo"
Initialize-PDATempRepo -DestinationRoot $TempRepoRoot -SourceRoot $Root

$Roadmap = Invoke-PDAJsonScript -Path $StateScript -Arguments @(
    "-Root", $TempRepoRoot,
    "-RoadmapPath", (Join-Path $TempRepoRoot "Roadmap\PDA-Roadmap.json"),
    "-TaskId", "task-001"
)

$Issues = New-Object System.Collections.Generic.List[string]
if ($Roadmap.task_state.status -ne "backlog") {
    $Issues.Add("Initial task state should be backlog.")
}

$OrchestratorDryRun = Invoke-PDAJsonScript -Path $OrchestratorScript -Arguments @(
    "-Root", $TempRepoRoot,
    "-RoadmapPath", (Join-Path $TempRepoRoot "Roadmap\PDA-Roadmap.json"),
    "-OutputRoot", $TempRoot
)

$OrchestratorPrepare = Invoke-PDAJsonScript -Path $OrchestratorScript -Arguments @(
    "-Root", $TempRepoRoot,
    "-RoadmapPath", (Join-Path $TempRepoRoot "Roadmap\PDA-Roadmap.json"),
    "-OutputRoot", $TempRoot,
    "-PrepareExecution"
)

$WrapperPrepare = Invoke-PDAJsonScript -Path $StartScript -Arguments @(
    "-Root", $TempRepoRoot,
    "-RoadmapPath", (Join-Path $TempRepoRoot "Roadmap\PDA-Roadmap.json"),
    "-OutputRoot", $TempRoot,
    "-PrepareExecution"
)

& git -C $TempRepoRoot add -f Roadmap/PDA-Roadmap.json | Out-Null
& git -C $TempRepoRoot commit -m "prepare nightly automation state" | Out-Null

$ExecuteRepoRoot = Join-Path $TempRoot "execute-repo"
Initialize-PDATempRepo -DestinationRoot $ExecuteRepoRoot -SourceRoot $TempRepoRoot
& git -C $ExecuteRepoRoot add -f Roadmap/PDA-Roadmap.json | Out-Null
& git -C $ExecuteRepoRoot commit -m "prepare execution state" | Out-Null

$OrchestratorExecute = Invoke-PDAJsonScript -Path $OrchestratorScript -Arguments @(
    "-Root", $ExecuteRepoRoot,
    "-RoadmapPath", (Join-Path $ExecuteRepoRoot "Roadmap\PDA-Roadmap.json"),
    "-OutputRoot", $TempRoot,
    "-ExecutePreparedTask"
)

$WrapperExecuteRepoRoot = Join-Path $TempRoot "wrapper-execute-repo"
Initialize-PDATempRepo -DestinationRoot $WrapperExecuteRepoRoot -SourceRoot $TempRepoRoot
& git -C $WrapperExecuteRepoRoot add -f Roadmap/PDA-Roadmap.json | Out-Null
& git -C $WrapperExecuteRepoRoot commit -m "prepare execution state" | Out-Null

$WrapperExecute = Invoke-PDAJsonScript -Path $StartScript -Arguments @(
    "-Root", $WrapperExecuteRepoRoot,
    "-RoadmapPath", (Join-Path $WrapperExecuteRepoRoot "Roadmap\PDA-Roadmap.json"),
    "-OutputRoot", $TempRoot,
    "-ExecutePreparedTask"
)

if ($OrchestratorDryRun.mode -ne "dry-run") {
    $Issues.Add("Default orchestrator mode should be dry-run.")
}

if ($OrchestratorPrepare.mode -ne "prepare") {
    $Issues.Add("Prepare mode did not activate.")
}

if ($WrapperPrepare.mode -ne "prepare") {
    $Issues.Add("Prepare wrapper did not activate prepare mode.")
}

if ($OrchestratorExecute.mode -ne "execute") {
    $Issues.Add("Execution mode did not activate.")
}

if ($WrapperExecute.mode -ne "execute") {
    $Issues.Add("Execution wrapper did not activate execute mode.")
}

if ($OrchestratorDryRun.selected_task_id -ne "task-001") {
    $Issues.Add("Dry-run orchestrator did not select task-001.")
}

if ($OrchestratorPrepare.selected_task_id -ne "task-001") {
    $Issues.Add("Prepare mode did not select task-001.")
}

if ($OrchestratorExecute.selected_task_id -ne "task-001") {
    $Issues.Add("Execution mode did not select task-001.")
}

if ($WrapperExecute.selected_task_id -ne "task-001") {
    $Issues.Add("Execution wrapper did not select task-001.")
}

if (-not ($OrchestratorDryRun.branch_name -like "codex/nightly-task-001-*")) {
    $Issues.Add("Dry-run branch name is not task-001 scoped.")
}

if (-not ($OrchestratorPrepare.branch_name -like "codex/nightly-task-001-*")) {
    $Issues.Add("Prepare branch name is not task-001 scoped.")
}

if (-not ($OrchestratorExecute.branch_name -like "codex/nightly-task-001-*")) {
    $Issues.Add("Execution branch name is not task-001 scoped.")
}

if (-not ($WrapperExecute.branch_name -like "codex/nightly-task-001-*")) {
    $Issues.Add("Wrapper execution branch name is not task-001 scoped.")
}

if ($OrchestratorDryRun.next_action -notmatch 'Human review required') {
    $Issues.Add("Dry-run next action should require human review.")
}

if ($OrchestratorPrepare.next_action -notmatch 'Human review required') {
    $Issues.Add("Prepare mode next action should require human review.")
}

if ($OrchestratorExecute.next_action -notmatch 'Human review required before Codex execution') {
    $Issues.Add("Execution mode next action should require human review before Codex execution.")
}

if ($WrapperExecute.next_action -notmatch 'Human review required before Codex execution') {
    $Issues.Add("Execution wrapper next action should require human review before Codex execution.")
}

if (-not ($OrchestratorDryRun.repo_backup_manifest.dry_run -eq $true)) {
    $Issues.Add("Dry-run repo backup manifest should be marked dry-run.")
}

if (-not ($OrchestratorPrepare.repo_backup_manifest.dry_run -eq $true)) {
    $Issues.Add("Prepare repo backup manifest should be marked dry-run.")
}

if (-not ($OrchestratorExecute.execution_transition_count -ge 1)) {
    $Issues.Add("Execution mode did not advance the roadmap state.")
}

if ($OrchestratorExecute.task_state.task_state.status -ne "assigned") {
    $Issues.Add("Execution mode should leave the task in assigned state.")
}

if ($WrapperExecute.task_state.task_state.status -ne "assigned") {
    $Issues.Add("Execution wrapper should leave the task in assigned state.")
}

if (-not (Test-Path -LiteralPath $OrchestratorPrepare.work_packet_path -PathType Leaf)) {
    $Issues.Add("Work packet JSON was not written.")
}

if (-not (Test-Path -LiteralPath $OrchestratorPrepare.work_packet_markdown_path -PathType Leaf)) {
    $Issues.Add("Work packet markdown was not written.")
}

if (-not (Test-Path -LiteralPath $OrchestratorExecute.execution_summary_path -PathType Leaf)) {
    $Issues.Add("Execution summary JSON was not written.")
}

if (-not (Test-Path -LiteralPath $OrchestratorExecute.execution_summary_markdown_path -PathType Leaf)) {
    $Issues.Add("Execution summary markdown was not written.")
}

if (-not (Test-Path -LiteralPath $OrchestratorExecute.morning_report_path -PathType Leaf)) {
    $Issues.Add("Morning report was not written.")
}

$Report = [pscustomobject]@{
    status                       = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    roadmap_path                 = (Join-Path $TempRepoRoot "Roadmap\PDA-Roadmap.json")
    dry_run_mode                 = $OrchestratorDryRun.mode
    prepare_mode                 = $OrchestratorPrepare.mode
    execute_mode                 = $OrchestratorExecute.mode
    execute_wrapper_mode         = $WrapperExecute.mode
    transition_count             = @($OrchestratorExecute.execution_transition_chain).Count
    work_packet_path             = $OrchestratorPrepare.work_packet_path
    morning_report_path          = $OrchestratorExecute.morning_report_path
    execution_summary_path       = $OrchestratorExecute.execution_summary_path
    execution_summary_markdown_path = $OrchestratorExecute.execution_summary_markdown_path
    issues                       = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 40
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA nightly automation validation failed."
    }
    return
}

Write-Host "[*] PDA nightly automation tests"
Write-Host ("Status         : {0}" -f $Report.status)
Write-Host ("Transitions    : {0}" -f $Report.transition_count)
Write-Host ("Work packet    : {0}" -f $Report.work_packet_path)
Write-Host ("Morning report : {0}" -f $Report.morning_report_path)
Write-Host ("Execution summary: {0}" -f $Report.execution_summary_path)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA nightly automation validation failed."
}
