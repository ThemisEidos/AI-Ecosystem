[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Text,

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$Persist,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$GoalPlanningHelper = Join-Path $PSScriptRoot "PDA_GoalPlanning.ps1"
if (Test-Path -LiteralPath $GoalPlanningHelper -PathType Leaf) {
    . $GoalPlanningHelper
}

if (-not (Get-Command -Name Get-PDAGoalPlanningClassification -ErrorAction SilentlyContinue)) {
    throw "Goal planning helper missing: $GoalPlanningHelper"
}

$Classification = Get-PDAGoalPlanningClassification -Text $Text
$GoalType = [string]$Classification.goal_type
$Category = [string]$Classification.category
$Deliverables = @($Classification.deliverables)
$Subtasks = @(Get-PDAGoalPlanningSubtasks -GoalType $GoalType -Deliverables $Deliverables -Category $Category -Text $Text)
$GoalId = "goal-{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 8))

$GoalPlan = [pscustomobject]@{
    status = "pass"
    plan_id = $GoalId
    goal_id = $GoalId
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    input_text = $Text
    goal = if ($Text -match '(?i)classic literature') { "Create a classic literature reading guide PDF" } elseif ($Text -match '(?i)roadmap') { "Build a roadmap" } elseif ($Text -match '(?i)study plan') { "Create a study plan" } else { $Text.Trim() }
    goal_type = $GoalType
    category = $Category
    complexity = [string]$Classification.complexity
    sensitivity = $Category
    approval_required = [bool]$Classification.approval_required
    confidence = 0.9
    deliverables = @($Deliverables)
    subtasks = @($Subtasks)
    required_capabilities = @($Classification.required_capabilities)
    planned_output_formats = @("markdown")
    recommended_executor_chain = @()
    execution_plan = $null
    summary = ""
    response_text = ""
    next_action = ""
    store_path = ""
    persisted = $false
    source_of_truth = "Scripts/Get-PDAGoalPlan.ps1"
}

$GoalPlan.recommended_executor_chain = @(Get-PDAGoalPlanningExecutorChain -Subtasks $GoalPlan.subtasks)
$ExecutionPlan = New-PDAExecutionPlanFromGoalPlan -GoalPlan $GoalPlan
$GoalPlan.execution_plan = $ExecutionPlan
$GoalPlan.response_text = $ExecutionPlan.response_text
$GoalPlan.next_action = $ExecutionPlan.next_action
$GoalPlan.summary = "Goal: {0}; Deliverables: {1}; Executors: {2}" -f $GoalPlan.goal, ($GoalPlan.deliverables -join ", "), ($GoalPlan.recommended_executor_chain.executor -join ", ")

if ($Persist) {
    try {
        $StoreRecord = [pscustomobject]@{
            plan_id = $GoalPlan.plan_id
            goal_id = $GoalPlan.goal_id
            created_at = $GoalPlan.created_at
            input_text = $GoalPlan.input_text
            goal = $GoalPlan.goal
            goal_type = $GoalPlan.goal_type
            category = $GoalPlan.category
            complexity = $GoalPlan.complexity
            sensitivity = $GoalPlan.sensitivity
            approval_required = [bool]$GoalPlan.approval_required
            deliverables = @($GoalPlan.deliverables)
            subtasks = @($GoalPlan.subtasks)
            recommended_executor_chain = @($GoalPlan.recommended_executor_chain)
            execution_plan = $ExecutionPlan
            status = "pending_review"
            summary = $GoalPlan.summary
        }
        $GoalPlan.store_path = Save-PDACommanderGoalStore -PlanRecord $StoreRecord -Root $Root
        $GoalPlan.persisted = $true
        $GoalPlan.store_path = [string]$GoalPlan.store_path
    }
    catch {
        $GoalPlan.persisted = $false
        $GoalPlan.summary = if ($GoalPlan.summary) { "$($GoalPlan.summary) | persist failed: $($_.Exception.Message)" } else { $_.Exception.Message }
    }
}

if (-not [string]::IsNullOrWhiteSpace([string]$GoalPlan.store_path) -and -not $GoalPlan.persisted) {
    $GoalPlan.store_path = ""
}

if (-not [string]::IsNullOrWhiteSpace([string]$GoalPlan.store_path)) {
    $GoalPlan.execution_plan.output_location = $GoalPlan.store_path
}

if ($AsJson) {
    $GoalPlan | ConvertTo-Json -Depth 30
    return
}

Write-Host "[PDA GOAL PLAN]"
Write-Host $GoalPlan.response_text
