[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [object]$ApprovalDecision,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$SupportedToolIds = @("status_summary", "status_summary_private", "obsidian_note_writer", "codex_task_launcher", "restricted_dmz_writer")
$SupportedExecutorTypes = @("informational", "note_editor", "cli_launcher")
$WorkshopIdentityScript = Join-Path $PSScriptRoot "Get-COOPERWorkshopIdentity.ps1"
$OperationalStatusScript = Join-Path $PSScriptRoot "Get-COOPEROperationalStatus.ps1"

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
$NotePath = [string](Get-COOPERDecisionField -Object $ApprovalDecision -Names @("note_path", "file_path", "target_path"))
$MarkdownContent = [string](Get-COOPERDecisionField -Object $ApprovalDecision -Names @("markdown_content", "content"))

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

if ($ToolId -eq "obsidian_note_writer" -and [bool]$WorkshopIdentity.cloud_allowed -eq $false) {
    return [pscustomobject]@{
        success = $false
        dry_run = [bool]$DryRun
        tool_id = $ToolId
        workshop = $Workshop
        workshop_mode = $WorkshopMode
        executor_type = $ExecutorType
        action_taken = "blocked"
        output = $null
        reason = "Private Workshop must not execute note creation tools."
    }
}

if ($ToolId -eq "codex_task_launcher" -and [bool]$WorkshopIdentity.cloud_allowed -eq $false) {
    return [pscustomobject]@{
        success = $false
        dry_run = [bool]$DryRun
        tool_id = $ToolId
        workshop = $Workshop
        workshop_mode = $WorkshopMode
        executor_type = $ExecutorType
        action_taken = "blocked"
        output = $null
        reason = "Private Workshop must not execute Codex task generation tools."
    }
}

if ($ToolId -ne "restricted_dmz_writer" -and [bool]$WorkshopIdentity.cloud_allowed -eq $false -and $ExecutorType -and $SupportedExecutorTypes -notcontains $ExecutorType) {
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

function Resolve-COOPERNotePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$RequestedPath
    )

    $VaultRoot = [System.IO.Path]::GetFullPath((Join-Path $Root "Obsidian Vault"))
    $CandidatePath = if ([System.IO.Path]::IsPathRooted($RequestedPath)) {
        [System.IO.Path]::GetFullPath($RequestedPath)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $Root $RequestedPath))
    }

    $VaultPrefix = $VaultRoot.TrimEnd('\') + '\'
    if (-not ($CandidatePath -eq $VaultRoot -or $CandidatePath.StartsWith($VaultPrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Note path must stay within the Obsidian Vault."
    }

    return $CandidatePath
}

function Resolve-COOPERCodexTaskPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$RequestedPath
    )

    $TaskRoot = [System.IO.Path]::GetFullPath((Join-Path $Root "Codex_Tasks"))
    $CandidatePath = if ([System.IO.Path]::IsPathRooted($RequestedPath)) {
        [System.IO.Path]::GetFullPath($RequestedPath)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $Root $RequestedPath))
    }

    $TaskPrefix = $TaskRoot.TrimEnd('\') + '\'
    if (-not ($CandidatePath -eq $TaskRoot -or $CandidatePath.StartsWith($TaskPrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Task path must stay within the Codex_Tasks folder."
    }

    return $CandidatePath
}

function Resolve-COOPERRestrictedDMZPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$RequestedPath
    )

    $WorkspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $Root "Restricted DMZ Workspace"))
    $CandidatePath = if ([System.IO.Path]::IsPathRooted($RequestedPath)) {
        [System.IO.Path]::GetFullPath($RequestedPath)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $Root $RequestedPath))
    }

    $WorkspacePrefix = $WorkspaceRoot.TrimEnd('\') + '\'
    if (-not ($CandidatePath -eq $WorkspaceRoot -or $CandidatePath.StartsWith($WorkspacePrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Restricted DMZ output must stay within the Restricted DMZ Workspace."
    }

    return $CandidatePath
}

if ($ToolId -eq "restricted_dmz_writer") {
    if ([string]::IsNullOrWhiteSpace($NotePath)) {
        return [pscustomobject]@{
            success = $false
            dry_run = [bool]$DryRun
            tool_id = $ToolId
            workshop = $Workshop
            workshop_mode = $WorkshopMode
            executor_type = $ExecutorType
            action_taken = "blocked"
            output = $null
            reason = "Restricted DMZ writing requires file_path."
        }
    }

    if ([string]::IsNullOrWhiteSpace($MarkdownContent)) {
        return [pscustomobject]@{
            success = $false
            dry_run = [bool]$DryRun
            tool_id = $ToolId
            workshop = $Workshop
            workshop_mode = $WorkshopMode
            executor_type = $ExecutorType
            action_taken = "blocked"
            output = $null
            reason = "Restricted DMZ writing requires content."
        }
    }

    try {
        $ResolvedOutputPath = Resolve-COOPERRestrictedDMZPath -Root $Root -RequestedPath $NotePath
    }
    catch {
        return [pscustomobject]@{
            success = $false
            dry_run = [bool]$DryRun
            tool_id = $ToolId
            workshop = $Workshop
            workshop_mode = $WorkshopMode
            executor_type = $ExecutorType
            action_taken = "blocked"
            output = $null
            reason = $_.Exception.Message
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
            action_taken = "dry_run_restricted_dmz_write"
            output = [pscustomobject]@{
                file_path = $ResolvedOutputPath
                content = $MarkdownContent
                would_create = $true
            }
            reason = "Dry run only. No restricted DMZ file was written."
        }
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ResolvedOutputPath) | Out-Null
    Set-Content -LiteralPath $ResolvedOutputPath -Value $MarkdownContent -Encoding UTF8

    return [pscustomobject]@{
        success = $true
        dry_run = $false
        tool_id = $ToolId
        workshop = $Workshop
        workshop_mode = $WorkshopMode
        executor_type = $ExecutorType
        action_taken = "write_restricted_dmz_file"
        output = [pscustomobject]@{
            file_path = $ResolvedOutputPath
            file_exists = (Test-Path -LiteralPath $ResolvedOutputPath -PathType Leaf)
            bytes_written = (Get-Item -LiteralPath $ResolvedOutputPath).Length
        }
        reason = "Restricted DMZ markdown written."
    }
}

if ($ToolId -eq "obsidian_note_writer") {
    if ([string]::IsNullOrWhiteSpace($NotePath)) {
        return [pscustomobject]@{
            success = $false
            dry_run = [bool]$DryRun
            tool_id = $ToolId
            workshop = $Workshop
            workshop_mode = $WorkshopMode
            executor_type = $ExecutorType
            action_taken = "blocked"
            output = $null
            reason = "Note creation requires note_path."
        }
    }

    if ([string]::IsNullOrWhiteSpace($MarkdownContent)) {
        return [pscustomobject]@{
            success = $false
            dry_run = [bool]$DryRun
            tool_id = $ToolId
            workshop = $Workshop
            workshop_mode = $WorkshopMode
            executor_type = $ExecutorType
            action_taken = "blocked"
            output = $null
            reason = "Note creation requires markdown_content."
        }
    }

    try {
        $ResolvedNotePath = Resolve-COOPERNotePath -Root $Root -RequestedPath $NotePath
    }
    catch {
        return [pscustomobject]@{
            success = $false
            dry_run = [bool]$DryRun
            tool_id = $ToolId
            workshop = $Workshop
            workshop_mode = $WorkshopMode
            executor_type = $ExecutorType
            action_taken = "blocked"
            output = $null
            reason = $_.Exception.Message
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
            action_taken = "dry_run_note_creation"
            output = [pscustomobject]@{
                note_path = $ResolvedNotePath
                markdown_content = $MarkdownContent
                would_create = $true
            }
            reason = "Dry run only. No note was written."
        }
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ResolvedNotePath) | Out-Null
    Set-Content -LiteralPath $ResolvedNotePath -Value $MarkdownContent -Encoding UTF8

    return [pscustomobject]@{
        success = $true
        dry_run = $false
        tool_id = $ToolId
        workshop = $Workshop
        workshop_mode = $WorkshopMode
        executor_type = $ExecutorType
        action_taken = "create_markdown_note"
        output = [pscustomobject]@{
            note_path = $ResolvedNotePath
            note_exists = (Test-Path -LiteralPath $ResolvedNotePath -PathType Leaf)
            bytes_written = (Get-Item -LiteralPath $ResolvedNotePath).Length
        }
        reason = "Markdown note written."
    }
}

if ($ToolId -eq "codex_task_launcher") {
    $TaskPath = [string](Get-COOPERDecisionField -Object $ApprovalDecision -Names @("task_path", "file_path", "target_path"))

    if ([string]::IsNullOrWhiteSpace($TaskPath)) {
        return [pscustomobject]@{
            success = $false
            dry_run = [bool]$DryRun
            tool_id = $ToolId
            workshop = $Workshop
            workshop_mode = $WorkshopMode
            executor_type = $ExecutorType
            action_taken = "blocked"
            output = $null
            reason = "Codex task creation requires task_path."
        }
    }

    if ([string]::IsNullOrWhiteSpace($MarkdownContent)) {
        return [pscustomobject]@{
            success = $false
            dry_run = [bool]$DryRun
            tool_id = $ToolId
            workshop = $Workshop
            workshop_mode = $WorkshopMode
            executor_type = $ExecutorType
            action_taken = "blocked"
            output = $null
            reason = "Codex task creation requires markdown_content."
        }
    }

    try {
        $ResolvedTaskPath = Resolve-COOPERCodexTaskPath -Root $Root -RequestedPath $TaskPath
    }
    catch {
        return [pscustomobject]@{
            success = $false
            dry_run = [bool]$DryRun
            tool_id = $ToolId
            workshop = $Workshop
            workshop_mode = $WorkshopMode
            executor_type = $ExecutorType
            action_taken = "blocked"
            output = $null
            reason = $_.Exception.Message
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
            action_taken = "dry_run_task_creation"
            output = [pscustomobject]@{
                task_path = $ResolvedTaskPath
                markdown_content = $MarkdownContent
                would_create = $true
            }
            reason = "Dry run only. No task file was written."
        }
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ResolvedTaskPath) | Out-Null
    Set-Content -LiteralPath $ResolvedTaskPath -Value $MarkdownContent -Encoding UTF8

    return [pscustomobject]@{
        success = $true
        dry_run = $false
        tool_id = $ToolId
        workshop = $Workshop
        workshop_mode = $WorkshopMode
        executor_type = $ExecutorType
        action_taken = "create_markdown_task"
        output = [pscustomobject]@{
            task_path = $ResolvedTaskPath
            task_exists = (Test-Path -LiteralPath $ResolvedTaskPath -PathType Leaf)
            bytes_written = (Get-Item -LiteralPath $ResolvedTaskPath).Length
        }
        reason = "Markdown task written."
    }
}

if ($SupportedToolIds -notcontains $ToolId) {
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
            workshop_mode = [string]$WorkshopIdentity.workshop_label
            workshop_name = [string]$WorkshopIdentity.display_name
            default_model = [string]$WorkshopIdentity.default_model
            active_registry = [string]$WorkshopIdentity.registry
            status_workflow = "Available"
            security_sources = [pscustomobject]@{
                firewall_status = "Not Configured"
                ids_status = "Not Configured"
                backup_status = "Not Configured"
            }
        }
        reason = "Dry run only. No execution performed."
    }
}

