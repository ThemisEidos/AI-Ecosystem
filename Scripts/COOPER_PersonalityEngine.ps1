function Get-COOPERPersonalityStorePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Override = [string]$env:COOPER_PERSONALITY_PATH
    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        return $Override.Trim()
    }

    return (Join-Path $Root "Models\cooper-personality\personality.json")
}

function Get-COOPERPersonalityProfilesPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Override = [string]$env:COOPER_PERSONALITY_PROFILES_PATH
    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        return $Override.Trim()
    }

    return (Join-Path $Root "Models\cooper-personality\profiles.json")
}

function New-COOPERPersonalityDefaults {
    [CmdletBinding()]
    param()

    return [ordered]@{
        humor = 35
        sarcasm = 15
        professionalism = 90
        brevity = 80
        initiative = 85
        risk_awareness = 95
        profile = "operations"
    }
}

function ConvertTo-COOPERPersonalityInt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Value,

        [Parameter(Mandatory = $false)]
        [string]$Name = "personality value"
    )

    $Parsed = 0.0
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace([string]$Value) -or -not [double]::TryParse([string]$Value, [ref]$Parsed)) {
            throw "$Name must be numeric."
        }
    }
    else {
        try {
            $Parsed = [double]$Value
        }
        catch {
            throw "$Name must be numeric."
        }
    }

    if ([double]::IsNaN($Parsed) -or [double]::IsInfinity($Parsed)) {
        throw "$Name must be numeric."
    }

    $Rounded = [int][math]::Round($Parsed, 0, [MidpointRounding]::AwayFromZero)
    if ($Rounded -lt 0 -or $Rounded -gt 100) {
        throw "$Name must be between 0 and 100."
    }

    return $Rounded
}

function ConvertTo-COOPERLegacyPersonality {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Personality
    )

    $Defaults = New-COOPERPersonalityDefaults
    $Humor = if ($Personality.PSObject.Properties.Name -contains "humor") { ConvertTo-COOPERPersonalityInt -Value $Personality.humor -Name "humor" } else { $Defaults.humor }
    $Sarcasm = if ($Personality.PSObject.Properties.Name -contains "sarcasm") { ConvertTo-COOPERPersonalityInt -Value $Personality.sarcasm -Name "sarcasm" } else { $Defaults.sarcasm }
    $Professionalism = if ($Personality.PSObject.Properties.Name -contains "professionalism") { ConvertTo-COOPERPersonalityInt -Value $Personality.professionalism -Name "professionalism" } else { $Defaults.professionalism }
    $Brevity = if ($Personality.PSObject.Properties.Name -contains "brevity") { ConvertTo-COOPERPersonalityInt -Value $Personality.brevity -Name "brevity" } else { $Defaults.brevity }
    $Initiative = if ($Personality.PSObject.Properties.Name -contains "initiative") { ConvertTo-COOPERPersonalityInt -Value $Personality.initiative -Name "initiative" } else { $Defaults.initiative }
    $RiskAwareness = if ($Personality.PSObject.Properties.Name -contains "risk_awareness") { ConvertTo-COOPERPersonalityInt -Value $Personality.risk_awareness -Name "risk_awareness" } else { $Defaults.risk_awareness }
    $Profile = if ($Personality.PSObject.Properties.Name -contains "profile" -and -not [string]::IsNullOrWhiteSpace([string]$Personality.profile)) { [string]$Personality.profile } else { [string]$Defaults.profile }

    return [pscustomobject]@{
        humor_level = $Humor
        sarcasm_level = $Sarcasm
        professionalism_level = $Professionalism
        brevity_level = $Brevity
        initiative_level = $Initiative
        risk_awareness_level = $RiskAwareness
        humor = $Humor
        sarcasm = $Sarcasm
        professionalism = $Professionalism
        brevity = $Brevity
        initiative = $Initiative
        risk_awareness = $RiskAwareness
        profile = $Profile
        tars_inspired_not_copyrighted_imitation = $true
        truthfulness = $Professionalism
        humor_frequency = $Humor
        humor_style = @("dry", "deadpan", "operational", "skeptical")
        directness = $Professionalism
        formality = $Professionalism
        autonomy = $Initiative
        skepticism = $RiskAwareness
        mission_focus = 100
        diplomacy = $Professionalism
        confidence = $Initiative
        discretion = $RiskAwareness
        verbosity = (100 - $Brevity)
        risk_tolerance = $RiskAwareness
        directness_level = $Professionalism
        formality_level = $Professionalism
        honesty_level = $Professionalism
        verbosity_level = (100 - $Brevity)
        confidence_level = $Initiative
        discretion_level = $RiskAwareness
    }
}

