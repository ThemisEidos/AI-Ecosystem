[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$RouterScript = Join-Path $PSScriptRoot "Invoke-COOPERTool.ps1"
$ApprovalScript = Join-Path $PSScriptRoot "Resolve-COOPERApproval.ps1"

function Invoke-ApprovalDecision {
    param(
        [Parameter(Mandatory = $true)]
        [object]$RoutedToolResult,

        [switch]$Approved
    )

    & $ApprovalScript -RoutedToolResult $RoutedToolResult -Approved:$Approved
}

function New-RoutedToolObject {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolId,

        [Parameter(Mandatory = $true)]
        [string]$Workshop,

        [Parameter(Mandatory = $true)]
        [int]$PermissionLevel,

        [Parameter(Mandatory = $true)]
        [bool]$ApprovalRequired,

        [Parameter(Mandatory = $true)]
        [string]$ExecutorType,

        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    [pscustomobject]@{
        status = "pass"
        selected_tool = $ToolId
        tool_id = $ToolId
        id = $ToolId
        name = "Test Tool $ToolId"
        drawer = "Test Drawer"
        workshop = $Workshop
        description = "Synthetic routed tool for approval testing."
        permission_level = $PermissionLevel
        approval_required = $ApprovalRequired
        executor_type = $ExecutorType
        enabled = $Enabled
        inputs = @("input")
        outputs = @("output")
        notes = "Test helper only."
        execution_allowed = $false
    }
}

function Get-RoutedToolCase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolId,

        [Parameter(Mandatory = $true)]
        [string]$Workshop,

        [Parameter(Mandatory = $true)]
        [string]$WorkshopMode
    )

    & $RouterScript -ToolId $ToolId -Workshop $Workshop -WorkshopMode $WorkshopMode -DryRun
}

$Cases = @(
    [pscustomobject]@{
        name = "level 0 allowed without approval"
        input = (Get-RoutedToolCase -ToolId "status_summary" -Workshop "Open Workshop" -WorkshopMode "Open Workshop")
        expect_allowed = $true
        expect_blocked = $false
        expect_requires = $false
        expect_authorized = $true
        expect_reason_like = "Level 0 may auto-run"
    }
    [pscustomobject]@{
        name = "level 1 allowed without approval"
        input = (Get-RoutedToolCase -ToolId "registry_inspector" -Workshop "Open Workshop" -WorkshopMode "Open Workshop")
        expect_allowed = $true
        expect_blocked = $false
        expect_requires = $false
        expect_authorized = $true
        expect_reason_like = "Level 1 may auto-run"
    }
    [pscustomobject]@{
        name = "level 2 requires approval"
        input = (Get-RoutedToolCase -ToolId "obsidian_note_writer" -Workshop "Open Workshop" -WorkshopMode "Open Workshop")
        expect_allowed = $true
        expect_blocked = $false
        expect_requires = $true
        expect_authorized = $false
        expect_reason_like = "Level 2 requires user approval"
    }
    [pscustomobject]@{
        name = "level 3 open workshop requires approval"
        input = (Get-RoutedToolCase -ToolId "browser_research" -Workshop "Open Workshop" -WorkshopMode "Open Workshop")
        expect_allowed = $true
        expect_blocked = $false
        expect_requires = $true
        expect_authorized = $false
        expect_reason_like = "Level 3 requires user approval"
    }
    [pscustomobject]@{
        name = "level 3 private workshop blocked"
        input = (New-RoutedToolObject -ToolId "private_level3_tool" -Workshop "Private Workshop" -PermissionLevel 3 -ApprovalRequired $true -ExecutorType "filesystem" -Enabled $true)
        expect_allowed = $false
        expect_blocked = $true
        expect_requires = $false
        expect_authorized = $false
        expect_reason_like = "Private Workshop does not allow Level 3 tools"
    }
    [pscustomobject]@{
        name = "level 4 requires approval"
        input = (Get-RoutedToolCase -ToolId "powershell_open" -Workshop "Open Workshop" -WorkshopMode "Open Workshop")
        expect_allowed = $true
        expect_blocked = $false
        expect_requires = $true
        expect_authorized = $false
        expect_reason_like = "Level 4 requires user approval"
    }
    [pscustomobject]@{
        name = "level 5 blocked"
        input = (New-RoutedToolObject -ToolId "dangerous_tool" -Workshop "Open Workshop" -PermissionLevel 5 -ApprovalRequired $true -ExecutorType "powershell" -Enabled $true)
        expect_allowed = $false
        expect_blocked = $true
        expect_requires = $false
        expect_authorized = $false
        expect_reason_like = "Level 5 actions are blocked"
    }
    [pscustomobject]@{
        name = "disabled tool blocked"
        input = (New-RoutedToolObject -ToolId "disabled_tool" -Workshop "Open Workshop" -PermissionLevel 1 -ApprovalRequired $false -ExecutorType "local_read" -Enabled $false)
        expect_allowed = $false
        expect_blocked = $true
        expect_requires = $false
        expect_authorized = $false
        expect_reason_like = "disabled"
    }
    [pscustomobject]@{
        name = "private external executor blocked"
        input = (New-RoutedToolObject -ToolId "private_external_tool" -Workshop "Private Workshop" -PermissionLevel 2 -ApprovalRequired $true -ExecutorType "llm_api" -Enabled $true)
        expect_allowed = $false
        expect_blocked = $true
        expect_requires = $false
        expect_authorized = $false
        expect_reason_like = "Private Workshop does not allow external executor types"
    }
)

