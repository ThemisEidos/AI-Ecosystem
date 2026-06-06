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
    [string]$StatePath,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ResolvedStatePath = if ([string]::IsNullOrWhiteSpace($StatePath)) {
    Join-Path $Root "PDA-Runtime\data\conversation-state.json"
} else {
    $StatePath
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

function Load-PDAConversationState {
    if (-not (Test-Path -Path $ResolvedStatePath -PathType Leaf)) {
        return New-PDAConversationStateStore
    }

    try {
        $Raw = Get-Content -Path $ResolvedStatePath -Raw -ErrorAction Stop
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

function Get-PDATaskFilesystemSnapshot {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $Records = @{}
    foreach ($Dir in (Get-PDAQueueDirs -RootPath $RootPath)) {
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
                    "error",
                    "conversation_id",
                    "session_id",
                    "user_id",
                    "conversation_title",
                    "result_summary"
                )) {
                    if ($Json.PSObject.Properties.Name -contains $Property -and -not [string]::IsNullOrWhiteSpace([string]$Json.$Property)) {
                        $Record[$Property] = [string]$Json.$Property
                    }
                }
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

    if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        if ($State.tasks.ContainsKey($TaskId) -and $State.tasks[$TaskId].conversation_id) {
            return [string]$State.tasks[$TaskId].conversation_id
        }
        if ($FilesystemTasks.ContainsKey($TaskId) -and $FilesystemTasks[$TaskId].conversation_id) {
            return [string]$FilesystemTasks[$TaskId].conversation_id
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($SessionId) -and $State.sessions.ContainsKey($SessionId)) {
        if ($State.sessions[$SessionId].conversation_id) {
            return [string]$State.sessions[$SessionId].conversation_id
        }
    }

    $LatestConversation = $null
    foreach ($Conversation in $State.conversations.GetEnumerator()) {
        if ($Conversation.Key -eq "default") {
            continue
        }
        if (-not $LatestConversation -or [string]$Conversation.Value.updated_at -gt [string]$LatestConversation.Value.updated_at) {
            $LatestConversation = $Conversation
        }
    }

    if ($LatestConversation) {
        return [string]$LatestConversation.Key
    }

    if ($State.conversations.ContainsKey("default")) {
        return "default"
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

        $Tasks.Add([pscustomobject]$Merged)
    }

    foreach ($Entry in $FilesystemTasks.GetEnumerator()) {
        $Task = $Entry.Value
        if ([string]$Task.conversation_id -ne $ConversationKey) {
            continue
        }

        $TaskId = [string]$Task.task_id
        if ($Tasks | Where-Object { [string]$_.task_id -eq $TaskId }) {
            continue
        }
        $Tasks.Add([pscustomobject](ConvertTo-PDAHashtable -Value $Task))
    }

    return @($Tasks | Sort-Object -Property @{ Expression = { [datetime]::Parse([string]($_.updated_at ?? $_.created_at ?? "1970-01-01T00:00:00Z")) } } -Descending)
}

function Get-PDATaskResultResponse {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$FilesystemTasks,
        [Parameter(Mandatory = $true)][string]$ConversationKey,
        [string]$TaskId,
        [string]$UserMessage
    )

    $Tasks = Get-PDAConversationTasks -State $State -FilesystemTasks $FilesystemTasks -ConversationKey $ConversationKey

    $LatestTask = $null
    if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        $LatestTask = $Tasks | Where-Object { [string]$_.task_id -eq $TaskId } | Select-Object -First 1
    }
    if (-not $LatestTask -and $State.conversations.ContainsKey($ConversationKey) -and $State.conversations[$ConversationKey].latest_task_id) {
        $StateLatestTaskId = [string]$State.conversations[$ConversationKey].latest_task_id
        $LatestTask = $Tasks | Where-Object { [string]$_.task_id -eq $StateLatestTaskId } | Select-Object -First 1
        if (-not $LatestTask -and $State.tasks.ContainsKey($StateLatestTaskId)) {
            $LatestTask = [pscustomobject](ConvertTo-PDAHashtable -Value $State.tasks[$StateLatestTaskId])
        }
        if (-not $LatestTask -and $FilesystemTasks.ContainsKey($StateLatestTaskId)) {
            $LatestTask = [pscustomobject](ConvertTo-PDAHashtable -Value $FilesystemTasks[$StateLatestTaskId])
        }
    }
    if (-not $LatestTask -and $Tasks.Count -gt 0) {
        $LatestTask = $Tasks[0]
    }

    $LatestResult = $null
    foreach ($Task in ($Tasks | Where-Object { [string]$_.task_status -eq "completed" } )) {
        if ($Task.result_path -and (Test-Path -Path $Task.result_path -PathType Leaf)) {
            $LatestResult = $Task
            break
        }
    }

    $TaskResponseText = "No tracked PDA task found for this conversation."
    $TaskNextAction = "Ask the PDA to start a new task or confirm a queued request."

    if ($LatestTask) {
        $LatestCommand = if ($LatestTask.command) { [string]$LatestTask.command } else { "" }
        $LatestStatus = if ($LatestTask.task_status) { [string]$LatestTask.task_status } else { "" }
        $LatestTaskId = if ($LatestTask.task_id) { [string]$LatestTask.task_id } else { "" }

        if ($LatestStatus -eq "completed") {
            $LatestLocation = if ($LatestTask.result_path) { [string]$LatestTask.result_path } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($LatestLocation)) {
                $TaskResponseText = "Task $LatestTaskId for $LatestCommand is completed. Output located at $LatestLocation."
            }
            else {
                $TaskResponseText = "Task $LatestTaskId for $LatestCommand is completed."
            }
            $TaskNextAction = "Open the result path or ask for a summary of the latest output."
        }
        elseif ($LatestStatus -eq "running") {
            $TaskResponseText = "Task $LatestTaskId for $LatestCommand is running."
            $TaskNextAction = "Wait for the queue worker to finish, then ask again for the latest status."
        }
        elseif ($LatestStatus -eq "pending_approval" -or $LatestTask.requires_confirmation -eq $true) {
            $TaskResponseText = "Task $LatestTaskId for $LatestCommand is waiting for approval."
            $TaskNextAction = "Confirm the request if you want the governed submitter to dispatch it."
        }
        elseif ($LatestStatus -eq "failed") {
            $TaskResponseText = "Task $LatestTaskId for $LatestCommand failed."
            $TaskNextAction = "Inspect the failure reason and retry through the governed route if needed."
        }
        elseif ($LatestStatus -eq "queued" -or $LatestStatus -eq "submitted" -or $LatestStatus -eq "pending") {
            $TaskResponseText = "Task $LatestTaskId for $LatestCommand has been submitted and is waiting in the queue."
            $TaskNextAction = "Wait for the queue worker to finish, then ask again for the latest status."
        }
    }

    $LatestResultResponseText = ""
    if ($LatestResult -and $LatestResult.result_path) {
        $LatestResultResponseText = "Latest result for this conversation is available at $([string]$LatestResult.result_path)."
    }

    $PreferLatestResult = $false
    if (-not [string]::IsNullOrWhiteSpace($UserMessage)) {
        $PreferLatestResult = [bool]($UserMessage -match '(?i)\b(latest result|show latest result|show result|result location|result artifact|latest output|output location|what happened to my task|what happened with my task)\b')
    }

    $ResponseText = if ($PreferLatestResult -and -not [string]::IsNullOrWhiteSpace($LatestResultResponseText)) {
        $LatestResultResponseText
    } else {
        $TaskResponseText
    }

    $NextAction = if ($PreferLatestResult -and -not [string]::IsNullOrWhiteSpace($LatestResultResponseText)) {
        "Open the latest result artifact or ask for a summary of the output."
    } else {
        $TaskNextAction
    }

    $Conversation = $null
    if ($State.conversations.ContainsKey($ConversationKey)) {
        $Conversation = ConvertTo-PDAHashtable -Value $State.conversations[$ConversationKey]
        $Conversation.latest_task_id = if ($LatestTask) { [string]$LatestTask.task_id } else { [string]$Conversation.latest_task_id }
        $Conversation.latest_task_status = if ($LatestTask) { [string]$LatestTask.task_status } else { [string]$Conversation.latest_task_status }
        $Conversation.latest_result_path = if ($LatestResult) { [string]$LatestResult.result_path } else { [string]$Conversation.latest_result_path }
        $Conversation.latest_response_text = $ResponseText
        $Conversation.pending_approval_count = @($Tasks | Where-Object { $_.requires_confirmation -eq $true -or $_.task_status -eq "pending_approval" }).Count
        $Conversation.active_task_count = @($Tasks | Where-Object { $_.task_status -in @("queued", "pending", "running", "submitted", "approved", "pending_approval") }).Count
        $Conversation.completed_task_count = @($Tasks | Where-Object { $_.task_status -eq "completed" }).Count
        $Conversation.submitted_task_count = @($Tasks | Where-Object { $_.dispatch_status -eq "submitted" -or $_.task_status -in @("queued", "pending", "running", "completed", "failed", "approved", "pending_approval") }).Count
        $Conversation.updated_at = if ($Conversation.updated_at) { [string]$Conversation.updated_at } else { (Get-Date).ToUniversalTime().ToString("o") }
    }

    $ResultArtifact = $null
    if ($LatestResult -and $LatestResult.result_path -and (Test-Path -Path $LatestResult.result_path -PathType Leaf)) {
        try {
            $ResultArtifact = Get-Content -Path $LatestResult.result_path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            $ResultArtifact = $null
        }
    }

    return [pscustomobject]@{
        conversation_id            = $ConversationKey
        conversation               = if ($Conversation) { [pscustomobject]$Conversation } else { $null }
        tasks                      = @($Tasks)
        active_tasks               = @($Tasks | Where-Object { $_.task_status -in @("queued", "pending", "running", "submitted", "approved", "pending_approval") })
        pending_approvals          = @($Tasks | Where-Object { $_.requires_confirmation -eq $true -or $_.task_status -eq "pending_approval" })
        submitted_tasks            = @($Tasks | Where-Object { $_.dispatch_status -eq "submitted" -or $_.task_status -in @("queued", "pending", "running", "completed", "failed", "approved", "pending_approval") })
        completed_tasks            = @($Tasks | Where-Object { $_.task_status -eq "completed" })
        latest_task                = if ($LatestTask) { $LatestTask } else { $null }
        latest_result              = if ($LatestResult) { $LatestResult } else { $null }
        result_artifact            = $ResultArtifact
        response_text              = $ResponseText
        latest_result_response_text = $LatestResultResponseText
        next_action                = $NextAction
    }
}

