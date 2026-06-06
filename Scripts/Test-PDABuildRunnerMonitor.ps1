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
$MonitorScript = Join-Path $PSScriptRoot "Monitor-PDABuildRunner.ps1"
$ExecutionScript = Join-Path $PSScriptRoot "Invoke-PDACodexExecution.ps1"
$WorkPacketScript = Join-Path $PSScriptRoot "Generate-PDACodexWorkPacket.ps1"
$StackScript = Join-Path $PSScriptRoot "Test-PDAStack.ps1"
$RoadmapScript = Join-Path $Root "Roadmap\PDA-Roadmap.json"
$PolicyScript = Join-Path $Root "Roadmap\PDA-BuildRunnerPolicy.json"

foreach ($Path in @($MonitorScript, $ExecutionScript, $WorkPacketScript, $StackScript, $RoadmapScript, $PolicyScript)) {
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

    try {
        return (ConvertFrom-PDAMixedJson -Text $Text -SourceName $Path)
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
}

function Initialize-PDATempRepo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot,

        [Parameter(Mandatory = $true)]
        [string]$SourceRoot
    )

    New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null
    foreach ($Folder in @("Roadmap", "Scripts", "PDA-Backups\build-runner\executions", "PDA-Backups\build-runner\logs", "PDA-Tasks\staging\nightly-build", "Obsidian Vault\02_Projects\AI Tool Ecosystem")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $DestinationRoot $Folder) | Out-Null
    }

    & git init $DestinationRoot | Out-Null
    & git -C $DestinationRoot config user.name "Codex Test" | Out-Null
    & git -C $DestinationRoot config user.email "codex@example.com" | Out-Null
    & git -C $DestinationRoot commit --allow-empty -m "seed" | Out-Null
    & git -C $DestinationRoot branch -M main | Out-Null

    $TrackedFiles = @(
        "Roadmap\PDA-Roadmap.json",
        "Roadmap\PDA-BuildRunnerPolicy.json",
        "Scripts\PDA_OutputParsing.ps1",
        "Scripts\PDA_NightlyAutomation.ps1",
        "Scripts\PDA_BuildRunner.ps1",
        "Scripts\Monitor-PDABuildRunner.ps1",
        "Scripts\Invoke-PDACodexExecution.ps1",
        "Scripts\Generate-PDACodexWorkPacket.ps1",
        "Scripts\Export-PDACodexExecutionPrompt.ps1",
        "Scripts\Generate-PDARunReport.ps1",
        "Scripts\Update-PDARoadmapStatus.ps1",
        "Scripts\Get-PDABuildRunnerTaskState.ps1",
        "Scripts\Get-PDADashboardStatus.ps1",
        "Scripts\Update-PDADashboard.ps1",
        "Scripts\Test-PDADashboardRefresh.ps1",
        "Scripts\Test-PDAStack.ps1",
        "Scripts\Backup-PDARepo.ps1",
        "Scripts\Backup-PDAVolumes.ps1",
        "Scripts\Invoke-PDABuildRunner.ps1",
        "Scripts\Start-PDABuildRunner.ps1",
        "Obsidian Vault\02_Projects\AI Tool Ecosystem\PDA Dashboard.md"
    )

    foreach ($Path in $TrackedFiles) {
        Copy-Item -Force (Join-Path $SourceRoot $Path) (Join-Path $DestinationRoot $Path)
    }

    $ExcludePath = Join-Path $DestinationRoot ".git\info\exclude"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ExcludePath) | Out-Null
    @(
        "Roadmap/",
        "Roadmap/work-packets/",
        "Roadmap/codex-prompts/",
        "Obsidian Vault/",
        "PDA-Tasks/",
        "PDA-Backups/",
        "Scripts/PDA_OutputParsing.ps1",
        "Scripts/PDA_NightlyAutomation.ps1",
        "Scripts/PDA_BuildRunner.ps1",
        "Scripts/Monitor-PDABuildRunner.ps1",
        "Scripts/Invoke-PDACodexExecution.ps1",
        "Scripts/Generate-PDACodexWorkPacket.ps1",
        "Scripts/Export-PDACodexExecutionPrompt.ps1",
        "Scripts/Generate-PDARunReport.ps1",
        "Scripts/Update-PDARoadmapStatus.ps1",
        "Scripts/Get-PDABuildRunnerTaskState.ps1",
        "Scripts/Get-PDADashboardStatus.ps1",
        "Scripts/Update-PDADashboard.ps1",
        "Scripts/Test-PDADashboardRefresh.ps1",
        "Scripts/Test-PDAStack.ps1",
        "Scripts/Backup-PDARepo.ps1",
        "Scripts/Backup-PDAVolumes.ps1",
        "Scripts/Invoke-PDABuildRunner.ps1",
        "Scripts/Start-PDABuildRunner.ps1",
        "Obsidian Vault\02_Projects\AI Tool Ecosystem\PDA Dashboard.md"
    ) | Add-Content -Path $ExcludePath
}

