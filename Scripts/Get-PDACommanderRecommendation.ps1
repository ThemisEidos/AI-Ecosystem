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
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$InterpreterScript = Join-Path $PSScriptRoot "PDA_CommandInterpreter.ps1"
$CapabilityRouterScript = Join-Path $PSScriptRoot "PDA_CapabilityRouter.ps1"
$ExecutorRegistryScript = Join-Path $PSScriptRoot "PDA_ExecutorRegistry.ps1"
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot "PDA_OutputParsing.ps1") -PathType Leaf) {
    . (Join-Path $PSScriptRoot "PDA_OutputParsing.ps1")
}
if (Test-Path -LiteralPath $CapabilityRouterScript -PathType Leaf) {
    . $CapabilityRouterScript
}
if (Test-Path -LiteralPath $ExecutorRegistryScript -PathType Leaf) {
    . $ExecutorRegistryScript
}

function Invoke-PDACommanderInterpreterJson {
    param([Parameter(Mandatory = $true)][string]$Value)

    if (-not (Test-Path -LiteralPath $InterpreterScript -PathType Leaf)) {
        return $null
    }

    try {
        $Raw = & pwsh -NoProfile -File $InterpreterScript -Text $Value -AsJson 2>&1
        $TextOutput = [string]($Raw -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($TextOutput)) {
            return $null
        }

        return ConvertFrom-PDAMixedJson -Text $TextOutput -SourceName $InterpreterScript
    }
    catch {
        return $null
    }
}

function Get-PDACommanderGuidanceClassification {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $Normalized = [string]$Value
    if ([string]::IsNullOrWhiteSpace($Normalized)) {
        return "unknown"
    }

    $Normalized = $Normalized.ToLowerInvariant()
    if ($Normalized -match '(?i)\b(what should i work on next|what should i do next|give me my pda briefing|give me a pda briefing|what is blocked|what needs attention|what changed recently|what needs review|what should i delegate|what changed since last time)\b') {
        return "operator_guidance"
    }

    if ($Normalized -match '(?i)\b(filesystem|file system|repository|repositories|docker|container|containers|service inventory|service status|tool inventory|workspace inventory|environment awareness|environment inventory|file structure|organize folders|storage locations|scan c:\\|scan ~/|scan my filesystem|show my repositories|what ai services are running|help organize my folders|recommend a better project structure)\b') {
        return "environment_awareness"
    }

    return "request"
}

function Resolve-PDACommanderTaskType {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [string]$TaskType
    )

    if (-not [string]::IsNullOrWhiteSpace($TaskType)) {
        return (Normalize-PDACapabilityTaskType -Value $TaskType)
    }

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    if ($Text -match '(?i)\b(roadmap|road map|planner|planning|build me a roadmap|make me a roadmap)\b') {
        return "planning"
    }

    if ($Text -match '(?i)\b(filesystem|file system|repository|repositories|docker|container|containers|service inventory|service status|tool inventory|workspace inventory|environment awareness|environment inventory|file structure|organize folders|storage locations|scan c:\\|scan ~/|scan my filesystem|show my repositories|what ai services are running|help organize my folders|recommend a better project structure)\b') {
        return "environment_awareness"
    }

    if (-not [string]::IsNullOrWhiteSpace($Text)) {
        $Interpreter = Invoke-PDACommanderInterpreterJson -Value $Text
        if ($Interpreter -and [string]$Interpreter.status -eq "mapped") {
            $NormalizedInterpreterTask = Normalize-PDACapabilityTaskType -Value $Interpreter.task_type
            switch ($NormalizedInterpreterTask) {
                "operator_status" { return "administrative" }
                "operator_tasks" { return "administrative" }
                "operator_approvals" { return "administrative" }
                "operator_workers" { return "administrative" }
                "operator_reports" { return "administrative" }
                "operator_memory" { return "knowledge_management" }
                "operator_help" { return "operator_guidance" }
                default { return $NormalizedInterpreterTask }
            }
        }
    }

    $Normalized = $Text.ToLowerInvariant()
    switch -Regex ($Normalized) {
        '(?i)\b(codex task|implementation task|development task|engineering task|project task|action item|work item|task generator|task file)\b' { return "task_generation" }
        '(?i)\b(create|generate|draft|write|make)\b.*\b(task|action item|work item)\b' { return "task_generation" }
        '(?i)\b(turn this into|convert this into|transform this into)\b.*\b(task|action item|work item)\b' { return "task_generation" }
        '(?i)\b(research|investigate|evidence|sources|synthesis|study)\b' { return "research" }
        '(?i)\b(report|summary|summarize|briefing|brief)\b' { return "reporting" }
        '(?i)\b(review|audit|critique|evaluate|findings)\b' { return "review" }
        '(?i)\b(execute|run|dispatch|workflow|launch)\b' { return "coding" }
        '(?i)\b(automate|automation|workflow)\b' { return "automation" }
        '(?i)\b(notebooklm|learning|knowledge|notes|memory)\b' { return "knowledge_management" }
        '(?i)\b(infrastructure|ops|operate|status|worker|queue|approval)\b' { return "administrative" }
        '(?i)\b(briefing|guide|next step|what should i work on next|what should i do next|what is blocked|what needs attention|what changed recently)\b' { return "operator_guidance" }
        default { return "unknown" }
    }
}

