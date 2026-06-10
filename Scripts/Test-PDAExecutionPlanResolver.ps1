[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$ResolverScript = Join-Path $PSScriptRoot "Resolve-PDAExecutionPlan.ps1"
$RegistryPath = Join-Path $PSScriptRoot "PDA_ExecutionPlanRegistry.json"

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
        [Parameter(Mandatory = $false)][string]$SelectedAgent = "",
        [Parameter(Mandatory = $false)][string]$SelectedProvider = "",
        [Parameter(Mandatory = $false)][string]$Category = "",
        [Parameter(Mandatory = $false)][string]$RestrictedLocalOnly = ""
    )

    $Args = @(
        "-NoProfile",
        "-File", $ResolverScript,
        "-CapabilityId", $CapabilityId,
        "-RegistryPath", $RegistryPath,
        "-AsJson",
        "-NoThrow"
    )

    if (-not [string]::IsNullOrWhiteSpace($SelectedAgent)) {
        $Args += @("-SelectedAgent", $SelectedAgent)
    }
    if (-not [string]::IsNullOrWhiteSpace($SelectedProvider)) {
        $Args += @("-SelectedProvider", $SelectedProvider)
    }
    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        $Args += @("-Category", $Category)
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

function Get-Registry {
    if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $RegistryPath -Raw -ErrorAction Stop) | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
}

$Issues = New-Object System.Collections.Generic.List[string]
$Results = @()
$Passed = 0
$Failed = 0

