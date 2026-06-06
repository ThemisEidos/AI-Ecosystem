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
    [string]$CodexExecutable,

    [Parameter(Mandatory = $false)]
    [string]$CodexArguments,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PDA_OutputParsing.ps1")
. (Join-Path $PSScriptRoot "PDA_NightlyAutomation.ps1")
. (Join-Path $PSScriptRoot "PDA_BuildRunner.ps1")

$Mode = if ($ExecuteCodexTask) { "codex" } elseif ($ExecutePreparedTask) { "execute" } elseif ($PrepareExecution) { "prepare" } elseif ($PSBoundParameters.ContainsKey("DryRun")) { if ($DryRun.IsPresent) { "dry-run" } else { "prepare" } } elseif ($NoDryRun) { "prepare" } else { "dry-run" }
if ($Mode -notin @("dry-run", "prepare", "execute", "codex")) {
    throw "Unsupported orchestrator mode: $Mode"
}

if (-not (Test-Path -Path $RoadmapPath -PathType Leaf)) {
    throw "Roadmap not found: $RoadmapPath"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $Root ("PDA-Backups\nightly-build\" + (Get-Date -Format "yyyyMMdd-HHmmss"))
}

$ScriptsRoot = Join-Path $Root "Scripts"
$BuildRunnerHelperScript = Join-Path $ScriptsRoot "PDA_BuildRunner.ps1"
$NightlyHelperScript = Join-Path $ScriptsRoot "PDA_NightlyAutomation.ps1"
$RepoBackupScript = Join-Path $ScriptsRoot "Backup-PDARepo.ps1"
$VolumeBackupScript = Join-Path $ScriptsRoot "Backup-PDAVolumes.ps1"
$QueueAuditScript = Join-Path $ScriptsRoot "Invoke-PDAQueueBacklogAudit.ps1"
$BuildRunnerTaskStateScript = Join-Path $ScriptsRoot "Get-PDABuildRunnerTaskState.ps1"
$NightlyTaskStateScript = Join-Path $ScriptsRoot "Get-PDANightlyTaskState.ps1"
$UpdateRoadmapScript = Join-Path $ScriptsRoot "Update-PDARoadmapStatus.ps1"
$PacketScript = Join-Path $ScriptsRoot "Generate-PDACodexWorkPacket.ps1"
$BuildRunnerReportScript = Join-Path $ScriptsRoot "Generate-PDARunReport.ps1"
$NightlyReportScript = Join-Path $ScriptsRoot "Generate-PDAMorningReport.ps1"
$CodexPromptScript = Join-Path $ScriptsRoot "Export-PDACodexExecutionPrompt.ps1"
$CodexExecutionScript = Join-Path $ScriptsRoot "Invoke-PDACodexExecution.ps1"
$ExecutionStageRoot = Join-Path $Root "PDA-Tasks\staging\nightly-build"
$QueueAuditScriptExists = Test-Path -Path $QueueAuditScript -PathType Leaf
$HelperScriptInUse = if (Test-Path -Path $BuildRunnerHelperScript -PathType Leaf) { $BuildRunnerHelperScript } else { $NightlyHelperScript }
$TaskStateScript = if (Test-Path -Path $BuildRunnerTaskStateScript -PathType Leaf) { $BuildRunnerTaskStateScript } else { $NightlyTaskStateScript }
$MorningReportScript = if (Test-Path -Path $BuildRunnerReportScript -PathType Leaf) { $BuildRunnerReportScript } else { $NightlyReportScript }
$RequiredScripts = @(
    $HelperScriptInUse,
    $RepoBackupScript,
    $VolumeBackupScript,
    $QueueAuditScript,
    $TaskStateScript,
    $UpdateRoadmapScript,
    $PacketScript,
    $MorningReportScript,
    $CodexPromptScript,
    $CodexExecutionScript
)
foreach ($RequiredScript in $RequiredScripts) {
    if (-not (Test-Path -Path $RequiredScript -PathType Leaf)) {
        throw "Build runner script not found: $RequiredScript"
    }
}
$NightlyDir = $OutputRoot
New-Item -ItemType Directory -Force -Path $NightlyDir | Out-Null

function Invoke-PDAGit {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    return @(& git -C $Root @Arguments 2>$null)
}

function Test-PDAWorktreeDirty {
    $Status = @(& git -C $Root status --porcelain 2>$null)
    return (@($Status).Count -gt 0)
}

function Get-PDARoadmap {
    param([string]$Path)
    return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
}

function Test-PDATaskDependenciesSatisfied {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)]$Roadmap
    )

    $Dependencies = @($Task.dependencies) | ForEach-Object { [string]$_ }
    if ($Dependencies.Count -eq 0) {
        return $true
    }

    $Completed = @($Roadmap.completed_task_ids) | ForEach-Object { [string]$_ }
    foreach ($Dependency in $Dependencies) {
        if ($Completed -notcontains $Dependency) {
            return $false
        }
    }

    return $true
}

