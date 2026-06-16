[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$WorkerScript = Join-Path $PSScriptRoot "Invoke-PDAResearchWorker.ps1"
$ReviewScript = Join-Path $PSScriptRoot "Resolve-COOPERWorkflowReview.ps1"
$SkillsScript = Join-Path $PSScriptRoot "Update-COOPERWorkflowSkills.ps1"
$ResultsRoot = Join-Path $Root "PDA-Tasks\results"
$TempRoot = Join-Path $Root "tmp\research-worker-validation"
$TempSkillsState = Join-Path $TempRoot "COOPER_Skills.failed-review.json"
. (Join-Path $PSScriptRoot "Test-PDAAssertions.ps1")

if (-not (Test-Path -LiteralPath $WorkerScript -PathType Leaf)) {
    throw "Research worker missing: $WorkerScript"
}
if (-not (Test-Path -LiteralPath $ReviewScript -PathType Leaf)) {
    throw "Workflow review script missing: $ReviewScript"
}

function Invoke-ResearchWorker {
    param([Parameter(Mandatory = $true)][string]$TaskPath)

    $Raw = & pwsh -NoProfile -File $WorkerScript -TaskPath $TaskPath 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Worker returned empty output."
    }

    $Match = [regex]::Match($Text, '(?m)^\{')
    if (-not $Match.Success) {
        throw "Worker output did not contain JSON."
    }

    $JsonText = $Text.Substring($Match.Index).Trim()
    return $JsonText | ConvertFrom-Json -ErrorAction Stop
}

