[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $ScriptRoot = $PSScriptRoot
}
elseif ($MyInvocation.MyCommand.Path) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    $ScriptRoot = (Get-Location).Path
}

$ScriptFolder = $ScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $ScriptFolder "COOPER_ConversationalRouter.ps1") -PathType Leaf)) {
    $CandidateScriptFolder = Join-Path $ScriptRoot "Scripts"
    if (Test-Path -LiteralPath (Join-Path $CandidateScriptFolder "COOPER_ConversationalRouter.ps1") -PathType Leaf) {
        $ScriptFolder = $CandidateScriptFolder
    }
}

$Root = Split-Path -Parent $ScriptFolder
$RouterScript = Join-Path $ScriptFolder "COOPER_ConversationalRouter.ps1"
$WorkflowScript = Join-Path $ScriptFolder "Invoke-COOPERCodexTaskGenerator.ps1"
$ReviewScript = Join-Path $ScriptFolder "Resolve-COOPERWorkflowReview.ps1"
$MemoryScript = Join-Path $ScriptFolder "Update-COOPERProjectMemory.ps1"
$SkillsScript = Join-Path $ScriptFolder "Update-COOPERWorkflowSkills.ps1"
$MemoryStatePath = Join-Path $Root "State\COOPER_ProjectMemory.json"
$SkillsStatePath = Join-Path $Root "State\COOPER_Skills.json"
$TempRoot = Join-Path $Root "tmp\cooper-codex-task-generator-tests"
$TempMemoryState = Join-Path $TempRoot "COOPER_ProjectMemory.failed-review.json"
$TempSkillsState = Join-Path $TempRoot "COOPER_Skills.failed-review.json"

. $RouterScript

if (-not (Test-Path -LiteralPath $TempRoot -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
}

foreach ($Path in @($MemoryStatePath, $SkillsStatePath)) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Remove-Item -LiteralPath $Path -Force
    }
}

foreach ($Path in @($TempMemoryState, $TempSkillsState)) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Remove-Item -LiteralPath $Path -Force
    }
}

$Request = "Create a Codex task to add Docker administration documentation to the Linux & Infrastructure collection."
$Route = Resolve-PDAConversationalRoute -Text $Request -Root $Root
$Result = & (Get-Command $WorkflowScript) -Text $Request -Approved -Root $Root

$Issues = New-Object System.Collections.Generic.List[string]

if ([string]$Route.route_type -ne "codex_task_generator") {
    $Issues.Add("Request did not route to codex_task_generator.")
}

foreach ($Field in @("success", "workflow_id", "tool_id", "task_path", "routed_tool", "approval_decision", "workbench_result", "workflow_review", "response_text", "source_of_truth")) {
    if ($Result.PSObject.Properties.Name -notcontains $Field) {
        $Issues.Add("Workflow result is missing '$Field'.")
    }
}

if ([bool]$Result.success -ne $true) {
    $Issues.Add("Workflow did not succeed.")
}
if ([string]$Result.workflow_id -ne "WF-002") {
    $Issues.Add("Workflow id mismatch.")
}
if ([string]$Result.tool_id -ne "codex_task_launcher") {
    $Issues.Add("Workflow did not use the codex task launcher tool.")
}