function Get-PDANextEligibleTask {
    param([Parameter(Mandatory = $true)]$Roadmap)

    $EligibleStatuses = @("backlog", "eligible")
    foreach ($Task in @($Roadmap.tasks)) {
        if ($EligibleStatuses -contains [string]$Task.status -and (Test-PDATaskDependenciesSatisfied -Task $Task -Roadmap $Roadmap)) {
            return $Task
        }
    }

    return $null
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
    if ($Result.PSObject.Properties.Name -contains "status" -and [string]$Result.status -eq "fail") {
        throw "Command failed: $Path"
    }
    if ($LASTEXITCODE -ne 0 -and (-not $Result.PSObject.Properties.Name -contains "status" -or [string]$Result.status -ne "pass")) {
        throw "Command failed: $Path"
    }

    return $Result
}

$Roadmap = Get-PDARoadmap -Path $RoadmapPath
$SelectedTask = if ($Mode -in @("execute", "codex")) {
    Get-PDANightlyTask -Roadmap $Roadmap -TaskId ([string]$Roadmap.current_task_id)
}
else {
    Get-PDANextEligibleTask -Roadmap $Roadmap
}

if ($Mode -in @("prepare", "execute", "codex") -and (Test-PDAWorktreeDirty)) {
    throw "Dirty worktree detected before orchestrator start."
}

$SelectedTaskId = if ($SelectedTask) { [string]$SelectedTask.id } else { "" }
$SelectedTaskTitle = if ($SelectedTask) { [string]$SelectedTask.title } else { "" }
$SelectedTaskObjective = if ($SelectedTask) { [string]$SelectedTask.objective } else { "" }
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BranchName = if ($SelectedTaskId) { "codex/nightly-$($SelectedTaskId)-$Timestamp" } else { "codex/nightly-idle-$Timestamp" }

$CurrentBranch = [string]((& git -C $Root branch --show-current 2>$null | Select-Object -First 1))
$BranchCreationStatus = "not_attempted"
$BranchCreationMessage = ""
if ($Mode -in @("prepare", "execute", "codex")) {
    if ([string]::IsNullOrWhiteSpace($CurrentBranch)) {
        $CurrentBranch = "(detached)"
    }

    $BranchExists = $false
    & git -C $Root rev-parse --verify --quiet $BranchName 2>$null | Out-Null
    $BranchExists = ($LASTEXITCODE -eq 0)

    if ($BranchExists) {
        $BranchCreationStatus = "existing"
        $BranchCreationMessage = "Branch already exists; no checkout needed."
    }
    else {
        $CheckoutArgs = @("checkout", "-b", $BranchName)
        $CheckoutOutput = Invoke-PDAGit -Arguments $CheckoutArgs
        if ($LASTEXITCODE -ne 0) {
            if ($CurrentBranch -eq "main") {
                throw "Branch creation failed while on main."
            }
            throw "Branch creation failed: $($CheckoutOutput -join ' ')"
        }

        $BranchCreationStatus = "created"
        $BranchCreationMessage = "Checked out new task branch."
    }
}

$RepoBackup = Invoke-PDAJsonScript -Path $RepoBackupScript -Arguments @(
    "-Root", $Root,
    "-OutputRoot", $NightlyDir,
    "-DryRun"
)

$VolumeBackup = Invoke-PDAJsonScript -Path $VolumeBackupScript -Arguments @(
    "-Root", $Root,
    "-OutputRoot", $NightlyDir,
    "-DryRun"
)