function New-FakeCodexScript {
    param([Parameter(Mandatory = $true)][string]$Path)

@'
param()
$Prompt = [Console]::In.ReadToEnd()
[Console]::Out.WriteLine("`e[33mFAKE CODEX START`e[0m")
[Console]::Out.WriteLine("mixed output before json")
[Console]::Out.WriteLine("{""status"":""pass"",""mode"":""fake-codex"",""prompt_length"":$($Prompt.Length)}")
[Console]::Error.WriteLine("fake codex stderr diagnostic")
exit 0
'@ | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Update-TempRoadmapForMonitor {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $Roadmap = Get-Content -LiteralPath $SourcePath -Raw | ConvertFrom-Json -ErrorAction Stop
    $Task = @($Roadmap.tasks | Where-Object { [string]$_.id -eq "task-001" } | Select-Object -First 1)[0]
    if (-not $Task) {
        throw "Roadmap must include task-001."
    }

    $Task.status = "testing"
    $Task.required_tests = @("Scripts/Test-PDAStack.ps1 -NoThrow")
    $Roadmap.current_task_id = "task-001"
    $Roadmap.completed_task_ids = @()
    $Roadmap.task_state_history = @()
    $Roadmap.last_updated = (Get-Date).ToUniversalTime().ToString("o")
    $Roadmap | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $TargetPath -Encoding UTF8
}

function Update-TempPolicyForMonitor {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $Policy = Get-Content -LiteralPath $SourcePath -Raw | ConvertFrom-Json -ErrorAction Stop
    $Policy.max_retries_per_task = 2
    $Policy.monitor_interval_seconds = 1
    $Policy.stalled_run_timeout_minutes = 1
    $Policy.require_clean_start = $true
    $Policy.allow_commit_to_branch = $false
    $Policy.allow_push_branch = $false
    $Policy.allow_main_mod = $false
    $Policy.allow_secret_changes = $false
    $Policy | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $TargetPath -Encoding UTF8
}

function New-FailedExecutionRecord {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$WorkPacketJsonPath,
        [Parameter(Mandatory = $true)][string]$WorkPacketMarkdownPath
    )

    $Timestamp = "20260101-010101"
    $ExecutionRoot = Join-Path $RepoRoot "PDA-Backups\build-runner\executions\$TaskId-$Timestamp"
    $SummaryRoot = Join-Path $RepoRoot "PDA-Tasks\staging\nightly-build\$TaskId-$Timestamp"
    New-Item -ItemType Directory -Force -Path $ExecutionRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $SummaryRoot | Out-Null

    Set-Content -LiteralPath (Join-Path $ExecutionRoot "codex.stdout.log") -Value "failure: simulated codex crash" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $ExecutionRoot "codex.stderr.log") -Value "fatal: simulated error" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $ExecutionRoot "codex.command.json") -Value (@{
        executable = "pwsh.exe"
        arguments = @("-File","fake-codex.ps1")
        exit_code = 1
    } | ConvertTo-Json -Depth 10) -Encoding UTF8

    $Summary = [pscustomobject]@{
        schema_version = "1.0"
        artifact_type = "pda_build_runner_codex_execution_summary"
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        task_id = $TaskId
        title = "Audit queue and approval backlog"
        objective = "Restore dashboard health to green."
        branch_name = "codex/build-runner/monitor-test"
        source_summary_path = (Join-Path $SummaryRoot "handoff-summary.json")
        source_prompt_json_path = (Join-Path $RepoRoot "Roadmap\codex-prompts\$TaskId-20260101-010101.json")
        source_prompt_markdown_path = (Join-Path $RepoRoot "Roadmap\codex-prompts\$TaskId-20260101-010101.md")
        work_packet_json_path = $WorkPacketJsonPath
        work_packet_markdown_path = $WorkPacketMarkdownPath
        state_before = "testing"
        state_after = "testing"
        preparation_transition_chain = @()
        execution_transition_chain = @()
        codex_executable = "pwsh.exe"
        codex_arguments = @("-File","fake-codex.ps1")
        codex_exit_code = 1
        codex_stdout_log_path = (Join-Path $ExecutionRoot "codex.stdout.log")
        codex_stderr_log_path = (Join-Path $ExecutionRoot "codex.stderr.log")
        codex_command_log_path = (Join-Path $ExecutionRoot "codex.command.json")
        codex_result = [pscustomobject]@{
            status = "fail"
            mode = "fake-codex"
        }
        retry_execution = $false
        prompt_input_path = (Join-Path $ExecutionRoot "codex-input.txt")
        execution_log_root = $ExecutionRoot
        backups_created = @()
        tests_executed = @("Scripts/Test-PDAStack.ps1 -Deep")
        test_results = @(
            [pscustomobject]@{ command = "Scripts/Test-PDAStack.ps1 -Deep"; status = "fail" }
        )
        status = "fail"
        review_required = $true
        next_action = "Human review required; validation did not complete."
        execution_notes = @("Simulated failed run for monitor validation.")
    }
    $Summary | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath (Join-Path $SummaryRoot "handoff-summary.json") -Encoding UTF8

    return [pscustomobject]@{
        execution_root = $ExecutionRoot
        summary_root = $SummaryRoot
    }
}

