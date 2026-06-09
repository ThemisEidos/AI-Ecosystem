[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [int]$Latest = 10,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PDA_ApprovalWorkflow.ps1')

$Report = Get-PDAApprovalWorkflowStatus -Root $Root -Latest $Latest

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 30
    if (-not $NoThrow -and $Report.status -ne 'pass') {
        throw 'PDA approval workflow validation failed.'
    }
    return
}

Write-Host '[PDA APPROVAL WORKFLOW STATUS]'
Write-Host ("Approval count        : {0}" -f $Report.approval_count)
Write-Host ("Pending approvals     : {0}" -f $Report.pending_approval_count)
Write-Host ("Blocked approvals     : {0}" -f $Report.blocked_count)
Write-Host ("Blocked agent runs    : {0}" -f $Report.counts.blocked_agent_runs)
Write-Host ("Pending agent runs    : {0}" -f $Report.counts.pending_agent_runs)
