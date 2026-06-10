[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$RunRegression,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "PDA_OutputParsing.ps1")

$Root = Split-Path -Parent $PSScriptRoot
$EnvironmentHelperScript = Join-Path $PSScriptRoot "PDA_Environment.ps1"
$FilesystemScript = Join-Path $PSScriptRoot "Get-PDAFilesystemInventory.ps1"
$RepositoryScript = Join-Path $PSScriptRoot "Get-PDARepositoryInventory.ps1"
$DockerScript = Join-Path $PSScriptRoot "Get-PDADockerInventory.ps1"
$ServiceScript = Join-Path $PSScriptRoot "Get-PDAServiceInventory.ps1"
$ToolScript = Join-Path $PSScriptRoot "Get-PDAToolInventory.ps1"
$SummaryScript = Join-Path $PSScriptRoot "Get-PDAEnvironmentSummary.ps1"
$RecommendationScript = Join-Path $PSScriptRoot "Get-PDAFileOrganizationRecommendation.ps1"
$RouterScript = Join-Path $PSScriptRoot "COOPER_ConversationalRouter.ps1"
$BridgeScript = Join-Path $PSScriptRoot "Invoke-PDAChatBridge.ps1"
$DashboardStatusScript = Join-Path $PSScriptRoot "Get-PDADashboardStatus.ps1"
$UpdateDashboardScript = Join-Path $PSScriptRoot "Update-PDADashboard.ps1"

if (Test-Path -LiteralPath $EnvironmentHelperScript -PathType Leaf) {
    . $EnvironmentHelperScript
}

function Invoke-PDAJsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $Raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Script returned empty output: $Path"
    }

    return ConvertFrom-PDAMixedJson -Text $Text -SourceName $Path
}

function Invoke-PDAPlainScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments | Out-Null
    return [pscustomobject]@{
        path = $Path
        exit_code = $LASTEXITCODE
        passed = ($LASTEXITCODE -eq 0)
    }
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
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pda-env-awareness-{0}" -f ([guid]::NewGuid().ToString("N")))

