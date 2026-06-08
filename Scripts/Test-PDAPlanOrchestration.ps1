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
$GoalPlanScript = Join-Path $PSScriptRoot "Get-PDAGoalPlan.ps1"
$PlanInstanceScript = Join-Path $PSScriptRoot "New-PDAPlanInstance.ps1"
$PlanInvokeScript = Join-Path $PSScriptRoot "Invoke-PDAPlan.ps1"
$PlanStatusScript = Join-Path $PSScriptRoot "Get-PDAPlanStatus.ps1"
$PlanResultsScript = Join-Path $PSScriptRoot "Get-PDAPlanResults.ps1"
$DashboardStatusScript = Join-Path $PSScriptRoot "Get-PDADashboardStatus.ps1"

function Invoke-PDAJsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $Raw = & pwsh -NoProfile -File $Path @Arguments 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Script returned empty output: $Path"
    }

    return ConvertFrom-PDAMixedJson -Text $Text -SourceName $Path
}

function Assert-PDACondition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][System.Collections.Generic.List[string]]$Issues
    )

    if (-not $Condition -and $Issues) {
        $Issues.Add($Message)
    }

    return $Condition
}

function Format-PDAJsonFence {
    param([Parameter(Mandatory = $true)][string]$JsonText)

    return @('```json', $JsonText, '```') -join [Environment]::NewLine
}

$Issues = New-Object System.Collections.Generic.List[string]
$GoalText = "I want to start reading classic literature. Research the topic, create a reading list, write a report, and generate a PDF."

$GoalPlan = Invoke-PDAJsonScript -Path $GoalPlanScript -Arguments @("-Text", $GoalText, "-Root", $Root, "-Persist", "-AsJson")
Assert-PDACondition -Condition ([string]$GoalPlan.goal_type -eq "research_report_pdf") -Message "Goal plan did not classify the literature request correctly." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (@($GoalPlan.subtasks).Count -ge 4) -Message "Goal plan did not create enough subtasks." -Issues $Issues | Out-Null

$PlanInstance = Invoke-PDAJsonScript -Path $PlanInstanceScript -Arguments @("-ExecutionPlanJson", (($GoalPlan.execution_plan | ConvertTo-Json -Depth 40 -Compress)), "-Root", $Root, "-Status", "approved", "-AsJson")
Assert-PDACondition -Condition ([string]$PlanInstance.plan_folder -eq "approved") -Message "Plan instance was not written to the approved folder." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (@($PlanInstance.steps).Count -ge 4) -Message "Plan instance did not preserve the execution steps." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (@($PlanInstance.steps | Where-Object { @($_.depends_on).Count -gt 0 }).Count -ge 2) -Message "Step dependency tracking was not preserved." -Issues $Issues | Out-Null

$PlanInstanceFenced = Invoke-PDAJsonScript -Path $PlanInstanceScript -Arguments @("-ExecutionPlanJson", (Format-PDAJsonFence -JsonText (($GoalPlan.execution_plan | ConvertTo-Json -Depth 40 -Compress))), "-Root", $Root, "-Status", "approved", "-AsJson")
Assert-PDACondition -Condition ([string]$PlanInstanceFenced.plan_folder -eq "approved") -Message "Plan instance did not accept fenced execution-plan JSON." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (@($PlanInstanceFenced.steps).Count -ge 4) -Message "Fenced execution-plan JSON did not preserve the steps." -Issues $Issues | Out-Null

$PlanInstancePath = $PlanInstance.plan_path
$PlanSnapshot = Get-Content -LiteralPath $PlanInstancePath -Raw | ConvertFrom-Json
$StepCount = @($PlanSnapshot.steps).Count
$PreparedResultPaths = New-Object System.Collections.Generic.List[string]
$LastPrepareResult = $null
$LastResumeResult = $null

