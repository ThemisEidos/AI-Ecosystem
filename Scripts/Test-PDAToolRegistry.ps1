[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$RegistryScript = Join-Path $PSScriptRoot "Get-PDATool.ps1"
$ResolverScript = Join-Path $PSScriptRoot "Resolve-PDATool.ps1"
$RegistryPath = Join-Path $PSScriptRoot "PDA_ToolRegistry.json"

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
        [Parameter(Mandatory = $true)][string]$Capability,
        [Parameter(Mandatory = $true)][string]$Agent,
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][string]$Category
    )

    $Raw = & pwsh -NoProfile -File $ResolverScript -Capability $Capability -Agent $Agent -Provider $Provider -Category $Category -AsJson -NoThrow 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Resolver returned no output for capability '$Capability'."
    }

    return ConvertFrom-PDAMixedJson -Text $Text
}

$Issues = New-Object System.Collections.Generic.List[string]
$Results = @()
$Passed = 0
$Failed = 0

if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) {
    $Result = [pscustomobject]@{
        status = "fail"
        error = "PDA_ToolRegistry.json not found."
        issues = @("PDA_ToolRegistry.json not found.")
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

$SummaryRaw = & pwsh -NoProfile -File $RegistryScript -AsJson -NoThrow 2>&1
$Summary = ConvertFrom-PDAMixedJson -Text ([string]($SummaryRaw -join "`n"))
if (-not $Summary -or [string]$Summary.status -ne "pass") {
    $Issues.Add("Tool registry summary failed to load.")
}
elseif ([int]$Summary.tool_count -lt 13) {
    $Issues.Add("Expected at least 13 registered tools.")
}

$Registry = (Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json)
foreach ($Tool in @($Registry.tools)) {
    foreach ($Field in @(
        "tool_id",
        "display_name",
        "description",
        "supported_capabilities",
        "supported_agents",
        "local_only",
        "category_allowed",
        "approval_required",
        "risk_level",
        "inputs",
        "outputs",
        "notes"
    )) {
        if ($Tool.PSObject.Properties.Name -notcontains $Field) {
            $Issues.Add("Tool '$([string]$Tool.tool_id)' is missing field '$Field'.")
        }
    }
}

$Cases = @(
    [pscustomobject]@{
        name = "research"
        capability = "research"
        agent = "research_agent"
        provider = "gemini"
        category = "category_1"
        expected_tool = "browser"
        expected_approval_required = $false
        expected_local_only = $false
    }
    [pscustomobject]@{
        name = "code implementation"
        capability = "code_implementation"
        agent = "build_agent"
        provider = "claude_code"
        category = "category_1"
        expected_tool = "claude_code"
        expected_approval_required = $true
        expected_local_only = $false
    }
    [pscustomobject]@{
        name = "automation design"
        capability = "automation_design"
        agent = "automation_agent"
        provider = "claude_code"
        category = "category_1"
        expected_tool = "n8n"
        expected_approval_required = $true
        expected_local_only = $false
    }
    [pscustomobject]@{
        name = "local restricted analysis"
        capability = "local_restricted_analysis"
        agent = "restricted_agent"
        provider = "local-llama"
        category = "category_2"
        expected_tool = "local_llm"
        expected_approval_required = $true
        expected_local_only = $true
    }
)

foreach ($Case in $Cases) {
    $Result = Invoke-Resolver -Capability $Case.capability -Agent $Case.agent -Provider $Case.provider -Category $Case.category
    $CaseIssues = New-Object System.Collections.Generic.List[string]

    if ([string]$Result.status -ne "pass") {
        $CaseIssues.Add("Resolver did not return pass.")
    }
    if ([string]$Result.selected_tool -ne [string]$Case.expected_tool) {
        $CaseIssues.Add("Expected selected tool '$($Case.expected_tool)' but got '$($Result.selected_tool)'.")
    }
    if ([bool]$Result.approval_required -ne [bool]$Case.expected_approval_required) {
        $CaseIssues.Add("Expected approval_required '$($Case.expected_approval_required)' but got '$($Result.approval_required)'.")
    }
    if ([bool]$Result.restricted_local_only -ne [bool]$Case.expected_local_only) {
        $CaseIssues.Add("Expected restricted_local_only '$($Case.expected_local_only)' but got '$($Result.restricted_local_only)'.")
    }
    if ($Case.name -eq "local restricted analysis" -and -not (@($Result.candidate_tools) -contains "file_system")) {
        $CaseIssues.Add("Local restricted analysis should still consider file_system as a fallback tool.")
    }

    $Results += [pscustomobject]@{
        name = $Case.name
        passed = ($CaseIssues.Count -eq 0)
        capability = [string]$Case.capability
        agent = [string]$Case.agent
        provider = [string]$Case.provider
        selected_tool = [string]$Result.selected_tool
        candidate_tools = @($Result.candidate_tools)
        routing_reason = [string]$Result.routing_reason
        approval_required = [bool]$Result.approval_required
        restricted_local_only = [bool]$Result.restricted_local_only
        issues = @($CaseIssues)
    }

    if ($CaseIssues.Count -eq 0) {
        $Passed++
    }
    else {
        $Failed++
        foreach ($Issue in $CaseIssues) {
            $Issues.Add("$($Case.name): $Issue")
        }
    }
}

$InvalidRaw = & pwsh -NoProfile -File $ResolverScript -Capability "not-a-real-capability" -Agent "research_agent" -Provider "gemini" -Category "category_1" -AsJson -NoThrow 2>&1
$Invalid = ConvertFrom-PDAMixedJson -Text ([string]($InvalidRaw -join "`n"))
if ([string]$Invalid.status -ne "fail") {
    $Issues.Add("Invalid capability should fail gracefully.")
}
if ([string]::IsNullOrWhiteSpace([string]$Invalid.blocked_reason)) {
    $Issues.Add("Invalid capability should return a blocked reason.")
}

$IssuesText = @($Issues + ($Results | ForEach-Object { $_.issues } | Where-Object { $_ })) | ForEach-Object { $_ } | Select-Object -Unique
$Status = if ($IssuesText.Count -eq 0) { "pass" } else { "fail" }

$Report = [pscustomobject]@{
    status = $Status
    registry_path = $RegistryPath
    tool_count = if ($Summary) { [int]$Summary.tool_count } else { 0 }
    passed_count = $Passed
    failed_count = $Failed
    issues = @($IssuesText)
    results = $Results
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if ($Status -ne "pass" -and -not $NoThrow) { throw "PDA tool registry validation failed." }
    return
}

if ($Status -eq "pass") {
    Write-Host "[OK] PDA tool registry validation passed."
}
else {
    Write-Host "[ERROR] PDA tool registry validation failed."
    foreach ($Issue in $IssuesText) {
        Write-Host (" - {0}" -f $Issue)
    }
    if (-not $NoThrow) { throw "PDA tool registry validation failed." }
}
