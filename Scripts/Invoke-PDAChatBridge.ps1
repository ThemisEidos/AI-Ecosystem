[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Message,

    [Parameter(Mandatory = $false)]
    [switch]$ConfirmDispatch,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [string]$ConversationId,

    [Parameter(Mandatory = $false)]
    [string]$SessionId,

    [Parameter(Mandatory = $false)]
    [string]$UserId,

    [Parameter(Mandatory = $false)]
    [string]$ConversationTitle
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$HandoffScript = Join-Path $PSScriptRoot "Invoke-PDACommandHandoff.ps1"
$ConversationStateScript = Join-Path $PSScriptRoot "Get-PDAConversationState.ps1"
$TaskResultScript = Join-Path $PSScriptRoot "Get-PDATaskResult.ps1"
$UpdateConversationStateScript = Join-Path $PSScriptRoot "Update-PDAConversationState.ps1"

if (-not (Test-Path -Path $HandoffScript -PathType Leaf)) {
    throw "Command handoff missing: $HandoffScript"
}

function Test-PDAStatusLookupMessage {
    param([Parameter(Mandatory = $true)][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    return [bool]($Text -match '(?i)\b(status|what happened|where is|how is|did it finish|latest result|result location|what happened to)\b')
}

function Test-PDAOperatorConsoleMessage {
    param([Parameter(Mandatory = $true)][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $Normalized = $Text.Trim().ToLowerInvariant()
    return [bool]($Normalized -match '^(\/status|\/tasks|\/approvals|\/workers|\/reports|\/memory|\/help)(\b|\s|$)')
}

function Test-PDAConfirmationMessage {
    param([Parameter(Mandatory = $true)][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $Normalized = $Text.Trim().ToLowerInvariant()
    return [bool]($Normalized -match '^(confirm|yes|approve|proceed|dispatch)\b')
}

function Get-PDAConversationPendingActionFromSummary {
    param([Parameter(Mandatory = $false)]$ConversationState)

    if (-not $ConversationState) {
        return $null
    }

    if ($ConversationState.pending_action) {
        return $ConversationState.pending_action
    }

    if ($ConversationState.conversation -and $ConversationState.conversation.pending_recommended_command) {
        return [pscustomobject]@{
            recommended_command = [string]$ConversationState.conversation.pending_recommended_command
            dispatch_category    = [string]$ConversationState.conversation.pending_dispatch_category
            original_message     = [string]$ConversationState.conversation.pending_original_message
            timestamp            = [string]$ConversationState.conversation.pending_timestamp
            expires_at           = [string]$ConversationState.conversation.pending_expires_at
            status               = [string]$ConversationState.conversation.pending_status
            is_expired           = [bool]$ConversationState.conversation.pending_is_expired
        }
    }

    return $null
}

function Get-PDAPendingConfirmationTimeoutMinutes {
    $DefaultMinutes = 30
    $EnvValue = [string]$env:PDA_PENDING_CONFIRMATION_TIMEOUT_MINUTES
    if ([string]::IsNullOrWhiteSpace($EnvValue)) {
        return $DefaultMinutes
    }

    $Parsed = 0
    if ([int]::TryParse($EnvValue, [ref]$Parsed) -and $Parsed -gt 0) {
        return $Parsed
    }

    return $DefaultMinutes
}

function Invoke-PDAConversationStateQuery {
    param(
        [string]$ConversationId,
        [string]$SessionId,
        [string]$Message
    )

    if (-not (Test-Path -Path $ConversationStateScript -PathType Leaf)) {
        return $null
    }

    $Args = @("-AsJson")
    if (-not [string]::IsNullOrWhiteSpace($ConversationId)) {
        $Args += @("-ConversationId", $ConversationId)
    }
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $Args += @("-SessionId", $SessionId)
    }
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $Args += @("-UserMessage", $Message)
    }

    try {
        $Raw = & pwsh -NoProfile -File $ConversationStateScript @Args 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $null
        }

        $JsonText = [string]($Raw -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($JsonText)) {
            return $null
        }

        return $JsonText | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Invoke-PDATaskResultQuery {
    param(
        [string]$ConversationId,
        [string]$SessionId,
        [string]$Message
    )

    if (-not (Test-Path -Path $TaskResultScript -PathType Leaf)) {
        return $null
    }

    $Args = @("-AsJson")
    if (-not [string]::IsNullOrWhiteSpace($ConversationId)) {
        $Args += @("-ConversationId", $ConversationId)
    }
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $Args += @("-SessionId", $SessionId)
    }
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $Args += @("-UserMessage", $Message)
    }

    try {
        $Raw = & pwsh -NoProfile -File $TaskResultScript @Args 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $null
        }

        $JsonText = [string]($Raw -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($JsonText)) {
            return $null
        }

        return $JsonText | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Invoke-PDAConversationStateUpdate {
    param(
        [string]$TaskId,
        [string]$TaskStatus,
        [string]$TaskFilePath,
        [string]$ApprovalFilePath,
        [string]$ResultPath,
        [string]$ResultSummary,
        [string]$BridgeStatus,
        [string]$DispatchStatus,
        [string]$NextAction,
        [string]$ResponseText,
        [string]$RecommendedCommand,
        [string]$Intent,
        [double]$Confidence = 0,
        [bool]$RequiresConfirmation = $false,
        [string]$PendingRecommendedCommand,
        [string]$PendingDispatchCategory,
        [string]$PendingOriginalMessage,
        [string]$PendingTimestamp,
        [string]$PendingExpiresAt,
        [string]$PendingStatus,
        [switch]$ClearPendingAction
    )

    if (-not (Test-Path -Path $UpdateConversationStateScript -PathType Leaf)) {
        return $null
    }

    $LogPath = Join-Path $Root "PDA-Logs\conversation-state-bridge.log"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
    Add-Content -Path $LogPath -Value ("{0} update-start conversation={1} session={2} task={3}" -f (Get-Date -Format o), $(if ($ConversationId) { $ConversationId } else { "default" }), $(if ($SessionId) { $SessionId } else { "" }), $(if ($TaskId) { $TaskId } else { "" }))

    $Args = @(
        "-ConversationId", $(if ([string]::IsNullOrWhiteSpace($ConversationId)) { "default" } else { $ConversationId }),
        "-SessionId", $SessionId,
        "-UserId", $UserId,
        "-ConversationTitle", $ConversationTitle,
        "-UserMessage", $Message,
        "-RecommendedCommand", $RecommendedCommand,
        "-Intent", $Intent,
        "-Confidence", $Confidence,
        "-RequiresConfirmation", $RequiresConfirmation,
        "-DispatchStatus", $DispatchStatus,
        "-BridgeStatus", $BridgeStatus,
        "-NextAction", $NextAction,
        "-ResponseText", $ResponseText
    )

    if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        $Args += @("-TaskId", $TaskId)
    }
    if (-not [string]::IsNullOrWhiteSpace($TaskStatus)) {
        $Args += @("-TaskStatus", $TaskStatus)
    }
    if (-not [string]::IsNullOrWhiteSpace($TaskFilePath)) {
        $Args += @("-TaskFilePath", $TaskFilePath)
    }
    if (-not [string]::IsNullOrWhiteSpace($ApprovalFilePath)) {
        $Args += @("-ApprovalFilePath", $ApprovalFilePath)
    }
    if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
        $Args += @("-ResultPath", $ResultPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($ResultSummary)) {
        $Args += @("-ResultSummary", $ResultSummary)
    }
    if (-not [string]::IsNullOrWhiteSpace($PendingRecommendedCommand)) {
        $Args += @("-PendingRecommendedCommand", $PendingRecommendedCommand)
    }
    if (-not [string]::IsNullOrWhiteSpace($PendingDispatchCategory)) {
        $Args += @("-PendingDispatchCategory", $PendingDispatchCategory)
    }
    if (-not [string]::IsNullOrWhiteSpace($PendingOriginalMessage)) {
        $Args += @("-PendingOriginalMessage", $PendingOriginalMessage)
    }
    if (-not [string]::IsNullOrWhiteSpace($PendingTimestamp)) {
        $Args += @("-PendingTimestamp", $PendingTimestamp)
    }
    if (-not [string]::IsNullOrWhiteSpace($PendingExpiresAt)) {
        $Args += @("-PendingExpiresAt", $PendingExpiresAt)
    }
    if (-not [string]::IsNullOrWhiteSpace($PendingStatus)) {
        $Args += @("-PendingStatus", $PendingStatus)
    }
    if ($ClearPendingAction) {
        $Args += "-ClearPendingAction"
    }

    try {
        $Raw = & pwsh -NoProfile -File $UpdateConversationStateScript @Args -AsJson 2>&1
        $Text = [string]($Raw -join "`n").Trim()
        if (-not [string]::IsNullOrWhiteSpace($Text)) {
            Add-Content -Path $LogPath -Value ("{0} update-output {1}" -f (Get-Date -Format o), $Text.Replace("`r", " ").Replace("`n", " "))
        }
        else {
            Add-Content -Path $LogPath -Value ("{0} update-output (empty)" -f (Get-Date -Format o))
        }
    }
    catch {
        try {
            Add-Content -Path $LogPath -Value ("{0} update-error {1}" -f (Get-Date -Format o), $_.Exception.Message.Replace("`r", " ").Replace("`n", " "))
        }
        catch {}
        return $null
    }
}

function Resolve-PDATaskFileFromDispatchPath {
    param([string]$DispatchPath)

    if ([string]::IsNullOrWhiteSpace($DispatchPath)) {
        return $null
    }

    if (Test-Path -Path $DispatchPath -PathType Leaf) {
        return Get-Item -Path $DispatchPath
    }

    $Leaf = Split-Path -Path $DispatchPath -Leaf
    foreach ($CandidateRoot in @(
        (Join-Path $Root "PDA-Tasks\pending"),
        (Join-Path $Root "PDA-Tasks\approvals\pending"),
        (Join-Path $Root "PDA-Tasks\approvals\approved"),
        (Join-Path $Root "PDA-Tasks\approvals\rejected"),
        (Join-Path $Root "PDA-Tasks\running"),
        (Join-Path $Root "PDA-Tasks\completed"),
        (Join-Path $Root "PDA-Tasks\failed")
    )) {
        $Candidate = Join-Path $CandidateRoot $Leaf
        if (Test-Path -Path $Candidate -PathType Leaf) {
            return Get-Item -Path $Candidate
        }
    }

    return $null
}

function Get-PDATaskIdFromFile {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$FileInfo)

    try {
        $Json = Get-Content -Path $FileInfo.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($Json.PSObject.Properties.Name -contains "task_id" -and -not [string]::IsNullOrWhiteSpace([string]$Json.task_id)) {
            return [string]$Json.task_id
        }
    }
    catch {
        return ""
    }

    return ""
}

$ConversationState = Invoke-PDAConversationStateQuery -ConversationId $ConversationId -SessionId $SessionId -Message $Message
$PendingAction = Get-PDAConversationPendingActionFromSummary -ConversationState $ConversationState
$HasPendingAction = $PendingAction -and -not [bool]$PendingAction.is_expired
$IsConfirmationMessage = Test-PDAConfirmationMessage -Text $Message
$IsStatusLookup = Test-PDAStatusLookupMessage -Text $Message
$IsOperatorConsoleCommand = Test-PDAOperatorConsoleMessage -Text $Message

if ($IsConfirmationMessage -and -not $HasPendingAction) {
    if ($PendingAction -and [bool]$PendingAction.is_expired) {
        Invoke-PDAConversationStateUpdate -TaskId "" -TaskStatus "" -ResultPath "" -BridgeStatus "ready" -DispatchStatus "not_dispatched" -NextAction "Start a new request or ask for a status refresh." -ResponseText "Pending confirmation expired for this conversation." -RecommendedCommand "" -Intent "confirmation" -Confidence 1 -RequiresConfirmation:$false -ClearPendingAction | Out-Null
    }

    $Result = [pscustomobject]@{
        original_message         = $Message
        response_text            = "No pending governed action found for this conversation."
        recommended_command      = ""
        intent                   = "confirmation"
        confidence               = 1
        requires_confirmation    = $false
        dispatch_ready           = $false
        dispatch_status          = "not_dispatched"
        next_action              = "Start a new request or request a status lookup."
        bridge_status            = "ready"
        handoff_status           = "no_pending_confirmation"
        source_of_truth          = "Scripts/Get-PDAConversationState.ps1"
        confirmation_mode        = [bool]$ConfirmDispatch
        dispatch_path            = ""
        dispatch_category        = ""
        conversation_id          = $(if ($ConversationId) { $ConversationId } elseif ($ConversationState -and $ConversationState.conversation_id) { [string]$ConversationState.conversation_id } else { "" })
        session_id               = $SessionId
        conversation_state_status = if ($ConversationState) { [string]$ConversationState.status } else { "empty" }
        latest_task_id           = if ($ConversationState -and $ConversationState.latest_task) { [string]$ConversationState.latest_task.task_id } else { "" }
        latest_task_status       = if ($ConversationState -and $ConversationState.latest_task) { [string]$ConversationState.latest_task.task_status } else { "" }
        latest_result_path       = if ($ConversationState -and $ConversationState.latest_result) { [string]$ConversationState.latest_result.result_path } else { "" }
        latest_result_response_text = if ($ConversationState) { [string]$ConversationState.response_text } else { "" }
        result_artifact_path     = if ($ConversationState -and $ConversationState.latest_result) { [string]$ConversationState.latest_result.result_path } else { "" }
        result_artifact          = if ($ConversationState) { $ConversationState.latest_result } else { $null }
        bridge_mode              = "confirmation_replay"
        pending_action           = if ($PendingAction) { $PendingAction } else { $null }
    }

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        return
    }

    Write-Host "[OK] PDA chat bridge result:"
    Write-Host ("Response text        : {0}" -f $Result.response_text)
    Write-Host ("Recommended command  : {0}" -f $(if ($Result.recommended_command) { $Result.recommended_command } else { "(none)" }))
    Write-Host ("Intent               : {0}" -f $(if ($Result.intent) { $Result.intent } else { "(none)" }))
    Write-Host ("Confidence           : {0}" -f $Result.confidence)
    Write-Host ("Dispatch ready       : {0}" -f $Result.dispatch_ready)
    Write-Host ("Dispatch status      : {0}" -f $Result.dispatch_status)
    Write-Host ("Next action          : {0}" -f $Result.next_action)
    return
}

if ($HasPendingAction -and ($IsConfirmationMessage -or $ConfirmDispatch)) {
    $DispatchMessage = if ($PendingAction.original_message) { [string]$PendingAction.original_message } else { $Message }
    $ConfirmationArgs = @(
        "-Text", $DispatchMessage,
        "-AsJson",
        "-ConfirmDispatch",
        "-ConversationId", $(if ($ConversationId) { $ConversationId } else { "" }),
        "-SessionId", $(if ($SessionId) { $SessionId } else { "" }),
        "-UserId", $(if ($UserId) { $UserId } else { "" }),
        "-ConversationTitle", $(if ($ConversationTitle) { $ConversationTitle } else { "" })
    )

    $Raw = & pwsh -NoProfile -File $HandoffScript @ConfirmationArgs
    $Handoff = $Raw | ConvertFrom-Json

    $ResponseText = ""
    $NextAction = ""

    if ($Handoff.dispatch_status -eq "not_applicable") {
        $ResponseText = [string]$Handoff.response_text
        $NextAction = [string]$Handoff.next_action
    }
    elseif ($Handoff.dispatch_status -eq "submitted") {
        $ResponseText = "Dispatched via governed PDA handoff using $($Handoff.recommended_command)."
        $NextAction = "Dispatch submitted through the governed submitter."
    }
    elseif ($Handoff.requires_confirmation) {
        $ResponseText = "Recommended command: $($Handoff.recommended_command). Confirm to dispatch."
        $NextAction = "Reply with confirmation to submit through the governed handoff."
    }
    else {
        $ResponseText = "Recommended command: $($Handoff.recommended_command)."
        $NextAction = "Review the recommendation before dispatch."
    }

    $DispatchPath = [string]$Handoff.dispatch_path
    $TaskFile = Resolve-PDATaskFileFromDispatchPath -DispatchPath $DispatchPath
    $TaskId = ""
    $TaskStatus = ""
    $ApprovalPath = ""
    $ResultPath = ""

    if ($TaskFile) {
        $TaskId = Get-PDATaskIdFromFile -FileInfo $TaskFile
        if ($TaskFile.FullName -match '\\approvals\\pending\\') {
            $ApprovalPath = $TaskFile.FullName
            $TaskStatus = "pending_approval"
        }
        elseif ($TaskFile.FullName -match '\\running\\') {
            $TaskStatus = "running"
        }
        elseif ($TaskFile.FullName -match '\\completed\\') {
            $TaskStatus = "completed"
        }
        elseif ($TaskFile.FullName -match '\\failed\\') {
            $TaskStatus = "failed"
        }
        elseif ($TaskFile.FullName -match '\\pending\\') {
            $TaskStatus = "queued"
        }

        if (-not [string]::IsNullOrWhiteSpace($TaskId) -and $TaskStatus -eq "completed") {
            try {
                $TaskJson = Get-Content -Path $TaskFile.FullName -Raw | ConvertFrom-Json
                if ($TaskJson.PSObject.Properties.Name -contains "result_path" -and -not [string]::IsNullOrWhiteSpace([string]$TaskJson.result_path)) {
                    $ResultPath = [string]$TaskJson.result_path
                }
            }
            catch {}
        }
    }

    if ($Handoff.dispatch_status -eq "submitted") {
        Invoke-PDAConversationStateUpdate -TaskId $TaskId -TaskStatus $TaskStatus -TaskFilePath $(if ($TaskFile) { $TaskFile.FullName } else { "" }) -ApprovalFilePath $ApprovalPath -ResultPath $ResultPath -BridgeStatus "submitted" -DispatchStatus $Handoff.dispatch_status -NextAction $NextAction -ResponseText $ResponseText -RecommendedCommand $Handoff.recommended_command -Intent $Handoff.intent -Confidence $Handoff.confidence -RequiresConfirmation:([bool]$Handoff.requires_confirmation) -PendingRecommendedCommand ([string]$PendingAction.recommended_command) -PendingDispatchCategory ([string]$PendingAction.dispatch_category) -PendingOriginalMessage ([string]$PendingAction.original_message) -PendingTimestamp ([string]$PendingAction.timestamp) -PendingExpiresAt ([string]$PendingAction.expires_at) -PendingStatus "dispatched" -ClearPendingAction | Out-Null
    }

    $Result = [pscustomobject]@{
        original_message         = $Message
        response_text            = $ResponseText
        recommended_command      = [string]$Handoff.recommended_command
        intent                   = [string]$Handoff.intent
        confidence               = [double]$Handoff.confidence
        requires_confirmation    = [bool]$Handoff.requires_confirmation
        dispatch_ready           = [bool]$Handoff.dispatch_ready
        dispatch_status          = [string]$Handoff.dispatch_status
        next_action              = $NextAction
        bridge_status            = if ($Handoff.dispatch_status -eq "submitted") { "submitted" } elseif ($Handoff.interpreter_status -eq "mapped") { "ready" } else { "needs_clarification" }
        handoff_status           = [string]$Handoff.interpreter_status
        source_of_truth          = "Scripts/PDA_CommandInterpreter.ps1"
        confirmation_mode        = [bool]$ConfirmDispatch
        dispatch_path            = $DispatchPath
        dispatch_category        = [string]$Handoff.dispatch_category
        conversation_id          = $(if ($ConversationId) { $ConversationId } else { $(if ($ConversationState -and $ConversationState.conversation_id) { [string]$ConversationState.conversation_id } else { "" }) })
        session_id               = $SessionId
        conversation_state_status = if ($ConversationState) { [string]$ConversationState.status } else { "empty" }
        latest_task_id           = $TaskId
        latest_task_status       = $TaskStatus
        latest_result_path       = $ResultPath
        bridge_mode              = "confirmation_replay"
        pending_action           = if ($PendingAction) { $PendingAction } else { $null }
    }

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        return
    }

    Write-Host "[OK] PDA chat bridge result:"
    Write-Host ("Response text        : {0}" -f $Result.response_text)
    Write-Host ("Recommended command  : {0}" -f $(if ($Result.recommended_command) { $Result.recommended_command } else { "(none)" }))
    Write-Host ("Intent               : {0}" -f $(if ($Result.intent) { $Result.intent } else { "(none)" }))
    Write-Host ("Confidence           : {0}" -f $Result.confidence)
    Write-Host ("Dispatch ready       : {0}" -f $Result.dispatch_ready)
    Write-Host ("Dispatch status      : {0}" -f $Result.dispatch_status)
    Write-Host ("Next action          : {0}" -f $Result.next_action)
    return
}

if ($IsStatusLookup -and -not $IsOperatorConsoleCommand) {
    $TaskResult = Invoke-PDATaskResultQuery -ConversationId $ConversationId -SessionId $SessionId -Message $Message
    if (-not $TaskResult) {
        $TaskResult = Invoke-PDAConversationStateQuery -ConversationId $ConversationId -SessionId $SessionId -Message $Message
    }

    $LatestTask = $null
    $ResponseText = "No tracked PDA task found for this conversation."
    $NextAction = "Start a governed PDA task or confirm a request so the bridge can track it."
    $RecommendedCommand = ""
    $Intent = "status_lookup"
    $Confidence = 1
    $LatestTaskStatus = ""
    $LatestTaskId = ""
    $LatestResultPath = ""

    if ($TaskResult -and $TaskResult.conversation_id) {
        $LatestTask = $TaskResult.latest_task
        if ($LatestTask) {
            $LatestTaskId = [string]$LatestTask.task_id
            $LatestTaskStatus = [string]$LatestTask.task_status
            $RecommendedCommand = if ($LatestTask.command) { [string]$LatestTask.command } else { "" }
            $Intent = if ($LatestTask.intent) { [string]$LatestTask.intent } else { "status_lookup" }
            $LatestResultPath = if ($TaskResult.latest_result -and $TaskResult.latest_result.result_path) {
                [string]$TaskResult.latest_result.result_path
            } elseif ($TaskResult.result_artifact -and $TaskResult.result_artifact.saved_path) {
                [string]$TaskResult.result_artifact.saved_path
            } else {
                ""
            }
        }

        $ResponseText = [string]$TaskResult.response_text
        $NextAction = [string]$TaskResult.next_action
    }

    $Result = [pscustomobject]@{
        original_message         = $Message
        response_text            = $ResponseText
        recommended_command      = $RecommendedCommand
        intent                   = $Intent
        confidence               = [double]$Confidence
        requires_confirmation    = $false
        dispatch_ready           = $false
        dispatch_status          = "not_dispatched"
        next_action              = $NextAction
        bridge_status            = "ready"
        handoff_status           = "status_lookup"
        source_of_truth          = "Scripts/Get-PDATaskResult.ps1"
        confirmation_mode        = [bool]$ConfirmDispatch
        dispatch_path            = ""
        dispatch_category        = ""
        conversation_id          = $(if ($ConversationId) { $ConversationId } elseif ($TaskResult -and $TaskResult.conversation_id) { [string]$TaskResult.conversation_id } else { "" })
        session_id               = $SessionId
        conversation_state_status = $(if ($TaskResult) { [string]$TaskResult.status } else { "empty" })
        latest_task_id           = $LatestTaskId
        latest_task_status       = $LatestTaskStatus
        latest_result_path       = $LatestResultPath
        latest_result_response_text = $(if ($TaskResult) { [string]$TaskResult.latest_result_response_text } else { "" })
        result_artifact_path     = $(if ($TaskResult -and $TaskResult.latest_result) { [string]$TaskResult.latest_result.result_path } else { "" })
        result_artifact          = $(if ($TaskResult) { $TaskResult.result_artifact } else { $null })
        bridge_mode              = "status_lookup"
    }

    Invoke-PDAConversationStateUpdate -TaskId $LatestTaskId -TaskStatus $LatestTaskStatus -ResultPath $LatestResultPath -BridgeStatus "ready" -DispatchStatus "not_dispatched" -NextAction $NextAction -ResponseText $ResponseText -RecommendedCommand $RecommendedCommand -Intent $Intent -Confidence $Confidence -RequiresConfirmation:$false | Out-Null

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        return
    }

    Write-Host "[OK] PDA chat bridge result:"
    Write-Host ("Response text        : {0}" -f $Result.response_text)
    Write-Host ("Recommended command  : {0}" -f $(if ($Result.recommended_command) { $Result.recommended_command } else { "(none)" }))
    Write-Host ("Intent               : {0}" -f $(if ($Result.intent) { $Result.intent } else { "(none)" }))
    Write-Host ("Confidence           : {0}" -f $Result.confidence)
    Write-Host ("Dispatch ready       : {0}" -f $Result.dispatch_ready)
    Write-Host ("Dispatch status      : {0}" -f $Result.dispatch_status)
    Write-Host ("Next action          : {0}" -f $Result.next_action)
    return
}

