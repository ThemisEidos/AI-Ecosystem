[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow,

    [Parameter(Mandatory = $false)]
    [switch]$SkipOperatorConsole,

    [Parameter(Mandatory = $false)]
    [switch]$SkipDispatch,

    [Parameter(Mandatory = $false)]
    [switch]$DashboardMode
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$BridgeScript = Join-Path $PSScriptRoot "Invoke-PDAChatBridge.ps1"
$HandoffScript = Join-Path $PSScriptRoot "Invoke-PDACommandHandoff.ps1"
$StateScript = Join-Path $PSScriptRoot "Get-PDAConversationState.ps1"
$PendingRoot = Join-Path $Root "PDA-Tasks\pending"
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
if (Test-Path -Path $ParserPath -PathType Leaf) {
    . $ParserPath
}

if (-not (Test-Path -Path $BridgeScript -PathType Leaf)) {
    throw "Chat bridge missing: $BridgeScript"
}

function Find-QueueArtifactByMarker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Marker
    )

    foreach ($SearchRoot in @(
        $PendingRoot,
        (Join-Path $Root "PDA-Tasks\approvals\pending")
    )) {
        $Match = Get-ChildItem -Path $SearchRoot -Filter *.json -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    $Content = Get-Content $_.FullName -Raw -ErrorAction Stop
                    return ($Content -match [regex]::Escape($Marker))
                }
                catch {
                    return $false
                }
            } |
            Select-Object -First 1

        if ($Match) {
            return $Match
        }
    }
}

function Get-QueueArtifactCountByMarker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Marker
    )

    @(
        Get-ChildItem -Path $PendingRoot -Filter *.json -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    $Content = Get-Content $_.FullName -Raw -ErrorAction Stop
                    return ($Content -match [regex]::Escape($Marker))
                }
                catch {
                    return $false
                }
            }
    ).Count
}

function Invoke-JsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $ScriptArgs = @($Arguments | Where-Object { $_ -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$_) })
    $Raw = & $Path @ScriptArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Script failed: $Path"
    }

    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Script returned empty output: $Path"
    }

    return ConvertFrom-PDAMixedJson -Text $Text -SourceName $Path
}

$ScriptContent = Get-Content -Path $BridgeScript -Raw
if ($ScriptContent -notmatch 'Invoke-PDACommandHandoff\.ps1') {
    throw "Chat bridge does not call the governed handoff layer."
}

if ($ScriptContent -match 'Submit-PDATask\.ps1|Invoke-PDAWorker\.ps1|process-pda-queue\.ps1|Start-PDAQueueWorker\.ps1') {
    throw "Chat bridge contains a queue bypass or direct worker execution path."
}

$Results = @()
$Passed = 0
$Failed = 0

