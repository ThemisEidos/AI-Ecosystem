[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$RoadmapPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\PDA-Roadmap.json"),

    [Parameter(Mandatory = $false)]
    [string]$PolicyPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\PDA-BuildRunnerPolicy.json"),

    [Parameter(Mandatory = $false)]
    [string]$ExecutionRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "PDA-Backups\build-runner\executions"),

    [Parameter(Mandatory = $false)]
    [string]$LogsRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "PDA-Backups\build-runner\logs"),

    [Parameter(Mandatory = $false)]
    [string]$StagingRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "PDA-Tasks\staging\nightly-build"),

    [Parameter(Mandatory = $false)]
    [string]$PacketRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\work-packets"),

    [Parameter(Mandatory = $false)]
    [string]$PromptRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\codex-prompts"),

    [Parameter(Mandatory = $false)]
    [string]$CodexExecutable = "",

    [Parameter(Mandatory = $false)]
    [string]$CodexArguments = "",

    [Parameter(Mandatory = $false)]
    [int]$PollIntervalSeconds = 30,

    [Parameter(Mandatory = $false)]
    [int]$MaxIterations = 0,

    [Parameter(Mandatory = $false)]
    [switch]$Once,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PDA_OutputParsing.ps1")
. (Join-Path $PSScriptRoot "PDA_BuildRunner.ps1")

$StackScript = Join-Path $PSScriptRoot "Test-PDAStack.ps1"
$ExecutionScript = Join-Path $PSScriptRoot "Invoke-PDACodexExecution.ps1"

foreach ($Path in @($RoadmapPath, $PolicyPath, $StackScript, $ExecutionScript)) {
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

function Read-PDABuildRunnerJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $Text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    return ($Text | ConvertFrom-Json -ErrorAction Stop)
}

function Test-PDABuildRunnerWorktreeDirty {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $Status = @(& git -C $Root status --porcelain 2>$null)
    return ($Status.Count -gt 0)
}