$HandoffArgs = @(
    "-Text", $Message,
    "-AsJson",
    "-ConversationId", $(if ($ConversationId) { $ConversationId } else { "" }),
    "-SessionId", $(if ($SessionId) { $SessionId } else { "" }),
    "-UserId", $(if ($UserId) { $UserId } else { "" }),
    "-ConversationTitle", $(if ($ConversationTitle) { $ConversationTitle } else { "" })
)
if ($ConfirmDispatch) {
    $HandoffArgs += "-ConfirmDispatch"
}

$Raw = & pwsh -NoProfile -File $HandoffScript @HandoffArgs
$Handoff = $Raw | ConvertFrom-Json

$ResponseText = ""
$NextAction = ""

if ($Handoff.dispatch_status -eq "not_applicable") {
    $ResponseText = [string]$Handoff.response_text
    $NextAction = [string]$Handoff.next_action
}
else {
switch ($Handoff.interpreter_status) {
    "mapped" {
        if ($Handoff.dispatch_status -eq "submitted") {
            $ResponseText = "Dispatched via governed PDA handoff using $($Handoff.recommended_command)."
            $NextAction = "Dispatch submitted through the governed submitter."
        }
        elseif ($Handoff.requires_confirmation) {
            $ResponseText = "Recommended command: $($Handoff.recommended_command). Confirm to dispatch."
            $NextAction = "Reply with confirmation to submit through the governed handoff."
        }
        else {
            $ResponseText = "Recommended command: $($Handoff.recommended_command)."
            $NextAction = "Review the recommendation before dispatch."
        }
    }
    "ambiguous" {
        $ResponseText = "Clarification required. $($Handoff.ambiguity_reason)"
        $NextAction = "Refine the request so the interpreter returns one governed command."
    }
    default {
        $ResponseText = "No governed command matched. $($Handoff.ambiguity_reason)"
        $NextAction = "Rephrase using review, report, analyze, run, or research language."
    }
}
}

