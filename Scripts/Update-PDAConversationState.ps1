[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConversationId,

    [Parameter(Mandatory = $false)]
    [string]$SessionId,

    [Parameter(Mandatory = $false)]
    [string]$UserId,

    [Parameter(Mandatory = $false)]
    [string]$ConversationTitle,

    [Parameter(Mandatory = $false)]
    [string]$TaskId,

    [Parameter(Mandatory = $false)]
    [string]$UserMessage,

    [Parameter(Mandatory = $false)]
    [string]$RecommendedCommand,

    [Parameter(Mandatory = $false)]
    [string]$Intent,

    [Parameter(Mandatory = $false)]
    [double]$Confidence = 0,

    [Parameter(Mandatory = $false)]
    [object]$RequiresConfirmation = $false,

    [Parameter(Mandatory = $false)]
    [string]$DispatchStatus,

    [Parameter(Mandatory = $false)]
    [string]$BridgeStatus,

    [Parameter(Mandatory = $false)]
    [string]$NextAction,

    [Parameter(Mandatory = $false)]
    [string]$ResponseText,

    [Parameter(Mandatory = $false)]
    [string]$TaskStatus,

    [Parameter(Mandatory = $false)]
    [string]$TaskFilePath,

    [Parameter(Mandatory = $false)]
    [string]$ApprovalFilePath,

    [Parameter(Mandatory = $false)]
    [string]$ResultPath,

    [Parameter(Mandatory = $false)]
    [string]$ResultSummary,

    [Parameter(Mandatory = $false)]
    [string]$PendingRecommendedCommand,

    [Parameter(Mandatory = $false)]
    [string]$PendingDispatchCategory,

    [Parameter(Mandatory = $false)]
    [string]$PendingOriginalMessage,

    [Parameter(Mandatory = $false)]
    [string]$PendingTimestamp,

    [Parameter(Mandatory = $false)]
    [string]$PendingExpiresAt,

    [Parameter(Mandatory = $false)]
    [string]$PendingStatus,

    [Parameter(Mandatory = $false)]
    [switch]$ClearPendingAction,

    [Parameter(Mandatory = $false)]
    [string]$Source,

    [Parameter(Mandatory = $false)]
    [switch]$Confirmed,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$StatePath = Join-Path $Root "PDA-Runtime\data\conversation-state.json"

function New-PDAConversationStateStore {
    return [ordered]@{
        schema_version = "1.0"
        created_at     = (Get-Date).ToUniversalTime().ToString("o")
        updated_at     = (Get-Date).ToUniversalTime().ToString("o")
        conversations  = @{}
        tasks          = @{}
        sessions       = @{}
    }
}

function ConvertTo-PDAHashtable {
    param([Parameter(Mandatory = $true)]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [hashtable] -or $Value -is [System.Collections.IDictionary]) {
        $Copy = @{}
        foreach ($Key in $Value.Keys) {
            $Copy[$Key] = ConvertTo-PDAHashtable -Value $Value[$Key]
        }
        return $Copy
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $List = @()
        foreach ($Item in $Value) {
            $List += ,(ConvertTo-PDAHashtable -Value $Item)
        }
        return $List
    }

    if ($Value -is [psobject] -and $Value.PSObject.Properties.Name.Count -gt 0) {
        $Copy = @{}
        foreach ($Prop in $Value.PSObject.Properties) {
            $Copy[$Prop.Name] = ConvertTo-PDAHashtable -Value $Prop.Value
        }
        return $Copy
    }

    return $Value
}

function Load-PDAConversationState {
    if (-not (Test-Path -Path $StatePath -PathType Leaf)) {
        return New-PDAConversationStateStore
    }

    try {
        $Raw = Get-Content -Path $StatePath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($Raw)) {
            return New-PDAConversationStateStore
        }

        $Loaded = $Raw | ConvertFrom-Json -AsHashtable
        if (-not $Loaded) {
            return New-PDAConversationStateStore
        }

        foreach ($Key in @("conversations", "tasks", "sessions")) {
            if (-not $Loaded.ContainsKey($Key) -or $null -eq $Loaded[$Key]) {
                $Loaded[$Key] = @{}
            }
        }

        if (-not $Loaded.ContainsKey("schema_version")) {
            $Loaded["schema_version"] = "1.0"
        }
        if (-not $Loaded.ContainsKey("created_at")) {
            $Loaded["created_at"] = (Get-Date).ToUniversalTime().ToString("o")
        }
        if (-not $Loaded.ContainsKey("updated_at")) {
            $Loaded["updated_at"] = (Get-Date).ToUniversalTime().ToString("o")
        }

        return $Loaded
    }
    catch {
        return New-PDAConversationStateStore
    }
}

