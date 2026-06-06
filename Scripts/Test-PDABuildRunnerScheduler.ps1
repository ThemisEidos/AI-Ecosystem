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
$RoadmapScript = Join-Path $Root "Roadmap\PDA-Roadmap.json"
$PolicyScript = Join-Path $Root "Roadmap\PDA-BuildRunnerPolicy.json"

foreach ($Path in @($RunnerScript, $RoadmapScript, $PolicyScript)) {
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
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $true)][string]$SourceRoot
    )

    New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null
    foreach ($Folder in @("Roadmap","Scripts","PDA-Tasks\staging\nightly-build","PDA-Backups\build-runner\executions","PDA-Backups\build-runner\logs")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $DestinationRoot $Folder) | Out-Null
    }

    & git init $DestinationRoot | Out-Null
    & git -C $DestinationRoot config user.name "Codex Test" | Out-Null
    & git -C $DestinationRoot config user.email "codex@example.com" | Out-Null
    & git -C $DestinationRoot commit --allow-empty -m "seed" | Out-Null
    & git -C $DestinationRoot branch -M main | Out-Null

    foreach ($Path in @(
        "Roadmap\PDA-Roadmap.json",
        "Roadmap\PDA-BuildRunnerPolicy.json",
        "Scripts\PDA_OutputParsing.ps1",
        "Scripts\PDA_NightlyAutomation.ps1",
        "Scripts\PDA_BuildRunner.ps1",
        "Scripts\Invoke-PDABuildRunner.ps1",
        "Scripts\Invoke-PDACodexExecution.ps1",
        "Scripts\Generate-PDACodexWorkPacket.ps1",
        "Scripts\Export-PDACodexExecutionPrompt.ps1",
        "Scripts\Get-PDADashboardStatus.ps1",
        "Scripts\Update-PDADashboard.ps1",
        "Scripts\Generate-PDARunReport.ps1",
        "Scripts\Backup-PDARepo.ps1",
        "Scripts\Backup-PDAVolumes.ps1",
        "Scripts\Start-PDABuildRunner.ps1",
        "Scripts\Test-PDAStack.ps1",
        "Scripts\Test-OpenWebUIChatCompletion.ps1",
        "Scripts\Test-PDADashboardRefresh.ps1"
    )) {
        Copy-Item -Force (Join-Path $SourceRoot $Path) (Join-Path $DestinationRoot $Path)
    }

    $ExcludePath = Join-Path $DestinationRoot ".git\info\exclude"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ExcludePath) | Out-Null
    @(
        "Roadmap/",
        "Roadmap/work-packets/",
        "Roadmap/codex-prompts/",
        "PDA-Tasks/",
        "PDA-Backups/",
        "Scripts/PDA_OutputParsing.ps1",
        "Scripts/PDA_NightlyAutomation.ps1",
        "Scripts/PDA_BuildRunner.ps1",
        "Scripts/Invoke-PDABuildRunner.ps1",
        "Scripts/Invoke-PDACodexExecution.ps1",
        "Scripts/Generate-PDACodexWorkPacket.ps1",
        "Scripts/Export-PDACodexExecutionPrompt.ps1",
        "Scripts/Get-PDADashboardStatus.ps1",
        "Scripts/Update-PDADashboard.ps1",
        "Scripts/Generate-PDARunReport.ps1",
        "Scripts/Backup-PDARepo.ps1",
        "Scripts/Backup-PDAVolumes.ps1",
        "Scripts/Start-PDABuildRunner.ps1",
        "Scripts/Test-PDAStack.ps1",
        "Scripts/Test-OpenWebUIChatCompletion.ps1",
        "Scripts/Test-PDADashboardRefresh.ps1"
    ) | Add-Content -Path $ExcludePath
}