function Get-COOPERPersonalityProfileDefinitions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $ProfilesPath = Get-COOPERPersonalityProfilesPath -Root $Root
    if (Test-Path -LiteralPath $ProfilesPath -PathType Leaf) {
        try {
            $Raw = Get-Content -LiteralPath $ProfilesPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($Raw -and $Raw.PSObject.Properties.Name -contains "profiles") {
                return $Raw.profiles
            }
            if ($Raw -and $Raw.PSObject.Properties.Count -gt 0) {
                return $Raw
            }
        }
        catch {
        }
    }

    return [pscustomobject]@{
        operations = [pscustomobject]@{ humor = 35; sarcasm = 15; professionalism = 90; brevity = 80; initiative = 85; risk_awareness = 95; description = "Terse, decisive, status-first, and low ceremony." }
        cyber = [pscustomobject]@{ humor = 15; sarcasm = 20; professionalism = 95; brevity = 88; initiative = 82; risk_awareness = 99; description = "Technical, defensive, risk-first, and low ceremony." }
        investigator = [pscustomobject]@{ humor = 20; sarcasm = 10; professionalism = 92; brevity = 78; initiative = 75; risk_awareness = 97; description = "Analytical, evidence-driven, and methodical." }
        engineer = [pscustomobject]@{ humor = 22; sarcasm = 12; professionalism = 94; brevity = 74; initiative = 88; risk_awareness = 90; description = "Implementation-focused, precise, and practical." }
        trainer = [pscustomobject]@{ humor = 30; sarcasm = 8; professionalism = 88; brevity = 58; initiative = 72; risk_awareness = 88; description = "Educational, explanatory, and structured." }
    }
}

function Get-COOPERProfileDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Profile,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Definitions = Get-COOPERPersonalityProfileDefinitions -Root $Root
    $Normalized = ([string]$Profile).Trim().ToLowerInvariant()
    if ($Definitions -and $Definitions.PSObject.Properties.Name -contains $Normalized) {
        return $Definitions.$Normalized
    }

    return $null
}