function Save-PDAConversationState {
    param([Parameter(Mandatory = $true)]$State)

    $Parent = Split-Path -Parent $StatePath
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null

    $TempPath = "$StatePath.tmp"
    $State.updated_at = (Get-Date).ToUniversalTime().ToString("o")
    $State | ConvertTo-Json -Depth 30 | Set-Content -Path $TempPath -Encoding UTF8
    Move-Item -Path $TempPath -Destination $StatePath -Force
}

function Resolve-PDAConversationKey {
    param(
        [string]$ConversationId,
        [string]$SessionId,
        [string]$TaskId
    )

    if (-not [string]::IsNullOrWhiteSpace($ConversationId)) {
        return [string]$ConversationId
    }

    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        return [string]$SessionId
    }

    if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        return [string]$TaskId
    }

    return "default"
}

function Ensure-PDAConversationRecord {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$ConversationKey
    )

    if (-not $State.conversations.ContainsKey($ConversationKey)) {
        $State.conversations[$ConversationKey] = [ordered]@{
            conversation_id = $ConversationKey
            created_at      = (Get-Date).ToUniversalTime().ToString("o")
        }
    }

    return $State.conversations[$ConversationKey]
}

function Set-PDAFieldIfPresent {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $false)]$Value
    )

    if ($null -eq $Value) {
        return
    }

    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $Record[$Name] = $Value
}

function Remove-PDAFieldIfPresent {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Record.Contains($Name)) {
        [void]$Record.Remove($Name)
    }
}

function Get-PDATaskStatusFromInputs {
    param(
        [string]$TaskStatus,
        [string]$DispatchStatus,
        [string]$TaskFilePath,
        [string]$ApprovalFilePath,
        [string]$ResultPath,
        [bool]$RequiresConfirmation
    )

    if (-not [string]::IsNullOrWhiteSpace($TaskStatus)) {
        return $TaskStatus
    }
    if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
        return "completed"
    }
    if (-not [string]::IsNullOrWhiteSpace($ApprovalFilePath)) {
        return "pending_approval"
    }
    if (-not [string]::IsNullOrWhiteSpace($TaskFilePath)) {
        if ($TaskFilePath -match '\\running\\') { return "running" }
        if ($TaskFilePath -match '\\completed\\') { return "completed" }
        if ($TaskFilePath -match '\\failed\\') { return "failed" }
        if ($TaskFilePath -match '\\approvals\\pending\\') { return "pending_approval" }
        if ($TaskFilePath -match '\\approvals\\approved\\') { return "approved" }
        if ($TaskFilePath -match '\\approvals\\rejected\\') { return "rejected" }
        if ($TaskFilePath -match '\\pending\\') { return "queued" }
    }
    if ($DispatchStatus -eq "submitted") { return "submitted" }
    if ($RequiresConfirmation) { return "pending_confirmation" }
    if ($DispatchStatus) { return $DispatchStatus }
    return "unknown"
}

function ConvertTo-PDABool {
    param([Parameter(Mandatory = $false)]$Value)

    if ($Value -is [bool]) {
        return [bool]$Value
    }
    if ($Value -is [string]) {
        $Normalized = $Value.Trim().ToLowerInvariant()
        return $Normalized -in @("1", "true", "yes", "y", "on")
    }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return [bool]$Value
    }

    return [bool]$Value
}

