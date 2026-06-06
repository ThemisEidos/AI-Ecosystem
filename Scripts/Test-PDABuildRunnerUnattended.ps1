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
$RunnerScript = Join-Path $PSScriptRoot "Invoke-PDABuildRunner.ps1"
$StartScript = Join-Path $PSScriptRoot "Start-PDABuildRunner.ps1"
$PolicyScript = Join-Path $PSScriptRoot "PDA_BuildRunnerPolicy.json"
$RoadmapScript = Join-Path $Root "Roadmap\PDA-Roadmap.json"

foreach ($Path in @($RunnerScript, $StartScript, $PolicyScript, $RoadmapScript)) {
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
    foreach ($Folder in @("Roadmap", "Scripts", "Documentation", "Obsidian Vault\02_Projects\AI Tool Ecosystem")) {
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
        "Scripts\Invoke-PDABuildOrchestrator.ps1",
        "Scripts\Invoke-PDABuildRunner.ps1",
        "Scripts\Start-PDABuildRunner.ps1",
        "Scripts\Start-PDANightlyBuild.ps1",
        "Scripts\Update-PDARoadmapStatus.ps1",
        "Scripts\Get-PDANightlyTaskState.ps1",
        "Scripts\Get-PDABuildRunnerTaskState.ps1",
        "Scripts\Generate-PDACodexWorkPacket.ps1",
        "Scripts\Generate-PDAMorningReport.ps1",
        "Scripts\Generate-PDARunReport.ps1",
        "Scripts\Test-PDADashboardRefresh.ps1",
        "Scripts\Test-OpenWebUIChatCompletion.ps1",
        "Scripts\Test-PDALiteLLMProviders.ps1",
        "Scripts\Test-PDALiteLLMEnv.ps1",
        "Scripts\Test-PDAStack.ps1",
        "Scripts\Invoke-PDAQueueBacklogAudit.ps1",
        "Scripts\Test-PDAQueueBacklogAudit.ps1",
        "Scripts\Backup-PDARepo.ps1",
        "Scripts\Backup-PDAVolumes.ps1",
        "Scripts\Export-PDACodexExecutionPrompt.ps1",
        "Scripts\Invoke-PDACodexExecution.ps1",
        "Scripts\PDA_ModelRouting.json",
        "Scripts\PDA_WorkerRegistry.json",
        "Scripts\Test-PDABuildRunner.ps1",
        "Scripts\Test-PDANightlyAutomation.ps1",
        "Scripts\Test-PDABuildOrchestrator.ps1",
        "Scripts\Test-PDACodexExecutionPrompt.ps1",
        "Scripts\Test-PDACodexExecution.ps1",
        "Scripts\Get-PDADashboardStatus.ps1",
        "Scripts\Update-PDADashboard.ps1",
        "Documentation\OpenWebUI-Integration.md",
        "Documentation\AIEC-Startup-Commands.md",
        "Obsidian Vault\02_Projects\AI Tool Ecosystem\PDA Dashboard.md"
    )

    foreach ($Path in $TrackedFiles) {
        $SourcePath = Join-Path $SourceRoot $Path
        if (Test-Path -LiteralPath $SourcePath -PathType Leaf) {
            Copy-Item -Force $SourcePath (Join-Path $DestinationRoot $Path)
        }
    }

    $ExcludePath = Join-Path $DestinationRoot ".git\info\exclude"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ExcludePath) | Out-Null
    @(
        "Roadmap/",
        "Roadmap/work-packets/",
        "Roadmap/codex-prompts/",
        "PDA-Tasks/",
        "PDA-Backups/",
        "PDA-Runtime/data/",
        "Scripts/PDA_OutputParsing.ps1",
        "Scripts/PDA_NightlyAutomation.ps1",
        "Scripts/PDA_BuildRunner.ps1",
        "Scripts/Invoke-PDABuildOrchestrator.ps1",
        "Scripts/Invoke-PDABuildRunner.ps1",
        "Scripts/Start-PDABuildRunner.ps1",
        "Scripts/Start-PDANightlyBuild.ps1",
        "Scripts/Update-PDARoadmapStatus.ps1",
        "Scripts/Get-PDANightlyTaskState.ps1",
        "Scripts/Get-PDABuildRunnerTaskState.ps1",
        "Scripts/Generate-PDACodexWorkPacket.ps1",
        "Scripts/Generate-PDAMorningReport.ps1",
        "Scripts/Generate-PDARunReport.ps1",
        "Scripts/Test-PDADashboardRefresh.ps1",
        "Scripts/Test-OpenWebUIChatCompletion.ps1",
        "Scripts/Test-PDALiteLLMProviders.ps1",
        "Scripts/Test-PDALiteLLMEnv.ps1",
        "Scripts/Test-PDAStack.ps1",
        "Scripts/Invoke-PDAQueueBacklogAudit.ps1",
        "Scripts/Test-PDAQueueBacklogAudit.ps1",
        "Scripts/Backup-PDARepo.ps1",
        "Scripts/Backup-PDAVolumes.ps1",
        "Scripts/Export-PDACodexExecutionPrompt.ps1",
        "Scripts/Invoke-PDACodexExecution.ps1",
        "Scripts/PDA_ModelRouting.json",
        "Scripts/PDA_WorkerRegistry.json",
        "Scripts/Test-PDABuildRunner.ps1",
        "Scripts/Test-PDANightlyAutomation.ps1",
        "Scripts/Test-PDABuildOrchestrator.ps1",
        "Scripts/Test-PDACodexExecutionPrompt.ps1",
        "Scripts/Test-PDACodexExecution.ps1",
        "Scripts/Get-PDADashboardStatus.ps1",
        "Scripts/Update-PDADashboard.ps1",
        "Documentation/OpenWebUI-Integration.md",
        "Documentation/AIEC-Startup-Commands.md",
        "Obsidian Vault/02_Projects/AI Tool Ecosystem/PDA Dashboard.md"
    ) | Add-Content -Path $ExcludePath
}

