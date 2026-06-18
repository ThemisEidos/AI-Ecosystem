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
$StatusBridgeScript = Join-Path $PSScriptRoot "Invoke-COOPERStatusCommand.ps1"
$EnvironmentHelperScript = Join-Path $PSScriptRoot "PDA_Environment.ps1"
$ExecutorRegistryScript = Join-Path $PSScriptRoot "PDA_ExecutorRegistry.ps1"
$WorkflowDefinitionsScript = Join-Path $PSScriptRoot "Get-COOPERWorkflowDefinitions.ps1"
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
if (Test-Path -LiteralPath $WorkflowDefinitionsScript -PathType Leaf) {
    . $WorkflowDefinitionsScript
}
. (Join-Path $PSScriptRoot "COOPER_PersonalityEngine.ps1")

function Normalize-PDAConversationalText {
    param([Parameter(Mandatory = $true)][string]$Value)

    $Normalized = [string]$Value
    $Normalized = $Normalized.ToLowerInvariant()
    $Normalized = $Normalized -replace '[^a-z0-9/\s]+', ' '
    $Normalized = $Normalized -replace '\s+', ' '
    return $Normalized.Trim()
}

function Get-COOPERWorkflowDefinitionById {
    param([Parameter(Mandatory = $true)][string]$WorkflowId)

    if (-not (Get-Command -Name Get-COOPERWorkflowDefinitions -ErrorAction SilentlyContinue)) {
        return $null
    }

    try {
        return @(Get-COOPERWorkflowDefinitions -Root $Root) | Where-Object { [string]$_.id -eq $WorkflowId } | Select-Object -First 1
    }
    catch {
        return $null
    }
}

function Test-PDAWorkflowDefinitionKeywordMatch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NormalizedText,

        [Parameter(Mandatory = $true)]
        [string[]]$Keywords
    )

    foreach ($Keyword in $Keywords) {
        $Candidate = [string]$Keyword
        if ([string]::IsNullOrWhiteSpace($Candidate)) {
            continue
        }

        if ($NormalizedText.Contains($Candidate.Trim().ToLowerInvariant())) {
            return $true
        }
    }

    return $false
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

function Get-COOPERDefaultModelName {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Configured = [string]$env:COOPER_DEFAULT_MODEL
    if (-not [string]::IsNullOrWhiteSpace($Configured)) {
        return $Configured.Trim()
    }

    if (Get-Command -Name Get-COOPERIdentity -ErrorAction SilentlyContinue) {
        try {
            $Identity = Get-COOPERIdentity -Root $Root
            if ($Identity -and $Identity.PSObject.Properties.Name -contains "default_model" -and -not [string]::IsNullOrWhiteSpace([string]$Identity.default_model)) {
                return [string]$Identity.default_model
            }
        }
        catch {}
    }

    return "qwen2.5:7b"
}

function Get-COOPERDefaultModelCandidates {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Candidates = @(
        (Get-COOPERDefaultModelName -Root $Root)
        "mistral"
        "local-llama"
    )

    $UniqueCandidates = New-Object System.Collections.Generic.List[string]
    foreach ($Candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace([string]$Candidate)) {
            continue
        }

        $Normalized = [string]$Candidate
        if ($UniqueCandidates -notcontains $Normalized) {
            $UniqueCandidates.Add($Normalized)
        }
    }

    return @($UniqueCandidates)
}

function Test-COOPERLightweightStatusMode {
    $Value = [string]$env:COOPER_LIGHTWEIGHT_STATUS
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return [bool]($Value -notmatch '^(0|false|no)$')
}

if (-not (Get-Command -Name Invoke-COOPERDefaultModelChat -ErrorAction SilentlyContinue)) {
function Invoke-COOPERDefaultModelChat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [string]$ResponseStyle = ""
    )

    $ModelScript = Join-Path $PSScriptRoot "Invoke-PDAModel.ps1"
    $DefaultModelCandidates = Get-COOPERDefaultModelCandidates -Root $Root
    $DefaultModel = if ($DefaultModelCandidates.Count -gt 0) { [string]$DefaultModelCandidates[0] } else { "qwen2.5:7b" }
    $FallbackHelp = "Status, reports, research, planning, execution. Pick a target."
    $Result = [ordered]@{
        status = "fail"
        default_model = $DefaultModel
        selected_model = $DefaultModel
        model_status = "fail"
        model_error_message = ""
        routing_reason = ""
        response_text = ""
        next_action = "Ask for help with the command list."
        bridge_mode = "model_fallback"
        handoff_status = "fallback"
        source_of_truth = "Scripts/Invoke-PDAModel.ps1"
        model_result = $null
        model_routing = $null
    }

    if (-not (Test-Path -LiteralPath $ModelScript -PathType Leaf)) {
        $Result.model_error_message = "Model invocation adapter missing: $ModelScript"
        $Result.response_text = "COOPER default model '$DefaultModel' is unavailable. $($Result.model_error_message) $FallbackHelp"
        return [pscustomobject]$Result
    }

    try {
        $AttemptErrors = New-Object System.Collections.Generic.List[string]
        $PromptText = [string]$Text
        if ([string]::IsNullOrWhiteSpace($PromptText)) {
            $PromptText = ""
        }
        if (-not [string]::IsNullOrWhiteSpace($ResponseStyle)) {
            $PromptText = "{0}`n`n{1}" -f $ResponseStyle.Trim(), $PromptText
        }
        foreach ($Candidate in $DefaultModelCandidates) {
            $Result.selected_model = [string]$Candidate
            $Raw = & pwsh -NoProfile -File $ModelScript -WorkerName "cooper-chat" -TaskType "conversational" -Category "category_1" -Sensitivity "standard" -Prompt $PromptText -SelectedModelOverride ([string]$Candidate) -AsJson -NoThrow 2>&1
            $JsonText = [string]($Raw -join "`n").Trim()
            if ([string]::IsNullOrWhiteSpace($JsonText)) {
                $AttemptErrors.Add("COOPER default model '$Candidate' returned empty output.")
                continue
            }

            $ModelResult = ConvertFrom-PDAMixedJson -Text $JsonText -SourceName "COOPER default model"
            if (-not $ModelResult) {
                $Result.raw_output = $JsonText
                $AttemptErrors.Add("COOPER default model '$Candidate' returned unparseable output.")
                continue
            }

            $Result.model_result = $ModelResult
            if ($ModelResult.PSObject.Properties.Name -contains "routing") {
                $Result.model_routing = $ModelResult.routing
                if ($ModelResult.routing -and $ModelResult.routing.PSObject.Properties.Name -contains "selected_model" -and -not [string]::IsNullOrWhiteSpace([string]$ModelResult.routing.selected_model)) {
                    $Result.selected_model = [string]$ModelResult.routing.selected_model
                }
                if ($ModelResult.routing -and $ModelResult.routing.PSObject.Properties.Name -contains "routing_reason" -and -not [string]::IsNullOrWhiteSpace([string]$ModelResult.routing.routing_reason)) {
                    $Result.routing_reason = [string]$ModelResult.routing.routing_reason
                }
            }

            $Result.model_status = if ($ModelResult.PSObject.Properties.Name -contains "status") { [string]$ModelResult.status } else { "unknown" }
            $ModelResponseText = if ($ModelResult.PSObject.Properties.Name -contains "response_text") { [string]$ModelResult.response_text } else { "" }
            $ModelNextAction = if ($ModelResult.PSObject.Properties.Name -contains "next_action") { [string]$ModelResult.next_action } else { "" }
            $Result.model_error_message = if ($ModelResult.PSObject.Properties.Name -contains "error_message") { [string]$ModelResult.error_message } else { "" }

            if ($Result.model_status -eq "pass" -and -not [string]::IsNullOrWhiteSpace($ModelResponseText)) {
                $Result.status = "pass"
                $Result.response_text = $ModelResponseText
                $Result.next_action = if (-not [string]::IsNullOrWhiteSpace($ModelNextAction) -and $ModelNextAction -notmatch '(?i)continue the conversation') { $ModelNextAction } else { "" }
                $Result.bridge_mode = "model_chat"
                $Result.handoff_status = "fallback"
                $Result.model_error_message = ""
                return [pscustomobject]$Result
            }

            if (-not [string]::IsNullOrWhiteSpace($Result.model_error_message)) {
                $AttemptErrors.Add($Result.model_error_message)
            }
            else {
                $AttemptErrors.Add("COOPER default model '$Candidate' did not return a usable response.")
            }
        }

        $Result.model_error_message = if ($AttemptErrors.Count -gt 0) { [string]($AttemptErrors -join " ") } else { "COOPER default model '$DefaultModel' did not return a usable response." }
        $Result.response_text = "COOPER default models are unavailable. $($Result.model_error_message) $FallbackHelp"
        $Result.next_action = "Restore a local model or ask for help with the command list."
        $Result.bridge_mode = "model_fallback"
        $Result.handoff_status = "fallback"
        return [pscustomobject]$Result
    }
    catch {
        $Result.model_error_message = $_.Exception.Message
        $Result.response_text = "COOPER default models are unavailable. $($Result.model_error_message) $FallbackHelp"
        $Result.next_action = "Restore a local model or ask for help with the command list."
        return [pscustomobject]$Result
    }
}
}

function Test-PDAConversationalSlashCommand {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool]($NormalizedText.StartsWith("/"))
}

function Test-PDAConversationalDirectHelp {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(what do you do|help|what commands|available commands|show me help|show the command list)\b'
    )
}

