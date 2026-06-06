[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$RoadmapPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\PDA-Roadmap.json"),

    [Parameter(Mandatory = $false)]
    [string]$PacketRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\work-packets"),

    [Parameter(Mandatory = $false)]
    [string]$PromptRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\codex-prompts"),

    [Parameter(Mandatory = $false)]
    [string]$StagingRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "PDA-Tasks\staging\nightly-build"),

    [Parameter(Mandatory = $false)]
    [string]$ExecutionRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "PDA-Backups\build-runner\executions"),

    [Parameter(Mandatory = $false)]
    [string]$TaskId = "",

    [Parameter(Mandatory = $false)]
    [string]$CodexExecutable = "",

    [Parameter(Mandatory = $false)]
    [string]$CodexArguments = "",

    [Parameter(Mandatory = $false)]
    [string]$RepoBackupManifestPath = "",

    [Parameter(Mandatory = $false)]
    [string]$VolumeBackupManifestPath = "",

    [Parameter(Mandatory = $false)]
    [string]$QueueAuditReportPath = "",

    [Parameter(Mandatory = $false)]
    [switch]$RetryExecution,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PDA_OutputParsing.ps1")
. (Join-Path $PSScriptRoot "PDA_BuildRunner.ps1")

$UpdateRoadmapScript = Join-Path $PSScriptRoot "Update-PDARoadmapStatus.ps1"
$PromptExportScript = Join-Path $PSScriptRoot "Export-PDACodexExecutionPrompt.ps1"
$StateScript = Join-Path $PSScriptRoot "Get-PDABuildRunnerTaskState.ps1"
$PacketScript = Join-Path $PSScriptRoot "Generate-PDACodexWorkPacket.ps1"
$MorningReportScript = Join-Path $PSScriptRoot "Generate-PDARunReport.ps1"

foreach ($Path in @($RoadmapPath, $UpdateRoadmapScript, $PromptExportScript, $StateScript, $PacketScript, $MorningReportScript)) {
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
    if ($Result.PSObject.Properties.Name -contains "status" -and [string]$Result.status -eq "fail") {
        throw "Command failed: $Path"
    }
    if ($LASTEXITCODE -ne 0 -and (-not $Result.PSObject.Properties.Name -contains "status" -or [string]$Result.status -ne "pass")) {
        throw "Command failed: $Path"
    }

    return $Result
}

function Get-PDAExecutionPreparationChain {
    param([Parameter(Mandatory = $true)][string]$CurrentState)

    switch ($CurrentState) {
        "backlog" { return @("eligible", "prepared", "assigned") }
        "eligible" { return @("prepared", "assigned") }
        "prepared" { return @("assigned") }
        "assigned" { return @() }
        default {
            throw "Codex execution requires backlog, eligible, prepared, or assigned state; got '$CurrentState'."
        }
    }
}

function Split-PDACommandLine {
    param([Parameter(Mandatory = $true)][string]$Text)

    $Tokens = New-Object System.Collections.Generic.List[string]
    $Pattern = '(?:"([^"]*)"|(\S+))'
    foreach ($Match in [regex]::Matches($Text, $Pattern)) {
        $Value = if ($Match.Groups[1].Success) { $Match.Groups[1].Value } else { $Match.Groups[2].Value }
        if (-not [string]::IsNullOrWhiteSpace($Value)) {
            [void]$Tokens.Add($Value)
        }
    }

    return @($Tokens)
}

function Resolve-PDACodexExecutablePath {
    param([string]$ProvidedPath = "")
    $Resolution = Resolve-PDABuildRunnerCodexExecutablePath -ProvidedPath $ProvidedPath
    if ([string]$Resolution.status -ne "pass") {
        throw ("Codex invocation unavailable locally: {0}" -f [string]$Resolution.issue)
    }

    return [string]$Resolution.executable_path
}