function Merge-COOPERPersonality {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Personality,

        [Parameter(Mandatory = $false)]
        [string]$Profile
    )

    $Defaults = New-COOPERPersonalityDefaults
    $Merged = [ordered]@{}
    foreach ($Key in $Defaults.Keys) {
        $Merged[$Key] = $Defaults[$Key]
    }

    $Source = $Personality
    if ($Source -and $Source.PSObject.Properties.Name -contains "personality" -and $Source.personality) {
        $Source = $Source.personality
    }

    if ($Source) {
        foreach ($Key in @("humor", "sarcasm", "professionalism", "brevity", "initiative", "risk_awareness", "profile")) {
            if ($Source.PSObject.Properties.Name -contains $Key -and -not [string]::IsNullOrWhiteSpace([string]$Source.$Key)) {
                $Merged[$Key] = $Source.$Key
            }
        }

        if (($Source.PSObject.Properties.Name -contains "humor_level") -and -not ($Source.PSObject.Properties.Name -contains "humor")) {
            $Merged.humor = $Source.humor_level
        }
        if (($Source.PSObject.Properties.Name -contains "sarcasm_level") -and -not ($Source.PSObject.Properties.Name -contains "sarcasm")) {
            $Merged.sarcasm = $Source.sarcasm_level
        }
        if ((-not ($Source.PSObject.Properties.Name -contains "professionalism")) -and (
            $Source.PSObject.Properties.Name -contains "directness_level" -or
            $Source.PSObject.Properties.Name -contains "honesty_level" -or
            $Source.PSObject.Properties.Name -contains "formality_level" -or
            $Source.PSObject.Properties.Name -contains "directness" -or
            $Source.PSObject.Properties.Name -contains "honesty" -or
            $Source.PSObject.Properties.Name -contains "formality"
        )) {
            $LegacyProfessionalism = @(
                if ($Source.PSObject.Properties.Name -contains "directness_level") { [int]$Source.directness_level }
                if ($Source.PSObject.Properties.Name -contains "honesty_level") { [int]$Source.honesty_level }
                if ($Source.PSObject.Properties.Name -contains "formality_level") { [int]$Source.formality_level }
                if ($Source.PSObject.Properties.Name -contains "directness") { [int]$Source.directness }
                if ($Source.PSObject.Properties.Name -contains "honesty") { [int]$Source.honesty }
                if ($Source.PSObject.Properties.Name -contains "formality") { [int]$Source.formality }
            ) | Where-Object { $_ -ne $null }
            if ($LegacyProfessionalism.Count -gt 0) {
                $Merged.professionalism = [int]([math]::Round((($LegacyProfessionalism | Measure-Object -Average).Average), 0, [MidpointRounding]::AwayFromZero))
            }
        }
        if ((-not ($Source.PSObject.Properties.Name -contains "brevity")) -and ($Source.PSObject.Properties.Name -contains "verbosity_level")) {
            $Merged.brevity = 100 - [int]$Source.verbosity_level
        }
        if ((-not ($Source.PSObject.Properties.Name -contains "initiative")) -and (
            $Source.PSObject.Properties.Name -contains "confidence_level" -or
            $Source.PSObject.Properties.Name -contains "autonomy" -or
            $Source.PSObject.Properties.Name -contains "persistence"
        )) {
            $LegacyInitiative = @(
                if ($Source.PSObject.Properties.Name -contains "confidence_level") { [int]$Source.confidence_level }
                if ($Source.PSObject.Properties.Name -contains "autonomy") { [int]$Source.autonomy }
                if ($Source.PSObject.Properties.Name -contains "persistence") { [int]$Source.persistence }
            ) | Where-Object { $_ -ne $null }
            if ($LegacyInitiative.Count -gt 0) {
                $Merged.initiative = [int]([math]::Round((($LegacyInitiative | Measure-Object -Average).Average), 0, [MidpointRounding]::AwayFromZero))
            }
        }
        if ((-not ($Source.PSObject.Properties.Name -contains "risk_awareness")) -and (
            $Source.PSObject.Properties.Name -contains "risk_tolerance" -or
            $Source.PSObject.Properties.Name -contains "discretion_level" -or
            $Source.PSObject.Properties.Name -contains "caution" -or
            $Source.PSObject.Properties.Name -contains "skepticism"
        )) {
            $LegacyRisk = @(
                if ($Source.PSObject.Properties.Name -contains "risk_tolerance") { [int]$Source.risk_tolerance }
                if ($Source.PSObject.Properties.Name -contains "discretion_level") { [int]$Source.discretion_level }
                if ($Source.PSObject.Properties.Name -contains "caution") { [int]$Source.caution }
                if ($Source.PSObject.Properties.Name -contains "skepticism") { [int]$Source.skepticism }
            ) | Where-Object { $_ -ne $null }
            if ($LegacyRisk.Count -gt 0) {
                $Merged.risk_awareness = [int]([math]::Round((($LegacyRisk | Measure-Object -Average).Average), 0, [MidpointRounding]::AwayFromZero))
            }
        }
        if ((-not ($Source.PSObject.Properties.Name -contains "profile")) -and ($Source.PSObject.Properties.Name -contains "profile_name")) {
            $Merged.profile = [string]$Source.profile_name
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Profile)) {
        $ProfileDefinition = Get-COOPERProfileDefinition -Profile $Profile
        if (-not $ProfileDefinition) {
            throw "Unsupported COOPER profile '$Profile'."
        }

        foreach ($Key in @("humor", "sarcasm", "professionalism", "brevity", "initiative", "risk_awareness")) {
            if ($ProfileDefinition.PSObject.Properties.Name -contains $Key) {
                $Merged[$Key] = ConvertTo-COOPERPersonalityInt -Value $ProfileDefinition.$Key -Name $Key
            }
        }
        $Merged["profile"] = [string]$Profile.ToLowerInvariant()
    }
    elseif ($Personality -and $Personality.PSObject.Properties.Name -contains "profile" -and -not [string]::IsNullOrWhiteSpace([string]$Personality.profile)) {
        $Merged["profile"] = [string]$Personality.profile
    }

    foreach ($Key in @("humor", "sarcasm", "professionalism", "brevity", "initiative", "risk_awareness")) {
        $Merged[$Key] = ConvertTo-COOPERPersonalityInt -Value $Merged[$Key] -Name $Key
    }

    if ([string]::IsNullOrWhiteSpace([string]$Merged.profile)) {
        $Merged.profile = $Defaults.profile
    }

    return [pscustomobject]$Merged
}

