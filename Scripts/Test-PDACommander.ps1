[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$BriefingScript = Join-Path $PSScriptRoot "Get-PDACommanderBriefing.ps1"
$RecommendationScript = Join-Path $PSScriptRoot "Get-PDACommanderRecommendation.ps1"
$BridgeScript = Join-Path $PSScriptRoot "Invoke-PDAChatBridge.ps1"
$DashboardScript = Join-Path $PSScriptRoot "Get-PDADashboardStatus.ps1"
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
if (Test-Path -LiteralPath $ParserPath -PathType Leaf) {
    . $ParserPath
}

function Invoke-PDAJsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $Raw = & pwsh -NoProfile -File $Path @Arguments 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Script returned empty output: $Path"
    }

    return ConvertFrom-PDAMixedJson -Text $Text -SourceName $Path
}

function Assert-PDACondition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][System.Collections.Generic.List[string]]$Issues
    )

    if (-not $Condition -and $Issues) {
        $Issues.Add($Message)
    }

    return $Condition
}

$Issues = New-Object System.Collections.Generic.List[string]

$Briefing = Invoke-PDAJsonScript -Path $BriefingScript -Arguments @("-Root", $Root, "-Focus", "default", "-AsJson")
Assert-PDACondition -Condition ([string]$Briefing.status -in @("pass", "warning")) -Message "Commander briefing did not return a usable status." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (-not [string]::IsNullOrWhiteSpace([string]$Briefing.briefing_text)) -Message "Commander briefing text was empty." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$Briefing.briefing_text -match '(?i)pda daily brief|recommended actions|queue:') -Message "Commander briefing text did not include the expected summary sections." -Issues $Issues | Out-Null

$Recommendation = Invoke-PDAJsonScript -Path $RecommendationScript -Arguments @("-Text", "Build me a roadmap.", "-AsJson")
Assert-PDACondition -Condition ([string]$Recommendation.classification -eq "planning") -Message "Commander recommendation did not classify a roadmap request as planning." -Issues $Issues | Out-Null
Assert-PDACondition -Condition (-not [string]::IsNullOrWhiteSpace([string]$Recommendation.recommended_executor)) -Message "Commander recommendation did not select an executor." -Issues $Issues | Out-Null

$Dashboard = Invoke-PDAJsonScript -Path $DashboardScript -Arguments @("-AsJson", "-NoThrow")
Assert-PDACondition -Condition ($Dashboard.PSObject.Properties.Name -contains "commander_briefing") -Message "Dashboard status did not expose commander briefing data." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($Dashboard.commander_briefing.PSObject.Properties.Name -contains "recommended_actions") -Message "Dashboard commander briefing did not include recommended actions." -Issues $Issues | Out-Null

$ChatCases = @(
    [pscustomobject]@{
        name = "next work"
        message = "What should I work on next?"
        expected_focus = "PDA DAILY BRIEF"
    }
    [pscustomobject]@{
        name = "blocked"
        message = "What is blocked?"
        expected_focus = "Recommended Actions"
    }
    [pscustomobject]@{
        name = "recent changes"
        message = "What changed recently?"
        expected_focus = "Recent Activity"
    }
)

$ChatResults = @()
foreach ($Case in $ChatCases) {
    $ChatResult = Invoke-PDAJsonScript -Path $BridgeScript -Arguments @("-Message", $Case.message, "-AsJson")
    $CaseIssues = New-Object System.Collections.Generic.List[string]
    Assert-PDACondition -Condition ([string]$ChatResult.handoff_status -eq "commander_briefing") -Message "Chat bridge did not route '$($Case.message)' to commander briefing." -Issues $CaseIssues | Out-Null
    Assert-PDACondition -Condition ([string]$ChatResult.dispatch_status -eq "not_applicable") -Message "Commander briefing should not dispatch work." -Issues $CaseIssues | Out-Null
    Assert-PDACondition -Condition ([string]$ChatResult.response_text -match [regex]::Escape($Case.expected_focus)) -Message "Commander briefing response did not include '$($Case.expected_focus)'." -Issues $CaseIssues | Out-Null

    $ChatResults += [pscustomobject]@{
        name = $Case.name
        passed = ($CaseIssues.Count -eq 0)
        handoff_status = [string]$ChatResult.handoff_status
        response_text = [string]$ChatResult.response_text
        issues = @($CaseIssues)
    }

    foreach ($Issue in $CaseIssues) {
        $Issues.Add($Issue)
    }
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    briefing = $Briefing
    recommendation = $Recommendation
    dashboard = [pscustomobject]@{
        status = [string]$Dashboard.status
        commander_briefing_status = [string]$Dashboard.commander_briefing.status
        commander_briefing_actions = @($Dashboard.commander_briefing.recommended_actions).Count
    }
    chat_cases = @($ChatResults)
    issues = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA Commander validation failed."
    }
    return
}

Write-Host "[*] PDA Commander tests"
Write-Host ("Status     : {0}" -f $Report.status)
Write-Host ("Issues     : {0}" -f @($Report.issues).Count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA Commander validation failed."
}
