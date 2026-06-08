[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TaskPath,

    [Parameter(Mandatory = $false)]
    [string]$Executor = "",

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
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
$TaskId = if ($Task.PSObject.Properties.Name -contains "task_id") { [string]$Task.task_id } else { [guid]::NewGuid().ToString() }
$ResolvedCategory = if ($Task.PSObject.Properties.Name -contains "category" -and -not [string]::IsNullOrWhiteSpace([string]$Task.category)) { [string]$Task.category } else { "category_1" }
$ResolvedTaskType = if ($Task.PSObject.Properties.Name -contains "task_type" -and -not [string]::IsNullOrWhiteSpace([string]$Task.task_type)) { [string]$Task.task_type } elseif ($Task.PSObject.Properties.Name -contains "intent" -and -not [string]::IsNullOrWhiteSpace([string]$Task.intent)) { [string]$Task.intent } else { [string]$Task.command }
$ResolvedPreferredOutput = if ($Task.PSObject.Properties.Name -contains "requested_output") { [string]$Task.requested_output } else { "" }

$ApprovalDecision = ""
if ($Task.PSObject.Properties.Name -contains "approved") {
    $ApprovalDecision = if ([bool]$Task.approved) { "approved" } else { "pending" }
}
elseif ($Task.PSObject.Properties.Name -contains "approval_decision" -and -not [string]::IsNullOrWhiteSpace([string]$Task.approval_decision)) {
    $ApprovalDecision = [string]$Task.approval_decision
}

if ($ApprovalDecision -ne "approved" -and $ApprovalDecision -ne "allow") {
    $Result = [pscustomobject]@{
        status            = "blocked"
        task_id           = $TaskId
        task_path         = $TaskPath
        executor_name     = [string]$Executor
        dispatch_status   = "awaiting_approval"
        blocked_reason    = "Task has not been approved for dispatch preparation."
        dispatch_package_path = ""
        dispatch_summary_path  = ""
        dispatch_prompt_path    = ""
        approval_decision = $ApprovalDecision
    }

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        if (-not $NoThrow) {
            throw $Result.blocked_reason
        }
        return
    }

    Write-Host "[BLOCKED] $($Result.blocked_reason)"
    if (-not $NoThrow) {
        throw $Result.blocked_reason
    }
    return
}

$SelectedExecutor = $Executor
if ([string]::IsNullOrWhiteSpace($SelectedExecutor) -and (Get-Command -Name Get-PDAExecutorRecommendation -ErrorAction SilentlyContinue)) {
    $Recommendation = Get-PDAExecutorRecommendation -TaskType $ResolvedTaskType -Category $ResolvedCategory -PreferredOutput $ResolvedPreferredOutput -RequiresLocalOnly:($ResolvedCategory -in @("category_2", "restricted_local")) -Text ([string]$Task.message) -Root $Root
    $SelectedExecutor = [string]$Recommendation.recommended_executor
}

if ([string]::IsNullOrWhiteSpace($SelectedExecutor)) {
    throw "Executor could not be determined for dispatch preparation."
}

$ExecutorCheck = Test-PDAExecutorAllowedForCategory -ExecutorName $SelectedExecutor -Category $ResolvedCategory -RequiresLocalOnly:($ResolvedCategory -in @("category_2", "restricted_local")) -Root $Root
if (-not $ExecutorCheck.allowed) {
    $Result = [pscustomobject]@{
        status              = "blocked"
        task_id             = $TaskId
        task_path           = $TaskPath
        executor_name       = [string]$SelectedExecutor
        dispatch_status     = "blocked"
        blocked_reason      = [string]$ExecutorCheck.blocked_reason
        dispatch_package_path = ""
        dispatch_summary_path  = ""
        dispatch_prompt_path    = ""
    }

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        if (-not $NoThrow) {
            throw $Result.blocked_reason
        }
        return
    }

    Write-Host "[BLOCKED] $($Result.blocked_reason)"
    if (-not $NoThrow) {
        throw $Result.blocked_reason
    }
    return
}

$Task | Add-Member -NotePropertyName executor_name -NotePropertyValue [string]$ExecutorCheck.executor_name -Force
$Task | Add-Member -NotePropertyName executor_display_name -NotePropertyValue [string]$ExecutorCheck.display_name -Force
$Task | Add-Member -NotePropertyName executor_type -NotePropertyValue [string]$ExecutorCheck.executor_type -Force
$Task | Add-Member -NotePropertyName executor_risk_level -NotePropertyValue [string]$ExecutorCheck.risk_level -Force
$Task | Add-Member -NotePropertyName executor_requires_approval -NotePropertyValue [bool]$ExecutorCheck.requires_approval -Force
$Task | Add-Member -NotePropertyName executor_supports_category2 -NotePropertyValue [bool]$ExecutorCheck.supports_category2 -Force
$Task | Add-Member -NotePropertyName executor_supports_local_only -NotePropertyValue [bool]$ExecutorCheck.supports_local_only -Force
$Task | Add-Member -NotePropertyName executor_dispatch_method -NotePropertyValue [string]$ExecutorCheck.dispatch_method -Force
$Task | Add-Member -NotePropertyName dispatch_state -NotePropertyValue "prepared" -Force
$Task | Add-Member -NotePropertyName dispatch_status -NotePropertyValue "prepared" -Force
$Task | Add-Member -NotePropertyName dispatch_ready -NotePropertyValue $true -Force
$Task | Add-Member -NotePropertyName dispatch_prepared_at -NotePropertyValue (Get-Date).ToUniversalTime().ToString("o") -Force
$Task | Add-Member -NotePropertyName dispatch_executor -NotePropertyValue [string]$ExecutorCheck.executor_name -Force
$Task | Add-Member -NotePropertyName approval_required_for_dispatch -NotePropertyValue [bool]$ExecutorCheck.requires_approval -Force

