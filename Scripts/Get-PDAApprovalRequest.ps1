[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ApprovalId = "",

    [Parameter(Mandatory = $false)]
    [string]$RunId = "",

    [Parameter(Mandatory = $false)]
    [string]$ConversationId = "",

    [Parameter(Mandatory = $false)]
    [string]$SessionId = "",

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PDA_ApprovalWorkflow.ps1')

$Result = Get-PDAApprovalRequest -ApprovalId $ApprovalId -RunId $RunId -ConversationId $ConversationId -SessionId $SessionId -Root $Root
if (-not $Result) {
    $Result = [pscustomobject]@{
        status = 'missing'
        approval_id = $ApprovalId
        run_id = $RunId
        conversation_id = $ConversationId
        session_id = $SessionId
    }
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 30
    return
}

Write-Host '[PDA APPROVAL REQUEST]'
Write-Host ("Approval ID   : {0}" -f $(if ($Result.approval_id) { $Result.approval_id } else { '(none)' }))
Write-Host ("Status        : {0}" -f $(if ($Result.status) { $Result.status } else { '(none)' }))
Write-Host ("Run ID        : {0}" -f $(if ($Result.run_id) { $Result.run_id } else { '(none)' }))
Write-Host ("Conversation  : {0}" -f $(if ($Result.conversation_id) { $Result.conversation_id } else { '(none)' }))