function Invoke-PDAProcessCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory = $Root,

        [Parameter(Mandatory = $false)]
        [string]$StandardInput = "",

        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory,

        [Parameter(Mandatory = $true)]
        [string]$LogPrefix
    )

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

    $StdOutPath = Join-Path $OutputDirectory "$LogPrefix.stdout.log"
    $StdErrPath = Join-Path $OutputDirectory "$LogPrefix.stderr.log"
    $CommandPath = Join-Path $OutputDirectory "$LogPrefix.command.json"

    $Process = [System.Diagnostics.Process]::new()
    $Process.StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $Process.StartInfo.FileName = $FilePath
    $Process.StartInfo.WorkingDirectory = $WorkingDirectory
    $Process.StartInfo.UseShellExecute = $false
    $Process.StartInfo.RedirectStandardInput = $true
    $Process.StartInfo.RedirectStandardOutput = $true
    $Process.StartInfo.RedirectStandardError = $true
    $Process.StartInfo.CreateNoWindow = $true

    $QuotedArguments = @(
        foreach ($Argument in @($Arguments)) {
            $Value = [string]$Argument
            if ($Value -match '[\s"]') {
                '"' + ($Value -replace '"', '\"') + '"'
            }
            else {
                $Value
            }
        }
    )
    $Process.StartInfo.Arguments = ($QuotedArguments -join ' ')

    if (-not $Process.Start()) {
        throw "Failed to start Codex process: $FilePath"
    }

    if (-not [string]::IsNullOrWhiteSpace($StandardInput)) {
        $Process.StandardInput.Write($StandardInput)
    }
    $Process.StandardInput.Close()

    $StdOutText = [string]$Process.StandardOutput.ReadToEnd()
    $StdErrText = [string]$Process.StandardError.ReadToEnd()
    $Process.WaitForExit()

    Set-Content -LiteralPath $StdOutPath -Value $StdOutText -Encoding UTF8
    Set-Content -LiteralPath $StdErrPath -Value $StdErrText -Encoding UTF8
    [pscustomobject]@{
        executable = $FilePath
        arguments = @($Arguments)
        working_directory = $WorkingDirectory
        stdout_log_path = $StdOutPath
        stderr_log_path = $StdErrPath
        command_log_path = $CommandPath
        exit_code = $Process.ExitCode
        stdout = $StdOutText
        stderr = $StdErrText
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $CommandPath -Encoding UTF8

    return [pscustomobject]@{
        exit_code      = $Process.ExitCode
        stdout         = $StdOutText
        stderr         = $StdErrText
        stdout_log_path = $StdOutPath
        stderr_log_path = $StdErrPath
        command_log_path = $CommandPath
    }
}

function Invoke-PDARecordedTest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string]$ExecutionRoot
    )

    $Tokens = Split-PDACommandLine -Text $Command
    if ($Tokens.Count -lt 1) {
        throw "Invalid test command: $Command"
    }

    $ScriptPath = $Tokens[0]
    $Arguments = @()
    if ($Tokens.Count -gt 1) {
        $Arguments = @($Tokens | Select-Object -Skip 1)
    }

    if (-not [System.IO.Path]::IsPathRooted($ScriptPath)) {
        $ScriptPath = Join-Path $Root $ScriptPath
    }

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Required test script was not found: $ScriptPath"
    }

    $NormalizedArguments = @($Arguments)
    if ($NormalizedArguments -notcontains "-NoThrow") {
        $NormalizedArguments += "-NoThrow"
    }
    if ($NormalizedArguments -notcontains "-AsJson") {
        $NormalizedArguments += "-AsJson"
    }

    $TestLogRoot = Join-Path $ExecutionRoot "tests"
    $TestArguments = @("-NoProfile", "-File", $ScriptPath) + @($NormalizedArguments)
    $Invocation = Invoke-PDAProcessCapture -FilePath "pwsh.exe" -Arguments $TestArguments -WorkingDirectory $Root -StandardInput "" -OutputDirectory $TestLogRoot -LogPrefix ([System.IO.Path]::GetFileNameWithoutExtension($ScriptPath))
    $Parsed = $null
    if (-not [string]::IsNullOrWhiteSpace($Invocation.stdout)) {
        try {
            $Parsed = ConvertFrom-PDAMixedJson -Text $Invocation.stdout -SourceName $ScriptPath
        }
        catch {
            $Parsed = $null
        }
    }

    if (-not $Parsed) {
        return [pscustomobject]@{
            command = $Command
            script_path = $ScriptPath
            arguments = @($NormalizedArguments)
            exit_code = $Invocation.exit_code
            stdout_log_path = $Invocation.stdout_log_path
            stderr_log_path = $Invocation.stderr_log_path
            command_log_path = $Invocation.command_log_path
            parsed_output = $null
            status = "fail"
            error = "Test output did not contain parseable JSON."
        }
    }

    return [pscustomobject]@{
        command = $Command
        script_path = $ScriptPath
        arguments = @($NormalizedArguments)
        exit_code = $Invocation.exit_code
        stdout_log_path = $Invocation.stdout_log_path
        stderr_log_path = $Invocation.stderr_log_path
        command_log_path = $Invocation.command_log_path
        parsed_output = $Parsed
        status = if ($Parsed -and $Parsed.PSObject.Properties.Name -contains "status") { [string]$Parsed.status } elseif ($Invocation.exit_code -eq 0) { "pass" } else { "fail" }
    }
}

