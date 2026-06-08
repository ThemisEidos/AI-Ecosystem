[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Text,

    [Parameter(Mandatory = $false)]
    [string]$Root,

    [Parameter(Mandatory = $false)]
    [Alias("AsJson")]
    [switch]$OutputJson
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

$InterpreterScript = Join-Path $PSScriptRoot "PDA_CommandInterpreter.ps1"
$DashboardStatusScript = Join-Path $PSScriptRoot "Get-PDADashboardStatus.ps1"
$TaskResultScript = Join-Path $PSScriptRoot "Get-PDATaskResult.ps1"
$MemoryCandidateSummaryScript = Join-Path $PSScriptRoot "Get-PDAMemoryCandidateSummary.ps1"
$DispatchStatusScript = Join-Path $PSScriptRoot "Get-PDADispatchStatus.ps1"
$EnvironmentHelperScript = Join-Path $PSScriptRoot "PDA_Environment.ps1"
$ExecutorRegistryScript = Join-Path $PSScriptRoot "PDA_ExecutorRegistry.ps1"
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
if (Test-Path -LiteralPath $ParserPath -PathType Leaf) {
    . $ParserPath
}
if (Test-Path -LiteralPath $EnvironmentHelperScript -PathType Leaf) {
    . $EnvironmentHelperScript
}
if (Test-Path -LiteralPath $ExecutorRegistryScript -PathType Leaf) {
    . $ExecutorRegistryScript
}

function Normalize-PDAConversationalText {
    param([Parameter(Mandatory = $true)][string]$Value)

    $Normalized = [string]$Value
    $Normalized = $Normalized.ToLowerInvariant()
    $Normalized = $Normalized -replace '[^a-z0-9/\s]+', ' '
    $Normalized = $Normalized -replace '\s+', ' '
    return $Normalized.Trim()
}

function Invoke-PDAConversationalJsonScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$SourceName
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        $SafeArguments = @(
            $Arguments | Where-Object {
                $_ -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$_)
            }
        )

        $Raw = & pwsh -NoProfile -File $Path @SafeArguments 2>&1
        $TextOutput = [string]($Raw -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($TextOutput)) {
            return $null
        }

        return ConvertFrom-PDAMixedJson -Text $TextOutput -SourceName $SourceName
    }
    catch {
        return $null
    }
}

function Test-PDAConversationalSlashCommand {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool]($NormalizedText.StartsWith("/"))
}

function Test-PDAConversationalDirectHelp {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(what can you do|what do you do|help|what commands|available commands|show me help|show the command list)\b'
    )
}

function Test-PDAConversationalDirectStatus {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(how is the pda doing|how is the ecosystem|summarize the ecosystem status|summarise the ecosystem status|show me the current status|current status|system status|how are things|pda status|how is everything)\b'
    )
}

function Test-PDAConversationalTaskLookup {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(what happened to my last task|what happened to my task|latest result|latest task|task status|where is my result|result location|what happened)\b'
    )
}

function Test-PDAConversationalMemoryCandidates {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(memory candidates|pending memory promotions|pending promotions|what did the pda learn recently|what has the pda learned recently|what did the pda learn|recent learnings|recent memory|memory promotion)\b'
    )
}

function Test-PDAConversationalCommanderBriefing {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(what should i work on next|what should i do next|give me my pda briefing|give me a pda briefing|pda daily brief|daily brief|what is blocked|what needs attention|what changed recently|what needs review|what should i delegate|what changed since last time)\b'
    )
}

function Test-PDAConversationalDispatchGuidance {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(what should handle this task|what should handle this|what executor should handle this|what executors are available|what should be delegated|what should i delegate|what should dispatch this|who should handle this task|best executor|best executor for this)\b'
    )
}

function Test-PDAConversationalEnvironmentAwareness {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(filesystem|file system|repository|repositories|docker|container|containers|service inventory|service status|tool inventory|workspace inventory|environment awareness|environment inventory|file structure|organize folders|storage locations|scan c:\\|scan ~/|scan my filesystem|show my repositories|what ai services are running|help organize my folders|recommend a better project structure|workspace structure|project structure)\b'
    )
}