$Root = Split-Path -Parent $PSScriptRoot
$Status = $null
if (Test-Path -LiteralPath $OperationalStatusScript -PathType Leaf) {
    try {
        $Status = & $OperationalStatusScript -Root $Root -WorkshopMode $WorkshopMode -WorkshopIdentity $WorkshopIdentity
    }
    catch {
        $Status = [pscustomobject]@{
            status = "fail"
            review_passed = $false
            review_reason = $_.Exception.Message
            response_text = $_.Exception.Message
            status_lines = @($_.Exception.Message)
            summary_lines = @($_.Exception.Message)
            status_source = "Scripts/Get-COOPEROperationalStatus.ps1"
            workshop_mode = [string]$WorkshopIdentity.workshop_label
            workshop_name = [string]$WorkshopIdentity.display_name
            default_model = [string]$WorkshopIdentity.default_model
            cloud_allowed = [bool]$WorkshopIdentity.cloud_allowed
            active_registry = [string]$WorkshopIdentity.registry
            workspace_root = $Root
        }
    }
}

if ($null -eq $Status) {
    $Status = [pscustomobject]@{
        status = "fail"
        review_passed = $false
        review_reason = "WF-004 operational status helper is unavailable."
        response_text = "WF-004 operational status helper is unavailable."
        status_lines = @("WF-004 operational status helper is unavailable.")
        summary_lines = @("WF-004 operational status helper is unavailable.")
        status_source = "Scripts/Get-COOPEROperationalStatus.ps1"
        workshop_mode = [string]$WorkshopIdentity.workshop_label
        workshop_name = [string]$WorkshopIdentity.display_name
        default_model = [string]$WorkshopIdentity.default_model
        cloud_allowed = [bool]$WorkshopIdentity.cloud_allowed
        active_registry = [string]$WorkshopIdentity.registry
        workspace_root = $Root
    }
}

[pscustomobject]@{
    success = [bool]$Status.review_passed
    dry_run = $false
    tool_id = $ToolId
    workshop = $Workshop
    workshop_mode = $WorkshopMode
    executor_type = $ExecutorType
    action_taken = "local_status_check"
    output = $Status
    reason = if ([bool]$Status.review_passed) { "Local read-only status check completed." } else { [string]$Status.review_reason }
}
