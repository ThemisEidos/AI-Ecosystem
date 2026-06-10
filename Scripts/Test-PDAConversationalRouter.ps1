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

if (-not (Test-Path -LiteralPath $RouterScript -PathType Leaf)) {
    throw "Conversational router missing: $RouterScript"
}

. $RouterScript

$Cases = @(
    [pscustomobject]@{
        name = "slash status"
        input = "/status"
        expected_route = "slash_command"
        expected_command = "/status"
    }
    [pscustomobject]@{
        name = "fabric report slash"
        input = "/fabric report Summarize the current PDA ecosystem status..."
        expected_route = "slash_command"
        expected_command = "/fabric report"
    }
    [pscustomobject]@{
        name = "natural status"
        input = "How is the PDA doing?"
        expected_route = "direct_status"
        expected_command = "/status"
    }
    [pscustomobject]@{
        name = "natural help"
        input = "What can you do?"
        expected_route = "direct_help"
        expected_command = "/help"
    }
    [pscustomobject]@{
        name = "status summary"
        input = "Summarize the ecosystem status."
        expected_route = "direct_status"
        expected_command = "/status"
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
        expected_command = "/memory"
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
        expected_command = "/dispatch"
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
        expected_default_model = "local-llama"
    }
)

$Results = @()
$Passed = 0
$Failed = 0
$DirectConversationId = "router-test-conv"
$DirectSessionId = "router-test-sess"
$DirectUserId = "router-test-user"
$DirectTitle = "PDA Conversational Router Test"

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

    if ($Route.route_type -in @("direct_status", "direct_help", "task_lookup", "dispatch_guidance", "goal_planning", "ambiguous", "fallback")) {
        $Direct = Get-PDAConversationalNaturalResponse -Route $Route -ConversationId $DirectConversationId -SessionId $DirectSessionId -UserId $DirectUserId -ConversationTitle $DirectTitle -Text $Case.input -Root $Root
        if ([string]::IsNullOrWhiteSpace([string]$Direct.response_text)) {
            $CasePassed = $false
            $Issues.Add("Direct response text was empty.")
        }
        if ($Route.route_type -eq "direct_status" -and $Direct.response_text -notmatch '(?i)pda is reachable|dashboard') {
            $CasePassed = $false
            $Issues.Add("Direct status response did not look like a status summary.")
        }
        if ($Route.route_type -eq "direct_help" -and $Direct.response_text -notmatch '(?i)i can check status|help') {
            $CasePassed = $false
            $Issues.Add("Direct help response did not look like help text.")
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
            elseif ($Direct.model_status -eq "pass" -and $Direct.response_text -match [regex]::Escape("I can help with status, briefing, blocked work, recent changes, tasks, workers, reports, memory, Fabric, NotebookLM, environment analysis, goal planning, research, review, and execution.")) {
                $CasePassed = $false
                $Issues.Add("Fallback response returned legacy static help even though the model path succeeded.")
            }
            elseif ($Direct.model_status -ne "pass" -and [string]::IsNullOrWhiteSpace([string]$Direct.model_error_message)) {
                $CasePassed = $false
                $Issues.Add("Fallback model failure did not report a useful error.")
            }
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
