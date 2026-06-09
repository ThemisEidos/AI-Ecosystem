[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConversationId,

    [Parameter(Mandatory = $false)]
    [string]$SessionId,

    [Parameter(Mandatory = $false)]
    [string]$TaskId,

    [Parameter(Mandatory = $false)]
    [string]$UserMessage,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
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
            if ($null -eq $Value[$Key]) {
                $Copy[$Key] = $null
            }
            else {
                $Copy[$Key] = ConvertTo-PDAHashtable -Value $Value[$Key]
            }
        }
        return $Copy
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $List = @()
        foreach ($Item in $Value) {
            if ($null -eq $Item) {
                $List += $null
            }
            else {
                $List += ,(ConvertTo-PDAHashtable -Value $Item)
            }
        }
        return $List
    }

    if ($Value -is [psobject] -and $Value.PSObject.Properties.Name.Count -gt 0) {
        $Copy = @{}
        foreach ($Prop in $Value.PSObject.Properties) {
            if ($null -eq $Prop.Value) {
                $Copy[$Prop.Name] = $null
            }
            else {
                $Copy[$Prop.Name] = ConvertTo-PDAHashtable -Value $Prop.Value
            }
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

function Get-PDAQueueDirs {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    return @(
        Join-Path $RootPath "PDA-Tasks\pending"
        Join-Path $RootPath "PDA-Tasks\running"
        Join-Path $RootPath "PDA-Tasks\completed"
        Join-Path $RootPath "PDA-Tasks\failed"
        Join-Path $RootPath "PDA-Tasks\approvals\pending"
        Join-Path $RootPath "PDA-Tasks\approvals\approved"
        Join-Path $RootPath "PDA-Tasks\approvals\rejected"
        Join-Path $RootPath "PDA-Tasks\results"
        Join-Path $RootPath "Tasks\pending"
        Join-Path $RootPath "Tasks\running"
        Join-Path $RootPath "Tasks\completed"
        Join-Path $RootPath "Tasks\failed"
        Join-Path $RootPath "Tasks\results"
    )
}

function Get-PDASafeString {
    param([Parameter(Mandatory = $false)]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return [string]$Value
}

function Get-PDAResultLocation {
    param([Parameter(Mandatory = $true)]$Task)

    foreach ($Candidate in @(
        $Task.result_path,
        $Task.saved_path,
        $Task.output_path,
        $Task.markdown_path,
        $Task.report_path
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Candidate)) {
            return [string]$Candidate
        }
    }

    return ""
}

function Get-PDATaskFilesystemSnapshot {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $Records = @{}
    $Dirs = Get-PDAQueueDirs -RootPath $RootPath

    foreach ($Dir in $Dirs) {
        if (-not (Test-Path -Path $Dir -PathType Container)) {
            continue
        }

        foreach ($File in Get-ChildItem -Path $Dir -Filter *.json -File -ErrorAction SilentlyContinue) {
            try {
                $Raw = Get-Content -Path $File.FullName -Raw -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace($Raw)) {
                    continue
                }

                $Json = $Raw | ConvertFrom-Json -ErrorAction Stop
                $TaskId = Get-PDASafeString $Json.task_id
                if ([string]::IsNullOrWhiteSpace($TaskId) -and $File.Name -match '^(?<Id>[0-9a-fA-F-]{36})-result\.json$') {
                    $TaskId = $Matches.Id
                }
                if ([string]::IsNullOrWhiteSpace($TaskId)) {
                    continue
                }

                if (-not $Records.ContainsKey($TaskId)) {
                    $Records[$TaskId] = [ordered]@{
                        task_id = $TaskId
                    }
                }

                $Record = $Records[$TaskId]
                $Record.file_path = $File.FullName
                $Record.file_name = $File.Name
                $Record.file_folder = Split-Path -Path $File.FullName -Parent
                $Record.file_last_write = $File.LastWriteTimeUtc.ToString("o")

                if ($Dir -match '\\approvals\\pending$') {
                    $Record.approval_status = "pending"
                    $Record.task_status = "pending_approval"
                    $Record.approval_file_path = $File.FullName
                }
                elseif ($Dir -match '\\approvals\\approved$') {
                    $Record.approval_status = "approved"
                    if (-not $Record.task_status) {
                        $Record.task_status = "queued"
                    }
                    $Record.approval_file_path = $File.FullName
                }
                elseif ($Dir -match '\\approvals\\rejected$') {
                    $Record.approval_status = "rejected"
                    $Record.task_status = "rejected"
                    $Record.approval_file_path = $File.FullName
                }
                elseif ($Dir -match '\\results$' -or $File.Name -match '-result\.json$') {
                    $Record.task_status = "completed"
                    $Record.result_path = $File.FullName
                    $Record.result_json = ConvertTo-PDAHashtable -Value $Json
                }
                else {
                    if ($Dir -match '\\running$') {
                        $Record.task_status = "running"
                    }
                    elseif ($Dir -match '\\completed$') {
                        $Record.task_status = "completed"
                    }
                    elseif ($Dir -match '\\failed$') {
                        $Record.task_status = "failed"
                    }
                    elseif ($Dir -match '\\pending$') {
                        if (-not $Record.task_status) {
                            $Record.task_status = "pending"
                        }
                    }
                }

                foreach ($Property in @(
                    "command",
                    "intent",
                    "classification",
                    "category",
                    "project",
                    "target",
                    "routing_surface",
                    "assigned_worker",
                    "approved",
                    "approval_status",
                    "approval_reason",
                    "status",
                    "created",
                    "started",
                    "completed",
                    "result_path",
                    "error"
                )) {
                    if ($Json.PSObject.Properties.Name -contains $Property -and -not [string]::IsNullOrWhiteSpace([string]$Json.$Property)) {
                        $Record[$Property] = [string]$Json.$Property
                    }
                }

                $Record.raw = ConvertTo-PDAHashtable -Value $Json
            }
            catch {
                continue
            }
        }
    }

    return $Records
}

function Resolve-PDAConversationId {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$FilesystemTasks,
        [string]$ConversationId,
        [string]$SessionId,
        [string]$TaskId
    )

    if (-not [string]::IsNullOrWhiteSpace($ConversationId)) {
        return [string]$ConversationId
    }

    if (-not [string]::IsNullOrWhiteSpace($TaskId) -and $State.tasks.ContainsKey($TaskId)) {
        $TaskRecord = $State.tasks[$TaskId]
        if ($TaskRecord.conversation_id) {
            return [string]$TaskRecord.conversation_id
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($TaskId) -and $FilesystemTasks.ContainsKey($TaskId)) {
        $TaskRecord = $FilesystemTasks[$TaskId]
        if ($TaskRecord.conversation_id) {
            return [string]$TaskRecord.conversation_id
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($SessionId) -and $State.sessions.ContainsKey($SessionId)) {
        $SessionRecord = $State.sessions[$SessionId]
        if ($SessionRecord.conversation_id) {
            return [string]$SessionRecord.conversation_id
        }
    }

    $LatestConversation = $null
    foreach ($Conversation in $State.conversations.GetEnumerator()) {
        if (-not $LatestConversation -or ([string]$Conversation.Value.updated_at -gt [string]$LatestConversation.Value.updated_at)) {
            $LatestConversation = $Conversation
        }
    }

    if ($LatestConversation) {
        return [string]$LatestConversation.Key
    }

    return ""
}

function Get-PDAConversationTasks {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$FilesystemTasks,
        [Parameter(Mandatory = $true)][string]$ConversationKey
    )

    $Tasks = New-Object System.Collections.Generic.List[object]
    foreach ($Entry in $State.tasks.GetEnumerator()) {
        $Task = $Entry.Value
        if ([string]$Task.conversation_id -ne $ConversationKey) {
            continue
        }

        $TaskId = [string]$Task.task_id
        $Merged = @{}
        if ($FilesystemTasks.ContainsKey($TaskId)) {
            $Merged = ConvertTo-PDAHashtable -Value $FilesystemTasks[$TaskId]
        }

        foreach ($Property in $Task.Keys) {
            if ($null -ne $Task[$Property]) {
                $Merged[$Property] = $Task[$Property]
            }
        }

        if (-not $Merged.ContainsKey("task_id")) {
            $Merged["task_id"] = $TaskId
        }
        if (-not $Merged.ContainsKey("conversation_id")) {
            $Merged["conversation_id"] = $ConversationKey
        }

        if (-not $Merged.ContainsKey("task_status")) {
            if ($Merged.ContainsKey("status") -and -not [string]::IsNullOrWhiteSpace([string]$Merged.status)) {
                $Merged["task_status"] = [string]$Merged.status
            }
            elseif ($Merged.ContainsKey("dispatch_status") -and [string]$Merged.dispatch_status -eq "submitted") {
                $Merged["task_status"] = "submitted"
            }
            else {
                $Merged["task_status"] = "unknown"
            }
        }

        if (-not $Merged.ContainsKey("updated_at")) {
            $Merged["updated_at"] = if ($Task.updated_at) { $Task.updated_at } else { $Task.created_at }
        }

        $Tasks.Add([pscustomobject]$Merged)
    }

    return @($Tasks | Sort-Object -Property @{
        Expression = {
            $UpdatedAt = $_.updated_at
            if ([string]::IsNullOrWhiteSpace([string]$UpdatedAt)) {
                $UpdatedAt = $_.created_at
            }
            if ([string]::IsNullOrWhiteSpace([string]$UpdatedAt)) {
                $UpdatedAt = "1970-01-01T00:00:00Z"
            }
            [datetime]::Parse([string]$UpdatedAt)
        }
    } -Descending)
}

function Get-PDAConversationPendingAction {
    param([Parameter(Mandatory = $true)]$Conversation)

    $PendingRecommendedCommand = [string]$Conversation.pending_recommended_command
    if ([string]::IsNullOrWhiteSpace($PendingRecommendedCommand)) {
        return $null
    }

    $PendingTimestamp = [string]$Conversation.pending_timestamp
    $PendingExpiresAt = [string]$Conversation.pending_expires_at
    $IsExpired = $false
    $SecondsRemaining = $null

    try {
        if (-not [string]::IsNullOrWhiteSpace($PendingExpiresAt)) {
            $Expires = [datetime]::Parse($PendingExpiresAt).ToUniversalTime()
            $Now = (Get-Date).ToUniversalTime()
            $SecondsRemaining = [math]::Round(($Expires - $Now).TotalSeconds, 0)
            if ($SecondsRemaining -le 0) {
                $IsExpired = $true
            }
        }
    }
    catch {
        $IsExpired = $true
    }

    return [pscustomobject]@{
        recommended_command = $PendingRecommendedCommand
        dispatch_category    = [string]$Conversation.pending_dispatch_category
        original_message     = [string]$Conversation.pending_original_message
        timestamp            = $PendingTimestamp
        expires_at           = $PendingExpiresAt
        status               = if ([string]::IsNullOrWhiteSpace([string]$Conversation.pending_status)) { "pending" } else { [string]$Conversation.pending_status }
        is_expired           = $IsExpired
        seconds_remaining    = $SecondsRemaining
    }
}

function Get-PDAConversationSummary {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$FilesystemTasks,
        [Parameter(Mandatory = $true)][string]$ConversationKey
    )

    if (-not $State.conversations.ContainsKey($ConversationKey)) {
        return $null
    }

    $Conversation = ConvertTo-PDAHashtable -Value $State.conversations[$ConversationKey]
    $Tasks = Get-PDAConversationTasks -State $State -FilesystemTasks $FilesystemTasks -ConversationKey $ConversationKey

    $ActiveTasks = @(
        $Tasks | Where-Object {
            $_.task_status -in @("queued", "pending", "running", "submitted", "approved", "pending_approval")
        }
    )
    $PendingApprovals = @(
        $Tasks | Where-Object {
            $_.requires_confirmation -eq $true -or $_.task_status -eq "pending_approval"
        }
    )

    $PendingAction = Get-PDAConversationPendingAction -Conversation $Conversation
    if ($PendingAction -and -not $PendingAction.is_expired) {
        $PendingApprovals = @(
            [pscustomobject]@{
                task_id              = ""
                task_status          = "pending_confirmation"
                requires_confirmation = $true
                recommended_command  = $PendingAction.recommended_command
                dispatch_category    = $PendingAction.dispatch_category
                original_message     = $PendingAction.original_message
                pending_timestamp    = $PendingAction.timestamp
                pending_expires_at   = $PendingAction.expires_at
                pending_status       = $PendingAction.status
                conversation_id      = $ConversationKey
                source               = "conversation_state"
            }
        ) + $PendingApprovals
    }
    $SubmittedTasks = @(
        $Tasks | Where-Object {
            $_.dispatch_status -eq "submitted" -or $_.task_status -in @("queued", "pending", "running", "completed", "failed", "approved", "pending_approval")
        }
    )
    $CompletedTasks = @(
        $Tasks | Where-Object {
            $_.task_status -eq "completed"
        }
    )

    $LatestTask = $null
    if ($Tasks.Count -gt 0) {
        $LatestTask = $Tasks[0]
    }

    $LatestResult = $null
    foreach ($Task in $CompletedTasks) {
        if ($Task.result_path -and (Test-Path -Path $Task.result_path -PathType Leaf)) {
            $LatestResult = $Task
            break
        }
    }

    $ResponseText = "No tracked PDA task found for this conversation."
    $NextAction = "Ask the PDA to start a new task or request a status refresh after a confirmed dispatch."

    if ($LatestTask) {
        $LatestCommand = [string]$LatestTask.command
        if ([string]::IsNullOrWhiteSpace($LatestCommand) -and $LatestTask.PSObject.Properties.Name -contains "recommended_command") {
            $LatestCommand = [string]$LatestTask.recommended_command
        }
        if ([string]::IsNullOrWhiteSpace($LatestCommand) -and $PendingAction) {
            $LatestCommand = [string]$PendingAction.recommended_command
        }
        if ([string]::IsNullOrWhiteSpace($LatestCommand)) {
            $LatestCommand = "(pending)"
        }
        $LatestStatus = [string]$LatestTask.task_status
        if ($LatestStatus -eq "completed") {
            $LatestLocation = if ($LatestTask.result_path) { [string]$LatestTask.result_path } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($LatestLocation)) {
                $ResponseText = "Task $($LatestTask.task_id) for $LatestCommand is completed. Output located at $LatestLocation."
            }
            else {
                $ResponseText = "Task $($LatestTask.task_id) for $LatestCommand is completed."
            }
            $NextAction = "Open the result path or ask for a summary of the latest output."
        }
        elseif ($LatestStatus -eq "running") {
            $ResponseText = "Task $($LatestTask.task_id) for $LatestCommand is running."
            $NextAction = "Wait for the queue worker to finish, then ask again for the latest status."
        }
        elseif ($LatestStatus -in @("pending_approval", "pending_confirmation") -or $LatestTask.requires_confirmation -eq $true) {
            $ResponseText = "Task $($LatestTask.task_id) for $LatestCommand is waiting for approval."
            $NextAction = "Confirm the request if you want the governed submitter to dispatch it."
        }
        elseif ($LatestStatus -eq "failed") {
            $ResponseText = "Task $($LatestTask.task_id) for $LatestCommand failed."
            $NextAction = "Inspect the failure reason and retry through the governed route if needed."
        }
        elseif ($LatestStatus -eq "queued" -or $LatestStatus -eq "submitted") {
            $ResponseText = "Task $($LatestTask.task_id) for $LatestCommand has been submitted and is waiting in the queue."
            $NextAction = "Wait for the queue worker to finish, then ask again for the latest status."
        }
    }
    elseif ($PendingAction -and -not $PendingAction.is_expired) {
        $LatestCommand = [string]$PendingAction.recommended_command
        $ResponseText = "Pending confirmation for $LatestCommand. Reply with confirm, yes, approve, proceed, or dispatch to submit it."
        $NextAction = "Confirm the pending governed action to dispatch it."
    }

    if ($LatestResult -and $LatestResult.result_path) {
        $ResponseText = "Latest result for this conversation is available at $($LatestResult.result_path)."
        $NextAction = "Open the result artifact or ask for a summary of the latest output."
    }

    $Conversation.latest_task_id = if ($LatestTask) { [string]$LatestTask.task_id } else { [string]$Conversation.latest_task_id }
    $Conversation.latest_task_status = if ($LatestTask) { [string]$LatestTask.task_status } else { [string]$Conversation.latest_task_status }
    $Conversation.latest_result_path = if ($LatestResult) { [string]$LatestResult.result_path } else { [string]$Conversation.latest_result_path }
    $Conversation.latest_response_text = $ResponseText
    $Conversation.pending_approval_count = $PendingApprovals.Count
    $Conversation.active_task_count = $ActiveTasks.Count
    $Conversation.completed_task_count = $CompletedTasks.Count
    $Conversation.submitted_task_count = $SubmittedTasks.Count
    $Conversation.pending_recommended_command = if ($PendingAction) { $PendingAction.recommended_command } else { $Conversation.pending_recommended_command }
    $Conversation.pending_dispatch_category = if ($PendingAction) { $PendingAction.dispatch_category } else { $Conversation.pending_dispatch_category }
    $Conversation.pending_original_message = if ($PendingAction) { $PendingAction.original_message } else { $Conversation.pending_original_message }
    $Conversation.pending_timestamp = if ($PendingAction) { $PendingAction.timestamp } else { $Conversation.pending_timestamp }
    $Conversation.pending_expires_at = if ($PendingAction) { $PendingAction.expires_at } else { $Conversation.pending_expires_at }
    $Conversation.pending_status = if ($PendingAction) { if ($PendingAction.is_expired) { "expired" } else { $PendingAction.status } } else { $Conversation.pending_status }
    $Conversation.pending_is_expired = if ($PendingAction) { [bool]$PendingAction.is_expired } else { $false }
    $Conversation.updated_at = if ($Conversation.updated_at) { [string]$Conversation.updated_at } else { (Get-Date).ToUniversalTime().ToString("o") }

    return [pscustomobject]@{
        conversation_id   = $ConversationKey
        conversation      = [pscustomobject]$Conversation
        tasks             = @($Tasks)
        active_tasks      = @($ActiveTasks)
        pending_approvals = @($PendingApprovals)
        submitted_tasks   = @($SubmittedTasks)
        completed_tasks   = @($CompletedTasks)
        pending_action    = $PendingAction
        latest_task       = if ($LatestTask) { $LatestTask } else { $null }
        latest_result     = if ($LatestResult) { $LatestResult } else { $null }
        response_text     = $ResponseText
        next_action       = $NextAction
    }
}

