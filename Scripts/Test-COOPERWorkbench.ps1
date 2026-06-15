[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$RouterScript = Join-Path $PSScriptRoot "Invoke-COOPERTool.ps1"
$ApprovalScript = Join-Path $PSScriptRoot "Resolve-COOPERApproval.ps1"
$WorkbenchScript = Join-Path $PSScriptRoot "Invoke-COOPERWorkbench.ps1"

function New-ApprovalDecisionFixture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolId,

        [Parameter(Mandatory = $true)]
        [string]$Workshop,

        [Parameter(Mandatory = $true)]
        [string]$WorkshopMode,

        [Parameter(Mandatory = $true)]
        [int]$PermissionLevel,

        [Parameter(Mandatory = $true)]
        [bool]$ApprovalRequired,

        [Parameter(Mandatory = $true)]
        [string]$ExecutorType,

        [Parameter(Mandatory = $true)]
        [bool]$Enabled,

        [Parameter(Mandatory = $true)]
        [bool]$Allowed,

        [Parameter(Mandatory = $true)]
        [bool]$Blocked,

        [Parameter(Mandatory = $true)]
        [string]$Reason,

        [Parameter(Mandatory = $true)]
        [bool]$RequiresUserApproval,

        [Parameter(Mandatory = $true)]
        [bool]$ExecutionAuthorized
    )

    [pscustomobject]@{
        tool_id = $ToolId
        workshop = $Workshop
        workshop_mode = $WorkshopMode
        permission_level = $PermissionLevel
        approval_required = $ApprovalRequired
        allowed = $Allowed
        blocked = $Blocked
        reason = $Reason
        requires_user_approval = $RequiresUserApproval
        execution_authorized = $ExecutionAuthorized
        executor_type = $ExecutorType
        enabled = $Enabled
    }
}

function Invoke-WorkbenchCase {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ApprovalDecision,

        [switch]$DryRun
    )

    & $WorkbenchScript -ApprovalDecision $ApprovalDecision -DryRun:$DryRun
}

$StatusRouter = & $RouterScript -ToolId "status_summary" -Workshop "Open Workshop" -WorkshopMode "Open Workshop" -DryRun
$StatusApproval = & $ApprovalScript -RoutedToolResult $StatusRouter

$Cases = @(
    [pscustomobject]@{
        name = "dry run never executes"
        decision = $StatusApproval
        dry_run = $true
        expect_success = $true
        expect_action = "dry_run_status_check"
        expect_reason_like = "Dry run only"
    }
    [pscustomobject]@{
        name = "blocked decision does not execute"
        decision = (New-ApprovalDecisionFixture -ToolId "blocked_tool" -Workshop "Open Workshop" -WorkshopMode "Open Workshop" -PermissionLevel 2 -ApprovalRequired $true -ExecutorType "powershell" -Enabled $true -Allowed $false -Blocked $true -Reason "Blocked by policy." -RequiresUserApproval $true -ExecutionAuthorized $false)
        dry_run = $false
        expect_success = $false
        expect_action = "blocked"
        expect_reason_like = "Blocked by policy"
    }
    [pscustomobject]@{
        name = "not authorized does not execute"
        decision = (New-ApprovalDecisionFixture -ToolId "blocked_tool" -Workshop "Open Workshop" -WorkshopMode "Open Workshop" -PermissionLevel 2 -ApprovalRequired $true -ExecutorType "powershell" -Enabled $true -Allowed $true -Blocked $false -Reason "Approval required." -RequiresUserApproval $true -ExecutionAuthorized $false)
        dry_run = $false
        expect_success = $false
        expect_action = "not_executed"
        expect_reason_like = "Approval required"
    }
    [pscustomobject]@{
        name = "level 5 does not execute"
        decision = (New-ApprovalDecisionFixture -ToolId "dangerous_tool" -Workshop "Open Workshop" -WorkshopMode "Open Workshop" -PermissionLevel 5 -ApprovalRequired $true -ExecutorType "powershell" -Enabled $true -Allowed $false -Blocked $true -Reason "Level 5 actions are blocked by default." -RequiresUserApproval $false -ExecutionAuthorized $false)
        dry_run = $false
        expect_success = $false
        expect_action = "blocked"
        expect_reason_like = "Level 5"
    }
    [pscustomobject]@{
        name = "private external executor does not execute"
        decision = (New-ApprovalDecisionFixture -ToolId "private_external_tool" -Workshop "Private Workshop" -WorkshopMode "Private Workshop" -PermissionLevel 2 -ApprovalRequired $true -ExecutorType "llm_api" -Enabled $true -Allowed $false -Blocked $true -Reason "Private Workshop must not execute external executor types." -RequiresUserApproval $true -ExecutionAuthorized $false)
        dry_run = $false
        expect_success = $false
        expect_action = "blocked"
        expect_reason_like = "Private Workshop must not execute external executor types"
    }
    [pscustomobject]@{
        name = "approved harmless status action succeeds"
        decision = $StatusApproval
        dry_run = $false
        expect_success = $true
        expect_action = "local_status_check"
        expect_reason_like = "Local read-only status check completed"
    }
    [pscustomobject]@{
        name = "unsupported tool id fails clearly"
        decision = (New-ApprovalDecisionFixture -ToolId "unsupported_tool" -Workshop "Open Workshop" -WorkshopMode "Open Workshop" -PermissionLevel 1 -ApprovalRequired $false -ExecutorType "local_read" -Enabled $true -Allowed $true -Blocked $false -Reason "OK" -RequiresUserApproval $false -ExecutionAuthorized $true)
        dry_run = $false
        expect_success = $false
        expect_action = "unsupported"
        expect_reason_like = "Unsupported workbench tool id"
    }
)

