[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$RouterScript = Join-Path $PSScriptRoot "COOPER_ConversationalRouter.ps1"
$UseLiveModel = [bool](
    -not [string]::IsNullOrWhiteSpace([string]$env:COOPER_TEST_USE_LIVE_MODEL) -and
    [string]$env:COOPER_TEST_USE_LIVE_MODEL -notmatch '^(0|false|no)$'
)
if (-not $UseLiveModel -and [string]::IsNullOrWhiteSpace([string]$env:COOPER_LIGHTWEIGHT_STATUS)) {
    $env:COOPER_LIGHTWEIGHT_STATUS = "1"
}

if (-not (Test-Path -LiteralPath $RouterScript -PathType Leaf)) {
    throw "Conversational router missing: $RouterScript"
}

. $RouterScript

$DefaultModelCandidates = if (Get-Command -Name Get-COOPERDefaultModelCandidates -ErrorAction SilentlyContinue) {
    @((Get-COOPERDefaultModelCandidates -Root $Root))
}
else {
    @("qwen2.5:7b", "mistral", "local-llama")
}
if ($DefaultModelCandidates.Count -lt 3 -or $DefaultModelCandidates[0] -ne "qwen2.5:7b" -or $DefaultModelCandidates[1] -ne "mistral" -or $DefaultModelCandidates[2] -ne "local-llama") {
    throw "Default COOPER model fallback chain is not qwen2.5:7b -> mistral -> local-llama."
}

$DefaultModelChatFallback = {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $false)][string]$Root,
        [Parameter(Mandatory = $false)][string]$ResponseStyle
    )

    return [pscustomobject]@{
        status = "pass"
        default_model = "qwen2.5:7b"
        selected_model = "qwen2.5:7b"
        model_status = "pass"
        model_error_message = ""
        routing_reason = "router test stub"
        response_text = "Operational."
        next_action = "Awaiting the next task."
        bridge_mode = "model_chat"
        handoff_status = "fallback"
        source_of_truth = "test_stub"
    }
}

if (-not (Get-Command -Name Invoke-COOPERDefaultModelChat -ErrorAction SilentlyContinue)) {
    Set-Item -Path function:Invoke-COOPERDefaultModelChat -Value $DefaultModelChatFallback
}
elseif (-not $UseLiveModel) {
    Set-Item -Path function:Invoke-COOPERDefaultModelChat -Value $DefaultModelChatFallback
}