function Test-PDAConversationalGoalPlanning {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(classic literature|reading list|study plan|goal plan|goal decomposition|build me a roadmap|create a roadmap|help me create|analyze my project|what needs to happen|reading guide|pdf report|write a report|make it a pdf|summarize and create|search the internet)\b' -or
        ($NormalizedText -match '(?i)\b(research|investigate|search|study|authors|books)\b' -and $NormalizedText -match '(?i)\b(report|pdf|synopsis|synopses|links|sources|reading list|roadmap|plan|guide)\b')
    )
}

function Test-PDAConversationalAmbiguous {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\breview\b.*\brun\b|\brun\b.*\breview\b|\breport\b.*\brun\b|\brun\b.*\breport\b|\bresearch\b.*\brun\b|\brun\b.*\bresearch\b|\bexecute\b.*\breview\b|\breview\b.*\bexecute\b'
    )
}

function Get-PDAConversationalInterpreterResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    if (-not (Test-Path -LiteralPath $InterpreterScript -PathType Leaf)) {
        return $null
    }

    try {
        $Raw = & $InterpreterScript -Text $Text -AsJson 2>&1
        $JsonText = [string]($Raw -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($JsonText)) {
            return $null
        }

        return ConvertFrom-PDAMixedJson -Text $JsonText -SourceName $InterpreterScript
    }
    catch {
        return $null
    }
}

