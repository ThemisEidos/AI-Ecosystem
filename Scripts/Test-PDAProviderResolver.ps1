[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$ResolverScript = Join-Path $PSScriptRoot "Resolve-PDAProvider.ps1"
$CapabilityRegistryPath = Join-Path $PSScriptRoot "PDA_CapabilityRegistry.json"
$AgentRegistryPath = Join-Path $PSScriptRoot "PDA_AgentProfileRegistry.json"
$PolicyPath = Join-Path $PSScriptRoot "PDA_ProviderRoutingPolicy.json"

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
        [Parameter(Mandatory = $true)][string]$SelectedAgent,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $false)][string]$RequestedProvider = "",
        [Parameter(Mandatory = $false)][string[]]$ApprovedProviders = @(),
        [Parameter(Mandatory = $false)][string]$RestrictedLocalOnly = "",
        [Parameter(Mandatory = $false)][object]$LocalConfidence = $null
    )

    $Args = @(
        "-NoProfile",
        "-File", $ResolverScript,
        "-CapabilityId", $CapabilityId,
        "-SelectedAgent", $SelectedAgent,
        "-Category", $Category,
        "-PolicyPath", $PolicyPath,
        "-CapabilityRegistryPath", $CapabilityRegistryPath,
        "-AgentRegistryPath", $AgentRegistryPath,
        "-AsJson",
        "-NoThrow"
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedProvider)) {
        $Args += @("-RequestedProvider", $RequestedProvider)
    }
    if ($ApprovedProviders.Count -gt 0) {
        $Args += @("-ApprovedProviders", $ApprovedProviders)
    }
    if (-not [string]::IsNullOrWhiteSpace($RestrictedLocalOnly)) {
        $Args += @("-RestrictedLocalOnly", $RestrictedLocalOnly)
    }
    if ($null -ne $LocalConfidence) {
        try {
            $ConfidenceValue = [double]$LocalConfidence
            if (-not [double]::IsNaN($ConfidenceValue)) {
                $Args += @("-LocalConfidence", [string]$ConfidenceValue)
            }
        }
        catch {
        }
    }

    $Raw = & pwsh @Args 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Resolver returned no output for capability '$CapabilityId'."
    }

    return ConvertFrom-PDAMixedJson -Text $Text
}

$Cases = @(
    [pscustomobject]@{
        name = "research to gemini"
        capability_id = "research"
        selected_agent = "research_agent"
        category = "category_1"
        expected_selected_provider = "gemini"
        expected_cloud_allowed = $true
        expected_defaulted_to_local = $false
        expected_escalation_required = $true
        expected_approval_required = $false
    }
    [pscustomobject]@{
        name = "report writing to claude"
        capability_id = "report_writing"
        selected_agent = "reporting_agent"
        category = "category_1"
        expected_selected_provider = "claude"
        expected_cloud_allowed = $true
        expected_defaulted_to_local = $false
        expected_escalation_required = $true
        expected_approval_required = $false
    }
    [pscustomobject]@{
        name = "code implementation to claude code"
        capability_id = "code_implementation"
        selected_agent = "build_agent"
        category = "category_1"
        expected_selected_provider = "claude_code"
        expected_cloud_allowed = $true
        expected_defaulted_to_local = $false
        expected_escalation_required = $true
        expected_approval_required = $true
    }
    [pscustomobject]@{
        name = "local restricted category 2"
        capability_id = "local_restricted_analysis"
        selected_agent = "restricted_agent"
        category = "category_2"
        expected_selected_provider = "local-llama"
        expected_cloud_allowed = $false
        expected_defaulted_to_local = $true
        expected_escalation_required = $false
        expected_approval_required = $true
    }
    [pscustomobject]@{
        name = "safe cloud override"
        capability_id = "report_review"
        selected_agent = "review_agent"
        category = "category_1"
        requested_provider = "gpt"
        expected_selected_provider = "gpt"
        expected_cloud_allowed = $true
        expected_defaulted_to_local = $false
        expected_escalation_required = $true
        expected_approval_required = $false
    }
    [pscustomobject]@{
        name = "blocked cloud override"
        capability_id = "file_processing"
        selected_agent = "restricted_agent"
        category = "category_2"
        requested_provider = "gemini"
        expected_selected_provider = "local-llama"
        expected_cloud_allowed = $false
        expected_defaulted_to_local = $true
        expected_escalation_required = $false
        expected_approval_required = $true
    }
    [pscustomobject]@{
        name = "local confidence escalation"
        capability_id = "research"
        selected_agent = "research_agent"
        category = "category_1"
        local_confidence = 0.2
        approved_providers = @("claude", "gpt")
        expected_selected_provider = "claude"
        expected_cloud_allowed = $true
        expected_defaulted_to_local = $false
        expected_escalation_required = $true
        expected_approval_required = $false
    }
)

