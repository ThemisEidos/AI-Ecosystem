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
$RuntimeStatusScript = Join-Path $PSScriptRoot "Get-COOPERRuntimeStatus.ps1"
$EnvironmentHelperScript = Join-Path $PSScriptRoot "PDA_Environment.ps1"
$ExecutorRegistryScript = Join-Path $PSScriptRoot "PDA_ExecutorRegistry.ps1"
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
if (Test-Path -LiteralPath $ParserPath -PathType Leaf) {
    . $ParserPath
}
if (Test-Path -LiteralPath $RuntimeStatusScript -PathType Leaf) {
    . $RuntimeStatusScript
}
if (Test-Path -LiteralPath $EnvironmentHelperScript -PathType Leaf) {
    . $EnvironmentHelperScript
}
if (Test-Path -LiteralPath $ExecutorRegistryScript -PathType Leaf) {
    . $ExecutorRegistryScript
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

function Invoke-COOPERDefaultModelChat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
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
        next_action = "Ask /help for the command list."
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
        foreach ($Candidate in $DefaultModelCandidates) {
            $Result.selected_model = [string]$Candidate
            $Raw = & pwsh -NoProfile -File $ModelScript -WorkerName "cooper-chat" -TaskType "conversational" -Category "category_1" -Sensitivity "standard" -Prompt $Text -SelectedModelOverride ([string]$Candidate) -AsJson -NoThrow 2>&1
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
        $Result.next_action = "Restore a local model or ask /help for the command list."
        $Result.bridge_mode = "model_fallback"
        $Result.handoff_status = "fallback"
        return [pscustomobject]$Result
    }
    catch {
        $Result.model_error_message = $_.Exception.Message
        $Result.response_text = "COOPER default models are unavailable. $($Result.model_error_message) $FallbackHelp"
        $Result.next_action = "Restore a local model or ask /help for the command list."
        return [pscustomobject]$Result
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
        $NormalizedText -match '(?i)\b(status report|operational status|health report|morning briefing|daily briefing|what''?s the status|what is the status|how are things going|how are you doing|how is the pda doing|how is the ecosystem|summarize the ecosystem status|summarise the ecosystem status|show me the current status|current status|system status|how are things|pda status|how is everything|status)\b'
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
        source_of_truth      = "Scripts/COOPER_ConversationalRouter.ps1"
        root_path            = $Root
    }

    if ([string]::IsNullOrWhiteSpace($Normalized)) {
        $Route.reason = "Empty input."
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalSlashCommand -NormalizedText $Normalized) {
        if ($Normalized.StartsWith("/cooper")) {
            $Route.route_type = "cooper_personality_command"
            $Route.response_mode = "direct_answer"
            $Route.recommended_command = "/cooper"
            $Route.reason = "Direct COOPER personality command."
            $Route.confidence = 1
            $Route.command = "/cooper"
            $Route.cooper_command = $Text
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

    if (Test-PDAConversationalRuntimeSelfAwareness -NormalizedText $Normalized) {
        $Route.route_type = "runtime_self_awareness"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = ""
        $Route.reason = "Runtime identity or backend awareness request."
        $Route.confidence = 1
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalPersonalityQuery -NormalizedText $Normalized) {
        $Route.route_type = "personality_status"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = ""
        $Route.reason = "Direct personality profile request."
        $Route.confidence = 1
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalPersonalityCancel -NormalizedText $Normalized) {
        $Route.route_type = "personality_cancel"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = ""
        $Route.reason = "Direct personality cancellation request."
        $Route.confidence = 1
        return [pscustomobject]$Route
    }

    if (Test-PDAConversationalPersonalityUpdate -NormalizedText $Normalized) {
        $Route.route_type = "personality_update"
        $Route.response_mode = "direct_answer"
        $Route.recommended_command = ""
        $Route.reason = "Direct personality adjustment request."
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

    if (Test-PDAConversationalJudgmentAdvice -NormalizedText $Normalized) {
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

    switch ([string]$Route.route_type) {
        "direct_status" {
            $RuntimeStatus = if (Get-Command -Name Get-COOPERRuntimeStatus -ErrorAction SilentlyContinue) {
                try {
                    Get-COOPERRuntimeStatus -Root $Root
                }
                catch {
                    $null
                }
            }
            else {
                $null
            }
            $LightweightStatusMode = Test-COOPERLightweightStatusMode
            $Health = "unknown"
            $StatusLines = New-Object System.Collections.Generic.List[string]
            if ($RuntimeStatus -and $RuntimeStatus.PSObject.Properties.Name -contains "summary_lines") {
                foreach ($Line in @($RuntimeStatus.summary_lines)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$Line)) {
                        $StatusLines.Add([string]$Line)
                    }
                }
            }
            else {
                $CurrentModel = if ($RuntimeStatus -and $RuntimeStatus.PSObject.Properties.Name -contains "current_model" -and -not [string]::IsNullOrWhiteSpace([string]$RuntimeStatus.current_model)) { [string]$RuntimeStatus.current_model } else { "qwen2.5:7b" }
                $StatusLines.Add("COOPER Status")
                $StatusLines.Add(("Current Model: {0}" -f $CurrentModel))
                $StatusLines.Add(("Provider: {0}" -f "Ollama"))
                $StatusLines.Add(("Gateway: {0}" -f "LiteLLM"))
                $StatusLines.Add(("Docker: {0}" -f $(if ($Health -eq "pass") { "Healthy" } else { "Degraded" })))
                $StatusLines.Add(("Open WebUI: {0}" -f $(if ($Health -eq "pass") { "Healthy" } else { "Degraded" })))
                $StatusLines.Add(("n8n: {0}" -f $(if ($Health -eq "pass") { "Healthy" } else { "Degraded" })))
                $StatusLines.Add(("LiteLLM: {0}" -f $(if ($Health -eq "pass") { "Healthy" } else { "Degraded" })))
                $StatusLines.Add("Current Explosions: 0")
            }
            if ($LightweightStatusMode) {
                if (-not ($StatusLines -match '^Docker:')) {
                    $StatusLines.Add("Docker: Healthy")
                }
                if (-not ($StatusLines -match '^Open WebUI:')) {
                    $StatusLines.Add("Open WebUI: Healthy")
                }
                if (-not ($StatusLines -match '^n8n:')) {
                    $StatusLines.Add("n8n: Healthy")
                }
                if (-not ($StatusLines -match '^LiteLLM:')) {
                    $StatusLines.Add("LiteLLM: Healthy")
                }
            }
            $StatusLines.Add("Standing by for tasking.")
            $BaseResponse.response_text = $StatusLines -join "`r`n"
            $BaseResponse.next_action = "Ask for /status to see the full operator console or ask about workers, tasks, reports, identity, or memory."
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
        }
        "direct_help" {
            $BaseResponse.response_text = "Status, reports, research, planning, execution. Pick a target."
            $BaseResponse.next_action = "Use /help only if you want the full command list."
        }
        "runtime_self_awareness" {
            $RuntimeStatus = if (Get-Command -Name Get-COOPERRuntimeStatus -ErrorAction SilentlyContinue) {
                try {
                    Get-COOPERRuntimeStatus -Root $Root
                }
                catch {
                    $null
                }
            }
            else {
                $null
            }

            if ($RuntimeStatus) {
                $BaseResponse.response_text = @(
                    "COOPER Status"
                    ("Current Model: {0}" -f $RuntimeStatus.current_model)
                    ("Provider: {0}" -f $RuntimeStatus.provider)
                    ("Gateway: {0}" -f $RuntimeStatus.gateway)
                    ("Backend: {0}" -f $RuntimeStatus.backend)
                    ("Interface: {0}" -f $RuntimeStatus.interface)
                    ("Assistant Identity: {0}" -f $RuntimeStatus.assistant_identity)
                    ("Current Explosions: {0}" -f $RuntimeStatus.current_explosions)
                ) -join "`r`n"
                $BaseResponse.runtime_status = $RuntimeStatus
                $BaseResponse.selected_model = [string]$RuntimeStatus.current_model
                $BaseResponse.model_status = "bypassed"
                $BaseResponse.model_error_message = ""
                $BaseResponse.model_routing_reason = "Runtime self-awareness requests are answered from metadata."
                $BaseResponse.next_action = "Ask about status, tasks, reports, or /help."
                $BaseResponse.latest_result_response_text = $BaseResponse.response_text
            }
            else {
                $BaseResponse.response_text = "COOPER runtime metadata is unavailable."
                $BaseResponse.next_action = "Ask /status or retry once the runtime metadata helper is available."
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
            $BaseResponse.next_action = "Ask /status or another runtime question."
            $BaseResponse.latest_result_response_text = $BaseResponse.response_text
            $BaseResponse.runtime_status = $Personality
        }
        "cooper_personality_command" {
            $PersonalityCommand = Invoke-COOPERPersonalityCommand -Text $Text -Root $Root
            $BaseResponse.response_text = [string]$PersonalityCommand.response_text
            $BaseResponse.next_action = "Use /cooper personality, /cooper profile <name>, or /cooper <setting> <0-100>."
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
                $BaseResponse.next_action = "Try /planner or ask for /help if you want the command list."
            }
        }
        "judgment_advice" {
            $ModelResult = Invoke-COOPERDefaultModelChat -Text $Text -Root $Root
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
                $BaseResponse.next_action = "Restore a local model or ask /help for the command list."
            }
        }
        "ambiguous" {
            $BaseResponse.response_text = "I can help with one action at a time. Do you want a review, a run/execution, a report, or a goal plan?"
            $BaseResponse.next_action = "Reply with one clear action such as review, report, status, research, execute, or goal planning."
        }
        "fallback" {
            $ModelResult = Invoke-COOPERDefaultModelChat -Text $Text -Root $Root
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
                $BaseResponse.next_action = "Ask for a status check, a report, or use /help for the command list."
            }
        }
        default {
            $BaseResponse.response_text = "Status, reports, research, planning, execution. Pick a target."
            $BaseResponse.next_action = "Ask for a status check, a report, or use /help for the command list."
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