$Cases = @(
    [pscustomobject]@{
        name = "known message"
        message = "review my latest findings for the launch"
        confirm = $false
        expected_handoff = "mapped"
        expected_response_contains = "Recommended command"
        expected_dispatch_ready = $true
        expected_dispatch = $false
        expected_command = "/review"
        marker = "chat-known-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "ambiguous message"
        message = "review and analyze this project"
        confirm = $false
        expected_handoff = "ambiguous"
        expected_response_contains = "one action at a time"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = ""
        marker = "chat-ambiguous-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "unknown message"
        message = "blorf glarb frobnicate"
        confirm = $false
        expected_handoff = "fallback"
        expected_response_contains = "I can help with status"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = ""
        marker = "chat-unknown-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "confirmed dispatch"
        message = "review my latest findings for chat bridge dispatch"
        confirm = $true
        expected_handoff = "mapped"
        expected_response_contains = "Dispatched via governed PDA handoff"
        expected_dispatch_ready = $true
        expected_dispatch = $true
        expected_command = "/review"
        marker = "chat-dispatch-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "research request"
        message = "create a test research task"
        confirm = $false
        expected_handoff = "mapped"
        expected_response_contains = "Recommended command"
        expected_dispatch_ready = $true
        expected_dispatch = $false
        expected_command = "/research"
        marker = "chat-research-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "natural status"
        message = "How is the PDA doing?"
        confirm = $false
        expected_handoff = "direct_status"
        expected_response_contains = "dashboard is showing degraded health"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = "/status"
        marker = "chat-natural-status-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "natural help"
        message = "What can you do?"
        confirm = $false
        expected_handoff = "direct_help"
        expected_response_contains = "I can check status"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = "/help"
        marker = "chat-natural-help-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "status summary"
        message = "Summarize the ecosystem status."
        confirm = $false
        expected_handoff = "direct_status"
        expected_response_contains = "dashboard is showing degraded health"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = "/status"
        marker = "chat-status-summary-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "roadmap request"
        message = "Build me a roadmap."
        confirm = $false
        expected_handoff = "goal_planning"
        expected_response_contains = "Goal Assessment"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = ""
        marker = "chat-roadmap-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "classic literature goal"
        message = "I want to start reading classic literature. Can you search the internet, create a list of top books from famous authors, write a report, include links and synopses, and make it a PDF?"
        confirm = $false
        expected_handoff = "goal_planning"
        expected_response_contains = "Execution Plan"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = ""
        marker = "chat-goal-planning-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "ambiguous request"
        message = "Review and run this."
        confirm = $false
        expected_handoff = "ambiguous"
        expected_response_contains = "I can help with one action at a time"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = ""
        marker = "chat-ambiguous-natural-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "task lookup"
        message = "What happened to my last task?"
        confirm = $false
        expected_handoff = "task_lookup"
        expected_response_contains = "tracked PDA task"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = ""
        marker = "chat-task-lookup-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "memory candidates"
        message = "What memory candidates exist?"
        confirm = $false
        expected_handoff = "memory_candidates"
        expected_response_contains = "memory learning is tracking"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = "/memory"
        marker = "chat-memory-candidates-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "commander briefing"
        message = "Give me my PDA briefing."
        confirm = $false
        expected_handoff = "commander_briefing"
        expected_response_contains = "PDA DAILY BRIEF"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = ""
        marker = "chat-commander-briefing-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "dispatch guidance"
        message = "What should handle this task?"
        confirm = $false
        expected_handoff = "dispatch_guidance"
        expected_response_contains = "recommended executor"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = "/dispatch"
        marker = "chat-dispatch-guidance-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "blocked guidance"
        message = "What is blocked?"
        confirm = $false
        expected_handoff = "commander_briefing"
        expected_response_contains = "Focus: blocked"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = ""
        marker = "chat-blocked-guidance-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "slash fabric report with status wording"
        message = "/fabric report Summarize the current PDA ecosystem status..."
        confirm = $false
        expected_handoff = "mapped"
        expected_response_contains = "Recommended command"
        expected_dispatch_ready = $true
        expected_dispatch = $false
        expected_command = "/fabric report"
        marker = "chat-fabric-report-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "operator status"
        message = "/status"
        confirm = $false
        expected_handoff = "mapped"
        expected_response_contains = "PDA Operator Console: Status"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = "/status"
        marker = "chat-status-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "operator tasks"
        message = "/tasks"
        confirm = $false
        expected_handoff = "mapped"
        expected_response_contains = "PDA Operator Console: Tasks"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = "/tasks"
        marker = "chat-tasks-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "operator approvals"
        message = "/approvals"
        confirm = $false
        expected_handoff = "mapped"
        expected_response_contains = "PDA Operator Console: Approvals"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = "/approvals"
        marker = "chat-approvals-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "operator workers"
        message = "/workers"
        confirm = $false
        expected_handoff = "mapped"
        expected_response_contains = "PDA Operator Console: Workers"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = "/workers"
        marker = "chat-workers-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "operator reports"
        message = "/reports"
        confirm = $false
        expected_handoff = "mapped"
        expected_response_contains = "PDA Operator Console: Reports"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = "/reports"
        marker = "chat-reports-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "operator memory"
        message = "/memory"
        confirm = $false
        expected_handoff = "mapped"
        expected_response_contains = "PDA Operator Console: Memory"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = "/memory"
        marker = "chat-memory-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "operator help"
        message = "/help"
        confirm = $false
        expected_handoff = "mapped"
        expected_response_contains = "PDA Commander Operator Console Commands"
        expected_dispatch_ready = $false
        expected_dispatch = $false
        expected_command = "/help"
        marker = "chat-help-$([guid]::NewGuid().ToString())"
    }
)