$TaskPath = [string]$Result.task_path
if ([string]::IsNullOrWhiteSpace($TaskPath)) {
    $Issues.Add("Workflow did not return a task path.")
}
else {
    $ExpectedTaskRoot = [System.IO.Path]::GetFullPath((Join-Path $Root "Codex_Tasks"))
    $ExpectedTaskPrefix = $ExpectedTaskRoot.TrimEnd('\') + '\'
    $ResolvedTaskPath = [System.IO.Path]::GetFullPath($TaskPath)
    if (-not ($ResolvedTaskPath -eq $ExpectedTaskRoot -or $ResolvedTaskPath.StartsWith($ExpectedTaskPrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
        $Issues.Add("Task path is not inside Codex_Tasks.")
    }
    if (-not (Test-Path -LiteralPath $ResolvedTaskPath -PathType Leaf)) {
        $Issues.Add("Expected markdown file was not created.")
    }
    else {
        $Content = Get-Content -LiteralPath $ResolvedTaskPath -Raw
        if ($Content -notmatch '(?m)^#\s+(?!Task Title$).+') {
            $Issues.Add("Task markdown is missing a concrete title.")
        }
        foreach ($Section in @("Objective", "Background", "Current State", "Required Work", "Constraints", "Validation", "Definition of Done")) {
            if ($Content -notmatch ("(?m)^##\s+{0}\s*$" -f [regex]::Escape($Section))) {
                $Issues.Add("Task markdown is missing '$Section'.")
            }
        }
        if ($Content -notmatch '(?i)Docker' -or $Content -notmatch '(?i)Linux & Infrastructure') {
            $Issues.Add("Task markdown does not reflect the requested implementation context.")
        }
    }
}

$WorkflowReview = $Result.workflow_review
if ($null -eq $WorkflowReview) {
    $Issues.Add("Workflow review did not return a result.")
}
else {
    if ([string]$WorkflowReview.status -ne "pass") {
        $Issues.Add("Workflow review did not pass.")
    }
    if ([bool]$WorkflowReview.review_passed -ne $true) {
        $Issues.Add("Workflow review did not mark the workflow as reviewed and passed.")
    }
    if ($WorkflowReview.PSObject.Properties.Name -contains "issues" -and @($WorkflowReview.issues | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
        $Issues.Add("Workflow review reported unexpected issues.")
    }
}

$RoutedTool = $Result.routed_tool
if ($null -eq $RoutedTool -or [string]$RoutedTool.status -ne "pass") {
    $Issues.Add("Registry lookup did not succeed.")
}
elseif ([string]$RoutedTool.selected_tool -ne "codex_task_launcher") {
    $Issues.Add("Registry lookup did not select codex_task_launcher.")
}
elseif ([bool]$RoutedTool.execution_allowed -ne $true) {
    $Issues.Add("Registry lookup did not allow execution.")
}

$ApprovalDecision = $Result.approval_decision
if ($null -eq $ApprovalDecision) {
    $Issues.Add("Approval gate did not return a decision.")
}
else {
    if ([bool]$ApprovalDecision.allowed -ne $true) {
        $Issues.Add("Approval gate did not allow the tool.")
    }
    if ([bool]$ApprovalDecision.blocked -ne $false) {
        $Issues.Add("Approval gate unexpectedly blocked the tool.")
    }
    if ([bool]$ApprovalDecision.execution_authorized -ne $true) {
        $Issues.Add("Approval gate did not authorize execution.")
    }
    if ([string]$ApprovalDecision.reason -notmatch '(?i)Level 4 requires user approval') {
        $Issues.Add("Approval gate reason did not reflect the governed approval path.")
    }
}

$WorkbenchResult = $Result.workbench_result
if ($null -eq $WorkbenchResult) {
    $Issues.Add("Workbench did not return a result.")
}
else {
    if ([bool]$WorkbenchResult.success -ne $true) {
        $Issues.Add("Workbench did not succeed.")
    }
    if ([string]$WorkbenchResult.action_taken -ne "create_markdown_task") {
        $Issues.Add("Workbench did not execute the task creation action.")
    }
    if ($WorkbenchResult.output -and $WorkbenchResult.output.PSObject.Properties.Name -contains "task_exists" -and [bool]$WorkbenchResult.output.task_exists -ne $true) {
        $Issues.Add("Workbench output did not report the task as created.")
    }
}

if (-not (Test-Path -LiteralPath $MemoryStatePath -PathType Leaf)) {
    $Issues.Add("Project memory state file was not created.")
}
else {
    $MemoryState = Get-Content -LiteralPath $MemoryStatePath -Raw | ConvertFrom-Json
    if ($null -eq $MemoryState) {
        $Issues.Add("Project memory state could not be parsed.")
    }
    else {
        $OperationalWorkflows = @($MemoryState.operational_workflows | ForEach-Object { [string]$_ })
        if ($OperationalWorkflows -notcontains "WF-002") {
            $Issues.Add("Project memory did not mark WF-002 as operational.")
        }
        if ($null -eq $MemoryState.last_successful_workflow -or [string]$MemoryState.last_successful_workflow.workflow_id -ne "WF-002") {
            $Issues.Add("Project memory did not record WF-002 as the last successful workflow.")
        }
    }
}

if (-not (Test-Path -LiteralPath $SkillsStatePath -PathType Leaf)) {
    $Issues.Add("Skills state file was not created.")
}
else {
    $SkillsState = Get-Content -LiteralPath $SkillsStatePath -Raw | ConvertFrom-Json
    if ($null -eq $SkillsState) {
        $Issues.Add("Skills state could not be parsed.")
    }
    else {
        $SkillEntry = @($SkillsState.skills | Where-Object { [string]$_.workflow_id -eq "WF-002" } | Select-Object -First 1)
        if ($SkillEntry.Count -eq 0) {
            $Issues.Add("Skills state did not record WF-002.")
        }
        else {
            $WF002Skill = $SkillEntry[0]
            if ([string]$WF002Skill.status -ne "operational") {
                $Issues.Add("WF-002 skill was not promoted to operational.")
            }
            if ([int]$WF002Skill.successful_run_count -lt 1) {
                $Issues.Add("WF-002 skill did not record a successful run.")
            }
        }
    }
}

$BadTaskPath = Join-Path $TempRoot "TASK-00000000-000000-bad-task.md"
@(
    "# Broken Task"
    ""
    "## Objective"
    "Test failure handling."
    ""
    "## Background"
    "Synthetic malformed task."
) | Set-Content -LiteralPath $BadTaskPath -Encoding UTF8

$BadReview = & (Get-Command $ReviewScript) -WorkflowId "WF-002" -WorkflowResult ([pscustomobject]@{
    success = $true
    workflow_id = "WF-002"
    result_artifact_path = $BadTaskPath
    output_type = "markdown_file"
}) -RequestText $Request -ExpectedOutputType "markdown_file" -ExpectedOutputPath $BadTaskPath

if ([string]$BadReview.status -ne "fail") {
    $Issues.Add("WF-002 review did not fail for malformed markdown.")
}
if ([bool]$BadReview.review_passed -ne $false) {
    $Issues.Add("WF-002 review incorrectly passed malformed markdown.")
}

$FailedPromotion = & (Get-Command $MemoryScript) -WorkflowId "WF-002" -ReviewResult $BadReview -RequestText $Request -OutputPath $BadTaskPath -StatePath $TempMemoryState
if ([string]$FailedPromotion.status -ne "fail") {
    $Issues.Add("Failed review did not stay in fail status for project memory.")
}
if ($FailedPromotion.project_memory -and @($FailedPromotion.project_memory.operational_workflows) -contains "WF-002") {
    $Issues.Add("Failed review incorrectly promoted WF-002 in project memory.")
}

$FailedSkillPromotion = & (Get-Command $SkillsScript) -WorkflowId "WF-002" -ReviewResult $BadReview -ExampleRequest $Request -ExampleOutput ([System.IO.Path]::GetFileName($BadTaskPath)) -SkillName "Codex Task Generator" -StatePath $TempSkillsState
if ([string]$FailedSkillPromotion.status -ne "fail") {
    $Issues.Add("Failed review did not stay in fail status for skills.")
}
if ($FailedSkillPromotion.promoted -ne $false) {
    $Issues.Add("Failed review incorrectly promoted the skill.")
}

if (-not (Test-Path -LiteralPath $TempMemoryState -PathType Leaf)) {
    $Issues.Add("Failed-review memory state file was not written.")
}
else {
    $TempMemory = Get-Content -LiteralPath $TempMemoryState -Raw | ConvertFrom-Json
    $TempOperational = @($TempMemory.operational_workflows | ForEach-Object { [string]$_ })
    if ($TempOperational -contains "WF-002") {
        $Issues.Add("Failed review promoted WF-002 in the temp project memory state.")
    }
}

if (-not (Test-Path -LiteralPath $TempSkillsState -PathType Leaf)) {
    $Issues.Add("Failed-review skills state file was not written.")
}
else {
    $TempSkills = Get-Content -LiteralPath $TempSkillsState -Raw | ConvertFrom-Json
    $TempSkill = @($TempSkills.skills | Where-Object { [string]$_.workflow_id -eq "WF-002" } | Select-Object -First 1)
    if ($TempSkill.Count -gt 0 -and [string]$TempSkill[0].status -eq "operational") {
        $Issues.Add("Failed review promoted WF-002 to operational in the temp skills state.")
    }
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    task_path = $TaskPath
    route_type = [string]$Route.route_type
    workflow = $Result
    bad_review = $BadReview
    failed_promotion = $FailedPromotion
    failed_skill_promotion = $FailedSkillPromotion
    issues = @($Issues)
}

Write-Host "[*] COOPER Codex task generator workflow test"
Write-Host ("Status   : {0}" -f $Report.status)
Write-Host ("Task     : {0}" -f $Report.task_path)
Write-Host ("Route    : {0}" -f $Report.route_type)

if ($Report.status -ne "pass") {
    foreach ($Issue in @($Report.issues)) {
        Write-Host ("[FAIL] {0}" -f $Issue)
    }
    exit 1
}

Write-Host "[PASS] WF-002 Codex Task Generator workflow validated."
exit 0