function Get-PDACommanderExecutorFallback {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Classification
    )

    switch ($Classification) {
        "research" { return [pscustomobject]@{ selected_tool = "gemini-cli"; backup_tool = "research-worker"; reason = "Research is best handled by a research-capable executor when Category 1 allows it." } }
        "reporting" { return [pscustomobject]@{ selected_tool = "reporter-worker"; backup_tool = "planner-worker"; reason = "Report synthesis is deterministic and fits the local reporter pipeline." } }
        "review" { return [pscustomobject]@{ selected_tool = "review-worker"; backup_tool = "reporter-worker"; reason = "Review and checklist work are best handled by the local review pipeline." } }
        "coding" { return [pscustomobject]@{ selected_tool = "codex"; backup_tool = "execute-worker"; reason = "Repository or script modification should use the local Codex execution path." } }
        "task_generation" { return [pscustomobject]@{ selected_tool = "codex"; backup_tool = "execute-worker"; reason = "Codex task generation should use the local Codex workflow path." } }
        "automation" { return [pscustomobject]@{ selected_tool = "n8n"; backup_tool = "execute-worker"; reason = "Deterministic automation should prefer n8n workflow orchestration." } }
        "knowledge_management" { return [pscustomobject]@{ selected_tool = "notebooklm"; backup_tool = "operator-console-worker"; reason = "Sanitized learning material belongs in NotebookLM before durable memory promotion." } }
        "administrative" { return [pscustomobject]@{ selected_tool = "operator-console-worker"; backup_tool = "human operator"; reason = "Administrative queue triage and approvals stay human-governed." } }
        "planning" { return [pscustomobject]@{ selected_tool = "planner-worker"; backup_tool = "operator-console-worker"; reason = "Planning is best handled by the local planner pipeline." } }
        "environment_awareness" { return [pscustomobject]@{ selected_tool = "planner-worker"; backup_tool = "operator-console-worker"; reason = "Environment analysis and file-structure planning should stay governed through the planner pipeline." } }
        "security_triage" { return [pscustomobject]@{ selected_tool = "review-worker"; backup_tool = "reporter-worker"; reason = "Security triage benefits from a deterministic local review pipeline." } }
        default { return [pscustomobject]@{ selected_tool = "operator-console-worker"; backup_tool = "human operator"; reason = "No stronger executor match was found; request human review." } }
    }
}