$State = Load-PDAConversationState
$ConversationKey = Resolve-PDAConversationKey -ConversationId $ConversationId -SessionId $SessionId -TaskId $TaskId
$Conversation = Ensure-PDAConversationRecord -State $State -ConversationKey $ConversationKey

Set-PDAFieldIfPresent -Record $Conversation -Name "conversation_id" -Value $ConversationKey
Set-PDAFieldIfPresent -Record $Conversation -Name "session_id" -Value $SessionId
Set-PDAFieldIfPresent -Record $Conversation -Name "user_id" -Value $UserId
Set-PDAFieldIfPresent -Record $Conversation -Name "title" -Value $ConversationTitle
Set-PDAFieldIfPresent -Record $Conversation -Name "last_message" -Value $UserMessage
Set-PDAFieldIfPresent -Record $Conversation -Name "last_command" -Value $RecommendedCommand
Set-PDAFieldIfPresent -Record $Conversation -Name "last_intent" -Value $Intent
Set-PDAFieldIfPresent -Record $Conversation -Name "last_response_text" -Value $ResponseText
Set-PDAFieldIfPresent -Record $Conversation -Name "last_next_action" -Value $NextAction
Set-PDAFieldIfPresent -Record $Conversation -Name "last_bridge_status" -Value $BridgeStatus
Set-PDAFieldIfPresent -Record $Conversation -Name "last_dispatch_status" -Value $DispatchStatus
Set-PDAFieldIfPresent -Record $Conversation -Name "latest_result_path" -Value $ResultPath
Set-PDAFieldIfPresent -Record $Conversation -Name "latest_result_summary" -Value $ResultSummary
Set-PDAFieldIfPresent -Record $Conversation -Name "updated_at" -Value (Get-Date).ToUniversalTime().ToString("o")

if ($ClearPendingAction) {
    foreach ($Field in @(
        "pending_recommended_command",
        "pending_dispatch_category",
        "pending_original_message",
        "pending_timestamp",
        "pending_expires_at",
        "pending_status",
        "pending_task_id"
    )) {
        Remove-PDAFieldIfPresent -Record $Conversation -Name $Field
    }
}
elseif (
    -not [string]::IsNullOrWhiteSpace($PendingRecommendedCommand) -or
    -not [string]::IsNullOrWhiteSpace($PendingDispatchCategory) -or
    -not [string]::IsNullOrWhiteSpace($PendingOriginalMessage) -or
    -not [string]::IsNullOrWhiteSpace($PendingTimestamp) -or
    -not [string]::IsNullOrWhiteSpace($PendingExpiresAt) -or
    -not [string]::IsNullOrWhiteSpace($PendingStatus)
) {
    Set-PDAFieldIfPresent -Record $Conversation -Name "pending_recommended_command" -Value $PendingRecommendedCommand
    Set-PDAFieldIfPresent -Record $Conversation -Name "pending_dispatch_category" -Value $PendingDispatchCategory
    Set-PDAFieldIfPresent -Record $Conversation -Name "pending_original_message" -Value $PendingOriginalMessage
    Set-PDAFieldIfPresent -Record $Conversation -Name "pending_timestamp" -Value $PendingTimestamp
    Set-PDAFieldIfPresent -Record $Conversation -Name "pending_expires_at" -Value $PendingExpiresAt
    Set-PDAFieldIfPresent -Record $Conversation -Name "pending_status" -Value $(if ([string]::IsNullOrWhiteSpace($PendingStatus)) { "pending" } else { $PendingStatus })
}

if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
    $State.sessions[$SessionId] = [ordered]@{
        conversation_id = $ConversationKey
        session_id      = $SessionId
        updated_at      = (Get-Date).ToUniversalTime().ToString("o")
    }
}

