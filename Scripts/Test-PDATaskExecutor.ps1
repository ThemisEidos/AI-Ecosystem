[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$RegistryScript = Join-Path $PSScriptRoot "PDA_ExecutorRegistry.ps1"
$SetExecutorScript = Join-Path $PSScriptRoot "Set-PDATaskExecutor.ps1"
$DispatchPrepScript = Join-Path $PSScriptRoot "Invoke-PDATaskDispatchPreparation.ps1"
$DispatchStatusScript = Join-Path $PSScriptRoot "Get-PDADispatchStatus.ps1"
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
if (Test-Path -Path $ParserPath -PathType Leaf) {
    . $ParserPath
}
if (Test-Path -Path $RegistryScript -PathType Leaf) {
    . $RegistryScript
}

if (-not (Test-Path -Path $SetExecutorScript -PathType Leaf)) {
    throw "Set-PDATaskExecutor missing: $SetExecutorScript"
}
if (-not (Test-Path -Path $DispatchPrepScript -PathType Leaf)) {
    throw "Invoke-PDATaskDispatchPreparation missing: $DispatchPrepScript"
}
if (-not (Test-Path -Path $DispatchStatusScript -PathType Leaf)) {
    throw "Get-PDADispatchStatus missing: $DispatchStatusScript"
}

$TempRoot = Join-Path $Root "PDA-Tasks\temp\dispatch-executor-tests"
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

function New-TestTaskFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [string]$Category
    )

    $Path = Join-Path $TempRoot "$Name.json"
    $Task = [pscustomobject]@{
        task_id = [guid]::NewGuid().ToString()
        created = (Get-Date).ToUniversalTime().ToString("o")
        command = $Command
        message = $Message
        category = $Category
        project = "AI Ecosystem"
        status = "approved"
        approved = $true
        approval_decision = "approved"
        approved_at = (Get-Date).ToUniversalTime().ToString("o")
        allowed_files = @("Scripts/*")
        required_tests = @("Scripts/Test-PDATaskExecutor.ps1")
        stop_conditions = @("Failed validation", "Policy violation", "Secret exposure")
        commit_message = "feat: test dispatch package"
    }
    $Task | ConvertTo-Json -Depth 20 | Set-Content -Path $Path -Encoding UTF8
    return $Path
}

$Issues = New-Object System.Collections.Generic.List[string]
$Results = New-Object System.Collections.Generic.List[object]

$Cases = @(
    [pscustomobject]@{ name = "category1 research"; task_type = "research"; category = "category_1"; expected_executor = "gemini-cli"; should_allow = $true; requires_approval = $true }
    [pscustomobject]@{ name = "category2 research"; task_type = "research"; category = "category_2"; expected_executor = "research-worker"; should_allow = $true; requires_approval = $true }
    [pscustomobject]@{ name = "category2 notebooklm blocked"; task_type = "knowledge_management"; category = "category_2"; expected_executor = "notebooklm"; should_allow = $false; requires_approval = $true }
    [pscustomobject]@{ name = "coding"; task_type = "coding"; category = "category_1"; expected_executor = "codex"; should_allow = $true; requires_approval = $true }
    [pscustomobject]@{ name = "reporting"; task_type = "reporting"; category = "category_1"; expected_executor = "reporter-worker"; should_allow = $true; requires_approval = $true }
    [pscustomobject]@{ name = "review"; task_type = "review"; category = "category_1"; expected_executor = "review-worker"; should_allow = $true; requires_approval = $true }
    [pscustomobject]@{ name = "planning"; task_type = "planning"; category = "category_1"; expected_executor = "planner-worker"; should_allow = $true; requires_approval = $true }
    [pscustomobject]@{ name = "automation"; task_type = "automation"; category = "category_1"; expected_executor = "n8n"; should_allow = $true; requires_approval = $true }
)