try {
    New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $TempRoot "Projects\Alpha") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $TempRoot "Archives\2023") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $TempRoot "Resources\Docs") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $TempRoot "Inbox") | Out-Null
    "alpha" | Set-Content -LiteralPath (Join-Path $TempRoot "Projects\Alpha\duplicate.txt") -Encoding UTF8
    "archive" | Set-Content -LiteralPath (Join-Path $TempRoot "Archives\2023\duplicate.txt") -Encoding UTF8
    "readme" | Set-Content -LiteralPath (Join-Path $TempRoot "README.md") -Encoding UTF8
    "notes" | Set-Content -LiteralPath (Join-Path $TempRoot "Resources\Docs\notes.txt") -Encoding UTF8

    $Filesystem = Invoke-PDAJsonScript -Path $FilesystemScript -Arguments @("-Roots", $TempRoot, "-AsJson", "-NoThrow")
    Assert-PDACondition -Condition ([string]$Filesystem.status -in @("pass", "warning")) -Message "Filesystem inventory did not return a usable status." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition (@($Filesystem.roots).Count -eq 1) -Message "Filesystem inventory did not return the requested root." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition (@($Filesystem.roots[0].top_level_categories).Count -ge 3) -Message "Filesystem inventory did not identify top-level categories." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition (@($Filesystem.roots[0].likely_projects).Count -ge 1) -Message "Filesystem inventory did not identify a likely project location." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition (@($Filesystem.roots[0].likely_archives).Count -ge 1) -Message "Filesystem inventory did not identify a likely archive location." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition (@($Filesystem.roots[0].duplicate_indicators).Count -ge 1) -Message "Filesystem inventory did not detect duplicate filename indicators." -Issues $Issues | Out-Null

    $Repository = Invoke-PDAJsonScript -Path $RepositoryScript -Arguments @("-Roots", $Root, "-AsJson", "-NoThrow")
    Assert-PDACondition -Condition ([string]$Repository.status -in @("pass", "warning")) -Message "Repository inventory did not return a usable status." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ([int]$Repository.repo_count -ge 1) -Message "Repository inventory did not detect the workspace repository." -Issues $Issues | Out-Null

    $Docker = Invoke-PDAJsonScript -Path $DockerScript -Arguments @("-AsJson", "-NoThrow")
    Assert-PDACondition -Condition ($Docker.PSObject.Properties.Name -contains "containers") -Message "Docker inventory did not expose containers." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ([string]$Docker.status -ne "") -Message "Docker inventory status was empty." -Issues $Issues | Out-Null

    $Services = Invoke-PDAJsonScript -Path $ServiceScript -Arguments @("-AsJson", "-NoThrow")
    Assert-PDACondition -Condition ($Services.PSObject.Properties.Name -contains "services") -Message "Service inventory did not expose services." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ([string]$Services.status -ne "") -Message "Service inventory status was empty." -Issues $Issues | Out-Null

    $Tools = Invoke-PDAJsonScript -Path $ToolScript -Arguments @("-AsJson", "-NoThrow")
    Assert-PDACondition -Condition ($Tools.PSObject.Properties.Name -contains "tools") -Message "Tool inventory did not expose tools." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ([int]$Tools.available_count -ge 3) -Message "Tool inventory did not detect the expected local toolset." -Issues $Issues | Out-Null

    $Summary = Invoke-PDAJsonScript -Path $SummaryScript -Arguments @("-Roots", $TempRoot, "-AsJson", "-NoThrow")
    Assert-PDACondition -Condition ($Summary.PSObject.Properties.Name -contains "counts") -Message "Environment summary did not expose counts." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ([int]$Summary.counts.repositories -ge 0) -Message "Environment summary counts were not usable." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ($Summary.PSObject.Properties.Name -contains "filesystem") -Message "Environment summary did not include filesystem inventory." -Issues $Issues | Out-Null

    $Recommendation = Invoke-PDAJsonScript -Path $RecommendationScript -Arguments @("-Roots", $TempRoot, "-AsJson", "-NoThrow")
    Assert-PDACondition -Condition (-not [string]::IsNullOrWhiteSpace([string]$Recommendation.recommended_model)) -Message "Organization recommendation did not select a model." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ($Recommendation.no_auto_moves -eq $true) -Message "Organization recommendation did not preserve the no-auto-move constraint." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition (@($Recommendation.proposed_structure).Count -ge 4) -Message "Organization recommendation did not include a proposed structure." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition (@($Recommendation.migration_strategy).Count -ge 3) -Message "Organization recommendation did not include a migration strategy." -Issues $Issues | Out-Null

    $Router = Invoke-PDAJsonScript -Path $RouterScript -Arguments @("-Text", "Scan $TempRoot and recommend a better project structure.", "-AsJson")
    Assert-PDACondition -Condition ([string]$Router.route_type -ne "fallback") -Message "Conversational router fell back on an environment request." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ([string]$Router.response_mode -in @("direct_answer", "clarification")) -Message "Conversational router returned an unexpected response mode." -Issues $Issues | Out-Null

    $Bridge = Invoke-PDAJsonScript -Path $BridgeScript -Arguments @("-Message", "Scan $TempRoot and recommend a better project structure.", "-AsJson")
    Assert-PDACondition -Condition ([string]$Bridge.response_text -match '(?i)environment discovery|recommended structure|approval path') -Message "Chat bridge did not surface the environment analysis response." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ([string]$Bridge.intent -match '(?i)environment_awareness|goal_planning') -Message "Chat bridge did not classify the environment request correctly." -Issues $Issues | Out-Null

    $RegressionResults = @()
    if ($RunRegression) {
        $RegressionResults += Invoke-PDAPlainScript -Path (Join-Path $PSScriptRoot "Test-PDACommander.ps1") -Arguments @("-AsJson", "-NoThrow")
        $RegressionResults += Invoke-PDAPlainScript -Path (Join-Path $PSScriptRoot "Test-PDAGoalPlanning.ps1") -Arguments @("-AsJson", "-NoThrow")
        $RegressionResults += Invoke-PDAPlainScript -Path (Join-Path $PSScriptRoot "Test-PDATaskExecutor.ps1") -Arguments @("-AsJson", "-NoThrow")
        $RegressionResults += Invoke-PDAPlainScript -Path (Join-Path $PSScriptRoot "Test-PDAPlanOrchestration.ps1") -Arguments @("-NoThrow")
        $RegressionResults += Invoke-PDAPlainScript -Path $DashboardStatusScript -Arguments @("-AsJson", "-NoThrow")
        $RegressionResults += Invoke-PDAPlainScript -Path $UpdateDashboardScript -Arguments @("-NoThrow")
        $RegressionResults += Invoke-PDAPlainScript -Path (Join-Path $PSScriptRoot "Test-PDAChatBridge.ps1") -Arguments @("-AsJson", "-NoThrow")
        $RegressionResults += Invoke-PDAPlainScript -Path (Join-Path $PSScriptRoot "Test-PDAConversationalRouter.ps1") -Arguments @("-AsJson", "-NoThrow")

        foreach ($Result in @($RegressionResults)) {
            Assert-PDACondition -Condition ([bool]$Result.passed) -Message ("Regression script failed: {0}" -f $Result.path) -Issues $Issues | Out-Null
        }
    }

    $Report = [pscustomobject]@{
        status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
        filesystem = $Filesystem
        repository = $Repository
        docker = $Docker
        services = $Services
        tools = $Tools
        summary = $Summary
        recommendation = $Recommendation
        router = $Router
        bridge = $Bridge
        regression_results = @($RegressionResults)
        issues = @($Issues)
    }

    if ($AsJson) {
        $Report | ConvertTo-Json -Depth 30
    }
    else {
        Write-Host "[*] PDA environment awareness tests"
        Write-Host ("Status     : {0}" -f $Report.status)
        Write-Host ("Issues     : {0}" -f @($Report.issues).Count)
    }

    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA environment awareness validation failed."
    }
}
finally {
    if (Test-Path -LiteralPath $TempRoot -PathType Container) {
        try { Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}
