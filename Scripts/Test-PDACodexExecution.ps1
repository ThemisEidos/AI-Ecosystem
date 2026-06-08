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
$PrepareScript = Join-Path $PSScriptRoot "Invoke-PDABuildOrchestrator.ps1"
$RunnerScript = Join-Path $PSScriptRoot "Start-PDABuildRunner.ps1"
$ExecutionScript = Join-Path $PSScriptRoot "Invoke-PDACodexExecution.ps1"
$PromptScript = Join-Path $PSScriptRoot "Export-PDACodexExecutionPrompt.ps1"
$StateScript = Join-Path $PSScriptRoot "Get-PDABuildRunnerTaskState.ps1"

foreach ($Path in @($RoadmapPath, $PrepareScript, $RunnerScript, $ExecutionScript, $PromptScript, $StateScript)) {
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

    $TrackedFiles = @(
        "Roadmap\PDA-Roadmap.json",
        "Scripts\PDA_OutputParsing.ps1",
        "Scripts\PDA_NightlyAutomation.ps1",
        "Scripts\PDA_BuildRunner.ps1",
        "Scripts\Monitor-PDABuildRunner.ps1",
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
        "Scripts\Get-PDADashboardStatus.ps1",
        "Scripts\Update-PDADashboard.ps1",
        "Scripts\Test-PDADashboardRefresh.ps1",
        "Scripts\Test-OpenWebUIChatCompletion.ps1",
        "Scripts\Export-PDACodexExecutionPrompt.ps1",
        "Scripts\Invoke-PDACodexExecution.ps1",
        "Scripts\Invoke-PDAQueueBacklogAudit.ps1",
        "Scripts\Test-PDAQueueBacklogAudit.ps1",
        "Scripts\Backup-PDARepo.ps1",
        "Scripts\Backup-PDAVolumes.ps1",
        "Scripts\Test-PDABuildRunner.ps1",
        "Scripts\Test-PDAStack.ps1"
    )

    foreach ($Path in $TrackedFiles) {
        Copy-Item -Force (Join-Path $SourceRoot $Path) (Join-Path $DestinationRoot $Path)
    }

    foreach ($IgnoredDir in @("Roadmap\work-packets", "Roadmap\codex-prompts")) {
        $SourceDir = Join-Path $SourceRoot $IgnoredDir
        if (Test-Path -LiteralPath $SourceDir -PathType Container) {
            New-Item -ItemType Directory -Force -Path (Join-Path $DestinationRoot $IgnoredDir) | Out-Null
            Copy-Item -Path (Join-Path $SourceDir "*") -Destination (Join-Path $DestinationRoot $IgnoredDir) -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    $ExcludePath = Join-Path $DestinationRoot ".git\info\exclude"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ExcludePath) | Out-Null
    @(
        "Roadmap/work-packets/",
        "Roadmap/codex-prompts/",
        "PDA-Tasks/",
        "PDA-Backups/",
        "Roadmap/PDA-Roadmap.json",
        "Scripts/PDA_OutputParsing.ps1",
        "Scripts/PDA_NightlyAutomation.ps1",
        "Scripts/PDA_BuildRunner.ps1",
        "Scripts/Monitor-PDABuildRunner.ps1",
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
        "Scripts/Export-PDACodexExecutionPrompt.ps1",
        "Scripts/Invoke-PDACodexExecution.ps1",
        "Scripts/Invoke-PDAQueueBacklogAudit.ps1",
        "Scripts/Test-PDAQueueBacklogAudit.ps1",
        "Scripts/Backup-PDARepo.ps1",
        "Scripts/Backup-PDAVolumes.ps1",
        "Scripts/Test-PDABuildRunner.ps1",
        "Scripts/Test-PDAStack.ps1",
        "Scripts/Generate-PDARunReport.ps1",
        "Scripts/Get-PDADashboardStatus.ps1",
        "Scripts/Update-PDADashboard.ps1",
        "Scripts/Test-OpenWebUIChatCompletion.ps1"
    ) | Add-Content -Path $ExcludePath
}

function Set-TempRoadmapForCodexExecution {
    param([Parameter(Mandatory = $true)][string]$TargetPath)

    $Roadmap = Get-Content -LiteralPath $RoadmapPath -Raw | ConvertFrom-Json -ErrorAction Stop
    $Task1 = @($Roadmap.tasks | Where-Object { [string]$_.id -eq "task-001" } | Select-Object -First 1)[0]
    $Task2 = @($Roadmap.tasks | Where-Object { [string]$_.id -eq "task-002" } | Select-Object -First 1)[0]
    if (-not $Task1 -or -not $Task2) {
        throw "Roadmap must contain task-001 and task-002."
    }

    $Task1.status = "backlog"
    $Task2.status = "backlog"
    $Task2.dependencies = @("task-001")
    $Roadmap.current_task_id = "task-001"
    $Roadmap.completed_task_ids = @()
    $Roadmap.task_state_history = @()
    $Roadmap.last_updated = (Get-Date).ToUniversalTime().ToString("o")
    $Roadmap.tasks = @($Task1, $Task2)
    $Roadmap | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $TargetPath -Encoding UTF8
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pda-codex-execution-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$PrepareRepoRoot = Join-Path $TempRoot "prepare-repo"
Initialize-PDATempRepo -DestinationRoot $PrepareRepoRoot -SourceRoot $Root
Set-TempRoadmapForCodexExecution -TargetPath (Join-Path $PrepareRepoRoot "Roadmap\PDA-Roadmap.json")

$PrepareResult = Invoke-PDAJsonScript -Path $PrepareScript -Arguments @(
    "-Root", $PrepareRepoRoot,
    "-RoadmapPath", (Join-Path $PrepareRepoRoot "Roadmap\PDA-Roadmap.json"),
    "-OutputRoot", $TempRoot,
    "-PrepareExecution"
)

$ExecuteRepoRoot = Join-Path $TempRoot "execute-repo"
Initialize-PDATempRepo -DestinationRoot $ExecuteRepoRoot -SourceRoot $PrepareRepoRoot
Set-TempRoadmapForCodexExecution -TargetPath (Join-Path $ExecuteRepoRoot "Roadmap\PDA-Roadmap.json")

& git -C $ExecuteRepoRoot add -f Roadmap/PDA-Roadmap.json | Out-Null
& git -C $ExecuteRepoRoot commit -m "prepare codex execution state" | Out-Null

$FakeCodexScript = Join-Path $TempRoot "fake-codex.ps1"
@'
param()
$Prompt = [Console]::In.ReadToEnd()
[Console]::Out.WriteLine("`e[32mFAKE CODEX START`e[0m")
[Console]::Out.WriteLine("mixed output before json")
[Console]::Out.WriteLine("{""status"":""pass"",""mode"":""fake-codex"",""prompt_length"":$($Prompt.Length)}")
[Console]::Error.WriteLine("fake codex stderr diagnostic")
exit 0
'@ | Set-Content -LiteralPath $FakeCodexScript -Encoding UTF8

$FakeCodexArgumentsFile = Join-Path $TempRoot "fake-codex-args.txt"
@(
    "-NoProfile"
    "-File"
    $FakeCodexScript
) | Set-Content -LiteralPath $FakeCodexArgumentsFile -Encoding UTF8

$ExecutionResult = Invoke-PDAJsonScript -Path $ExecutionScript -Arguments @(
    "-Root", $ExecuteRepoRoot,
    "-RoadmapPath", (Join-Path $ExecuteRepoRoot "Roadmap\PDA-Roadmap.json"),
    "-CodexExecutable", "pwsh.exe",
    "-CodexArguments", "@file:$FakeCodexArgumentsFile"
)

$TaskState = Invoke-PDAJsonScript -Path $StateScript -Arguments @(
    "-Root", $ExecuteRepoRoot,
    "-RoadmapPath", (Join-Path $ExecuteRepoRoot "Roadmap\PDA-Roadmap.json"),
    "-TaskId", "task-001"
)

$Issues = New-Object System.Collections.Generic.List[string]

if ($PrepareResult.mode -ne "prepare") {
    $Issues.Add("Prepare mode did not activate.")
}

if ($ExecutionResult.status -ne "pass") {
    $Issues.Add("Codex execution did not pass.")
}

if ($ExecutionResult.selected_task_id -ne "task-001") {
    $Issues.Add("Codex execution did not select task-001.")
}

if ($TaskState.task_state.status -ne "ready_for_review") {
    $Issues.Add("Task did not advance to ready_for_review.")
}

foreach ($Path in @($ExecutionResult.codex_stdout_log_path, $ExecutionResult.codex_stderr_log_path, $ExecutionResult.codex_command_log_path, $ExecutionResult.summary_json_path, $ExecutionResult.summary_markdown_path, $ExecutionResult.source_prompt_json_path, $ExecutionResult.source_prompt_markdown_path, $ExecutionResult.work_packet_json_path, $ExecutionResult.work_packet_markdown_path)) {
    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        $Issues.Add("Missing execution artifact path in runner output.")
        continue
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $Issues.Add("Missing execution artifact: $Path")
    }
}

if ($ExecutionResult.codex_result.status -ne "pass") {
    $Issues.Add("Codex output JSON was not parsed successfully.")
}

if ($ExecutionResult.codex_result.mode -ne "fake-codex") {
    $Issues.Add("Parsed Codex mode did not round-trip from stdout.")
}

if ([int]$ExecutionResult.codex_result.prompt_length -le 0) {
    $Issues.Add("Codex prompt length was not captured.")
}

if (($ExecutionResult.execution_transition_chain -notcontains "in_progress") -or ($ExecutionResult.execution_transition_chain -notcontains "testing") -or ($ExecutionResult.execution_transition_chain -notcontains "ready_for_review")) {
    $Issues.Add("Execution transition chain did not include in_progress/testing/ready_for_review.")
}

$Summary = $null
if (-not [string]::IsNullOrWhiteSpace([string]$ExecutionResult.summary_json_path) -and (Test-Path -LiteralPath $ExecutionResult.summary_json_path -PathType Leaf)) {
    $Summary = Get-Content -LiteralPath $ExecutionResult.summary_json_path -Raw | ConvertFrom-Json
    if ($Summary.state_after -ne "ready_for_review") {
        $Issues.Add("Summary state_after should be ready_for_review.")
    }
    if ($Summary.codex_exit_code -ne 0) {
        $Issues.Add("Summary codex_exit_code should be 0.")
    }
}

$StdOutText = if (-not [string]::IsNullOrWhiteSpace([string]$ExecutionResult.codex_stdout_log_path) -and (Test-Path -LiteralPath $ExecutionResult.codex_stdout_log_path -PathType Leaf)) { Get-Content -LiteralPath $ExecutionResult.codex_stdout_log_path -Raw } else { "" }
$StdErrText = if (-not [string]::IsNullOrWhiteSpace([string]$ExecutionResult.codex_stderr_log_path) -and (Test-Path -LiteralPath $ExecutionResult.codex_stderr_log_path -PathType Leaf)) { Get-Content -LiteralPath $ExecutionResult.codex_stderr_log_path -Raw } else { "" }
if ($StdOutText -notmatch "FAKE CODEX START") {
    $Issues.Add("Codex stdout log did not capture expected output.")
}
if ($StdErrText -notmatch "fake codex stderr diagnostic") {
    $Issues.Add("Codex stderr log did not capture expected diagnostics.")
}

$Report = [pscustomobject]@{
    status                 = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    prepare_mode           = $PrepareResult.mode
    execution_mode         = "codex"
    execution_script       = [string]$ExecutionScript
    selected_task_id       = $ExecutionResult.selected_task_id
    task_state             = $TaskState.task_state
    codex_exit_code        = $ExecutionResult.codex_exit_code
    codex_result           = $ExecutionResult.codex_result
    execution_transition_chain = @($ExecutionResult.execution_transition_chain)
    summary_json_path      = $ExecutionResult.summary_json_path
    summary_markdown_path  = $ExecutionResult.summary_markdown_path
    stdout_log_path        = $ExecutionResult.codex_stdout_log_path
    stderr_log_path        = $ExecutionResult.codex_stderr_log_path
    issues                 = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 40
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA Codex execution validation failed."
    }
    return
}

Write-Host "[*] PDA Codex execution tests"
Write-Host ("Status    : {0}" -f $Report.status)
Write-Host ("Task state: {0}" -f $Report.task_state.status)
Write-Host ("Summary   : {0}" -f $Report.summary_json_path)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA Codex execution validation failed."
}