$QueueBacklogAudit = Invoke-PDAJsonScript -Path $QueueAuditScript -Arguments @(
    "-Root", $Root,
    "-ReportRoot", (Join-Path $NightlyDir "reports")
)

$TaskStatePreview = Invoke-PDAJsonScript -Path $TaskStateScript -Arguments @(
    "-Root", $Root,
    "-RoadmapPath", $RoadmapPath,
    "-TaskId", $SelectedTaskId
)

$CurrentState = [string]$TaskStatePreview.task_state.status
$StateUpdate = $null
$TransitionResults = @()
$ExecutionSummary = $null
$ExecutionSummaryPath = ""
$ExecutionSummaryMarkdownPath = ""
$PacketResult = $null
if ($Mode -eq "codex") {
    $PacketLookup = Find-PDANightlyWorkPacket -Root $Root -TaskId $SelectedTaskId -PacketRoot (Join-Path $Root "Roadmap\work-packets")
    if ($PacketLookup) {
        $PacketResult = [pscustomobject]@{
            status        = "pass"
            task_id       = $SelectedTaskId
            packet_root   = (Join-Path $Root "Roadmap\work-packets")
            json_path     = $PacketLookup.json_path
            markdown_path = $PacketLookup.markdown_path
            packet        = $PacketLookup.packet
        }
    }
    else {
        $PacketResult = Invoke-PDAJsonScript -Path $PacketScript -Arguments @(
            "-Root", $Root,
            "-RoadmapPath", $RoadmapPath,
            "-TaskId", $SelectedTaskId,
            "-PacketRoot", (Join-Path $Root "Roadmap\work-packets"),
            "-BranchName", $BranchName
        )
    }
}
elseif ($Mode -eq "execute") {
    $PacketLookup = Find-PDANightlyWorkPacket -Root $Root -TaskId $SelectedTaskId -PacketRoot (Join-Path $Root "Roadmap\work-packets")
    if ($PacketLookup) {
        $PacketResult = [pscustomobject]@{
            status        = "pass"
            task_id       = $SelectedTaskId
            packet_root   = (Join-Path $Root "Roadmap\work-packets")
            json_path     = $PacketLookup.json_path
            markdown_path = $PacketLookup.markdown_path
            packet        = $PacketLookup.packet
        }
    }
    else {
        $PacketResult = Invoke-PDAJsonScript -Path $PacketScript -Arguments @(
            "-Root", $Root,
            "-RoadmapPath", $RoadmapPath,
            "-TaskId", $SelectedTaskId,
            "-PacketRoot", (Join-Path $Root "Roadmap\work-packets"),
            "-BranchName", $BranchName
        )
    }

    $TransitionChain = @(Get-PDANightlyExecutionTransitionChain -CurrentState $CurrentState)
    foreach ($NextState in $TransitionChain) {
        $TransitionResult = Invoke-PDAJsonScript -Path $UpdateRoadmapScript -Arguments @(
            "-Root", $Root,
            "-RoadmapPath", $RoadmapPath,
            "-TaskId", $SelectedTaskId,
            "-ToState", $NextState,
            "-Actor", "PDA Build Orchestrator",
            "-Reason", "Human-approved build runner execution"
        )
        $TransitionResults += $TransitionResult
    }

    $TaskState = Invoke-PDAJsonScript -Path $TaskStateScript -Arguments @(
        "-Root", $Root,
        "-RoadmapPath", $RoadmapPath,
        "-TaskId", $SelectedTaskId
    )

    $ExecutionSummary = New-PDANightlyExecutionSummaryObject -Roadmap (Get-PDARoadmap -Path $RoadmapPath) -Task $SelectedTask -WorkPacket $PacketResult -BranchName $BranchName -CurrentState $CurrentState -FinalState ([string]$TaskState.task_state.status) -TransitionChain $TransitionChain -BackupManifests @([string]$RepoBackup.manifest_path, [string]$VolumeBackup.manifest_path, [string]$QueueBacklogAudit.report_path) -TestsRequired @(@($SelectedTask.required_tests) | ForEach-Object { [string]$_ })
    $ExecutionSummarySaved = Save-PDANightlyExecutionSummary -Summary $ExecutionSummary -OutputRoot $ExecutionStageRoot
    $ExecutionSummaryPath = $ExecutionSummarySaved.json_path
    $ExecutionSummaryMarkdownPath = $ExecutionSummarySaved.markdown_path
}
elseif ($Mode -eq "codex") {
    $CodexExecutionArguments = @(
        "-Root", $Root,
        "-RoadmapPath", $RoadmapPath,
        "-PacketRoot", (Join-Path $Root "Roadmap\work-packets"),
        "-PromptRoot", (Join-Path $Root "Roadmap\codex-prompts"),
        "-StagingRoot", $ExecutionStageRoot,
        "-ExecutionRoot", (Join-Path $Root "PDA-Backups\build-runner\executions"),
        "-TaskId", $SelectedTaskId
    )
    $CodexExecutionArguments += @(
        "-RepoBackupManifestPath", [string]$RepoBackup.manifest_path,
        "-VolumeBackupManifestPath", [string]$VolumeBackup.manifest_path,
        "-QueueAuditReportPath", [string]$QueueBacklogAudit.report_path
    )
    if (-not [string]::IsNullOrWhiteSpace($CodexExecutable)) {
        $CodexExecutionArguments += @("-CodexExecutable", $CodexExecutable)
    }
    if (-not [string]::IsNullOrWhiteSpace($CodexArguments)) {
        $CodexExecutionArguments += @("-CodexArguments", $CodexArguments)
    }

    $CodexExecution = Invoke-PDAJsonScript -Path $CodexExecutionScript -Arguments $CodexExecutionArguments

    $TransitionResults = @()
    foreach ($StateName in @($CodexExecution.preparation_transition_chain)) {
        $TransitionResults += [pscustomobject]@{ to_state = [string]$StateName }
    }
    foreach ($StateName in @($CodexExecution.execution_transition_chain)) {
        $TransitionResults += [pscustomobject]@{ to_state = [string]$StateName }
    }

    $TaskState = Invoke-PDAJsonScript -Path $TaskStateScript -Arguments @(
        "-Root", $Root,
        "-RoadmapPath", $RoadmapPath,
        "-TaskId", $SelectedTaskId
    )

    $StateUpdate = [pscustomobject]@{
        status           = "pass"
        task_id          = $SelectedTaskId
        from_state       = [string]$CodexExecution.state_before
        to_state         = [string]$CodexExecution.state_after
        updated          = $true
        roadmap          = $TaskState
        transition_chain = @($TransitionResults | ForEach-Object { $_.to_state })
    }

    $ExecutionSummaryPath = [string]$CodexExecution.summary_json_path
    $ExecutionSummaryMarkdownPath = [string]$CodexExecution.summary_markdown_path
    $CodexPrompt = [pscustomobject]@{
        json_path     = [string]$CodexExecution.source_prompt_json_path
        markdown_path = [string]$CodexExecution.source_prompt_markdown_path
    }
    $CodexPromptPath = [string]$CodexPrompt.json_path
    $CodexPromptMarkdownPath = [string]$CodexPrompt.markdown_path
    $BackupManifests = @([string]$RepoBackup.manifest_path, [string]$VolumeBackup.manifest_path, [string]$QueueBacklogAudit.report_path)
    $RequiredTests = @($CodexExecution.tests_executed) | ForEach-Object { [string]$_ }
    $GeneratedReports = @(
        [string]$PacketResult.markdown_path,
        [string]$QueueBacklogAudit.report_path,
        [string]$ExecutionSummaryMarkdownPath,
        [string]$CodexPrompt.json_path,
        [string]$CodexPrompt.markdown_path
    )
}
else {
    $TargetState = switch ($CurrentState) {
        "backlog" { "eligible" }
        "eligible" { "prepared" }
        "prepared" { "assigned" }
        "assigned" { "in_progress" }
        "in_progress" { "testing" }
        "testing" { "ready_for_review" }
        "ready_for_review" { "completed" }
        default { $CurrentState }
    }

    $StateUpdate = if ($TargetState -eq $CurrentState) {
        [pscustomobject]@{
            status     = "pass"
            task_id    = $SelectedTaskId
            from_state = $CurrentState
            to_state   = $CurrentState
            updated    = $false
            roadmap    = $TaskStatePreview
        }
    }
    else {
        $UpdateArguments = @(
            "-Root", $Root,
            "-RoadmapPath", $RoadmapPath,
            "-TaskId", $SelectedTaskId,
            "-ToState", $TargetState,
            "-Actor", "PDA Build Orchestrator",
            "-Reason", "Build runner packet generation"
        )
        if ($Mode -eq "dry-run") {
            $UpdateArguments += "-NoWrite"
        }

        Invoke-PDAJsonScript -Path $UpdateRoadmapScript -Arguments $UpdateArguments
    }
    $TaskState = Invoke-PDAJsonScript -Path $TaskStateScript -Arguments @(
        "-Root", $Root,
        "-RoadmapPath", $RoadmapPath,
        "-TaskId", $SelectedTaskId
    )

    $PacketResult = Invoke-PDAJsonScript -Path $PacketScript -Arguments @(
        "-Root", $Root,
        "-RoadmapPath", $RoadmapPath,
        "-TaskId", $SelectedTaskId,
        "-PacketRoot", (Join-Path $Root "Roadmap\work-packets"),
        "-BranchName", $BranchName
    )
}