$State = Load-PDAConversationState
$FilesystemTasks = Get-PDATaskFilesystemSnapshot -RootPath $Root

$ResolvedConversationId = Resolve-PDAConversationId -State $State -FilesystemTasks $FilesystemTasks -ConversationId $ConversationId -SessionId $SessionId -TaskId $TaskId
$ResolvedTaskId = if (-not [string]::IsNullOrWhiteSpace($TaskId)) { $TaskId } elseif (-not [string]::IsNullOrWhiteSpace($ResolvedConversationId) -and $State.conversations.ContainsKey($ResolvedConversationId)) { [string]$State.conversations[$ResolvedConversationId].latest_task_id } else { "" }

$ConversationSummary = $null
if (-not [string]::IsNullOrWhiteSpace($ResolvedConversationId)) {
    $ConversationSummary = Get-PDAConversationSummary -State $State -FilesystemTasks $FilesystemTasks -ConversationKey $ResolvedConversationId
}

$Report = [pscustomobject]@{
    status                = if ($ConversationSummary) { "pass" } elseif ($State.conversations.Count -gt 0) { "partial" } else { "empty" }
    registry_path         = $StatePath
    conversation_id       = $ResolvedConversationId
    session_id            = $SessionId
    task_id               = $ResolvedTaskId
    query                 = [pscustomobject]@{
        conversation_id = $ConversationId
        session_id      = $SessionId
        task_id         = $TaskId
        user_message    = $UserMessage
    }
    conversation          = if ($ConversationSummary) { $ConversationSummary.conversation } else { $null }
    active_tasks          = if ($ConversationSummary) { $ConversationSummary.active_tasks } else { @() }
    pending_approvals     = if ($ConversationSummary) { $ConversationSummary.pending_approvals } else { @() }
    submitted_tasks       = if ($ConversationSummary) { $ConversationSummary.submitted_tasks } else { @() }
    completed_tasks       = if ($ConversationSummary) { $ConversationSummary.completed_tasks } else { @() }
    tasks                 = if ($ConversationSummary) { $ConversationSummary.tasks } else { @() }
    latest_task           = if ($ConversationSummary) { $ConversationSummary.latest_task } else { $null }
    latest_result         = if ($ConversationSummary) { $ConversationSummary.latest_result } else { $null }
    response_text         = if ($ConversationSummary) { $ConversationSummary.response_text } else { "No tracked PDA task found for this conversation." }
    next_action           = if ($ConversationSummary) { $ConversationSummary.next_action } else { "Ask the PDA to start a new task or confirm a queued request." }
    pending_approval_count = if ($ConversationSummary) { $ConversationSummary.pending_approvals.Count } else { 0 }
    active_task_count     = if ($ConversationSummary) { $ConversationSummary.active_tasks.Count } else { 0 }
    submitted_task_count  = if ($ConversationSummary) { $ConversationSummary.submitted_tasks.Count } else { 0 }
    completed_task_count  = if ($ConversationSummary) { $ConversationSummary.completed_tasks.Count } else { 0 }
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 30
    return
}

Write-Host "[PDA CONVERSATION STATE]"
Write-Host ("Registry path   : {0}" -f $Report.registry_path)
Write-Host ("Conversation ID : {0}" -f $(if ($Report.conversation_id) { $Report.conversation_id } else { "(none)" }))
Write-Host ("Session ID      : {0}" -f $(if ($Report.session_id) { $Report.session_id } else { "(none)" }))
Write-Host ("Task ID         : {0}" -f $(if ($Report.task_id) { $Report.task_id } else { "(none)" }))
Write-Host ("Active tasks    : {0}" -f $Report.active_task_count)
Write-Host ("Pending approvals: {0}" -f $Report.pending_approval_count)
Write-Host ("Completed tasks  : {0}" -f $Report.completed_task_count)
Write-Host ("Response text    : {0}" -f $Report.response_text)
Write-Host ("Next action      : {0}" -f $Report.next_action)