$PendingTimestamp = ""
$PendingExpiresAt = ""
if ($Handoff.interpreter_status -eq "mapped" -and $Handoff.requires_confirmation) {
    $PendingTimestamp = (Get-Date).ToUniversalTime().ToString("o")
    $PendingExpiresAt = (Get-Date).ToUniversalTime().AddMinutes((Get-PDAPendingConfirmationTimeoutMinutes)).ToString("o")
    Invoke-PDAConversationStateUpdate -TaskId "" -TaskStatus "pending_confirmation" -TaskFilePath "" -ApprovalFilePath "" -ResultPath "" -ResultSummary "" -BridgeStatus "ready" -DispatchStatus "not_dispatched" -NextAction $NextAction -ResponseText $ResponseText -RecommendedCommand $Handoff.recommended_command -Intent $Handoff.intent -Confidence $Handoff.confidence -RequiresConfirmation:([bool]$Handoff.requires_confirmation) -PendingRecommendedCommand ([string]$Handoff.recommended_command) -PendingDispatchCategory ([string]$Handoff.dispatch_category) -PendingOriginalMessage $Message -PendingTimestamp $PendingTimestamp -PendingExpiresAt $PendingExpiresAt -PendingStatus "awaiting_confirmation" | Out-Null
}

$DispatchPath = [string]$Handoff.dispatch_path
$TaskFile = Resolve-PDATaskFileFromDispatchPath -DispatchPath $DispatchPath
$TaskId = ""
$TaskStatus = ""
$ApprovalPath = ""
$ResultPath = ""

