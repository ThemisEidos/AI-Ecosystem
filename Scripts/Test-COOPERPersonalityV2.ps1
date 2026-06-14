[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$GetScript = Join-Path $PSScriptRoot "Get-COOPERPersonality.ps1"
$SetScript = Join-Path $PSScriptRoot "Set-COOPERPersonality.ps1"
$InterpreterScript = Join-Path $PSScriptRoot "PDA_CommandInterpreter.ps1"
$EngineScript = Join-Path $PSScriptRoot "COOPER_PersonalityEngine.ps1"

foreach ($Path in @($GetScript, $SetScript, $InterpreterScript, $EngineScript)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required personality test dependency missing: $Path"
    }
}

. $EngineScript

$TempRoot = Join-Path $Root "tmp\cooper-personality-v2"
$TempProfilePath = Join-Path $TempRoot "personality.json"
$TempProfilesPath = Join-Path $TempRoot "profiles.json"
$ModelProfilePath = Join-Path $Root "Models\cooper-personality\personality.json"
$LegacyMirrorPath = Join-Path $Root "Scripts\COOPER_Personality.json"
$LegacyMirrorBackupPath = Join-Path $TempRoot "COOPER_Personality.json.backup"
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $Root "Models\cooper-personality\personality.json") -Destination $TempProfilePath -Force
Copy-Item -LiteralPath (Join-Path $Root "Models\cooper-personality\profiles.json") -Destination $TempProfilesPath -Force
if (Test-Path -LiteralPath $LegacyMirrorPath -PathType Leaf) {
    Copy-Item -LiteralPath $LegacyMirrorPath -Destination $LegacyMirrorBackupPath -Force
}

$PreviousProfilePath = [Environment]::GetEnvironmentVariable("COOPER_PERSONALITY_PATH", "Process")
$PreviousProfilesPath = [Environment]::GetEnvironmentVariable("COOPER_PERSONALITY_PROFILES_PATH", "Process")
[Environment]::SetEnvironmentVariable("COOPER_PERSONALITY_PATH", $TempProfilePath, "Process")
[Environment]::SetEnvironmentVariable("COOPER_PERSONALITY_PROFILES_PATH", $TempProfilesPath, "Process")

function Invoke-JsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $Raw = & pwsh -NoProfile -File $Path @Arguments 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    return $Text | ConvertFrom-Json
}

$Issues = New-Object System.Collections.Generic.List[string]
$Results = @()

