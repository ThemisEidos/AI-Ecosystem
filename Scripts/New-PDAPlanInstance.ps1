[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ExecutionPlanJson = "",

    [Parameter(Mandatory = $false)]
    [string]$ExecutionPlanPath = "",

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [ValidateSet("pending_approval", "approved", "running", "completed", "failed")]
    [string]$Status = "approved",

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$HelperScript = Join-Path $PSScriptRoot "PDA_PlanOrchestration.ps1"
. $HelperScript

if ([string]::IsNullOrWhiteSpace($ExecutionPlanJson)) {
    if ([string]::IsNullOrWhiteSpace($ExecutionPlanPath)) {
        throw "Provide either -ExecutionPlanJson or -ExecutionPlanPath."
    }

    if (-not (Test-Path -LiteralPath $ExecutionPlanPath -PathType Leaf)) {
        throw "Execution plan not found: $ExecutionPlanPath"
    }

    $ExecutionPlanJson = Get-Content -LiteralPath $ExecutionPlanPath -Raw -ErrorAction Stop
}

$ExecutionPlan = $ExecutionPlanJson | ConvertFrom-Json -ErrorAction Stop
if ($ExecutionPlan.PSObject.Properties.Name -contains "execution_plan" -and $ExecutionPlan.execution_plan) {
    $ExecutionPlan = $ExecutionPlan.execution_plan
}

$NormalizedPlan = Normalize-PDAPlanRecord -Plan $ExecutionPlan -Path $ExecutionPlanPath
$NormalizedPlan.plan_id = if ($ExecutionPlan.PSObject.Properties.Name -contains "plan_id" -and -not [string]::IsNullOrWhiteSpace([string]$ExecutionPlan.plan_id)) { [string]$ExecutionPlan.plan_id } else { $NormalizedPlan.plan_id }
$NormalizedPlan.goal = if ($ExecutionPlan.PSObject.Properties.Name -contains "goal" -and -not [string]::IsNullOrWhiteSpace([string]$ExecutionPlan.goal)) { [string]$ExecutionPlan.goal } else { $NormalizedPlan.goal }
$NormalizedPlan.category = if ($ExecutionPlan.PSObject.Properties.Name -contains "category" -and -not [string]::IsNullOrWhiteSpace([string]$ExecutionPlan.category)) { [string]$ExecutionPlan.category } else { $NormalizedPlan.category }
$NormalizedPlan.status = $Status
$NormalizedPlan.plan_folder = Get-PDAPlanFolderNameForStatus -Status $Status
$NormalizedPlan.created_at = if ($ExecutionPlan.PSObject.Properties.Name -contains "created_at" -and -not [string]::IsNullOrWhiteSpace([string]$ExecutionPlan.created_at)) { [string]$ExecutionPlan.created_at } else { (Get-Date).ToUniversalTime().ToString("o") }
$NormalizedPlan.updated_at = (Get-Date).ToUniversalTime().ToString("o")
$NormalizedPlan.approved_at = if ($Status -in @("approved", "running", "completed", "failed")) { (Get-Date).ToUniversalTime().ToString("o") } else { "" }
$NormalizedPlan.execution_plan_path = if (-not [string]::IsNullOrWhiteSpace($ExecutionPlanPath)) { (Resolve-Path -LiteralPath $ExecutionPlanPath).Path } else { "" }
$NormalizedPlan.source_execution_plan = ConvertTo-PDAPlanHashtable -Value $ExecutionPlan
$NormalizedPlan.deliverables = @($ExecutionPlan.deliverables)
$NormalizedPlan.recommended_executors = @($ExecutionPlan.recommended_executors)
$NormalizedPlan.steps = @($NormalizedPlan.steps)
$NormalizedPlan.current_step = 1
$NormalizedPlan.overall_progress = 0
$NormalizedPlan.final_deliverable_package_path = ""
$NormalizedPlan.results_path = ""

$PlanPath = Write-PDAPlanRecord -Plan $NormalizedPlan -Root $Root -Status $Status
$NormalizedPlan.plan_path = $PlanPath

$Result = [pscustomobject]@{
    status = "pass"
    plan_id = [string]$NormalizedPlan.plan_id
    goal = [string]$NormalizedPlan.goal
    category = [string]$NormalizedPlan.category
    plan_folder = [string]$NormalizedPlan.plan_folder
    plan_path = $PlanPath
    step_count = @($NormalizedPlan.steps).Count
    current_step = [int]$NormalizedPlan.current_step
    overall_progress = [int]$NormalizedPlan.overall_progress
    status_label = [string]$NormalizedPlan.status
    approved_at = [string]$NormalizedPlan.approved_at
    execution_plan_path = [string]$NormalizedPlan.execution_plan_path
    steps = @($NormalizedPlan.steps)
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 40
    if (-not $NoThrow -and $Result.status -ne "pass") {
        throw "Plan instance creation failed."
    }
    return
}

Write-Host "[PDA PLAN INSTANCE]"
Write-Host ("Plan ID   : {0}" -f $Result.plan_id)
Write-Host ("Status    : {0}" -f $Result.plan_folder)
Write-Host ("Path      : {0}" -f $Result.plan_path)
