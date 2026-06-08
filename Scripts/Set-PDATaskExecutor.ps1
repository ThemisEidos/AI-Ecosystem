[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TaskPath,

    [Parameter(Mandatory = $false)]
    [string]$Executor = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("category_1", "category_2", "restricted_local")]
    [string]$Category = "category_1",

    [Parameter(Mandatory = $false)]
    [string]$TaskType = "",

    [Parameter(Mandatory = $false)]
    [string]$PreferredOutput = "",

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$RegistryScript = Join-Path $PSScriptRoot "PDA_ExecutorRegistry.ps1"
if (Test-Path -LiteralPath $RegistryScript -PathType Leaf) {
    . $RegistryScript
}

if (-not (Test-Path -LiteralPath $TaskPath -PathType Leaf)) {
    throw "Task file not found: $TaskPath"
}

$Task = Get-Content -Path $TaskPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$ResolvedCategory = if (-not [string]::IsNullOrWhiteSpace([string]$Task.category)) { [string]$Task.category } else { $Category }
$ResolvedTaskType = if (-not [string]::IsNullOrWhiteSpace([string]$TaskType)) { $TaskType } elseif ($Task.PSObject.Properties.Name -contains "task_type" -and -not [string]::IsNullOrWhiteSpace([string]$Task.task_type)) { [string]$Task.task_type } else { [string]$Task.command }
$ResolvedPreferredOutput = if (-not [string]::IsNullOrWhiteSpace([string]$PreferredOutput)) { $PreferredOutput } elseif ($Task.PSObject.Properties.Name -contains "requested_output") { [string]$Task.requested_output } else { "" }

$Recommendation = $null
if (Get-Command -Name Get-PDAExecutorRecommendation -ErrorAction SilentlyContinue) {
    $Recommendation = Get-PDAExecutorRecommendation -TaskType $ResolvedTaskType -Category $ResolvedCategory -PreferredOutput $ResolvedPreferredOutput -RequiresLocalOnly:($ResolvedCategory -in @("category_2", "restricted_local")) -Text ([string]$Task.message) -Root $Root
}

if ([string]::IsNullOrWhiteSpace($Executor)) {
    if ($Recommendation -and -not [string]::IsNullOrWhiteSpace([string]$Recommendation.recommended_executor)) {
        $Executor = [string]$Recommendation.recommended_executor
    }
}

if ([string]::IsNullOrWhiteSpace($Executor)) {
    throw "Executor could not be determined for task: $TaskPath"
}

$ExecutorCheck = Test-PDAExecutorAllowedForCategory -ExecutorName $Executor -Category $ResolvedCategory -RequiresLocalOnly:($ResolvedCategory -in @("category_2", "restricted_local")) -Root $Root
if (-not $ExecutorCheck.allowed) {
    throw "Executor '$Executor' is not allowed for ${ResolvedCategory}: $($ExecutorCheck.blocked_reason)"
}

$Timestamp = (Get-Date).ToUniversalTime().ToString("o")
$Task | Add-Member -NotePropertyName executor_name -NotePropertyValue [string]$ExecutorCheck.executor_name -Force
$Task | Add-Member -NotePropertyName executor_display_name -NotePropertyValue [string]$ExecutorCheck.display_name -Force
$Task | Add-Member -NotePropertyName executor_type -NotePropertyValue [string]$ExecutorCheck.executor_type -Force
$Task | Add-Member -NotePropertyName executor_risk_level -NotePropertyValue [string]$ExecutorCheck.risk_level -Force
$Task | Add-Member -NotePropertyName executor_requires_approval -NotePropertyValue [bool]$ExecutorCheck.requires_approval -Force
$Task | Add-Member -NotePropertyName executor_supports_category2 -NotePropertyValue [bool]$ExecutorCheck.supports_category2 -Force
$Task | Add-Member -NotePropertyName executor_supports_local_only -NotePropertyValue [bool]$ExecutorCheck.supports_local_only -Force
$Task | Add-Member -NotePropertyName executor_dispatch_method -NotePropertyValue [string]$ExecutorCheck.dispatch_method -Force
$Task | Add-Member -NotePropertyName executor_recommendation_reason -NotePropertyValue $(if ($Recommendation) { [string]$Recommendation.routing_reason } else { "" }) -Force
$Task | Add-Member -NotePropertyName executor_recommended_at -NotePropertyValue $Timestamp -Force
$Task | Add-Member -NotePropertyName executor_recommended_by -NotePropertyValue "Scripts/Set-PDATaskExecutor.ps1" -Force
$Task | Add-Member -NotePropertyName dispatch_state -NotePropertyValue "executor_assigned" -Force
$Task | Add-Member -NotePropertyName dispatch_status -NotePropertyValue "executor_assigned" -Force
$Task | Add-Member -NotePropertyName dispatch_ready -NotePropertyValue $false -Force
$Task | Add-Member -NotePropertyName dispatch_package_path -NotePropertyValue "" -Force
$Task | Add-Member -NotePropertyName dispatch_summary_path -NotePropertyValue "" -Force
$Task | Add-Member -NotePropertyName dispatch_prompt_path -NotePropertyValue "" -Force
$Task | Add-Member -NotePropertyName dispatch_executor -NotePropertyValue [string]$ExecutorCheck.executor_name -Force
$Task | Add-Member -NotePropertyName dispatch_category -NotePropertyValue [string]$ResolvedCategory -Force
$Task | Add-Member -NotePropertyName dispatch_task_type -NotePropertyValue [string]$ResolvedTaskType -Force
$Task | Add-Member -NotePropertyName dispatch_prepared_at -NotePropertyValue "" -Force
$Task | Add-Member -NotePropertyName approval_required_for_dispatch -NotePropertyValue [bool]$ExecutorCheck.requires_approval -Force

$Task | ConvertTo-Json -Depth 24 | Set-Content -Path $TaskPath -Encoding UTF8

$TaskId = ""
if ($Task.PSObject.Properties.Name -contains "task_id") {
    $TaskId = [string]$Task.task_id
}

$RoutingReason = ""
if ($Recommendation) {
    $RoutingReason = [string]$Recommendation.routing_reason
}

$Result = [pscustomobject]@{
    status                 = "pass"
    task_path              = $TaskPath
    task_id                = $TaskId
    executor_name          = [string]$ExecutorCheck.executor_name
    executor_display_name  = [string]$ExecutorCheck.display_name
    executor_type          = [string]$ExecutorCheck.executor_type
    executor_risk_level    = [string]$ExecutorCheck.risk_level
    approval_required      = [bool]$ExecutorCheck.requires_approval
    category               = [string]$ResolvedCategory
    task_type              = [string]$ResolvedTaskType
    routing_reason         = $RoutingReason
    blocked_reason         = ""
    allowed                = $true
    dispatch_state         = "executor_assigned"
    dispatch_status        = "executor_assigned"
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] Task executor attached:"
Write-Host ("Task path   : {0}" -f $Result.task_path)
Write-Host ("Executor    : {0}" -f $Result.executor_name)
Write-Host ("Category    : {0}" -f $Result.category)
Write-Host ("State       : {0}" -f $Result.dispatch_state)