function New-FakeCodexScript {
    param([Parameter(Mandatory = $true)][string]$Path)

@'
param()
$Prompt = [Console]::In.ReadToEnd()
[Console]::Out.WriteLine("`e[32mMOCK CODEX START`e[0m")
[Console]::Out.WriteLine("mixed output before json")
[Console]::Out.WriteLine("{""status"":""pass"",""mode"":""mock-codex"",""prompt_length"":$($Prompt.Length)}")
[Console]::Error.WriteLine("mock codex stderr diagnostic")
exit 0
'@ | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Set-TempRoadmap {
    param([Parameter(Mandatory = $true)][string]$TargetPath)

    $Roadmap = Get-Content -LiteralPath $RoadmapScript -Raw | ConvertFrom-Json -ErrorAction Stop
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

function Set-TempPolicy {
    param([Parameter(Mandatory = $true)][string]$TargetPath)

    $Policy = Get-Content -LiteralPath $PolicyScript -Raw | ConvertFrom-Json -ErrorAction Stop
    $Policy.max_tasks_per_run = 1
    $Policy.MaxTasks = 1
    $Policy.max_runtime_minutes = 30
    $Policy.MaxRuntimeMinutes = 30
    $Policy.stop_on_failed_tests = $true
    $Policy.StopOnFailure = $true
    $Policy.allow_commit_to_branch = $false
    $Policy.allow_push_branch = $false
    $Policy.allow_main_mod = $false
    $Policy.allow_secret_changes = $false
    $Policy.RunReport = "PDA-Backups/build-runner/reports"
    $Policy | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $TargetPath -Encoding UTF8
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pda-build-runner-scheduler-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
$RepoRoot = Join-Path $TempRoot "repo"
Initialize-PDATempRepo -DestinationRoot $RepoRoot -SourceRoot $Root
Set-TempRoadmap -TargetPath (Join-Path $RepoRoot "Roadmap\PDA-Roadmap.json")
Set-TempPolicy -TargetPath (Join-Path $RepoRoot "Roadmap\PDA-BuildRunnerPolicy.json")

$FakeCodexScript = Join-Path $TempRoot "mock-codex.ps1"
New-FakeCodexScript -Path $FakeCodexScript
$FakeCodexArgsFile = Join-Path $TempRoot "mock-codex-args.txt"
@(
    "-NoProfile"
    "-File"
    $FakeCodexScript
) | Set-Content -LiteralPath $FakeCodexArgsFile -Encoding UTF8

$Execution = Invoke-PDAJsonScript -Path $RunnerScript -Arguments @(
    "-Root", $RepoRoot,
    "-RoadmapPath", (Join-Path $RepoRoot "Roadmap\PDA-Roadmap.json"),
    "-OutputRoot", $TempRoot,
    "-Unattended",
    "-CodexExecutable", "pwsh.exe",
    "-CodexArguments", "@file:$FakeCodexArgsFile"
)

$Issues = New-Object System.Collections.Generic.List[string]
$SelectedTaskIds = @($Execution.selected_task_ids)
$ReportPath = [string]$Execution.report_path
if ($Execution.status -ne "pass") {
    $Issues.Add("Scheduler run did not pass.")
}
if ($Execution.stop_reason -ne "max_tasks_per_run") {
    $Issues.Add("Scheduler did not stop on max_tasks_per_run.")
}
if ($SelectedTaskIds.Count -ne 1) {
    $Issues.Add("Scheduler did not process exactly one task.")
}
if ($SelectedTaskIds.Count -gt 0 -and $SelectedTaskIds[0] -ne "task-001") {
    $Issues.Add("Scheduler did not select task-001 first.")
}
if ($Execution.max_tasks -ne 1) {
    $Issues.Add("Scheduler did not surface max_tasks = 1.")
}
if ($Execution.codex_status -ne "pass") {
    $Issues.Add("Scheduler did not detect Codex locally.")
}
if ([string]::IsNullOrWhiteSpace($ReportPath) -or -not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
    $Issues.Add("Scheduler report was not written.")
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    temp_root = $TempRoot
    repo_root = $RepoRoot
    execution = $Execution
    issues = @($Issues)
    parse_error = $Execution.parse_error
    raw_output = $Execution.raw_output
    report_path = $ReportPath
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 40
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA Build Runner scheduler validation failed."
    }
    return
}

Write-Host "[*] PDA Build Runner scheduler tests"
Write-Host ("Status : {0}" -f $Report.status)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA Build Runner scheduler validation failed."
}