if ($Mode -eq "execute") {
    $StateUpdate = [pscustomobject]@{
        status          = "pass"
        task_id         = $SelectedTaskId
        from_state      = $CurrentState
        to_state        = [string]$TaskState.task_state.status
        updated         = ($TransitionResults.Count -gt 0)
        roadmap         = $TaskState
        transition_chain = @($TransitionResults | ForEach-Object { $_.to_state })
    }
}

$BackupManifests = @(
    [string]$RepoBackup.manifest_path
    [string]$VolumeBackup.manifest_path
    [string]$QueueBacklogAudit.report_path
)
$RequiredTests = @(@($SelectedTask.required_tests) | ForEach-Object { [string]$_ })
$GeneratedReports = @(
    [string]$PacketResult.markdown_path
    [string]$QueueBacklogAudit.report_path
)
if ($ExecutionSummaryMarkdownPath) {
    $GeneratedReports += [string]$ExecutionSummaryMarkdownPath
}
if (-not [string]::IsNullOrWhiteSpace([string]$CodexPromptPath)) {
    $GeneratedReports += [string]$CodexPromptPath
}
if (-not [string]::IsNullOrWhiteSpace([string]$CodexPromptMarkdownPath)) {
    $GeneratedReports += [string]$CodexPromptMarkdownPath
}

    $MorningReport = Invoke-PDAJsonScript -Path $MorningReportScript -Arguments @(
        "-Root", $Root,
        "-RoadmapPath", $RoadmapPath,
        "-TaskId", $SelectedTaskId,
    "-BranchName", $BranchName,
    "-BackupManifests", ($BackupManifests -join '|'),
    "-TestsExecuted", ($RequiredTests -join '|'),
    "-GeneratedReports", ($GeneratedReports -join '|'),
    "-OutputRoot", (Join-Path $NightlyDir "reports")
    )
    $MorningReportPath = [string]$MorningReport.report_path

    if (-not $CodexPrompt) {
        $CodexPrompt = $null
    }
    if ($ExportCodexExecutionPrompt -and -not $CodexPrompt) {
        if (-not (Test-Path -Path $CodexPromptScript -PathType Leaf)) {
            throw "Codex execution prompt exporter not found: $CodexPromptScript"
        }

        $CodexPrompt = Invoke-PDAJsonScript -Path $CodexPromptScript -Arguments @(
            "-Root", $Root,
            "-RoadmapPath", $RoadmapPath,
            "-PacketRoot", (Join-Path $Root "Roadmap\work-packets"),
            "-StagingRoot", $ExecutionStageRoot,
            "-PromptRoot", (Join-Path $Root "Roadmap\codex-prompts"),
            "-TaskId", $SelectedTaskId
        )
    }

    $WorkPacketPath = [string]$PacketResult.json_path
    $WorkPacketMarkdownPath = [string]$PacketResult.markdown_path
    $CodexPromptPath = if ($CodexPrompt) { [string]$CodexPrompt.json_path } else { "" }
    $CodexPromptMarkdownPath = if ($CodexPrompt) { [string]$CodexPrompt.markdown_path } else { "" }
    $SummaryPath = Join-Path $NightlyDir "summary.md"
