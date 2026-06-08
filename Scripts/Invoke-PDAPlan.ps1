[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$PlanInstancePath = "",

    [Parameter(Mandatory = $false)]
    [string]$PlanId = "",

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$PrepareOnly,

    [Parameter(Mandatory = $false)]
    [switch]$Resume,

    [Parameter(Mandatory = $false)]
    [int]$PollIntervalSeconds = 3,

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 180,

    [Parameter(Mandatory = $false)]
    [int]$MaxSteps = 0,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "PDA_PlanOrchestration.ps1")
. (Join-Path $PSScriptRoot "PDA_ExecutorRegistry.ps1")

$TaskPrepScript = Join-Path $PSScriptRoot "Invoke-PDATaskDispatchPreparation.ps1"
$DispatcherScript = Join-Path $PSScriptRoot "dispatch-pda-command.ps1"
$ResultsRoot = Join-Path $Root "PDA-Tasks\results"

if ([string]::IsNullOrWhiteSpace($PlanInstancePath)) {
    if ([string]::IsNullOrWhiteSpace($PlanId)) {
        throw "Provide either -PlanInstancePath or -PlanId."
    }

    $PlanInstancePath = Find-PDAPlanFile -PlanId $PlanId -Root $Root
}

if ([string]::IsNullOrWhiteSpace($PlanInstancePath) -or -not (Test-Path -LiteralPath $PlanInstancePath -PathType Leaf)) {
    throw "Plan instance not found."
}

function Get-PDAPlanStepCommand {
    param([Parameter(Mandatory = $true)]$Step)

    switch ([string]$Step.task_type) {
        "research" { return "/research" }
        "reporting" { return "/reporter" }
        "document_generation" { return "/reporter" }
        "planning" { return "/planner" }
        "review" { return "/review" }
        "execution_manifest" { return "/execute" }
        default { return "/reporter" }
    }
}

function Invoke-PDAPlanStepTask {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)]$Step,
        [Parameter(Mandatory = $true)][int]$StepIndex,
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$PlanPath,
        [Parameter(Mandatory = $false)][switch]$PrepareOnly
    )

    $TaskId = if (-not [string]::IsNullOrWhiteSpace([string]$Step.task_id)) { [string]$Step.task_id } else { [guid]::NewGuid().ToString() }
    $TaskPath = Join-Path (Join-Path $RootPath "PDA-Tasks\pending") ("{0}.json" -f $TaskId)
    $TaskCommand = Get-PDAPlanStepCommand -Step $Step
    $Message = @(
        "Plan ID: $($Plan.plan_id)"
        "Plan Goal: $($Plan.goal)"
        "Step ID: $($Step.step_id)"
        "Step Title: $($Step.title)"
        "Dependencies: $(if (@($Step.depends_on).Count -gt 0) { @($Step.depends_on) -join ', ' } else { 'none' })"
        "Expected Output: $($Step.output)"
    ) -join "`n"

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TaskPath) | Out-Null
    $Task = [ordered]@{
        task_id = $TaskId
        created = (Get-Date).ToUniversalTime().ToString("o")
        command = $TaskCommand
        route = $TaskCommand.TrimStart("/")
        project = "PDA Plan Orchestration"
        target = $Message
        message = $Message
        category = if ([string]::IsNullOrWhiteSpace([string]$Plan.category)) { "category_1" } else { [string]$Plan.category }
        classification = if ([string]::IsNullOrWhiteSpace([string]$Plan.category)) { "category_1" } else { [string]$Plan.category }
        approved = $true
        status = "queued"
        assigned_worker = ([string]$Step.executor)
        routing_surface = "local-only"
        task_type = [string]$Step.task_type
        intent = [string]$Step.task_type
        requires_approval = $false
        requested_output = [string]$Step.output
        source_path = [string]$PlanPath
        plan_id = [string]$Plan.plan_id
        plan_step_id = [string]$Step.step_id
        plan_goal = [string]$Plan.goal
        plan_instance_path = [string]$PlanPath
        depends_on = @($Step.depends_on)
        retry_count = 0
    }

    $Task | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $TaskPath -Encoding UTF8

    if (-not $PrepareOnly) {
        & pwsh -NoProfile -File $DispatcherScript -TaskFile $TaskPath
        if ($LASTEXITCODE -ne 0) {
            throw "Dispatcher failed for step $($Step.step_id)."
        }
    }
    else {
        if (Test-Path -LiteralPath $TaskPrepScript -PathType Leaf) {
            & pwsh -NoProfile -File $TaskPrepScript -TaskPath $TaskPath -Executor ([string]$Step.executor) -Root $RootPath -AsJson | Out-Null
        }
    }

    return [pscustomobject]@{
        task_id = $TaskId
        task_path = $TaskPath
        command = $TaskCommand
        message = $Message
    }
}

