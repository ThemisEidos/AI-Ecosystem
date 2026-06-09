function Normalize-PDACommanderDecisionText {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    $Normalized = [string]$Value
    $Normalized = $Normalized.ToLowerInvariant()
    $Normalized = $Normalized -replace '[^a-z0-9/\s]+', ' '
    $Normalized = $Normalized -replace '\s+', ' '
    return $Normalized.Trim()
}

function Test-PDACommanderDecisionAmbiguous {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\breview\b.*\brun\b|\brun\b.*\breview\b|\breport\b.*\brun\b|\brun\b.*\breport\b|\bresearch\b.*\brun\b|\brun\b.*\bresearch\b|\bexecute\b.*\breview\b|\breview\b.*\bexecute\b'
    )
}

function Test-PDACommanderDecisionDirectAnswer {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(status|help|what can you do|what commands|available commands|task status|where is my result|result location|what happened|briefing|what should i work on next|what changed recently|what needs attention|what is blocked|memory candidates|workers|reports)\b'
    )
}

function Test-PDACommanderDecisionEnvironmentAwareness {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(filesystem|file system|repository|repositories|docker|container|containers|service inventory|service status|tool inventory|workspace inventory|environment awareness|environment inventory|file structure|organize folders|storage locations|scan c:\\|scan ~/|scan my filesystem|show my repositories|what ai services are running|help organize my folders|recommend a better project structure|workspace structure|project structure)\b'
    )
}

function Test-PDACommanderDecisionGoalPlanning {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(classic literature|reading list|study plan|goal plan|goal decomposition|build me a roadmap|create a roadmap|help me create|analyze my project|what needs to happen|reading guide|pdf report|write a report|make it a pdf|summarize and create|search the internet)\b' -or
        ($NormalizedText -match '(?i)\b(xlsx|excel|spreadsheet|workbook)\b' -and $NormalizedText -match '(?i)\b(validate|check|verify|audit|rate[- ]?limit|limit requests?|first \d+ links?|first ten links?|links?|urls?)\b' -and $NormalizedText -match '(?i)\b(report|markdown|obsidian|write|save)\b') -or
        ($NormalizedText -match '(?i)\b(research|investigate|search|study|authors|books)\b' -and $NormalizedText -match '(?i)\b(report|pdf|synopsis|synopses|links|sources|reading list|roadmap|plan|guide)\b')
    )
}

function Test-PDACommanderDecisionAutomation {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(automate|automation|workflow|n8n|sync|integration|orchestrate|scheduled)\b'
    )
}

function Test-PDACommanderDecisionExplicitDispatch {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText.StartsWith("/") -or
        $NormalizedText -match '(?i)\b(dispatch|run|execute|launch|start)\b'
    )
}

function Get-PDACommanderDecisionLegacyRouteType {
    param(
        [Parameter(Mandatory = $true)][string]$DecisionType,
        [Parameter(Mandatory = $true)][string]$Intent
    )

    switch ($DecisionType) {
        "clarify" { return "ambiguous" }
        "plan" { return "goal_planning" }
        "recommend_workflow" {
            if ($Intent -eq "environment_awareness") { return "environment_awareness" }
            return "dispatch_guidance"
        }
        "dispatch_worker" { return "governed_request" }
        "dispatch_n8n" { return "governed_request" }
        "restricted_local" { return "governed_request" }
        default {
            switch ($Intent) {
                "status_lookup" { return "direct_status" }
                "operator_help" { return "direct_help" }
                "task_lookup" { return "task_lookup" }
                "memory_candidates" { return "memory_candidates" }
                "commander_briefing" { return "commander_briefing" }
                "environment_awareness" { return "environment_awareness" }
                "goal_planning" { return "goal_planning" }
                "dispatch_guidance" { return "dispatch_guidance" }
                default { return "direct_answer" }
            }
        }
    }
}