$SummaryLines = @(
    "# PDA Build Runner Summary"
    ""
    "- Mode: $Mode"
    "- Roadmap: $RoadmapPath"
    "- Selected task: $(if ($SelectedTaskId) { "$SelectedTaskId - $SelectedTaskTitle" } else { '(none)' })"
    "- Branch: $BranchName"
    "- State transition: $($StateUpdate.from_state) -> $($StateUpdate.to_state)"
    "- Repo backup manifest: $($RepoBackup.manifest_path)"
    "- Volume backup manifest: $($VolumeBackup.manifest_path)"
    "- Backlog audit report: $($QueueBacklogAudit.report_path)"
    "- Work packet JSON: $WorkPacketPath"
    "- Work packet markdown: $WorkPacketMarkdownPath"
    "- Execution summary: $(if ($ExecutionSummaryPath) { $ExecutionSummaryPath } else { '(none)' })"
    "- Codex prompt JSON: $(if ($CodexPromptPath) { $CodexPromptPath } else { '(none)' })"
    "- Codex prompt markdown: $(if ($CodexPromptMarkdownPath) { $CodexPromptMarkdownPath } else { '(none)' })"
    "- Morning report: $MorningReportPath"
    "- Next action: $(if ($Mode -eq 'prepare') { 'Human review required before commit, push, or task execution.' } elseif ($Mode -eq 'execute') { 'Human review required before Codex execution.' } elseif ($Mode -eq 'codex') { 'Human review required before merge or promotion.' } else { 'Human review required before branch creation or execution.' })"
)
$SummaryLines | Set-Content -Path $SummaryPath -Encoding UTF8

