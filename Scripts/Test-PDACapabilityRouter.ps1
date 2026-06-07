[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$RouterScript = Join-Path $PSScriptRoot "PDA_CapabilityRouter.ps1"
if (-not (Test-Path -LiteralPath $RouterScript -PathType Leaf)) {
    throw "Capability router script missing: $RouterScript"
}

. $RouterScript

$Cases = @(
    [pscustomobject]@{
        name = "category 1 research"
        task_type = "research_synthesis"
        category = "category_1"
        preferred_output = "research_markdown"
        requires_local_only = $false
        expected_allowed = $true
        expected_tool_like = "Gemini"
    }
    [pscustomobject]@{
        name = "category 2 research"
        task_type = "research_synthesis"
        category = "category_2"
        preferred_output = "research_markdown"
        requires_local_only = $true
        expected_allowed = $true
        expected_tool_like = "Fabric research-synthesis local"
    }
    [pscustomobject]@{
        name = "notebooklm blocked category 2"
        task_type = "notebooklm_package"
        category = "category_2"
        preferred_output = "notebooklm_package"
        requires_local_only = $false
        expected_allowed = $false
        expected_blocked_like = "NotebookLM"
    }
    [pscustomobject]@{
        name = "report prefers fabric"
        task_type = "report_generation"
        category = "category_1"
        preferred_output = "report_markdown"
        requires_local_only = $false
        expected_allowed = $true
        expected_tool_like = "Fabric report-summary"
    }
    [pscustomobject]@{
        name = "review prefers fabric"
        task_type = "review"
        category = "category_1"
        preferred_output = "review_markdown"
        requires_local_only = $false
        expected_allowed = $true
        expected_tool_like = "Fabric review-checklist"
    }
    [pscustomobject]@{
        name = "planner stays local"
        task_type = "planning"
        category = "category_1"
        preferred_output = "plan_markdown"
        requires_local_only = $false
        expected_allowed = $true
        expected_tool_like = "PowerShell or Python local-first"
    }
)

$Results = @()
$Passed = 0
$Failed = 0

$Matrix = Get-PDACapabilityMatrix -Root $Root
if ($Matrix.status -ne "pass") {
    throw "Capability matrix failed to load: $($Matrix.matrix_path)"
}

foreach ($Case in $Cases) {
    $Issues = New-Object System.Collections.Generic.List[string]
    $Result = Get-PDAToolForTask -TaskType $Case.task_type -Category $Case.category -PreferredOutput $Case.preferred_output -RequiresLocalOnly:$Case.requires_local_only -Root $Root

    if ([bool]$Result.allowed -ne [bool]$Case.expected_allowed) {
        $Issues.Add("Expected allowed '$($Case.expected_allowed)' but got '$($Result.allowed)'.")
    }

    if ($Case.PSObject.Properties.Name -contains "expected_tool_like" -and [string]$Result.selected_tool -notmatch [regex]::Escape($Case.expected_tool_like)) {
        $Issues.Add("Expected selected tool to contain '$($Case.expected_tool_like)' but got '$($Result.selected_tool)'.")
    }

    if ($Case.PSObject.Properties.Name -contains "expected_blocked_like" -and [string]$Result.blocked_reason -notmatch [regex]::Escape($Case.expected_blocked_like)) {
        $Issues.Add("Expected blocked reason to contain '$($Case.expected_blocked_like)' but got '$($Result.blocked_reason)'.")
    }

    if ($Case.name -eq "category 2 research" -and [bool]$Result.cloud_allowed -ne $false) {
        $Issues.Add("Category 2 research should not allow cloud-backed routing.")
    }

    if ($Case.name -eq "notebooklm blocked category 2" -and [bool]$Result.allowed -ne $false) {
        $Issues.Add("NotebookLM should be blocked for category 2.")
    }

    $CasePassed = $Issues.Count -eq 0
    if ($CasePassed) {
        $Passed++
    }
    else {
        $Failed++
    }

    $Results += [pscustomobject]@{
        name = $Case.name
        passed = $CasePassed
        allowed = [bool]$Result.allowed
        selected_tool = [string]$Result.selected_tool
        backup_tool = [string]$Result.backup_tool
        blocked_reason = [string]$Result.blocked_reason
        routing_reason = [string]$Result.routing_reason
        output_location = @($Result.output_location)
        issues = @($Issues)
    }
}

$Report = [pscustomobject]@{
    status = if ($Failed -eq 0) { "pass" } else { "fail" }
    test_case_count = @($Cases).Count
    passed_count = $Passed
    failed_count = $Failed
    matrix_status = $Matrix.status
    matrix_path = $Matrix.matrix_path
    route_count = [int]$Matrix.route_count
    results = @($Results)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA capability router validation failed."
    }
    return
}

Write-Host "[*] PDA capability router tests"
Write-Host ("Status         : {0}" -f $Report.status)
Write-Host ("Test cases     : {0}" -f $Report.test_case_count)
Write-Host ("Passed         : {0}" -f $Report.passed_count)
Write-Host ("Failed         : {0}" -f $Report.failed_count)
Write-Host ("Matrix path    : {0}" -f $Report.matrix_path)
Write-Host ("Route count    : {0}" -f $Report.route_count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA capability router validation failed."
}