function Get-PDACommanderDecisionLocalExecutor {
    param(
        [Parameter(Mandatory = $true)][string]$DecisionType,
        [Parameter(Mandatory = $true)][string]$Intent,
        [Parameter(Mandatory = $false)]$Recommendation
    )

    if ($Recommendation -and -not [string]::IsNullOrWhiteSpace([string]$Recommendation.recommended_executor)) {
        $Selected = [string]$Recommendation.recommended_executor
        if ($Selected -notin @("n8n", "gemini-cli", "openai", "lite-llm")) {
            return $Selected
        }
    }

    switch ($DecisionType) {
        "plan" { return "planner-worker" }
        "recommend_workflow" {
            if ($Intent -eq "environment_awareness") { return "planner-worker" }
            return "operator-console-worker"
        }
        "dispatch_worker" { return "execute-worker" }
        "dispatch_n8n" { return "n8n" }
        "restricted_local" {
            switch ($Intent) {
                "goal_planning" { return "planner-worker" }
                "environment_awareness" { return "planner-worker" }
                "automation" { return "execute-worker" }
                default { return "operator-console-worker" }
            }
        }
        default { return "operator-console-worker" }
    }
}

function Get-PDACommanderDecisionRecommendedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$DecisionType,
        [Parameter(Mandatory = $true)][string]$Intent,
        [Parameter(Mandatory = $false)]$Recommendation
    )

    if ($Recommendation -and -not [string]::IsNullOrWhiteSpace([string]$Recommendation.recommended_command)) {
        return [string]$Recommendation.recommended_command
    }

    switch ($DecisionType) {
        "direct_answer" {
            switch ($Intent) {
                "status_lookup" { return "/status" }
                "operator_help" { return "/help" }
                "memory_candidates" { return "/memory" }
                "commander_briefing" { return "/status" }
                "task_lookup" { return "/tasks" }
                default { return "" }
            }
        }
        "plan" { return "/planner" }
        "recommend_workflow" {
            if ($Intent -eq "environment_awareness") { return "/planner" }
            return "/dispatch"
        }
        "dispatch_worker" { return "/dispatch" }
        "dispatch_n8n" { return "/dispatch" }
        "restricted_local" { return "/dispatch" }
        default { return "" }
    }
}

