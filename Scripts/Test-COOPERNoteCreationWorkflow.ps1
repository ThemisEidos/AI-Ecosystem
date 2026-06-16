[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$RouterScript = Join-Path $PSScriptRoot "COOPER_ConversationalRouter.ps1"
$WorkflowScript = Join-Path $PSScriptRoot "Invoke-COOPERNoteCreationCommand.ps1"
$MemoryStatePath = Join-Path $Root "State\COOPER_ProjectMemory.json"
$SkillsStatePath = Join-Path $Root "State\COOPER_Skills.json"
$ExpectedRegistryPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\Config\general_tool_registry.yaml"))
$ExpectedNotePath = [System.IO.Path]::GetFullPath((Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Drafts\wf-005-note-creation.md"))

. $RouterScript

if (Test-Path -LiteralPath $ExpectedNotePath -PathType Leaf) {
    Remove-Item -LiteralPath $ExpectedNotePath -Force
}
if (Test-Path -LiteralPath $MemoryStatePath -PathType Leaf) {
    Remove-Item -LiteralPath $MemoryStatePath -Force
}
if (Test-Path -LiteralPath $SkillsStatePath -PathType Leaf) {
    Remove-Item -LiteralPath $SkillsStatePath -Force
}

$Message = "Create an Obsidian note for WF-005."
$Route = Resolve-PDAConversationalRoute -Text $Message -Root $Root
$Result = & $WorkflowScript -Text $Message -Approved -Root $Root

$Issues = New-Object System.Collections.Generic.List[string]

if ([string]$Route.route_type -ne "note_creation") {
    $Issues.Add("Router did not classify the message as note_creation.")
}
if ([string]$Route.recommended_command -ne "Create Obsidian note") {
    $Issues.Add("Router did not recommend the note creation command.")
}

foreach ($Field in @("success", "workflow_id", "tool_id", "note_path", "routed_tool", "approval_decision", "workbench_result", "response_text", "source_of_truth")) {
    if ($Result.PSObject.Properties.Name -notcontains $Field) {
        $Issues.Add("Workflow result is missing '$Field'.")
    }
}

if ($Result.PSObject.Properties.Name -notcontains "workflow_review") {
    $Issues.Add("Workflow result is missing 'workflow_review'.")
}

if ([bool]$Result.success -ne $true) {
    $Issues.Add("Workflow did not succeed.")
}
if ([string]$Result.workflow_id -ne "WF-005") {
    $Issues.Add("Workflow id mismatch.")
}
if ([string]$Result.tool_id -ne "obsidian_note_writer") {
    $Issues.Add("Workflow did not use the obsidian note writer tool.")
}
if ([string]$Result.note_path -ne $ExpectedNotePath) {
    $Issues.Add("Unexpected note path '$([string]$Result.note_path)'.")
}

if (-not (Test-Path -LiteralPath $ExpectedNotePath -PathType Leaf)) {
    $Issues.Add("Expected markdown file was not created.")
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
elseif ([string]$RoutedTool.registry_path -ne $ExpectedRegistryPath) {
    $Issues.Add("Registry lookup did not use the general registry.")
}
elseif ([string]$RoutedTool.selected_tool -ne "obsidian_note_writer") {
    $Issues.Add("Registry lookup did not select obsidian_note_writer.")
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
    if ([bool]$ApprovalDecision.approval_required -ne $true) {
        $Issues.Add("Approval gate did not mark the tool as approval required.")
    }
    if ([bool]$ApprovalDecision.execution_authorized -ne $true) {
        $Issues.Add("Approval gate did not authorize execution.")
    }
    if ([string]$ApprovalDecision.reason -notmatch '(?i)Level 2 requires user approval') {
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
    if ([string]$WorkbenchResult.action_taken -ne "create_markdown_note") {
        $Issues.Add("Workbench did not execute the note creation action.")
    }
    if ($WorkbenchResult.output -and $WorkbenchResult.output.PSObject.Properties.Name -contains "note_exists" -and [bool]$WorkbenchResult.output.note_exists -ne $true) {
        $Issues.Add("Workbench output did not report the note as created.")
    }
}

if (-not (Test-Path -LiteralPath $ExpectedNotePath -PathType Leaf)) {
    $Issues.Add("Final markdown file verification failed.")
}
else {
    $Content = Get-Content -LiteralPath $ExpectedNotePath -Raw
    foreach ($Pattern in @("WF-005", "WF-005 Note Creation", "Created by the governed COOPER note-creation workflow")) {
        if ($Content -notmatch [regex]::Escape($Pattern)) {
            $Issues.Add("Created note is missing '$Pattern'.")
        }
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
        if ($OperationalWorkflows -notcontains "WF-005") {
            $Issues.Add("Project memory did not mark WF-005 as operational.")
        }
        if ($null -eq $MemoryState.last_successful_workflow -or [string]$MemoryState.last_successful_workflow.workflow_id -ne "WF-005") {
            $Issues.Add("Project memory did not record WF-005 as the last successful workflow.")
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
        $SkillEntry = @($SkillsState.skills | Where-Object { [string]$_.workflow_id -eq "WF-005" } | Select-Object -First 1)
        if ($SkillEntry.Count -eq 0) {
            $Issues.Add("Skills state did not record WF-005.")
        }
        else {
            $WF005Skill = $SkillEntry[0]
            if ([string]$WF005Skill.status -ne "operational") {
                $Issues.Add("WF-005 skill was not promoted to operational.")
            }
            if ([int]$WF005Skill.successful_run_count -lt 1) {
                $Issues.Add("WF-005 skill did not record a successful run.")
            }
        }
    }
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    note_path = $ExpectedNotePath
    route_type = [string]$Route.route_type
    workflow = $Result
    issues = @($Issues)
}

Write-Host "[*] COOPER note creation workflow test"
Write-Host ("Status   : {0}" -f $Report.status)
Write-Host ("Note     : {0}" -f $Report.note_path)
Write-Host ("Route    : {0}" -f $Report.route_type)

if ($Report.status -ne "pass") {
    foreach ($Issue in @($Report.issues)) {
        Write-Host ("[FAIL] {0}" -f $Issue)
    }
    exit 1
}

Write-Host "[PASS] WF-005 note creation workflow validated."
exit 0
