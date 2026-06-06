[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$HandoffScript = Join-Path $PSScriptRoot "Invoke-PDACommandHandoff.ps1"
$PendingRoot = Join-Path $Root "PDA-Tasks\pending"

if (-not (Test-Path -Path $HandoffScript -PathType Leaf)) {
    throw "Command handoff missing: $HandoffScript"
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

$Results = @()
$Passed = 0
$Failed = 0

$Cases = @(
    [pscustomobject]@{
        name = "known recommendation"
        input = "review my latest findings for the release candidate"
        confirm = $false
        expect_status = "mapped"
        expect_ready = $true
        expect_confirm = $true
        expect_dispatch = $false
        expect_command = "/review"
        marker = "handoff-known-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "ambiguous clarification"
        input = "review and analyze this project"
        confirm = $false
        expect_status = "ambiguous"
        expect_ready = $false
        expect_confirm = $false
        expect_dispatch = $false
        expect_command = ""
        marker = "handoff-ambiguous-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "unknown closed"
        input = "blorf glarb frobnicate"
        confirm = $false
        expect_status = "unknown"
        expect_ready = $false
        expect_confirm = $false
        expect_dispatch = $false
        expect_command = ""
        marker = "handoff-unknown-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "confirmed dispatch"
        input = "analyze this project for handoff dispatch"
        confirm = $true
        expect_status = "mapped"
        expect_ready = $true
        expect_confirm = $false
        expect_dispatch = $true
        expect_command = "/planner"
        marker = "handoff-dispatch-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "research request"
        input = "create a test research task"
        confirm = $false
        expect_status = "mapped"
        expect_ready = $true
        expect_confirm = $true
        expect_dispatch = $false
        expect_command = "/research"
        marker = "handoff-research-$([guid]::NewGuid().ToString())"
    }
)

foreach ($Case in $Cases) {
    $MarkerInput = "$($Case.input) [$($Case.marker)]"
    $Before = Find-QueueArtifactByMarker -Marker $Case.marker
    if ($Before) {
        throw "Test marker already existed in pending queue: $($Case.marker)"
    }

    $Args = @(
        "-Text", $MarkerInput,
        "-AsJson"
    )
    if ($Case.confirm) {
        $Args += "-ConfirmDispatch"
    }

    $Raw = & pwsh -NoProfile -File $HandoffScript @Args
    $Result = $Raw | ConvertFrom-Json

    $CasePassed = $true
    $Issues = New-Object System.Collections.Generic.List[string]

    if ($Result.interpreter_status -ne $Case.expect_status) {
        $CasePassed = $false
        $Issues.Add("Expected interpreter status '$($Case.expect_status)' but got '$($Result.interpreter_status)'.")
    }

    if ($Case.expect_command -and $Result.recommended_command -ne $Case.expect_command) {
        $CasePassed = $false
        $Issues.Add("Expected recommended command '$($Case.expect_command)' but got '$($Result.recommended_command)'.")
    }

    if (-not $Case.expect_command -and -not [string]::IsNullOrWhiteSpace([string]$Result.recommended_command)) {
        $CasePassed = $false
        $Issues.Add("Non-mapped input should not recommend an executable command.")
    }

    if ([bool]$Result.dispatch_ready -ne [bool]$Case.expect_ready) {
        $CasePassed = $false
        $Issues.Add("Expected dispatch_ready '$($Case.expect_ready)' but got '$($Result.dispatch_ready)'.")
    }

    if ([bool]$Result.requires_confirmation -ne [bool]$Case.expect_confirm) {
        $CasePassed = $false
        $Issues.Add("Expected requires_confirmation '$($Case.expect_confirm)' but got '$($Result.requires_confirmation)'.")
    }

    if (($Result.dispatch_status -eq "submitted") -ne [bool]$Case.expect_dispatch) {
        $CasePassed = $false
        $Issues.Add("Expected dispatch_status submitted '$($Case.expect_dispatch)' but got '$($Result.dispatch_status)'.")
    }

    if ($Result.original_input -notlike "*$($Case.marker)*") {
        $CasePassed = $false
        $Issues.Add("Original input did not round-trip through the handoff output.")
    }

    if ($Result.interpreter_status -in @("ambiguous", "unknown") -and [bool]$Result.dispatch_ready) {
        $CasePassed = $false
        $Issues.Add("Ambiguous/unknown input should not be dispatch ready.")
    }

    if ($Result.dispatch_status -eq "submitted") {
        $PendingMatch = Find-QueueArtifactByMarker -Marker $Case.marker
        if (-not $PendingMatch) {
            $CasePassed = $false
            $Issues.Add("Confirmed dispatch did not create a pending queue task.")
        }
        else {
            $Queued = Get-Content $PendingMatch.FullName -Raw | ConvertFrom-Json
            if ($Queued.command -ne $Case.expect_command) {
                $CasePassed = $false
                $Issues.Add("Queued task command mismatch: $($Queued.command).")
            }
        }
    }
    else {
        $PendingMatch = Find-QueueArtifactByMarker -Marker $Case.marker
        if ($PendingMatch) {
            $CasePassed = $false
            $Issues.Add("Non-confirmed handoff unexpectedly created queue task: $($PendingMatch.FullName)")
        }
    }

    $Results += [pscustomobject]@{
        name = $Case.name
        passed = $CasePassed
        status = $Result.interpreter_status
        command = $Result.recommended_command
        dispatch_status = $Result.dispatch_status
        dispatch_ready = $Result.dispatch_ready
        requires_confirmation = $Result.requires_confirmation
        issues = @($Issues)
    }

    if ($CasePassed) {
        $Passed++
    }
    else {
        $Failed++
    }
}

$ScriptContent = Get-Content -Path $HandoffScript -Raw
if ($ScriptContent -notmatch 'Submit-PDATask\.ps1') {
    throw "Handoff script does not use the governed submitter."
}

if ($ScriptContent -match 'Invoke-PDAWorker\.ps1|process-pda-queue\.ps1|Start-PDAQueueWorker\.ps1') {
    throw "Handoff script contains a queue bypass or direct worker execution path."
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
        throw "PDA command handoff validation failed."
    }
    return
}

Write-Host "[*] PDA command handoff tests"
Write-Host ("Test cases              : {0}" -f $Report.test_case_count)
Write-Host ("Passed                  : {0}" -f $Report.passed_count)
Write-Host ("Failed                  : {0}" -f $Report.failed_count)
Write-Host ("Dispatch confirmed      : {0}" -f $Report.dispatch_confirmed_count)
Write-Host ("Dispatch blocked        : {0}" -f $Report.dispatch_blocked_count)
Write-Host ("Source of truth         : {0}" -f $Report.source_of_truth)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA command handoff validation failed."
}