for ($StepIndex = 0; $StepIndex -lt $StepCount; $StepIndex++) {
    $LastPrepareResult = Invoke-PDAJsonScript -Path $PlanInvokeScript -Arguments @("-PlanInstancePath", $PlanInstancePath, "-Root", $Root, "-PrepareOnly", "-MaxSteps", "1", "-AsJson")
    Assert-PDACondition -Condition ([string]$LastPrepareResult.status -eq "running") -Message "Prepare-only orchestration did not enter running state." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition (@($LastPrepareResult.executed_steps).Count -eq 1) -Message "Prepare-only orchestration did not prepare exactly one step." -Issues $Issues | Out-Null
    if (-not [string]::IsNullOrWhiteSpace([string]$LastPrepareResult.plan_path)) {
        $PlanInstancePath = [string]$LastPrepareResult.plan_path
    }

    $PlanSnapshot = Get-Content -LiteralPath $PlanInstancePath -Raw | ConvertFrom-Json
    $PendingStep = @($PlanSnapshot.steps | Where-Object { [string]$_.status -in @("prepared", "running", "pending") } | Select-Object -First 1)
    Assert-PDACondition -Condition ($null -ne $PendingStep) -Message "Could not find the prepared step in the plan snapshot." -Issues $Issues | Out-Null

    $PreparedTaskId = [string]$PendingStep.task_id
    Assert-PDACondition -Condition (-not [string]::IsNullOrWhiteSpace($PreparedTaskId)) -Message "Prepared step did not receive a task id." -Issues $Issues | Out-Null

    $PreparedResultPath = Join-Path $Root ("PDA-Tasks\results\{0}-result.json" -f $PreparedTaskId)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $PreparedResultPath) | Out-Null
    @{
        task_id = $PreparedTaskId
        worker = [string]$PendingStep.executor
        status = "success"
        classification = "category_1"
        output_type = "markdown"
        output = @{
            content = "Prepared step output for $($PendingStep.step_id)"
            markdown_path = "C:\\temp\\$($PendingStep.step_id).md"
        }
        saved_path = "C:\\temp\\$($PendingStep.step_id).md"
        result_path = $PreparedResultPath
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $PreparedResultPath -Encoding UTF8
    $PreparedResultPaths.Add($PreparedResultPath) | Out-Null

    $LastResumeResult = Invoke-PDAJsonScript -Path $PlanInvokeScript -Arguments @("-PlanInstancePath", $PlanInstancePath, "-Root", $Root, "-Resume", "-MaxSteps", "1", "-AsJson")
    Assert-PDACondition -Condition (@($LastResumeResult.results.step_results).Count -ge 1) -Message "Resumed orchestration did not collect step results." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ([string]$LastResumeResult.results.status -in @("partial", "completed")) -Message "Resumed orchestration did not return a collectable status." -Issues $Issues | Out-Null
    if (-not [string]::IsNullOrWhiteSpace([string]$LastResumeResult.plan_path)) {
        $PlanInstancePath = [string]$LastResumeResult.plan_path
    }
}

$CompletedPlan = Get-Content -LiteralPath $PlanInstancePath -Raw | ConvertFrom-Json
if (-not [string]::IsNullOrWhiteSpace([string]$CompletedPlan.plan_path) -and (Test-Path -LiteralPath ([string]$CompletedPlan.plan_path))) {
    $PlanInstancePath = [string]$CompletedPlan.plan_path
}
else {
    $PlanInstancePath = (Get-ChildItem -LiteralPath (Join-Path $Root "PDA-Plans") -Recurse -Filter ("{0}.json" -f [string]$PlanInstance.plan_id) -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}
Assert-PDACondition -Condition ([string]$CompletedPlan.status -eq "completed") -Message "Plan did not finish in completed state." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([int]$CompletedPlan.overall_progress -eq 100) -Message "Plan progress did not reach 100%." -Issues $Issues | Out-Null

$StatusReport = Invoke-PDAJsonScript -Path $PlanStatusScript -Arguments @("-Root", $Root, "-AsJson")
Assert-PDACondition -Condition ($StatusReport.PSObject.Properties.Name -contains "counts") -Message "Plan status did not expose counts." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($StatusReport.PSObject.Properties.Name -contains "completed_plans") -Message "Plan status did not expose completed plans." -Issues $Issues | Out-Null

$ResultsReport = Invoke-PDAJsonScript -Path $PlanResultsScript -Arguments @("-PlanInstancePath", $PlanInstancePath, "-Root", $Root, "-AsJson")
Assert-PDACondition -Condition ($ResultsReport.PSObject.Properties.Name -contains "step_results") -Message "Plan results did not expose step results." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$ResultsReport.status -eq "completed") -Message "Plan results did not report completion." -Issues $Issues | Out-Null

