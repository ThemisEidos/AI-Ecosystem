[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$ResolverScript = Join-Path $PSScriptRoot "Resolve-PDAAgent.ps1"
$CapabilityRegistryPath = Join-Path $PSScriptRoot "PDA_CapabilityRegistry.json"
$AgentRegistryPath = Join-Path $PSScriptRoot "PDA_AgentProfileRegistry.json"

function ConvertFrom-PDAMixedJson {
    param([Parameter(Mandatory = $true)][string]$Text)

    $Trimmed = [string]$Text.Trim()
    if ([string]::IsNullOrWhiteSpace($Trimmed)) {
        return $null
    }

    try {
        return $Trimmed | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $Start = $Trimmed.LastIndexOf("{")
        $End = $Trimmed.LastIndexOf("}")
        if ($Start -ge 0 -and $End -gt $Start) {
            $Candidate = $Trimmed.Substring($Start, $End - $Start + 1)
            return $Candidate | ConvertFrom-Json -ErrorAction Stop
        }
        throw
    }
}

function Invoke-Resolver {
    param(
        [Parameter(Mandatory = $true)][string]$CapabilityId,
        [Parameter(Mandatory = $false)][string]$Category = "",
        [Parameter(Mandatory = $false)][string]$Agent = "",
        [Parameter(Mandatory = $false)][string]$Tool = "",
        [Parameter(Mandatory = $false)][string]$ApprovalRequired = "",
        [Parameter(Mandatory = $false)][string]$RestrictedLocalOnly = ""
    )

    $Args = @(
        "-NoProfile",
        "-File", $ResolverScript,
        "-CapabilityId", $CapabilityId,
        "-AsJson",
        "-NoThrow"
    )

    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        $Args += @("-Category", $Category)
    }
    if (-not [string]::IsNullOrWhiteSpace($Agent)) {
        $Args += @("-Agent", $Agent)
    }
    if (-not [string]::IsNullOrWhiteSpace($Tool)) {
        $Args += @("-Tool", $Tool)
    }
    if (-not [string]::IsNullOrWhiteSpace($ApprovalRequired)) {
        $Args += @("-ApprovalRequired", $ApprovalRequired)
    }
    if (-not [string]::IsNullOrWhiteSpace($RestrictedLocalOnly)) {
        $Args += @("-RestrictedLocalOnly", $RestrictedLocalOnly)
    }

    $Raw = & pwsh @Args 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Resolver returned no output for capability '$CapabilityId'."
    }

    return ConvertFrom-PDAMixedJson -Text $Text
}

$Issues = New-Object System.Collections.Generic.List[string]
$Results = @()
$Passed = 0
$Failed = 0

if (-not (Test-Path -LiteralPath $ResolverScript -PathType Leaf)) {
    $Result = [pscustomobject]@{
        status = "fail"
        error = "Resolve-PDAAgent.ps1 not found."
        tests = @()
        issues = @("Resolve-PDAAgent.ps1 not found.")
    }

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        if (-not $NoThrow) { throw $Result.error }
        return
    }

    Write-Host "[ERROR] $($Result.error)"
    if (-not $NoThrow) { throw $Result.error }
    return
}

try {
    $Research = Invoke-Resolver -CapabilityId "research"
    if ($Research.status -ne "pass") { $Issues.Add("Research capability did not resolve successfully.") }
    if ($Research.capability_registry_count -lt 15) { $Issues.Add("Capability registry count was not loaded.") }
    if ($Research.agent_profile_count -lt 6) { $Issues.Add("Agent profile registry count was not loaded.") }
} catch {
    $Issues.Add("Capability and agent registry load check failed: $($_.Exception.Message)")
    $Research = $null
}

function Add-ResolverCaseResult {
    param(
        [string]$Name,
        [bool]$Passed,
        [object]$Payload,
        [string[]]$CaseIssues
    )

    $script:Results += [pscustomobject]@{
        name = $Name
        passed = $Passed
        selected_agent = if ($Payload) { [string]$Payload.selected_agent } else { "" }
        candidate_agents = if ($Payload) { @($Payload.candidate_agents) } else { @() }
        approval_required = if ($Payload) { [bool]$Payload.approval_required } else { $false }
        restricted_local_only = if ($Payload) { [bool]$Payload.restricted_local_only } else { $false }
        routing_reason = if ($Payload) { [string]$Payload.routing_reason } else { "" }
        issues = @($CaseIssues)
    }
}

$CodeImpl = $null
$CodeIssues = New-Object System.Collections.Generic.List[string]
try {
    $CodeImpl = Invoke-Resolver -CapabilityId "code_implementation"
    if ($CodeImpl.status -ne "pass") { $CodeIssues.Add("code_implementation did not resolve successfully.") }
    if ($CodeImpl.selected_agent -ne "build_agent") { $CodeIssues.Add("code_implementation should resolve to build_agent.") }
    if (-not [bool]$CodeImpl.approval_required) { $CodeIssues.Add("code_implementation should require approval.") }
    if ([bool]$CodeImpl.restricted_local_only) { $CodeIssues.Add("code_implementation should not be restricted local-only.") }
} catch {
    $CodeIssues.Add("code_implementation resolution failed: $($_.Exception.Message)")
}
Add-ResolverCaseResult -Name "code implementation" -Passed ($CodeIssues.Count -eq 0) -Payload $CodeImpl -CaseIssues $CodeIssues
if ($CodeIssues.Count -eq 0) { $Passed++ } else { $Failed++ }