function Test-PDAConversationalDirectStatus {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(status report|operational status|show operational status|show workflow status|workflow status|health report|morning briefing|daily briefing|what''?s the status|what is the status|how are things going|how are you doing|how is the pda doing|how is the ecosystem|summarize the ecosystem status|summarise the ecosystem status|show me the current status|current status|system status|how are things|pda status|how is everything|status|what workshop am i in|what mode am i in|which workshop am i in|which mode am i in|what can you do|what can you do right now|what workflows are available|what workflows are operational|what workflow(s)? are operational|what capabilities do you have|what phase are we in|what is operational|what is working right now)\b'
    )
}

function Test-PDAConversationalToolInventory {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(what tools are available|what tools do i have|what tools can cooper use|list available tools|show available tools|tool inventory|toolbox inventory|approved tools|approved tool inventory)\b'
    )
}

function Test-PDAConversationalWorkflowCatalog {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(list available workflows|workflow catalog|workflow list|show workflows|show available workflows)\b'
    )
}

function Test-PDAConversationalResearchSummary {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    if ($NormalizedText.StartsWith("/")) {
        return $false
    }

    if ($NormalizedText -match '(?i)\bstatus\b') {
        return $false
    }

    $Definition = Get-COOPERWorkflowDefinitionById -WorkflowId "WF-001"
    $ResearchKeywords = if ($Definition -and $Definition.PSObject.Properties.Name -contains "intent_keywords") {
        @($Definition.intent_keywords)
    }
    else {
        @("research", "search", "study", "documentation", "docs", "official")
    }
    $SummaryKeywords = @("summary", "summarize", "summarise", "structured summary", "summary note", "research summary", "findings", "brief", "briefing")

    return [bool](
        (
            (Test-PDAWorkflowDefinitionKeywordMatch -NormalizedText $NormalizedText -Keywords $ResearchKeywords) -and
            (Test-PDAWorkflowDefinitionKeywordMatch -NormalizedText $NormalizedText -Keywords $SummaryKeywords)
        ) -or
        (
            $NormalizedText -match '(?i)\b(pop!_?os|pop os|linux & infrastructure|linux and infrastructure)\b' -and
            $NormalizedText -match '(?i)\b(research|documentation|official|summary|summarize|summarise|summary note|structured summary|findings|brief|briefing)\b'
        )
    )
}

function Test-PDAConversationalNoteCreation {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    $Definition = Get-COOPERWorkflowDefinitionById -WorkflowId "WF-005"
    $NoteKeywords = if ($Definition -and $Definition.PSObject.Properties.Name -contains "intent_keywords") {
        @($Definition.intent_keywords)
    }
    else {
        @("create note", "write note", "save note", "obsidian note", "note creation")
    }

    $ContainsNoteIntent = (
        (Test-PDAWorkflowDefinitionKeywordMatch -NormalizedText $NormalizedText -Keywords $NoteKeywords) -or
        ($NormalizedText -match '(?i)\b(create|write|draft|make|capture)\b.*\b(note|markdown note|obsidian note)\b')
    )
    $LooksLikeResearch = Test-PDAConversationalResearchSummary -NormalizedText $NormalizedText

    return [bool]($ContainsNoteIntent -and -not $LooksLikeResearch)
}

function Test-PDAConversationalCodexTaskGenerator {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    if ($NormalizedText.StartsWith("/")) {
        return $false
    }

    $Definition = Get-COOPERWorkflowDefinitionById -WorkflowId "WF-002"
    $TaskKeywords = if ($Definition -and $Definition.PSObject.Properties.Name -contains "intent_keywords") {
        @($Definition.intent_keywords)
    }
    else {
        @("codex task", "implementation task", "development task", "engineering task", "create task", "task generator", "task file")
    }

    return [bool](
        (
            (Test-PDAWorkflowDefinitionKeywordMatch -NormalizedText $NormalizedText -Keywords $TaskKeywords) -or
            ($NormalizedText -match '(?i)\b(turn this|transform this|convert this|make this|draft this|create a task from this|write a task from this|generate a task from this)\b') -or
            ($NormalizedText -match '(?i)\b(project decision|project discussion|issue|finding|roadmap item|workflow output|research summary|workflow review)\b' -and $NormalizedText -match '(?i)\b(task|codex task|implementation task|development task|engineering task)\b')
        ) -and
        ($NormalizedText -match '(?i)\b(task|codex task|implementation task|development task|engineering task|task file)\b')
    )
}

function Test-PDAConversationalKnowledgeCollectionImport {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(prepare for collection|knowledge collection|import draft|prepare for knowledge base|add to collection|collection import)\b'
    )
}

function Test-PDAConversationalResearchCollectionCodexChain {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    $ResearchMatch = $NormalizedText -match '(?i)\b(research|search|source|sources|documentation|docs|official|find|findings)\b'
    $CollectionMatch = $NormalizedText -match '(?i)\b(collection|knowledge base|knowledge collection|linux collection|linux & infrastructure collection|linux and infrastructure collection)\b'
    $ImplementationMatch = $NormalizedText -match '(?i)\b(prepare implementation work|prepare work|implementation work|implementation task|implementation plan|work item|action item|collection draft|prepare the collection draft)\b'

    return [bool]($ResearchMatch -and $CollectionMatch -and $ImplementationMatch)
}

function Test-PDAConversationalWorkshopChangeRequest {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(switch to private workshop|switch to open workshop|change to private workshop|change to open workshop|move to private workshop|move to open workshop)\b'
    )
}

function Test-PDAConversationalRuntimeSelfAwareness {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    $Patterns = @(
        '\bwhat model are you(?: running| using)?\b',
        '\bwhat llm are you\b',
        '\bwhat provider are you\b',
        '\bwho is your provider\b',
        '\bwhat backend are you using\b',
        '\bwhat backend are you on\b',
        '\bwhat are you running on\b',
        '\bwhat version are you\b',
        '\bwho are you\b',
        '\bwho made you\b',
        '\bwhat is your model\b',
        "\bwhat's your model\b"
    )

    foreach ($Pattern in $Patterns) {
        if ($NormalizedText -match $Pattern) {
            return $true
        }
    }

    return $false
}

function Test-PDAConversationalPersonalityQuery {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(humor level|humour level|honesty level|discretion level|directness level|formality level|verbosity level|confidence level|risk tolerance|personality settings|personality profile|your settings|your personality|how humorous are you|how direct are you|how formal are you|how verbose are you|how confident are you|how discreet are you|what are your settings|what is my personality profile|show personality settings)\b'
    )
}

function Test-PDAConversationalPersonalityUpdate {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(set|update|adjust|change|propose|increase|decrease|lower|raise|boost|reduce)\b.*\b(humor|humour|honesty|discretion|directness|formality|verbosity|confidence|risk tolerance)\b' -or
        $NormalizedText -match '(?i)\b(lower|raise|increase|decrease|boost|reduce|turn up|turn down|dial up|dial down)\b.*\b(humor|humour|honesty|discretion|directness|formality|verbosity|confidence|risk tolerance)\b' -or
        $NormalizedText -match '(?i)\b(make yourself|be more|be less|sound more|sound less)\b.*\b(dry|terse|concise|direct|formal|honest|discreet|confident|sarcastic)\b'
    )
}

function Test-PDAConversationalPersonalityCancel {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(cancel personality change|cancel the personality change|cancel personality update|cancel the personality update|abort personality change|discard personality change|never mind the personality change)\b'
    )
}

function Get-COOPERPersonalitySettingDefinition {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    $Definitions = @(
        [pscustomobject]@{ key = "humor"; property = "humor_level"; label = "Humor"; aliases = @("humor", "humour") }
        [pscustomobject]@{ key = "honesty"; property = "honesty_level"; label = "Honesty"; aliases = @("honesty") }
        [pscustomobject]@{ key = "discretion"; property = "discretion_level"; label = "Discretion"; aliases = @("discretion") }
        [pscustomobject]@{ key = "directness"; property = "directness_level"; label = "Directness"; aliases = @("directness") }
        [pscustomobject]@{ key = "verbosity"; property = "verbosity_level"; label = "Verbosity"; aliases = @("verbosity") }
        [pscustomobject]@{ key = "confidence"; property = "confidence_level"; label = "Confidence"; aliases = @("confidence") }
        [pscustomobject]@{ key = "formality"; property = "formality_level"; label = "Formality"; aliases = @("formality") }
        [pscustomobject]@{ key = "risk_tolerance"; property = "risk_tolerance"; label = "Risk Tolerance"; aliases = @("risk tolerance", "risk_tolerance", "risk-tolerance") }
    )

    foreach ($Definition in $Definitions) {
        foreach ($Alias in @($Definition.aliases)) {
            if ($NormalizedText -match ('(?i)\b{0}\b' -f [regex]::Escape([string]$Alias))) {
                return $Definition
            }
        }
    }

    return $null
}