function Get-PDACommanderRecommendation {
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

    $TaskClassification = Resolve-PDACommanderTaskType -Text $Text -TaskType $TaskType
    $GuidanceClassification = if (-not [string]::IsNullOrWhiteSpace([string]$Text)) {
        Get-PDACommanderGuidanceClassification -Value $Text
    }
    else {
        "unknown"
    }

    $RecommendedCommand = ""
    $CapabilityRoute = $null
    $SelectedTool = ""
    $BackupTool = ""
    $RoutingReason = ""
    $BlockedReason = ""
    $Allowed = $true
    $Confidence = 0.5
    $ExecutorRecommendation = $null

    if ($GuidanceClassification -eq "operator_guidance") {
        $Fallback = Get-PDACommanderExecutorFallback -Classification "administrative"
        $SelectedTool = [string]$Fallback.selected_tool
        $BackupTool = [string]$Fallback.backup_tool
        $RoutingReason = [string]$Fallback.reason
        $BlockedReason = ""
        $TaskClassification = "operator_guidance"
        $Confidence = 0.95
    }
    else {
        if (-not [string]::IsNullOrWhiteSpace($Text)) {
            $Interpreter = Invoke-PDACommanderInterpreterJson -Value $Text
            if ($Interpreter -and [string]$Interpreter.status -eq "mapped") {
                $RecommendedCommand = [string]$Interpreter.command
                if ([string]::IsNullOrWhiteSpace($TaskType)) {
                    $TaskClassification = Normalize-PDACapabilityTaskType -Value $Interpreter.task_type
                }
                $Confidence = [double]$Interpreter.confidence
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($TaskClassification) -and (Get-Command -Name Get-PDAToolForTask -ErrorAction SilentlyContinue)) {
            try {
                $CapabilityRoute = Get-PDAToolForTask -TaskType $TaskClassification -Category $Category -PreferredOutput $PreferredOutput -RequiresLocalOnly:$RequiresLocalOnly -Root $Root
            }
            catch {
                $CapabilityRoute = [pscustomobject]@{
                    selected_tool       = ""
                    backup_tool         = ""
                    routing_reason      = $_.Exception.Message
                    allowed             = $false
                    blocked_reason      = $_.Exception.Message
                    output_location     = @()
                    task_type           = $TaskClassification
                    category            = $Category
                    preferred_output    = $PreferredOutput
                    requires_local_only = [bool]$RequiresLocalOnly
                    cloud_allowed       = $false
                    matrix_status       = "error"
                    matrix_path         = ""
                    route_count         = 0
                    matrix_loaded       = $false
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($TaskClassification) -and (Get-Command -Name Get-PDAExecutorRecommendation -ErrorAction SilentlyContinue)) {
            try {
                $ExecutorRecommendation = Get-PDAExecutorRecommendation -TaskType $TaskClassification -Category $Category -PreferredOutput $PreferredOutput -RequiresLocalOnly:$RequiresLocalOnly -Text $Text -Root $Root
            }
            catch {
                $ExecutorRecommendation = $null
            }
        }

        if ($ExecutorRecommendation) {
            $SelectedTool = [string]$ExecutorRecommendation.recommended_executor
            $BackupTool = [string]$ExecutorRecommendation.backup_executor
            $RoutingReason = [string]$ExecutorRecommendation.routing_reason
            $Allowed = [bool]$ExecutorRecommendation.allowed
            $BlockedReason = [string]$ExecutorRecommendation.blocked_reason
            if ([string]::IsNullOrWhiteSpace($SelectedTool) -and $CapabilityRoute) {
                $SelectedTool = [string]$CapabilityRoute.selected_tool
            }
            if ([string]::IsNullOrWhiteSpace($BackupTool) -and $CapabilityRoute) {
                $BackupTool = [string]$CapabilityRoute.backup_tool
            }
        }
        else {
            if ($CapabilityRoute -and [bool]$CapabilityRoute.allowed) {
                $SelectedTool = [string]$CapabilityRoute.selected_tool
                $BackupTool = [string]$CapabilityRoute.backup_tool
                $RoutingReason = [string]$CapabilityRoute.routing_reason
                $Allowed = [bool]$CapabilityRoute.allowed
                $BlockedReason = [string]$CapabilityRoute.blocked_reason
            }
            else {
                $Fallback = Get-PDACommanderExecutorFallback -Classification $TaskClassification
                $SelectedTool = [string]$Fallback.selected_tool
                $BackupTool = [string]$Fallback.backup_tool
                $RoutingReason = if ($CapabilityRoute) { [string]$CapabilityRoute.routing_reason } else { [string]$Fallback.reason }
                $Allowed = if ($CapabilityRoute) { [bool]$CapabilityRoute.allowed } else { $true }
                $BlockedReason = if ($CapabilityRoute) { [string]$CapabilityRoute.blocked_reason } else { "" }
            }
            if ([string]::IsNullOrWhiteSpace($SelectedTool)) {
                $SelectedTool = if ($ExecutorRecommendation) { [string]$ExecutorRecommendation.recommended_executor } else { [string]$Fallback.selected_tool }
            }
            if ([string]::IsNullOrWhiteSpace($BackupTool)) {
                $BackupTool = if ($ExecutorRecommendation) { [string]$ExecutorRecommendation.backup_executor } else { [string]$Fallback.backup_tool }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($SelectedTool)) {
        $Allowed = $false
        $BlockedReason = "No executor could be recommended."
        $SelectedTool = "Human operator"
        $BackupTool = "PowerShell"
    }

    $RecommendedCommand = if ([string]::IsNullOrWhiteSpace($RecommendedCommand) -and $CapabilityRoute -and $CapabilityRoute.route_alias) { [string]$CapabilityRoute.route_alias } else { $RecommendedCommand }

    $Result = [pscustomobject]@{
        status               = if ($Allowed) { "pass" } else { "warning" }
        input_text           = [string]$Text
        classification       = [string]$TaskClassification
        task_type            = [string]$TaskClassification
        category             = [string]$Category
        preferred_output     = [string]$PreferredOutput
        requires_local_only  = [bool]$RequiresLocalOnly
        recommended_command  = [string]$RecommendedCommand
        recommended_executor = [string]$SelectedTool
        selected_tool        = [string]$SelectedTool
        backup_executor      = [string]$BackupTool
        backup_tool          = [string]$BackupTool
        routing_reason       = [string]$RoutingReason
        blocked_reason       = [string]$BlockedReason
        allowed              = [bool]$Allowed
        confidence           = [double]$Confidence
        approval_required    = if ($ExecutorRecommendation) { [bool]$ExecutorRecommendation.approval_required } else { $false }
        executor_type        = if ($ExecutorRecommendation) { [string]$ExecutorRecommendation.executor_type } else { "" }
        executor_risk_level  = if ($ExecutorRecommendation) { [string]$ExecutorRecommendation.risk_level } else { "" }
        capability_route     = $CapabilityRoute
        executor_recommendation = $ExecutorRecommendation
        source_of_truth      = "Scripts/PDA_CapabilityMatrix.json"
        matrix_status        = if ($CapabilityRoute) { [string]$CapabilityRoute.matrix_status } else { "unknown" }
        matrix_path          = if ($CapabilityRoute) { [string]$CapabilityRoute.matrix_path } else { (Join-Path $Root "Scripts\PDA_CapabilityMatrix.json") }
        output_location      = if ($CapabilityRoute) { @($CapabilityRoute.output_location) } else { @() }
        dispatch_ready       = $false
        dispatch_status      = if ($ExecutorRecommendation) { [string]$ExecutorRecommendation.dispatch_status } else { "not_applicable" }
        guidance_classification = [string]$GuidanceClassification
    }

    return $Result
}

if ($PSBoundParameters.ContainsKey("Text") -or $PSBoundParameters.ContainsKey("TaskType") -or $AsJson) {
    $Result = Get-PDACommanderRecommendation -Text $Text -TaskType $TaskType -Category $Category -PreferredOutput $PreferredOutput -RequiresLocalOnly:$RequiresLocalOnly -Root $Root

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        return
    }

    Write-Host "[PDA COMMANDER RECOMMENDATION]"
    Write-Host ("Classification   : {0}" -f $Result.classification)
    Write-Host ("Recommended tool : {0}" -f $Result.recommended_executor)
    Write-Host ("Backup tool      : {0}" -f $Result.backup_tool)
    Write-Host ("Reason           : {0}" -f $Result.routing_reason)

    $Result
}