$Results = @()
$Passed = 0
$Failed = 0
$Issues = New-Object System.Collections.Generic.List[string]

foreach ($Case in $Cases) {
    $InvokeCapabilityId = $Case.capability_id

    $Result = Invoke-Resolver -CapabilityId $InvokeCapabilityId -SelectedAgent $Case.selected_agent -Category $Case.category -RequestedProvider $Case.requested_provider -RestrictedLocalOnly $Case.restricted_local_only -LocalConfidence $Case.local_confidence -ApprovedProviders $Case.approved_providers
    $CaseIssues = New-Object System.Collections.Generic.List[string]

    if ([string]$Result.status -ne "pass") {
        $CaseIssues.Add("Resolver did not return pass.")
    }
    if ([string]$Result.selected_provider -ne [string]$Case.expected_selected_provider) {
        $CaseIssues.Add("Expected selected provider '$($Case.expected_selected_provider)' but got '$($Result.selected_provider)'.")
    }
    if ([bool]$Result.cloud_allowed -ne [bool]$Case.expected_cloud_allowed) {
        $CaseIssues.Add("Expected cloud_allowed '$($Case.expected_cloud_allowed)' but got '$($Result.cloud_allowed)'.")
    }
    if ([bool]$Result.defaulted_to_local -ne [bool]$Case.expected_defaulted_to_local) {
        $CaseIssues.Add("Expected defaulted_to_local '$($Case.expected_defaulted_to_local)' but got '$($Result.defaulted_to_local)'.")
    }
    if ([bool]$Result.escalation_required -ne [bool]$Case.expected_escalation_required) {
        $CaseIssues.Add("Expected escalation_required '$($Case.expected_escalation_required)' but got '$($Result.escalation_required)'.")
    }
    if ([bool]$Result.approval_required -ne [bool]$Case.expected_approval_required) {
        $CaseIssues.Add("Expected approval_required '$($Case.expected_approval_required)' but got '$($Result.approval_required)'.")
    }

    if ($Case.name -eq "blocked cloud override" -and -not [bool]$Result.override_blocked) {
        $CaseIssues.Add("Restricted-local override should be blocked.")
    }
    if ($Case.name -eq "safe cloud override" -and -not [bool]$Result.override_accepted) {
        $CaseIssues.Add("Safe user override should be accepted.")
    }
    if ($Case.name -eq "local confidence escalation" -and $Result.escalation_reason -notmatch "confidence") {
        $CaseIssues.Add("Low-confidence escalation should mention confidence.")
    }

    $CasePassed = ($CaseIssues.Count -eq 0)
    $Results += [pscustomobject]@{
        name = $Case.name
        passed = $CasePassed
        capability = [string]$InvokeCapabilityId
        selected_agent = [string]$Case.selected_agent
        selected_provider = [string]$Result.selected_provider
        candidate_providers = @($Result.candidate_providers)
        routing_reason = [string]$Result.routing_reason
        escalation_reason = [string]$Result.escalation_reason
        cloud_allowed = [bool]$Result.cloud_allowed
        defaulted_to_local = [bool]$Result.defaulted_to_local
        approval_required = [bool]$Result.approval_required
        issues = @($CaseIssues)
    }

    if ($CasePassed) {
        $Passed++
    }
    else {
        $Failed++
        foreach ($Issue in $CaseIssues) {
            $Issues.Add("$($Case.name): $Issue")
        }
    }
}

$Report = [pscustomobject]@{
    status = if ($Failed -eq 0) { "pass" } else { "fail" }
    policy_path = $PolicyPath
    resolver_script = $ResolverScript
    capability_registry_path = $CapabilityRegistryPath
    agent_registry_path = $AgentRegistryPath
    test_case_count = $Cases.Count
    passed_count = $Passed
    failed_count = $Failed
    issues = @($Issues)
    results = @($Results)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA provider resolver validation failed."
    }
    return
}

if ($Report.status -eq "pass") {
    Write-Host "[OK] PDA provider resolver validation passed."
}
else {
    Write-Host "[ERROR] PDA provider resolver validation failed."
    foreach ($Issue in $Issues) {
        Write-Host (" - {0}" -f $Issue)
    }
    if (-not $NoThrow) {
        throw "PDA provider resolver validation failed."
    }
}