function Get-PDABuildRunnerMonitorTaskRecord {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Roadmap,

        [Parameter(Mandatory = $true)]
        [object]$Policy,

        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$ExecutionRoot,

        [Parameter(Mandatory = $true)]
        [string]$StagingRoot
    )

    $TaskState = Get-PDABuildRunnerTaskState -Roadmap $Roadmap
    if (-not $TaskState) {
        return $null
    }

    $TaskId = [string]$TaskState.task_id
    $ExecutionDirectories = @(
        Get-ChildItem -LiteralPath $ExecutionRoot -Directory -Filter "$TaskId-*" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending
    )
    $LatestExecutionDirectory = @($ExecutionDirectories | Select-Object -First 1)[0]

    $SummaryDirectories = @(
        Get-ChildItem -LiteralPath $StagingRoot -Directory -Filter "$TaskId-*" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending
    )
    $LatestSummaryDirectory = @($SummaryDirectories | Select-Object -First 1)[0]

    $SummaryPath = $null
    $Summary = $null
    if ($LatestSummaryDirectory) {
        $SummaryPath = Join-Path $LatestSummaryDirectory.FullName "handoff-summary.json"
        $Summary = Read-PDABuildRunnerJson -Path $SummaryPath
    }

    $ExecutionAgeMinutes = 0
    if ($LatestExecutionDirectory) {
        $ExecutionAgeMinutes = [Math]::Max(0, ((Get-Date).ToUniversalTime() - $LatestExecutionDirectory.LastWriteTimeUtc).TotalMinutes)
    }

    $LatestExecutionLogPath = $null
    $LatestExecutionLogText = ""
    if ($LatestExecutionDirectory) {
        $LatestExecutionLogPath = Join-Path $LatestExecutionDirectory.FullName "codex.stderr.log"
        if (Test-Path -LiteralPath $LatestExecutionLogPath -PathType Leaf) {
            $LatestExecutionLogText = [string](Get-Content -LiteralPath $LatestExecutionLogPath -Raw -ErrorAction SilentlyContinue)
        }
        elseif ((Join-Path $LatestExecutionDirectory.FullName "codex.stdout.log")) {
            $StdOutPath = Join-Path $LatestExecutionDirectory.FullName "codex.stdout.log"
            if (Test-Path -LiteralPath $StdOutPath -PathType Leaf) {
                $LatestExecutionLogPath = $StdOutPath
                $LatestExecutionLogText = [string](Get-Content -LiteralPath $StdOutPath -Raw -ErrorAction SilentlyContinue)
            }
        }
    }

    $FailurePatterns = @([string[]](Get-PDABuildRunnerPolicyValue -Policy $Policy -Name "retryable_failure_patterns" -Default @()))
    $FailureMatched = $false
    $FailureMatchText = ""
    foreach ($Pattern in $FailurePatterns) {
        if ([string]::IsNullOrWhiteSpace([string]$Pattern)) {
            continue
        }

        if ($LatestExecutionLogText -match [regex]::Escape([string]$Pattern)) {
            $FailureMatched = $true
            $FailureMatchText = [string]$Pattern
            break
        }
    }

    $FailureDetected = $false
    $FailureReason = ""
    if ($Summary) {
        if ($Summary.status -ne "pass") {
            $FailureDetected = $true
            $FailureReason = "summary_status"
        }
        elseif ($Summary.PSObject.Properties.Name -contains "codex_exit_code" -and [int]$Summary.codex_exit_code -ne 0) {
            $FailureDetected = $true
            $FailureReason = "codex_exit_code"
        }
        elseif ($Summary.PSObject.Properties.Name -contains "test_results") {
            foreach ($TestResult in @($Summary.test_results)) {
                if ($TestResult -and $TestResult.PSObject.Properties.Name -contains "status" -and [string]$TestResult.status -ne "pass") {
                    $FailureDetected = $true
                    $FailureReason = "test_failure"
                    break
                }
            }
        }
        elseif ($FailureMatched) {
            $FailureDetected = $true
            $FailureReason = "failure_pattern:$FailureMatchText"
        }
    }
    elseif ($LatestExecutionDirectory -and $ExecutionAgeMinutes -ge [double](Get-PDABuildRunnerPolicyValue -Policy $Policy -Name "stalled_run_timeout_minutes" -Default 15)) {
        $FailureDetected = $true
        $FailureReason = "stalled_run"
    }
    elseif ($FailureMatched) {
        $FailureDetected = $true
        $FailureReason = "failure_pattern:$FailureMatchText"
    }

    $AttemptCount = @($ExecutionDirectories).Count
    $RetryCount = [Math]::Max(0, $AttemptCount - 1)
    $RetryLimit = [int](Get-PDABuildRunnerPolicyValue -Policy $Policy -Name "max_retries_per_task" -Default 0)
    $CurrentState = [string]$TaskState.status
    $RetryEligible = ($FailureDetected -or $FailureReason -eq "stalled_run") -and ($CurrentState -in @("assigned", "in_progress", "testing")) -and ($RetryCount -lt $RetryLimit)

    return [pscustomobject]@{
        task_id                  = $TaskId
        current_state            = $CurrentState
        execution_directory      = if ($LatestExecutionDirectory) { $LatestExecutionDirectory.FullName } else { $null }
        execution_age_minutes    = [Math]::Round($ExecutionAgeMinutes, 2)
        attempt_count            = $AttemptCount
        retry_count              = $RetryCount
        retry_limit              = $RetryLimit
        summary_path             = $SummaryPath
        summary                  = $Summary
        failure_detected         = $FailureDetected
        failure_reason           = $FailureReason
        failure_pattern_matched  = $FailureMatchText
        retry_eligible           = $RetryEligible
    }
}