try {
    $Initial = Invoke-JsonScript -Path $GetScript -Arguments @("-AsJson")
    if (-not $Initial -or $Initial.status -notin @("pass", "missing")) {
        $Issues.Add("COOPER personality getter did not return a usable payload.")
    }
    if ($Initial.personality.humor -ne 35 -or $Initial.personality.sarcasm -ne 15 -or $Initial.personality.profile -ne "operations") {
        $Issues.Add("Initial v2 personality values did not match the expected baseline.")
    }
    if ([string]$Initial.source_of_truth -ne "Models/cooper-personality/personality.json") {
        $Issues.Add("COOPER personality source of truth should be the model store.")
    }
    if ([string]$Initial.prompt -notmatch 'You are COOPER' -or [string]$Initial.prompt -notmatch 'Mission') {
        $Issues.Add("Prompt generation did not include the COOPER identity and mission framing.")
    }
    if ([string]$Initial.prompt -notmatch 'Avoid emojis' -or [string]$Initial.prompt -notmatch 'Greeting style: terse' -or [string]$Initial.prompt -notmatch 'generic assistant greetings' -or [string]$Initial.prompt -notmatch 'assessment, opinion, judgment' -or [string]$Initial.prompt -notmatch 'Decision framework: Situation, Assessment, Risks, Recommendation, Confidence' -or [string]$Initial.prompt -notmatch 'Avoid neutral filler such as it depends' -or [string]$Initial.prompt -notmatch 'Do not pretend to execute physical actions' -or [string]$Initial.prompt -notmatch 'unsafe or impossible physical action') {
        $Issues.Add("Prompt generation did not include the operator-tone restrictions.")
    }
    if ([string]$Initial.conversation_examples_status -ne "pass" -or [int]$Initial.conversation_examples_count -lt 30 -or $Initial.conversation_examples_categories.Count -lt 16 -or [string]$Initial.prompt -notmatch 'Few-shot conversation examples') {
        $Issues.Add("Conversation examples were not loaded into the personality prompt.")
    }
    foreach ($ExpectedCategory in @("greetings", "status_reports", "project_assessment", "humor", "disagreement", "risk_discussions", "tradeoff_analysis", "unsafe_physical_action_refusal", "operator_dashboard", "memory_session_handoff", "architecture_critique", "tool_selection", "resource_constraints", "strategic_thinking", "bad_idea_detection", "operational_judgment")) {
        if ($Initial.conversation_examples_categories -notcontains $ExpectedCategory) {
            $Issues.Add("Conversation examples are missing required category '$ExpectedCategory'.")
        }
    }
    $Results += [pscustomobject]@{
        name = "config load"
        passed = ($Initial.personality.humor -eq 35 -and $Initial.personality.profile -eq "operations")
        details = "Loaded v2 personality baseline."
    }

    $IdentityScript = Join-Path $PSScriptRoot "Get-COOPERIdentity.ps1"
    $IdentityRaw = & pwsh -NoProfile -Command (". '{0}'; Get-COOPERIdentity -Root '{1}' | ConvertTo-Json -Depth 8" -f ($IdentityScript -replace "'", "''"), ($Root -replace "'", "''")) 2>&1
    $IdentityText = [string]($IdentityRaw -join "`n").Trim()
    $Identity = if ([string]::IsNullOrWhiteSpace($IdentityText)) { $null } else { $IdentityText | ConvertFrom-Json }
    if ($Identity.status -eq "error") {
        $Issues.Add("Direct COOPER identity invocation still fails.")
    }
    if ($Identity.profile_path -ne $ModelProfilePath) {
        $Issues.Add("Direct COOPER identity invocation did not resolve the model personality path.")
    }
    if ($Identity.personality.profile -ne "operations") {
        $Issues.Add("Direct COOPER identity invocation did not report the operations baseline.")
    }
    $Results += [pscustomobject]@{
        name = "identity invocation"
        passed = ($Identity.status -ne "error" -and $Identity.personality.profile -eq "operations")
        details = "Direct identity helper invocation succeeded."
    }

    $ProfileSwitch = Invoke-JsonScript -Path $SetScript -Arguments @("-Profile", "cyber", "-AsJson")
    if ($ProfileSwitch.status -ne "pass" -or $ProfileSwitch.current.profile -ne "cyber") {
        $Issues.Add("Profile switching to cyber did not succeed.")
    }
    if ([int]$ProfileSwitch.current.risk_awareness -lt 95 -or [int]$ProfileSwitch.current.professionalism -lt 90) {
        $Issues.Add("Cyber profile did not apply the expected slider values.")
    }
    $Results += [pscustomobject]@{
        name = "profile switch"
        passed = ($ProfileSwitch.status -eq "pass" -and $ProfileSwitch.current.profile -eq "cyber")
        details = "Cyber profile applied."
    }

    $PromptAfterProfile = Invoke-JsonScript -Path $GetScript -Arguments @("-AsJson")
    if ([string]$PromptAfterProfile.prompt -notmatch 'cyber' -or [string]$PromptAfterProfile.prompt -notmatch 'risk' -or [string]$PromptAfterProfile.prompt -notmatch 'Greeting style: concise' -or [string]$PromptAfterProfile.prompt -notmatch 'assessment, opinion, judgment' -or [string]$PromptAfterProfile.prompt -notmatch 'Decision framework: Situation, Assessment, Risks, Recommendation, Confidence' -or [string]$PromptAfterProfile.prompt -notmatch 'Do not pretend to execute physical actions') {
        $Issues.Add("Prompt generation did not reflect the active profile.")
    }
    if ($PromptAfterProfile.conversation_examples_status -ne "pass" -or [int]$PromptAfterProfile.conversation_examples_count -lt 30) {
        $Issues.Add("Conversation examples were not reported after profile switching.")
    }
    $Results += [pscustomobject]@{
        name = "prompt generation"
        passed = ([string]$PromptAfterProfile.prompt -match 'cyber')
        details = "Prompt updated after profile switch."
    }

    $MissingExamplesPath = Join-Path $TempRoot "missing-conversation-examples.json"
    $PreviousExamplesPath = [Environment]::GetEnvironmentVariable("COOPER_CONVERSATION_EXAMPLES_PATH", "Process")
    try {
        [Environment]::SetEnvironmentVariable("COOPER_CONVERSATION_EXAMPLES_PATH", $MissingExamplesPath, "Process")
        $MissingExamples = Invoke-JsonScript -Path $GetScript -Arguments @("-AsJson")
        if ([string]$MissingExamples.conversation_examples_status -ne "missing") {
            $Issues.Add("Missing conversation examples file did not report a missing status.")
        }
        if ([string]$MissingExamples.prompt -notmatch 'You are COOPER' -or [string]$MissingExamples.prompt -match 'Few-shot conversation examples') {
            $Issues.Add("Missing conversation examples should not break the core prompt.")
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable("COOPER_CONVERSATION_EXAMPLES_PATH", $PreviousExamplesPath, "Process")
    }

    $InvalidExamplesPath = Join-Path $TempRoot "invalid-conversation-examples.json"
    Set-Content -LiteralPath $InvalidExamplesPath -Value '{ not valid json' -Encoding UTF8
    $PreviousExamplesPath = [Environment]::GetEnvironmentVariable("COOPER_CONVERSATION_EXAMPLES_PATH", "Process")
    try {
        [Environment]::SetEnvironmentVariable("COOPER_CONVERSATION_EXAMPLES_PATH", $InvalidExamplesPath, "Process")
        $InvalidExamples = Invoke-JsonScript -Path $GetScript -Arguments @("-AsJson")
        if ([string]$InvalidExamples.conversation_examples_status -ne "error") {
            $Issues.Add("Invalid conversation examples JSON did not report an error status.")
        }
        if ([string]$InvalidExamples.prompt -notmatch 'You are COOPER') {
            $Issues.Add("Invalid conversation examples JSON should not break personality prompt generation.")
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable("COOPER_CONVERSATION_EXAMPLES_PATH", $PreviousExamplesPath, "Process")
    }

    $CommandProfile = Invoke-JsonScript -Path $InterpreterScript -Arguments @("-Text", "/cooper profile engineer", "-AsJson")
    if ($CommandProfile.status -ne "mapped" -or $CommandProfile.command -notmatch '^/cooper profile') {
        $Issues.Add("Command parser did not recognize /cooper profile engineer.")
    }
    $CommandHumor = Invoke-JsonScript -Path $InterpreterScript -Arguments @("-Text", "/cooper humor 50", "-AsJson")
    if ($CommandHumor.status -ne "mapped" -or $CommandHumor.command -notmatch '^/cooper humor') {
        $Issues.Add("Command parser did not recognize /cooper humor 50.")
    }
    $Results += [pscustomobject]@{
        name = "command parsing"
        passed = ($CommandProfile.status -eq "mapped" -and $CommandHumor.status -eq "mapped")
        details = "Direct /cooper commands resolved."
    }

    $UpdateHumor = Invoke-JsonScript -Path $SetScript -Arguments @("-Humor", "50", "-AsJson")
    if ($UpdateHumor.status -ne "pass" -or [int]$UpdateHumor.current.humor -ne 50) {
        $Issues.Add("Humor update did not persist to disk.")
    }
    $Reload = Get-Content -LiteralPath $TempProfilePath -Raw | ConvertFrom-Json
    if ([int]$Reload.humor -ne 50) {
        $Issues.Add("Persisted personality file did not contain the updated humor value.")
    }
    if ($Reload.profile -ne "custom") {
        $Issues.Add("Manual slider updates should mark the profile as custom.")
    }
    $Results += [pscustomobject]@{
        name = "persistence"
        passed = ([int]$Reload.humor -eq 50)
        details = "Disk persistence verified."
    }

    $Invalid = & pwsh -NoProfile -File $SetScript -Humor 250 -AsJson -NoThrow 2>&1
    $InvalidText = [string]($Invalid -join "`n").Trim()
    $InvalidResult = $InvalidText | ConvertFrom-Json
    if ($InvalidResult.status -eq "pass") {
        $Issues.Add("Out-of-range validation did not fail.")
    }
    $Results += [pscustomobject]@{
        name = "validation"
        passed = ($InvalidResult.status -ne "pass")
        details = [string]$InvalidResult.message
    }
}
finally {
    [Environment]::SetEnvironmentVariable("COOPER_PERSONALITY_PATH", $PreviousProfilePath, "Process")
    [Environment]::SetEnvironmentVariable("COOPER_PERSONALITY_PROFILES_PATH", $PreviousProfilesPath, "Process")
    if (Test-Path -LiteralPath $LegacyMirrorBackupPath -PathType Leaf) {
        Copy-Item -LiteralPath $LegacyMirrorBackupPath -Destination $LegacyMirrorPath -Force
    }
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    test_case_count = @($Results).Count
    passed_count = @($Results | Where-Object { $_.passed }).Count
    failed_count = @($Results | Where-Object { -not $_.passed }).Count
    results = @($Results)
    issues = @($Issues)
    profile_path = $TempProfilePath
    profiles_path = $TempProfilesPath
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "COOPER personality v2 validation failed."
    }
    return
}

Write-Host "[*] COOPER personality v2 validation"
Write-Host ("Test cases : {0}" -f $Report.test_case_count)
Write-Host ("Passed     : {0}" -f $Report.passed_count)
Write-Host ("Failed     : {0}" -f $Report.failed_count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "COOPER personality v2 validation failed."
}
