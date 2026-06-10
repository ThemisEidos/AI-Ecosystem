[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$InvokeScript = Join-Path $PSScriptRoot "Invoke-PDAModel.ps1"
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
$RoutingLogRoot = Join-Path $Root "PDA-Logs\routing"

if (-not (Test-Path -Path $InvokeScript -PathType Leaf)) {
    throw "Model invocation adapter missing: $InvokeScript"
}
if (Test-Path -LiteralPath $ParserPath -PathType Leaf) {
    . $ParserPath
}

function Invoke-TestCase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$WorkerName,

        [Parameter(Mandatory = $false)]
        [string]$TaskType,

        [Parameter(Mandatory = $true)]
        [string]$Sensitivity,

        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter(Mandatory = $true)]
    [string]$ExpectedModel,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedToken,

    [Parameter(Mandatory = $false)]
    [switch]$AllowUnavailable
    )

    $Args = @(
        "-WorkerName", $WorkerName,
        "-Sensitivity", $Sensitivity,
        "-Prompt", $Prompt,
        "-NoThrow",
        "-AsJson"
    )
    if (-not [string]::IsNullOrWhiteSpace($TaskType)) {
        $Args += @("-TaskType", $TaskType)
    }

    $Raw = & pwsh -NoProfile -File $InvokeScript @Args 2>&1

    $JsonText = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        throw "Adapter returned empty output for test case '$Name'."
    }

    $Result = ConvertFrom-PDAMixedJson -Text $JsonText -SourceName $InvokeScript
    if (-not $Result) {
        throw "Adapter output could not be parsed as JSON for test case '$Name'."
    }
    $Issues = New-Object System.Collections.Generic.List[string]
    $Skipped = $false

    if ($AllowUnavailable -and $Result.status -ne "pass" -and $Result.response.http_status -in @(401, 403, 404, 429, 500, 502, 503, 504)) {
        $Skipped = $true
    }
    else {
        if ($Result.status -ne "pass") {
            $Issues.Add("Expected pass status but got '$($Result.status)'.")
        }
        if ([string]$Result.routing.selected_model -ne $ExpectedModel) {
            $Issues.Add("Expected selected model '$ExpectedModel' but got '$($Result.routing.selected_model)'.")
        }
        if ($Result.routing.sensitivity -eq "restricted_local" -and [string]$Result.routing.selected_model -ne "local-llama") {
            $Issues.Add("Restricted local route did not stay on local-llama.")
        }
        if ($Result.routing.routing_gateway -ne "litellm") {
            $Issues.Add("Routing gateway should be LiteLLM.")
        }
        if ($Result.routing.via_litellm -ne $true) {
            $Issues.Add("Adapter did not mark LiteLLM usage.")
        }
        if ([string]::IsNullOrWhiteSpace([string]$Result.routing_audit_log)) {
            $Issues.Add("Routing audit log path is missing.")
        }
        elseif (-not (Test-Path -Path ([string]$Result.routing_audit_log) -PathType Leaf)) {
            $Issues.Add("Routing audit log file was not created.")
        }
        else {
            $AuditRecord = Get-Content -Path ([string]$Result.routing_audit_log) -Raw | ConvertFrom-Json
            if ([string]$AuditRecord.command -ne [string]$Result.routing.command) {
                $Issues.Add("Routing audit command does not match invocation output.")
            }
            if ([string]$AuditRecord.category -ne [string]$Result.routing.category) {
                $Issues.Add("Routing audit category does not match invocation output.")
            }
            if ([string]$AuditRecord.selected_model -ne [string]$Result.routing.selected_model) {
                $Issues.Add("Routing audit selected_model does not match invocation output.")
            }
            if ([string]$AuditRecord.routing_reason -ne [string]$Result.routing.routing_reason) {
                $Issues.Add("Routing audit routing_reason does not match invocation output.")
            }
            if ([string]$AuditRecord.worker -ne $WorkerName) {
                $Issues.Add("Routing audit worker does not match invocation worker.")
            }
            if ([string]$AuditRecord.outcome -ne [string]$Result.status) {
                $Issues.Add("Routing audit outcome does not match invocation status.")
            }
        }
        if ([string]::IsNullOrWhiteSpace([string]$Result.response_text)) {
            $Issues.Add("Response text is empty.")
        }
        elseif ($Result.response_text -notmatch [regex]::Escape($ExpectedToken)) {
            $Issues.Add("Response text did not contain expected token '$ExpectedToken'.")
        }
    }

    return [pscustomobject]@{
        name = $Name
        passed = ($Issues.Count -eq 0 -and -not $Skipped)
        skipped = $Skipped
        worker_name = $WorkerName
        task_type = $TaskType
        sensitivity = $Sensitivity
        expected_model = $ExpectedModel
        expected_token = $ExpectedToken
        selected_model = [string]$Result.routing.selected_model
        response_text = [string]$Result.response_text
        status = [string]$Result.status
        routing_surface = [string]$Result.routing.routing_surface
        route_source = [string]$Result.routing.route_source
        routing_audit_log = [string]$Result.routing_audit_log
        issues = @($Issues)
    }
}

$Cases = @(
    [pscustomobject]@{
        name = "restricted local invocation"
        worker_name = "review-worker"
        task_type = "review"
        sensitivity = "restricted_local"
        prompt = "Return exactly: local-ok"
        expected_model = "local-llama"
        expected_token = "local-ok"
    }
    [pscustomobject]@{
        name = "research gemini invocation"
        worker_name = "research-worker"
        task_type = "research"
        sensitivity = "standard"
        prompt = "Return exactly: gemini-ok"
        expected_model = "gemini"
        expected_token = "gemini-ok"
        allow_unavailable = $true
    }
)

$Results = @()
$Passed = 0
$Failed = 0
$Skipped = 0

foreach ($Case in $Cases) {
    $CaseResult = Invoke-TestCase -Name $Case.name -WorkerName $Case.worker_name -TaskType $Case.task_type -Sensitivity $Case.sensitivity -Prompt $Case.prompt -ExpectedModel $Case.expected_model -ExpectedToken $Case.expected_token -AllowUnavailable:([bool]$Case.allow_unavailable)
    $Results += $CaseResult
    if ($CaseResult.skipped) {
        $Skipped++
    }
    elseif ($CaseResult.passed) {
        $Passed++
    }
    else {
        $Failed++
    }
}

$Report = [pscustomobject]@{
    status = if ($Failed -eq 0) { "pass" } else { "fail" }
    adapter_path = $InvokeScript
    test_case_count = $Cases.Count
    passed_count = $Passed
    failed_count = $Failed
    skipped_count = $Skipped
    results = @($Results)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA model invocation validation failed."
    }
    return
}

Write-Host "[*] PDA model invocation tests"
Write-Host ("Test cases : {0}" -f $Report.test_case_count)
Write-Host ("Passed     : {0}" -f $Report.passed_count)
Write-Host ("Failed     : {0}" -f $Report.failed_count)
Write-Host ("Skipped    : {0}" -f $Report.skipped_count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA model invocation validation failed."
}
