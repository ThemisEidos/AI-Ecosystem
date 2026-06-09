[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApprovalId,

    [Parameter(Mandatory = $false)]
    [ValidateSet('pending_approval', 'approved', 'rejected', 'revision_requested', 'replan_requested', 'escalated', 'cancelled', 'completed')]
    [string]$Status,

    [Parameter(Mandatory = $false)]
    [string]$Approver = '',

    [Parameter(Mandatory = $false)]
    [string]$Rationale = '',

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PDA_ApprovalWorkflow.ps1')

$Result = Update-PDAApprovalRequest -ApprovalId $ApprovalId -Status $Status -Approver $Approver -Rationale $Rationale -Root $Root -NoThrow:$NoThrow
if ($AsJson) {
    $Result | ConvertTo-Json -Depth 30
    return
}

Write-Host '[PDA APPROVAL REQUEST UPDATED]'
Write-Host ("Approval ID   : {0}" -f $(if ($Result.approval_id) { $Result.approval_id } else { $ApprovalId }))
Write-Host ("Status        : {0}" -f $(if ($Result.current_status) { $Result.current_status } else { $Status }))
Write-Host ("Blocked reason : {0}" -f $(if ($Result.blocked_reason) { $Result.blocked_reason } else { '(none)' }))