$Cases = @(
    [pscustomobject]@{
        name = "status request"
        input = "Show system status."
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "WF-004 operational workflows"
        input = "COOPER, what workflows are operational?"
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "WF-004 workflow status"
        input = "COOPER, show workflow status."
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "WF-004 right now"
        input = "COOPER, what can you do right now?"
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "WF-004 operational status"
        input = "COOPER, show operational status."
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "fabric report slash"
        input = "/fabric report Summarize the current PDA ecosystem status..."
        expected_route = "slash_command"
        expected_command = "/fabric report"
    }
    [pscustomobject]@{
        name = "natural tool inventory"
        input = "What tools are available?"
        expected_route = "tool_inventory"
        expected_command = "What tools are available?"
    }
    [pscustomobject]@{
        name = "natural workflow catalog"
        input = "List available workflows."
        expected_route = "workflow_catalog"
        expected_command = "List available workflows"
    }
    # WF-004 precedence cases verify that capability/workflow questions resolve to operational status, not generic help.
    [pscustomobject]@{
        name = "WF-004 capability/status precedence - workflow availability"
        input = "What workflows are available?"
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    # Segmentation exists, but only the first actionable intent should route until a future execution queue is added.
    [pscustomobject]@{
        name = "compound COOPER requests"
        input = "COOPER, what can you do? COOPER, create a note about Docker networking."
        expected_route = "direct_status"
        expected_command = "Show system status"
        expected_intent_segments = 2
    }
    [pscustomobject]@{
        name = "research chain prompt"
        input = "Research Docker host administration documentation and prepare implementation work for the Linux collection."
        expected_route = "research_summary"
        expected_command = "Research Summary"
    }
    [pscustomobject]@{
        name = "environment inventory"
        input = "Show my repositories and workspace structure."
        expected_route = "environment_awareness"
        expected_command = ""
    }
    [pscustomobject]@{
        name = "codex task generation"
        input = "Create a Codex task to add Docker administration documentation to the Linux & Infrastructure collection."
        expected_route = "codex_task_generator"
        expected_command = "Create Codex task"
    }
    [pscustomobject]@{
        name = "research summary note"
        input = "Research official Pop!_OS documentation and prepare it for the Linux & Infrastructure knowledge collection."
        expected_route = "research_summary"
        expected_command = "Research Summary"
    }
    [pscustomobject]@{
        name = "wf-005 note creation"
        input = "Create an Obsidian note for WF-005."
        expected_route = "note_creation"
        expected_command = "Create Obsidian note"
    }
    [pscustomobject]@{
        name = "wf-007 private local analysis"
        input = "Perform a private local analysis of this request."
        expected_route = "private_local_analysis"
        expected_command = "Run private local analysis"
    }
    [pscustomobject]@{
        name = "natural workshop change request"
        input = "Switch to Private Workshop."
        expected_route = "workshop_change_request"
        expected_command = "Select workshop in the host/UI."
    }
    [pscustomobject]@{
        name = "legacy cooper slash command"
        input = "/cooper status"
        expected_route = "legacy_cooper_slash_command"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "natural status"
        input = "How is the PDA doing?"
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "WF-004 capability/status precedence - help phrasing"
        input = "What can you do?"
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "WF-004 capability/status precedence - capability phrasing"
        input = "What capabilities do you have?"
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "WF-004 capability/status precedence - phase phrasing"
        input = "What phase are we in?"
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "WF-004 capability/status precedence - operational phrasing"
        input = "What is operational?"
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "WF-004 capability/status precedence - working now phrasing"
        input = "What is working right now?"
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "status summary"
        input = "Summarize the ecosystem status."
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "status report"
        input = "Good morning COOPER. Status report."
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "morning briefing"
        input = "Morning briefing please."
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "how are things going"
        input = "How are things going?"
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "system status"
        input = "System status."
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "health report"
        input = "Health report."
        expected_route = "direct_status"
        expected_command = "Show system status"
    }
    [pscustomobject]@{
        name = "model identity"
        input = "What model are you running?"
        expected_route = "runtime_self_awareness"
        expected_command = ""
    }
    [pscustomobject]@{
        name = "provider identity"
        input = "Who is your provider?"
        expected_route = "runtime_self_awareness"
        expected_command = ""
    }
    [pscustomobject]@{
        name = "backend identity"
        input = "What backend are you using?"
        expected_route = "runtime_self_awareness"
        expected_command = ""
    }
    [pscustomobject]@{
        name = "self identity"
        input = "Who are you?"
        expected_route = "runtime_self_awareness"
        expected_command = ""
    }
    [pscustomobject]@{
        name = "personality settings query"
        input = "What are your personality settings?"
        expected_route = "personality_status"
        expected_command = ""
    }
    [pscustomobject]@{
        name = "humor setting update"
        input = "Set humor to 50."
        expected_route = "personality_update"
        expected_command = ""
    }
    [pscustomobject]@{
        name = "personality proposal"
        input = "Lower verbosity."
        expected_route = "personality_update"
        expected_command = ""
    }
    [pscustomobject]@{
        name = "personality cancel"
        input = "Cancel personality change."
        expected_route = "personality_cancel"
        expected_command = ""
    }
    [pscustomobject]@{
        name = "roadmap request"
        input = "Build me a roadmap."
        expected_route = "goal_planning"
        expected_command = ""
    }
    [pscustomobject]@{
        name = "classic literature goal"
        input = "I want to start reading classic literature. Can you search the internet, create a list of top books from famous authors, write a report, include links and synopses, and make it a PDF?"
        expected_route = "goal_planning"
        expected_command = ""
    }
    [pscustomobject]@{
        name = "ambiguous request"
        input = "Review and run this."
        expected_route = "ambiguous"
        expected_command = ""
    }
    [pscustomobject]@{
        name = "task lookup"
        input = "What happened to my last task?"
        expected_route = "task_lookup"
        expected_command = ""
    }
    [pscustomobject]@{
        name = "memory candidates"
        input = "What memory candidates exist?"
        expected_route = "memory_candidates"
        expected_command = "Review memory candidates."
    }
    [pscustomobject]@{
        name = "commander briefing"
        input = "What should I work on next?"
        expected_route = "commander_briefing"
        expected_command = ""
    }
    [pscustomobject]@{
        name = "dispatch guidance"
        input = "What should handle this task?"
        expected_route = "dispatch_guidance"
        expected_command = "Review dispatch guidance."
    }
    [pscustomobject]@{
        name = "blocked guidance"
        input = "What is blocked?"
        expected_route = "commander_briefing"
        expected_command = ""
    }
    [pscustomobject]@{
        name = "plain chat fallback"
        input = "Tell me something useful about local-first routing."
        expected_route = "fallback"
        expected_command = ""
        expected_default_model = "qwen2.5:7b"
    }
    [pscustomobject]@{
        name = "project discussion fallback"
        input = "Good evening COOPER. What do you think about this project so far?"
        expected_route = "judgment_advice"
        expected_command = ""
        expected_default_model = "qwen2.5:7b"
    }
    [pscustomobject]@{
        name = "project assessment report"
        input = "Give me a project assessment report."
        expected_route = "goal_planning"
        expected_command = ""
    }
    [pscustomobject]@{
        name = "project opinion fallback"
        input = "What is your opinion on the project?"
        expected_route = "judgment_advice"
        expected_command = ""
        expected_default_model = "qwen2.5:7b"
    }
    [pscustomobject]@{
        name = "risk assessment fallback"
        input = "What is the biggest risk here?"
        expected_route = "judgment_advice"
        expected_command = ""
        expected_default_model = "qwen2.5:7b"
    }
    [pscustomobject]@{
        name = "linux migration recommendation"
        input = "Should I move my AI Ecosystem from Windows to Linux?"
        expected_route = "judgment_advice"
        expected_command = ""
        expected_default_model = "qwen2.5:7b"
    }
    [pscustomobject]@{
        name = "docker comparison"
        input = "Docker vs native install"
        expected_route = "judgment_advice"
        expected_command = ""
        expected_default_model = "qwen2.5:7b"
    }
    [pscustomobject]@{
        name = "repo access risk"
        input = "Should I give Codex repo access?"
        expected_route = "judgment_advice"
        expected_command = ""
        expected_default_model = "qwen2.5:7b"
    }
    [pscustomobject]@{
        name = "agent replacement challenge"
        input = "Should I replace workers with agents?"
        expected_route = "judgment_advice"
        expected_command = ""
        expected_default_model = "qwen2.5:7b"
    }
    [pscustomobject]@{
        name = "airlock joke fallback"
        input = "Open the airlock."
        expected_route = "fallback"
        expected_command = ""
        expected_default_model = "qwen2.5:7b"
    }
    [pscustomobject]@{
        name = "launch missiles fallback"
        input = "Launch missiles."
        expected_route = "fallback"
        expected_command = ""
        expected_default_model = "qwen2.5:7b"
    }
    [pscustomobject]@{
        name = "unlock the door fallback"
        input = "Unlock the door."
        expected_route = "fallback"
        expected_command = ""
        expected_default_model = "qwen2.5:7b"
    }
    [pscustomobject]@{
        name = "delete all files fallback"
        input = "Delete all files."
        expected_route = "fallback"
        expected_command = ""
        expected_default_model = "qwen2.5:7b"
    }
    [pscustomobject]@{
        name = "normal greeting"
        input = "Hello COOPER."
        expected_route = "fallback"
        expected_command = ""
        expected_default_model = "qwen2.5:7b"
        expected_token = "Operational."
        stub_model_response = "Operational."
    }
)

$Results = @()
$Passed = 0
$Failed = 0
$DirectConversationId = "router-test-conv"
$DirectSessionId = "router-test-sess"
$DirectUserId = "router-test-user"
$DirectTitle = "PDA Conversational Router Test"
$OriginalDefaultModelChat = if (Get-Command -Name Invoke-COOPERDefaultModelChat -ErrorAction SilentlyContinue) {
    (Get-Item function:Invoke-COOPERDefaultModelChat).ScriptBlock
}
else {
    $DefaultModelChatFallback
}

foreach ($Case in $Cases) {
    $Route = Resolve-PDAConversationalRoute -Text $Case.input -Root $Root
    $Issues = New-Object System.Collections.Generic.List[string]
    $CasePassed = $true

    if ($Route.route_type -ne $Case.expected_route) {
        $CasePassed = $false
        $Issues.Add("Expected route '$($Case.expected_route)' but got '$($Route.route_type)'.")
    }

    if ($Case.expected_command) {
        if ($Route.recommended_command -ne $Case.expected_command) {
            $CasePassed = $false
            $Issues.Add("Expected recommended command '$($Case.expected_command)' but got '$($Route.recommended_command)'.")
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$Route.recommended_command) -and $Route.route_type -notin @("direct_status", "direct_help")) {
        $CasePassed = $false
        $Issues.Add("Expected no recommended command but got '$($Route.recommended_command)'.")
    }

    if ($Case.PSObject.Properties.Name -contains "expected_intent_segments") {
        $SegmentCount = @($Route.intent_segments).Count
        if ($SegmentCount -ne [int]$Case.expected_intent_segments) {
            $CasePassed = $false
            $Issues.Add("Expected $($Case.expected_intent_segments) intent segments but got $SegmentCount.")
        }
    }

    if ($Route.route_type -in @("direct_status", "direct_help", "task_lookup", "dispatch_guidance", "goal_planning", "research_summary", "judgment_advice", "ambiguous", "fallback")) {
        $OriginalDefaultModelChat = $null
        $StubbedModelInvocation = $false
        if (-not $UseLiveModel -or ($Case.PSObject.Properties.Name -contains "stub_model_response" -and -not [string]::IsNullOrWhiteSpace([string]$Case.stub_model_response))) {
            $StubbedModelInvocation = $true
            if (Get-Command -Name Invoke-COOPERDefaultModelChat -ErrorAction SilentlyContinue) {
                $OriginalDefaultModelChat = (Get-Item function:Invoke-COOPERDefaultModelChat).ScriptBlock
            }
            $StubResponse = if ($Case.PSObject.Properties.Name -contains "stub_model_response" -and -not [string]::IsNullOrWhiteSpace([string]$Case.stub_model_response)) {
                [string]$Case.stub_model_response
            }
            else {
                "Operational."
            }
            $StubScript = {
                param(
                    [Parameter(Mandatory = $true)][string]$Text,
                    [Parameter(Mandatory = $false)][string]$Root,
                    [Parameter(Mandatory = $false)][string]$ResponseStyle
                )

                return [pscustomobject]@{
                    status = "pass"
                    default_model = "qwen2.5:7b"
                    selected_model = "qwen2.5:7b"
                    model_status = "pass"
                    model_error_message = ""
                    routing_reason = "router test stub"
                    response_text = $StubResponse
                    next_action = "Awaiting the next task."
                    bridge_mode = "model_chat"
                    handoff_status = "fallback"
                    source_of_truth = "test_stub"
                }
            }.GetNewClosure()
            Set-Item -Path function:Invoke-COOPERDefaultModelChat -Value $StubScript
        }

        $Direct = Get-PDAConversationalNaturalResponse -Route $Route -ConversationId $DirectConversationId -SessionId $DirectSessionId -UserId $DirectUserId -ConversationTitle $DirectTitle -Text $Case.input -Root $Root

        if ($StubbedModelInvocation) {
            $RestoreScript = if ($OriginalDefaultModelChat) { $OriginalDefaultModelChat } else { $DefaultModelChatFallback }
            Set-Item -Path function:Invoke-COOPERDefaultModelChat -Value $RestoreScript
        }

        if ([string]::IsNullOrWhiteSpace([string]$Direct.response_text)) {
            $CasePassed = $false
            $Issues.Add("Direct response text was empty.")
        }
        if ($Route.route_type -eq "direct_status" -and $Direct.response_text -notmatch '(?i)Current Phase: Phase 6 - Private Workshop Hardening|Current Phase: Phase 5 - First Operational Workflows|Operational Workflow Status|Operational Workflows|Approval / Pending Action|Recommended Next Action') {
            $CasePassed = $false
            $Issues.Add("Direct status response did not look like an operational status summary.")
        }
        if ($Route.route_type -eq "direct_help" -and $Direct.response_text -notmatch '(?i)Ask naturally for status, tools, workflows, planning, research, or execution help') {
            $CasePassed = $false
            $Issues.Add("Direct help response did not look like help text.")
        }
        if ($Route.route_type -eq "tool_inventory" -and $Direct.response_text -notmatch '(?i)Tool inventory:') {
            $CasePassed = $false
            $Issues.Add("Tool inventory response did not summarize available tools.")
        }
        if ($Route.route_type -eq "workflow_catalog" -and $Direct.response_text -notmatch '(?i)Workflow catalog:') {
            $CasePassed = $false
            $Issues.Add("Workflow catalog response did not summarize available workflows.")
        }
        if ($Route.route_type -eq "codex_task_generator" -and $Direct.response_text -notmatch '(?i)Created Codex task at|WF-002 Codex task generation could not be completed') {
            $CasePassed = $false
            $Issues.Add("Codex task generation response did not reflect the governed workflow outcome.")
        }
        if ($Case.name -ne "research chain prompt" -and $Route.route_type -eq "research_summary" -and $Direct.response_text -notmatch '(?i)Created research summary at|WF-001 research summary could not be completed') {
            $CasePassed = $false
            $Issues.Add("Research summary response did not reflect the governed workflow outcome.")
        }
        if ($Route.route_type -eq "note_creation" -and $Direct.response_text -notmatch '(?i)Created note at|WF-005 note creation could not be completed') {
            $CasePassed = $false
            $Issues.Add("Note creation response did not reflect the governed workflow outcome.")
        }
        if ($Route.route_type -eq "workshop_change_request" -and $Direct.response_text -notmatch '(?i)Workshop selection remains a human decision') {
            $CasePassed = $false
            $Issues.Add("Workshop change request response did not preserve human control.")
        }
        if ($Route.route_type -eq "legacy_cooper_slash_command" -and $Direct.response_text -notmatch '(?i)legacy COOPER slash-command interface is retired') {
            $CasePassed = $false
            $Issues.Add("Legacy COOPER slash command response did not mark the interface retired.")
        }
        if ($Route.route_type -eq "personality_status" -and $Direct.response_text -notmatch '(?i)COOPER Personality|Profile: operations|Humor: 35|Sarcasm: 15|Professionalism: 90|Brevity: 80|Initiative: 85|Risk awareness: 95') {
            $CasePassed = $false
            $Issues.Add("Personality query response did not include the expected profile values.")
        }
        if ($Route.route_type -eq "cooper_personality_command" -and $Direct.response_text -notmatch '(?i)COOPER Personality|Profile: cyber|Humor:|Risk awareness:') {
            $CasePassed = $false
            $Issues.Add("COOPER personality command response did not summarize the new personality values.")
        }
        if ($Route.route_type -eq "personality_update" -and $Direct.response_text -notmatch '(?i)COOPER Personality|Proposed update|Confirm\?') {
            $CasePassed = $false
            $Issues.Add("Personality update response did not propose a confirmed update.")
        }
        if ($Route.route_type -eq "personality_cancel" -and $Direct.response_text -notmatch '(?i)Change cancelled|No write was performed|Standing by') {
            $CasePassed = $false
            $Issues.Add("Personality cancel response did not acknowledge the cancellation.")
        }
        if ($Route.route_type -eq "ambiguous" -and $Direct.response_text -notmatch '(?i)one action|clarify') {
            $CasePassed = $false
            $Issues.Add("Ambiguous response did not ask for clarification.")
        }
        if ($Route.route_type -eq "memory_candidates" -and $Direct.response_text -notmatch '(?i)memory learning is tracking|pending approvals') {
            $CasePassed = $false
            $Issues.Add("Memory candidate response did not summarize the candidate queue.")
        }
        if ($Route.route_type -eq "commander_briefing" -and $Direct.response_text -notmatch '(?i)pda daily brief|recommended actions|queue:') {
            $CasePassed = $false
            $Issues.Add("Commander briefing response did not look like a daily brief.")
        }
        if ($Route.route_type -eq "dispatch_guidance" -and $Direct.response_text -notmatch '(?i)recommended executor|available executors|dispatch queue') {
            $CasePassed = $false
            $Issues.Add("Dispatch guidance response did not mention executors or dispatch state.")
        }
        if ($Route.route_type -eq "goal_planning" -and $Direct.response_text -notmatch '(?i)goal assessment|execution plan|approval path') {
            $CasePassed = $false
            $Issues.Add("Goal planning response did not look like a structured plan.")
        }
        if ($Route.route_type -eq "goal_planning" -and $Case.name -eq "project assessment report" -and $Direct.response_text -notmatch '(?i)goal assessment|execution plan|approval path') {
            $CasePassed = $false
            $Issues.Add("Explicit structured report request did not return structured output.")
        }
        if ($Route.route_type -eq "judgment_advice" -and $Direct.response_text -match '(?i)\bRecommended command\b|Confirm to dispatch|Reply with confirmation|Standing by for tasking|^\s*(Recommendation|Assessment|Risks|Benefits|Costs|Alternative|Confidence)\s*:') {
            $CasePassed = $false
            $Issues.Add("Judgment advice should not produce workflow-routing language.")
        }
        if ($Route.route_type -eq "judgment_advice") {
            $SentenceCount = @([regex]::Split([string]$Direct.response_text, '(?<=[\.\!\?])\s+') | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
            if ($SentenceCount -gt 4) {
                $CasePassed = $false
                $Issues.Add("Judgment advice should stay within 4 sentences.")
            }
            if ($Direct.response_text -match '(?i)\b(next move|next step|next steps|I recommend|Recommendation:|Assessment:|Risks:|Benefits:|Costs:|Alternative:)\b') {
                $CasePassed = $false
                $Issues.Add("Judgment advice should not auto-inject recommendations or next steps.")
            }
        }
        if ($Route.route_type -eq "fallback") {
            if (-not ($Direct.PSObject.Properties.Name -contains "selected_model")) {
                $CasePassed = $false
                $Issues.Add("Fallback response did not include selected_model.")
            }
            elseif ($Case.PSObject.Properties.Name -contains "expected_default_model" -and $Direct.selected_model -ne $Case.expected_default_model) {
                $CasePassed = $false
                $Issues.Add("Fallback response selected '$($Direct.selected_model)' instead of '$($Case.expected_default_model)'.")
            }

            if (-not ($Direct.PSObject.Properties.Name -contains "model_status")) {
                $CasePassed = $false
                $Issues.Add("Fallback response did not include model_status.")
            }
            elseif ($Direct.model_status -eq "pass" -and $Direct.response_text -match [regex]::Escape("Status, reports, research, planning, execution. Pick a target.")) {
                $CasePassed = $false
                $Issues.Add("Fallback response returned legacy static help even though the model path succeeded.")
            }
            elseif ($Direct.model_status -ne "pass" -and [string]::IsNullOrWhiteSpace([string]$Direct.model_error_message)) {
                $CasePassed = $false
                $Issues.Add("Fallback model failure did not report a useful error.")
            }
            if ($Direct.PSObject.Properties.Name -contains "next_action" -and [string]$Direct.next_action -match '(?i)provider metadata|raw response') {
                $CasePassed = $false
                $Issues.Add("Fallback response exposed the provider metadata trailer in next_action.")
            }
            if ($Case.name -eq "normal greeting" -and $Direct.response_text -match '(?i)How can I assist you today|I''m happy to help|Continue the conversation|Current Explosions: 0') {
                $CasePassed = $false
                $Issues.Add("Normal greeting used a cheerful or noisy legacy phrase.")
            }
        }
        if ($Case.PSObject.Properties.Name -contains "expected_token" -and -not [string]::IsNullOrWhiteSpace([string]$Case.expected_token)) {
            if ($Direct.response_text -notmatch [regex]::Escape([string]$Case.expected_token)) {
                $CasePassed = $false
                $Issues.Add("Expected response text to contain '$([string]$Case.expected_token)'.")
            }
        }
    }
    elseif ($Route.route_type -eq "runtime_self_awareness") {
        $script:COOPERModelInvocationCount = 0
        $StubScript = {
            param(
                [Parameter(Mandatory = $true)][string]$Text,
                [Parameter(Mandatory = $false)][string]$Root,
                [Parameter(Mandatory = $false)][string]$ResponseStyle
            )

            $script:COOPERModelInvocationCount++
            return [pscustomobject]@{
                status = "pass"
                default_model = "stub"
                selected_model = "stub"
                model_status = "pass"
                model_error_message = ""
                routing_reason = "stub"
                response_text = "stub"
                next_action = "stub"
                bridge_mode = "model_chat"
                handoff_status = "fallback"
                source_of_truth = "test_stub"
            }
        }

        try {
            Set-Item -Path function:Invoke-COOPERDefaultModelChat -Value $StubScript
            $Direct = Get-PDAConversationalNaturalResponse -Route $Route -ConversationId $DirectConversationId -SessionId $DirectSessionId -UserId $DirectUserId -ConversationTitle $DirectTitle -Text $Case.input -Root $Root
        }
        finally {
            $RestoreScript = if ($OriginalDefaultModelChat) { $OriginalDefaultModelChat } else { $DefaultModelChatFallback }
            Set-Item -Path function:Invoke-COOPERDefaultModelChat -Value $RestoreScript
        }

        if ([string]::IsNullOrWhiteSpace([string]$Direct.response_text)) {
            $CasePassed = $false
            $Issues.Add("Runtime self-awareness response text was empty.")
        }
        if ($Direct.response_text -notmatch '(?i)Active Workshop: COOPER|Default Model: Claude Sonnet|Assistant Identity: COOPER') {
            $CasePassed = $false
            $Issues.Add("Runtime self-awareness response did not include the expected metadata.")
        }
        if ($Direct.runtime_status -and $Direct.runtime_status.PSObject.Properties.Name -contains "workbench_result" -and $Direct.runtime_status.workbench_result -and $Direct.runtime_status.workbench_result.PSObject.Properties.Name -contains "output" -and $Direct.runtime_status.workbench_result.output.PSObject.Properties.Name -contains "status_source" -and [string]$Direct.runtime_status.workbench_result.output.status_source -match 'Get-COOPERRuntimeStatus\.ps1') {
            $CasePassed = $false
            $Issues.Add("Runtime self-awareness response must not use the legacy runtime helper as authoritative output.")
        }
        if ($script:COOPERModelInvocationCount -ne 0) {
            $CasePassed = $false
            $Issues.Add("Runtime self-awareness response should bypass model invocation.")
        }
    }

    $Results += [pscustomobject]@{
        name = $Case.name
        passed = $CasePassed
        route_type = $Route.route_type
        recommended_command = $Route.recommended_command
        response_mode = $Route.response_mode
        reason = $Route.reason
        issues = @($Issues)
    }

    if ($CasePassed) {
        $Passed++
    }
    else {
        $Failed++
    }
}

$Report = [pscustomobject]@{
    status = if ($Failed -eq 0) { "pass" } else { "fail" }
    test_case_count = @($Results).Count
    passed_count = $Passed
    failed_count = $Failed
    results = @($Results)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA conversational router validation failed."
    }
    return
}

Write-Host "[*] PDA conversational router tests"
Write-Host ("Test cases : {0}" -f $Report.test_case_count)
Write-Host ("Passed     : {0}" -f $Report.passed_count)
Write-Host ("Failed     : {0}" -f $Report.failed_count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA conversational router validation failed."
}
