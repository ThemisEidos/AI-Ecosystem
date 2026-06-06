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

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PDA_OutputParsing.ps1")
. (Join-Path $PSScriptRoot "PDA_BuildRunner.ps1")

$Orchestrator = Join-Path $PSScriptRoot "Invoke-PDABuildOrchestrator.ps1"
$MonitorScript = Join-Path $PSScriptRoot "Monitor-PDABuildRunner.ps1"
if (-not (Test-Path -LiteralPath $Orchestrator -PathType Leaf)) {
    throw "Build runner orchestrator missing: $Orchestrator"
}
if (-not (Test-Path -LiteralPath $MonitorScript -PathType Leaf)) {
    throw "Build runner monitor missing: $MonitorScript"
}

if ($Monitor) {
    $MonitorArgs = @(
        "-Root", $Root,
        "-RoadmapPath", $RoadmapPath
    )

    if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) {
        $MonitorArgs += @("-LogsRoot", $OutputRoot)
    }
    if (-not [string]::IsNullOrWhiteSpace($CodexExecutable)) {
        $MonitorArgs += @("-CodexExecutable", $CodexExecutable)
    }
    if (-not [string]::IsNullOrWhiteSpace($CodexArguments)) {
        $MonitorArgs += @("-CodexArguments", $CodexArguments)
    }
    if ($AsJson) {
        $MonitorArgs += "-AsJson"
    }

    & pwsh -NoProfile -File $MonitorScript @MonitorArgs
    return
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

    try {
        $Result = ConvertFrom-PDAMixedJson -Text $Text -SourceName $Path
    }
    catch {
        return [pscustomobject]@{
            status      = "fail"
            parse_error = $_.Exception.Message
            raw_output  = $Text
            exit_code   = $LASTEXITCODE
            source_path = $Path
        }
    }
    if ($Result.PSObject.Properties.Name -contains "status" -and [string]$Result.status -eq "fail") {
        throw "Command failed: $Path"
    }
    if ($LASTEXITCODE -ne 0 -and (-not $Result.PSObject.Properties.Name -contains "status" -or [string]$Result.status -ne "pass")) {
        throw "Command failed: $Path"
    }

    return $Result
}

function Test-PDAUnattendedRunPolicy {
    param([Parameter(Mandatory = $true)][object]$Policy)

    $Validation = Test-PDABuildRunnerPolicy -Policy $Policy
    if (-not $Validation.valid) {
        throw ("Invalid unattended policy: " + ($Validation.issues -join "; "))
    }

    foreach ($Key in @("max_tasks_per_run","max_runtime_minutes","stop_on_failed_tests","allowed_file_globs","blocked_file_globs","require_clean_start","branch_prefix","allow_commit_to_branch","allow_push_branch","allow_main_mod","allow_secret_changes")) {
        if (-not ($Policy.PSObject.Properties.Name -contains $Key)) {
            throw "Unattended policy missing key: $Key"
        }
    }

    if (-not [bool]$Policy.stop_on_failed_tests) {
        throw "Unattended policy must stop on failed tests."
    }
    if ([bool]$Policy.allow_main_mod) {
        throw "Unattended policy must not allow main branch modifications."
    }
    if ([bool]$Policy.allow_secret_changes) {
        throw "Unattended policy must not allow secret changes."
    }
}

