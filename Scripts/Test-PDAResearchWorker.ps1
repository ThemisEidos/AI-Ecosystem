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
$FabricScript = Join-Path $PSScriptRoot "Invoke-PDAFabricPattern.ps1"
$ResultsRoot = Join-Path $Root "PDA-Tasks\results"
$TempRoot = Join-Path $Root "tmp\research-worker-validation"
. (Join-Path $PSScriptRoot "Test-PDAAssertions.ps1")

if (-not (Test-Path -Path $WorkerScript -PathType Leaf)) {
    throw "Research worker missing: $WorkerScript"
}

function ConvertTo-PDAHashtable {
    param([Parameter(Mandatory = $true)]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [hashtable] -or $Value -is [System.Collections.IDictionary]) {
        $Copy = @{}
        foreach ($Key in $Value.Keys) {
            if ($null -eq $Value[$Key]) {
                $Copy[$Key] = $null
            }
            else {
                $Copy[$Key] = ConvertTo-PDAHashtable -Value $Value[$Key]
            }
        }
        return $Copy
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $List = @()
        foreach ($Item in $Value) {
            if ($null -eq $Item) {
                $List += $null
            }
            else {
                $List += ,(ConvertTo-PDAHashtable -Value $Item)
            }
        }
        return $List
    }

    if ($Value -is [psobject] -and $Value.PSObject.Properties.Name.Count -gt 0) {
        $Copy = @{}
        foreach ($Prop in $Value.PSObject.Properties) {
            if ($null -eq $Prop.Value) {
                $Copy[$Prop.Name] = $null
            }
            else {
                $Copy[$Prop.Name] = ConvertTo-PDAHashtable -Value $Prop.Value
            }
        }
        return $Copy
    }

    return $Value
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

New-Item -ItemType Directory -Force -Path $TempRoot, $ResultsRoot | Out-Null

$Issues = New-Object System.Collections.Generic.List[string]

$WorkerSource = Get-Content -Path $WorkerScript -Raw
$LegacyQueuePattern = '(?i)(?<!PDA-)Tasks\\(queued|running|completed|failed|results)'
$BypassScan = [pscustomobject]@{
    legacy_queue_reference = [bool]([regex]::IsMatch($WorkerSource, $LegacyQueuePattern))
    direct_litellm_request = [bool]([regex]::IsMatch($WorkerSource, 'http://localhost:4000/v1/chat/completions'))
    adapter_call = [bool]([regex]::IsMatch($WorkerSource, 'Invoke-PDAModel\.ps1'))
    fabric_renderer_call = [bool]([regex]::IsMatch($WorkerSource, 'Invoke-PDAFabricPattern\.ps1'))
    direct_fabric_model_call = [bool]([regex]::IsMatch($WorkerSource, '(?i)(fabric\s+--pattern|Invoke-RestMethod|chat/completions)'))
}
if ($BypassScan.legacy_queue_reference) {
    $Issues.Add("Research worker references legacy queue paths.")
}
if ($BypassScan.direct_litellm_request) {
    $Issues.Add("Research worker still calls LiteLLM directly.")
}
if (-not $BypassScan.adapter_call) {
    $Issues.Add("Research worker does not call Invoke-PDAModel.ps1.")
}
if (-not $BypassScan.fabric_renderer_call) {
    $Issues.Add("Research worker does not call the Fabric renderer helper.")
}
if ($BypassScan.direct_fabric_model_call) {
    $Issues.Add("Research worker should not call a Fabric model transport directly.")
}

$TaskId = [guid]::NewGuid().ToString()
$SourcePath = Join-Path $TempRoot "$TaskId-source.md"
$TaskPath = Join-Path $TempRoot "$TaskId-task.json"
$SourceContent = @"
# Topic

Summarize the current research findings for the PDA system.
"@
$SourceContent | Set-Content -Path $SourcePath -Encoding UTF8

$Task = [ordered]@{
    task_id = $TaskId
    command = "/research"
    classification = "category_3"
    category = "category_3"
    approved = $true
    source_path = $SourcePath
    target = "Summarize the current research findings for the PDA system."
    project = "AI Ecosystem"
}
$Task | ConvertTo-Json -Depth 10 | Set-Content -Path $TaskPath -Encoding UTF8

$SuccessResult = $null
$FailureResult = $null

try {
    $SuccessResult = Invoke-ResearchWorker -TaskPath $TaskPath
}
catch {
    $Issues.Add("Research worker execution threw unexpectedly: $($_.Exception.Message)")
}

$SuccessArtifactPath = Join-Path $ResultsRoot "$TaskId-result.json"
if (-not $SuccessResult) {
    $Issues.Add("Research worker did not return a result contract.")
}
else {
    if ($SuccessResult.status -notin @("success", "failed")) {
        $Issues.Add("Unexpected status returned by research worker: '$($SuccessResult.status)'.")
    }
    if ([string]$SuccessResult.worker -ne "research-worker") {
        $Issues.Add("Expected worker research-worker.")
    }
    if ([string]$SuccessResult.result_path -ne $SuccessArtifactPath) {
        $Issues.Add("Canonical result path mismatch.")
    }
    if (-not (Test-Path -Path $SuccessArtifactPath -PathType Leaf)) {
        $Issues.Add("Canonical result artifact was not written.")
    }
    else {
        try {
            $StoredResult = Get-Content -Path $SuccessArtifactPath -Raw | ConvertFrom-Json
            if ([string]$StoredResult.task_id -ne $TaskId) {
                $Issues.Add("Stored result task_id mismatch.")
            }
            if ([string]$StoredResult.result_path -ne $SuccessArtifactPath) {
                $Issues.Add("Stored result does not point to the canonical artifact path.")
            }
        }
        catch {
            $Issues.Add("Stored result artifact is not valid JSON.")
        }
    }

    if ($SuccessResult.status -eq "success") {
        if ([string]::IsNullOrWhiteSpace([string]$SuccessResult.saved_path)) {
            $Issues.Add("saved_path is empty on success.")
        }
        elseif (-not (Test-Path -Path $SuccessResult.saved_path -PathType Leaf)) {
            $Issues.Add("Research markdown output was not created.")
        }

        $ModelRoute = if ($SuccessResult.output.model_route) { ConvertTo-PDAHashtable -Value $SuccessResult.output.model_route } else { $null }
        if (-not $ModelRoute) {
            $Issues.Add("Research result did not include a model_route payload.")
        }
        else {
            try {
                Assert-ValidRouteSource -RouteSource $ModelRoute.route_source -Context standard
            }
            catch {
                $Issues.Add($_.Exception.Message)
            }
            if ($ModelRoute.via_litellm -ne $true) {
                $Issues.Add("Research worker should use LiteLLM.")
            }
            if (-not (@("gemini","openrouter") -contains [string]$ModelRoute.selected_model)) {
                $Issues.Add("Research worker did not select a gemini/openrouter route.")
            }
        }
        
        $Fabric = if ($SuccessResult.output.fabric) { ConvertTo-PDAHashtable -Value $SuccessResult.output.fabric } else { $null }
        if (-not $Fabric) {
            $Issues.Add("Research result did not include a fabric payload.")
        }
        else {
            if ([string]$Fabric.default_pattern -ne "Research/research-synthesis") {
                $Issues.Add("Research worker default_pattern should resolve from the registry.")
            }
            if ([bool]$Fabric.used -ne $true) {
                $Issues.Add("Research worker should use the Fabric renderer when default_pattern exists.")
            }
            if ([string]$Fabric.render_status -ne "success") {
                $Issues.Add("Research Fabric render status should be success.")
            }
        $ModelRequest = if ($SuccessResult.output.model_request) { ConvertTo-PDAHashtable -Value $SuccessResult.output.model_request } else { $null }
        if (-not $ModelRequest) {
            $Issues.Add("Research result did not include a model_request payload.")
        }
        elseif ([string]::IsNullOrWhiteSpace([string]$ModelRequest.prompt) -or [string]$ModelRequest.prompt -notmatch '# PDA Fabric Research Pattern') {
            $Issues.Add("Rendered prompt was not passed into the model adapter.")
        }
    }

        $Fallback = if ($SuccessResult.output.fallback) { ConvertTo-PDAHashtable -Value $SuccessResult.output.fallback } else { $null }
        if (-not $Fallback) {
            $Issues.Add("Research result did not include a fallback payload.")
        }
        else {
            if ([bool]$Fallback.allowed -ne $true) {
                $Issues.Add("Research worker fallback should be allowed for standard routes.")
            }
            if ([bool]$Fallback.used -ne $false) {
                $Issues.Add("Research worker should not report fallback used on the primary route case.")
            }
            if ([int]$Fallback.attempt_count -lt 1) {
                $Issues.Add("Research worker fallback attempt count is invalid.")
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$SuccessResult.output.content)) {
            $Issues.Add("Research worker returned empty markdown content.")
        }
        if ([string]$SuccessResult.next_worker -ne "review-worker") {
            $Issues.Add("Research worker should hand off to review-worker.")
        }
    }
    else {
        if ([string]::IsNullOrWhiteSpace([string]$SuccessResult.output.error)) {
            $Issues.Add("Failure path should include an error message.")
        }
    }
}

$FailureTaskId = [guid]::NewGuid().ToString()
$FailureTaskPath = Join-Path $TempRoot "$FailureTaskId-missing-input-task.json"
$FailureTask = [ordered]@{
    task_id = $FailureTaskId
    command = "/research"
    classification = "category_3"
    category = "category_3"
    approved = $true
    project = "AI Ecosystem"
}
$FailureTask | ConvertTo-Json -Depth 10 | Set-Content -Path $FailureTaskPath -Encoding UTF8

try {
    $FailureResult = Invoke-ResearchWorker -TaskPath $FailureTaskPath
}
catch {
    $Issues.Add("Failure case threw unexpectedly: $($_.Exception.Message)")
}

$FailureArtifactPath = Join-Path $ResultsRoot "$FailureTaskId-result.json"
if (-not $FailureResult) {
    $Issues.Add("Failure case did not return a result contract.")
}
else {
    if ($FailureResult.status -ne "failed") {
        $Issues.Add("Failure case should return failed status.")
    }
    if ([string]::IsNullOrWhiteSpace([string]$FailureResult.output.error)) {
        $Issues.Add("Failure case should include an error message.")
    }
    if (-not (Test-Path -Path $FailureArtifactPath -PathType Leaf)) {
        $Issues.Add("Failure case did not write a canonical result artifact.")
    }
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    worker_script = $WorkerScript
    results_root = $ResultsRoot
    test_case_count = 2
    passed_count = if ($Issues.Count -eq 0) { 2 } else { 0 }
    failed_count = if ($Issues.Count -eq 0) { 0 } else { 1 }
    bypass_scan = $BypassScan
    success_result = if ($SuccessResult) { $SuccessResult } else { $null }
    failure_result = if ($FailureResult) { $FailureResult } else { $null }
    issues = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "Research worker validation failed."
    }
    return
}

Write-Host "[*] PDA research worker validation"
Write-Host ("Status     : {0}" -f $Report.status)
Write-Host ("Results    : {0}" -f $ResultsRoot)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "Research worker validation failed."
}
