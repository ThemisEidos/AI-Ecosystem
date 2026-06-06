[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$RoadmapPath = Join-Path $Root "Roadmap\PDA-Roadmap.json"
$Orchestrator = Join-Path $PSScriptRoot "Invoke-PDABuildOrchestrator.ps1"
$QueueAuditTest = Join-Path $PSScriptRoot "Test-PDAQueueBacklogAudit.ps1"

if (-not (Test-Path -Path $RoadmapPath -PathType Leaf)) {
    throw "Roadmap missing: $RoadmapPath"
}

if (-not (Test-Path -Path $Orchestrator -PathType Leaf)) {
    throw "Orchestrator missing: $Orchestrator"
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pda-nightly-build-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$PrepareRepoRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pda-nightly-build-repo-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $PrepareRepoRoot | Out-Null

function Invoke-PDAJsonScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $Raw = & pwsh -NoProfile -File $Path @Arguments -AsJson 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $Path"
    }

    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Command returned empty output: $Path"
    }

    return $Text | ConvertFrom-Json
}

$Roadmap = Get-Content -Path $RoadmapPath -Raw | ConvertFrom-Json
$Task = @($Roadmap.tasks) | Select-Object -First 1

$Report = [pscustomobject]@{
    status                 = "fail"
    roadmap_exists         = $true
    task_exists            = [bool]$Task
    selected_task_id       = if ($Task) { [string]$Task.id } else { "" }
    selected_task_title    = if ($Task) { [string]$Task.title } else { "" }
    dry_run_default        = $false
    prepare_mode_exists    = $false
    repo_manifest_exists   = $false
    volume_manifest_exists = $false
    work_packet_exists     = $false
    summary_exists         = $false
    proposed_branch_ok     = $false
    required_tests_ok      = $false
    safety_gates_ok        = $false
    output_root            = $TempRoot
    results                = @()
}

$Issues = New-Object System.Collections.Generic.List[string]

if (-not $Task -or [string]$Task.id -ne "task-001") {
    $Issues.Add("Task-001 was not selected as the first roadmap task.")
}

$OrchestratorResult = Invoke-PDAJsonScript -Path $Orchestrator -Arguments @(
    "-Root", $Root,
    "-RoadmapPath", $RoadmapPath,
    "-OutputRoot", $TempRoot
)

function Initialize-PDAPrepareRepo {
    param(
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $true)][string]$SourceRoot
    )

    & git init $DestinationRoot | Out-Null
    & git -C $DestinationRoot config user.name "Codex Test" | Out-Null
    & git -C $DestinationRoot config user.email "codex@example.com" | Out-Null
    & git -C $DestinationRoot commit --allow-empty -m "seed" | Out-Null
    & git -C $DestinationRoot branch -M main | Out-Null

    foreach ($Path in @("Roadmap", "Scripts")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $DestinationRoot $Path) | Out-Null
    }

    foreach ($Path in @(
        "Roadmap\PDA-Roadmap.json",
        "Scripts\Invoke-PDABuildOrchestrator.ps1",
        "Scripts\Start-PDANightlyBuild.ps1",
        "Scripts\Backup-PDARepo.ps1",
        "Scripts\Backup-PDAVolumes.ps1",
        "Scripts\Invoke-PDAQueueBacklogAudit.ps1",
        "Scripts\Test-PDABuildOrchestrator.ps1"
    )) {
        Copy-Item -Force (Join-Path $SourceRoot $Path) (Join-Path $DestinationRoot $Path)
    }

    $ExcludePath = Join-Path $DestinationRoot ".git\info\exclude"
    Add-Content -Path $ExcludePath -Value @(
        "Roadmap/",
        "Scripts/Invoke-PDABuildOrchestrator.ps1",
        "Scripts/Start-PDANightlyBuild.ps1",
        "Scripts/Backup-PDARepo.ps1",
        "Scripts/Backup-PDAVolumes.ps1",
        "Scripts/Invoke-PDAQueueBacklogAudit.ps1",
        "Scripts/Test-PDABuildOrchestrator.ps1"
    )
}

Initialize-PDAPrepareRepo -DestinationRoot $PrepareRepoRoot -SourceRoot $Root