$FailureGoalPlan = Invoke-PDAJsonScript -Path $GoalPlanScript -Arguments @("-Text", $GoalText, "-Root", $Root, "-Persist", "-AsJson")
$FailurePlan = Invoke-PDAJsonScript -Path $PlanInstanceScript -Arguments @("-ExecutionPlanJson", (($FailureGoalPlan.execution_plan | ConvertTo-Json -Depth 40 -Compress)), "-Root", $Root, "-Status", "approved", "-AsJson")
$FailurePlanPath = $FailurePlan.plan_path
$FailurePlanRecord = Get-Content -LiteralPath $FailurePlanPath -Raw | ConvertFrom-Json
$FailurePlanRecord.steps[0].executor = "bogus-executor"
$FailurePlanRecord | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $FailurePlanPath -Encoding UTF8
$FailureResult = Invoke-PDAJsonScript -Path $PlanInvokeScript -Arguments @("-PlanInstancePath", $FailurePlanPath, "-Root", $Root, "-Resume", "-MaxSteps", "1", "-AsJson", "-NoThrow")
Assert-PDACondition -Condition ([string]$FailureResult.status -eq "failed") -Message "Failure path did not mark the plan as failed." -Issues $Issues | Out-Null
if (-not [string]::IsNullOrWhiteSpace([string]$FailureResult.plan_path) -and (Test-Path -LiteralPath ([string]$FailureResult.plan_path))) {
    $FailurePlanPath = [string]$FailureResult.plan_path
}
else {
    $FailurePlanPath = (Get-ChildItem -LiteralPath (Join-Path $Root "PDA-Plans") -Recurse -Filter ("{0}.json" -f [string]$FailurePlan.plan_id) -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}

$DashboardReport = Invoke-PDAJsonScript -Path $DashboardStatusScript -Arguments @("-AsJson", "-NoThrow")
Assert-PDACondition -Condition ($DashboardReport.PSObject.Properties.Name -contains "commander_plan_orchestration") -Message "Dashboard status did not expose commander plan orchestration." -Issues $Issues | Out-Null

$CleanupTargets = @(
    $PlanInstancePath,
    $FailurePlanPath,
    (Join-Path $Root ("PDA-Plans\completed\{0}-results.json" -f [string]$PlanInstance.plan_id)),
    (Join-Path $Root ("PDA-Plans\failed\{0}-results.json" -f [string]$FailurePlan.plan_id))
)

$PlanInstanceFencedPath = if ($PlanInstanceFenced -and $PlanInstanceFenced.plan_path) { [string]$PlanInstanceFenced.plan_path } else { "" }
$CleanupTargets += $PlanInstanceFencedPath
$CleanupTargets += $PreparedResultPaths
$CleanupTargets += @(
    $CompletedPlan.steps |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.task_id) } |
        ForEach-Object { Join-Path $Root ("PDA-Tasks\pending\{0}.json" -f [string]$_.task_id) }
)
$CleanupTargets += @(
    $FailurePlanRecord.steps |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.task_id) } |
        ForEach-Object { Join-Path $Root ("PDA-Tasks\pending\{0}.json" -f [string]$_.task_id) }
)

foreach ($Target in $CleanupTargets) {
    if ([string]::IsNullOrWhiteSpace([string]$Target)) {
        continue
    }

    if (Test-Path -LiteralPath $Target) {
        try { Remove-Item -LiteralPath $Target -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    goal_plan = $GoalPlan
    plan_instance = $PlanInstance
    prepare_result = $LastPrepareResult
    resume_result = $LastResumeResult
    status_report = $StatusReport
    results_report = $ResultsReport
    dashboard_report = $DashboardReport
    issues = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 40
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA plan orchestration validation failed."
    }
    return
}

Write-Host "[*] PDA plan orchestration tests"
Write-Host ("Status     : {0}" -f $Report.status)
Write-Host ("Issues     : {0}" -f @($Report.issues).Count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA plan orchestration validation failed."
}