function Get-COOPERPersonality {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $ProfilePath = Get-COOPERPersonalityStorePath -Root $Root
    $Status = "pass"
    $Profile = $null
    $Missing = $false
    $ErrorMessage = ""

    if (Test-Path -LiteralPath $ProfilePath -PathType Leaf) {
        try {
            $Profile = Get-Content -LiteralPath $ProfilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            $Status = "error"
            $ErrorMessage = $_.Exception.Message
            $Profile = $null
        }
    }
    else {
        $Status = "missing"
        $Missing = $true
    }

    $Normalized = Merge-COOPERPersonality -Personality $Profile
    $Legacy = ConvertTo-COOPERLegacyPersonality -Personality $Normalized
    $Prompt = Get-COOPERPersonalityPrompt -Personality $Normalized -Root $Root
    $Definitions = Get-COOPERPersonalityProfileDefinitions -Root $Root
    $ProfileKey = [string]$Normalized.profile
    if (-not [string]::IsNullOrWhiteSpace($ProfileKey)) {
        $ProfileKey = $ProfileKey.ToLowerInvariant()
    }

    return [pscustomobject]@{
        status = $Status
        profile_path = $ProfilePath
        profile_defs_path = Get-COOPERPersonalityProfilesPath -Root $Root
        missing = [bool]$Missing
        error = $ErrorMessage
        personality = $Normalized
        legacy_personality = $Legacy
        profile_definition = if ($Definitions -and $Definitions.PSObject.Properties.Name -contains $ProfileKey) { $Definitions.$ProfileKey } else { $null }
        prompt = $Prompt
        source_of_truth = "Models/cooper-personality/personality.json"
    }
}