$PrepareOrchestrator = Join-Path $PrepareRepoRoot "Scripts\Invoke-PDABuildOrchestrator.ps1"
$PrepareStart = Join-Path $PrepareRepoRoot "Scripts\Start-PDANightlyBuild.ps1"
$PrepareRoadmap = Join-Path $PrepareRepoRoot "Roadmap\PDA-Roadmap.json"
$QueueAuditResult = Invoke-PDAJsonScript -Path $QueueAuditTest -Arguments @(
    "-NoThrow"
)
$PrepareResult = Invoke-PDAJsonScript -Path $PrepareOrchestrator -Arguments @(
    "-Root", $PrepareRepoRoot,
    "-RoadmapPath", $PrepareRoadmap,
    "-OutputRoot", $TempRoot,
    "-PrepareExecution"
)
$PrepareWrapperResult = Invoke-PDAJsonScript -Path $PrepareStart -Arguments @(
    "-Root", $PrepareRepoRoot,
    "-RoadmapPath", $PrepareRoadmap,
    "-OutputRoot", $TempRoot,
    "-PrepareExecution"
)

$RepoManifestPath = [string]$OrchestratorResult.repo_backup_manifest.manifest_path
$VolumeManifestPath = [string]$OrchestratorResult.volume_backup_manifest.manifest_path
$WorkPacketPath = [string]$OrchestratorResult.work_packet_path
$SummaryPath = [string]$OrchestratorResult.summary_path

if ($OrchestratorResult.mode -ne "dry-run") {
    $Issues.Add("Default orchestrator mode should be dry-run.")
}

if ($QueueAuditResult.status -ne "pass") {
    $Issues.Add("Queue backlog audit validation did not pass.")
}

if ($PrepareResult.mode -ne "prepare") {
    $Issues.Add("Prepare mode did not activate.")
}

if ($PrepareWrapperResult.mode -ne "prepare") {
    $Issues.Add("Prepare wrapper did not activate prepare mode.")
}

if ($OrchestratorResult.selected_task_id -ne "task-001") {
    $Issues.Add("Dry-run orchestrator did not select task-001.")
}

if ($PrepareResult.selected_task_id -ne "task-001") {
    $Issues.Add("Prepare mode did not select task-001.")
}

if (-not ($OrchestratorResult.branch_name -like "codex/nightly-task-001-*")) {
    $Issues.Add("Proposed branch name is not task-001 scoped.")
}

if (-not ($PrepareResult.branch_name -like "codex/nightly-task-001-*")) {
    $Issues.Add("Prepare mode branch name is not task-001 scoped.")
}

if (-not ($OrchestratorResult.next_action -match 'Human review required')) {
    $Issues.Add("Next action does not require human review.")
}

if (-not ($PrepareResult.next_action -match 'Human review required')) {
    $Issues.Add("Prepare mode next action does not require human review.")
}

if (-not ($PrepareWrapperResult.next_action -match 'Human review required')) {
    $Issues.Add("Prepare wrapper next action does not require human review.")
}

if (-not ($OrchestratorResult.repo_backup_manifest.dry_run -eq $true)) {
    $Issues.Add("Repo backup manifest did not report dry-run mode.")
}

if (-not ($PrepareResult.repo_backup_manifest.dry_run -eq $true)) {
    $Issues.Add("Prepare mode repo backup manifest did not report dry-run mode.")
}

if (-not ($PrepareWrapperResult.repo_backup_manifest.dry_run -eq $true)) {
    $Issues.Add("Prepare wrapper repo backup manifest did not report dry-run mode.")
}

if (-not ($OrchestratorResult.volume_backup_manifest.dry_run -eq $true)) {
    $Issues.Add("Volume backup manifest did not report dry-run mode.")
}

if (-not ($PrepareResult.volume_backup_manifest.dry_run -eq $true)) {
    $Issues.Add("Prepare mode volume backup manifest did not report dry-run mode.")
}

if (-not ($PrepareWrapperResult.volume_backup_manifest.dry_run -eq $true)) {
    $Issues.Add("Prepare wrapper volume backup manifest did not report dry-run mode.")
}

if (-not (Test-Path -Path $RepoManifestPath -PathType Leaf)) {
    $Issues.Add("Repo backup manifest was not written.")
}

if (-not (Test-Path -Path $VolumeManifestPath -PathType Leaf)) {
    $Issues.Add("Volume backup manifest was not written.")
}

if (-not (Test-Path -Path $WorkPacketPath -PathType Leaf)) {
    $Issues.Add("Work packet was not written.")
}

if (-not (Test-Path -Path $SummaryPath -PathType Leaf)) {
    $Issues.Add("Summary report was not written.")
}

if (-not [string]::IsNullOrWhiteSpace([string]$OrchestratorResult.audit_report_path)) {
    if (-not (Test-Path -Path $OrchestratorResult.audit_report_path -PathType Leaf)) {
        $Issues.Add("Audit report path from orchestrator was not written.")
    }
}

if (-not ($PrepareResult.branch_creation_status -in @("created", "existing"))) {
    $Issues.Add("Prepare mode did not attempt branch creation.")
}