if ($SkipOperatorConsole) {
    $Cases = @($Cases | Where-Object { [string]$_.name -notlike "operator *" })
}

if ($SkipDispatch) {
    $Cases = @($Cases | Where-Object { -not [bool]$_.expected_dispatch })
}

if ($DashboardMode) {
    $Cases = @($Cases | Where-Object { [string]$_.name -in @("known message", "ambiguous message", "unknown message", "research request") })
}

if (-not $SkipDispatch -and -not $DashboardMode) {
    $ConfirmationConversationId = "conv-confirm-$([guid]::NewGuid().ToString('N').Substring(0, 12))"
    $ConfirmationSessionId = "sess-confirm-$([guid]::NewGuid().ToString('N').Substring(0, 12))"
    $ConfirmationMarker = "confirm-flow-$([guid]::NewGuid().ToString())"

    $ConfirmationRequestRaw = & $BridgeScript -Message "generate a report [$ConfirmationMarker]" -ConversationId $ConfirmationConversationId -SessionId $ConfirmationSessionId -AsJson 2>&1
    $ConfirmationRequest = ConvertFrom-PDAMixedJson -Text ([string]($ConfirmationRequestRaw -join "`n")) -SourceName $BridgeScript

    $ConfirmationStateRaw = & $StateScript -ConversationId $ConfirmationConversationId -SessionId $ConfirmationSessionId -AsJson 2>&1
    $ConfirmationStateAfterRequest = ConvertFrom-PDAMixedJson -Text ([string]($ConfirmationStateRaw -join "`n")) -SourceName $StateScript

    $ConfirmationRequestIssues = New-Object System.Collections.Generic.List[string]
    if ($ConfirmationRequest.recommended_command -ne "/reporter") {
        $ConfirmationRequestIssues.Add("Expected /reporter recommendation for report request.")
    }
    if (-not [bool]$ConfirmationRequest.requires_confirmation) {
        $ConfirmationRequestIssues.Add("Report request should require confirmation.")
    }
    if ($ConfirmationRequest.dispatch_status -ne "not_dispatched") {
        $ConfirmationRequestIssues.Add("Report request should not dispatch before confirmation.")
    }
    if ($ConfirmationStateAfterRequest.conversation.pending_recommended_command -ne "/reporter") {
        $ConfirmationRequestIssues.Add("Pending confirmation command was not stored in conversation state.")
    }
    if ($ConfirmationStateAfterRequest.conversation.pending_dispatch_category -eq "") {
        $ConfirmationRequestIssues.Add("Pending dispatch category was not stored in conversation state.")
    }
    if ($ConfirmationStateAfterRequest.pending_approval_count -lt 1) {
        $ConfirmationRequestIssues.Add("Pending approval count should be at least one after request.")
    }

    $ConfirmationDispatchBefore = Get-QueueArtifactCountByMarker -Marker $ConfirmationMarker
    $ConfirmationDispatchRaw = & $BridgeScript -Message "confirm [$ConfirmationMarker]" -ConversationId $ConfirmationConversationId -SessionId $ConfirmationSessionId -AsJson 2>&1
    $ConfirmationDispatch = ConvertFrom-PDAMixedJson -Text ([string]($ConfirmationDispatchRaw -join "`n")) -SourceName $BridgeScript
    $ConfirmationDispatchAfter = Get-QueueArtifactCountByMarker -Marker $ConfirmationMarker
    $ConfirmationStateAfterDispatchRaw = & $StateScript -ConversationId $ConfirmationConversationId -SessionId $ConfirmationSessionId -AsJson 2>&1
    $ConfirmationStateAfterDispatch = ConvertFrom-PDAMixedJson -Text ([string]($ConfirmationStateAfterDispatchRaw -join "`n")) -SourceName $StateScript

    if ($ConfirmationDispatch.dispatch_status -ne "submitted") {
        $ConfirmationRequestIssues.Add("Confirmation should dispatch through the governed submitter.")
    }
    if ($ConfirmationDispatchBefore -ge $ConfirmationDispatchAfter) {
        $ConfirmationRequestIssues.Add("Confirmation did not create a new queue artifact.")
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$ConfirmationStateAfterDispatch.conversation.pending_recommended_command)) {
        $ConfirmationRequestIssues.Add("Pending confirmation state should be cleared after dispatch.")
    }
    if ($ConfirmationStateAfterDispatch.pending_approval_count -ne 0) {
        $ConfirmationRequestIssues.Add("Pending approval count should be zero after dispatch.")
    }

    $DuplicateDispatchBefore = Get-QueueArtifactCountByMarker -Marker $ConfirmationMarker
    $DuplicateConfirmationRaw = & $BridgeScript -Message "dispatch [$ConfirmationMarker]" -ConversationId $ConfirmationConversationId -SessionId $ConfirmationSessionId -AsJson 2>&1
    $DuplicateConfirmation = ConvertFrom-PDAMixedJson -Text ([string]($DuplicateConfirmationRaw -join "`n")) -SourceName $BridgeScript
    $DuplicateDispatchAfter = Get-QueueArtifactCountByMarker -Marker $ConfirmationMarker
    if ($DuplicateConfirmation.dispatch_status -eq "submitted") {
        $ConfirmationRequestIssues.Add("Duplicate confirmation should not dispatch a second time.")
    }
    if ($DuplicateDispatchAfter -ne $DuplicateDispatchBefore) {
        $ConfirmationRequestIssues.Add("Duplicate confirmation should not create another queue artifact.")
    }

    $Results += [pscustomobject]@{
        name = "confirmation replay"
        passed = ($ConfirmationRequestIssues.Count -eq 0)
        status = $ConfirmationDispatch.dispatch_status
        response_text = $ConfirmationDispatch.response_text
        dispatch_status = $ConfirmationDispatch.dispatch_status
        dispatch_ready = $ConfirmationDispatch.dispatch_ready
        issues = @($ConfirmationRequestIssues)
    }

    if ($ConfirmationRequestIssues.Count -eq 0) {
        $Passed++
    }
    else {
        $Failed++
    }
}