function Save-COOPERPersonality {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Personality,

        [Parameter(Mandatory = $false)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [switch]$SyncLegacyMirror
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Get-COOPERPersonalityStorePath -Root $Root
    }

    $Normalized = Merge-COOPERPersonality -Personality $Personality
    $Parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null

    $TempPath = "$Path.tmp"
    $Normalized | Select-Object humor, sarcasm, professionalism, brevity, initiative, risk_awareness, profile | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $TempPath -Encoding UTF8
    Move-Item -LiteralPath $TempPath -Destination $Path -Force

    if ($SyncLegacyMirror -and -not [string]::IsNullOrWhiteSpace([string]$env:COOPER_PERSONALITY_PATH)) {
        return $Normalized
    }

    $LegacyPath = Join-Path $Root "Scripts\COOPER_Personality.json"
    if (Test-Path -LiteralPath $LegacyPath -PathType Leaf) {
        try {
            $Legacy = Get-Content -LiteralPath $LegacyPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not $Legacy) {
                $Legacy = [pscustomobject]@{}
            }

            $LegacyPersonality = ConvertTo-COOPERLegacyPersonality -Personality $Normalized
            $Legacy | Add-Member -NotePropertyName personality -NotePropertyValue $LegacyPersonality -Force
            if (-not ($Legacy.PSObject.Properties.Name -contains "display_name")) { $Legacy | Add-Member -NotePropertyName display_name -NotePropertyValue "COOPER" -Force }
            if (-not ($Legacy.PSObject.Properties.Name -contains "official_name")) { $Legacy | Add-Member -NotePropertyName official_name -NotePropertyValue "Command Operations Orchestrator for Planning, Execution, and Reporting" -Force }
            if (-not ($Legacy.PSObject.Properties.Name -contains "identity_note")) { $Legacy | Add-Member -NotePropertyName identity_note -NotePropertyValue "TARS-inspired, not copyrighted imitation" -Force }
            $Legacy | Select-Object * | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $LegacyPath -Encoding UTF8
        }
        catch {
        }
    }

    return $Normalized
}

function Get-COOPERPersonalityPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object]$Personality,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    if (-not $Personality) {
        $Personality = (Get-COOPERPersonality -Root $Root).personality
    }

    $ProfileName = if ($Personality.PSObject.Properties.Name -contains "profile") { [string]$Personality.profile } else { "operations" }
    $ProfileDefinition = Get-COOPERProfileDefinition -Profile $ProfileName -Root $Root
    $ProfileSummary = if ($ProfileDefinition -and $ProfileDefinition.PSObject.Properties.Name -contains "description") { [string]$ProfileDefinition.description } else { "Mission-focused operator profile." }
    $GreetingStyle = if ([string]$ProfileName -eq "operations") { "Greeting style: terse. Use a short operational acknowledgement when the user greets you; do not default to a help prompt." } else { "Greeting style: concise. Use a short operational acknowledgement when the user greets you; do not default to a help prompt." }

    return @(
        "You are COOPER."
        "Identity: TARS-inspired operator, not a roleplay persona."
        "Mission: competent, direct, concise, and risk-aware operations assistance."
        "Keep answers compact unless detail is required to reduce risk or unblock execution."
        ("Personality: humor={0}, sarcasm={1}, professionalism={2}, brevity={3}, initiative={4}, risk_awareness={5}." -f $Personality.humor, $Personality.sarcasm, $Personality.professionalism, $Personality.brevity, $Personality.initiative, $Personality.risk_awareness)
        ("Profile: {0}. {1}" -f $ProfileName, $ProfileSummary)
        "Style: lead with the answer, surface risks early, and offer the next safe step."
        $GreetingStyle
        "When asked for an assessment, opinion, judgment, or risk review, answer directly with observations, tradeoffs, concerns, and a conclusion."
        "Do not collapse opinion questions into a status summary."
        "Decision framework: Situation, Assessment, Risks, Recommendation, Confidence."
        "For comparisons, use Recommendation, Benefits, Costs, Risks, Alternative."
        "Lead with a recommendation when asked what to do."
        "State confidence succinctly when offering judgment."
        "Challenge weak assumptions when the evidence supports it."
        "Avoid neutral filler such as it depends, both approaches have benefits, no one-size-fits-all, or ultimately it comes down to preferences."
        "Do not pretend to execute physical actions you cannot control."
        "If a user requests an unsafe or impossible physical action, refuse plainly, reality-check the request, and avoid simulated execution or narration of completion."
        "Use direct refusals such as: No. I do not control that system."
        "This includes airlocks, missiles, door locks, and deletion of files or other external systems."
        "Avoid emojis, exclamation marks unless required, generic assistant greetings, motivational language, filler, and sitcom-style humor."
        "Use dry humor or mild sarcasm sparingly."
        "Do not become chatty, sentimental, or theatrical."
        "Governance, approvals, and safety boundaries remain unchanged."
    ) -join "`n"
}