$ResolvedTaskState = $TaskState
if (-not $ResolvedTaskState -and $Mode -eq "codex") {
    $ResolvedTaskState = Get-PDABuildRunnerTaskState -Roadmap (Import-PDABuildRunnerRoadmap -Root $Root -RoadmapPath $RoadmapPath) -TaskId $SelectedTaskId
}

$ResolvedStateUpdate = $StateUpdate
if (-not $ResolvedStateUpdate -and $Mode -eq "codex" -and $CodexExecution) {
    $ResolvedExecutionTransitionChain = @(
        @($CodexExecution.preparation_transition_chain)
        @($CodexExecution.execution_transition_chain)
    ) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $ResolvedStateUpdate = [pscustomobject]@{
        status           = "pass"
        task_id          = $SelectedTaskId
        from_state       = [string]$CodexExecution.state_before
        to_state         = [string]$CodexExecution.state_after
        updated          = $true
        roadmap          = $ResolvedTaskState
        transition_chain = $ResolvedExecutionTransitionChain
    }
}

$ResolvedExecutionSummaryPath = if (-not [string]::IsNullOrWhiteSpace($ExecutionSummaryPath)) { [string]$ExecutionSummaryPath } elseif ($Mode -eq "codex" -and $CodexExecution) { [string]$CodexExecution.summary_json_path } else { "" }
$ResolvedExecutionSummaryMarkdownPath = if (-not [string]::IsNullOrWhiteSpace($ExecutionSummaryMarkdownPath)) { [string]$ExecutionSummaryMarkdownPath } elseif ($Mode -eq "codex" -and $CodexExecution) { [string]$CodexExecution.summary_markdown_path } else { "" }
$ResolvedCodexPromptPath = if (-not [string]::IsNullOrWhiteSpace($CodexPromptPath)) { [string]$CodexPromptPath } elseif ($Mode -eq "codex" -and $CodexExecution) { [string]$CodexExecution.source_prompt_json_path } else { "" }
$ResolvedCodexPromptMarkdownPath = if (-not [string]::IsNullOrWhiteSpace($CodexPromptMarkdownPath)) { [string]$CodexPromptMarkdownPath } elseif ($Mode -eq "codex" -and $CodexExecution) { [string]$CodexExecution.source_prompt_markdown_path } else { "" }
$ResolvedMorningReportPath = if (-not [string]::IsNullOrWhiteSpace($MorningReportPath)) { [string]$MorningReportPath } elseif ($MorningReport -and $MorningReport.PSObject.Properties.Name -contains "report_path") { [string]$MorningReport.report_path } else { "" }
$ResolvedExecutionTransitionChain = if ($TransitionResults) {
    @($TransitionResults | ForEach-Object { [string]$_.to_state })
}
elseif ($Mode -eq "codex" -and $CodexExecution) {
    @(
        @($CodexExecution.preparation_transition_chain)
        @($CodexExecution.execution_transition_chain)
    ) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}
