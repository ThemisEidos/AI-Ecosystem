[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$CandidateScript = Join-Path $PSScriptRoot "New-PDAMemoryCandidate.ps1"
$DashboardScript = Join-Path $PSScriptRoot "Get-PDADashboardStatus.ps1"
$BridgeScript = Join-Path $PSScriptRoot "Invoke-PDAChatBridge.ps1"
$RouterScript = Join-Path $PSScriptRoot "COOPER_ConversationalRouter.ps1"
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
if (Test-Path -LiteralPath $ParserPath -PathType Leaf) {
    . $ParserPath
}

if (-not (Test-Path -LiteralPath $CandidateScript -PathType Leaf)) {
    throw "Memory candidate generator missing: $CandidateScript"
}

if (-not (Test-Path -LiteralPath $RouterScript -PathType Leaf)) {
    throw "Conversational router missing: $RouterScript"
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

    if (-not $Condition) {
        if ($Issues) {
            $Issues.Add($Message)
        }
        return $false
    }

    return $true
}

function Get-PDASampleArtifact {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $IndexPath = Join-Path $RootPath "PDA_ArtifactIndex.json"
    $Index = Get-Content -LiteralPath $IndexPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $Candidate = @(
        $Index.artifacts |
            Where-Object {
                [string]$_.category -eq "category_1" -and
                -not [string]::IsNullOrWhiteSpace([string]$_.artifact_id) -and
                -not [string]::IsNullOrWhiteSpace([string]$_.artifact_path) -and
                -not [string]::IsNullOrWhiteSpace([string]$_.summary)
            } |
            Select-Object -First 1
    )

    if (-not $Candidate) {
        throw "No suitable category_1 artifact was found for the memory candidate test."
    }

    return $Candidate[0]
}

$Issues = New-Object System.Collections.Generic.List[string]

$BeforeDashboard = Invoke-PDAJsonScript -Path $DashboardScript -Arguments @("-AsJson", "-NoThrow")
$BeforeCandidates = if ($BeforeDashboard.memory_summary.PSObject.Properties.Name -contains "candidate_count") { [int]$BeforeDashboard.memory_summary.candidate_count } else { 0 }
$BeforePending = if ($BeforeDashboard.memory_summary.PSObject.Properties.Name -contains "pending_approval_count") { [int]$BeforeDashboard.memory_summary.pending_approval_count } else { 0 }

$SampleArtifact = Get-PDASampleArtifact -RootPath $Root
$GenerationResult = Invoke-PDAJsonScript -Path $CandidateScript -Arguments @(
    "-SourceArtifactId", [string]$SampleArtifact.artifact_id,
    "-Title", "Memory candidate test: $([string]$SampleArtifact.summary)",
    "-Summary", [string]$SampleArtifact.summary,
    "-ProposedMemoryText", "Promote the validated artifact '$([string]$SampleArtifact.summary)' for future retrieval.",
    "-PromotionReason", "Regression test for governed memory candidate generation.",
    "-Confidence", "0.82",
    "-Force",
    "-AsJson"
)

Assert-PDACondition -Condition ($GenerationResult.status -in @("pass", "empty")) -Message "Memory candidate generator did not return a pass/empty status." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($GenerationResult.created_count -ge 1 -or $GenerationResult.skipped_count -ge 1) -Message "Memory candidate generator did not create or skip a candidate as expected." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($GenerationResult.candidate_paths.Count -ge 1) -Message "Memory candidate generator did not return candidate paths." -Issues $Issues | Out-Null

$CandidatePath = [string]$GenerationResult.candidate_paths[0]
Assert-PDACondition -Condition (Test-Path -LiteralPath $CandidatePath -PathType Leaf) -Message "Generated candidate file does not exist: $CandidatePath" -Issues $Issues | Out-Null

$CandidateJson = Get-Content -LiteralPath $CandidatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
Assert-PDACondition -Condition ([string]$CandidateJson.title -like "Memory candidate test:*") -Message "Candidate title was not written correctly." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$CandidateJson.approval_status -eq "pending") -Message "Candidate should require pending approval." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$CandidateJson.source_artifact_id -eq [string]$SampleArtifact.artifact_id) -Message "Candidate source artifact id mismatch." -Issues $Issues | Out-Null

$AfterDashboard = Invoke-PDAJsonScript -Path $DashboardScript -Arguments @("-AsJson", "-NoThrow")
$AfterCandidates = if ($AfterDashboard.memory_summary.PSObject.Properties.Name -contains "candidate_count") { [int]$AfterDashboard.memory_summary.candidate_count } else { 0 }
$AfterPending = if ($AfterDashboard.memory_summary.PSObject.Properties.Name -contains "pending_approval_count") { [int]$AfterDashboard.memory_summary.pending_approval_count } else { 0 }

Assert-PDACondition -Condition ($AfterCandidates -ge ($BeforeCandidates + 1)) -Message "Dashboard candidate count did not increase after generation." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ($AfterPending -ge $BeforePending) -Message "Dashboard pending approval count regressed after generation." -Issues $Issues | Out-Null

$RouterResult = Invoke-PDAJsonScript -Path $RouterScript -Arguments @("-Text", "What memory candidates exist?", "-AsJson")
Assert-PDACondition -Condition ([string]$RouterResult.route_type -eq "memory_candidates") -Message "Conversational router did not classify memory candidate requests correctly." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$RouterResult.recommended_command -eq "/memory") -Message "Conversational router did not recommend /memory." -Issues $Issues | Out-Null

$BridgeResult = Invoke-PDAJsonScript -Path $BridgeScript -Arguments @("-Message", "What memory candidates exist?", "-AsJson")
Assert-PDACondition -Condition ([string]$BridgeResult.handoff_status -eq "memory_candidates") -Message "Chat bridge did not route memory candidate questions correctly." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$BridgeResult.recommended_command -eq "/memory") -Message "Chat bridge did not recommend /memory for memory candidate questions." -Issues $Issues | Out-Null
Assert-PDACondition -Condition ([string]$BridgeResult.response_text -match '(?i)memory learning is tracking|pending approvals') -Message "Chat bridge did not provide a memory candidate summary." -Issues $Issues | Out-Null

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    before = [pscustomobject]@{
        candidate_count = $BeforeCandidates
        pending_approval_count = $BeforePending
    }
    after = [pscustomobject]@{
        candidate_count = $AfterCandidates
        pending_approval_count = $AfterPending
    }
    sample_artifact = [pscustomobject]@{
        artifact_id = [string]$SampleArtifact.artifact_id
        artifact_type = [string]$SampleArtifact.artifact_type
        category = [string]$SampleArtifact.category
        summary = [string]$SampleArtifact.summary
    }
    candidate_path = $CandidatePath
    generation = $GenerationResult
    router = $RouterResult
    bridge = $BridgeResult
    issues = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA memory candidate validation failed."
    }
    return
}

Write-Host "[*] PDA memory candidate tests"
Write-Host ("Candidate count before : {0}" -f $Report.before.candidate_count)
Write-Host ("Candidate count after  : {0}" -f $Report.after.candidate_count)
Write-Host ("Pending approvals      : {0}" -f $Report.after.pending_approval_count)
Write-Host ("Candidate path         : {0}" -f $Report.candidate_path)
Write-Host ("Sample artifact        : {0}" -f $Report.sample_artifact.artifact_id)

if ($Issues.Count -gt 0) {
    Write-Host ""
    Write-Host "[Issues]"
    foreach ($Issue in $Issues) {
        Write-Host ("- {0}" -f $Issue)
    }
}

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA memory candidate validation failed."
}