function Invoke-ResearchReview {
    param(
        [Parameter(Mandatory = $true)]
        [object]$WorkflowResult,

        [Parameter(Mandatory = $true)]
        [string]$RequestText
    )

    & $ReviewScript `
        -WorkflowId "WF-001" `
        -WorkflowResult $WorkflowResult `
        -RequestText $RequestText `
        -ExpectedOutputType "research_markdown" `
        -ExpectedOutputPath ([string]$WorkflowResult.saved_path)
}

function New-ResearchTaskFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskPath,

        [Parameter(Mandatory = $true)]
        [string]$RequestText
    )

    $Task = [ordered]@{
        task_id = [guid]::NewGuid().ToString()
        command = "/research"
        classification = "category_3"
        category = "category_3"
        approved = $true
        target = $RequestText
        source_path = ""
    }

    $Task | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $TaskPath -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $TempRoot -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
}
New-Item -ItemType Directory -Force -Path $ResultsRoot | Out-Null

$Issues = New-Object System.Collections.Generic.List[string]

$OfficialRequest = "Research official Pop!_OS documentation and create a structured summary note in the Linux & Infrastructure collection."
$OfficialTaskPath = Join-Path $TempRoot "wf001-official-task.json"
New-ResearchTaskFile -TaskPath $OfficialTaskPath -RequestText $OfficialRequest

$OfficialResult = $null
try {
    $OfficialResult = Invoke-ResearchWorker -TaskPath $OfficialTaskPath
}
catch {
    $Issues.Add("WF-001 worker threw unexpectedly for an official Pop!_OS request: $($_.Exception.Message)")
}

if ($null -eq $OfficialResult) {
    $Issues.Add("WF-001 worker did not return a result for an official Pop!_OS request.")
}
else {
    if ([string]$OfficialResult.status -ne "success") {
        $Issues.Add("WF-001 worker did not succeed for an official Pop!_OS request.")
    }
    if ([string]::IsNullOrWhiteSpace([string]$OfficialResult.saved_path)) {
        $Issues.Add("WF-001 worker did not return a saved markdown path.")
    }
    elseif (-not (Test-Path -LiteralPath $OfficialResult.saved_path -PathType Leaf)) {
        $Issues.Add("WF-001 markdown file was not created.")
    }

    $OfficialOutput = if ($OfficialResult.PSObject.Properties.Name -contains "output") { $OfficialResult.output } else { $null }
    if ($null -eq $OfficialOutput) {
        $Issues.Add("WF-001 worker did not return an output payload.")
    }
    else {
        if ([int]$OfficialOutput.source_count -le 0) {
            $Issues.Add("WF-001 worker did not collect any sources.")
        }
        if (-not ($OfficialOutput.sources) -or @($OfficialOutput.sources).Count -le 0) {
            $Issues.Add("WF-001 worker output is missing collected sources.")
        }
        if ([string]::IsNullOrWhiteSpace([string]$OfficialOutput.retrieved_at)) {
            $Issues.Add("WF-001 worker output is missing retrieved_at.")
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$OfficialResult.saved_path) -and (Test-Path -LiteralPath $OfficialResult.saved_path -PathType Leaf)) {
        $Content = Get-Content -LiteralPath $OfficialResult.saved_path -Raw
        if ($Content -notmatch '(?i)https?://') {
            $Issues.Add("WF-001 markdown does not contain source URLs.")
        }
        if ($Content -notmatch '(?im)^##\s+Retrieved At') {
            $Issues.Add("WF-001 markdown does not contain a Retrieved At section.")
        }
        if ($Content -match '(?i)cannot perform real-time research|knowledge cutoff|if you provide source material|as an ai|i can''t browse|i cannot browse|unable to access the web') {
            $Issues.Add("WF-001 markdown contains disclaimer-only language.")
        }
        if ($Content -notmatch '(?i)pop!?_?os|system76|linux & infrastructure|summary') {
            $Issues.Add("WF-001 markdown does not appear to address the request.")
        }
    }

    $Review = $null
    try {
        $Review = Invoke-ResearchReview -WorkflowResult $OfficialResult -RequestText $OfficialRequest
    }
    catch {
        $Issues.Add("WF-001 review threw unexpectedly for a valid result: $($_.Exception.Message)")
    }

    if ($null -eq $Review) {
        $Issues.Add("WF-001 review did not return a result for a valid research output.")
    }
    else {
        if ([string]$Review.status -ne "pass") {
            $Issues.Add("WF-001 review did not pass for a source-backed result.")
        }
        if ([bool]$Review.review_passed -ne $true) {
            $Issues.Add("WF-001 review did not set review_passed to true.")
        }
    }
}

$NoSourceRequest = "Research the history of tea and create a summary note."
$NoSourceTaskPath = Join-Path $TempRoot "wf001-nosource-task.json"
New-ResearchTaskFile -TaskPath $NoSourceTaskPath -RequestText $NoSourceRequest
$NoSourceResult = $null
try {
    $NoSourceResult = Invoke-ResearchWorker -TaskPath $NoSourceTaskPath
}
catch {
    $Issues.Add("WF-001 worker threw unexpectedly for a no-source request: $($_.Exception.Message)")
}

if ($null -eq $NoSourceResult) {
    $Issues.Add("WF-001 worker did not return a result for a no-source request.")
}
else {
    if ([string]$NoSourceResult.status -ne "failed") {
        $Issues.Add("WF-001 worker should fail when no approved sources are collected.")
    }
    if ([string]::IsNullOrWhiteSpace([string]$NoSourceResult.reason) -or [string]$NoSourceResult.reason -ne "no_sources_collected") {
        $Issues.Add("WF-001 worker should report no_sources_collected for unsupported research requests.")
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$NoSourceResult.saved_path)) {
        $Issues.Add("WF-001 should not create a markdown artifact when no sources are collected.")
    }
}

$DisclaimerPath = Join-Path $TempRoot "wf001-disclaimer.md"
@"
# WF-001 Research Summary

I cannot perform real-time research on external documentation.
"@ | Set-Content -LiteralPath $DisclaimerPath -Encoding UTF8

$DisclaimerResult = [pscustomobject]@{
    status = "success"
    saved_path = $DisclaimerPath
    output = [pscustomobject]@{
        markdown_path = $DisclaimerPath
        source_count = 1
        retrieved_at = (Get-Date).ToUniversalTime().ToString("o")
        sources = @(
            [pscustomobject]@{
                title = "Synthetic Source"
                url = "https://system76.com/support/articles/pop-basics/"
                retrieved_at = (Get-Date).ToUniversalTime().ToString("o")
                source_domain = "system76.com"
                excerpt = "Synthetic excerpt."
            }
        )
    }
}
$DisclaimerReview = Invoke-ResearchReview -WorkflowResult $DisclaimerResult -RequestText $OfficialRequest
if ([string]$DisclaimerReview.status -ne "fail") {
    $Issues.Add("WF-001 review should fail disclaimer-only output.")
}
if (-not (@($DisclaimerReview.issues | Where-Object { [string]$_ -match 'disclaimer' }).Count -gt 0)) {
    $Issues.Add("WF-001 review should report disclaimer-only language as an issue.")
}

if (Test-Path -LiteralPath $TempSkillsState -PathType Leaf) {
    Remove-Item -LiteralPath $TempSkillsState -Force
}

$FailedPromotion = & $SkillsScript -WorkflowId "WF-001" -ReviewResult $DisclaimerReview -ExampleRequest $OfficialRequest -ExampleOutput "wf-001-research-summary.md" -SkillName "Research Summary" -StatePath $TempSkillsState
if ([string]$FailedPromotion.status -ne "fail") {
    $Issues.Add("Failed WF-001 review did not stay in fail status.")
}
if ([bool]$FailedPromotion.promoted -ne $false) {
    $Issues.Add("Failed WF-001 review incorrectly promoted the skill.")
}

if (-not (Test-Path -LiteralPath $TempSkillsState -PathType Leaf)) {
    $Issues.Add("Failed-review skills state file was not written.")
}
else {
    $SkillState = Get-Content -LiteralPath $TempSkillsState -Raw | ConvertFrom-Json
    $WF001Skill = @($SkillState.skills | Where-Object { [string]$_.workflow_id -eq "WF-001" } | Select-Object -First 1)
    if ($WF001Skill.Count -gt 0 -and [string]$WF001Skill[0].status -eq "operational") {
        $Issues.Add("Failed WF-001 review promoted the skill to operational.")
    }
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    official_result = $OfficialResult
    no_source_result = $NoSourceResult
    disclaimer_review = $DisclaimerReview
    failed_promotion = $FailedPromotion
    issues = @($Issues)
}

Write-Host "[*] PDA research worker validation"
Write-Host ("Status   : {0}" -f $Report.status)
Write-Host ("WF-001   : source-backed research, no-source failure, and disclaimer rejection")

if ($Report.status -ne "pass") {
    foreach ($Issue in @($Report.issues)) {
        Write-Host ("[FAIL] {0}" -f $Issue)
    }
    exit 1
}

Write-Host "[PASS] WF-001 source-backed research workflow validated."
exit 0
