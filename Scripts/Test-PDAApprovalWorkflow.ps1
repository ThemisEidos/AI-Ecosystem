[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = if ([string]::IsNullOrWhiteSpace([string]$PSScriptRoot)) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace([string]$Root)) {
    $Root = Split-Path -Parent $ScriptRoot
}
. (Join-Path $ScriptRoot 'PDA_ApprovalWorkflow.ps1')
. (Join-Path $ScriptRoot 'PDA_AgentLoop.ps1')
. (Join-Path $ScriptRoot 'PDA_OutputParsing.ps1')

function Assert-PDACondition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][System.Collections.Generic.List[string]]$Issues
    )

    if (-not $Condition -and $Issues) {
        $Issues.Add($Message)
    }

    return $Condition
}

$Issues = New-Object System.Collections.Generic.List[string]
$Goal = 'Governed approval workflow foundation'

$CreateResult = New-PDAApprovalRequest -RunId 'run-approval-test-001' -ConversationId 'conv-approval-test-001' -SessionId 'sess-approval-test-001' -Goal $Goal -RequestedAction 'approve agent execution' -Category 'category_1' -RouteType 'goal_planning' -RecommendedCommand '/planner' -RecommendedExecutor 'planner-worker' -DispatchCategory 'local-only' -UserMessage 'Please approve the goal plan.' -ApprovalKind 'goal_plan' -ApprovalRationale 'Testing approval creation.' -Root $Root
Assert-PDACondition -Condition ([string]$CreateResult.status -eq 'pass') -Message 'Approval request creation failed.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition (-not [string]::IsNullOrWhiteSpace([string]$CreateResult.approval_id)) -Message 'Approval ID was not created.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$CreateResult.approval.status -eq 'pending_approval') -Message 'New approval should start pending.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition (Test-Path -LiteralPath $CreateResult.approval_path -PathType Leaf) -Message 'Approval file was not created.' -Issues $Issues | Out-Null

$StoredApproval = Get-PDAApprovalRequest -ApprovalId $CreateResult.approval_id -Root $Root
Assert-PDACondition -Condition ($StoredApproval -and [string]$StoredApproval.approval_id -eq [string]$CreateResult.approval_id) -Message 'Approval persistence lookup failed.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$StoredApproval.status -eq 'pending_approval') -Message 'Stored approval status mismatch.' -Issues $Issues | Out-Null

$ApproveResult = Update-PDAApprovalRequest -ApprovalId $CreateResult.approval_id -Status 'approved' -Approver 'human operator' -Rationale 'Approved for execution.' -Root $Root -NoThrow
Assert-PDACondition -Condition ([string]$ApproveResult.status -eq 'pass') -Message 'Approval transition to approved failed.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$ApproveResult.current_status -eq 'approved') -Message 'Approval did not move to approved state.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition (Test-Path -LiteralPath $ApproveResult.approval.approval_path -PathType Leaf) -Message 'Approved approval file missing.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition (($ApproveResult.approval.history | Select-Object -Last 1).to_status -eq 'approved') -Message 'Approval history did not record the approved transition.' -Issues $Issues | Out-Null

$InvalidTransition = Update-PDAApprovalRequest -ApprovalId $CreateResult.approval_id -Status 'pending_approval' -Approver 'human operator' -Rationale 'Invalid transition.' -Root $Root -NoThrow
Assert-PDACondition -Condition ([string]$InvalidTransition.status -eq 'blocked') -Message 'Invalid approval transition should be blocked.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition (-not [string]::IsNullOrWhiteSpace([string]$InvalidTransition.blocked_reason)) -Message 'Invalid approval transition should provide a blocked reason.' -Issues $Issues | Out-Null

$AgentCreate = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'New-PDAAgentRun.ps1') -Goal 'Validate first 10 website links in XLSX and write Markdown report to Obsidian.' -AsJson 2>&1
$AgentCreateJson = ConvertFrom-PDAMixedJson -Text ([string]($AgentCreate -join "`n")) -SourceName (Join-Path $PSScriptRoot 'New-PDAAgentRun.ps1')
Assert-PDACondition -Condition ([string]$AgentCreateJson.status -eq 'pass') -Message 'Agent run creation failed during approval workflow test.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($AgentCreateJson.run.PSObject.Properties.Name -contains 'approval_id') -Message 'Agent run did not persist approval_id.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($AgentCreateJson.run.PSObject.Properties.Name -contains 'approval_path') -Message 'Agent run did not persist approval_path.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$AgentCreateJson.run.approval_status -eq 'pending') -Message 'Agent run approval_status should start pending.' -Issues $Issues | Out-Null

$DashboardStatus = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Get-PDADashboardStatus.ps1') -RootPath $Root -AsJson -NoThrow 2>&1
$DashboardJson = ConvertFrom-PDAMixedJson -Text ([string]($DashboardStatus -join "`n")) -SourceName (Join-Path $PSScriptRoot 'Get-PDADashboardStatus.ps1')
Assert-PDACondition -Condition ($DashboardJson.PSObject.Properties.Name -contains 'approval_workflow') -Message 'Dashboard status missing approval workflow section.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([int]$DashboardJson.approval_workflow.pending_approval_count -ge 1) -Message 'Dashboard approval workflow pending count should be at least one.' -Issues $Issues | Out-Null