function Resolve-PDAConversationalRoute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Normalized = Normalize-PDAConversationalText -Value $Text
    $Route = [ordered]@{
        route_type           = "fallback"
        response_mode        = "direct_answer"
        recommended_command  = ""
        requires_confirmation = $false
        confidence           = 0
        reason               = "No conversational rule matched."
        ambiguity_reason     = ""
        synthetic_text       = ""
        briefing_focus       = ""
        intent               = ""
        task_type            = ""
        command              = ""
        source_of_truth      = "Scripts/PDA_ConversationalRouter.ps1"
        root_path            = $Root
    }

    if ([string]::IsNullOrWhiteSpace($Normalized)) {
        $Route.reason = "Empty input."
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalSlashCommand -NormalizedText $Normalized) {
        $InterpreterResult = Get-PDAConversationalInterpreterResult -Text $Text
        if ($InterpreterResult -and [string]$InterpreterResult.status -eq "mapped") {
            $Route.route_type = "slash_command"
            $Route.response_mode = "governed_command"
            $Route.recommended_command = [string]$InterpreterResult.command
            $Route.requires_confirmation = [bool]$InterpreterResult.requires_confirmation
            $Route.confidence = [double]$InterpreterResult.confidence
            $Route.reason = [string]$InterpreterResult.reason
            $Route.ambiguity_reason = [string]$InterpreterResult.reason
            $Route.intent = [string]$InterpreterResult.intent
            $Route.task_type = [string]$InterpreterResult.task_type
            $Route.command = [string]$InterpreterResult.command
            return [pscustomobject]$Route
        }

        $Route.route_type = "slash_command"
        $Route.response_mode = "governed_command"
        $Route.recommended_command = [string]($Normalized.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)[0])
        $Route.requires_confirmation = $false
        $Route.confidence = 1
        $Route.reason = "Explicit slash command."
        $Route.ambiguity_reason = "Explicit slash command."
        $Route.command = $Route.recommended_command
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalDirectHelp -NormalizedText $Normalized) {
        $Route.route_type = "direct_help"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = "/help"
        $Route.reason = "Direct help request."
        $Route.confidence = 1
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalDirectStatus -NormalizedText $Normalized) {
        $Route.route_type = "direct_status"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = "/status"
        $Route.reason = "Direct status request."
        $Route.confidence = 1
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalTaskLookup -NormalizedText $Normalized) {
        $Route.route_type = "task_lookup"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = ""
        $Route.reason = "Direct task lookup request."
        $Route.confidence = 1
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalMemoryCandidates -NormalizedText $Normalized) {
        $Route.route_type = "memory_candidates"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = "/memory"
        $Route.reason = "Direct memory candidate request."
        $Route.confidence = 1
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalCommanderBriefing -NormalizedText $Normalized) {
        $Route.route_type = "commander_briefing"
        $Route.response_mode = "direct_answer"
        $Route.reason = "Direct Commander briefing request."
        $Route.confidence = 1
        if ($Normalized -match '(?i)\b(blocked|blocked items|what is blocked)\b') {
            $Route.briefing_focus = "blocked"
        }
        elseif ($Normalized -match '(?i)\b(recent|changed recently|what changed)\b') {
            $Route.briefing_focus = "recent"
        }
        elseif ($Normalized -match '(?i)\b(next|what should i work on next|what should i do next)\b') {
            $Route.briefing_focus = "next"
        }
        else {
            $Route.briefing_focus = "default"
        }
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalDispatchGuidance -NormalizedText $Normalized) {
        $Route.route_type = "dispatch_guidance"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = "/dispatch"
        $Route.reason = "Direct dispatch guidance request."
        $Route.confidence = 1
        if ($Normalized -match '(?i)\b(executors are available|available executors|what executors)\b') {
            $Route.briefing_focus = "available"
        }
        elseif ($Normalized -match '(?i)\b(should handle this task|should handle this|best executor|delegate)\b') {
            $Route.briefing_focus = "recommendation"
        }
        else {
            $Route.briefing_focus = "dispatch"
        }
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalEnvironmentAwareness -NormalizedText $Normalized) {
        $Route.route_type = "environment_awareness"
        $Route.response_mode = "direct_answer"
        $Route.reason = "Environment analysis or file-structure recommendation request."
        $Route.confidence = 1
        if ($Normalized -match '(?i)\b(recommend|better structure|organize|organization|structure|migration|cleanup|plan)\b') {
            $Route.briefing_focus = "recommendation"
        }
        else {
            $Route.briefing_focus = "inventory"
        }
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalGoalPlanning -NormalizedText $Normalized) {
        $Route.route_type = "goal_planning"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = ""
        $Route.reason = "Natural-language goal decomposition request."
        $Route.confidence = 0.9
        $Route.intent = "goal_planning"
        $Route.task_type = "goal_planning"
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalAmbiguous -NormalizedText $Normalized) {
        $Route.route_type = "ambiguous"
        $Route.response_mode = "clarification"
        $Route.reason = "Multiple governed actions were requested in one message."
        $Route.ambiguity_reason = "Multiple governed actions were requested in one message."
        $Route.confidence = 0.5
        return [pscustomobject]$Route
    }

    if ($Normalized -match '(?i)\b(roadmap|road map)\b') {
        $Route.route_type = "governed_request"
        $Route.response_mode = "governed_command"
        $Route.recommended_command = "/planner"
        $Route.requires_confirmation = $true
        $Route.confidence = 0.95
        $Route.reason = "Roadmap language maps to the planner workflow."
        $Route.synthetic_text = "/planner $Text"
        $Route.intent = "planning"
        $Route.task_type = "planning"
        $Route.command = "/planner"
        return [pscustomobject]$Route
    }

    $InterpreterResult = Get-PDAConversationalInterpreterResult -Text $Text
    if ($InterpreterResult -and [string]$InterpreterResult.status -eq "mapped") {
        $Route.route_type = "governed_request"
        $Route.response_mode = "governed_command"
        $Route.recommended_command = [string]$InterpreterResult.command
        $Route.requires_confirmation = [bool]$InterpreterResult.requires_confirmation
        $Route.confidence = [double]$InterpreterResult.confidence
        $Route.reason = [string]$InterpreterResult.reason
        $Route.ambiguity_reason = [string]$InterpreterResult.reason
        $Route.intent = [string]$InterpreterResult.intent
        $Route.task_type = [string]$InterpreterResult.task_type
        $Route.command = [string]$InterpreterResult.command
        $Route.synthetic_text = if ($Route.recommended_command -and -not $Normalized.StartsWith($Route.recommended_command.ToLowerInvariant())) {
            "$($Route.recommended_command) $Text"
        }
        else {
            $Text
        }
        return [pscustomobject]$Route
    }

    if ($InterpreterResult -and [string]$InterpreterResult.status -eq "ambiguous") {
        $Route.route_type = "ambiguous"
        $Route.response_mode = "clarification"
        $Route.reason = [string]$InterpreterResult.reason
        $Route.ambiguity_reason = [string]$InterpreterResult.reason
        $Route.confidence = 0.5
        return [pscustomobject]$Route
    }

    $Route.route_type = "fallback"
    $Route.response_mode = "direct_answer"
    $Route.reason = if ($InterpreterResult) { [string]$InterpreterResult.reason } else { "No conversational rule matched." }
    $Route.ambiguity_reason = $Route.reason
    $Route.confidence = 0
    return [pscustomobject]$Route
}