foreach ($Case in $Cases) {
    if (-not $DashboardMode) {
        $Before = Find-QueueArtifactByMarker -Marker $Case.marker
        if ($Before) {
            throw "Test marker already existed in pending queue: $($Case.marker)"
        }
    }

    $CaseConversationId = "conv-$([guid]::NewGuid().ToString('N').Substring(0, 12))"
    $CaseSessionId = "sess-$([guid]::NewGuid().ToString('N').Substring(0, 12))"

    $Raw = if ($Case.confirm) {
        & $BridgeScript -Message "$($Case.message) [$($Case.marker)]" -ConversationId $CaseConversationId -SessionId $CaseSessionId -ConfirmDispatch -AsJson
    }
    else {
        & $BridgeScript -Message "$($Case.message) [$($Case.marker)]" -ConversationId $CaseConversationId -SessionId $CaseSessionId -AsJson
    }
    $Result = ConvertFrom-PDAMixedJson -Text ([string]($Raw -join "`n")) -SourceName $BridgeScript

    $CasePassed = $true
    $Issues = New-Object System.Collections.Generic.List[string]

    if ($Result.handoff_status -ne $Case.expected_handoff) {
        $CasePassed = $false
        $Issues.Add("Expected handoff status '$($Case.expected_handoff)' but got '$($Result.handoff_status)'.")
    }

    if ($Result.response_text -notlike "*$($Case.expected_response_contains)*") {
        $CasePassed = $false
        $Issues.Add("Response text did not include expected guidance.")
    }

    if ($Case.expected_command -and $Result.recommended_command -ne $Case.expected_command) {
        $CasePassed = $false
        $Issues.Add("Expected recommended command '$($Case.expected_command)' but got '$($Result.recommended_command)'.")
    }

    if (-not $Case.expected_command -and -not [string]::IsNullOrWhiteSpace([string]$Result.recommended_command)) {
        $CasePassed = $false
        $Issues.Add("Non-mapped input should not recommend an executable command.")
    }

    if ($Case.expected_handoff -eq "goal_planning") {
        if (-not ($Result.PSObject.Properties.Name -contains "goal_plan")) {
            $CasePassed = $false
            $Issues.Add("Goal planning response did not include goal_plan data.")
        }
        if (-not ($Result.PSObject.Properties.Name -contains "execution_plan")) {
            $CasePassed = $false
            $Issues.Add("Goal planning response did not include execution_plan data.")
        }
    }

    if ($Case.PSObject.Properties.Name -contains "expected_dispatch_ready") {
        if ([bool]$Result.dispatch_ready -ne [bool]$Case.expected_dispatch_ready) {
            $CasePassed = $false
            $Issues.Add("Dispatch readiness mismatch.")
        }
    }
    elseif ([bool]$Result.dispatch_ready -ne [bool]($Case.expected_handoff -eq "mapped")) {
        $CasePassed = $false
        $Issues.Add("Dispatch readiness mismatch.")
    }

    if (($Result.dispatch_status -eq "submitted") -ne [bool]$Case.expected_dispatch) {
        $CasePassed = $false
        $Issues.Add("Dispatch status mismatch.")
    }

    if ($Result.original_message -notlike "*$($Case.marker)*") {
        $CasePassed = $false
        $Issues.Add("Original message did not round-trip through the bridge output.")
    }

    if (-not $DashboardMode -and $Result.dispatch_status -eq "submitted") {
        if ([string]::IsNullOrWhiteSpace([string]$Result.dispatch_path) -or -not (Test-Path -Path $Result.dispatch_path -PathType Leaf)) {
            $CasePassed = $false
            $Issues.Add("Confirmed bridge dispatch did not return a valid dispatch path.")
        }
    }
    elseif (-not $DashboardMode) {
        $Match = Find-QueueArtifactByMarker -Marker $Case.marker
        if ($Match) {
            $CasePassed = $false
            $Issues.Add("Non-dispatch bridge call unexpectedly created queue work.")
        }
    }

    $Results += [pscustomobject]@{
        name = $Case.name
        passed = $CasePassed
        status = $Result.bridge_status
        response_text = $Result.response_text
        dispatch_status = $Result.dispatch_status
        dispatch_ready = $Result.dispatch_ready
        issues = @($Issues)
    }

    if ($CasePassed) {
        $Passed++
    }
    else {
        $Failed++
    }
}

$Total = $Cases.Count
$Report = [pscustomobject]@{
    status = if ($Failed -eq 0) { "pass" } else { "fail" }
    test_case_count = @($Results).Count
    passed_count = $Passed
    failed_count = $Failed
    dispatch_confirmed_count = @($Results | Where-Object { $_.dispatch_status -eq "submitted" }).Count
    dispatch_blocked_count = @($Results | Where-Object { $_.dispatch_status -eq "blocked" }).Count
    source_of_truth = "Scripts/PDA_CommandInterpreter.ps1"
    results = @($Results)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA chat bridge validation failed."
    }
    return
}

Write-Host "[*] PDA chat bridge tests"
Write-Host ("Test cases              : {0}" -f $Report.test_case_count)
Write-Host ("Passed                  : {0}" -f $Report.passed_count)
Write-Host ("Failed                  : {0}" -f $Report.failed_count)
Write-Host ("Dispatch confirmed      : {0}" -f $Report.dispatch_confirmed_count)
Write-Host ("Dispatch blocked        : {0}" -f $Report.dispatch_blocked_count)
Write-Host ("Source of truth         : {0}" -f $Report.source_of_truth)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA chat bridge validation failed."
}