$Task | ConvertTo-Json -Depth 24 | Set-Content -Path $TaskPath -Encoding UTF8

$DispatchRoot = Join-Path $Root "PDA-Tasks\staging\dispatch"
New-Item -ItemType Directory -Force -Path $DispatchRoot | Out-Null

$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
$SafeExecutor = [string]$ExecutorCheck.executor_name -replace '[^a-z0-9_-]', '-'
$PackageDir = Join-Path $DispatchRoot ("{0}-{1}-{2}" -f $TaskId, $SafeExecutor, $Timestamp)
New-Item -ItemType Directory -Force -Path $PackageDir | Out-Null

$PromptPath = Join-Path $PackageDir "dispatch-prompt.md"
$SummaryPath = Join-Path $PackageDir "dispatch-summary.md"
$PackagePath = Join-Path $PackageDir "dispatch-request.json"

$AllowedFiles = @()
if ($Task.PSObject.Properties.Name -contains "allowed_files") {
    $AllowedFiles = @($Task.allowed_files)
}

$RequiredTests = @()
if ($Task.PSObject.Properties.Name -contains "required_tests") {
    $RequiredTests = @($Task.required_tests)
}

$StopConditions = @()
if ($Task.PSObject.Properties.Name -contains "stop_conditions") {
    $StopConditions = @($Task.stop_conditions)
}

$CommitMessage = if ($Task.PSObject.Properties.Name -contains "commit_message") { [string]$Task.commit_message } else { "" }

$PromptLines = @(
    "# PDA Dispatch Request"
    ""
    "Task ID: $TaskId"
    "Executor: $($ExecutorCheck.executor_name)"
    "Display Name: $($ExecutorCheck.display_name)"
    "Risk Level: $($ExecutorCheck.risk_level)"
    "Approval Required: $([bool]$ExecutorCheck.requires_approval)"
    ""
    "## Task"
    ""
    "Command: $([string]$Task.command)"
    "Task Type: $ResolvedTaskType"
    "Category: $ResolvedCategory"
    "Summary: $(if ($Task.PSObject.Properties.Name -contains 'message') { [string]$Task.message } else { '' })"
    ""
    "## Allowed Files"
)

if ($AllowedFiles.Count -gt 0) {
    $PromptLines += @($AllowedFiles | ForEach-Object { "- $_" })
}
else {
    $PromptLines += "- No explicit allowlist provided."
}

$PromptLines += ""
$PromptLines += "## Required Tests"
if ($RequiredTests.Count -gt 0) {
    $PromptLines += @($RequiredTests | ForEach-Object { "- $_" })
}
else {
    $PromptLines += "- No explicit test list provided."
}

$PromptLines += ""
$PromptLines += "## Stop Conditions"
if ($StopConditions.Count -gt 0) {
    $PromptLines += @($StopConditions | ForEach-Object { "- $_" })
}
else {
    $PromptLines += "- Stop on failed tests, blocked policy checks, secret exposure, or unsafe file changes."
}

$PromptLines += ""
$PromptLines += "## Expected Output"
$PromptLines += "- JSON execution summary"
$PromptLines += "- Markdown summary"
$PromptLines += "- Result artifact path"
$PromptLines += ""
$PromptLines += "## Commit Message"
$PromptLines += $(if (-not [string]::IsNullOrWhiteSpace($CommitMessage)) { $CommitMessage } else { "No commit message specified." })

$SummaryLines = @(
    "# PDA Dispatch Preparation Summary"
    ""
    "- Task ID: $TaskId"
    "- Executor: $($ExecutorCheck.executor_name)"
    "- Display Name: $($ExecutorCheck.display_name)"
    "- State: prepared"
    "- Approval Required: $([bool]$ExecutorCheck.requires_approval)"
    "- Package Directory: $PackageDir"
    "- Prompt Path: $PromptPath"
    "- Summary Path: $SummaryPath"
    "- Package Path: $PackagePath"
)

$Task | ConvertTo-Json -Depth 24 | Set-Content -Path $PackagePath -Encoding UTF8
$PromptLines -join "`r`n" | Set-Content -Path $PromptPath -Encoding UTF8
$SummaryLines -join "`r`n" | Set-Content -Path $SummaryPath -Encoding UTF8

$Result = [pscustomobject]@{
    status               = "pass"
    task_id              = $TaskId
    task_path            = $TaskPath
    executor_name        = [string]$ExecutorCheck.executor_name
    executor_display_name = [string]$ExecutorCheck.display_name
    approval_decision    = [string]$ApprovalDecision
    dispatch_status      = "prepared"
    dispatch_state       = "prepared"
    approval_required    = [bool]$ExecutorCheck.requires_approval
    package_directory    = $PackageDir
    package_path         = $PackagePath
    prompt_path          = $PromptPath
    summary_path         = $SummaryPath
    allowed_files        = @($AllowedFiles)
    required_tests       = @($RequiredTests)
    stop_conditions      = @($StopConditions)
    commit_message       = $CommitMessage
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] Dispatch package prepared:"
Write-Host ("Task ID           : {0}" -f $Result.task_id)
Write-Host ("Executor          : {0}" -f $Result.executor_name)
Write-Host ("Package directory  : {0}" -f $Result.package_directory)
Write-Host ("Prompt path       : {0}" -f $Result.prompt_path)