if (-not (Test-Path -LiteralPath $ResolverScript -PathType Leaf)) {
    $Result = [pscustomobject]@{
        status = "fail"
        error = "Resolve-PDAExecutionPlan.ps1 not found."
        tests = @()
        issues = @("Resolve-PDAExecutionPlan.ps1 not found.")
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

$Registry = Get-Registry
if (-not $Registry) {
    $Issues.Add("Execution plan registry was missing or invalid.")
}
else {
    $RequiredCapabilities = @(
        "research",
        "source_discovery",
        "large_context_analysis",
        "report_writing",
        "report_review",
        "code_implementation",
        "code_review",
        "repo_modification",
        "automation_design",
        "n8n_workflow_design",
        "local_restricted_analysis",
        "file_processing",
        "dashboard_status_generation",
        "memory_summarization",
        "skill_promotion_review"
    )

    foreach ($CapabilityId in $RequiredCapabilities) {
        $Plan = @($Registry.execution_plans | Where-Object { [string]$_.capability_id -ieq $CapabilityId })
        if ($Plan.Count -eq 0) {
            $Issues.Add("Missing execution plan for capability '$CapabilityId'.")
        }
        elseif ($Plan.Count -gt 1) {
            $Issues.Add("Duplicate execution plans were registered for capability '$CapabilityId'.")
        }
        else {
            $Entry = $Plan[0]
            foreach ($Field in @(
                "capability_id",
                "execution_plan_id",
                "display_name",
                "description",
                "agent",
                "provider_strategy",
                "approval_required",
                "restricted_local_only",
                "estimated_complexity",
                "estimated_steps",
                "execution_steps",
                "success_criteria",
                "outputs",
                "notes"
            )) {
                if ($Entry.PSObject.Properties.Name -notcontains $Field) {
                    $Issues.Add("Plan '$CapabilityId' is missing field '$Field'.")
                }
            }
        }
    }
}

function Add-CaseResult {
    param(
        [string]$Name,
        [bool]$Passed,
        [object]$Payload,
        [string[]]$CaseIssues
    )

    $script:Results += [pscustomobject]@{
        name = $Name
        passed = $Passed
        execution_plan_id = if ($Payload) { [string]$Payload.execution_plan_id } else { "" }
        restricted_local_only = if ($Payload) { [bool]$Payload.restricted_local_only } else { $false }
        approval_required = if ($Payload) { [bool]$Payload.approval_required } else { $false }
        estimated_steps = if ($Payload) { [int]$Payload.estimated_steps } else { 0 }
        routing_reason = if ($Payload) { [string]$Payload.routing_reason } else { "" }
        issues = @($CaseIssues)
    }
}

$Research = $null
$ResearchIssues = New-Object System.Collections.Generic.List[string]
try {
    $Research = Invoke-Resolver -CapabilityId "research" -SelectedAgent "research_agent" -SelectedProvider "local-llama" -Category "category_1"
    if ($Research.status -ne "pass") { $ResearchIssues.Add("Research plan did not resolve successfully.") }
    if ($Research.execution_plan_id -ne "research_standard") { $ResearchIssues.Add("Research plan id mismatch.") }
    if (@($Research.execution_steps).Count -ne 5) { $ResearchIssues.Add("Research plan should contain 5 execution steps.") }
    if ($Research.approval_required) { $ResearchIssues.Add("Research should not require approval.") }
    if ($Research.restricted_local_only) { $ResearchIssues.Add("Research should not be restricted local-only.") }
    if ($Research.routing_reason -notmatch "local-first") { $ResearchIssues.Add("Research routing reason should mention the local-first path.") }
} catch {
    $ResearchIssues.Add("Research resolution failed: $($_.Exception.Message)")
}
Add-CaseResult -Name "research" -Passed ($ResearchIssues.Count -eq 0) -Payload $Research -CaseIssues $ResearchIssues
if ($ResearchIssues.Count -eq 0) { $Passed++ } else { $Failed++ }

$ReportWriting = $null
$ReportWritingIssues = New-Object System.Collections.Generic.List[string]
try {
    $ReportWriting = Invoke-Resolver -CapabilityId "report_writing" -SelectedAgent "reporting_agent" -SelectedProvider "claude" -Category "category_1"
    if ($ReportWriting.status -ne "pass") { $ReportWritingIssues.Add("Report writing plan did not resolve successfully.") }
    if ($ReportWriting.execution_plan_id -ne "report_writing_standard") { $ReportWritingIssues.Add("Report writing plan id mismatch.") }
    if ($ReportWriting.approval_required) { $ReportWritingIssues.Add("Report writing should not require approval.") }
    if (@($ReportWriting.outputs) -notcontains "report") { $ReportWritingIssues.Add("Report writing output set should contain report.") }
    if ($ReportWriting.routing_reason -notmatch "preferred provider") { $ReportWritingIssues.Add("Report writing routing reason should reflect the chosen provider context.") }
} catch {
    $ReportWritingIssues.Add("Report writing resolution failed: $($_.Exception.Message)")
}
Add-CaseResult -Name "report writing" -Passed ($ReportWritingIssues.Count -eq 0) -Payload $ReportWriting -CaseIssues $ReportWritingIssues
if ($ReportWritingIssues.Count -eq 0) { $Passed++ } else { $Failed++ }

$CodeImplementation = $null
$CodeImplementationIssues = New-Object System.Collections.Generic.List[string]
try {
    $CodeImplementation = Invoke-Resolver -CapabilityId "code_implementation" -SelectedAgent "build_agent" -SelectedProvider "claude_code" -Category "category_1"
    if ($CodeImplementation.status -ne "pass") { $CodeImplementationIssues.Add("Code implementation plan did not resolve successfully.") }
    if ($CodeImplementation.execution_plan_id -ne "code_implementation_standard") { $CodeImplementationIssues.Add("Code implementation plan id mismatch.") }
    if (-not $CodeImplementation.approval_required) { $CodeImplementationIssues.Add("Code implementation should require approval.") }
    if ($CodeImplementation.restricted_local_only) { $CodeImplementationIssues.Add("Code implementation should not be local-only.") }
    if (@($CodeImplementation.execution_steps).Count -ne 6) { $CodeImplementationIssues.Add("Code implementation should contain 6 execution steps.") }
} catch {
    $CodeImplementationIssues.Add("Code implementation resolution failed: $($_.Exception.Message)")
}
Add-CaseResult -Name "code implementation" -Passed ($CodeImplementationIssues.Count -eq 0) -Payload $CodeImplementation -CaseIssues $CodeImplementationIssues
if ($CodeImplementationIssues.Count -eq 0) { $Passed++ } else { $Failed++ }

$LocalRestricted = $null
$LocalRestrictedIssues = New-Object System.Collections.Generic.List[string]
try {
    $LocalRestricted = Invoke-Resolver -CapabilityId "local_restricted_analysis" -SelectedAgent "restricted_agent" -SelectedProvider "local-llama" -Category "category_2" -RestrictedLocalOnly "true"
    if ($LocalRestricted.status -ne "pass") { $LocalRestrictedIssues.Add("Restricted analysis plan did not resolve successfully.") }
    if ($LocalRestricted.execution_plan_id -ne "local_restricted_analysis_local_only") { $LocalRestrictedIssues.Add("Restricted analysis plan id mismatch.") }
    if (-not $LocalRestricted.restricted_local_only) { $LocalRestrictedIssues.Add("Restricted analysis should remain local-only.") }
    if (-not $LocalRestricted.approval_required) { $LocalRestrictedIssues.Add("Restricted analysis should require approval.") }
    if ($LocalRestricted.cloud_allowed) { $LocalRestrictedIssues.Add("Restricted analysis should block cloud providers.") }
    if (@($LocalRestricted.outputs) -notcontains "restricted_analysis") { $LocalRestrictedIssues.Add("Restricted analysis output set should contain restricted_analysis.") }
} catch {
    $LocalRestrictedIssues.Add("Restricted analysis resolution failed: $($_.Exception.Message)")
}
Add-CaseResult -Name "restricted analysis" -Passed ($LocalRestrictedIssues.Count -eq 0) -Payload $LocalRestricted -CaseIssues $LocalRestrictedIssues
if ($LocalRestrictedIssues.Count -eq 0) { $Passed++ } else { $Failed++ }

$Invalid = $null
$InvalidIssues = New-Object System.Collections.Generic.List[string]
try {
    $Invalid = Invoke-Resolver -CapabilityId "not-a-real-capability" -SelectedAgent "research_agent" -SelectedProvider "local-llama" -Category "category_1"
    if ($Invalid.status -ne "fail") { $InvalidIssues.Add("Invalid capability should fail gracefully.") }
    if ([string]::IsNullOrWhiteSpace([string]$Invalid.blocked_reason)) { $InvalidIssues.Add("Invalid capability should provide a blocked reason.") }
} catch {
    $InvalidIssues.Add("Invalid capability should not throw when -NoThrow is used: $($_.Exception.Message)")
}
Add-CaseResult -Name "invalid capability" -Passed ($InvalidIssues.Count -eq 0) -Payload $Invalid -CaseIssues $InvalidIssues
if ($InvalidIssues.Count -eq 0) { $Passed++ } else { $Failed++ }

$PlanJson = $null
$PlanJsonIssues = New-Object System.Collections.Generic.List[string]
try {
    $Raw = & pwsh -NoProfile -File $ResolverScript -CapabilityId "research" -SelectedAgent "research_agent" -SelectedProvider "local-llama" -Category "category_1" -RegistryPath $RegistryPath -AsJson -NoThrow 2>&1
    $PlanJson = ConvertFrom-PDAMixedJson -Text ([string]($Raw -join "`n"))
    if ($PlanJson.status -ne "pass") { $PlanJsonIssues.Add("AsJson response did not return pass.") }
    if ($PlanJson.PSObject.Properties.Name -notcontains "execution_plan_id") { $PlanJsonIssues.Add("AsJson response missing execution_plan_id.") }
} catch {
    $PlanJsonIssues.Add("AsJson invocation failed: $($_.Exception.Message)")
}
Add-CaseResult -Name "as json" -Passed ($PlanJsonIssues.Count -eq 0) -Payload $PlanJson -CaseIssues $PlanJsonIssues
if ($PlanJsonIssues.Count -eq 0) { $Passed++ } else { $Failed++ }

$IssuesText = @($Issues + ($Results | ForEach-Object { $_.issues } | Where-Object { $_ })) | ForEach-Object { $_ } | Select-Object -Unique
$Status = if ($IssuesText.Count -eq 0) { "pass" } else { "fail" }

$Report = [pscustomobject]@{
    status = $Status
    resolver_script = $ResolverScript
    registry_path = $RegistryPath
    test_case_count = @($Results).Count
    passed_count = $Passed
    failed_count = $Failed
    issues = @($IssuesText)
    results = $Results
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if ($Status -ne "pass" -and -not $NoThrow) { throw "PDA execution plan resolver validation failed." }
    return
}

if ($Status -eq "pass") {
    Write-Host "[OK] PDA execution plan resolver validation passed."
}
else {
    Write-Host "[ERROR] PDA execution plan resolver validation failed."
    foreach ($Issue in $IssuesText) {
        Write-Host (" - {0}" -f $Issue)
    }
    if (-not $NoThrow) { throw "PDA execution plan resolver validation failed." }
}
