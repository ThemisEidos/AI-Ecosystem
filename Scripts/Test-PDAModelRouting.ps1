[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$RouteScript = Join-Path $PSScriptRoot "Get-PDAModelRoute.ps1"
$PolicyPath = Join-Path $PSScriptRoot "PDA_ModelRouting.json"

if (-not (Test-Path -LiteralPath $RouteScript -PathType Leaf)) {
    throw "Model routing script missing: $RouteScript"
}
if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
    throw "Model routing policy missing: $PolicyPath"
}

function Invoke-Route {
    param(
        [string]$WorkerName,
        [string]$TaskType,
        [string]$Command,
        [string]$Category = "category_1",
        [string]$Sensitivity = "standard"
    )

    $Args = @(
        "-PolicyPath", $PolicyPath,
        "-Category", $Category,
        "-Sensitivity", $Sensitivity,
        "-AsJson",
        "-NoThrow"
    )
    if (-not [string]::IsNullOrWhiteSpace($WorkerName)) {
        $Args += @("-WorkerName", $WorkerName)
    }
    if (-not [string]::IsNullOrWhiteSpace($TaskType)) {
        $Args += @("-TaskType", $TaskType)
    }
    if (-not [string]::IsNullOrWhiteSpace($Command)) {
        $Args += @("-Command", $Command)
    }

    $Raw = & pwsh -NoProfile -File $RouteScript @Args 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Route script returned empty output."
    }

    return $Text | ConvertFrom-Json
}

$Cases = @(
    [pscustomobject]@{
        name = "research category_1"
        worker_name = "research-worker"
        task_type = "research"
        command = "/research"
        category = "category_1"
        expected_status = "pass"
        expected_model = "gemini"
        expected_fallback_chain = @("openrouter")
        expected_cloud_allowed = $true
    }
    [pscustomobject]@{
        name = "review category_1"
        worker_name = "review-worker"
        task_type = "review"
        command = "/review"
        category = "category_1"
        expected_status = "pass"
        expected_model = "claude"
        expected_fallback_chain = @("openai")
        expected_cloud_allowed = $true
    }
    [pscustomobject]@{
        name = "draft category_1"
        worker_name = "draft-worker"
        task_type = "draft"
        command = "/draft"
        category = "category_1"
        expected_status = "pass"
        expected_model = "openai"
        expected_fallback_chain = @("claude")
        expected_cloud_allowed = $true
    }
    [pscustomobject]@{
        name = "execute category_1"
        worker_name = "execute-worker"
        task_type = "execute"
        command = "/execute"
        category = "category_1"
        expected_status = "pass"
        expected_model = "local-llama"
        expected_fallback_chain = @()
        expected_cloud_allowed = $false
    }
    [pscustomobject]@{
        name = "category_2 local only"
        worker_name = "review-worker"
        task_type = "review"
        command = "/review"
        category = "category_2"
        expected_status = "pass"
        expected_model = "local-llama"
        expected_fallback_chain = @()
        expected_cloud_allowed = $false
    }
    [pscustomobject]@{
        name = "restricted_local local only"
        worker_name = "draft-worker"
        task_type = "draft"
        command = "/draft"
        category = "category_1"
        sensitivity = "restricted_local"
        expected_status = "pass"
        expected_model = "local-llama"
        expected_fallback_chain = @()
        expected_cloud_allowed = $false
    }
    [pscustomobject]@{
        name = "unknown command fails"
        worker_name = ""
        task_type = ""
        command = "/unknown"
        category = "category_1"
        expected_status = "fail"
        expected_model = ""
        expected_fallback_chain = @()
        expected_cloud_allowed = $false
    }
)

$Results = @()
$Passed = 0
$Failed = 0

foreach ($Case in $Cases) {
    $Result = Invoke-Route -WorkerName $Case.worker_name -TaskType $Case.task_type -Command $Case.command -Category $Case.category -Sensitivity $Case.sensitivity
    $Issues = New-Object System.Collections.Generic.List[string]

    if ([string]$Result.status -ne [string]$Case.expected_status) {
        $Issues.Add("Expected status '$($Case.expected_status)' but got '$($Result.status)'.")
    }
    if ([string]$Result.selected_model -ne [string]$Case.expected_model) {
        $Issues.Add("Expected selected model '$($Case.expected_model)' but got '$($Result.selected_model)'.")
    }
    if ((@($Result.fallback_chain) -join ",") -ne (@($Case.expected_fallback_chain) -join ",")) {
        $Issues.Add("Expected fallback chain '$(@($Case.expected_fallback_chain) -join ',')' but got '$(@($Result.fallback_chain) -join ',')'.")
    }
    if ([bool]$Result.cloud_allowed -ne [bool]$Case.expected_cloud_allowed) {
        $Issues.Add("Expected cloud_allowed '$($Case.expected_cloud_allowed)' but got '$($Result.cloud_allowed)'.")
    }
    if ($Case.expected_status -eq "pass" -and [string]$Result.routing_gateway -ne "litellm") {
        $Issues.Add("Routing gateway should remain litellm.")
    }
    if ($Case.name -eq "category_2 local only" -and ($Result.selected_model -ne "local-llama" -or $Result.cloud_allowed)) {
        $Issues.Add("Category 2 route must remain local-only.")
    }

    $CasePassed = ($Issues.Count -eq 0)
    $Results += [pscustomobject]@{
        name = $Case.name
        passed = $CasePassed
        command = $Result.command
        category = $Result.category
        selected_model = $Result.selected_model
        fallback_chain = @($Result.fallback_chain)
        routing_reason = $Result.routing_reason
        cloud_allowed = [bool]$Result.cloud_allowed
        status = $Result.status
        issues = @($Issues)
    }

    if ($CasePassed) {
        $Passed++
    }
    else {
        $Failed++
    }
}

$Report = [pscustomobject]@{
    status = if ($Failed -eq 0) { "pass" } else { "fail" }
    policy_path = $PolicyPath
    route_script = $RouteScript
    test_case_count = $Cases.Count
    passed_count = $Passed
    failed_count = $Failed
    results = @($Results)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA model routing validation failed."
    }
    return
}

Write-Host "[*] PDA model routing tests"
Write-Host ("Test cases : {0}" -f $Report.test_case_count)
Write-Host ("Passed     : {0}" -f $Report.passed_count)
Write-Host ("Failed     : {0}" -f $Report.failed_count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA model routing validation failed."
}