function Get-PDAUnattendedChangedFiles {
    param([Parameter(Mandatory = $true)][string]$Root)

    $Status = @(& git -C $Root status --porcelain 2>$null)
    $Files = New-Object System.Collections.Generic.List[string]
    foreach ($Line in @($Status)) {
        if ([string]::IsNullOrWhiteSpace([string]$Line)) {
            continue
        }
        $Path = [string]$Line.Substring(3).Trim()
        if ([string]::IsNullOrWhiteSpace($Path)) {
            continue
        }

        if ($Path.StartsWith('"') -and $Path.EndsWith('"') -and $Path.Length -ge 2) {
            $Path = $Path.Substring(1, $Path.Length - 2)
        }

        $FullPath = Join-Path $Root $Path
        if ((Test-Path -LiteralPath $FullPath -PathType Container) -and ($Path.EndsWith("/") -or $Path.EndsWith("\") -or $Path -notmatch '\.[^\\/]+$')) {
            foreach ($Child in @(Get-ChildItem -LiteralPath $FullPath -Recurse -File -Force -ErrorAction SilentlyContinue)) {
                $Relative = [string]($Child.FullName.Substring($Root.Length).TrimStart('\','/'))
                if (-not [string]::IsNullOrWhiteSpace($Relative)) {
                    [void]$Files.Add($Relative)
                }
            }
            continue
        }

        [void]$Files.Add($Path)
    }
    return @($Files)
}

function Test-PDAUnattendedWorktreeDirty {
    param([Parameter(Mandatory = $true)][string]$Root)

    return (@(& git -C $Root status --porcelain 2>$null).Count -gt 0)
}

function Get-PDABuildRunnerExecutionTransitionChain {
    param([Parameter(Mandatory = $true)][string]$CurrentState)

    switch ($CurrentState) {
        "backlog" { return @("eligible", "prepared", "assigned") }
        "eligible" { return @("prepared", "assigned") }
        "prepared" { return @("assigned") }
        "assigned" { return @() }
        default {
            throw "Execution mode cannot advance task state from '$CurrentState'."
        }
    }
}

if ($Unattended) {
    $PolicyPath = Get-PDABuildRunnerPolicyPath -Root $Root
    $Policy = Import-PDABuildRunnerPolicy -Root $Root -PolicyPath $PolicyPath
    Test-PDAUnattendedRunPolicy -Policy $Policy

    $MaxTasksPerRun = if ($PSBoundParameters.ContainsKey("MaxTasks")) { [int]$MaxTasks } else { Get-PDABuildRunnerPolicyNumber -Policy $Policy -Names @("max_tasks_per_run", "MaxTasks") -Default 1 }
    $MaxRuntimeMinutesValue = if ($PSBoundParameters.ContainsKey("MaxRuntimeMinutes")) { [int]$MaxRuntimeMinutes } else { Get-PDABuildRunnerPolicyNumber -Policy $Policy -Names @("max_runtime_minutes", "MaxRuntimeMinutes") -Default 120 }
    $StopOnFailureValue = if ($PSBoundParameters.ContainsKey("StopOnFailure")) { [bool]$StopOnFailure.IsPresent } else { Get-PDABuildRunnerPolicyBoolean -Policy $Policy -Names @("stop_on_failed_tests", "StopOnFailure") -Default $true }
    $RunReportRootValue = if ($PSBoundParameters.ContainsKey("RunReport") -and -not [string]::IsNullOrWhiteSpace($RunReport)) { $RunReport } else { Get-PDABuildRunnerPolicyValue -Policy $Policy -Name "RunReport" -Default "PDA-Backups/build-runner/reports" }
    if ([string]::IsNullOrWhiteSpace([string]$RunReportRootValue)) {
        $RunReportRootValue = "PDA-Backups/build-runner/reports"
    }
    if ([System.IO.Path]::IsPathRooted([string]$RunReportRootValue)) {
        $ReportsRoot = [string]$RunReportRootValue
    }
    else {
        $ReportsRoot = Join-Path $Root ([string]$RunReportRootValue)
    }

    $RunTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $LogsRoot = Join-Path $Root "PDA-Backups\build-runner\logs\$RunTimestamp"
    New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $ReportsRoot | Out-Null

    $CodexResolution = Test-PDABuildRunnerCodexAvailable -ProvidedPath $CodexExecutable
    if ([string]$CodexResolution.status -ne "pass") {
        $Result = [pscustomobject]@{
            status            = "fail"
            mode              = "unattended"
            policy_path       = $PolicyPath
            branch_name       = ""
            logs_root         = $LogsRoot
            report_path       = (Join-Path $ReportsRoot ("unattended-{0}.md" -f $RunTimestamp))
            stop_reason       = "codex_unavailable"
            codex_issue       = [string]$CodexResolution.issue
            codex_candidates  = @($CodexResolution.candidates)
            max_tasks         = $MaxTasksPerRun
            max_runtime_minutes = $MaxRuntimeMinutesValue
            stop_on_failure   = [bool]$StopOnFailureValue
            selected_task_ids = @()
            policy_violation_message = ""
            executed_tasks    = @()
        }

        if ($AsJson) {
            $Result | ConvertTo-Json -Depth 40
        }
        else {
            Write-Host ("[FAIL] PDA Build Runner unattended run stopped: {0}" -f $Result.codex_issue)
        }
        return
    }

    if ($Policy.require_clean_start -and (Test-PDAUnattendedWorktreeDirty -Root $Root)) {
        throw "Dirty worktree detected before unattended run start."
    }

    $RunBranchName = ""
    $CurrentBranch = [string](& git -C $Root branch --show-current 2>$null | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($CurrentBranch)) {
        $CurrentBranch = "(detached)"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Policy.branch_prefix)) {
        $RunBranchName = [string]$Policy.branch_prefix + $RunTimestamp
        if ($CurrentBranch -ne $RunBranchName) {
            & git -C $Root checkout -b $RunBranchName 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                if ($CurrentBranch -eq "main") {
                    throw "Branch creation failed while on main."
                }
                throw "Branch creation failed for unattended run branch: $RunBranchName"
            }
        }
    }

    $RunStarted = Get-Date
    $Iteration = 0
    $ExecutedTasks = New-Object System.Collections.Generic.List[object]
    $StateTransitions = New-Object System.Collections.Generic.List[object]
    $StopReason = ""
    while ($true) {
        if ($Iteration -ge $MaxTasksPerRun) {
            $StopReason = "max_tasks_per_run"
            break
        }

        if (((Get-Date) - $RunStarted).TotalMinutes -ge $MaxRuntimeMinutesValue) {
            $StopReason = "max_runtime_minutes"
            break
        }

        $Roadmap = Import-PDABuildRunnerRoadmap -Root $Root -RoadmapPath $RoadmapPath
        $NextTask = Get-PDABuildRunnerNextEligibleTask -Roadmap $Roadmap
        if (-not $NextTask) {
            $StopReason = "no_eligible_tasks"
            break
        }

        $TaskId = [string]$NextTask.id
        $Iteration++
        $TaskOutputRoot = Join-Path $LogsRoot ("task-{0}-{1}" -f $TaskId, (Get-Date -Format "HHmmss"))
        New-Item -ItemType Directory -Force -Path $TaskOutputRoot | Out-Null

        $RepoBackup = Invoke-PDAJsonScript -Path (Join-Path $PSScriptRoot "Backup-PDARepo.ps1") -Arguments @("-Root", $Root, "-OutputRoot", $TaskOutputRoot, "-DryRun")
        $VolumeBackup = Invoke-PDAJsonScript -Path (Join-Path $PSScriptRoot "Backup-PDAVolumes.ps1") -Arguments @("-Root", $Root, "-OutputRoot", $TaskOutputRoot, "-DryRun")
        if ($RepoBackup.status -ne "pass" -or $VolumeBackup.status -ne "pass") {
            $StopReason = "backup_failure"
            break
        }

        $QueueAudit = Invoke-PDAJsonScript -Path (Join-Path $PSScriptRoot "Invoke-PDAQueueBacklogAudit.ps1") -Arguments @(
            "-Root", $Root,
            "-ReportRoot", (Join-Path $TaskOutputRoot "reports")
        )

        $WorkPacket = Invoke-PDAJsonScript -Path (Join-Path $PSScriptRoot "Generate-PDACodexWorkPacket.ps1") -Arguments @(
            "-Root", $Root,
            "-RoadmapPath", $RoadmapPath,
            "-TaskId", $TaskId,
            "-PacketRoot", (Join-Path $Root "Roadmap\work-packets"),
            "-BranchName", $RunBranchName
        )

        $CodexArgumentsList = @(
            "-Root", $Root,
            "-RoadmapPath", $RoadmapPath,
            "-PacketRoot", (Join-Path $Root "Roadmap\work-packets"),
            "-PromptRoot", (Join-Path $Root "Roadmap\codex-prompts"),
            "-StagingRoot", (Join-Path $Root "PDA-Tasks\staging\nightly-build"),
            "-ExecutionRoot", (Join-Path $Root "PDA-Backups\build-runner\executions"),
            "-TaskId", $TaskId,
            "-CodexExecutable", $(if ([string]::IsNullOrWhiteSpace($CodexExecutable)) { "pwsh.exe" } else { $CodexExecutable })
        )
        if (-not [string]::IsNullOrWhiteSpace($CodexArguments)) {
            $CodexArgumentsList += @("-CodexArguments", $CodexArguments)
        }
        $CodexArgumentsList += @(
            "-RepoBackupManifestPath", [string]$RepoBackup.manifest_path,
            "-VolumeBackupManifestPath", [string]$VolumeBackup.manifest_path,
            "-QueueAuditReportPath", [string]$QueueAudit.report_path
        )

        $TaskState = Invoke-PDAJsonScript -Path (Join-Path $PSScriptRoot "Get-PDABuildRunnerTaskState.ps1") -Arguments @(
            "-Root", $Root,
            "-RoadmapPath", $RoadmapPath,
            "-TaskId", $TaskId
        )
        $CurrentTaskState = [string]$TaskState.task_state.status
        foreach ($TargetState in @(Get-PDABuildRunnerExecutionTransitionChain -CurrentState $CurrentTaskState)) {
            $TransitionResult = Invoke-PDAJsonScript -Path (Join-Path $PSScriptRoot "Update-PDARoadmapStatus.ps1") -Arguments @(
                "-Root", $Root,
                "-RoadmapPath", $RoadmapPath,
                "-TaskId", $TaskId,
                "-ToState", $TargetState,
                "-Actor", "PDA Build Runner",
                "-Reason", "Build runner preparation before Codex execution"
            )
            [void]$StateTransitions.Add($TransitionResult)
            $CurrentTaskState = [string]$TransitionResult.to_state
        }

        $Worker = Invoke-PDAJsonScript -Path (Join-Path $PSScriptRoot "Invoke-PDACodexExecution.ps1") -Arguments $CodexArgumentsList
        [void]$ExecutedTasks.Add($Worker)

        if ($Worker.status -ne "pass") {
            $StopReason = "test_failure"
            if ($StopOnFailureValue) {
                break
            }
        }

        $ChangedFiles = @(Get-PDAUnattendedChangedFiles -Root $Root)
        $ForbiddenChange = $false
        try {
            foreach ($File in $ChangedFiles) {
                if (-not (Test-PDABuildRunnerPolicyAllowsPath -Path $File -Policy $Policy)) {
                    $ForbiddenChange = $true
                    break
                }
            }
        }
        catch {
            $StopReason = "blocked_policy_violation"
            $PolicyViolationMessage = [string]$_.Exception.Message
            break
        }
        if ($ForbiddenChange) {
            $StopReason = "blocked_policy_violation"
            break
        }

        if ($Policy.allow_commit_to_branch) {
            if (($ChangedFiles -contains ".env") -or ($ChangedFiles | Where-Object { $_ -like "*.env" })) {
                throw "Policy blocked secret changes."
            }

            if ($Policy.allow_main_mod -eq $false -and $CurrentBranch -eq "main") {
                throw "Policy blocked main branch modification."
            }

            if ($ChangedFiles.Count -gt 0) {
                & git -C $Root add -- @($ChangedFiles) 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $CommitMessage = if ([string]::IsNullOrWhiteSpace([string]$NextTask.commit_message)) { "feat: unattended build runner task $TaskId" } else { [string]$NextTask.commit_message }
                    & git -C $Root commit -m $CommitMessage 2>$null | Out-Null
                }
            }
        }

        if ($Policy.allow_push_branch) {
            & git -C $Root push -u origin HEAD 2>$null | Out-Null
        }
    }

    $ReportPath = Join-Path $ReportsRoot ("unattended-{0}.md" -f $RunTimestamp)
    $ExecutedTasksArray = @($ExecutedTasks.ToArray())
    $ExecutedTaskCount = $ExecutedTasksArray.Count
    $SelectedTaskIds = @()
    foreach ($TaskRun in $ExecutedTasksArray) {
        $SelectedTaskIds += [string]$TaskRun.selected_task_id
    }
    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add("# PDA Build Runner Unattended Run")
    $Lines.Add("")
    $Lines.Add(("Started at: {0}" -f (Get-Date $RunStarted -Format 'o')))
    $Lines.Add(("Branch: {0}" -f $RunBranchName))
    $Lines.Add(("Policy: {0}" -f $PolicyPath))
    $Lines.Add(("Stop reason: {0}" -f $(if ($StopReason) { $StopReason } else { "completed" })))
    $Lines.Add(("Executed tasks: {0}" -f $ExecutedTaskCount))
    if ($StopReason -eq "backup_failure" -and $QueueAudit) {
        $Lines.Add(("Queue audit: {0}" -f $QueueAudit.report_path))
    }
    $Lines.Add("")
    $Lines.Add("## Task Results")
    foreach ($TaskRun in $ExecutedTasksArray) {
        $Lines.Add(("- {0}: {1}" -f $TaskRun.selected_task_id, $TaskRun.status))
    }
    $Lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

    $Result = [pscustomobject]@{
        status          = if ($StopReason -eq "blocked_policy_violation" -or $StopReason -eq "backup_failure" -or $StopReason -eq "test_failure") { "fail" } else { "pass" }
        mode            = "unattended"
        policy_path     = $PolicyPath
        branch_name     = $RunBranchName
        logs_root       = $LogsRoot
        report_path     = $ReportPath
        stop_reason     = if ($StopReason) { $StopReason } else { "completed" }
        max_tasks       = $MaxTasksPerRun
        max_runtime_minutes = $MaxRuntimeMinutesValue
        stop_on_failure = [bool]$StopOnFailureValue
        selected_task_ids = @($SelectedTaskIds)
        policy_violation_message = $(if ($PolicyViolationMessage) { $PolicyViolationMessage } else { "" })
        executed_tasks  = @($ExecutedTasksArray)
        state_transitions = @($StateTransitions.ToArray())
        codex_status    = [string]$CodexResolution.status
        codex_issue     = if ($CodexResolution.status -ne "pass") { [string]$CodexResolution.issue } else { "" }
    }

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 40
        return
    }

    Write-Host ("[OK] PDA Build Runner unattended run complete: {0}" -f $Result.stop_reason)
    Write-Host ("Report: {0}" -f $ReportPath)
    return
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

if ($Unattended) {
    $Args += "-Unattended"
}

if ($ExportCodexExecutionPrompt) {
    $Args += "-ExportCodexExecutionPrompt"
}

if (-not [string]::IsNullOrWhiteSpace($CodexExecutable)) {
    $Args += @("-CodexExecutable", $CodexExecutable)
}

if (-not [string]::IsNullOrWhiteSpace($CodexArguments)) {
    $Args += @("-CodexArguments", $CodexArguments)
}

if ($AsJson) {
    $Args += "-AsJson"
}

& pwsh -NoProfile -File $Orchestrator @Args