$Roadmap = Import-PDABuildRunnerRoadmap -Root $Root -RoadmapPath $RoadmapPath
if ([string]::IsNullOrWhiteSpace($TaskId)) {
    $TaskId = [string]$Roadmap.current_task_id
}

$Task = Get-PDABuildRunnerTaskState -Roadmap $Roadmap -TaskId $TaskId
if (-not $Task) {
    throw "Task state not found: $TaskId"
}

$PromptScriptResult = Invoke-PDAJsonScript -Path $PromptExportScript -Arguments @(
    "-Root", $Root,
    "-RoadmapPath", $RoadmapPath,
    "-PacketRoot", $PacketRoot,
    "-StagingRoot", $StagingRoot,
    "-PromptRoot", $PromptRoot,
    "-TaskId", $TaskId
)

if ($PromptScriptResult.source_kind -eq "staged_summary" -and -not [string]::IsNullOrWhiteSpace([string]$PromptScriptResult.source_summary_path)) {
    $StagedSummaryPath = [string]$PromptScriptResult.source_summary_path
}
else {
    $StagedSummaryPath = ""
}

$InitialState = [string]$Task.status
$PreparationChain = @()
if ($RetryExecution) {
    if ($InitialState -notin @("assigned", "in_progress", "testing")) {
        throw "Retry execution requires assigned, in_progress, or testing state; got '$InitialState'."
    }
}
else {
    $PreparationChain = @(Get-PDAExecutionPreparationChain -CurrentState $InitialState)
}

$StateTransitions = New-Object System.Collections.Generic.List[object]
foreach ($TargetState in $PreparationChain) {
    $Transition = Invoke-PDAJsonScript -Path $UpdateRoadmapScript -Arguments @(
        "-Root", $Root,
        "-RoadmapPath", $RoadmapPath,
        "-TaskId", $TaskId,
        "-ToState", $TargetState,
        "-Actor", "PDA Build Runner Codex",
        "-Reason", "Prepare task for Codex execution"
    )
    [void]$StateTransitions.Add($Transition)
}

$Task = Get-PDABuildRunnerTaskState -Roadmap (Import-PDABuildRunnerRoadmap -Root $Root -RoadmapPath $RoadmapPath) -TaskId $TaskId
if (-not $RetryExecution -and [string]$Task.status -ne "assigned") {
    throw "Task must be assigned before Codex execution; current state is '$($Task.status)'."
}
if ($RetryExecution -and [string]$Task.status -notin @("assigned", "in_progress", "testing")) {
    throw "Retry execution requires assigned, in_progress, or testing state after preparation; current state is '$($Task.status)'."
}

$ExecutionTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ExecutionLogRoot = Join-Path $ExecutionRoot "$TaskId-$ExecutionTimestamp"
New-Item -ItemType Directory -Force -Path $ExecutionLogRoot | Out-Null