$Results = @()
$Passed = 0
$Failed = 0

foreach ($Case in $Cases) {
    $Result = Invoke-WorkbenchCase -ApprovalDecision $Case.decision -DryRun:$Case.dry_run
    $Issues = New-Object System.Collections.Generic.List[string]

    foreach ($Field in @(
        "success",
        "dry_run",
        "tool_id",
        "workshop",
        "workshop_mode",
        "executor_type",
        "action_taken",
        "output",
        "reason"
    )) {
        if ($Result.PSObject.Properties.Name -notcontains $Field) {
            $Issues.Add("Missing required field '$Field'.")
        }
    }

    if ([bool]$Result.success -ne [bool]$Case.expect_success) {
        $Issues.Add("Expected success '$($Case.expect_success)' but got '$($Result.success)'.")
    }

    if ([string]$Result.action_taken -ne [string]$Case.expect_action) {
        $Issues.Add("Expected action_taken '$($Case.expect_action)' but got '$($Result.action_taken)'.")
    }

    if ([string]$Result.reason -notmatch [regex]::Escape([string]$Case.expect_reason_like)) {
        $Issues.Add("Expected reason to contain '$($Case.expect_reason_like)' but got '$([string]$Result.reason)'.")
    }

    if ($Case.name -eq "dry run never executes" -and [bool]$Result.dry_run -ne $true) {
        $Issues.Add("Dry run flag was not preserved.")
    }

    if ($Case.name -eq "approved harmless status action succeeds") {
        if ($Result.output.PSObject.Properties.Name -notcontains "workspace_root") {
            $Issues.Add("Status action output must include workspace_root.")
        }
        if ($Result.output.PSObject.Properties.Name -notcontains "registry_exists") {
            $Issues.Add("Status action output must include registry_exists.")
        }
    }

    $CasePassed = ($Issues.Count -eq 0)
    if ($CasePassed) {
        $Passed++
    }
    else {
        $Failed++
    }

    $Results += [pscustomobject]@{
        name = $Case.name
        passed = $CasePassed
        success = [bool]$Result.success
        dry_run = [bool]$Result.dry_run
        tool_id = [string]$Result.tool_id
        workshop = [string]$Result.workshop
        workshop_mode = [string]$Result.workshop_mode
        executor_type = [string]$Result.executor_type
        action_taken = [string]$Result.action_taken
        reason = [string]$Result.reason
        issues = @($Issues)
    }
}

$Report = [pscustomobject]@{
    status = if ($Failed -eq 0) { "pass" } else { "fail" }
    test_case_count = @($Cases).Count
    passed_count = $Passed
    failed_count = $Failed
    results = @($Results)
}

Write-Host "[*] COOPER workbench tests"
Write-Host ("Status     : {0}" -f $Report.status)
Write-Host ("Test cases : {0}" -f $Report.test_case_count)
Write-Host ("Passed     : {0}" -f $Report.passed_count)
Write-Host ("Failed     : {0}" -f $Report.failed_count)

foreach ($Result in $Results) {
    if (-not $Result.passed) {
        Write-Host ("[FAIL] {0}" -f $Result.name)
        foreach ($Issue in @($Result.issues)) {
            Write-Host ("[FAIL] {0}" -f $Issue)
        }
    }
}

if ($Report.status -ne "pass") {
    exit 1
}

exit 0