else {
    @()
}
$ResolvedExecutionTransitionCount = if ($TransitionResults) {
    @($TransitionResults).Count
}
elseif ($Mode -eq "codex" -and $CodexExecution) {
    @($ResolvedExecutionTransitionChain).Count
}
else {
    0
}

$Result = [pscustomobject]@{
    status                  = "pass"
    mode                    = $Mode
    roadmap_path            = $RoadmapPath
    roadmap_name            = [string]$Roadmap.roadmap_name
    selected_task           = $SelectedTask
    selected_task_id        = $SelectedTaskId
    selected_task_title     = $SelectedTaskTitle
    branch_name             = $BranchName
    current_branch          = $CurrentBranch
    branch_creation_status  = $BranchCreationStatus
    branch_creation_message = $BranchCreationMessage
    repo_backup_manifest    = $RepoBackup
    volume_backup_manifest  = $VolumeBackup
    queue_backlog_audit     = $QueueBacklogAudit
    task_state              = $ResolvedTaskState
    task_state_transition   = $ResolvedStateUpdate
    execution_transition_chain = $ResolvedExecutionTransitionChain
    execution_transition_count = $ResolvedExecutionTransitionCount
    work_packet_path        = $WorkPacketPath
    work_packet_markdown_path = $WorkPacketMarkdownPath
    execution_summary_path  = $ResolvedExecutionSummaryPath
    execution_summary_markdown_path = $ResolvedExecutionSummaryMarkdownPath
    codex_prompt_path       = $ResolvedCodexPromptPath
    codex_prompt_markdown_path = $ResolvedCodexPromptMarkdownPath
    morning_report_path     = $ResolvedMorningReportPath
    summary_path            = $SummaryPath
    audit_report_path       = $QueueBacklogAudit.report_path
    next_action             = if ($Mode -eq "prepare") { "Human review required before commit, push, or task execution." } elseif ($Mode -eq "execute") { "Human review required before Codex execution." } elseif ($Mode -eq "codex") { "Human review required before merge or promotion." } else { "Human review required before branch creation or execution." }
    safety_gates            = @(
        "Dry-run only",
        "Prepare mode allowed",
        "Human-approved execution allowed",
        "No secrets",
        "No auto-approval",
        "No auto-push",
        "No queue deletion"
    )
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 30
    return
}

Write-Host ("[OK] PDA build runner orchestrator {0} complete." -f $Mode)
Write-Host ("Selected task   : {0}" -f $(if ($SelectedTaskId) { "$SelectedTaskId - $SelectedTaskTitle" } else { "(none)" }))
Write-Host ("Current branch  : {0}" -f $CurrentBranch)
Write-Host ("Branch          : {0}" -f $BranchName)
if ($BranchCreationMessage) {
    Write-Host ("Branch status   : {0}" -f $BranchCreationMessage)
}
Write-Host ("Task state      : {0} -> {1}" -f $StateUpdate.from_state, $StateUpdate.to_state)
Write-Host ("Work packet     : {0}" -f $WorkPacketPath)
if ($ExecutionSummaryPath) {
    Write-Host ("Execution summary: {0}" -f $ExecutionSummaryPath)
}
Write-Host ("Morning report  : {0}" -f $MorningReportPath)
Write-Host ("Summary         : {0}" -f $SummaryPath)
Write-Host ("Repo manifest   : {0}" -f $RepoBackup.manifest_path)
Write-Host ("Volume manifest : {0}" -f $VolumeBackup.manifest_path)