$Plan = Read-PDAPlanRecord -Path $PlanInstancePath
if ([string]$Plan.status -eq "pending" -or [string]$Plan.status -eq "pending_approval") {
    $BlockedResult = [pscustomobject]@{
        status = "blocked"
        reason = "Plan is waiting for approval."
        plan_id = [string]$Plan.plan_id
        plan_path = [string]$Plan.plan_path
    }
    if ($AsJson) {
        $BlockedResult | ConvertTo-Json -Depth 20
        if (-not $NoThrow) { throw $BlockedResult.reason }
        return
    }
    Write-Host "[BLOCKED] $($BlockedResult.reason)"
    if (-not $NoThrow) { throw $BlockedResult.reason }
    return
}

$Plan.status = if ([string]$Plan.status -eq "approved") { "running" } else { [string]$Plan.status }
$Plan.plan_folder = "running"
$Plan.updated_at = (Get-Date).ToUniversalTime().ToString("o")

$ProgressReport = [ordered]@{
    plan_id = [string]$Plan.plan_id
    plan_path = [string]$Plan.plan_path
    status = [string]$Plan.status
    current_step = [int]$Plan.current_step
    overall_progress = [int]$Plan.overall_progress
    executed_steps = @()
    blocked_reason = ""
}

$Plan = Normalize-PDAPlanRecord -Plan $Plan -Path $PlanInstancePath
$ProcessedStepCount = 0