if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
    if (-not $State.tasks.ContainsKey($TaskId)) {
        $State.tasks[$TaskId] = [ordered]@{
            task_id         = $TaskId
            conversation_id = $ConversationKey
            created_at      = (Get-Date).ToUniversalTime().ToString("o")
        }
    }

    $TaskRecord = $State.tasks[$TaskId]
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "task_id" -Value $TaskId
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "conversation_id" -Value $ConversationKey
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "session_id" -Value $SessionId
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "user_id" -Value $UserId
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "user_message" -Value $UserMessage
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "recommended_command" -Value $RecommendedCommand
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "intent" -Value $Intent
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "confidence" -Value $Confidence
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "requires_confirmation" -Value (ConvertTo-PDABool -Value $RequiresConfirmation)
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "dispatch_status" -Value $DispatchStatus
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "bridge_status" -Value $BridgeStatus
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "next_action" -Value $NextAction
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "response_text" -Value $ResponseText
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "task_file_path" -Value $TaskFilePath
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "approval_file_path" -Value $ApprovalFilePath
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "result_path" -Value $ResultPath
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "result_summary" -Value $ResultSummary
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "source" -Value $Source
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "confirmed" -Value ([bool]$Confirmed)

    $TaskStatusValue = Get-PDATaskStatusFromInputs -TaskStatus $TaskStatus -DispatchStatus $DispatchStatus -TaskFilePath $TaskFilePath -ApprovalFilePath $ApprovalFilePath -ResultPath $ResultPath -RequiresConfirmation (ConvertTo-PDABool -Value $RequiresConfirmation)
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "task_status" -Value $TaskStatusValue
    Set-PDAFieldIfPresent -Record $TaskRecord -Name "updated_at" -Value (Get-Date).ToUniversalTime().ToString("o")
    if ($ClearPendingAction) {
        foreach ($Field in @(
            "pending_recommended_command",
            "pending_dispatch_category",
            "pending_original_message",
            "pending_timestamp",
            "pending_expires_at",
            "pending_status",
            "pending_task_id"
        )) {
            Remove-PDAFieldIfPresent -Record $TaskRecord -Name $Field
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($PendingRecommendedCommand)) {
        Set-PDAFieldIfPresent -Record $TaskRecord -Name "pending_recommended_command" -Value $PendingRecommendedCommand
        Set-PDAFieldIfPresent -Record $TaskRecord -Name "pending_dispatch_category" -Value $PendingDispatchCategory
        Set-PDAFieldIfPresent -Record $TaskRecord -Name "pending_original_message" -Value $PendingOriginalMessage
        Set-PDAFieldIfPresent -Record $TaskRecord -Name "pending_timestamp" -Value $PendingTimestamp
        Set-PDAFieldIfPresent -Record $TaskRecord -Name "pending_expires_at" -Value $PendingExpiresAt
        Set-PDAFieldIfPresent -Record $TaskRecord -Name "pending_status" -Value $(if ([string]::IsNullOrWhiteSpace($PendingStatus)) { "pending" } else { $PendingStatus })
    }

    $Conversation.latest_task_id = $TaskId
    $Conversation.latest_task_status = $TaskStatusValue
    if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
        $Conversation.latest_result_path = $ResultPath
    }
    if (-not [string]::IsNullOrWhiteSpace($ResponseText)) {
        $Conversation.latest_response_text = $ResponseText
    }
}

Save-PDAConversationState -State $State

$Result = [pscustomobject]@{
    status           = "pass"
    registry_path    = $StatePath
    conversation_id  = $ConversationKey
    session_id       = $SessionId
    task_id          = $TaskId
    task_status      = if ($TaskId) { $State.tasks[$TaskId].task_status } else { "" }
    dispatch_status  = $DispatchStatus
    bridge_status    = $BridgeStatus
    response_text    = $ResponseText
    next_action      = $NextAction
    result_path      = $ResultPath
    approval_path    = $ApprovalFilePath
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    return
}

Write-Host "[PDA CONVERSATION STATE UPDATED]"
Write-Host ("Registry path   : {0}" -f $Result.registry_path)
Write-Host ("Conversation ID : {0}" -f $Result.conversation_id)
Write-Host ("Task ID         : {0}" -f $(if ($Result.task_id) { $Result.task_id } else { "(none)" }))
Write-Host ("Task status     : {0}" -f $(if ($Result.task_status) { $Result.task_status } else { "(none)" }))
Write-Host ("Dispatch status  : {0}" -f $(if ($Result.dispatch_status) { $Result.dispatch_status } else { "(none)" }))