function Get-COOPERPersonalitySettingCurrentValue {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Personality,

        [Parameter(Mandatory = $false)]
        [object]$LegacyPersonality,

        [Parameter(Mandatory = $true)]
        [psobject]$Definition
    )

    function Get-FirstPropertyValue {
        param(
            [Parameter(Mandatory = $false)]
            [object]$Source,

            [Parameter(Mandatory = $true)]
            [string[]]$Names
        )

        if (-not $Source -or -not $Source.PSObject) {
            return $null
        }

        foreach ($Name in $Names) {
            if ($Source.PSObject.Properties.Name -contains $Name) {
                $Value = $Source.$Name
                if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)) {
                    return [int]$Value
                }
            }
        }

        return $null
    }

    switch ([string]$Definition.key) {
        "humor" {
            $Value = Get-FirstPropertyValue -Source $Personality -Names @("humor", "humor_level")
            if ($null -ne $Value) { return $Value }
            return (Get-FirstPropertyValue -Source $LegacyPersonality -Names @("humor", "humor_level"))
        }
        "honesty" {
            $Value = Get-FirstPropertyValue -Source $Personality -Names @("professionalism", "honesty", "honesty_level", "directness", "directness_level", "formality", "formality_level")
            if ($null -ne $Value) { return $Value }
            return (Get-FirstPropertyValue -Source $LegacyPersonality -Names @("professionalism", "honesty", "honesty_level", "directness", "directness_level", "formality", "formality_level"))
        }
        "discretion" {
            $Value = Get-FirstPropertyValue -Source $Personality -Names @("risk_awareness", "risk_tolerance", "discretion", "discretion_level")
            if ($null -ne $Value) { return $Value }
            return (Get-FirstPropertyValue -Source $LegacyPersonality -Names @("risk_awareness", "risk_tolerance", "discretion", "discretion_level"))
        }
        "directness" {
            $Value = Get-FirstPropertyValue -Source $Personality -Names @("professionalism", "directness", "directness_level")
            if ($null -ne $Value) { return $Value }
            return (Get-FirstPropertyValue -Source $LegacyPersonality -Names @("professionalism", "directness", "directness_level"))
        }
        "verbosity" {
            $Verbosity = Get-FirstPropertyValue -Source $Personality -Names @("verbosity", "verbosity_level")
            if ($null -ne $Verbosity) {
                return $Verbosity
            }

            $Verbosity = Get-FirstPropertyValue -Source $LegacyPersonality -Names @("verbosity", "verbosity_level")
            if ($null -ne $Verbosity) {
                return $Verbosity
            }

            $Brevity = Get-FirstPropertyValue -Source $Personality -Names @("brevity")
            if ($null -ne $Brevity) {
                return (100 - [int]$Brevity)
            }
            $Brevity = Get-FirstPropertyValue -Source $LegacyPersonality -Names @("brevity")
            if ($null -ne $Brevity) {
                return (100 - [int]$Brevity)
            }
            return $null
        }
        "confidence" {
            $Value = Get-FirstPropertyValue -Source $Personality -Names @("initiative", "confidence", "confidence_level", "autonomy", "persistence")
            if ($null -ne $Value) { return $Value }
            return (Get-FirstPropertyValue -Source $LegacyPersonality -Names @("initiative", "confidence", "confidence_level", "autonomy", "persistence"))
        }
        "formality" {
            $Value = Get-FirstPropertyValue -Source $Personality -Names @("professionalism", "formality", "formality_level")
            if ($null -ne $Value) { return $Value }
            return (Get-FirstPropertyValue -Source $LegacyPersonality -Names @("professionalism", "formality", "formality_level"))
        }
        "risk_tolerance" {
            $Value = Get-FirstPropertyValue -Source $Personality -Names @("risk_awareness", "risk_tolerance", "discretion", "discretion_level")
            if ($null -ne $Value) { return $Value }
            return (Get-FirstPropertyValue -Source $LegacyPersonality -Names @("risk_awareness", "risk_tolerance", "discretion", "discretion_level"))
        }
        default {
            $Value = Get-FirstPropertyValue -Source $Personality -Names @([string]$Definition.property, [string]$Definition.key)
            if ($null -ne $Value) { return $Value }
            return (Get-FirstPropertyValue -Source $LegacyPersonality -Names @([string]$Definition.property, [string]$Definition.key))
        }
    }
}

function Get-COOPERPersonalityChangeProposal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $NormalizedText = Normalize-PDAConversationalText -Value $Text
    $Definition = Get-COOPERPersonalitySettingDefinition -NormalizedText $NormalizedText
    if (-not $Definition) {
        return [pscustomobject]@{
            status = "clarify"
            reason = "No supported personality setting was recognized."
            response_text = "Specify one setting to update: humor, honesty, discretion, directness, verbosity, confidence, formality, or risk tolerance."
            next_action = "Pick a single supported setting and value."
        }
    }

    $Identity = $null
    $PersonalityResult = $null
    $CurrentPersonality = $null
    $LegacyPersonality = $null
    if (Get-Command -Name Get-COOPERPersonality -ErrorAction SilentlyContinue) {
        try {
            $PersonalityResult = Get-COOPERPersonality -Root $Root
            if ($PersonalityResult -and $PersonalityResult.PSObject.Properties.Name -contains "personality") {
                $CurrentPersonality = $PersonalityResult.personality
            }
            if ($PersonalityResult -and $PersonalityResult.PSObject.Properties.Name -contains "legacy_personality") {
                $LegacyPersonality = $PersonalityResult.legacy_personality
            }
        }
        catch {
            $CurrentPersonality = $null
        }
    }

    if (-not $CurrentPersonality -and (Get-Command -Name Get-COOPERIdentity -ErrorAction SilentlyContinue)) {
        try {
            $Identity = Get-COOPERIdentity -Root $Root
            if ($Identity -and $Identity.PSObject.Properties.Name -contains "personality") {
                $CurrentPersonality = $Identity.personality
            }
            if ($Identity -and $Identity.PSObject.Properties.Name -contains "legacy_personality") {
                $LegacyPersonality = $Identity.legacy_personality
            }
        }
        catch {
            $CurrentPersonality = $null
        }
    }

    $CurrentValue = Get-COOPERPersonalitySettingCurrentValue -Personality $CurrentPersonality -LegacyPersonality $LegacyPersonality -Definition $Definition
    if ($null -eq $CurrentValue) {
        $CurrentValue = 0
    }

    $ExplicitValue = $null
    foreach ($Pattern in @(
        '(?i)\b(?:to|=|->)\s*(\d{1,3})\b',
        '(?i)\b(?:set|update|adjust|change|propose|increase|decrease|lower|raise|boost|reduce)\s+(?:humor|humour|honesty|discretion|directness|formality|verbosity|confidence|risk tolerance)\s+(?:to\s+)?(\d{1,3})\b'
    )) {
        if ($Text -match $Pattern) {
            $ExplicitValue = [int]$Matches[1]
            break
        }
    }

    $Delta = 0
    if ($NormalizedText -match '(?i)\b(lower|decrease|reduce|less|turn down|dial down|dial back)\b') {
        $Delta = -10
    }
    elseif ($NormalizedText -match '(?i)\b(increase|raise|boost|more|higher|turn up|dial up|dial higher)\b') {
        $Delta = 10
    }

    $ProposedValue = $null
    $ChangeMode = "unspecified"
    if ($null -ne $ExplicitValue) {
        $ProposedValue = [int]([math]::Max(0, [math]::Min(100, $ExplicitValue)))
        $ChangeMode = "absolute"
    }
    elseif ($Delta -ne 0) {
        $ProposedValue = [int]([math]::Max(0, [math]::Min(100, ($CurrentValue + $Delta))))
        $ChangeMode = "relative"
    }

    if ($null -eq $ProposedValue) {
        return [pscustomobject]@{
            status = "clarify"
            reason = "No numeric value or relative adjustment could be derived."
            setting_key = [string]$Definition.key
            setting_label = [string]$Definition.label
            current_value = $CurrentValue
            response_text = ("{0}: {1}. Specify a value from 0 to 100, or say lower/increase." -f $Definition.label, $CurrentValue)
            next_action = "Specify a value from 0 to 100 and confirm."
        }
    }

    return [pscustomobject]@{
        status = "pass"
        reason = "Personality change proposal resolved."
        setting_key = [string]$Definition.key
        setting_label = [string]$Definition.label
        setting_property = [string]$Definition.property
        current_value = $CurrentValue
        proposed_value = [int]$ProposedValue
        change_mode = $ChangeMode
        response_text = @(
            "COOPER Personality"
            "Proposed update:"
            ("{0}: {1} -> {2}" -f $Definition.label, $CurrentValue, $ProposedValue)
            "Confirm?"
        ) -join "`r`n"
        next_action = "Reply Confirm to persist the update, or cancel personality change."
    }
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
        ($NormalizedText -match '(?i)\b(xlsx|excel|spreadsheet|workbook)\b' -and $NormalizedText -match '(?i)\b(validate|check|verify|audit|rate[- ]?limit|limit requests?|first \d+ links?|first ten links?|links?|urls?)\b' -and $NormalizedText -match '(?i)\b(report|markdown|obsidian|write|save)\b') -or
        ($NormalizedText -match '(?i)\b(research|investigate|search|study|authors|books)\b' -and $NormalizedText -match '(?i)\b(report|pdf|synopsis|synopses|links|sources|reading list|roadmap|plan|guide)\b')
    )
}

function Test-PDAConversationalJudgmentAdvice {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(should i|should we|would it be better|what should i do|what do you recommend|what is your recommendation|what is your opinion|what do you think|should i use|should we use|should i move|should we move|is it worth|is it better|compare|comparison|tradeoff|trade-off|pros and cons|what are the risks|biggest risk|concern|concerns|assumption|assumptions|challenge the assumption|\bvs\b|\bversus\b)\b'
    )
}

function Test-PDAConversationalStructuredOutputRequest {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\b(give me|create|draft|write|build|show me|provide|format as|turn this into|compile|make me)\b.*\b(report|assessment report|analysis report|risk register|assessment matrix|dashboard|status output|status report|structured analysis|structured report)\b' -or
        $NormalizedText -match '(?i)\b(project assessment report|assessment report|analysis report|risk register|assessment matrix|status output|status dashboard|status report)\b'
    )
}