$ApprovalConversationId = 'conv-goal-approval-foundation'
$ApprovalSessionId = 'sess-goal-approval-foundation'
$ApprovalMarker = "approval-foundation-$([guid]::NewGuid().ToString())"
$BridgeCreateRaw = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Invoke-PDAChatBridge.ps1') -Message "I want to start reading classic literature. Can you search the internet, create a list of top books from famous authors, write a report, include links and synopses, and make it a PDF? [$ApprovalMarker]" -ConversationId $ApprovalConversationId -SessionId $ApprovalSessionId -AsJson 2>&1
$BridgeCreate = ConvertFrom-PDAMixedJson -Text ([string]($BridgeCreateRaw -join "`n")) -SourceName (Join-Path $PSScriptRoot 'Invoke-PDAChatBridge.ps1')
Assert-PDACondition -Condition ($BridgeCreate.PSObject.Properties.Name -contains 'pending_action') -Message 'Bridge should persist a pending action for approval-required goal plans.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($BridgeCreate.PSObject.Properties.Name -contains 'approval_id' -or ($BridgeCreate.conversation_state_status -match 'pending')) -Message 'Bridge should surface approval state for the conversation.' -Issues $Issues | Out-Null

$BridgeApproveRaw = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Invoke-PDAChatBridge.ps1') -Message 'approved' -ConversationId $ApprovalConversationId -SessionId $ApprovalSessionId -AsJson 2>&1
$BridgeApprove = ConvertFrom-PDAMixedJson -Text ([string]($BridgeApproveRaw -join "`n")) -SourceName (Join-Path $PSScriptRoot 'Invoke-PDAChatBridge.ps1')
Assert-PDACondition -Condition ($BridgeApprove.response_text -notmatch 'No pending governed action found for this conversation') -Message 'Approved reply should resolve the pending governed action.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($BridgeApprove.handoff_status -ne 'no_pending_confirmation') -Message 'Approved reply should not lose the pending confirmation state.' -Issues $Issues | Out-Null

$BridgeCancelRaw = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Invoke-PDAChatBridge.ps1') -Message 'cancel' -ConversationId $ApprovalConversationId -SessionId $ApprovalSessionId -AsJson 2>&1
$BridgeCancel = ConvertFrom-PDAMixedJson -Text ([string]($BridgeCancelRaw -join "`n")) -SourceName (Join-Path $PSScriptRoot 'Invoke-PDAChatBridge.ps1')
Assert-PDACondition -Condition ($BridgeCancel.response_text -notmatch 'No pending governed action found for this conversation') -Message 'Cancel reply should be tied to the approval state.' -Issues $Issues | Out-Null

$WorkflowStatus = Get-PDAApprovalWorkflowStatus -Root $Root -Latest 10
Assert-PDACondition -Condition ([int]$WorkflowStatus.counts.pending_approval -ge 0) -Message 'Approval workflow status missing pending count.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($WorkflowStatus.PSObject.Properties.Name -contains 'recent_approvals') -Message 'Approval workflow status missing recent approvals.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($WorkflowStatus.PSObject.Properties.Name -contains 'stale_count') -Message 'Approval workflow status missing stale_count.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($WorkflowStatus.PSObject.Properties.Name -contains 'blocked_count') -Message 'Approval workflow status missing blocked_count.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($WorkflowStatus.counts.PSObject.Properties.Name -contains 'completed') -Message 'Approval workflow status missing completed lifecycle count.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($WorkflowStatus.counts.PSObject.Properties.Name -contains 'stale') -Message 'Approval workflow status missing stale lifecycle count.' -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($WorkflowStatus.counts.PSObject.Properties.Name -contains 'blocked') -Message 'Approval workflow status missing blocked lifecycle count.' -Issues $Issues | Out-Null

if (Get-Command -Name Load-PDAApprovalWorkflowStore -ErrorAction SilentlyContinue) {
    $Store = Load-PDAApprovalWorkflowStore -Root $Root
    if ($Store.PSObject.Properties.Name -contains 'pending_approval_count') {
        Assert-PDACondition -Condition ([int]$WorkflowStatus.pending_approval_count -eq [int]$Store.pending_approval_count) -Message 'Approval workflow status pending count does not match the store.' -Issues $Issues | Out-Null
    }
    if ($Store.PSObject.Properties.Name -contains 'blocked_count') {
        Assert-PDACondition -Condition ([int]$WorkflowStatus.blocked_count -eq [int]$Store.blocked_count) -Message 'Approval workflow status blocked count does not match the store.' -Issues $Issues | Out-Null
    }
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { 'pass' } else { 'fail' }
    created = $CreateResult
    approved = $ApproveResult
    invalid_transition = $InvalidTransition
    dashboard = $DashboardJson
    bridge = [pscustomobject]@{
        create = $BridgeCreate
        approve = $BridgeApprove
        cancel = $BridgeCancel
    }
    workflow = $WorkflowStatus
    issues = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 30
    if (-not $NoThrow -and $Report.status -ne 'pass') {
        throw 'PDA approval workflow validation failed.'
    }
    return
}

Write-Host '[*] PDA approval workflow tests'
Write-Host ("Status     : {0}" -f $Report.status)
Write-Host ("Issues     : {0}" -f @($Report.issues).Count)

if (-not $NoThrow -and $Report.status -ne 'pass') {
    throw 'PDA approval workflow validation failed.'
}