foreach ($Case in $Cases) {
    $Recommendation = Get-PDAExecutorRecommendation -TaskType $Case.task_type -Category $Case.category -Root $Root -RequiresLocalOnly:($Case.category -eq "category_2")
    $CaseIssues = New-Object System.Collections.Generic.List[string]
    $Passed = $true

    if ([bool]$Recommendation.allowed -ne [bool]$Case.should_allow) {
        $Passed = $false
        $CaseIssues.Add("Expected allowed=$($Case.should_allow) but got $($Recommendation.allowed).")
    }

    if ($Case.should_allow -and [string]$Recommendation.recommended_executor -ne [string]$Case.expected_executor) {
        $Passed = $false
        $CaseIssues.Add("Expected executor '$($Case.expected_executor)' but got '$($Recommendation.recommended_executor)'.")
    }

    if ([bool]$Recommendation.approval_required -ne [bool]$Case.requires_approval) {
        $Passed = $false
        $CaseIssues.Add("Expected approval_required=$($Case.requires_approval) but got $($Recommendation.approval_required).")
    }

    $Results.Add([pscustomobject]@{
        name = $Case.name
        passed = $Passed
        recommended_executor = [string]$Recommendation.recommended_executor
        allowed = [bool]$Recommendation.allowed
        approval_required = [bool]$Recommendation.approval_required
        blocked_reason = [string]$Recommendation.blocked_reason
        routing_reason = [string]$Recommendation.routing_reason
        issues = @($CaseIssues)
    })

    foreach ($Issue in $CaseIssues) {
        $Issues.Add($Issue)
    }
}

$TaskPath = New-TestTaskFile -Name "approved-dispatch-task" -Command "/research" -Message "create a governed research dispatch package" -Category "category_1"
$UpdatedTask = & pwsh -NoProfile -File $SetExecutorScript -TaskPath $TaskPath -Executor "gemini-cli" -Category "category_1" -TaskType "research" -AsJson
$UpdatedTaskObj = $UpdatedTask | ConvertFrom-Json
if ([string]$UpdatedTaskObj.executor_name -ne "gemini-cli") {
    $Issues.Add("Set-PDATaskExecutor did not attach gemini-cli metadata.")
}

$DispatchResult = & pwsh -NoProfile -File $DispatchPrepScript -TaskPath $TaskPath -Root $Root -AsJson -NoThrow
$DispatchObj = $DispatchResult | ConvertFrom-Json
if ([string]$DispatchObj.status -ne "pass") {
    $Issues.Add("Dispatch preparation did not complete successfully.")
}
if (-not (Test-Path -LiteralPath ([string]$DispatchObj.package_path) -PathType Leaf)) {
    $Issues.Add("Dispatch package file was not created.")
}
if (-not (Test-Path -LiteralPath ([string]$DispatchObj.prompt_path) -PathType Leaf)) {
    $Issues.Add("Dispatch prompt file was not created.")
}

$Status = & pwsh -NoProfile -File $DispatchStatusScript -Root $Root -AsJson -NoThrow
$StatusObj = $Status | ConvertFrom-Json
if (-not ($StatusObj.PSObject.Properties.Name -contains "counts")) {
    $Issues.Add("Dispatch status did not return counts.")
}
if (-not ($StatusObj.PSObject.Properties.Name -contains "registry")) {
    $Issues.Add("Dispatch status did not expose registry data.")
}

$FinalStatus = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
$StatusExecutorCount = if ($StatusObj.PSObject.Properties.Name -contains "registry" -and $StatusObj.registry.PSObject.Properties.Name -contains "executor_count") { [int]$StatusObj.registry.executor_count } else { 0 }
$StatusCounts = if ($StatusObj.PSObject.Properties.Name -contains "counts") { $StatusObj.counts } else { $null }
$PassedCaseCount = @($Results | Where-Object { $_.passed }).Count
$FailedCaseCount = @($Results | Where-Object { -not $_.passed }).Count
$DispatchSummary = [pscustomobject]@{
    status = [string]$DispatchObj.status
    executor_name = [string]$DispatchObj.executor_name
    package_path = [string]$DispatchObj.package_path
    prompt_path = [string]$DispatchObj.prompt_path
    summary_path = [string]$DispatchObj.summary_path
    dispatch_status = [string]$DispatchObj.dispatch_status
}
$StatusReport = [pscustomobject]@{
    status = [string]$StatusObj.status
    executor_count = $StatusExecutorCount
    counts = $StatusCounts
}

$Report = [pscustomobject]@{
    status = $FinalStatus
    case_count = @($Cases).Count
    passed_case_count = $PassedCaseCount
    failed_case_count = $FailedCaseCount
    dispatch_result = $DispatchSummary
    status_report = $StatusReport
    issues = @($Issues.ToArray())
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA executor dispatch validation failed."
    }
    return
}

Write-Host "[*] PDA executor dispatch tests"
Write-Host ("Status : {0}" -f $Report.status)
Write-Host ("Issues : {0}" -f @($Report.issues).Count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA executor dispatch validation failed."
}