$State = Load-PDAConversationState
$FilesystemTasks = Get-PDATaskFilesystemSnapshot -RootPath $Root
$ResolvedConversationId = Resolve-PDAConversationId -State $State -FilesystemTasks $FilesystemTasks -ConversationId $ConversationId -SessionId $SessionId -TaskId $TaskId
$ResolvedTaskId = if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
    $TaskId
} elseif (-not [string]::IsNullOrWhiteSpace($ResolvedConversationId) -and $State.conversations.ContainsKey($ResolvedConversationId)) {
    [string]$State.conversations[$ResolvedConversationId].latest_task_id
} else {
    ""
}

$ConversationResult = $null
if (-not [string]::IsNullOrWhiteSpace($ResolvedConversationId)) {
    $ConversationResult = Get-PDATaskResultResponse -State $State -FilesystemTasks $FilesystemTasks -ConversationKey $ResolvedConversationId -TaskId $ResolvedTaskId -UserMessage $UserMessage
}

$Report = [pscustomobject]@{
    status                      = if ($ConversationResult) { "pass" } elseif ($State.conversations.Count -gt 0) { "partial" } else { "empty" }
    registry_path               = $ResolvedStatePath
    conversation_id             = $ResolvedConversationId
    session_id                  = $SessionId
    task_id                     = $ResolvedTaskId
    latest_task_id              = if ($ConversationResult -and $ConversationResult.latest_task) { [string]$ConversationResult.latest_task.task_id } else { "" }
    latest_task_status          = if ($ConversationResult -and $ConversationResult.latest_task) { [string]$ConversationResult.latest_task.task_status } else { "" }
    latest_result_path          = if ($ConversationResult -and $ConversationResult.latest_result) { [string]$ConversationResult.latest_result.result_path } else { "" }
    result_artifact_path        = if ($ConversationResult -and $ConversationResult.latest_result) { [string]$ConversationResult.latest_result.result_path } else { "" }
    query                       = [pscustomobject]@{
        conversation_id = $ConversationId
        session_id      = $SessionId
        task_id         = $TaskId
        user_message    = $UserMessage
    }
    conversation                = if ($ConversationResult) { $ConversationResult.conversation } else { $null }
    active_tasks                = if ($ConversationResult) { $ConversationResult.active_tasks } else { @() }
    pending_approvals           = if ($ConversationResult) { $ConversationResult.pending_approvals } else { @() }
    submitted_tasks             = if ($ConversationResult) { $ConversationResult.submitted_tasks } else { @() }
    completed_tasks             = if ($ConversationResult) { $ConversationResult.completed_tasks } else { @() }
    latest_task                 = if ($ConversationResult) { $ConversationResult.latest_task } else { $null }
    latest_result               = if ($ConversationResult) { $ConversationResult.latest_result } else { $null }
    result_artifact             = if ($ConversationResult) { $ConversationResult.result_artifact } else { $null }
    latest_result_response_text  = if ($ConversationResult) { $ConversationResult.latest_result_response_text } else { "" }
    response_text               = if ($ConversationResult) { $ConversationResult.response_text } else { "No tracked PDA task found for this conversation." }
    next_action                 = if ($ConversationResult) { $ConversationResult.next_action } else { "Ask the PDA to start a new task or confirm a queued request." }
    pending_approval_count      = if ($ConversationResult) { $ConversationResult.pending_approvals.Count } else { 0 }
    active_task_count           = if ($ConversationResult) { $ConversationResult.active_tasks.Count } else { 0 }
    submitted_task_count        = if ($ConversationResult) { $ConversationResult.submitted_tasks.Count } else { 0 }
    completed_task_count        = if ($ConversationResult) { $ConversationResult.completed_tasks.Count } else { 0 }
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 30
    if (-not $NoThrow -and $Report.status -eq "empty") {
        throw "PDA task result lookup is empty."
    }
    return
}

Write-Host "[PDA TASK RESULT]"
Write-Host ("Registry path   : {0}" -f $Report.registry_path)
Write-Host ("Conversation ID : {0}" -f $(if ($Report.conversation_id) { $Report.conversation_id } else { "(none)" }))
Write-Host ("Session ID      : {0}" -f $(if ($Report.session_id) { $Report.session_id } else { "(none)" }))
Write-Host ("Task ID         : {0}" -f $(if ($Report.task_id) { $Report.task_id } else { "(none)" }))
Write-Host ("Active tasks    : {0}" -f $Report.active_task_count)
Write-Host ("Pending approvals: {0}" -f $Report.pending_approval_count)
Write-Host ("Completed tasks  : {0}" -f $Report.completed_task_count)
Write-Host ("Response text    : {0}" -f $Report.response_text)
Write-Host ("Next action      : {0}" -f $Report.next_action)