function Get-ResultStatus {
    param([Parameter(Mandatory = $true)][object]$Result)

    if ($Result -and $Result.PSObject.Properties.Name -contains "status") {
        return [string]$Result.status
    }

    return ""
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pda-build-runner-monitor-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$RecoveryRepo = Join-Path $TempRoot "recovery-repo"
Initialize-PDATempRepo -DestinationRoot $RecoveryRepo -SourceRoot $Root
Update-TempRoadmapForMonitor -SourcePath $RoadmapScript -TargetPath (Join-Path $RecoveryRepo "Roadmap\PDA-Roadmap.json")
Update-TempPolicyForMonitor -SourcePath $PolicyScript -TargetPath (Join-Path $RecoveryRepo "Roadmap\PDA-BuildRunnerPolicy.json")

$WorkPacketResult = Invoke-PDAJsonScript -Path $WorkPacketScript -Arguments @(
    "-Root", $RecoveryRepo,
    "-RoadmapPath", (Join-Path $RecoveryRepo "Roadmap\PDA-Roadmap.json"),
    "-TaskId", "task-001",
    "-PacketRoot", (Join-Path $RecoveryRepo "Roadmap\work-packets"),
    "-BranchName", "codex/build-runner/monitor-test"
)

$FailedExecution = New-FailedExecutionRecord -RepoRoot $RecoveryRepo -TaskId "task-001" -WorkPacketJsonPath $WorkPacketResult.json_path -WorkPacketMarkdownPath $WorkPacketResult.markdown_path

$FakeCodexScript = Join-Path $TempRoot "fake-codex.ps1"
New-FakeCodexScript -Path $FakeCodexScript

$FakeCodexArgs = Join-Path $TempRoot "fake-codex-args.txt"
@(
    "-NoProfile"
    "-File"
    $FakeCodexScript
) | Set-Content -LiteralPath $FakeCodexArgs -Encoding UTF8

$RecoveryResult = Invoke-PDAJsonScript -Path $MonitorScript -Arguments @(
    "-Root", $RecoveryRepo,
    "-RoadmapPath", (Join-Path $RecoveryRepo "Roadmap\PDA-Roadmap.json"),
    "-PolicyPath", (Join-Path $RecoveryRepo "Roadmap\PDA-BuildRunnerPolicy.json"),
    "-ExecutionRoot", $FailedExecution.execution_root,
    "-LogsRoot", (Join-Path $RecoveryRepo "PDA-Backups\build-runner\logs"),
    "-StagingRoot", (Join-Path $RecoveryRepo "PDA-Tasks\staging\nightly-build"),
    "-PacketRoot", (Join-Path $RecoveryRepo "Roadmap\work-packets"),
    "-PromptRoot", (Join-Path $RecoveryRepo "Roadmap\codex-prompts"),
    "-CodexExecutable", "pwsh.exe",
    "-CodexArguments", "@file:$FakeCodexArgs",
    "-Once"
)

$RecoveryRoadmap = Get-Content -LiteralPath (Join-Path $RecoveryRepo "Roadmap\PDA-Roadmap.json") -Raw | ConvertFrom-Json -ErrorAction Stop
$RecoveryTask = @($RecoveryRoadmap.tasks | Where-Object { [string]$_.id -eq "task-001" } | Select-Object -First 1)[0]
$RecoveryReportText = if (Test-Path -LiteralPath $RecoveryResult.report_path -PathType Leaf) { Get-Content -LiteralPath $RecoveryResult.report_path -Raw } else { "" }

$DirtyRepo = Join-Path $TempRoot "dirty-repo"
Initialize-PDATempRepo -DestinationRoot $DirtyRepo -SourceRoot $Root
Update-TempRoadmapForMonitor -SourcePath $RoadmapScript -TargetPath (Join-Path $DirtyRepo "Roadmap\PDA-Roadmap.json")
Update-TempPolicyForMonitor -SourcePath $PolicyScript -TargetPath (Join-Path $DirtyRepo "Roadmap\PDA-BuildRunnerPolicy.json")
Set-Content -LiteralPath (Join-Path $DirtyRepo "unexpected.txt") -Value "dirty" -Encoding UTF8

$DirtyResult = Invoke-PDAJsonScript -Path $MonitorScript -Arguments @(
    "-Root", $DirtyRepo,
    "-RoadmapPath", (Join-Path $DirtyRepo "Roadmap\PDA-Roadmap.json"),
    "-PolicyPath", (Join-Path $DirtyRepo "Roadmap\PDA-BuildRunnerPolicy.json"),
    "-ExecutionRoot", (Join-Path $DirtyRepo "PDA-Backups\build-runner\executions"),
    "-LogsRoot", (Join-Path $DirtyRepo "PDA-Backups\build-runner\logs"),
    "-StagingRoot", (Join-Path $DirtyRepo "PDA-Tasks\staging\nightly-build"),
    "-PacketRoot", (Join-Path $DirtyRepo "Roadmap\work-packets"),
    "-PromptRoot", (Join-Path $DirtyRepo "Roadmap\codex-prompts"),
    "-CodexExecutable", "pwsh.exe",
    "-CodexArguments", "@file:$FakeCodexArgs",
    "-Once"
)

$Issues = New-Object System.Collections.Generic.List[string]

if ((Get-ResultStatus -Result $RecoveryResult) -ne "pass") {
    $Issues.Add("Monitor did not recover the failed task.")
}
if ($RecoveryResult.stop_reason -ne "recovered") {
    $Issues.Add("Recovery pass did not stop with recovered.")
}
if ($RecoveryResult.task_id -ne "task-001") {
    $Issues.Add("Recovery pass did not target task-001.")
}
if ($RecoveryTask.status -ne "ready_for_review") {
    $Issues.Add("Recovered task did not advance to ready_for_review.")
}
if ($RecoveryResult.retry_result -and $RecoveryResult.retry_result.status -ne "pass") {
    $Issues.Add("Retry result did not pass.")
}
if ($RecoveryReportText -notmatch "Recovery Actions") {
    $Issues.Add("Recovery report did not include the recovery section.")
}
if ($RecoveryReportText -notmatch "retry:task-001") {
    $Issues.Add("Recovery report did not list the retry action.")
}
if (-not (Test-Path -LiteralPath $RecoveryResult.report_path -PathType Leaf)) {
    $Issues.Add("Recovery report file was not written.")
}
if (-not (Test-Path -LiteralPath $RecoveryResult.json_path -PathType Leaf)) {
    $Issues.Add("Recovery JSON file was not written.")
}

if ((Get-ResultStatus -Result $DirtyResult) -ne "fail") {
    $Issues.Add("Dirty worktree monitor pass did not fail.")
}
if ($DirtyResult.stop_reason -ne "dirty_worktree") {
    $Issues.Add("Dirty worktree stop reason was not dirty_worktree.")
}
if ($DirtyResult.retry_result) {
    $Issues.Add("Dirty worktree stop should not attempt a retry.")
}
if (-not (Test-Path -LiteralPath $DirtyResult.report_path -PathType Leaf)) {
    $Issues.Add("Dirty worktree report file was not written.")
}

$Report = [pscustomobject]@{
    status            = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    recovery          = $RecoveryResult
    dirty_stop        = $DirtyResult
    issues            = @($Issues)
    recovery_report   = $RecoveryResult.report_path
    dirty_report      = $DirtyResult.report_path
    temp_root         = $TempRoot
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 40
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA Build Runner monitor validation failed."
    }
    return
}

Write-Host "[*] PDA Build Runner monitor tests"
Write-Host ("Status : {0}" -f $Report.status)
Write-Host ("Recovery report: {0}" -f $Report.recovery_report)
Write-Host ("Dirty report   : {0}" -f $Report.dirty_report)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA Build Runner monitor validation failed."
}