$ReportWriting = $null
$ReportWritingIssues = New-Object System.Collections.Generic.List[string]
try {
    $ReportWriting = Invoke-Resolver -CapabilityId "report_writing"
    if ($ReportWriting.status -ne "pass") { $ReportWritingIssues.Add("report_writing did not resolve successfully.") }
    if ($ReportWriting.selected_agent -ne "reporting_agent") { $ReportWritingIssues.Add("report_writing should resolve to reporting_agent.") }
} catch {
    $ReportWritingIssues.Add("report_writing resolution failed: $($_.Exception.Message)")
}
Add-ResolverCaseResult -Name "report writing" -Passed ($ReportWritingIssues.Count -eq 0) -Payload $ReportWriting -CaseIssues $ReportWritingIssues
if ($ReportWritingIssues.Count -eq 0) { $Passed++ } else { $Failed++ }

$ReportReview = $null
$ReportReviewIssues = New-Object System.Collections.Generic.List[string]
try {
    $ReportReview = Invoke-Resolver -CapabilityId "report_review"
    if ($ReportReview.status -ne "pass") { $ReportReviewIssues.Add("report_review did not resolve successfully.") }
    if ($ReportReview.selected_agent -ne "review_agent") { $ReportReviewIssues.Add("report_review should resolve to review_agent.") }
    if (-not (@($ReportReview.candidate_agents) -contains "review_agent")) { $ReportReviewIssues.Add("report_review candidate list should contain review_agent.") }
    if (-not (@($ReportReview.candidate_agents) -contains "reporting_agent")) { $ReportReviewIssues.Add("report_review candidate list should contain reporting_agent.") }
} catch {
    $ReportReviewIssues.Add("report_review resolution failed: $($_.Exception.Message)")
}
Add-ResolverCaseResult -Name "report review" -Passed ($ReportReviewIssues.Count -eq 0) -Payload $ReportReview -CaseIssues $ReportReviewIssues
if ($ReportReviewIssues.Count -eq 0) { $Passed++ } else { $Failed++ }

$LocalRestricted = $null
$LocalRestrictedIssues = New-Object System.Collections.Generic.List[string]
try {
    $LocalRestricted = Invoke-Resolver -CapabilityId "local_restricted_analysis" -Category "category_2"
    if ($LocalRestricted.status -ne "pass") { $LocalRestrictedIssues.Add("local_restricted_analysis did not resolve successfully.") }
    if ($LocalRestricted.selected_agent -ne "restricted_agent") { $LocalRestrictedIssues.Add("local_restricted_analysis should resolve to restricted_agent.") }
    if (-not [bool]$LocalRestricted.restricted_local_only) { $LocalRestrictedIssues.Add("local_restricted_analysis should be restricted local-only.") }
    if (-not [bool]$LocalRestricted.approval_required) { $LocalRestrictedIssues.Add("local_restricted_analysis should require approval.") }
} catch {
    $LocalRestrictedIssues.Add("local_restricted_analysis resolution failed: $($_.Exception.Message)")
}
Add-ResolverCaseResult -Name "local restricted analysis" -Passed ($LocalRestrictedIssues.Count -eq 0) -Payload $LocalRestricted -CaseIssues $LocalRestrictedIssues
if ($LocalRestrictedIssues.Count -eq 0) { $Passed++ } else { $Failed++ }

$Invalid = $null
$InvalidIssues = New-Object System.Collections.Generic.List[string]
try {
    $Invalid = Invoke-Resolver -CapabilityId "not-a-real-capability"
    if ($Invalid.status -ne "fail") { $InvalidIssues.Add("Invalid capability should fail gracefully.") }
    if ([string]::IsNullOrWhiteSpace([string]$Invalid.blocked_reason)) { $InvalidIssues.Add("Invalid capability should return a blocked reason.") }
} catch {
    $InvalidIssues.Add("Invalid capability path should not throw when -NoThrow is used: $($_.Exception.Message)")
}
Add-ResolverCaseResult -Name "invalid capability" -Passed ($InvalidIssues.Count -eq 0) -Payload $Invalid -CaseIssues $InvalidIssues
if ($InvalidIssues.Count -eq 0) { $Passed++ } else { $Failed++ }

if ($Research) {
    if ($Research.PSObject.Properties.Name -notcontains "selected_agent") {
        $Issues.Add("Resolver output did not include selected_agent.")
    }
    if ($Research.PSObject.Properties.Name -notcontains "candidate_agents") {
        $Issues.Add("Resolver output did not include candidate_agents.")
    }
    if ($Research.PSObject.Properties.Name -notcontains "routing_reason") {
        $Issues.Add("Resolver output did not include routing_reason.")
    }
}

$IssuesText = @($Issues + ($Results | ForEach-Object { $_.issues } | Where-Object { $_ })) | ForEach-Object { $_ } | Select-Object -Unique
$Status = if ($IssuesText.Count -eq 0) { "pass" } else { "fail" }
$Report = [pscustomobject]@{
    status = $Status
    resolver_script = $ResolverScript
    capability_registry_path = $CapabilityRegistryPath
    agent_registry_path = $AgentRegistryPath
    test_case_count = @($Results).Count
    passed_count = $Passed
    failed_count = $Failed
    issues = @($IssuesText)
    results = $Results
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if ($Status -ne "pass" -and -not $NoThrow) { throw "PDA agent resolver validation failed." }
    return
}

if ($Status -eq "pass") {
    Write-Host "[OK] PDA agent resolver validation passed."
}
else {
    Write-Host "[ERROR] PDA agent resolver validation failed."
    foreach ($Issue in $IssuesText) {
        Write-Host (" - {0}" -f $Issue)
    }
    if (-not $NoThrow) { throw "PDA agent resolver validation failed." }
}