$CodexExecutablePath = Resolve-PDACodexExecutablePath -ProvidedPath $CodexExecutable
if ([string]::IsNullOrWhiteSpace($CodexArguments)) {
    $ResolvedCodexArguments = @("exec", "--full-auto", "--cd", $Root)
}
else {
    if ($CodexArguments -match '^(?i)@file:(.+)$') {
        $ArgumentFile = $Matches[1]
        if (-not (Test-Path -LiteralPath $ArgumentFile -PathType Leaf)) {
            throw "Codex arguments file not found: $ArgumentFile"
        }

        $ResolvedCodexArguments = @(
            Get-Content -LiteralPath $ArgumentFile -ErrorAction Stop |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
    }
    else {
        $ResolvedCodexArguments = @($CodexArguments -split '\|') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }
}

$ExecutionPrompt = [string]$PromptScriptResult.copy_paste_prompt
$PromptInputPath = Join-Path $ExecutionLogRoot "codex-input.txt"
Set-Content -LiteralPath $PromptInputPath -Value $ExecutionPrompt -Encoding UTF8

$CodexInvocation = Invoke-PDAProcessCapture -FilePath $CodexExecutablePath -Arguments $ResolvedCodexArguments -WorkingDirectory $Root -StandardInput $ExecutionPrompt -OutputDirectory $ExecutionLogRoot -LogPrefix "codex"
$CodexParsed = $null
if (-not [string]::IsNullOrWhiteSpace($CodexInvocation.stdout)) {
    try {
        $CodexParsed = ConvertFrom-PDAMixedJson -Text $CodexInvocation.stdout -SourceName "Codex stdout"
    }
    catch {
        $CodexParsed = $null
    }
}

$ExecutionTransitions = New-Object System.Collections.Generic.List[object]
if (-not $RetryExecution -or [string]$Task.status -eq "assigned") {
    $ExecutionState = "in_progress"
    $TransitionToInProgress = Invoke-PDAJsonScript -Path $UpdateRoadmapScript -Arguments @(
        "-Root", $Root,
        "-RoadmapPath", $RoadmapPath,
        "-TaskId", $TaskId,
        "-ToState", "in_progress",
        "-Actor", "PDA Build Runner Codex",
        "-Reason", "Codex execution started"
    )
    [void]$ExecutionTransitions.Add($TransitionToInProgress)
}
else {
    $ExecutionState = [string]$Task.status
}

if ($CodexInvocation.exit_code -eq 0) {
    if ([string]$Task.status -ne "testing") {
        $TransitionToTesting = Invoke-PDAJsonScript -Path $UpdateRoadmapScript -Arguments @(
            "-Root", $Root,
            "-RoadmapPath", $RoadmapPath,
            "-TaskId", $TaskId,
            "-ToState", "testing",
            "-Actor", "PDA Build Runner Codex",
            "-Reason", "Codex execution completed; running validation"
        )
        [void]$ExecutionTransitions.Add($TransitionToTesting)
    }
    $ExecutionState = "testing"

    $RequiredTests = @($PromptScriptResult.required_tests) | ForEach-Object { [string]$_ }
    $TestResults = New-Object System.Collections.Generic.List[object]
    foreach ($Command in $RequiredTests) {
        $TestResult = Invoke-PDARecordedTest -Command $Command -ExecutionRoot $ExecutionLogRoot
        [void]$TestResults.Add($TestResult)
        if ($TestResult.status -ne "pass") {
        $ExecutionState = "testing"
        break
    }
    }

    if (@($TestResults | Where-Object { $_.status -ne "pass" }).Count -eq 0) {
        $TransitionToReady = Invoke-PDAJsonScript -Path $UpdateRoadmapScript -Arguments @(
            "-Root", $Root,
            "-RoadmapPath", $RoadmapPath,
            "-TaskId", $TaskId,
            "-ToState", "ready_for_review",
            "-Actor", "PDA Build Runner Codex",
            "-Reason", "Codex execution and validation completed"
        )
        [void]$ExecutionTransitions.Add($TransitionToReady)
        $ExecutionState = "ready_for_review"
    }
}
else {
    $TestResults = New-Object System.Collections.Generic.List[object]
}

$RoadmapAfter = Import-PDABuildRunnerRoadmap -Root $Root -RoadmapPath $RoadmapPath
$TaskAfter = Get-PDABuildRunnerTaskState -Roadmap $RoadmapAfter -TaskId $TaskId
$ExecutionTransitionsArray = @($ExecutionTransitions.ToArray())
$ExecutionTransitionStates = @()
for ($TransitionIndex = 0; $TransitionIndex -lt $ExecutionTransitionsArray.Count; $TransitionIndex++) {
    $ExecutionTransitionStates += [string]$ExecutionTransitionsArray[$TransitionIndex].to_state
}

$TestResultsArray = @($TestResults.ToArray())
$TestCommandNames = @()
for ($TestIndex = 0; $TestIndex -lt $TestResultsArray.Count; $TestIndex++) {
    $TestResult = $TestResultsArray[$TestIndex]
    if ($TestResult -and $TestResult.PSObject.Properties.Name -contains "command") {
        $TestCommandNames += [string]$TestResult.command
    }
}
$CodexExitCode = [int]$CodexInvocation.exit_code
$CodexStdoutLogPath = [string]$CodexInvocation.stdout_log_path
$CodexStderrLogPath = [string]$CodexInvocation.stderr_log_path
$CodexCommandLogPath = [string]$CodexInvocation.command_log_path
$TestsPassedCount = 0
$TestsFailedCount = 0
for ($TestIndex = 0; $TestIndex -lt $TestResultsArray.Count; $TestIndex++) {
    $TestResult = $TestResultsArray[$TestIndex]
    if ([string]$TestResult.status -eq "pass") {
        $TestsPassedCount++
    }
    else {
        $TestsFailedCount++
    }
}
$SummaryStatus = if ($CodexExitCode -eq 0 -and $TestsFailedCount -eq 0) { "pass" } else { "fail" }
$BackupsCreated = New-Object System.Collections.Generic.List[string]
foreach ($BackupPath in @([string]$RepoBackupManifestPath, [string]$VolumeBackupManifestPath, [string]$QueueAuditReportPath)) {
    if (-not [string]::IsNullOrWhiteSpace($BackupPath)) {
        [void]$BackupsCreated.Add($BackupPath)
    }
}

$SummaryDir = Join-Path $StagingRoot "$TaskId-$ExecutionTimestamp"
New-Item -ItemType Directory -Force -Path $SummaryDir | Out-Null
$SummaryJsonPath = Join-Path $SummaryDir "handoff-summary.json"
$SummaryMarkdownPath = Join-Path $SummaryDir "handoff-summary.md"

$SummaryObject = [pscustomobject]@{
    schema_version              = "1.0"
    artifact_type               = "pda_build_runner_codex_execution_summary"
    generated_at                = (Get-Date).ToUniversalTime().ToString("o")
    task_id                     = $TaskId
    title                       = [string]$TaskAfter.title
    objective                   = [string]$TaskAfter.objective
    branch_name                 = [string]((& git -C $Root branch --show-current 2>$null | Select-Object -First 1))
    source_summary_path         = $StagedSummaryPath
    source_prompt_json_path     = [string]$PromptScriptResult.json_path
    source_prompt_markdown_path = [string]$PromptScriptResult.markdown_path
    work_packet_json_path       = [string]$PromptScriptResult.source_packet_json_path
    work_packet_markdown_path   = [string]$PromptScriptResult.source_packet_markdown_path
    state_before                = $InitialState
    state_after                 = [string]$TaskAfter.status
    preparation_transition_chain = @($PreparationChain)
    execution_transition_chain   = @($ExecutionTransitionStates)
    codex_executable            = $CodexExecutablePath
    codex_arguments             = @($ResolvedCodexArguments)
    codex_exit_code             = $CodexExitCode
    codex_stdout_log_path       = $CodexStdoutLogPath
    codex_stderr_log_path       = $CodexStderrLogPath
    codex_command_log_path      = $CodexCommandLogPath
    codex_result                = $CodexParsed
    retry_execution             = [bool]$RetryExecution
    prompt_input_path           = $PromptInputPath
    execution_log_root          = $ExecutionLogRoot
    backups_created             = @($BackupsCreated)
    tests_executed              = @($TestCommandNames)
    test_results                = @($TestResultsArray)
    status                      = $SummaryStatus
    review_required             = ($ExecutionState -eq "ready_for_review")
    next_action                 = if ($ExecutionState -eq "ready_for_review") { "Human review required before commit, push, or merge." } else { "Human review required; validation did not complete." }
    execution_notes             = @(
        "Human-governed only.",
        "No auto-commit.",
        "No auto-push.",
        "No unattended Codex execution.",
        "No approval bypass.",
        "No queue deletion."
    )
}

$SummaryObject | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $SummaryJsonPath -Encoding UTF8

$SummaryLines = New-Object System.Collections.Generic.List[string]
$SummaryLines.Add("# PDA Build Runner Codex Execution Summary")
$SummaryLines.Add("")
$SummaryLines.Add(("Generated at: {0}" -f $SummaryObject.generated_at))
$SummaryLines.Add(("Task ID: {0}" -f $SummaryObject.task_id))
$SummaryLines.Add(("Title: {0}" -f $SummaryObject.title))
$SummaryLines.Add(("Objective: {0}" -f $SummaryObject.objective))
$SummaryLines.Add(("Branch: {0}" -f $SummaryObject.branch_name))
$SummaryLines.Add(("State before: {0}" -f $SummaryObject.state_before))
$SummaryLines.Add(("State after: {0}" -f $SummaryObject.state_after))
$SummaryLines.Add(("Codex executable: {0}" -f $SummaryObject.codex_executable))
$SummaryLines.Add(("Codex exit code: {0}" -f $SummaryObject.codex_exit_code))
$SummaryLines.Add("")
$SummaryLines.Add("## Preparation Transitions")
foreach ($State in @($SummaryObject.preparation_transition_chain)) {
    $SummaryLines.Add(("- {0}" -f $State))
}
$SummaryLines.Add("")
$SummaryLines.Add("## Execution Transitions")
foreach ($State in @($SummaryObject.execution_transition_chain)) {
    $SummaryLines.Add(("- {0}" -f $State))
}
$SummaryLines.Add("")
$SummaryLines.Add("## Prompt Artifacts")
$SummaryLines.Add(("Prompt JSON: {0}" -f $SummaryObject.source_prompt_json_path))
$SummaryLines.Add(("Prompt Markdown: {0}" -f $SummaryObject.source_prompt_markdown_path))
$SummaryLines.Add(("Prompt input: {0}" -f $SummaryObject.prompt_input_path))
$SummaryLines.Add("")
$SummaryLines.Add("## Logs")
$SummaryLines.Add(("Stdout: {0}" -f $SummaryObject.codex_stdout_log_path))
$SummaryLines.Add(("Stderr: {0}" -f $SummaryObject.codex_stderr_log_path))
$SummaryLines.Add(("Command log: {0}" -f $SummaryObject.codex_command_log_path))
$SummaryLines.Add(("Execution root: {0}" -f $SummaryObject.execution_log_root))
$SummaryLines.Add("")
$SummaryLines.Add("## Validation")
foreach ($TestResult in @($SummaryObject.test_results)) {
    $SummaryLines.Add(("- {0}: {1}" -f $TestResult.command, $TestResult.status))
}
$SummaryLines.Add("")
$SummaryLines.Add(("Status: {0}" -f $SummaryObject.status))
$SummaryLines.Add(("Next action: {0}" -f $SummaryObject.next_action))

$SummaryLines | Set-Content -LiteralPath $SummaryMarkdownPath -Encoding UTF8

$Result = [pscustomobject]@{
    status                    = $SummaryObject.status
    task_id                   = $TaskId
    selected_task_id          = $TaskId
    source_summary_path       = $StagedSummaryPath
    source_prompt_json_path   = $SummaryObject.source_prompt_json_path
    source_prompt_markdown_path = $SummaryObject.source_prompt_markdown_path
    work_packet_json_path     = $SummaryObject.work_packet_json_path
    work_packet_markdown_path = $SummaryObject.work_packet_markdown_path
    state_before              = $InitialState
    state_after               = [string]$TaskAfter.status
    preparation_transition_chain = @($PreparationChain)
    execution_transition_chain = @($ExecutionTransitionStates)
    codex_executable          = $SummaryObject.codex_executable
    codex_arguments           = @($SummaryObject.codex_arguments)
    codex_exit_code           = $SummaryObject.codex_exit_code
    codex_stdout_log_path     = $SummaryObject.codex_stdout_log_path
    codex_stderr_log_path     = $SummaryObject.codex_stderr_log_path
    codex_command_log_path    = $SummaryObject.codex_command_log_path
    codex_result              = $SummaryObject.codex_result
    retry_execution           = $SummaryObject.retry_execution
    prompt_input_path          = $SummaryObject.prompt_input_path
    execution_log_root        = $SummaryObject.execution_log_root
    tests_executed            = @($SummaryObject.tests_executed)
    test_results              = @($SummaryObject.test_results)
    summary_json_path         = $SummaryJsonPath
    summary_markdown_path     = $SummaryMarkdownPath
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 40
    return
}

Write-Host "[OK] PDA Build Runner Codex execution complete."
Write-Host ("Task     : {0}" -f $TaskId)
Write-Host ("State    : {0} -> {1}" -f $InitialState, $TaskAfter.status)
Write-Host ("Summary  : {0}" -f $SummaryJsonPath)
