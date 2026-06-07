[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Text,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_TaskOntology.ps1")
$CapabilityRouterScript = Join-Path $PSScriptRoot "PDA_CapabilityRouter.ps1"
if (Test-Path -LiteralPath $CapabilityRouterScript -PathType Leaf) {
    . $CapabilityRouterScript
}

function Normalize-PDACommandInterpreterText {
    param([string]$Value)

    $Normalized = [string]$Value
    $Normalized = $Normalized.ToLowerInvariant()
    $Normalized = $Normalized -replace '[^a-z0-9/]+', ' '
    $Normalized = $Normalized -replace '\s+', ' '
    return $Normalized.Trim()
}

function Get-PDACommandInterpreterRules {
    @(
        [pscustomobject]@{
            rule_id        = "review_findings"
            intent         = "review"
            task_type      = "review"
            command        = "/review"
            priority       = 100
            exact_phrases  = @("review my latest findings", "review latest findings", "latest findings review", "review findings")
            keywords       = @("review", "findings", "audit", "evaluate", "feedback", "critique")
            recommendation = "Use /review for findings review, critique, audit, and evaluation requests."
        }
        [pscustomobject]@{
            rule_id        = "report_generation"
            intent         = "report_generation"
            task_type      = "report_generation"
            command        = "/reporter"
            priority       = 95
            exact_phrases  = @("draft an executive summary", "executive summary", "write a summary", "draft a summary", "generate a report", "write a report")
            keywords       = @("draft", "summary", "summarize", "report", "reporting", "executive", "briefing")
            recommendation = "Use /reporter for report generation, summaries, and executive briefings."
        }
        [pscustomobject]@{
            rule_id        = "planning"
            intent         = "planning"
            task_type      = "planning"
            command        = "/planner"
            priority       = 90
            exact_phrases  = @("analyze this project", "analyze the project", "plan this project", "project analysis", "workflow planning")
            keywords       = @("analyze", "analysis", "plan", "planning", "project", "workflow", "strategy")
            recommendation = "Use /planner for project analysis, planning, and workflow design requests."
        }
        [pscustomobject]@{
            rule_id        = "operator_status"
            intent         = "operator_status"
            task_type      = "operator_status"
            command        = "/status"
            priority       = 92
            exact_phrases  = @("/status")
            keywords       = @()
            recommendation = "Use /status for a read-only PDA operator console health summary."
        }
        [pscustomobject]@{
            rule_id        = "operator_tasks"
            intent         = "operator_tasks"
            task_type      = "operator_tasks"
            command        = "/tasks"
            priority       = 91
            exact_phrases  = @("/tasks")
            keywords       = @()
            recommendation = "Use /tasks for a read-only summary of recent task activity."
        }
        [pscustomobject]@{
            rule_id        = "operator_approvals"
            intent         = "operator_approvals"
            task_type      = "operator_approvals"
            command        = "/approvals"
            priority       = 90
            exact_phrases  = @("/approvals")
            keywords       = @()
            recommendation = "Use /approvals for a read-only summary of pending approvals."
        }
        [pscustomobject]@{
            rule_id        = "operator_workers"
            intent         = "operator_workers"
            task_type      = "operator_workers"
            command        = "/workers"
            priority       = 89
            exact_phrases  = @("/workers")
            keywords       = @()
            recommendation = "Use /workers for a read-only summary of worker health and registry status."
        }
        [pscustomobject]@{
            rule_id        = "operator_reports"
            intent         = "operator_reports"
            task_type      = "operator_reports"
            command        = "/reports"
            priority       = 88
            exact_phrases  = @("/reports")
            keywords       = @()
            recommendation = "Use /reports for a read-only summary of recent reports and artifacts."
        }
        [pscustomobject]@{
            rule_id        = "operator_memory"
            intent         = "operator_memory"
            task_type      = "operator_memory"
            command        = "/memory"
            priority       = 87
            exact_phrases  = @("/memory")
            keywords       = @()
            recommendation = "Use /memory for a read-only summary of memory health and recent records."
        }
        [pscustomobject]@{
            rule_id        = "operator_help"
            intent         = "operator_help"
            task_type      = "operator_help"
            command        = "/help"
            priority       = 86
            exact_phrases  = @("/help")
            keywords       = @()
            recommendation = "Use /help for a read-only list of PDA Commander operator commands."
        }
        [pscustomobject]@{
            rule_id        = "notebooklm_package"
            intent         = "notebooklm_package"
            task_type      = "notebooklm_package"
            command        = "/notebooklm"
            priority       = 93
            exact_phrases  = @(
                "create a notebooklm package",
                "create notebooklm package",
                "generate a notebooklm package",
                "generate notebooklm package",
                "notebooklm package",
                "prepare notebooklm sources"
            )
            keywords       = @("notebooklm", "sanitized", "package", "sources", "upload package")
            recommendation = "Use /notebooklm to build a sanitized NotebookLM package from Category 1 Obsidian sources."
        }
        [pscustomobject]@{
            rule_id        = "research_task_requests"
            intent         = "research_synthesis"
            task_type      = "research_synthesis"
            command        = "/research"
            priority       = 89
            exact_phrases  = @(
                "create a test research task",
                "create a research task",
                "create research task",
                "test research task",
                "research task",
                "research request"
            )
            keywords       = @("research", "researching", "investigate", "sources", "evidence", "study", "synthesis", "lookup")
            recommendation = "Use /research for evidence gathering, synthesis, and research task requests."
        }
        [pscustomobject]@{
            rule_id        = "execution_manifest"
            intent         = "execution_manifest"
            task_type      = "execution_manifest"
            command        = "/execute"
            priority       = 85
            exact_phrases  = @("run the workflow", "execute the workflow", "run workflow", "start the workflow", "execute this", "run this")
            keywords       = @("run", "execute", "workflow", "launch", "start", "apply")
            recommendation = "Use /execute for governed execution requests and workflow launches."
        }
        [pscustomobject]@{
            rule_id        = "research_synthesis"
            intent         = "research_synthesis"
            task_type      = "research_synthesis"
            command        = "/research"
            priority       = 80
            exact_phrases  = @("research this", "investigate this", "find sources", "research sources", "gather evidence")
            keywords       = @("research", "investigate", "sources", "evidence", "study", "synthesis", "lookup")
            recommendation = "Use /research for evidence gathering and synthesis requests."
        }
        [pscustomobject]@{
            rule_id        = "fabric_research_pattern"
            intent         = "fabric_research_pattern"
            task_type      = "fabric_research_pattern"
            command        = "/fabric research"
            priority       = 75
            exact_phrases  = @("fabric research", "run fabric research", "research with fabric", "fabric research pattern")
            keywords       = @("fabric", "research", "evidence", "synthesis", "sources")
            recommendation = "Use /fabric research for local research synthesis with the Fabric CLI."
        }
        [pscustomobject]@{
            rule_id        = "fabric_report_pattern"
            intent         = "fabric_report_pattern"
            task_type      = "fabric_report_pattern"
            command        = "/fabric report"
            priority       = 74
            exact_phrases  = @("fabric report", "run fabric report", "report with fabric", "fabric report pattern")
            keywords       = @("fabric", "report", "summary", "brief", "reporting")
            recommendation = "Use /fabric report for local report-style Fabric runs."
        }
        [pscustomobject]@{
            rule_id        = "fabric_review_pattern"
            intent         = "fabric_review_pattern"
            task_type      = "fabric_review_pattern"
            command        = "/fabric review"
            priority       = 73
            exact_phrases  = @("fabric review", "run fabric review", "review with fabric", "fabric review pattern")
            keywords       = @("fabric", "review", "checklist", "audit", "verification")
            recommendation = "Use /fabric review for local review-checklist Fabric runs."
        }
        [pscustomobject]@{
            rule_id        = "fabric_security_pattern"
            intent         = "fabric_security_pattern"
            task_type      = "fabric_security_pattern"
            command        = "/fabric security"
            priority       = 72
            exact_phrases  = @("fabric security", "run fabric security", "security with fabric", "fabric security pattern")
            keywords       = @("fabric", "security", "triage", "risk", "local-only")
            recommendation = "Use /fabric security for local security-triage Fabric runs."
        }
        [pscustomobject]@{
            rule_id        = "fabric_pattern"
            intent         = "fabric_pattern"
            task_type      = "fabric_pattern"
            command        = "/fabric"
            priority       = 70
            exact_phrases  = @("fabric pattern", "fabric workflow", "run fabric", "fabric task")
            keywords       = @("fabric", "pattern", "local model", "model task")
            recommendation = "Use /fabric for governed Fabric pattern tasks."
        }
    )
}

function Resolve-PDACommandInterpretation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Ontology = Import-PDATaskOntology -Root $Root
    $NormalizedText = Normalize-PDACommandInterpreterText -Value $Text
    $NormalizedTokens = @($NormalizedText.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries))
    $Rules = @(Get-PDACommandInterpreterRules)
    $KnownCommands = @($Ontology.task_intents.command | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $Candidates = New-Object System.Collections.Generic.List[object]

    foreach ($Rule in $Rules) {
        $OntologyMatch = @(Find-PDATaskTypes -Root $Root -Intent $Rule.intent | Select-Object -First 1)[0]
        if (-not $OntologyMatch) {
            continue
        }

        $Score = 0
        $Reasons = New-Object System.Collections.Generic.List[string]

        $CommandToken = Normalize-PDACommandInterpreterText -Value $Rule.command
        if ($NormalizedText.Contains($CommandToken)) {
            $Score += 1000
            $Reasons.Add("Direct ontology command token matched.")
        }

        foreach ($Phrase in @($Rule.exact_phrases)) {
            $PhraseNormalized = Normalize-PDACommandInterpreterText -Value $Phrase
            if ($PhraseNormalized -and $NormalizedText.Contains($PhraseNormalized)) {
                $Score += 180
                $Reasons.Add("Matched exact phrase: $Phrase")
            }
        }

        foreach ($Keyword in @($Rule.keywords)) {
            $KeywordNormalized = Normalize-PDACommandInterpreterText -Value $Keyword
            if ($KeywordNormalized) {
                if ($KeywordNormalized.Contains(' ')) {
                    if ($NormalizedText.Contains($KeywordNormalized)) {
                        $Score += 25
                        $Reasons.Add("Matched keyword: $Keyword")
                    }
                }
                elseif ($NormalizedTokens -contains $KeywordNormalized) {
                    $Score += 25
                    $Reasons.Add("Matched keyword: $Keyword")
                }
            }
        }

        if ($NormalizedText.Contains("executive summary") -and $Rule.intent -eq "report_generation") {
            $Score += 50
            $Reasons.Add("Executive summary phrasing matched report generation.")
        }

        if ($NormalizedText.Contains("latest findings") -and $Rule.intent -eq "review") {
            $Score += 50
            $Reasons.Add("Latest findings phrasing matched review.")
        }

        if ($Score -le 0) {
            continue
        }

        $Candidates.Add([pscustomobject]@{
            rule_id           = $Rule.rule_id
            intent            = $Rule.intent
            task_type         = [string]$OntologyMatch.task_type
            command           = [string]$OntologyMatch.command
            score             = $Score
            priority          = [int]$Rule.priority
            recommendation    = $Rule.recommendation
            reasons           = @($Reasons)
            ontology_verified = $true
        })
    }

    $SortedCandidates = @(
        $Candidates | Sort-Object `
            @{ Expression = { $_.score }; Descending = $true }, `
            @{ Expression = { $_.priority }; Descending = $true }, `
            @{ Expression = { $_.command }; Descending = $false }
    )

    $Recommendations = @()
    $Status = "unknown"
    $Intent = ""
    $TaskType = ""
    $Command = ""
    $Confidence = 0.0
    $OntologyVerified = $false
    $Reason = "No governed command matched."

    if ($SortedCandidates.Count -gt 0) {
        $Top = $SortedCandidates[0]
        $Second = if ($SortedCandidates.Count -gt 1) { $SortedCandidates[1] } else { $null }
        $AmbiguousWindow = 25
        $ConjunctionSignal = $NormalizedText -match '\b(and|or|plus)\b'
        $ExactCommandInput = $KnownCommands -contains $NormalizedText
        $Tie = $null -ne $Second -and (
            (($Top.score - $Second.score) -le $AmbiguousWindow) -or
            ($ConjunctionSignal -and $SortedCandidates.Count -gt 1)
        )

        if ($Tie -and $ExactCommandInput -and ([string]$Top.command -eq $NormalizedText)) {
            $Tie = $false
            $Reason = "Exact command match resolved deterministically to the canonical workflow."
        }

        $Recommendations = @($SortedCandidates | Select-Object -First 3 | ForEach-Object {
            [pscustomobject]@{
                intent         = $_.intent
                task_type      = $_.task_type
                command        = $_.command
                score          = $_.score
                recommendation = $_.recommendation
            }
        })

        if ($Tie) {
            $Status = "ambiguous"
            $Reason = "Multiple governed commands matched with equal confidence."
        }
        else {
            $Status = "mapped"
            $Intent = $Top.intent
            $TaskType = $Top.task_type
            $Command = $Top.command
            $Confidence = [math]::Min(1.0, [math]::Round(($Top.score / 1000.0), 2))
            $OntologyVerified = $true
            $Reason = $Top.recommendation
        }
    }

    if ($Status -eq "unknown") {
        $Recommendations = @(
            [pscustomobject]@{
                intent         = "clarify_request"
                task_type      = "clarify_request"
                command        = ""
                score          = 0
                recommendation = "No governed command matched. Rephrase using review, report, analyze, run, or research language."
            }
        )
        $Reason = $Recommendations[0].recommendation
    }

    return [pscustomobject]@{
        input_text             = $Text
        normalized_text        = $NormalizedText
        status                 = $Status
        intent                 = $Intent
        task_type              = $TaskType
        command                = $Command
        confidence             = $Confidence
        ontology_verified      = $OntologyVerified
        source_of_truth        = "Scripts/PDA_TaskOntology.json"
        ontology_command_count = $KnownCommands.Count
        candidate_count        = $SortedCandidates.Count
        recommendations        = @($Recommendations)
        matched_rules          = @($SortedCandidates | Select-Object -ExpandProperty rule_id)
        reason                 = $Reason
        ontology_version       = [string]$Ontology.ontology_version
    }
}

$Result = Resolve-PDACommandInterpretation -Text $Text -Root $Root

$CapabilityMatrixSummary = [pscustomobject]@{
    status            = "skipped"
    matrix_path       = ""
    route_count       = 0
    local_only_count  = 0
    cloud_allowed_count = 0
}
if (Get-Command -Name Get-PDACapabilityMatrix -ErrorAction SilentlyContinue) {
    try {
        $CapabilityMatrix = Get-PDACapabilityMatrix -Root $Root
        $CapabilityMatrixSummary = [pscustomobject]@{
            status            = [string]$CapabilityMatrix.status
            matrix_path       = [string]$CapabilityMatrix.matrix_path
            route_count       = [int]$CapabilityMatrix.route_count
            local_only_count  = [int]$CapabilityMatrix.local_only_count
            cloud_allowed_count = [int]$CapabilityMatrix.cloud_allowed_count
        }
    }
    catch {
        $CapabilityMatrixSummary = [pscustomobject]@{
            status            = "error"
            matrix_path       = [string]$CapabilityRouterScript
            route_count       = 0
            local_only_count  = 0
            cloud_allowed_count = 0
            error             = $_.Exception.Message
        }
    }
}

$Result | Add-Member -NotePropertyName capability_matrix -NotePropertyValue $CapabilityMatrixSummary -Force

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] PDA command interpreter result:"
Write-Host ("Status            : {0}" -f $Result.status)
Write-Host ("Intent            : {0}" -f $(if ($Result.intent) { $Result.intent } else { "(none)" }))
Write-Host ("Task type         : {0}" -f $(if ($Result.task_type) { $Result.task_type } else { "(none)" }))
Write-Host ("Command           : {0}" -f $(if ($Result.command) { $Result.command } else { "(none)" }))
Write-Host ("Confidence        : {0}" -f $Result.confidence)
Write-Host ("Ontology verified : {0}" -f $Result.ontology_verified)
Write-Host ("Reason            : {0}" -f $Result.reason)

if ($Result.recommendations.Count -gt 0) {
    Write-Host ""
    Write-Host "Recommendations:"
    $Result.recommendations |
        Select-Object intent, task_type, command, score, recommendation |
        Format-Table -AutoSize
}
