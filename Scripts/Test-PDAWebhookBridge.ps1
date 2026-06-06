[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$WebhookScript = Join-Path $PSScriptRoot "Invoke-PDAWebhookBridge.ps1"
$BridgeScript = Join-Path $PSScriptRoot "Invoke-PDAChatBridge.ps1"
$PendingRoot = Join-Path $Root "PDA-Tasks\pending"

if (-not (Test-Path -Path $WebhookScript -PathType Leaf)) {
    throw "Webhook bridge missing: $WebhookScript"
}

function Find-QueueArtifactByMarker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Marker
    )

    Get-ChildItem -Path $PendingRoot -Filter *.json -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $Content = Get-Content $_.FullName -Raw -ErrorAction Stop
                return ($Content -match [regex]::Escape($Marker))
            }
            catch {
                return $false
            }
        } |
        Select-Object -First 1
}

$ScriptContent = Get-Content -Path $WebhookScript -Raw
if ($ScriptContent -notmatch 'Invoke-PDAChatBridge\.ps1') {
    throw "Webhook bridge does not call the chat bridge."
}

if ($ScriptContent -match 'Submit-PDATask\.ps1|Invoke-PDAWorker\.ps1|process-pda-queue\.ps1|Start-PDAQueueWorker\.ps1') {
    throw "Webhook bridge contains a queue bypass or direct worker execution path."
}

$Results = @()
$Passed = 0
$Failed = 0

$Cases = @(
    [pscustomobject]@{
        name = "valid request"
        message = "review my latest findings for the webhook bridge"
        confirm = $false
        expect_status = "mapped"
        expect_dispatch = $false
        expect_command = "/review"
        expect_response_contains = "Recommended command"
        marker = "webhook-known-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "ambiguous request"
        message = "review and analyze this project"
        confirm = $false
        expect_status = "ambiguous"
        expect_dispatch = $false
        expect_command = ""
        expect_response_contains = "Clarification required"
        marker = "webhook-ambiguous-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "unknown request"
        message = "blorf glarb frobnicate"
        confirm = $false
        expect_status = "unknown"
        expect_dispatch = $false
        expect_command = ""
        expect_response_contains = "No governed command matched"
        marker = "webhook-unknown-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "confirmed dispatch"
        message = "review my latest findings for webhook dispatch"
        confirm = $true
        expect_status = "mapped"
        expect_dispatch = $true
        expect_command = "/review"
        expect_response_contains = "Dispatched via governed PDA handoff"
        marker = "webhook-dispatch-$([guid]::NewGuid().ToString())"
    }
)

foreach ($Case in $Cases) {
    $MarkerMessage = "$($Case.message) [$($Case.marker)]"
    $Before = Find-QueueArtifactByMarker -Marker $Case.marker
    if ($Before) {
        throw "Test marker already existed in pending queue: $($Case.marker)"
    }

    $Args = @(
        "-Message", $MarkerMessage,
        "-AsJson"
    )
    if ($Case.confirm) {
        $Args += "-ConfirmDispatch"
    }

    $Raw = & pwsh -NoProfile -File $WebhookScript @Args
    $Result = $Raw | ConvertFrom-Json

    $CasePassed = $true
    $Issues = New-Object System.Collections.Generic.List[string]

    if ($Result.handoff_status -ne $Case.expect_status) {
        $CasePassed = $false
        $Issues.Add("Expected handoff status '$($Case.expect_status)' but got '$($Result.handoff_status)'.")
    }

    if ($Result.response_text -notlike "*$($Case.expect_response_contains)*") {
        $CasePassed = $false
        $Issues.Add("Response text did not include expected guidance.")
    }

    if ($Case.expect_command -and $Result.recommended_command -ne $Case.expect_command) {
        $CasePassed = $false
        $Issues.Add("Expected recommended command '$($Case.expect_command)' but got '$($Result.recommended_command)'.")
    }

    if (-not $Case.expect_command -and -not [string]::IsNullOrWhiteSpace([string]$Result.recommended_command)) {
        $CasePassed = $false
        $Issues.Add("Non-mapped input should not recommend an executable command.")
    }

    if (($Result.dispatch_status -eq "submitted") -ne [bool]$Case.expect_dispatch) {
        $CasePassed = $false
        $Issues.Add("Dispatch status mismatch.")
    }

    if ($Result.original_message -notlike "*$($Case.marker)*") {
        $CasePassed = $false
        $Issues.Add("Original message did not round-trip through the webhook bridge output.")
    }

    $JsonRoundTrip = $null
    try {
        $JsonRoundTrip = $Result | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    }
    catch {
        $CasePassed = $false
        $Issues.Add("Webhook bridge output did not round-trip as JSON.")
    }

    if ($Case.confirm -and $Result.dispatch_status -eq "submitted") {
        if ([string]::IsNullOrWhiteSpace([string]$Result.dispatch_path) -or -not (Test-Path -Path $Result.dispatch_path -PathType Leaf)) {
            $CasePassed = $false
            $Issues.Add("Confirmed webhook bridge dispatch did not return a valid dispatch path.")
        }
    }
    elseif (-not $Case.confirm) {
        $Match = Find-QueueArtifactByMarker -Marker $Case.marker
        if ($Match) {
            $CasePassed = $false
            $Issues.Add("Non-confirmed webhook bridge call unexpectedly created queue work.")
        }
    }

    if ($JsonRoundTrip -and $JsonRoundTrip.source_of_truth -ne "Scripts/PDA_CommandInterpreter.ps1") {
        $CasePassed = $false
        $Issues.Add("Bridge source of truth changed unexpectedly.")
    }

    $Results += [pscustomobject]@{
        name = $Case.name
        passed = $CasePassed
        status = $Result.handoff_status
        response_text = $Result.response_text
        dispatch_status = $Result.dispatch_status
        dispatch_ready = $Result.dispatch_ready
        issues = @($Issues)
    }

    if ($CasePassed) {
        $Passed++
    }
    else {
        $Failed++
    }
}

$Total = $Cases.Count
$Report = [pscustomobject]@{
    status = if ($Failed -eq 0) { "pass" } else { "fail" }
    test_case_count = $Total
    passed_count = $Passed
    failed_count = $Failed
    dispatch_confirmed_count = @($Results | Where-Object { $_.dispatch_status -eq "submitted" }).Count
    dispatch_blocked_count = @($Results | Where-Object { $_.dispatch_status -eq "blocked" }).Count
    source_of_truth = "Scripts/PDA_CommandInterpreter.ps1"
    results = @($Results)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA webhook bridge validation failed."
    }
    return
}

Write-Host "[*] PDA webhook bridge tests"
Write-Host ("Test cases              : {0}" -f $Report.test_case_count)
Write-Host ("Passed                  : {0}" -f $Report.passed_count)
Write-Host ("Failed                  : {0}" -f $Report.failed_count)
Write-Host ("Dispatch confirmed      : {0}" -f $Report.dispatch_confirmed_count)
Write-Host ("Dispatch blocked        : {0}" -f $Report.dispatch_blocked_count)
Write-Host ("Source of truth         : {0}" -f $Report.source_of_truth)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA webhook bridge validation failed."
}
