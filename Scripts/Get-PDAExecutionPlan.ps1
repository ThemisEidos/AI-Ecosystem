[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Text,

    [Parameter(Mandatory = $false)]
    [string]$GoalPlanJson,

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$GoalPlanningHelper = Join-Path $PSScriptRoot "PDA_GoalPlanning.ps1"
if (Test-Path -LiteralPath $GoalPlanningHelper -PathType Leaf) {
    . $GoalPlanningHelper
}

if (-not (Get-Command -Name New-PDAExecutionPlanFromGoalPlan -ErrorAction SilentlyContinue)) {
    throw "Goal planning helper missing: $GoalPlanningHelper"
}

if ([string]::IsNullOrWhiteSpace($GoalPlanJson)) {
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Provide either -Text or -GoalPlanJson."
    }

    $GoalPlanScript = Join-Path $PSScriptRoot "Get-PDAGoalPlan.ps1"
    $RawGoalPlan = & pwsh -NoProfile -File $GoalPlanScript -Text $Text -Root $Root -AsJson 2>&1
    $GoalPlanJson = [string]($RawGoalPlan -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($GoalPlanJson)) {
        throw "Goal plan generation returned empty output."
    }
}

$GoalPlan = $GoalPlanJson | ConvertFrom-Json -ErrorAction Stop
$ExecutionPlan = New-PDAExecutionPlanFromGoalPlan -GoalPlan $GoalPlan

$ExecutionPlan = [pscustomobject]@{
    status = $ExecutionPlan.status
    plan_id = $ExecutionPlan.plan_id
    goal = $ExecutionPlan.goal
    goal_type = $ExecutionPlan.goal_type
    category = $ExecutionPlan.category
    complexity = $ExecutionPlan.complexity
    approval_required = [bool]$ExecutionPlan.approval_required
    deliverables = @($ExecutionPlan.deliverables)
    subtasks = @($ExecutionPlan.subtasks)
    executor_chain = @($ExecutionPlan.executor_chain)
    dependencies = @($ExecutionPlan.dependencies)
    recommended_executors = @($ExecutionPlan.recommended_executors)
    response_text = [string]$ExecutionPlan.response_text
    next_action = [string]$ExecutionPlan.next_action
    source_of_truth = [string]$ExecutionPlan.source_of_truth
    output_location = [string]$ExecutionPlan.output_location
    goal_plan = $GoalPlan
}

if ($AsJson) {
    $ExecutionPlan | ConvertTo-Json -Depth 30
    return
}

Write-Host "[PDA EXECUTION PLAN]"
Write-Host $ExecutionPlan.response_text