$Results = @()
$Passed = 0
$Failed = 0

foreach ($Case in $Cases) {
    $Result = Invoke-ApprovalDecision -RoutedToolResult $Case.input
    $Issues = New-Object System.Collections.Generic.List[string]

    foreach ($Field in @(
        "tool_id",
        "workshop",
        "permission_level",
        "approval_required",
        "allowed",
        "blocked",
        "reason",
        "requires_user_approval",
        "execution_authorized"
    )) {
        if ($Result.PSObject.Properties.Name -notcontains $Field) {
            $Issues.Add("Missing required field '$Field'.")
        }
    }

    if ([bool]$Result.allowed -ne [bool]$Case.expect_allowed) {
        $Issues.Add("Expected allowed '$($Case.expect_allowed)' but got '$($Result.allowed)'.")
    }
    if ([bool]$Result.blocked -ne [bool]$Case.expect_blocked) {
        $Issues.Add("Expected blocked '$($Case.expect_blocked)' but got '$($Result.blocked)'.")
    }
    if ([bool]$Result.requires_user_approval -ne [bool]$Case.expect_requires) {
        $Issues.Add("Expected requires_user_approval '$($Case.expect_requires)' but got '$($Result.requires_user_approval)'.")
    }
    if ([bool]$Result.execution_authorized -ne [bool]$Case.expect_authorized) {
        $Issues.Add("Expected execution_authorized '$($Case.expect_authorized)' but got '$($Result.execution_authorized)'.")
    }
    if ([string]$Result.reason -notmatch [regex]::Escape([string]$Case.expect_reason_like)) {
        $Issues.Add("Expected reason to contain '$($Case.expect_reason_like)' but got '$([string]$Result.reason)'.")
    }

    if ($Case.name -eq "level 0 allowed without approval" -and [bool]$Result.approval_required -ne $false) {
        $Issues.Add("Level 0 should not require approval.")
    }
    if ($Case.name -eq "level 1 allowed without approval" -and [bool]$Result.approval_required -ne $false) {
        $Issues.Add("Level 1 should not require approval.")
    }
    if ($Case.name -in @("level 2 requires approval", "level 3 open workshop requires approval", "level 4 requires approval") -and [bool]$Result.approval_required -ne $true) {
        $Issues.Add("Levels 2-4 should report approval_required true.")
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
        tool_id = [string]$Result.tool_id
        workshop = [string]$Result.workshop
        permission_level = [int]$Result.permission_level
        approval_required = [bool]$Result.approval_required
        allowed = [bool]$Result.allowed
        blocked = [bool]$Result.blocked
        requires_user_approval = [bool]$Result.requires_user_approval
        execution_authorized = [bool]$Result.execution_authorized
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

Write-Host "[*] COOPER approval policy tests"
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