function New-PDAFakeCodexScript {
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

function Set-PDAUnattendedTempPolicy {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][int]$MaxTasks
    )

    $Policy = Get-Content -LiteralPath $SourcePath -Raw | ConvertFrom-Json -ErrorAction Stop
    $Policy.max_tasks_per_run = $MaxTasks
    $Policy.max_runtime_minutes = 30
    $Policy.stop_on_failed_tests = $true
    $Policy.allow_commit_to_branch = $false
    $Policy.allow_push_branch = $false
    $Policy.allow_main_mod = $false
    $Policy.allow_secret_changes = $false
    $Policy.branch_prefix = "codex/build-runner/"
    $Policy | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $TargetPath -Encoding UTF8
}

function Set-PDAUnattendedTempRoadmap {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $Roadmap = Get-Content -LiteralPath $SourcePath -Raw | ConvertFrom-Json -ErrorAction Stop
    $Task1 = @($Roadmap.tasks | Select-Object -First 1)[0]
    if (-not $Task1) {
        throw "Source roadmap does not contain task-001."
    }

    $Task2 = $Task1 | ConvertTo-Json -Depth 40 | ConvertFrom-Json
    $Task2.id = "task-002"
    $Task2.title = "Audit queue and approval backlog follow-up"
    $Task2.description = "Continue the read-only backlog audit and confirm sequential Build Runner execution."
    $Task2.objective = "Validate unattended sequential task processing."
    $Task2.commit_message = "chore: validate unattended build runner sequencing"
    $Task2.status = "backlog"

    $Task1.status = "backlog"
    $Roadmap.current_task_id = "task-001"
    $Roadmap.completed_task_ids = @()
    $Roadmap.task_state_history = @()
    $Roadmap.last_updated = (Get-Date).ToUniversalTime().ToString("o")
    $Roadmap.tasks = @($Task1, $Task2)
    $Roadmap | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $TargetPath -Encoding UTF8
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pda-build-runner-unattended-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$RepoRoot = Join-Path $TempRoot "repo"
Initialize-PDATempRepo -DestinationRoot $RepoRoot -SourceRoot $Root

$RepoRoadmapPath = Join-Path $RepoRoot "Roadmap\PDA-Roadmap.json"
$RepoPolicyPath = Join-Path $RepoRoot "Roadmap\PDA-BuildRunnerPolicy.json"
Set-PDAUnattendedTempRoadmap -SourcePath $RoadmapScript -TargetPath $RepoRoadmapPath
Set-PDAUnattendedTempPolicy -SourcePath $PolicyScript -TargetPath $RepoPolicyPath -MaxTasks 2

$FakeCodexScript = Join-Path $TempRoot "fake-codex.ps1"
New-PDAFakeCodexScript -Path $FakeCodexScript

$FakeCodexArgsFile = Join-Path $TempRoot "fake-codex-args.txt"
@(
    "-NoProfile"
    "-File"
    $FakeCodexScript
) | Set-Content -LiteralPath $FakeCodexArgsFile -Encoding UTF8

$MainHeadBefore = [string](& git -C $RepoRoot rev-parse main 2>$null).Trim()
$StatusBefore = [string](& git -C $RepoRoot status --porcelain 2>$null | Select-Object -First 1)

$RunResult = Invoke-PDAJsonScript -Path $RunnerScript -Arguments @(
    "-Root", $RepoRoot,
    "-RoadmapPath", $RepoRoadmapPath,
    "-OutputRoot", $TempRoot,
    "-Unattended",
    "-CodexExecutable", "pwsh.exe",
    "-CodexArguments", "@file:$FakeCodexArgsFile"
)

$RoadmapAfter = Get-Content -LiteralPath $RepoRoadmapPath -Raw | ConvertFrom-Json -ErrorAction Stop
$Task1After = @($RoadmapAfter.tasks | Where-Object { [string]$_.id -eq "task-001" } | Select-Object -First 1)[0]
$Task2After = @($RoadmapAfter.tasks | Where-Object { [string]$_.id -eq "task-002" } | Select-Object -First 1)[0]
$MainHeadAfter = [string](& git -C $RepoRoot rev-parse main 2>$null).Trim()
$StatusAfter = [string](& git -C $RepoRoot status --porcelain 2>$null | Select-Object -First 1)

$Issues = New-Object System.Collections.Generic.List[string]

if ($StatusBefore) {
    $Issues.Add("Temp repo was not clean before unattended run.")
}
if ($RunResult.status -ne "pass") {
    $Issues.Add("Unattended run did not pass.")
    if (-not [string]::IsNullOrWhiteSpace([string]$RunResult.parse_error)) {
        $Issues.Add(("Parse error: {0}" -f [string]$RunResult.parse_error))
    }
}
if ($RunResult.status -eq "pass") {
    if ($RunResult.mode -ne "unattended") {
        $Issues.Add("Unattended mode did not activate.")
    }
    if (@($RunResult.selected_task_ids).Count -lt 2) {
        $Issues.Add("Sequential task loop did not execute two tasks.")
    }
    if (@($RunResult.selected_task_ids)[0] -ne "task-001" -or @($RunResult.selected_task_ids)[1] -ne "task-002") {
        $Issues.Add("Task selection order was not task-001 then task-002.")
    }
    if ($RunResult.stop_reason -ne "max_tasks_per_run") {
        $Issues.Add("Unattended run did not stop on max_tasks_per_run.")
    }
    if ($RunResult.branch_name -notlike "codex/build-runner/*") {
        $Issues.Add("Branch name did not use the build runner prefix.")
    }
    if ($RunResult.policy_path -ne $RepoPolicyPath) {
        $Issues.Add("Unattended run did not use the Roadmap policy file.")
    }
    if (-not (Test-Path -LiteralPath $RunResult.report_path -PathType Leaf)) {
        $Issues.Add("Unattended report was not written.")
    }
    if (-not (Test-Path -LiteralPath $RunResult.logs_root -PathType Container)) {
        $Issues.Add("Unattended logs root was not written.")
    }
    if ($Task1After.status -ne "ready_for_review") {
        $Issues.Add("Task-001 did not advance to ready_for_review.")
    }
    if ($Task2After.status -ne "ready_for_review") {
        $Issues.Add("Task-002 did not advance to ready_for_review.")
    }
}
if ($MainHeadBefore -ne $MainHeadAfter) {
    $Issues.Add("Main branch was modified during unattended run.")
}
if ($StatusAfter) {
    $Issues.Add("Temp repo was dirty after unattended run.")
}

$DirtyRepoRoot = Join-Path $TempRoot "dirty-repo"
Initialize-PDATempRepo -DestinationRoot $DirtyRepoRoot -SourceRoot $Root
Set-PDAUnattendedTempRoadmap -SourcePath $RoadmapScript -TargetPath (Join-Path $DirtyRepoRoot "Roadmap\PDA-Roadmap.json")
Set-PDAUnattendedTempPolicy -SourcePath $PolicyScript -TargetPath (Join-Path $DirtyRepoRoot "Roadmap\PDA-BuildRunnerPolicy.json") -MaxTasks 1
Set-Content -LiteralPath (Join-Path $DirtyRepoRoot "unexpected.txt") -Value "dirty" -Encoding UTF8

$DirtyFailed = $false
try {
    $DirtyResult = Invoke-PDAJsonScript -Path $RunnerScript -Arguments @(
        "-Root", $DirtyRepoRoot,
        "-RoadmapPath", (Join-Path $DirtyRepoRoot "Roadmap\PDA-Roadmap.json"),
        "-OutputRoot", $TempRoot,
        "-Unattended",
        "-CodexExecutable", "pwsh.exe",
        "-CodexArguments", "@file:$FakeCodexArgsFile"
    )
    if ($DirtyResult.status -ne "fail") {
        $DirtyFailed = $false
    }
    else {
        $DirtyFailed = $true
    }
}
catch {
    $DirtyFailed = $true
}

if (-not $DirtyFailed) {
    $Issues.Add("Dirty worktree stop condition was not enforced.")
}

$Report = [pscustomobject]@{
    status              = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    temp_root           = $TempRoot
    repo_root           = $RepoRoot
    selected_task_ids   = @($RunResult.selected_task_ids)
    branch_name         = $RunResult.branch_name
    stop_reason         = $RunResult.stop_reason
    report_path         = $RunResult.report_path
    logs_root           = $RunResult.logs_root
    task_001_status     = if ($Task1After) { $Task1After.status } else { $null }
    task_002_status     = if ($Task2After) { $Task2After.status } else { $null }
    main_head_before    = $MainHeadBefore
    main_head_after     = $MainHeadAfter
    runner_parse_error  = $RunResult.parse_error
    runner_raw_output   = $RunResult.raw_output
    issues              = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 40
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA unattended build runner validation failed."
    }
    return
}

Write-Host "[*] PDA unattended build runner tests"
Write-Host ("Status    : {0}" -f $Report.status)
Write-Host ("Stop      : {0}" -f $Report.stop_reason)
Write-Host ("Report    : {0}" -f $Report.report_path)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA unattended build runner validation failed."
}