if ($TaskFile) {
    $TaskId = Get-PDATaskIdFromFile -FileInfo $TaskFile
    if ($TaskFile.FullName -match '\\approvals\\pending\\') {
        $ApprovalPath = $TaskFile.FullName
        $TaskStatus = "pending_approval"
    }
    elseif ($TaskFile.FullName -match '\\running\\') {
        $TaskStatus = "running"
    }
    elseif ($TaskFile.FullName -match '\\completed\\') {
        $TaskStatus = "completed"
    }
    elseif ($TaskFile.FullName -match '\\failed\\') {
        $TaskStatus = "failed"
    }
    elseif ($TaskFile.FullName -match '\\pending\\') {
        $TaskStatus = "queued"
    }

    if (-not [string]::IsNullOrWhiteSpace($TaskId) -and $TaskStatus -eq "completed") {
        try {
            $TaskJson = Get-Content -Path $TaskFile.FullName -Raw | ConvertFrom-Json
            if ($TaskJson.PSObject.Properties.Name -contains "result_path" -and -not [string]::IsNullOrWhiteSpace([string]$TaskJson.result_path)) {
                $ResultPath = [string]$TaskJson.result_path
            }
        }
        catch {}
    }
}

$Result = [pscustomobject]@{
    original_message         = $Message
    response_text            = $ResponseText
    recommended_command      = [string]$Handoff.recommended_command
    intent                   = [string]$Handoff.intent
    confidence               = [double]$Handoff.confidence
    requires_confirmation    = [bool]$Handoff.requires_confirmation
    dispatch_ready           = [bool]$Handoff.dispatch_ready
    dispatch_status          = [string]$Handoff.dispatch_status
    next_action              = $NextAction
    bridge_status            = if ($Handoff.dispatch_status -eq "submitted") { "submitted" } elseif ($Handoff.interpreter_status -eq "mapped") { "ready" } else { "needs_clarification" }
    handoff_status           = [string]$Handoff.interpreter_status
    source_of_truth          = "Scripts/PDA_CommandInterpreter.ps1"
    confirmation_mode        = [bool]$ConfirmDispatch
    dispatch_path            = $DispatchPath
    dispatch_category        = [string]$Handoff.dispatch_category
    conversation_id          = $(if ($ConversationId) { $ConversationId } else { "" })
    session_id               = $SessionId
    conversation_state_status = "unknown"
    latest_task_id           = $TaskId
    latest_task_status       = $TaskStatus
    latest_result_path       = $ResultPath
    bridge_mode              = "command_handoff"
}

Invoke-PDAConversationStateUpdate -TaskId $TaskId -TaskStatus $TaskStatus -TaskFilePath $(if ($TaskFile) { $TaskFile.FullName } else { "" }) -ApprovalFilePath $ApprovalPath -ResultPath $ResultPath -BridgeStatus $Result.bridge_status -DispatchStatus $Result.dispatch_status -NextAction $Result.next_action -ResponseText $Result.response_text -RecommendedCommand $Result.recommended_command -Intent $Result.intent -Confidence $Result.confidence -RequiresConfirmation:([bool]$Result.requires_confirmation) | Out-Null

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] PDA chat bridge result:"
Write-Host ("Response text        : {0}" -f $Result.response_text)
Write-Host ("Recommended command  : {0}" -f $(if ($Result.recommended_command) { $Result.recommended_command } else { "(none)" }))
Write-Host ("Intent               : {0}" -f $(if ($Result.intent) { $Result.intent } else { "(none)" }))
Write-Host ("Confidence           : {0}" -f $Result.confidence)
Write-Host ("Dispatch ready       : {0}" -f $Result.dispatch_ready)
Write-Host ("Dispatch status      : {0}" -f $Result.dispatch_status)
Write-Host ("Next action          : {0}" -f $Result.next_action)
