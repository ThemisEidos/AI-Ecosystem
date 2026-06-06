[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$WorkerScript = Join-Path $PSScriptRoot "Invoke-PDAReporterWorker.ps1"
$LookupScript = Join-Path $PSScriptRoot "Get-PDATaskResult.ps1"
$ResultsRoot = Join-Path $Root "PDA-Tasks\results"
$TempRoot = Join-Path $Root "tmp\reporter-worker-validation"

if (-not (Test-Path -Path $WorkerScript -PathType Leaf)) {
    throw "Reporter worker missing: $WorkerScript"
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

function Invoke-ReporterWorker {
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
    direct_litellm_request  = [bool]([regex]::IsMatch($WorkerSource, 'http://localhost:4000/v1/chat/completions'))
    direct_adapter_call     = [bool]([regex]::IsMatch($WorkerSource, 'Invoke-PDAModel\.ps1'))
    stage_worker_calls      = [bool](
        [regex]::IsMatch($WorkerSource, 'Invoke-PDATimelineWorker\.ps1') -and
        [regex]::IsMatch($WorkerSource, 'Invoke-PDAFindingsWorker\.ps1') -and
        [regex]::IsMatch($WorkerSource, 'Invoke-PDAResearchWorker\.ps1') -and
        [regex]::IsMatch($WorkerSource, 'Invoke-PDADraftWorker\.ps1') -and
        [regex]::IsMatch($WorkerSource, 'Invoke-PDAReviewWorker\.ps1')
    )
}
if ($BypassScan.legacy_queue_reference) {
    $Issues.Add("Reporter worker references legacy queue paths.")
}
if ($BypassScan.direct_litellm_request) {
    $Issues.Add("Reporter worker still calls LiteLLM directly.")
}
if ($BypassScan.direct_adapter_call) {
    $Issues.Add("Reporter worker should not call the model adapter directly.")
}
if (-not $BypassScan.stage_worker_calls) {
    $Issues.Add("Reporter worker does not call the expected stage worker scripts.")
}

$TaskId = [guid]::NewGuid().ToString()
$ConversationId = "conv-reporter-" + $TaskId.Substring(0, 8)
$SessionId = "sess-reporter-" + $TaskId.Substring(9, 8)
$UserId = "user-reporter-validation"
$ConversationTitle = "Reporter pipeline validation"
$SourcePath = Join-Path $TempRoot "$TaskId-source.md"
$TaskPath = Join-Path $TempRoot "$TaskId-task.json"
$SourceContent = @"
# Reporter Source Notes

- Validate the operational reporter pipeline
- Preserve queue lifecycle
- Keep governance intact
- Surface final result through the task result lookup
"@
$SourceContent | Set-Content -Path $SourcePath -Encoding UTF8

$Task = [ordered]@{
    task_id            = $TaskId
    command            = "/reporter"
    classification     = "category_1"
    category           = "category_1"
    approved           = $true
    source_path        = $SourcePath
    project            = "AI Ecosystem"
    conversation_id    = $ConversationId
    session_id         = $SessionId
    user_id            = $UserId
    conversation_title = $ConversationTitle
}
$Task | ConvertTo-Json -Depth 10 | Set-Content -Path $TaskPath -Encoding UTF8

$SuccessResult = $null
$FailureResult = $null

try {
    $SuccessResult = Invoke-ReporterWorker -TaskPath $TaskPath
}
catch {
    $Issues.Add("Reporter worker execution threw unexpectedly: $($_.Exception.Message)")
}

$SuccessArtifactPath = Join-Path $ResultsRoot "$TaskId-result.json"
if (-not $SuccessResult) {
    $Issues.Add("Reporter worker did not return a result contract.")
}
else {
    if ([string]$SuccessResult.status -ne "success") {
        $Issues.Add("Expected success status but got '$($SuccessResult.status)'.")
    }
    if ([string]$SuccessResult.worker -ne "reporter-worker") {
        $Issues.Add("Expected worker reporter-worker.")
    }
    if ([string]$SuccessResult.result_path -ne $SuccessArtifactPath) {
        $Issues.Add("Canonical result path mismatch.")
    }
    if ([string]$SuccessResult.saved_path -eq "") {
        $Issues.Add("saved_path is empty on success.")
    }
    elseif (-not (Test-Path -Path $SuccessResult.saved_path -PathType Leaf)) {
        $Issues.Add("Reporter markdown output was not created.")
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
            if ([string]$StoredResult.status -ne "success") {
                $Issues.Add("Stored result status mismatch.")
            }
            if ([string]$StoredResult.result_path -ne $SuccessArtifactPath) {
                $Issues.Add("Stored result does not point to the canonical artifact path.")
            }
        }
        catch {
            $Issues.Add("Stored result artifact is not valid JSON.")
        }
    }

    $Pipeline = if ($SuccessResult.output.pipeline) { ConvertTo-PDAHashtable -Value $SuccessResult.output.pipeline } else { $null }
    if (-not $Pipeline) {
        $Issues.Add("Reporter result did not include a pipeline payload.")
    }
    else {
        if ([int]$Pipeline.stage_count -ne 5) {
            $Issues.Add("Reporter pipeline should include five stages.")
        }
        if ([int]$Pipeline.completed_stage_count -ne 5) {
            $Issues.Add("Reporter pipeline should complete all five stages on the success path.")
        }

        $StageNames = @($Pipeline.stages | ForEach-Object { [string]$_.stage })
        if (("timeline,findings,research,draft,review") -ne ($StageNames -join ",")) {
            $Issues.Add("Reporter stage order mismatch.")
        }

        foreach ($Stage in @($Pipeline.stages)) {
            if ([string]::IsNullOrWhiteSpace([string]$Stage.saved_path)) {
                $Issues.Add("Reporter stage '$($Stage.stage)' did not record a saved path.")
            }
            elseif (-not (Test-Path -Path ([string]$Stage.saved_path) -PathType Leaf)) {
                $Issues.Add("Reporter stage '$($Stage.stage)' saved path does not exist.")
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$Pipeline.final_review.content)) {
            $Issues.Add("Reporter pipeline did not surface final review content.")
        }

        $Artifacts = ConvertTo-PDAHashtable -Value $Pipeline.artifacts
        foreach ($Key in @("timeline", "findings", "research", "draft", "review", "final_report")) {
            if ([string]::IsNullOrWhiteSpace([string]$Artifacts[$Key])) {
                $Issues.Add("Reporter pipeline artifact '$Key' is missing.")
            }
        }
    }
}

$LookupResult = $null
try {
    $LookupRaw = & pwsh -NoProfile -File $LookupScript -ConversationId $ConversationId -TaskId $TaskId -AsJson -NoThrow 2>&1
    $LookupText = [string]($LookupRaw -join "`n").Trim()
    if (-not [string]::IsNullOrWhiteSpace($LookupText)) {
        $LookupResult = $LookupText | ConvertFrom-Json -ErrorAction Stop
    }
}
catch {
    $Issues.Add("Lookup path threw unexpectedly: $($_.Exception.Message)")
}

if (-not $LookupResult) {
    $Issues.Add("Task lookup did not return a result.")
}
else {
    if ([string]$LookupResult.conversation_id -ne $ConversationId) {
        $Issues.Add("Lookup conversation_id mismatch.")
    }
    if ([string]$LookupResult.latest_task_id -ne $TaskId) {
        $Issues.Add("Lookup latest_task_id mismatch.")
    }
    if ([string]$LookupResult.latest_task_status -ne "completed") {
        $Issues.Add("Lookup latest_task_status should be completed.")
    }
    if ([string]$LookupResult.latest_result_path -ne $SuccessArtifactPath) {
        $Issues.Add("Lookup latest_result_path mismatch.")
    }
    if ([string]$LookupResult.result_artifact_path -ne $SuccessArtifactPath) {
        $Issues.Add("Lookup result_artifact_path mismatch.")
    }
    if (-not $LookupResult.result_artifact) {
        $Issues.Add("Lookup did not return the result artifact payload.")
    }
    elseif ([string]$LookupResult.result_artifact.status -ne "success") {
        $Issues.Add("Lookup result artifact status mismatch.")
    }
}

$FailureTaskId = [guid]::NewGuid().ToString()
$FailureTaskPath = Join-Path $TempRoot "$FailureTaskId-missing-source-task.json"
$FailureTask = [ordered]@{
    task_id            = $FailureTaskId
    command            = "/reporter"
    classification     = "category_1"
    category           = "category_1"
    approved           = $true
    project            = "AI Ecosystem"
    conversation_id    = "conv-failure-$($FailureTaskId.Substring(0,8))"
    session_id         = "sess-failure-$($FailureTaskId.Substring(9,8))"
    user_id            = $UserId
    conversation_title = "Reporter failure validation"
}
$FailureTask | ConvertTo-Json -Depth 10 | Set-Content -Path $FailureTaskPath -Encoding UTF8

try {
    $FailureResult = Invoke-ReporterWorker -TaskPath $FailureTaskPath
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
    status             = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    worker_script      = $WorkerScript
    lookup_script      = $LookupScript
    results_root       = $ResultsRoot
    test_case_count    = 2
    passed_count       = if ($Issues.Count -eq 0) { 2 } else { 0 }
    failed_count       = if ($Issues.Count -eq 0) { 0 } else { 1 }
    bypass_scan        = $BypassScan
    success_result     = if ($SuccessResult) { $SuccessResult } else { $null }
    failure_result     = if ($FailureResult) { $FailureResult } else { $null }
    lookup_result      = if ($LookupResult) { $LookupResult } else { $null }
    issues             = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 30
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "Reporter worker validation failed."
    }
    return
}

Write-Host "[*] PDA reporter worker validation"
Write-Host ("Status     : {0}" -f $Report.status)
Write-Host ("Results    : {0}" -f $ResultsRoot)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "Reporter worker validation failed."
}