function Save-PDABuildRunnerRecoveryReport {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,

        [Parameter(Mandatory = $true)]
        [string]$MarkdownPath,

        [Parameter(Mandatory = $true)]
        [string]$JsonPath
    )

    $Report | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $JsonPath -Encoding UTF8

    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add("# PDA Build Runner Recovery Report")
    $Lines.Add("")
    $Lines.Add(("Generated at: {0}" -f $Report.generated_at))
    $Lines.Add(("Task ID: {0}" -f $Report.task_id))
    $Lines.Add(("Status: {0}" -f $Report.status))
    $Lines.Add(("Stop reason: {0}" -f $Report.stop_reason))
    $Lines.Add(("Task state: {0}" -f $Report.task_state))
    $Lines.Add(("Retry count: {0}" -f $Report.retry_count))
    $Lines.Add(("Retry limit: {0}" -f $Report.retry_limit))
    $Lines.Add("")
    $Lines.Add("## Stack Health")
    $Lines.Add(("Stack check status: {0}" -f $Report.stack_health.status))
    foreach ($Issue in @($Report.stack_health.issues)) {
        $Lines.Add(("- {0}" -f $Issue))
    }
    $Lines.Add("")
    $Lines.Add("## Execution Snapshot")
    $Lines.Add(("Execution directory: {0}" -f $Report.execution_directory))
    $Lines.Add(("Summary path: {0}" -f $Report.summary_path))
    $Lines.Add(("Failure reason: {0}" -f $Report.failure_reason))
    $Lines.Add(("Execution age (minutes): {0}" -f $Report.execution_age_minutes))
    $Lines.Add("")
    $Lines.Add("## Recovery Actions")
    foreach ($Action in @($Report.actions_taken)) {
        $Lines.Add(("- {0}" -f $Action))
    }
    $Lines.Add("")
    $Lines.Add("## Issues")
    foreach ($Issue in @($Report.issues)) {
        $Lines.Add(("- {0}" -f $Issue))
    }
    $Lines | Set-Content -LiteralPath $MarkdownPath -Encoding UTF8
}

$Policy = Import-PDABuildRunnerPolicy -Root $Root -PolicyPath $PolicyPath
$RunTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$RunLogRoot = Join-Path $LogsRoot $RunTimestamp
New-Item -ItemType Directory -Force -Path $RunLogRoot | Out-Null
$RecoveryReportPath = Join-Path $LogsRoot ("recovery-{0}.md" -f $RunTimestamp)
$RecoveryJsonPath = Join-Path $RunLogRoot "recovery.json"
$Iterations = 0
$Issues = New-Object System.Collections.Generic.List[string]
$Actions = New-Object System.Collections.Generic.List[string]
$RetryResult = $null
$StopReason = "healthy"
$MonitorStatus = "pass"
$TaskRecord = $null
$StackResult = $null

