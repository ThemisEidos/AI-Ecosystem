[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RunId = "",

    [Parameter(Mandatory = $false)]
    [string]$ConversationId = "",

    [Parameter(Mandatory = $false)]
    [string]$SessionId = "",

    [Parameter(Mandatory = $false)]
    [string]$Goal = "",

    [Parameter(Mandatory = $false)]
    [string]$RequestedAction = "",

    [Parameter(Mandatory = $false)]
    [string]$Category = "category_1",

    [Parameter(Mandatory = $false)]
    [string]$RouteType = "",

    [Parameter(Mandatory = $false)]
    [string]$RecommendedCommand = "",

    [Parameter(Mandatory = $false)]
    [string]$RecommendedExecutor = "",

    [Parameter(Mandatory = $false)]
    [string]$DispatchCategory = "",

    [Parameter(Mandatory = $false)]
    [string]$UserMessage = "",

    [Parameter(Mandatory = $false)]
    [string]$ApprovalKind = "goal_plan",

    [Parameter(Mandatory = $false)]
    [string]$ApprovalRationale = "",

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PDA_ApprovalWorkflow.ps1')

$Result = New-PDAApprovalRequest -RunId $RunId -ConversationId $ConversationId -SessionId $SessionId -Goal $Goal -RequestedAction $RequestedAction -Category $Category -RouteType $RouteType -RecommendedCommand $RecommendedCommand -RecommendedExecutor $RecommendedExecutor -DispatchCategory $DispatchCategory -UserMessage $UserMessage -ApprovalKind $ApprovalKind -ApprovalRationale $ApprovalRationale -Root $Root

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 30
    return
}

Write-Host '[PDA APPROVAL REQUEST CREATED]'
Write-Host ("Approval ID   : {0}" -f $Result.approval_id)
Write-Host ("Status        : {0}" -f $Result.approval.status)
Write-Host ("Approval path : {0}" -f $Result.approval_path)