function Test-PDAConversationalAmbiguous {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '(?i)\breview\b.*\brun\b|\brun\b.*\breview\b|\breport\b.*\brun\b|\brun\b.*\breport\b|\bresearch\b.*\brun\b|\brun\b.*\bresearch\b|\bexecute\b.*\breview\b|\breview\b.*\bexecute\b'
    )
}

function Split-PDAConversationalIntents {
    param([Parameter(Mandatory = $true)][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    # Segment compound prompts conservatively; execution still uses only the first actionable intent.
    $SentenceSegments = @([regex]::Split([string]$Text, '(?<=[\.\!\?;])\s+') | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    $NormalizedSegments = New-Object System.Collections.Generic.List[string]
    foreach ($Segment in $SentenceSegments) {
        $Current = [string]$Segment
        $Current = [regex]::Replace($Current, '^\s*COOPER\s*[:,]?\s*', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $Current = $Current.Trim()
        if (-not [string]::IsNullOrWhiteSpace($Current)) {
            $NormalizedSegments.Add($Current)
        }
    }

    if ($NormalizedSegments.Count -gt 0) {
        return @($NormalizedSegments)
    }

    return @($Text.Trim())
}

function Test-PDAConversationalPreludeOnly {
    param([Parameter(Mandatory = $true)][string]$NormalizedText)

    return [bool](
        $NormalizedText -match '^(good (morning|afternoon|evening)|hello|hi|hey|greetings|morning|afternoon|evening|good day)\b(?:\s+cooper)?$' -or
        (
            $NormalizedText -match '^(good (morning|afternoon|evening)|hello|hi|hey|greetings|morning|afternoon|evening|good day)\b' -and
            $NormalizedText -notmatch '(?i)\b(status|workflow|workflows|tool|tools|research|note|task|codex|report|brief|help|what can you do|what is operational|what capabilities do you have|what workflows are available|what phase are we in)\b'
        )
    )
}

function Invoke-PDACommandOrScript {
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][hashtable]$Arguments
    )

    $Command = Get-Command -Name $CommandName -ErrorAction SilentlyContinue
    if ($Command) {
        return & $Command @Arguments 2>&1
    }

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        return $null
    }

    return & $ScriptPath @Arguments 2>&1
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

function Get-COOPERToolInventorySummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $InventoryScript = Join-Path $PSScriptRoot "Get-PDAToolInventory.ps1"
    if (-not (Test-Path -LiteralPath $InventoryScript -PathType Leaf)) {
        return [pscustomobject]@{
            status = "warning"
            response_text = "Tool inventory unavailable."
            available_count = 0
            tools = @()
            source_of_truth = "Scripts/COOPER_ConversationalRouter.ps1"
        }
    }

    $Inventory = $null
    try {
        $Raw = & $InventoryScript -Root $Root -AsJson -NoThrow 2>&1
        $JsonText = [string]($Raw -join "`n").Trim()
        if (-not [string]::IsNullOrWhiteSpace($JsonText)) {
            $Inventory = $JsonText | ConvertFrom-Json
        }
    }
    catch {
        $Inventory = $null
    }

    if (-not $Inventory) {
        return [pscustomobject]@{
            status = "warning"
            response_text = "Tool inventory unavailable."
            available_count = 0
            tools = @()
            source_of_truth = "Scripts/Get-PDAToolInventory.ps1"
        }
    }

    $AvailableToolNames = @(
        @($Inventory.tools) |
            Where-Object { [bool]$_.available } |
            ForEach-Object { [string]$_.tool_name }
    )
    $ToolListText = if ($AvailableToolNames.Count -gt 0) { $AvailableToolNames -join ", " } else { "no available tools detected" }

    return [pscustomobject]@{
        status = [string]$Inventory.status
        response_text = "Tool inventory: $([int]$Inventory.available_count) available. Available tools: $ToolListText."
        available_count = [int]$Inventory.available_count
        tools = @($Inventory.tools)
        source_of_truth = "Scripts/Get-PDAToolInventory.ps1"
    }
}

function Get-COOPERWorkflowCatalogSummary {
    [CmdletBinding()]
    param()

    $SourceOfTruth = "06_Automation & Workflow Catalog.md"
    $Workflows = @()
    if (Get-Command -Name Get-COOPERWorkflowDefinitions -ErrorAction SilentlyContinue) {
        try {
            $Definitions = @(Get-COOPERWorkflowDefinitions -Root $Root)
            $Workflows = @(
                foreach ($Definition in $Definitions) {
                    [pscustomobject]@{
                        workflow_id = [string]$Definition.id
                        name = [string]$Definition.name
                        purpose = if ($Definition.PSObject.Properties.Name -contains "executor" -and -not [string]::IsNullOrWhiteSpace([string]$Definition.executor)) {
                            "Route to $([string]$Definition.executor) with governed approval."
                        }
                        else {
                            "Governed workflow."
                        }
                        workshop = if ($Definition.PSObject.Properties.Name -contains "workshop" -and -not [string]::IsNullOrWhiteSpace([string]$Definition.workshop)) {
                            "$([string]$Definition.workshop) Workshop"
                        }
                        else {
                            "Open Workshop"
                        }
                        category = if ($Definition.PSObject.Properties.Name -contains "storage_target" -and [string]$Definition.storage_target -eq "obsidian_drafts") {
                            "Category 1"
                        }
                        else {
                            "Category 1"
                        }
                    }
                }
            )
        }
        catch {
            $Workflows = @()
        }
    }

    if ($Workflows.Count -eq 0) {
        $Workflows = @(
            [pscustomobject]@{ workflow_id = "WF-002"; name = "Codex Task Generator"; purpose = "Turn project inputs into an implementation-ready Codex task file."; workshop = "Open Workshop"; category = "Category 1" }
            [pscustomobject]@{ workflow_id = "WF-004"; name = "Operational Status"; purpose = "Summarize current operational state from runtime sources."; workshop = "Open Workshop"; category = "Category 1" }
            [pscustomobject]@{ workflow_id = "WF-001"; name = "Research Summary"; purpose = "Collect and summarize research findings."; workshop = "Open Workshop"; category = "Category 1" }
            [pscustomobject]@{ workflow_id = "WF-005"; name = "Obsidian Note Creation"; purpose = "Create non-sensitive Obsidian notes or drafts."; workshop = "Open Workshop"; category = "Category 1" }
        )
    }

    $WorkflowLines = @($Workflows | ForEach-Object { "{0} {1}" -f $_.workflow_id, $_.name })
    if ($WorkflowLines.Count -eq 0) {
        $WorkflowLines = @("WF-002 Codex Task Generator", "WF-004 Operational Status", "WF-001 Research Summary", "WF-005 Obsidian Note Creation")
    }

    return [pscustomobject]@{
        status = "pass"
        response_text = (@("Workflow catalog:") + @($WorkflowLines)) -join "`r`n"
        workflow_count = $Workflows.Count
        workflows = $Workflows
        source_of_truth = $SourceOfTruth
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

    $IntentSegments = @(Split-PDAConversationalIntents -Text $Text)
    $PrimaryText = if ($IntentSegments.Count -gt 0) { [string]$IntentSegments[0] } else { [string]$Text }
    if ($IntentSegments.Count -gt 1) {
        $PrimaryNormalized = Normalize-PDAConversationalText -Value $PrimaryText
        if (Test-PDAConversationalPreludeOnly -NormalizedText $PrimaryNormalized) {
            $PrimaryText = [string]$IntentSegments[1]
        }
    }
    $Normalized = Normalize-PDAConversationalText -Value $PrimaryText
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
        source_of_truth      = "Scripts/COOPER_ConversationalRouter.ps1"
        root_path            = $Root
        intent_segments      = @()
    }

    if ([string]::IsNullOrWhiteSpace($Normalized)) {
        $Route.reason = "Empty input."
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalToolInventory -NormalizedText $Normalized) {
        $Route.route_type = "tool_inventory"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = "What tools are available?"
        $Route.reason = "Tool inventory request."
        $Route.confidence = 1
        if ($IntentSegments.Count -gt 1) { $Route.intent_segments = @($IntentSegments) }
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalWorkflowCatalog -NormalizedText $Normalized) {
        $Route.route_type = "workflow_catalog"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = "List available workflows"
        $Route.reason = "Workflow catalog request."
        $Route.confidence = 1
        if ($IntentSegments.Count -gt 1) { $Route.intent_segments = @($IntentSegments) }
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalResearchCollectionCodexChain -NormalizedText $Normalized) {
        $Route.route_type = "research_summary"
        $Route.response_mode = "governed_command"
        $Route.recommended_command = "Research Summary"
        $Route.reason = "Research, collection preparation, and implementation chain request."
        $Route.confidence = 0.98
        $Route.intent = "research_summary"
        $Route.task_type = "research_summary"
        $Route.workflow_chain = "research_collection_codex"
        if ($IntentSegments.Count -gt 1) { $Route.intent_segments = @($IntentSegments) }
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalCodexTaskGenerator -NormalizedText $Normalized) {
        $Route.route_type = "codex_task_generator"
        $Route.response_mode = "governed_command"
        $Route.recommended_command = "Create Codex task"
        $Route.reason = "WF-002 Codex Task Generator request."
        $Route.confidence = 1
        $Route.intent = "codex_task_generator"
        $Route.task_type = "codex_task_generator"
        if ($IntentSegments.Count -gt 1) { $Route.intent_segments = @($IntentSegments) }
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalResearchSummary -NormalizedText $Normalized) {
        $Route.route_type = "research_summary"
        $Route.response_mode = "governed_command"
        $Route.recommended_command = "Research Summary"
        $Route.reason = "WF-001 Research Summary request."
        $Route.confidence = 1
        $Route.intent = "research_summary"
        $Route.task_type = "research_summary"
        if ($IntentSegments.Count -gt 1) { $Route.intent_segments = @($IntentSegments) }
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalNoteCreation -NormalizedText $Normalized) {
        $Route.route_type = "note_creation"
        $Route.response_mode = "governed_command"
        $Route.recommended_command = "Create Obsidian note"
        $Route.reason = "WF-005 Obsidian note creation request."
        $Route.confidence = 1
        $Route.intent = "note_creation"
        $Route.task_type = "note_creation"
        if ($IntentSegments.Count -gt 1) { $Route.intent_segments = @($IntentSegments) }
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalWorkshopChangeRequest -NormalizedText $Normalized) {
        $Route.route_type = "workshop_change_request"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = "Select workshop in the host/UI."
        $Route.reason = "Workshop change request."
        $Route.confidence = 1
        if ($IntentSegments.Count -gt 1) { $Route.intent_segments = @($IntentSegments) }
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalSlashCommand -NormalizedText $Normalized) {
        if ($Normalized.StartsWith("/cooper")) {
            $Route.route_type = "legacy_cooper_slash_command"
            $Route.response_mode = "direct_answer"
            $Route.recommended_command = "Show system status"
            $Route.reason = "Legacy COOPER slash commands are deprecated."
            $Route.confidence = 1
            $Route.command = ""
            $Route.cooper_command = $Text
            if ($IntentSegments.Count -gt 1) { $Route.intent_segments = @($IntentSegments) }
            return [pscustomobject]$Route
        }

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
            if ($IntentSegments.Count -gt 1) { $Route.intent_segments = @($IntentSegments) }
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
        if ($IntentSegments.Count -gt 1) { $Route.intent_segments = @($IntentSegments) }
        return [pscustomobject]$Route
    }

    # Capability and status questions should resolve to WF-004 before generic help.
    if (Test-PDAConversationalDirectStatus -NormalizedText $Normalized) {
        $Route.route_type = "direct_status"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = "Show system status"
        $Route.reason = "Direct status request."
        $Route.confidence = 1
        if ($IntentSegments.Count -gt 1) { $Route.intent_segments = @($IntentSegments) }
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalDirectHelp -NormalizedText $Normalized) {
        $Route.route_type = "direct_help"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = "Ask naturally for status, tools, workflows, or workshop mode."
        $Route.reason = "Direct help request."
        $Route.confidence = 1
        if ($IntentSegments.Count -gt 1) { $Route.intent_segments = @($IntentSegments) }
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalRuntimeSelfAwareness -NormalizedText $Normalized) {
        $Route.route_type = "runtime_self_awareness"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = ""
        $Route.reason = "Runtime identity or backend awareness request."
        $Route.confidence = 1
        if ($IntentSegments.Count -gt 1) { $Route.intent_segments = @($IntentSegments) }
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalPersonalityQuery -NormalizedText $Normalized) {
        $Route.route_type = "personality_status"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = ""
        $Route.reason = "Direct personality profile request."
        $Route.confidence = 1
        if ($IntentSegments.Count -gt 1) { $Route.intent_segments = @($IntentSegments) }
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalPersonalityCancel -NormalizedText $Normalized) {
        $Route.route_type = "personality_cancel"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = ""
        $Route.reason = "Direct personality cancellation request."
        $Route.confidence = 1
        if ($IntentSegments.Count -gt 1) { $Route.intent_segments = @($IntentSegments) }
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalPersonalityUpdate -NormalizedText $Normalized) {
        $Route.route_type = "personality_update"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = ""
        $Route.reason = "Direct personality adjustment request."
        $Route.confidence = 1
        if ($IntentSegments.Count -gt 1) { $Route.intent_segments = @($IntentSegments) }
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
        $Route.recommended_command = "Review memory candidates."
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
        $Route.recommended_command = "Review dispatch guidance."
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

    if (Test-PDAConversationalJudgmentAdvice -NormalizedText $Normalized) {
        if (Test-PDAConversationalStructuredOutputRequest -NormalizedText $Normalized) {
            $Route.route_type = "goal_planning"
            $Route.response_mode = "direct_answer"
            $Route.recommended_command = ""
            $Route.reason = "Explicit structured output request."
            $Route.confidence = 0.96
            $Route.intent = "goal_planning"
            $Route.task_type = "goal_planning"
            return [pscustomobject]$Route
        }

        $Route.route_type = "judgment_advice"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = ""
        $Route.reason = "Natural-language recommendation or comparative judgment request."
        $Route.confidence = 0.95
        $Route.intent = "judgment_advice"
        $Route.task_type = "judgment_advice"
        $Route.briefing_focus = "judgment"
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

    if (Test-PDAConversationalStructuredOutputRequest -NormalizedText $Normalized) {
        $Route.route_type = "goal_planning"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = ""
        $Route.reason = "Explicit structured output request."
        $Route.confidence = 0.96
        $Route.intent = "goal_planning"
        $Route.task_type = "goal_planning"
        $Route.briefing_focus = "structured_report"
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
        [string]$WorkshopMode,

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
        source_of_truth          = "Scripts/COOPER_ConversationalRouter.ps1"
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
        intent_segments          = @()
        research_summary_path    = ""
        collection_import_path    = ""
        codex_task_path          = ""
        workflow_chain           = ""
        bridge_mode              = "conversational_direct"
        default_model            = Get-COOPERDefaultModelName -Root $Root
        selected_model           = ""
        model_status             = ""
        model_error_message      = ""
        model_routing_reason     = ""
        model_result             = $null
        goal_plan                = $null
        execution_plan           = $null
        runtime_status           = $null
    }
    $NormalizedText = Normalize-PDAConversationalText -Value $Text
    if ($Route.PSObject.Properties.Name -contains "intent_segments" -and $Route.intent_segments) {
        $BaseResponse.intent_segments = @($Route.intent_segments)
    }

    switch ([string]$Route.route_type) {
        "direct_status" {
            $ResolvedWorkshopMode = [string]$WorkshopMode
            if ([string]::IsNullOrWhiteSpace($ResolvedWorkshopMode) -and -not [string]::IsNullOrWhiteSpace([string]$env:COOPER_WORKSHOP_MODE)) {
                $ResolvedWorkshopMode = [string]$env:COOPER_WORKSHOP_MODE
            }

            if (Test-Path -LiteralPath $StatusBridgeScript -PathType Leaf) {
                try {
                    $StatusResult = & $StatusBridgeScript -WorkshopMode $ResolvedWorkshopMode
                }
                catch {
                    $StatusResult = [pscustomobject]@{
                        success = $false
                        reason = $_.Exception.Message
                        response_text = ""
                    }
                }
            }
            else {
                $StatusResult = [pscustomobject]@{
                    success = $false
                    reason = "COOPER status bridge is unavailable."
                    response_text = ""
                }
            }

            $BaseResponse.runtime_status = $StatusResult
            if ($StatusResult -and ($StatusResult.PSObject.Properties.Name -contains "response_text" -and -not [string]::IsNullOrWhiteSpace([string]$StatusResult.response_text))) {
                $BaseResponse.response_text = [string]$StatusResult.response_text
                $BaseResponse.next_action = "Ask about tools, workflows, identity, or memory."
                $BaseResponse.latest_result_response_text = $BaseResponse.response_text
            }
            elseif ($StatusResult -and [bool]$StatusResult.success -eq $true) {
                $BaseResponse.response_text = if ($StatusResult.PSObject.Properties.Name -contains "reason" -and -not [string]::IsNullOrWhiteSpace([string]$StatusResult.reason)) { [string]$StatusResult.reason } else { "COOPER status summary completed." }
                $BaseResponse.next_action = "Ask about tools, workflows, identity, or memory."
                $BaseResponse.latest_result_response_text = $BaseResponse.response_text
            }
            else {
                $BaseResponse.response_text = if ($StatusResult -and $StatusResult.PSObject.Properties.Name -contains "reason" -and -not [string]::IsNullOrWhiteSpace([string]$StatusResult.reason)) { [string]$StatusResult.reason } else { "COOPER status is unavailable because workshop mode was not selected." }
                $BaseResponse.next_action = "Select COOPER or COOPER Private, then ask for system status again."
                $BaseResponse.latest_result_response_text = $BaseResponse.response_text
            }
        }
        "tool_inventory" {
            $Inventory = Get-COOPERToolInventorySummary -Root $Root
            $BaseResponse.response_text = [string]$Inventory.response_text
            $BaseResponse.next_action = "Ask for a specific tool by name or request a workshop status check."
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
            $BaseResponse.runtime_status = $Inventory
        }
        "workflow_catalog" {
            $Catalog = Get-COOPERWorkflowCatalogSummary
            $BaseResponse.response_text = [string]$Catalog.response_text
            $BaseResponse.next_action = "Ask for a specific workflow description or a status check."
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
            $BaseResponse.runtime_status = $Catalog
        }
        "codex_task_generator" {
            $TaskGeneratorScript = Join-Path $PSScriptRoot "Invoke-COOPERCodexTaskGenerator.ps1"
            if (Test-Path -LiteralPath $TaskGeneratorScript -PathType Leaf) {
                try {
                    $TaskResult = & $TaskGeneratorScript -Text $Text -Approved -Root $Root
                }
                catch {
                    $TaskResult = [pscustomobject]@{
                        success = $false
                        reason = $_.Exception.Message
                        response_text = ""
                        routed_tool = $null
                        approval_decision = $null
                        workbench_result = $null
                    }
                }
            }
            else {
                $TaskResult = [pscustomobject]@{
                    success = $false
                    reason = "COOPER Codex task generation workflow is unavailable."
                    response_text = ""
                    routed_tool = $null
                    approval_decision = $null
                    workbench_result = $null
                }
            }

            $BaseResponse.runtime_status = $TaskResult
            $BaseResponse.response_text = if ($TaskResult -and [bool]$TaskResult.success -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$TaskResult.response_text)) { [string]$TaskResult.response_text } else { if ($TaskResult -and $TaskResult.PSObject.Properties.Name -contains "reason" -and -not [string]::IsNullOrWhiteSpace([string]$TaskResult.reason)) { [string]$TaskResult.reason } else { "WF-002 Codex task generation could not be completed." } }
            $BaseResponse.next_action = if ($TaskResult -and [bool]$TaskResult.success -eq $true) { "Review the Codex task or ask for another implementation task." } else { "Review approval or task path configuration." }
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
            $BaseResponse.codex_task_result = $TaskResult
            if ($TaskResult -and $TaskResult.PSObject.Properties.Name -contains "task_path") {
                $BaseResponse.latest_result_path = [string]$TaskResult.task_path
                $BaseResponse.result_artifact_path = [string]$TaskResult.task_path
            }
        }
        "research_summary" {
            $ResearchWorkerScript = Join-Path $PSScriptRoot "Invoke-PDAResearchWorker.ps1"
            $ResearchReviewScript = Join-Path $PSScriptRoot "Resolve-COOPERWorkflowReview.ps1"
            $KnowledgeImportScript = Join-Path $PSScriptRoot "Invoke-COOPERKnowledgeImportDraft.ps1"
            $TaskGeneratorScript = Join-Path $PSScriptRoot "Invoke-COOPERCodexTaskGenerator.ps1"
            $ProjectMemoryScript = Join-Path $PSScriptRoot "Update-COOPERProjectMemory.ps1"
            $WorkflowSkillsScript = Join-Path $PSScriptRoot "Update-COOPERWorkflowSkills.ps1"
            $ResearchCollectionCodexChainRequested = [bool](
                $Route.PSObject.Properties.Name -contains "workflow_chain" -and
                [string]$Route.workflow_chain -eq "research_collection_codex"
            )
            $ImportDraftRequested = (Test-PDAConversationalKnowledgeCollectionImport -NormalizedText $NormalizedText) -or $ResearchCollectionCodexChainRequested
            if (Test-Path -LiteralPath $ResearchWorkerScript -PathType Leaf) {
                $TempDir = Join-Path $Root "tmp\pda-research-summary"
                New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
                $TaskPath = Join-Path $TempDir ("wf-001-{0}.json" -f ([guid]::NewGuid().ToString("N")))
                $Task = [pscustomobject]@{
                    task_id = "WF-001"
                    command = "/research"
                    classification = "category_1"
                    target = $Text
                    source_path = ""
                }

                try {
                    $Task | ConvertTo-Json -Depth 10 | Set-Content -Path $TaskPath -Encoding UTF8
                    $Raw = @(Invoke-PDACommandOrScript -CommandName "Invoke-PDAResearchWorker" -ScriptPath $ResearchWorkerScript -Arguments @{ TaskPath = $TaskPath })
                    $JsonText = [string]($Raw -join "`n").Trim()
                    if (-not [string]::IsNullOrWhiteSpace($JsonText)) {
                        $ResearchResult = ConvertFrom-PDAMixedJson -Text $JsonText -SourceName $ResearchWorkerScript
                    }
                }
                catch {
                    $ResearchResult = [pscustomobject]@{
                        success = $false
                        reason = $_.Exception.Message
                        saved_path = ""
                        output = $null
                    }
                }
                finally {
                    Remove-Item -LiteralPath $TaskPath -Force -ErrorAction SilentlyContinue
                }
            }
            else {
                $ResearchResult = [pscustomobject]@{
                    success = $false
                    reason = "WF-001 research worker is unavailable."
                    saved_path = ""
                    output = $null
                }
            }

            $BaseResponse.runtime_status = $ResearchResult
            $WorkflowReview = $null
            $SummaryPath = ""
            if ($ResearchResult -and $ResearchResult.PSObject.Properties.Name -contains "saved_path" -and -not [string]::IsNullOrWhiteSpace([string]$ResearchResult.saved_path)) {
                $SummaryPath = [string]$ResearchResult.saved_path
            }
            elseif ($ResearchResult -and $ResearchResult.PSObject.Properties.Name -contains "output" -and $ResearchResult.output -and $ResearchResult.output.PSObject.Properties.Name -contains "markdown_path" -and -not [string]::IsNullOrWhiteSpace([string]$ResearchResult.output.markdown_path)) {
                $SummaryPath = [string]$ResearchResult.output.markdown_path
            }

            $ResearchSucceeded = $false
            $ReviewPassed = $false
            if ($ResearchResult) {
                if ($ResearchResult.PSObject.Properties.Name -contains "status" -and [string]$ResearchResult.status -eq "success") {
                    $ResearchSucceeded = $true
                }
                elseif ($ResearchResult.PSObject.Properties.Name -contains "success" -and [bool]$ResearchResult.success -eq $true) {
                    $ResearchSucceeded = $true
                }
            }

            if ($ResearchSucceeded -and (Test-Path -LiteralPath $ResearchReviewScript -PathType Leaf)) {
                try {
                    $WorkflowReview = Invoke-PDACommandOrScript -CommandName "Resolve-COOPERWorkflowReview" -ScriptPath $ResearchReviewScript -Arguments @{
                        WorkflowId = "WF-001"
                        WorkflowResult = $ResearchResult
                        RequestText = $Text
                        ExpectedOutputType = "research_markdown"
                        ExpectedOutputPath = $SummaryPath
                    }
                    $ReviewPassed = [bool]$WorkflowReview.review_passed
                }
                catch {
                    $WorkflowReview = [pscustomobject]@{
                        status = "fail"
                        review_passed = $false
                        reason = $_.Exception.Message
                        issues = @($_.Exception.Message)
                    }
                }
            }
            elseif ($ResearchSucceeded) {
                $WorkflowReview = [pscustomobject]@{
                    status = "fail"
                    review_passed = $false
                    reason = "WF-001 workflow review script is unavailable."
                    issues = @("WF-001 workflow review script is unavailable.")
                }
            }

            if ($ReviewPassed -and -not $ImportDraftRequested) {
                if (Test-Path -LiteralPath $ProjectMemoryScript -PathType Leaf) {
                    try {
                        $BaseResponse.project_memory_update = & $ProjectMemoryScript -WorkflowId "WF-001" -ReviewResult $WorkflowReview -RequestText $Text -OutputPath $SummaryPath
                    }
                    catch {
                        $BaseResponse.project_memory_update = [pscustomobject]@{
                            status = "fail"
                            workflow_id = "WF-001"
                            reason = $_.Exception.Message
                        }
                    }
                }

                if (Test-Path -LiteralPath $WorkflowSkillsScript -PathType Leaf) {
                    try {
                        $BaseResponse.skill_update = & $WorkflowSkillsScript -WorkflowId "WF-001" -ReviewResult $WorkflowReview -ExampleRequest $Text -ExampleOutput ([System.IO.Path]::GetFileName($SummaryPath)) -SkillName "Research Summary"
                    }
                    catch {
                        $BaseResponse.skill_update = [pscustomobject]@{
                            status = "fail"
                            workflow_id = "WF-001"
                            reason = $_.Exception.Message
                        }
                    }
                }
            }

            $ImportDraftResult = $null
            if ($ReviewPassed -and $ImportDraftRequested) {
                if (Test-Path -LiteralPath $KnowledgeImportScript -PathType Leaf) {
                    try {
                        $ImportDraftResult = Invoke-PDACommandOrScript -CommandName "Invoke-COOPERKnowledgeImportDraft" -ScriptPath $KnowledgeImportScript -Arguments @{
                            RequestText = $Text
                            ResearchResult = $ResearchResult
                            ResearchReview = $WorkflowReview
                            Approved = $true
                            Root = $Root
                        }
                    }
                    catch {
                        $ImportDraftResult = [pscustomobject]@{
                            success = $false
                            workflow_id = "WF-006"
                            response_text = $_.Exception.Message
                            reason = $_.Exception.Message
                            research_summary_path = $SummaryPath
                            import_draft_path = ""
                            workflow_review = $null
                        }
                    }
                }
                else {
                    $ImportDraftResult = [pscustomobject]@{
                        success = $false
                        workflow_id = "WF-006"
                        response_text = "WF-006 import draft workflow is unavailable."
                        reason = "WF-006 import draft workflow is unavailable."
                        research_summary_path = $SummaryPath
                        import_draft_path = ""
                        workflow_review = $null
                    }
                }

                $BaseResponse.collection_import_result = $ImportDraftResult
                if ($ImportDraftResult -and [bool]$ImportDraftResult.success -eq $true) {
                    $BaseResponse.collection_import_path = [string]$ImportDraftResult.import_draft_path
                    $BaseResponse.latest_result_path = [string]$ImportDraftResult.import_draft_path
                    $BaseResponse.result_artifact_path = [string]$ImportDraftResult.import_draft_path
                }
            }

            $CodexTaskResult = $null
            if ($ResearchCollectionCodexChainRequested -and $ImportDraftResult -and [bool]$ImportDraftResult.success -eq $true) {
                if (Test-Path -LiteralPath $TaskGeneratorScript -PathType Leaf) {
                    try {
                        $CodexTaskResult = Invoke-PDACommandOrScript -CommandName "Invoke-COOPERCodexTaskGenerator" -ScriptPath $TaskGeneratorScript -Arguments @{
                            Text = $Text
                            Approved = $true
                            Root = $Root
                        }
                    }
                    catch {
                        $CodexTaskResult = [pscustomobject]@{
                            success = $false
                            workflow_id = "WF-002"
                            response_text = $_.Exception.Message
                            reason = $_.Exception.Message
                            task_path = ""
                            workflow_review = $null
                        }
                    }
                }
                else {
                    $CodexTaskResult = [pscustomobject]@{
                        success = $false
                        workflow_id = "WF-002"
                        response_text = "WF-002 Codex task generation workflow is unavailable."
                        reason = "WF-002 Codex task generation workflow is unavailable."
                        task_path = ""
                        workflow_review = $null
                    }
                }

                $BaseResponse.codex_task_result = $CodexTaskResult
                if ($CodexTaskResult -and [bool]$CodexTaskResult.success -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$CodexTaskResult.task_path)) {
                    $CodexTaskPath = [string]$CodexTaskResult.task_path
                    $BaseResponse.codex_task_path = $CodexTaskPath
                    $BaseResponse.latest_result_path = $CodexTaskPath
                    $BaseResponse.result_artifact_path = $CodexTaskPath
                }
            }

            $BaseResponse.workflow_review = $WorkflowReview
            if ($ResearchCollectionCodexChainRequested -and $ImportDraftResult -and [bool]$ImportDraftResult.success -eq $true -and $CodexTaskResult -and [bool]$CodexTaskResult.success -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$SummaryPath) -and -not [string]::IsNullOrWhiteSpace([string]$ImportDraftResult.import_draft_path) -and -not [string]::IsNullOrWhiteSpace([string]$CodexTaskResult.task_path)) {
                $WF001ReviewStatus = if ($WorkflowReview -and $WorkflowReview.PSObject.Properties.Name -contains "review_passed") { if ([bool]$WorkflowReview.review_passed) { "pass" } else { "fail" } } else { if ($ReviewPassed) { "pass" } else { "fail" } }
                $WF006ReviewStatus = if ($ImportDraftResult.PSObject.Properties.Name -contains "workflow_review" -and $ImportDraftResult.workflow_review -and $ImportDraftResult.workflow_review.PSObject.Properties.Name -contains "review_passed") { if ([bool]$ImportDraftResult.workflow_review.review_passed) { "pass" } else { "fail" } } else { if ([bool]$ImportDraftResult.success -eq $true) { "pass" } else { "fail" } }
                $WF002ReviewStatus = if ($CodexTaskResult.PSObject.Properties.Name -contains "workflow_review" -and $CodexTaskResult.workflow_review -and $CodexTaskResult.workflow_review.PSObject.Properties.Name -contains "review_passed") { if ([bool]$CodexTaskResult.workflow_review.review_passed) { "pass" } else { "fail" } } else { if ([bool]$CodexTaskResult.success -eq $true) { "pass" } else { "fail" } }
                $BaseResponse.response_text = @(
                    "Research summary: $SummaryPath"
                    "Collection import draft: $([string]$ImportDraftResult.import_draft_path)"
                    "Codex task: $([string]$CodexTaskResult.task_path)"
                    "Review status: WF-001 $WF001ReviewStatus; WF-006 $WF006ReviewStatus; WF-002 $WF002ReviewStatus"
                    "Recommended next action: Review the Codex task or ask for another implementation task."
                ) -join "`r`n"
                $BaseResponse.next_action = "Review the Codex task or ask for another implementation task."
            }
            elseif ($ReviewPassed -and $ImportDraftRequested -and $ImportDraftResult -and [bool]$ImportDraftResult.success -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$ImportDraftResult.import_draft_path)) {
                $BaseResponse.response_text = "Created research summary at $SummaryPath and import draft at $([string]$ImportDraftResult.import_draft_path)."
            }
            elseif ($ReviewPassed -and -not [string]::IsNullOrWhiteSpace($SummaryPath)) {
                $BaseResponse.response_text = "Created research summary at $SummaryPath."
            }
            elseif ($ResearchCollectionCodexChainRequested -and $ImportDraftResult -and [bool]$ImportDraftResult.success -eq $true -and $CodexTaskResult -and [bool]$CodexTaskResult.success -ne $true -and -not [string]::IsNullOrWhiteSpace([string]$CodexTaskResult.reason)) {
                $BaseResponse.response_text = [string]$CodexTaskResult.reason
            }
            elseif ($ImportDraftRequested -and $ImportDraftResult -and [bool]$ImportDraftResult.success -ne $true -and -not [string]::IsNullOrWhiteSpace([string]$ImportDraftResult.reason)) {
                $BaseResponse.response_text = [string]$ImportDraftResult.reason
            }
            elseif ($WorkflowReview -and ($WorkflowReview.PSObject.Properties.Name -contains "issues") -and $WorkflowReview.issues) {
                $BaseResponse.response_text = [string]($WorkflowReview.issues -join "; ")
            }
            elseif ($ResearchResult -and ($ResearchResult.PSObject.Properties.Name -contains "reason") -and -not [string]::IsNullOrWhiteSpace([string]$ResearchResult.reason)) {
                [string]$ResearchResult.reason
            }
            else {
                "WF-001 research summary could not be completed."
            }
            if ($ImportDraftResult) {
                $BaseResponse.runtime_status = $ImportDraftResult
            }
            $BaseResponse.next_action = if ($ReviewPassed -and $ImportDraftRequested) { "Review the import draft or ask for another research topic." } elseif ($ReviewPassed) { "Review the research summary note or ask for another research topic." } else { "Review the research workflow or the source path configuration." }
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
            $BaseResponse.intent = "research_summary"
            $BaseResponse.confidence = 1
            $BaseResponse.task_type = "research_summary"
            if (-not [string]::IsNullOrWhiteSpace($SummaryPath)) {
                $BaseResponse.research_summary_path = $SummaryPath
            }
            if ($ImportDraftResult -and [bool]$ImportDraftResult.success -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$ImportDraftResult.import_draft_path)) {
                $BaseResponse.collection_import_path = [string]$ImportDraftResult.import_draft_path
                $BaseResponse.latest_result_path = [string]$ImportDraftResult.import_draft_path
                $BaseResponse.result_artifact_path = [string]$ImportDraftResult.import_draft_path
            }
            if ($CodexTaskResult -and [bool]$CodexTaskResult.success -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$CodexTaskResult.task_path)) {
                $BaseResponse.codex_task_path = [string]$CodexTaskResult.task_path
                $BaseResponse.latest_result_path = [string]$CodexTaskResult.task_path
                $BaseResponse.result_artifact_path = [string]$CodexTaskResult.task_path
                $BaseResponse.runtime_status = $CodexTaskResult
            }
            elseif (-not [string]::IsNullOrWhiteSpace($SummaryPath)) {
                $BaseResponse.latest_result_path = $SummaryPath
                $BaseResponse.result_artifact_path = $SummaryPath
            }
            $BaseResponse.research_summary_result = $ResearchResult
        }
        "note_creation" {
            $NoteScript = Join-Path $PSScriptRoot "Invoke-COOPERNoteCreationCommand.ps1"
            if (Test-Path -LiteralPath $NoteScript -PathType Leaf) {
                try {
                    $NoteResult = & $NoteScript -Text $Text -Approved -Root $Root
                }
                catch {
                    $NoteResult = [pscustomobject]@{
                        success = $false
                        reason = $_.Exception.Message
                        response_text = ""
                        routed_tool = $null
                        approval_decision = $null
                        workbench_result = $null
                    }
                }
            }
            else {
                $NoteResult = [pscustomobject]@{
                    success = $false
                    reason = "COOPER note creation workflow is unavailable."
                    response_text = ""
                    routed_tool = $null
                    approval_decision = $null
                    workbench_result = $null
                }
            }

            $BaseResponse.runtime_status = $NoteResult
            $BaseResponse.response_text = if ($NoteResult -and [bool]$NoteResult.success -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$NoteResult.response_text)) { [string]$NoteResult.response_text } else { if ($NoteResult -and $NoteResult.PSObject.Properties.Name -contains "reason" -and -not [string]::IsNullOrWhiteSpace([string]$NoteResult.reason)) { [string]$NoteResult.reason } else { "WF-005 note creation could not be completed." } }
            $BaseResponse.next_action = if ($NoteResult -and [bool]$NoteResult.success -eq $true) { "Ask for another note or request a workflow catalog." } else { "Review approval or note path configuration." }
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
            $BaseResponse.note_creation_result = $NoteResult
            if ($NoteResult -and $NoteResult.PSObject.Properties.Name -contains "note_path") {
                $BaseResponse.latest_result_path = [string]$NoteResult.note_path
                $BaseResponse.result_artifact_path = [string]$NoteResult.note_path
            }
        }
        "workshop_change_request" {
            $BaseResponse.response_text = "Workshop selection remains a human decision. Select COOPER or COOPER Private in the host or UI, then ask for status again."
            $BaseResponse.next_action = "Switch the workshop in the host/UI."
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
        }
        "legacy_cooper_slash_command" {
            $BaseResponse.response_text = "The legacy COOPER slash-command interface is retired. Use conversational language such as 'Show system status.'"
            $BaseResponse.next_action = "Ask naturally for status, tools, workflows, or workshop mode."
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
        }
        "direct_help" {
            $BaseResponse.response_text = "Ask naturally for status, tools, workflows, planning, research, or execution help."
            $BaseResponse.next_action = "Ask for the action you want in normal language."
        }
        "runtime_self_awareness" {
            $ResolvedWorkshopMode = [string]$WorkshopMode
            if ([string]::IsNullOrWhiteSpace($ResolvedWorkshopMode) -and -not [string]::IsNullOrWhiteSpace([string]$env:COOPER_WORKSHOP_MODE)) {
                $ResolvedWorkshopMode = [string]$env:COOPER_WORKSHOP_MODE
            }

            if (Test-Path -LiteralPath $StatusBridgeScript -PathType Leaf) {
                try {
                    $StatusResult = & $StatusBridgeScript -WorkshopMode $ResolvedWorkshopMode
                }
                catch {
                    $StatusResult = [pscustomobject]@{
                        success = $false
                        reason = $_.Exception.Message
                        response_text = ""
                    }
                }
            }
            else {
                $StatusResult = [pscustomobject]@{
                    success = $false
                    reason = "COOPER status bridge is unavailable."
                    response_text = ""
                }
            }

            if ($StatusResult -and [bool]$StatusResult.success -eq $true) {
                $BaseResponse.response_text = [string]$StatusResult.response_text
                $BaseResponse.runtime_status = $StatusResult
                $BaseResponse.selected_model = [string]$StatusResult.workshop_identity.default_model
                $BaseResponse.model_status = "bypassed"
                $BaseResponse.model_error_message = ""
                $BaseResponse.model_routing_reason = "Runtime self-awareness requests are answered from governed status output."
                $BaseResponse.next_action = "Ask about tools, workflows, identity, or memory."
                $BaseResponse.latest_result_response_text = $BaseResponse.response_text
            }
            else {
                $BaseResponse.response_text = if ($StatusResult -and $StatusResult.PSObject.Properties.Name -contains "reason" -and -not [string]::IsNullOrWhiteSpace([string]$StatusResult.reason)) { [string]$StatusResult.reason } else { "COOPER status is unavailable because workshop mode was not selected." }
                $BaseResponse.next_action = "Select COOPER or COOPER Private, then ask for system status again."
            }
        }
        "personality_status" {
            $Personality = Get-COOPERPersonality -Root $Root
            $BaseResponse.response_text = @(
                "COOPER Personality"
                ("Profile: {0}" -f $Personality.personality.profile)
                ("Humor: {0}" -f $Personality.personality.humor)
                ("Sarcasm: {0}" -f $Personality.personality.sarcasm)
                ("Professionalism: {0}" -f $Personality.personality.professionalism)
                ("Brevity: {0}" -f $Personality.personality.brevity)
                ("Initiative: {0}" -f $Personality.personality.initiative)
                ("Risk awareness: {0}" -f $Personality.personality.risk_awareness)
            ) -join "`r`n"
            $BaseResponse.next_action = "Ask for system status or another runtime question."
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
            $BaseResponse.runtime_status = $Personality
        }
        "cooper_personality_command" {
            $PersonalityCommand = Invoke-COOPERPersonalityCommand -Text $Text -Root $Root
            $BaseResponse.response_text = [string]$PersonalityCommand.response_text
            $BaseResponse.next_action = "Ask to query or adjust personality using conversational language."
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
            $BaseResponse.personality_command = $PersonalityCommand
            if ($PersonalityCommand.PSObject.Properties.Name -contains "personality") {
                $BaseResponse.personality = $PersonalityCommand.personality
            }
        }
        "personality_update" {
            $Proposal = Get-COOPERPersonalityChangeProposal -Text $Text -Root $Root
            if ($Proposal.status -eq "pass") {
                $BaseResponse.response_text = $Proposal.response_text
                $BaseResponse.next_action = $Proposal.next_action
                $BaseResponse.personality_setting = $Proposal.setting_key
                $BaseResponse.personality_label = $Proposal.setting_label
                $BaseResponse.personality_property = $Proposal.setting_property
                $BaseResponse.personality_current_value = $Proposal.current_value
                $BaseResponse.personality_proposed_value = $Proposal.proposed_value
                $BaseResponse.personality_change_mode = $Proposal.change_mode
                $BaseResponse.personality_proposal = $Proposal
            }
            else {
                $BaseResponse.response_text = $Proposal.response_text
                $BaseResponse.next_action = $Proposal.next_action
                $BaseResponse.personality_proposal = $Proposal
            }
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
        }
        "personality_cancel" {
            $BaseResponse.response_text = @(
                "COOPER Personality"
                "Change cancelled."
                "No write was performed."
            ) -join "`r`n"
            $BaseResponse.next_action = "Standing by."
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
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
                $BaseResponse.next_action = if ($TaskResult.PSObject.Properties.Name -contains "next_action" -and -not [string]::IsNullOrWhiteSpace([string]$TaskResult.next_action)) { [string]$TaskResult.next_action } else { "Ask me to start a task with planning, research, or reporting, or confirm a queued request." }
            }
            else {
                $BaseResponse.response_text = "I don't see a tracked PDA task for this conversation yet. If you want, I can help start one with planning, research, or reporting."
                $BaseResponse.next_action = "Ask me to start a task with planning or research, or ask for system status."
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
            $BaseResponse.next_action = "Review the full memory index or inspect PDA-Memory/candidates for pending promotions."
            $BaseResponse.recommended_command = "Review memory candidates"
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
                $BaseResponse.next_action = "Ask for system status if you need the operator console summary."
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
                    "Review the governed dispatch path."
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
                    "Review the governed dispatch path or share a specific task for recommendation."
                ) -join "`r`n"
            }

            $BaseResponse.next_action = "Review the governed dispatch path or share a specific task for recommendation."
            $BaseResponse.recommended_command = "Review dispatch guidance"
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
                $BaseResponse.task_type = if ($GoalPlan.PSObject.Properties.Name -contains "goal_type" -and -not [string]::IsNullOrWhiteSpace([string]$GoalPlan.goal_type)) { [string]$GoalPlan.goal_type } else { "goal_planning" }
                if ($GoalPlan.PSObject.Properties.Name -contains "goal_type" -and [string]$GoalPlan.goal_type -eq "data_validation_report") {
                    $BaseResponse.task_type = "data_validation_report"
                    $BaseResponse.route_type = "goal_planning"
                    $BaseResponse.decision_type = "plan"
                    $BaseResponse.dispatch_ready = $false
                    $BaseResponse.dispatch_status = "not_dispatched"
                    $BaseResponse.requires_confirmation = $true
                }
            }
            else {
                $BaseResponse.response_text = "I can turn natural-language goals into a structured plan, but the goal planner is unavailable right now."
                $BaseResponse.next_action = "Try planning or ask for help if you want the command list."
            }
        }
        "judgment_advice" {
            $ModelResult = Invoke-COOPERDefaultModelChat -Text $Text -Root $Root -ResponseStyle "Answer in 1 to 4 sentences. Use short paragraphs. Do not add next steps unless the user asks."
            if ($ModelResult) {
                $BaseResponse.bridge_mode = [string]$ModelResult.bridge_mode
                $BaseResponse.response_text = [string]$ModelResult.response_text
                $BaseResponse.next_action = [string]$ModelResult.next_action
                $BaseResponse.selected_model = [string]$ModelResult.selected_model
                $BaseResponse.model_status = [string]$ModelResult.model_status
                $BaseResponse.model_error_message = [string]$ModelResult.model_error_message
                $BaseResponse.model_routing_reason = [string]$ModelResult.routing_reason
                $BaseResponse.model_result = $ModelResult.model_result
                if ([string]::IsNullOrWhiteSpace([string]$BaseResponse.model_routing_reason) -and $ModelResult.model_routing) {
                    $BaseResponse.model_routing_reason = if ($ModelResult.model_routing.PSObject.Properties.Name -contains "routing_reason") { [string]$ModelResult.model_routing.routing_reason } else { "" }
                }
            }
            else {
                $BaseResponse.response_text = "I can assess the options, but the model path is unavailable right now."
                $BaseResponse.next_action = "Restore a local model or ask for help with the command list."
            }
        }
        "ambiguous" {
            $BaseResponse.response_text = "I can help with one action at a time. Do you want a review, a run/execution, a report, or a goal plan?"
            $BaseResponse.next_action = "Reply with one clear action such as review, report, status, research, execute, or goal planning."
        }
        "fallback" {
            $ModelResult = Invoke-COOPERDefaultModelChat -Text $Text -Root $Root -ResponseStyle "Answer in 1 to 4 sentences. Use short paragraphs. Do not add next steps unless the user asks."
            if ($ModelResult) {
                $BaseResponse.bridge_mode = [string]$ModelResult.bridge_mode
                $BaseResponse.response_text = [string]$ModelResult.response_text
                $BaseResponse.next_action = [string]$ModelResult.next_action
                $BaseResponse.selected_model = [string]$ModelResult.selected_model
                $BaseResponse.model_status = [string]$ModelResult.model_status
                $BaseResponse.model_error_message = [string]$ModelResult.model_error_message
                $BaseResponse.model_routing_reason = [string]$ModelResult.routing_reason
                $BaseResponse.model_result = $ModelResult.model_result
                if ([string]::IsNullOrWhiteSpace([string]$BaseResponse.model_routing_reason) -and $ModelResult.model_routing) {
                    $BaseResponse.model_routing_reason = if ($ModelResult.model_routing.PSObject.Properties.Name -contains "routing_reason") { [string]$ModelResult.model_routing.routing_reason } else { "" }
                }
            }
            else {
                $BaseResponse.response_text = "Status, reports, research, planning, execution. Pick a target."
                $BaseResponse.next_action = "Ask for a status check, a report, or use help for the command list."
            }
        }
        default {
            $BaseResponse.response_text = "Status, reports, research, planning, execution. Pick a target."
            $BaseResponse.next_action = "Ask for a status check, a report, or use help for the command list."
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