for ($Index = 0; $Index -lt @($Plan.steps).Count; $Index++) {
    $Step = $Plan.steps[$Index]
    if (([string]$Step.status) -eq "completed") {
        continue
    }

    $StepCompletionMap = Get-PDAPlanDependencyCompletion -Steps $Plan.steps
    if (-not (Test-PDAPlanDependenciesSatisfied -Step $Step -CompletionMap $StepCompletionMap)) {
        $Plan.status = "blocked"
        $Step.status = "blocked"
        $Step.blocked_reason = "Dependency chain incomplete."
        $ProgressReport.blocked_reason = $Step.blocked_reason
        $Plan.steps[$Index] = $Step
        Write-PDAPlanRecord -Plan $Plan -Root $Root -Status "failed" | Out-Null
        break
    }

    if ($Step.executor) {
        $Eligibility = Test-PDAExecutorAllowedForCategory -ExecutorName ([string]$Step.executor) -Category $(if ([string]::IsNullOrWhiteSpace([string]$Plan.category)) { "category_1" } else { ([string]$Plan.category) }) -RequiresLocalOnly:($Plan.category -in @("category_2", "restricted_local")) -Root $Root
        if (-not $Eligibility.allowed) {
            $Plan.status = "failed"
            $Step.status = "blocked"
            $Step.blocked_reason = [string]$Eligibility.blocked_reason
            $ProgressReport.blocked_reason = [string]$Eligibility.blocked_reason
            $Plan.steps[$Index] = $Step
            Write-PDAPlanRecord -Plan $Plan -Root $Root -Status "failed" | Out-Null
            break
        }
    }

    $TaskPath = ([string]$Step.task_path)
    $ExistingResultPath = ""
    if (-not [string]::IsNullOrWhiteSpace(([string]$Step.task_id))) {
        $ExistingResultPath = Join-Path $ResultsRoot ("{0}-result.json" -f ([string]$Step.task_id))
    }

    $NeedsDispatch = $true
    if ((([string]$Step.status) -in @("prepared", "running")) -and -not [string]::IsNullOrWhiteSpace($TaskPath) -and (Test-Path -LiteralPath $TaskPath -PathType Leaf)) {
        if (Test-Path -LiteralPath $ExistingResultPath -PathType Leaf) {
            $NeedsDispatch = $false
        }
        elseif ((([string]$Step.status) -eq "prepared") -and -not $PrepareOnly) {
            & pwsh -NoProfile -File $DispatcherScript -TaskFile $TaskPath
            if ($LASTEXITCODE -ne 0) {
                throw "Dispatcher failed for prepared step $($Step.step_id)."
            }
            $NeedsDispatch = $false
        }
        else {
            $NeedsDispatch = $false
        }
    }

    if ($NeedsDispatch) {
        $Dispatch = Invoke-PDAPlanStepTask -Plan $Plan -Step $Step -StepIndex ($Index + 1) -RootPath $Root -PlanPath $PlanInstancePath -PrepareOnly:$PrepareOnly
        $Step.task_id = $Dispatch.task_id
        $Step.task_path = $Dispatch.task_path
        $ExistingResultPath = Join-Path $ResultsRoot ("{0}-result.json" -f $Dispatch.task_id)
        $Step.started_at = (Get-Date).ToUniversalTime().ToString("o")
        $Step.status = $(if ($PrepareOnly) { "prepared" } else { "running" })
        $ProgressReport.executed_steps += [pscustomobject]@{
            step_id = ([string]$Step.step_id)
            task_id = ([string]$Step.task_id)
            task_path = ([string]$Step.task_path)
            status = ([string]$Step.status)
        }
    }

    $Plan.current_step = $Index + 1
    $Plan.status = "running"
    $Plan.updated_at = (Get-Date).ToUniversalTime().ToString("o")
    $Plan.steps[$Index] = $Step
    Write-PDAPlanRecord -Plan $Plan -Root $Root -Status "running" | Out-Null

    if ($PrepareOnly) {
        $ProcessedStepCount++
        break
    }

    if ((([string]$Step.status) -eq "prepared") -and -not (Test-Path -LiteralPath $ExistingResultPath -PathType Leaf)) {
        $Step.status = "running"
        $Plan.steps[$Index] = $Step
        Write-PDAPlanRecord -Plan $Plan -Root $Root -Status "running" | Out-Null
    }

    $StopAt = (Get-Date).AddSeconds($TimeoutSeconds)
    while (-not (Test-Path -LiteralPath $ExistingResultPath -PathType Leaf)) {
        if ((Get-Date) -ge $StopAt) {
            $Plan.status = "failed"
            $Step.status = "failed"
            $Step.blocked_reason = "Timed out waiting for worker result."
            $ProgressReport.blocked_reason = $Step.blocked_reason
            $Plan.steps[$Index] = $Step
            Write-PDAPlanRecord -Plan $Plan -Root $Root -Status "failed" | Out-Null
            break
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }

    if ($Plan.status -eq "failed") {
        break
    }

    $WorkerResult = Get-Content -LiteralPath $ExistingResultPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $Step.result_path = $ExistingResultPath
    $Step.completed_at = (Get-Date).ToUniversalTime().ToString("o")
    $Step.status = $(if (([string]$WorkerResult.status) -in @("success", "completed", "pass")) { "completed" } else { "failed" })
    if ((([string]$Step.status) -ne "completed")) {
        $Step.blocked_reason = if ($WorkerResult.PSObject.Properties.Name -contains "error" -and -not [string]::IsNullOrWhiteSpace(([string]$WorkerResult.error))) { [string]$WorkerResult.error } else { "Worker returned non-success status." }
        $Plan.status = "failed"
        $ProgressReport.blocked_reason = $Step.blocked_reason
    }

    $Plan.steps[$Index] = $Step
    $Plan.completed_step_count = @($Plan.steps | Where-Object { [string]$_.status -eq "completed" }).Count
    $Plan.failed_step_count = @($Plan.steps | Where-Object { [string]$_.status -in @("failed", "blocked") }).Count
    $Plan.overall_progress = if (@($Plan.steps).Count -gt 0) { [math]::Round((@($Plan.steps | Where-Object { [string]$_.status -eq "completed" }).Count / @($Plan.steps).Count) * 100, 0) } else { 0 }
    $Plan.updated_at = (Get-Date).ToUniversalTime().ToString("o")
    if ($Plan.status -eq "failed") {
        Write-PDAPlanRecord -Plan $Plan -Root $Root -Status "failed" | Out-Null
        break
    }

    Write-PDAPlanRecord -Plan $Plan -Root $Root -Status "running" | Out-Null
    $ProcessedStepCount++
    if ($MaxSteps -gt 0 -and $ProcessedStepCount -ge $MaxSteps) {
        break
    }
}

if ($Plan.status -ne "failed") {
    $RemainingIncomplete = @($Plan.steps | Where-Object { [string]$_.status -ne "completed" })
    if ($RemainingIncomplete.Count -eq 0 -and @($Plan.steps).Count -gt 0) {
        $Plan.status = "completed"
        $Plan.plan_folder = "completed"
        $Plan.current_step = @($Plan.steps).Count + 1
        $Plan.overall_progress = 100
        $Plan.updated_at = (Get-Date).ToUniversalTime().ToString("o")
        Write-PDAPlanRecord -Plan $Plan -Root $Root -Status "completed" | Out-Null
    }
    else {
        Write-PDAPlanRecord -Plan $Plan -Root $Root -Status $Plan.status | Out-Null
    }
}

$ProgressReport.status = [string]$Plan.status
$ProgressReport.current_step = [int]$Plan.current_step
$ProgressReport.overall_progress = [int]$Plan.overall_progress
$CurrentPlanPath = if (-not [string]::IsNullOrWhiteSpace([string]$Plan.plan_path) -and (Test-Path -LiteralPath ([string]$Plan.plan_path) -PathType Leaf)) {
    [string]$Plan.plan_path
}
else {
    Find-PDAPlanFile -PlanId ([string]$Plan.plan_id) -Root $Root
}

$ProgressReport.plan_path = $CurrentPlanPath

$Results = & pwsh -NoProfile -File (Join-Path $PSScriptRoot "Get-PDAPlanResults.ps1") -PlanInstancePath $CurrentPlanPath -Root $Root -AsJson
$FinalResults = $Results | ConvertFrom-Json -ErrorAction Stop

$ProgressReport.results = $FinalResults

if ($AsJson) {
    $ProgressReport | ConvertTo-Json -Depth 40
    if (-not $NoThrow -and $ProgressReport.status -eq "failed") {
        throw "Plan orchestration failed."
    }
    return
}

Write-Host "[PDA PLAN ORCHESTRATION]"
Write-Host ("Plan ID   : {0}" -f $ProgressReport.plan_id)
Write-Host ("Status    : {0}" -f $ProgressReport.status)
Write-Host ("Progress  : {0}%" -f $ProgressReport.overall_progress)
