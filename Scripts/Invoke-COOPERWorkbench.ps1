[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [object]$ApprovalDecision,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$SupportedToolId = "status_summary"
$SupportedExecutorType = "informational"
$WorkshopIdentityScript = Join-Path $PSScriptRoot "Get-COOPERWorkshopIdentity.ps1"

function Get-COOPERDecisionField {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($Name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $Name) {
            $Value = $Object.$Name
            if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)) {
                return $Value
            }
        }
    }

    return $null
}

function ConvertTo-COOPERBool {
    param([Parameter(Mandatory = $false)]$Value)

    if ($Value -is [bool]) {
        return [bool]$Value
    }

    if ($null -eq $Value) {
        return $null
    }

    $Text = [string]$Value
    if ($Text -match '^(?i:true|false)$') {
        return [bool]::Parse($Text)
    }

    return $null
}

function ConvertTo-COOPERInt {
    param([Parameter(Mandatory = $false)]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    try {
        return [int]$Value
    }
    catch {
        return $null
    }
}

$ToolId = [string](Get-COOPERDecisionField -Object $ApprovalDecision -Names @("tool_id"))
$Workshop = [string](Get-COOPERDecisionField -Object $ApprovalDecision -Names @("workshop"))
$WorkshopMode = [string](Get-COOPERDecisionField -Object $ApprovalDecision -Names @("workshop_mode"))
$ExecutorType = [string](Get-COOPERDecisionField -Object $ApprovalDecision -Names @("executor_type"))
$PermissionLevel = ConvertTo-COOPERInt -Value (Get-COOPERDecisionField -Object $ApprovalDecision -Names @("permission_level"))
$ApprovalRequired = ConvertTo-COOPERBool -Value (Get-COOPERDecisionField -Object $ApprovalDecision -Names @("approval_required"))
$Allowed = ConvertTo-COOPERBool -Value (Get-COOPERDecisionField -Object $ApprovalDecision -Names @("allowed"))
$Blocked = ConvertTo-COOPERBool -Value (Get-COOPERDecisionField -Object $ApprovalDecision -Names @("blocked"))
$RequiresUserApproval = ConvertTo-COOPERBool -Value (Get-COOPERDecisionField -Object $ApprovalDecision -Names @("requires_user_approval"))
$ExecutionAuthorized = ConvertTo-COOPERBool -Value (Get-COOPERDecisionField -Object $ApprovalDecision -Names @("execution_authorized"))
$Reason = [string](Get-COOPERDecisionField -Object $ApprovalDecision -Names @("reason"))

if ([string]::IsNullOrWhiteSpace($ToolId)) {
    return [pscustomobject]@{
        success = $false
        dry_run = [bool]$DryRun
        tool_id = ""
        workshop = ""
        workshop_mode = ""
        executor_type = ""
        action_taken = "none"
        output = $null
        reason = "Approval decision is missing tool_id."
    }
}

if ([string]::IsNullOrWhiteSpace($WorkshopMode)) {
    return [pscustomobject]@{
        success = $false
        dry_run = [bool]$DryRun
        tool_id = $ToolId
        workshop = $Workshop
        workshop_mode = $WorkshopMode
        executor_type = $ExecutorType
        action_taken = "blocked"
        output = $null
        reason = "Approval decision is missing workshop_mode."
    }
}

$WorkshopIdentity = & $WorkshopIdentityScript -WorkshopMode $WorkshopMode

if ($Blocked -eq $true) {
    return [pscustomobject]@{
        success = $false
        dry_run = [bool]$DryRun
        tool_id = $ToolId
        workshop = $Workshop
        workshop_mode = $WorkshopMode
        executor_type = $ExecutorType
        action_taken = "blocked"
        output = $null
        reason = if ([string]::IsNullOrWhiteSpace($Reason)) { "Blocked approval decision." } else { $Reason }
    }
}

if ($null -eq $PermissionLevel) {
    return [pscustomobject]@{
        success = $false
        dry_run = [bool]$DryRun
        tool_id = $ToolId
        workshop = $Workshop
        workshop_mode = $WorkshopMode
        executor_type = $ExecutorType
        action_taken = "blocked"
        output = $null
        reason = "Approval decision is missing a permission level."
    }
}

if ($ExecutionAuthorized -ne $true) {
    return [pscustomobject]@{
        success = $false
        dry_run = [bool]$DryRun
        tool_id = $ToolId
        workshop = $Workshop
        workshop_mode = $WorkshopMode
        executor_type = $ExecutorType
        action_taken = "not_executed"
        output = $null
        reason = if ([string]::IsNullOrWhiteSpace($Reason)) { "Execution is not authorized." } else { $Reason }
    }
}

if ($PermissionLevel -eq 5) {
    return [pscustomobject]@{
        success = $false
        dry_run = [bool]$DryRun
        tool_id = $ToolId
        workshop = $Workshop
        workshop_mode = $WorkshopMode
        executor_type = $ExecutorType
        action_taken = "blocked"
        output = $null
        reason = "Level 5 actions must not execute."
    }
}

if ([bool]$WorkshopIdentity.cloud_allowed -eq $false -and $ExecutorType -and $ExecutorType -ne $SupportedExecutorType) {
    return [pscustomobject]@{
        success = $false
        dry_run = [bool]$DryRun
        tool_id = $ToolId
        workshop = $Workshop
        workshop_mode = $WorkshopMode
        executor_type = $ExecutorType
        action_taken = "blocked"
        output = $null
        reason = "Private Workshop must not execute external executor types."
    }
}

if ($ToolId -ne $SupportedToolId) {
    return [pscustomobject]@{
        success = $false
        dry_run = [bool]$DryRun
        tool_id = $ToolId
        workshop = $Workshop
        workshop_mode = $WorkshopMode
        executor_type = $ExecutorType
        action_taken = "unsupported"
        output = $null
        reason = "Unsupported workbench tool id '$ToolId'."
    }
}

if ($DryRun) {
    return [pscustomobject]@{
        success = $true
        dry_run = $true
        tool_id = $ToolId
        workshop = $Workshop
        workshop_mode = $WorkshopMode
        executor_type = $ExecutorType
        action_taken = "dry_run_status_check"
        output = [pscustomobject]@{
            would_execute = $true
            action = "local_status_check"
            authorization_status = [bool]$ExecutionAuthorized
            permission_level = $PermissionLevel
            approval_required = [bool]$ApprovalRequired
            requires_user_approval = [bool]$RequiresUserApproval
            cloud_allowed = [bool]$WorkshopIdentity.cloud_allowed
        }
        reason = "Dry run only. No execution performed."
    }
}

$Root = Split-Path -Parent $PSScriptRoot
$Status = [pscustomobject]@{
    workspace_root = $Root
    config_exists = (Test-Path -LiteralPath (Join-Path $Root "Config") -PathType Container)
    scripts_exists = (Test-Path -LiteralPath (Join-Path $Root "Scripts") -PathType Container)
    registry_exists = (Test-Path -LiteralPath (Join-Path $Root "Config\general_tool_registry.yaml") -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $Root "Config\private_tool_registry.yaml") -PathType Leaf)
    guidance_docs_present = @(
        "00_Project Charter.md",
        "01_AI Ecosystem Architecture.md",
        "02_COOPER System Specification.md",
        "03_AI Tool Stack & Roles.md"
    ) | ForEach-Object { Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf }
}

[pscustomobject]@{
    success = $true
    dry_run = $false
    tool_id = $ToolId
    workshop = $Workshop
    workshop_mode = $WorkshopMode
    executor_type = $ExecutorType
    action_taken = "local_status_check"
    output = $Status
    reason = "Local read-only status check completed."
}