while ($true) {
    $Iterations++
    $Roadmap = Import-PDABuildRunnerRoadmap -Root $Root -RoadmapPath $RoadmapPath
    if (Test-PDABuildRunnerWorktreeDirty -Root $Root) {
        $StopReason = "dirty_worktree"
        $MonitorStatus = "fail"
        [void]$Issues.Add("Dirty worktree detected before monitor pass.")
        break
    }

    $StackResult = Invoke-PDAJsonScript -Path $StackScript -Arguments @("-Deep", "-NoThrow")
    if (-not $StackResult) {
        $StackResult = [pscustomobject]@{ status = "fail"; issues = @("Stack health check produced no result.") }
    }

    if ($StackResult.status -ne "pass") {
        $StopReason = "service_outage"
        $MonitorStatus = "fail"
        [void]$Issues.Add("PDA stack health check failed.")
        break
    }

    $TaskRecord = Get-PDABuildRunnerMonitorTaskRecord -Roadmap $Roadmap -Policy $Policy -Root $Root -ExecutionRoot $ExecutionRoot -StagingRoot $StagingRoot
    if (-not $TaskRecord) {
        $StopReason = "no_task"
        $MonitorStatus = "pass"
        break
    }

    if (-not $TaskRecord.failure_detected) {
        $StopReason = "healthy"
        if ($Once -or ($MaxIterations -gt 0 -and $Iterations -ge $MaxIterations)) {
            break
        }

        Start-Sleep -Seconds ([Math]::Max(1, $PollIntervalSeconds))
        continue
    }

    [void]$Issues.Add(("Detected {0} for task {1}." -f $TaskRecord.failure_reason, $TaskRecord.task_id))
    if ($TaskRecord.retry_eligible) {
        [void]$Actions.Add(("retry:{0}" -f $TaskRecord.task_id))
        $RetryArguments = @(
            "-Root", $Root,
            "-RoadmapPath", $RoadmapPath,
            "-PacketRoot", $PacketRoot,
            "-PromptRoot", $PromptRoot,
            "-StagingRoot", $StagingRoot,
            "-ExecutionRoot", $ExecutionRoot,
            "-TaskId", $TaskRecord.task_id,
            "-RetryExecution"
        )
        if (-not [string]::IsNullOrWhiteSpace($CodexExecutable)) {
            $RetryArguments += @("-CodexExecutable", $CodexExecutable)
        }
        if (-not [string]::IsNullOrWhiteSpace($CodexArguments)) {
            $RetryArguments += @("-CodexArguments", $CodexArguments)
        }

        $RetryResult = Invoke-PDAJsonScript -Path $ExecutionScript -Arguments $RetryArguments
        if ($RetryResult.status -eq "pass") {
            $StopReason = "recovered"
            $MonitorStatus = "pass"
            $TaskRecord = Get-PDABuildRunnerMonitorTaskRecord -Roadmap (Import-PDABuildRunnerRoadmap -Root $Root -RoadmapPath $RoadmapPath) -Policy $Policy -Root $Root -ExecutionRoot $ExecutionRoot -StagingRoot $StagingRoot
        }
        else {
            $StopReason = "retry_failed"
            $MonitorStatus = "fail"
            [void]$Issues.Add("Recovery retry failed.")
            if ($TaskRecord.retry_count -ge ($TaskRecord.retry_limit - 1)) {
                $StopReason = "retry_limit_reached"
            }
        }
    }
    else {
        $MonitorStatus = "fail"
        if ($TaskRecord.failure_reason -eq "stalled_run") {
            $StopReason = "stalled_run"
        }
        else {
            $StopReason = "failed_run"
        }
    }

    break
}

$Report = [pscustomobject]@{
    status              = $MonitorStatus
    mode                = "monitor"
    generated_at        = (Get-Date).ToUniversalTime().ToString("o")
    task_id             = if ($TaskRecord) { $TaskRecord.task_id } else { $null }
    task_state          = if ($TaskRecord) { $TaskRecord.current_state } else { $null }
    stop_reason         = $StopReason
    retry_count         = if ($TaskRecord) { $TaskRecord.retry_count } else { 0 }
    retry_limit         = if ($TaskRecord) { $TaskRecord.retry_limit } else { 0 }
    failure_reason      = if ($TaskRecord) { $TaskRecord.failure_reason } else { "" }
    execution_directory = if ($TaskRecord) { $TaskRecord.execution_directory } else { $null }
    summary_path        = if ($TaskRecord) { $TaskRecord.summary_path } else { $null }
    execution_age_minutes = if ($TaskRecord) { $TaskRecord.execution_age_minutes } else { 0 }
    stack_health        = $StackResult
    retry_result        = $RetryResult
    actions_taken       = @($Actions)
    issues              = @($Issues)
    report_path         = $RecoveryReportPath
    json_path           = $RecoveryJsonPath
    monitor_log_root    = $RunLogRoot
}

Save-PDABuildRunnerRecoveryReport -Report $Report -MarkdownPath $RecoveryReportPath -JsonPath $RecoveryJsonPath

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 40
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA Build Runner monitor detected a failure."
    }
    return
}

Write-Host "[OK] PDA Build Runner monitor completed."
Write-Host ("Status : {0}" -f $Report.status)
Write-Host ("Stop   : {0}" -f $Report.stop_reason)
Write-Host ("Report : {0}" -f $Report.report_path)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA Build Runner monitor detected a failure."
}