if (-not ($PrepareWrapperResult.branch_creation_status -in @("created", "existing"))) {
    $Issues.Add("Prepare wrapper did not attempt branch creation.")
}

if ($Task) {
    if (@($Task.required_tests).Count -lt 2) {
        $Issues.Add("Task-001 required tests were not defined.")
    }
    elseif (-not (@($Task.required_tests) -contains "Scripts/Test-PDAStack.ps1 -Deep -NoThrow")) {
        $Issues.Add("Task-001 required tests do not include the deep stack test.")
    }
}

if ($Task) {
    if (@($Task.stop_conditions).Count -lt 1) {
        $Issues.Add("Task-001 stop conditions were not defined.")
    }
}

if ($Task) {
    $AllowedFiles = @($Task.allowed_files)
    if ($AllowedFiles.Count -lt 1) {
        $Issues.Add("Task-001 allowed files were not defined.")
    }
}

$Report.status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
$Report.dry_run_default = ($OrchestratorResult.mode -eq "dry-run")
$Report.prepare_mode_exists = ($PrepareResult.mode -eq "prepare" -and $PrepareWrapperResult.mode -eq "prepare")
$Report.repo_manifest_exists = (Test-Path -Path $RepoManifestPath -PathType Leaf)
$Report.volume_manifest_exists = (Test-Path -Path $VolumeManifestPath -PathType Leaf)
$Report.work_packet_exists = (Test-Path -Path $WorkPacketPath -PathType Leaf)
$Report.summary_exists = (Test-Path -Path $SummaryPath -PathType Leaf)
$Report.proposed_branch_ok = ($OrchestratorResult.branch_name -like "codex/nightly-task-001-*")
$Report.proposed_branch_ok = $Report.proposed_branch_ok -and ($PrepareResult.branch_name -like "codex/nightly-task-001-*") -and ($PrepareWrapperResult.branch_name -like "codex/nightly-task-001-*")
$Report.required_tests_ok = ($Task -and @($Task.required_tests) -contains "Scripts/Test-PDAStack.ps1 -Deep -NoThrow")
$Report.safety_gates_ok = ($OrchestratorResult.safety_gates -contains "Dry-run only" -and $OrchestratorResult.safety_gates -contains "No auto-push" -and $OrchestratorResult.safety_gates -contains "No auto-approval" -and $PrepareResult.safety_gates -contains "Prepare mode allowed" -and $PrepareWrapperResult.safety_gates -contains "Prepare mode allowed")
$Report.results = @(
    [pscustomobject]@{ name = "roadmap"; passed = $Report.roadmap_exists; path = $RoadmapPath }
    [pscustomobject]@{ name = "task-selection"; passed = ($OrchestratorResult.selected_task_id -eq "task-001"); task_id = $OrchestratorResult.selected_task_id }
    [pscustomobject]@{ name = "queue-backlog-audit"; passed = ($QueueAuditResult.status -eq "pass"); path = $QueueAuditResult.report_path }
    [pscustomobject]@{ name = "prepare-selection"; passed = ($PrepareResult.selected_task_id -eq "task-001"); task_id = $PrepareResult.selected_task_id }
    [pscustomobject]@{ name = "prepare-wrapper"; passed = ($PrepareWrapperResult.selected_task_id -eq "task-001"); task_id = $PrepareWrapperResult.selected_task_id }
    [pscustomobject]@{ name = "repo-manifest"; passed = $Report.repo_manifest_exists; path = $RepoManifestPath }
    [pscustomobject]@{ name = "volume-manifest"; passed = $Report.volume_manifest_exists; path = $VolumeManifestPath }
    [pscustomobject]@{ name = "work-packet"; passed = $Report.work_packet_exists; path = $WorkPacketPath }
    [pscustomobject]@{ name = "summary"; passed = $Report.summary_exists; path = $SummaryPath }
)

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA build orchestrator validation failed."
    }
    return
}

Write-Host "[*] PDA build orchestrator tests"
Write-Host ("Status               : {0}" -f $Report.status)
Write-Host ("Roadmap exists       : {0}" -f $Report.roadmap_exists)
Write-Host ("Task selected        : {0}" -f $Report.selected_task_id)
Write-Host ("Repo manifest exists : {0}" -f $Report.repo_manifest_exists)
Write-Host ("Volume manifest exists: {0}" -f $Report.volume_manifest_exists)
Write-Host ("Work packet exists   : {0}" -f $Report.work_packet_exists)
Write-Host ("Summary exists       : {0}" -f $Report.summary_exists)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA build orchestrator validation failed."
}