function New-PDACommanderDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [string]$TaskType,

        [Parameter(Mandatory = $false)]
        [ValidateSet("category_1", "category_2", "restricted_local")]
        [string]$Category = "category_1",

        [Parameter(Mandatory = $false)]
        [string]$PreferredOutput = "",

        [Parameter(Mandatory = $false)]
        [switch]$RequiresLocalOnly,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
    if ((Test-Path -LiteralPath $ParserPath -PathType Leaf) -and -not (Get-Command -Name ConvertFrom-PDAMixedJson -ErrorAction SilentlyContinue)) {
        . $ParserPath
    }

    $RecommendationScript = Join-Path $PSScriptRoot "Get-PDACommanderRecommendation.ps1"
    if ((-not (Get-Command -Name Get-PDACommanderRecommendation -ErrorAction SilentlyContinue)) -and (Test-Path -LiteralPath $RecommendationScript -PathType Leaf)) {
        . $RecommendationScript
    }

    $Normalized = Normalize-PDACommanderDecisionText -Value $Text
    $CategoryValue = [string]$Category
    $DecisionType = "clarify"
    $Intent = "clarification"
    $Reason = "No decision could be derived."
    $RequiresConfirmation = $false
    $DispatchReady = $false
    $DispatchStatus = "not_applicable"
    $RecommendedCommand = ""
    $RecommendedExecutor = ""
    $FallbackRecommendation = $null
    $MatchedRules = New-Object System.Collections.Generic.List[string]
    $RequiresLocalOnlyValue = [bool]$RequiresLocalOnly -or $CategoryValue -in @("category_2", "restricted_local")

    if ([string]::IsNullOrWhiteSpace($Normalized)) {
        $Reason = "Empty input."
    }
    elseif (Test-PDACommanderDecisionAmbiguous -NormalizedText $Normalized) {
        $DecisionType = "clarify"
        $Intent = "clarification"
        $Reason = "Multiple governed actions were requested in one message."
        $MatchedRules.Add("ambiguous") | Out-Null
    }
    elseif (Test-PDACommanderDecisionDirectAnswer -NormalizedText $Normalized) {
        $DecisionType = "direct_answer"
        if ($Normalized -match '(?i)\b(help|commands|available commands)\b') {
            $Intent = "operator_help"
            $Reason = "Direct help request."
            $MatchedRules.Add("direct_help") | Out-Null
        }
        elseif ($Normalized -match '(?i)\b(memory candidates|pending memory promotions|memory promotion|what did the pda learn)\b') {
            $Intent = "memory_candidates"
            $Reason = "Direct memory candidate request."
            $MatchedRules.Add("memory_candidates") | Out-Null
        }
        elseif ($Normalized -match '(?i)\b(task status|where is my result|result location|what happened)\b') {
            $Intent = "task_lookup"
            $Reason = "Direct task lookup request."
            $MatchedRules.Add("task_lookup") | Out-Null
        }
        elseif ($Normalized -match '(?i)\b(what should i work on next|give me my pda briefing|what is blocked|what needs attention|what changed recently)\b') {
            $Intent = "commander_briefing"
            $Reason = "Direct Commander briefing request."
            $MatchedRules.Add("commander_briefing") | Out-Null
        }
        else {
            $Intent = "status_lookup"
            $Reason = "Direct status request."
            $MatchedRules.Add("direct_status") | Out-Null
        }
    }
    elseif (Test-PDACommanderDecisionEnvironmentAwareness -NormalizedText $Normalized) {
        $Intent = "environment_awareness"
        $FallbackRecommendation = if (Get-Command -Name Get-PDACommanderRecommendation -ErrorAction SilentlyContinue) {
            Get-PDACommanderRecommendation -Text $Text -TaskType $TaskType -Category $CategoryValue -PreferredOutput $PreferredOutput -RequiresLocalOnly:$RequiresLocalOnly -Root $Root
        }
        else {
            $null
        }

        if ($Normalized -match '(?i)\b(recommend|better structure|organize|organization|structure|migration|cleanup|plan)\b') {
            $DecisionType = "plan"
            $Reason = "Environment analysis should produce a governed plan."
            $MatchedRules.Add("environment_plan") | Out-Null
        }
        else {
            $DecisionType = "recommend_workflow"
            $Reason = "Environment analysis should recommend a workflow or inventory path."
            $MatchedRules.Add("environment_inventory") | Out-Null
        }
    }
    elseif (Test-PDACommanderDecisionGoalPlanning -NormalizedText $Normalized) {
        $DecisionType = "plan"
        $Intent = "goal_planning"
        $Reason = "Natural-language goal decomposition request."
        $MatchedRules.Add("goal_planning") | Out-Null
        if (Get-Command -Name Get-PDACommanderRecommendation -ErrorAction SilentlyContinue) {
            $FallbackRecommendation = Get-PDACommanderRecommendation -Text $Text -TaskType $TaskType -Category $CategoryValue -PreferredOutput $PreferredOutput -RequiresLocalOnly:$RequiresLocalOnly -Root $Root
        }
    }
    elseif (Test-PDACommanderDecisionAutomation -NormalizedText $Normalized) {
        if ($RequiresLocalOnlyValue -or $CategoryValue -in @("category_2", "restricted_local")) {
            $DecisionType = "restricted_local"
            $Intent = "automation"
            $Reason = "Automation request must remain local-only under the current category policy."
            $MatchedRules.Add("automation_local_only") | Out-Null
        }
        else {
            $DecisionType = "dispatch_n8n"
            $Intent = "automation"
            $Reason = "Automation request can be handled by n8n under category 1."
            $MatchedRules.Add("automation_n8n") | Out-Null
        }
        if (Get-Command -Name Get-PDACommanderRecommendation -ErrorAction SilentlyContinue) {
            $FallbackRecommendation = Get-PDACommanderRecommendation -Text $Text -TaskType $TaskType -Category $CategoryValue -PreferredOutput $PreferredOutput -RequiresLocalOnly:$RequiresLocalOnly -Root $Root
        }
    }
    elseif (Test-PDACommanderDecisionExplicitDispatch -NormalizedText $Normalized) {
        $DecisionType = "dispatch_worker"
        $Intent = if ($TaskType) { [string]$TaskType } else { "dispatch" }
        $Reason = "Explicit dispatch request."
        $MatchedRules.Add("explicit_dispatch") | Out-Null
        if (Get-Command -Name Get-PDACommanderRecommendation -ErrorAction SilentlyContinue) {
            $FallbackRecommendation = Get-PDACommanderRecommendation -Text $Text -TaskType $TaskType -Category $CategoryValue -PreferredOutput $PreferredOutput -RequiresLocalOnly:$RequiresLocalOnly -Root $Root
        }
    }
    else {
        $DecisionType = "clarify"
        $Intent = "clarification"
        $Reason = "Request needs clarification before governed routing."
        $MatchedRules.Add("fallback_clarify") | Out-Null
    }

    if (-not $FallbackRecommendation -and (Get-Command -Name Get-PDACommanderRecommendation -ErrorAction SilentlyContinue)) {
        try {
            $FallbackRecommendation = Get-PDACommanderRecommendation -Text $Text -TaskType $TaskType -Category $CategoryValue -PreferredOutput $PreferredOutput -RequiresLocalOnly:$RequiresLocalOnly -Root $Root
        }
        catch {
            $FallbackRecommendation = $null
        }
    }

    if ($RequiresLocalOnlyValue -and $DecisionType -eq "dispatch_n8n") {
        $DecisionType = "restricted_local"
        $Reason = "Category policy requires local-only routing."
        $MatchedRules.Add("category_restricted") | Out-Null
    }

    if ($DecisionType -eq "restricted_local") {
        $RequiresLocalOnlyValue = $true
    }

    $RecommendedExecutor = Get-PDACommanderDecisionLocalExecutor -DecisionType $DecisionType -Intent $Intent -Recommendation $FallbackRecommendation
    if ($RequiresLocalOnlyValue -and [string]::IsNullOrWhiteSpace($RecommendedExecutor)) {
        $RecommendedExecutor = "planner-worker"
    }

    if ($RequiresLocalOnlyValue -and $RecommendedExecutor -eq "n8n") {
        $RecommendedExecutor = "execute-worker"
    }

    $RecommendedCommand = Get-PDACommanderDecisionRecommendedCommand -DecisionType $DecisionType -Intent $Intent -Recommendation $FallbackRecommendation

    if ($DecisionType -in @("dispatch_worker", "dispatch_n8n", "restricted_local")) {
        $RequiresConfirmation = $true
        $DispatchReady = $true
        $DispatchStatus = "not_dispatched"
    }
    elseif ($DecisionType -eq "recommend_workflow") {
        $DispatchReady = $false
        $DispatchStatus = "not_applicable"
    }
    elseif ($DecisionType -eq "plan") {
        $DispatchReady = $false
        $DispatchStatus = "not_applicable"
    }
    else {
        $DispatchReady = $false
        $DispatchStatus = "not_applicable"
    }

    $RouteType = Get-PDACommanderDecisionLegacyRouteType -DecisionType $DecisionType -Intent $Intent
    $ResponseMode = switch ($DecisionType) {
        "clarify" { "clarification" }
        "direct_answer" { "direct_answer" }
        default { if ($DecisionType -in @("dispatch_worker", "dispatch_n8n", "restricted_local")) { "governed_command" } else { "direct_answer" } }
    }

    $Allowed = -not $RequiresLocalOnlyValue -or $DecisionType -ne "dispatch_n8n"
    $BlockedReason = ""
    if ($RequiresLocalOnlyValue -and $RecommendedExecutor -eq "n8n") {
        $Allowed = $false
        $BlockedReason = "Local-only routing requires a local executor."
    }

    if ($DecisionType -eq "plan" -and $RouteType -eq "goal_planning") {
        $RecommendedCommand = if ([string]::IsNullOrWhiteSpace($RecommendedCommand)) { "/planner" } else { $RecommendedCommand }
    }

    if ($DecisionType -eq "direct_answer" -and [string]::IsNullOrWhiteSpace($RecommendedCommand)) {
        switch ($Intent) {
            "operator_help" { $RecommendedCommand = "/help" }
            "status_lookup" { $RecommendedCommand = "/status" }
            "memory_candidates" { $RecommendedCommand = "/memory" }
            "task_lookup" { $RecommendedCommand = "/tasks" }
            default { }
        }
    }

    $Result = [pscustomobject]@{
        decision_id = [guid]::NewGuid().ToString()
        created_at = (Get-Date).ToUniversalTime().ToString("o")
        source = [pscustomobject]@{
            surface = "decision_engine"
            script = "Scripts/PDA_DecisionEngine.ps1"
        }
        request = [pscustomobject]@{
            text = [string]$Text
            conversation_id = ""
            session_id = ""
            user_id = ""
            root_path = [string]$Root
        }
        decision_type = [string]$DecisionType
        classification = [pscustomobject]@{
            decision_type = [string]$DecisionType
            intent = [string]$Intent
            task_type = if ([string]::IsNullOrWhiteSpace($TaskType)) { "" } else { [string]$TaskType }
            goal_type = if ($FallbackRecommendation -and $FallbackRecommendation.PSObject.Properties.Name -contains "classification") { [string]$FallbackRecommendation.classification } else { "" }
            category = [string]$CategoryValue
            confidence = if ($FallbackRecommendation -and $FallbackRecommendation.PSObject.Properties.Name -contains "confidence") { [double]$FallbackRecommendation.confidence } else { if ($DecisionType -eq "clarify") { 0.5 } elseif ($DecisionType -eq "direct_answer") { 1 } else { 0.9 } }
            ambiguous = [bool]($DecisionType -eq "clarify")
        }
        governance = [pscustomobject]@{
            allowed = [bool]$Allowed
            requires_confirmation = [bool]$RequiresConfirmation
            approval_required = if ($FallbackRecommendation -and $FallbackRecommendation.PSObject.Properties.Name -contains "approval_required") { [bool]$FallbackRecommendation.approval_required } else { $false }
            requires_local_only = [bool]$RequiresLocalOnlyValue
            blocked_reason = [string]$BlockedReason
        }
        routing = [pscustomobject]@{
            recommended_command = [string]$RecommendedCommand
            recommended_executor = [string]$RecommendedExecutor
            recommended_workflow = if ($DecisionType -eq "dispatch_n8n") { "n8n" } elseif ($DecisionType -eq "plan" -and $Intent -eq "environment_awareness") { "environment_inventory" } else { "" }
            dispatch_target = if ($DecisionType -eq "dispatch_n8n") { "n8n" } elseif ($DecisionType -in @("dispatch_worker", "restricted_local")) { "worker" } elseif ($DecisionType -eq "plan") { "planner" } else { "none" }
            next_action = if ($DecisionType -eq "clarify") { "Refine the request so the decision engine can route one governed action." } elseif ($DecisionType -eq "plan") { "Review the generated plan before any dispatch." } elseif ($DecisionType -in @("dispatch_worker", "dispatch_n8n", "restricted_local")) { "Confirm the recommendation to submit through governed dispatch." } else { "Continue with the direct answer." }
            response_mode = $ResponseMode
        }
        plan = [pscustomobject]@{
            goal_plan = $null
            execution_plan = $null
            subtasks = @()
            deliverables = @()
        }
        diagnostics = [pscustomobject]@{
            reason = [string]$Reason
            fallback_reason = if ($FallbackRecommendation -and $FallbackRecommendation.PSObject.Properties.Name -contains "routing_reason") { [string]$FallbackRecommendation.routing_reason } else { "" }
            matched_rules = @($MatchedRules)
            capability_route = if ($FallbackRecommendation -and $FallbackRecommendation.PSObject.Properties.Name -contains "capability_route") { $FallbackRecommendation.capability_route } else { $null }
            executor_recommendation = $FallbackRecommendation
        }
        route_type = [string]$RouteType
        intent = [string]$Intent
        recommended_command = [string]$RecommendedCommand
        recommended_executor = [string]$RecommendedExecutor
        requires_confirmation = [bool]$RequiresConfirmation
        dispatch_ready = [bool]$DispatchReady
        dispatch_status = [string]$DispatchStatus
        response_mode = [string]$ResponseMode
        allowed = [bool]$Allowed
        blocked_reason = [string]$BlockedReason
        source_of_truth = "Scripts/PDA_DecisionEngine.ps1"
    }

    return $Result
}