function Get-PDAConversationalNaturalResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Route,

        [Parameter(Mandatory = $false)]
        [string]$ConversationId,

        [Parameter(Mandatory = $false)]
        [string]$SessionId,

        [Parameter(Mandatory = $false)]
        [string]$UserId,

        [Parameter(Mandatory = $false)]
        [string]$ConversationTitle,

        [Parameter(Mandatory = $false)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $ConversationIdValue = if ([string]::IsNullOrWhiteSpace($ConversationId)) { "" } else { [string]$ConversationId }
    $SessionIdValue = if ([string]::IsNullOrWhiteSpace($SessionId)) { "" } else { [string]$SessionId }
    $BaseResponse = [ordered]@{
        original_message         = $Text
        response_text            = ""
        recommended_command      = [string]$Route.recommended_command
        intent                   = [string]$Route.route_type
        confidence               = [double]$Route.confidence
        requires_confirmation    = $false
        dispatch_ready           = $false
        dispatch_status          = "not_applicable"
        next_action              = ""
        bridge_status            = "ready"
        handoff_status           = [string]$Route.route_type
        source_of_truth          = "Scripts/PDA_ConversationalRouter.ps1"
        confirmation_mode        = $false
        dispatch_path            = ""
        dispatch_category        = ""
        conversation_id          = $ConversationIdValue
        session_id               = $SessionIdValue
        conversation_state_status = "unknown"
        latest_task_id           = ""
        latest_task_status       = ""
        latest_result_path       = ""
        latest_result_response_text = ""
        result_artifact_path     = ""
        result_artifact          = $null
        bridge_mode              = "conversational_direct"
        goal_plan                = $null
        execution_plan           = $null
    }

    switch ([string]$Route.route_type) {
        "direct_status" {
            $Dashboard = Invoke-PDAConversationalJsonScript -Path $DashboardStatusScript -Arguments @("-AsJson", "-NoThrow", "-SkipCoreIntegration") -SourceName "PDA dashboard status"
            $Health = if ($Dashboard -and $Dashboard.PSObject.Properties.Name -contains "dashboard_health") { [string]$Dashboard.dashboard_health.status } else { "unknown" }
            $QueueDepth = if ($Dashboard -and $Dashboard.PSObject.Properties.Name -contains "queue_status") { [int]$Dashboard.queue_status.queue_depth } else { 0 }
            $PendingApprovals = if ($Dashboard -and $Dashboard.PSObject.Properties.Name -contains "pending_approvals") { @($Dashboard.pending_approvals).Count } else { 0 }
            $RecentTasks = if ($Dashboard -and $Dashboard.PSObject.Properties.Name -contains "recent_tasks") { @($Dashboard.recent_tasks).Count } else { 0 }
            $HealthSentence = if ($Health -eq "pass") { "PDA is reachable and healthy." } elseif ($Health -eq "warning") { "PDA is reachable, but the dashboard is showing warning-level health." } elseif ($Health -eq "degraded") { "PDA is reachable, but the dashboard is showing degraded health." } else { "PDA status is available, but the dashboard health is unknown." }
            $BaseResponse.response_text = "{0} Queue depth is {1}, with {2} pending approvals and {3} recent tasks." -f $HealthSentence, $QueueDepth, $PendingApprovals, $RecentTasks
            $BaseResponse.next_action = "Ask for /status to see the full operator console or ask about workers, tasks, reports, or memory."
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
        }
        "direct_help" {
            $BaseResponse.response_text = "I can check status, give you a briefing, summarize tasks, list workers, show reports, summarize memory, review memory candidates, plan goals, run Fabric patterns, create NotebookLM packages, and route governed requests. Ask a plain-language question or use /help."
            $BaseResponse.next_action = "Ask for a briefing, a status question, a goal plan, or use /help for the full command list."
        }
        "task_lookup" {
            $TaskResult = Invoke-PDAConversationalJsonScript -Path $TaskResultScript -Arguments @(
                "-AsJson",
                "-NoThrow",
                "-ConversationId", $ConversationIdValue,
                "-SessionId", $SessionIdValue,
                "-UserMessage", $(if ([string]::IsNullOrWhiteSpace($Text)) { "what happened to my last task" } else { $Text })
            ) -SourceName "PDA task result lookup"

            if ($TaskResult -and $TaskResult.PSObject.Properties.Name -contains "latest_task" -and $TaskResult.latest_task) {
                $LatestTask = $TaskResult.latest_task
                $BaseResponse.latest_task_id = if ($LatestTask.PSObject.Properties.Name -contains "task_id") { [string]$LatestTask.task_id } else { "" }
                $BaseResponse.latest_task_status = if ($LatestTask.PSObject.Properties.Name -contains "task_status") { [string]$LatestTask.task_status } else { "" }
                $BaseResponse.latest_result_path = if ($TaskResult.PSObject.Properties.Name -contains "latest_result_path") { [string]$TaskResult.latest_result_path } else { "" }
                $BaseResponse.result_artifact_path = $BaseResponse.latest_result_path
                $BaseResponse.latest_result_response_text = if ($TaskResult.PSObject.Properties.Name -contains "latest_result_response_text") { [string]$TaskResult.latest_result_response_text } else { "" }
                $BaseResponse.response_text = if ($TaskResult.PSObject.Properties.Name -contains "response_text" -and -not [string]::IsNullOrWhiteSpace([string]$TaskResult.response_text) -and [string]$TaskResult.response_text -notmatch 'No tracked PDA task found for this conversation\.?') {
                    [string]$TaskResult.response_text
                }
                else {
                    "I don't see a tracked PDA task for this conversation yet."
                }
                $BaseResponse.next_action = if ($TaskResult.PSObject.Properties.Name -contains "next_action" -and -not [string]::IsNullOrWhiteSpace([string]$TaskResult.next_action)) { [string]$TaskResult.next_action } else { "Ask me to start a task with /planner or /research, or confirm a queued request." }
            }
            else {
                $BaseResponse.response_text = "I don't see a tracked PDA task for this conversation yet. If you want, I can help start one with /planner, /research, or /reporter."
                $BaseResponse.next_action = "Ask me to start a task with /planner or /research, or ask for /status."
            }
        }
        "memory_candidates" {
            $CandidateSummary = Invoke-PDAConversationalJsonScript -Path $MemoryCandidateSummaryScript -Arguments @("-AsJson", "-Latest", "5") -SourceName "PDA memory candidate summary"
            $CandidateCount = if ($CandidateSummary -and $CandidateSummary.PSObject.Properties.Name -contains "candidate_count") { [int]$CandidateSummary.candidate_count } else { 0 }
            $PendingCount = if ($CandidateSummary -and $CandidateSummary.PSObject.Properties.Name -contains "pending_approval_count") { [int]$CandidateSummary.pending_approval_count } else { 0 }
            $PromotedCount = if ($CandidateSummary -and $CandidateSummary.PSObject.Properties.Name -contains "promoted_count") { [int]$CandidateSummary.promoted_count } else { 0 }
            $MemoryCount = if ($CandidateSummary -and $CandidateSummary.PSObject.Properties.Name -contains "memory_count") { [int]$CandidateSummary.memory_count } else { 0 }

            $RecentCandidateTitles = @()
            if ($CandidateSummary -and $CandidateSummary.PSObject.Properties.Name -contains "recent_candidates" -and $CandidateSummary.recent_candidates) {
                $RecentCandidateTitles = @(
                    $CandidateSummary.recent_candidates |
                        Select-Object -First 3 |
                        ForEach-Object {
                            if ($_.PSObject.Properties.Name -contains "title" -and -not [string]::IsNullOrWhiteSpace([string]$_.title)) {
                                [string]$_.title
                            }
                            else {
                                ""
                            }
                        } |
                        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
                )
            }

            $RecentMemoryTitles = @()
            if ($CandidateSummary -and $CandidateSummary.PSObject.Properties.Name -contains "recent_memories" -and $CandidateSummary.recent_memories) {
                $RecentMemoryTitles = @(
                    $CandidateSummary.recent_memories |
                        Select-Object -First 3 |
                        ForEach-Object {
                            if ($_.PSObject.Properties.Name -contains "title" -and -not [string]::IsNullOrWhiteSpace([string]$_.title)) {
                                [string]$_.title
                            }
                            else {
                                ""
                            }
                        } |
                        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
                )
            }

            $RecentCandidateText = if ($RecentCandidateTitles.Count -gt 0) { $RecentCandidateTitles -join "; " } else { "none yet" }
            $RecentMemoryText = if ($RecentMemoryTitles.Count -gt 0) { $RecentMemoryTitles -join "; " } else { "none yet" }

            $BaseResponse.response_text = "PDA memory learning is tracking $CandidateCount candidates, with $PendingCount pending approvals and $PromotedCount promoted memories out of $MemoryCount total memories. Recent candidates: $RecentCandidateText. Recent memories: $RecentMemoryText."
            $BaseResponse.next_action = "Use /memory to review the full index or inspect PDA-Memory/candidates for pending promotions."
            $BaseResponse.recommended_command = "/memory"
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
        }
        "commander_briefing" {
            $BriefingScript = Join-Path $PSScriptRoot "Get-PDACommanderBriefing.ps1"
            $Focus = if ($Route.PSObject.Properties.Name -contains "briefing_focus" -and -not [string]::IsNullOrWhiteSpace([string]$Route.briefing_focus)) { [string]$Route.briefing_focus } else { "default" }
            $Briefing = Invoke-PDAConversationalJsonScript -Path $BriefingScript -Arguments @("-Focus", $Focus, "-AsJson", "-Root", $Root) -SourceName "PDA commander briefing"

            if ($Briefing) {
                $BaseResponse.response_text = if ($Briefing.PSObject.Properties.Name -contains "briefing_text" -and -not [string]::IsNullOrWhiteSpace([string]$Briefing.briefing_text)) { [string]$Briefing.briefing_text } else { "PDA daily brief unavailable." }
                $BaseResponse.next_action = if ($Briefing.PSObject.Properties.Name -contains "next_action" -and -not [string]::IsNullOrWhiteSpace([string]$Briefing.next_action)) { [string]$Briefing.next_action } else { "Review the briefing and choose the highest priority action." }
                $BaseResponse.recommended_command = ""
                $BaseResponse.latest_result_response_text = $BaseResponse.response_text
                $BaseResponse.intent = "commander_briefing"
                $BaseResponse.confidence = 1
            }
            else {
                $BaseResponse.response_text = "PDA daily briefing unavailable."
                $BaseResponse.next_action = "Ask /status if you need the operator console summary."
            }
        }
        "dispatch_guidance" {
            $RegistrySummary = $null
            if (Get-Command -Name Get-PDAExecutorRegistrySummary -ErrorAction SilentlyContinue) {
                try {
                    $RegistrySummary = Get-PDAExecutorRegistrySummary -Root $Root
                }
                catch {
                    $RegistrySummary = $null
                }
            }

            $DispatchStatus = $null
            if (Test-Path -LiteralPath $DispatchStatusScript -PathType Leaf) {
                try {
                    $DispatchStatus = Invoke-PDAConversationalJsonScript -Path $DispatchStatusScript -Arguments @("-AsJson", "-NoThrow", "-Root", $Root) -SourceName "PDA dispatch status"
                }
                catch {
                    $DispatchStatus = $null
                }
            }

            $ExecutorLine = if ($RegistrySummary -and $RegistrySummary.PSObject.Properties.Name -contains "executors") {
                "Available executors: {0}" -f (@($RegistrySummary.executors | ForEach-Object { $_.executor_name }) -join ", ")
            }
            else {
                "Available executors: codex, gemini-cli, n8n, research-worker, reporter-worker, planner-worker, review-worker, execute-worker, notebooklm, operator-console-worker."
            }

            $QueueLine = "Dispatch queue: unavailable."
            if ($DispatchStatus -and $DispatchStatus.PSObject.Properties.Name -contains "counts") {
                $QueueLine = "Dispatch queue: {0} pending approval, {1} approved, {2} prepared, {3} running." -f $DispatchStatus.counts.pending_approval, $DispatchStatus.counts.approved, $DispatchStatus.counts.prepared, $DispatchStatus.counts.running
            }

            $Recommendation = $null
            if (Get-Command -Name Get-PDAExecutorRecommendation -ErrorAction SilentlyContinue) {
                try {
                    $Recommendation = Get-PDAExecutorRecommendation -TaskType "administrative" -Category "category_1" -Text $Text -Root $Root
                }
                catch {
                    $Recommendation = $null
                }
            }

            if ($Route.briefing_focus -eq "available") {
                $BaseResponse.response_text = @(
                    $ExecutorLine
                    $QueueLine
                    "Use /dispatch to review the governed dispatch path."
                ) -join "`r`n"
            }
            else {
                $RecommendedText = if ($Recommendation -and -not [string]::IsNullOrWhiteSpace([string]$Recommendation.recommended_executor)) {
                    "Recommended executor: {0}. Approval required: {1}. Reason: {2}" -f $Recommendation.recommended_executor, $Recommendation.approval_required, $Recommendation.routing_reason
                }
                else {
                    "Recommended executor: operator-console-worker. Approval required: false."
                }

                $BaseResponse.response_text = @(
                    $RecommendedText
                    $ExecutorLine
                    $QueueLine
                    "Use /dispatch to view the governed dispatch path or share a specific task for recommendation."
                ) -join "`r`n"
            }

            $BaseResponse.next_action = "Use /dispatch to view the governed dispatch path or share a specific task for recommendation."
            $BaseResponse.recommended_command = "/dispatch"
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
        }
        "environment_awareness" {
            $RequestedRoots = @()
            if (Get-Command -Name Get-PDAEnvironmentRootsFromText -ErrorAction SilentlyContinue) {
                $RequestedRoots = @(Get-PDAEnvironmentRootsFromText -Text $Text -FallbackRoots @($Root))
            }
            elseif (-not [string]::IsNullOrWhiteSpace($Root)) {
                $RequestedRoots = @($Root)
            }

            $EnvironmentSummary = $null
            if (Get-Command -Name Get-PDAEnvironmentSummary -ErrorAction SilentlyContinue) {
                try {
                    $EnvironmentSummary = Get-PDAEnvironmentSummary -Roots $RequestedRoots -Root $Root
                }
                catch {
                    $EnvironmentSummary = $null
                }
            }

            $Recommendation = $null
            if (Get-Command -Name Get-PDAFileOrganizationRecommendation -ErrorAction SilentlyContinue) {
                try {
                    $Recommendation = Get-PDAFileOrganizationRecommendation -Roots $RequestedRoots -Root $Root -FilesystemInventory $(if ($EnvironmentSummary) { $EnvironmentSummary.filesystem } else { $null })
                }
                catch {
                    $Recommendation = $null
                }
            }

            $GoalLine = if ($Route.briefing_focus -eq "recommendation") {
                "Goal: Analyze the local environment and recommend a file structure."
            }
            else {
                "Goal: Analyze the local environment and build a current-state inventory."
            }

            $InventoryLines = New-Object System.Collections.Generic.List[string]
            if ($EnvironmentSummary) {
                $InventoryLines.Add(("Roots scanned: {0}" -f (@($EnvironmentSummary.roots).Count)))
                $InventoryLines.Add(("Repositories: {0}" -f $EnvironmentSummary.counts.repositories))
                $InventoryLines.Add(("Containers: {0} running / {1} total" -f $EnvironmentSummary.counts.running_containers, $EnvironmentSummary.counts.containers))
                $InventoryLines.Add(("Services online: {0}" -f $EnvironmentSummary.counts.services_online))
                $InventoryLines.Add(("Tools available: {0}" -f $EnvironmentSummary.counts.tools_available))
                $InventoryLines.Add(("Likely projects: {0}" -f @($EnvironmentSummary.filesystem.project_candidates).Count))
                $InventoryLines.Add(("Likely archives: {0}" -f @($EnvironmentSummary.filesystem.archive_candidates).Count))
            }
            else {
                $InventoryLines.Add("Environment inventory unavailable.")
            }

            $RecommendationLines = New-Object System.Collections.Generic.List[string]
            if ($Recommendation) {
                $RecommendationLines.Add(("Recommended model: {0}" -f [string]$Recommendation.recommended_model))
                $RecommendationLines.Add("Proposed structure:")
                foreach ($Item in @($Recommendation.proposed_structure)) {
                    $RecommendationLines.Add(("- {0}: {1}" -f [string]$Item.path, [string]$Item.purpose))
                }
                $RecommendationLines.Add("Migration plan:")
                foreach ($Item in @($Recommendation.migration_strategy)) {
                    $RecommendationLines.Add(("- Phase {0}: {1}" -f [string]$Item.phase, [string]$Item.action))
                }
                $RecommendationLines.Add("Approval path:")
                foreach ($Item in @($Recommendation.approval_path)) {
                    $RecommendationLines.Add(("- {0}" -f [string]$Item))
                }
            }
            else {
                $RecommendationLines.Add("No recommendation could be generated yet.")
            }

            $BaseResponse.response_text = @(
                "Goal Assessment"
                $GoalLine
                ""
                "Environment Discovery"
                ($InventoryLines -join "`r`n")
                ""
                "Execution Plan"
                "1. Review the current-state inventory."
                "2. Validate the recommended structure and staged migration."
                "3. Approve any manual move or rename before execution."
                ""
                "Recommended Structure"
                ($RecommendationLines -join "`r`n")
                ""
                "Approval Path"
                "- No automatic moves, renames, or cleanup actions will be performed."
            ) -join "`r`n"
            $BaseResponse.next_action = "Review the inventory and approve or refine the proposed structure before any manual migration."
            $BaseResponse.recommended_command = ""
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
            $BaseResponse.intent = "environment_awareness"
            $BaseResponse.confidence = 1
        }
        "goal_planning" {
            $GoalPlanScript = Join-Path $PSScriptRoot "Get-PDAGoalPlan.ps1"
            $GoalPlan = Invoke-PDAConversationalJsonScript -Path $GoalPlanScript -Arguments @("-Text", $Text, "-Root", $Root, "-Persist", "-AsJson") -SourceName "PDA goal plan"
            if ($GoalPlan) {
                $BaseResponse.response_text = if ($GoalPlan.PSObject.Properties.Name -contains "response_text" -and -not [string]::IsNullOrWhiteSpace([string]$GoalPlan.response_text)) { [string]$GoalPlan.response_text } else { "PDA goal plan unavailable." }
                $BaseResponse.next_action = if ($GoalPlan.PSObject.Properties.Name -contains "next_action" -and -not [string]::IsNullOrWhiteSpace([string]$GoalPlan.next_action)) { [string]$GoalPlan.next_action } else { "Review the goal plan and ask for refinements or approval." }
                $BaseResponse.recommended_command = ""
                $BaseResponse.latest_result_response_text = $BaseResponse.response_text
                $BaseResponse.intent = "goal_planning"
                $BaseResponse.confidence = if ($GoalPlan.PSObject.Properties.Name -contains "confidence") { [double]$GoalPlan.confidence } else { 0.9 }
                $BaseResponse.goal_plan = $GoalPlan
                $BaseResponse.execution_plan = if ($GoalPlan.PSObject.Properties.Name -contains "execution_plan") { $GoalPlan.execution_plan } else { $null }
            }
            else {
                $BaseResponse.response_text = "I can turn natural-language goals into a structured plan, but the goal planner is unavailable right now."
                $BaseResponse.next_action = "Try /planner or ask for /help if you want the command list."
            }
        }
        "ambiguous" {
            $BaseResponse.response_text = "I can help with one action at a time. Do you want a review, a run/execution, a report, or a goal plan?"
            $BaseResponse.next_action = "Reply with one clear action such as review, report, status, research, execute, or goal planning."
        }
        "fallback" {
            $BaseResponse.response_text = "I can help with status, briefing, blocked work, recent changes, tasks, workers, reports, memory, Fabric, NotebookLM, environment analysis, goal planning, research, review, and execution. Ask a direct question or use /help."
            $BaseResponse.next_action = "Ask for a briefing, a status question, an environment inventory, a goal plan, or use /help for the full command list."
        }
        default {
            $BaseResponse.response_text = "I can help with status, briefing, blocked work, recent changes, tasks, workers, reports, memory, Fabric, NotebookLM, environment analysis, goal planning, research, review, and execution. Ask a direct question or use /help."
            $BaseResponse.next_action = "Ask for a briefing, a status question, an environment inventory, a goal plan, or use /help for the full command list."
        }
    }

    return [pscustomobject]$BaseResponse
}

if ($PSBoundParameters.ContainsKey("Text")) {
    $Route = Resolve-PDAConversationalRoute -Text $Text -Root $Root
    if ($OutputJson) {
        $Route | ConvertTo-Json -Depth 20
    }
    else {
        Write-Host ("Route type          : {0}" -f $Route.route_type)
        Write-Host ("Recommended command : {0}" -f $(if ($Route.recommended_command) { $Route.recommended_command } else { "(none)" }))
        Write-Host ("Requires confirmation: {0}" -f $Route.requires_confirmation)
        Write-Host ("Reason              : {0}" -f $Route.reason)
    }
}