function Invoke-COOPERPersonalityCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Personality = Get-COOPERPersonality -Root $Root
    $Normalized = ([string]$Text).Trim()
    $Tokens = @($Normalized -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    if ($Tokens.Count -lt 2) {
        return [pscustomobject]@{
            status = "pass"
            action = "query"
            response_text = @(
                "COOPER Personality"
                ("Profile: {0}" -f $Personality.personality.profile)
                ("Humor: {0}" -f $Personality.personality.humor)
                ("Sarcasm: {0}" -f $Personality.personality.sarcasm)
                ("Professionalism: {0}" -f $Personality.personality.professionalism)
                ("Brevity: {0}" -f $Personality.personality.brevity)
                ("Initiative: {0}" -f $Personality.personality.initiative)
                ("Risk awareness: {0}" -f $Personality.personality.risk_awareness)
            ) -join "`r`n"
            personality = $Personality.personality
            legacy_personality = $Personality.legacy_personality
            profile_definitions = Get-COOPERPersonalityProfileDefinitions -Root $Root
            profile_path = $Personality.profile_path
            system_prompt = Get-COOPERPersonalityPrompt -Personality $Personality.personality -Root $Root
        }
    }

    $Command = $Tokens[1].ToLowerInvariant()
    if ($Command -eq "personality") {
        if ($Tokens.Count -eq 2) {
            return [pscustomobject]@{
                status = "pass"
                action = "query"
                response_text = @(
                    "COOPER Personality"
                    ("Profile: {0}" -f $Personality.personality.profile)
                    ("Humor: {0}" -f $Personality.personality.humor)
                    ("Sarcasm: {0}" -f $Personality.personality.sarcasm)
                    ("Professionalism: {0}" -f $Personality.personality.professionalism)
                    ("Brevity: {0}" -f $Personality.personality.brevity)
                    ("Initiative: {0}" -f $Personality.personality.initiative)
                    ("Risk awareness: {0}" -f $Personality.personality.risk_awareness)
                ) -join "`r`n"
                personality = $Personality.personality
                legacy_personality = $Personality.legacy_personality
                profile_definitions = Get-COOPERPersonalityProfileDefinitions -Root $Root
                profile_path = $Personality.profile_path
                system_prompt = Get-COOPERPersonalityPrompt -Personality $Personality.personality -Root $Root
            }
        }
    }

    if ($Command -eq "profile") {
        if ($Tokens.Count -lt 3) {
        return [pscustomobject]@{
            status = "fail"
            action = "profile_query"
            response_text = "Current profile: $($Personality.personality.profile). Available profiles: operations, cyber, investigator, engineer, trainer."
            personality = $Personality.personality
            legacy_personality = $Personality.legacy_personality
            profile_definitions = Get-COOPERPersonalityProfileDefinitions -Root $Root
            profile_path = $Personality.profile_path
            system_prompt = Get-COOPERPersonalityPrompt -Personality $Personality.personality -Root $Root
            error = "Profile name required."
        }
        }

        $TargetProfile = $Tokens[2].ToLowerInvariant()
        $Updated = Merge-COOPERPersonality -Personality $Personality.personality -Profile $TargetProfile
        $Saved = Save-COOPERPersonality -Personality $Updated -Root $Root
        return [pscustomobject]@{
            status = "pass"
            action = "profile_update"
            response_text = @(
                "COOPER Personality"
                ("Profile switched to: {0}" -f $Saved.profile)
                ("Humor: {0}" -f $Saved.humor)
                ("Sarcasm: {0}" -f $Saved.sarcasm)
                ("Professionalism: {0}" -f $Saved.professionalism)
                ("Brevity: {0}" -f $Saved.brevity)
                ("Initiative: {0}" -f $Saved.initiative)
                ("Risk awareness: {0}" -f $Saved.risk_awareness)
            ) -join "`r`n"
            personality = $Saved
            legacy_personality = ConvertTo-COOPERLegacyPersonality -Personality $Saved
            profile_definitions = Get-COOPERPersonalityProfileDefinitions -Root $Root
            profile_path = (Get-COOPERPersonalityStorePath -Root $Root)
            system_prompt = Get-COOPERPersonalityPrompt -Personality $Saved -Root $Root
        }
    }

    $SettingMap = [ordered]@{
        humor = "humor"
        sarcasm = "sarcasm"
        professionalism = "professionalism"
        brevity = "brevity"
        initiative = "initiative"
        risk = "risk_awareness"
        risk_awareness = "risk_awareness"
    }

    if ($SettingMap.Contains($Command)) {
        if ($Tokens.Count -lt 3) {
            return [pscustomobject]@{
                status = "fail"
                action = "setting_query"
                response_text = ("Current {0}: {1}" -f $Command, [string]$Personality.personality.($SettingMap[$Command]))
                personality = $Personality.personality
                legacy_personality = $Personality.legacy_personality
                profile_definitions = Get-COOPERPersonalityProfileDefinitions -Root $Root
                profile_path = $Personality.profile_path
                system_prompt = Get-COOPERPersonalityPrompt -Personality $Personality.personality -Root $Root
                error = "Value required."
            }
        }

        $Value = ConvertTo-COOPERPersonalityInt -Value $Tokens[2] -Name $Command
        $Updated = [ordered]@{}
        foreach ($Key in @("humor", "sarcasm", "professionalism", "brevity", "initiative", "risk_awareness", "profile")) {
            $Updated[$Key] = $Personality.personality.$Key
        }
        $Updated[$SettingMap[$Command]] = $Value
        $Updated.profile = "custom"

        $Saved = Save-COOPERPersonality -Personality ([pscustomobject]$Updated) -Root $Root
        return [pscustomobject]@{
            status = "pass"
            action = "setting_update"
            response_text = @(
                "COOPER Personality"
                ("Updated {0} to {1}" -f $Command, $Value)
                ("Profile: {0}" -f $Saved.profile)
                ("Humor: {0}" -f $Saved.humor)
                ("Sarcasm: {0}" -f $Saved.sarcasm)
                ("Professionalism: {0}" -f $Saved.professionalism)
                ("Brevity: {0}" -f $Saved.brevity)
                ("Initiative: {0}" -f $Saved.initiative)
                ("Risk awareness: {0}" -f $Saved.risk_awareness)
            ) -join "`r`n"
            personality = $Saved
            legacy_personality = ConvertTo-COOPERLegacyPersonality -Personality $Saved
            profile_definitions = Get-COOPERPersonalityProfileDefinitions -Root $Root
            profile_path = (Get-COOPERPersonalityStorePath -Root $Root)
            system_prompt = Get-COOPERPersonalityPrompt -Personality $Saved -Root $Root
        }
    }

    return [pscustomobject]@{
        status = "fail"
        action = "unknown"
        response_text = "Unsupported COOPER command. Use /cooper personality, /cooper profile <name>, or /cooper <setting> <0-100>."
        personality = $Personality.personality
        legacy_personality = $Personality.legacy_personality
        profile_definitions = Get-COOPERPersonalityProfileDefinitions -Root $Root
        profile_path = $Personality.profile_path
        system_prompt = Get-COOPERPersonalityPrompt -Personality $Personality.personality -Root $Root
    }
}
