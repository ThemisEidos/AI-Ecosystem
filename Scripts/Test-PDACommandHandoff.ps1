[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow,

    [Parameter(Mandatory = $false)]
    [switch]$SkipOperatorConsole,

    [Parameter(Mandatory = $false)]
    [switch]$SkipDispatch,

    [Parameter(Mandatory = $false)]
    [switch]$DashboardMode
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$HandoffScript = Join-Path $PSScriptRoot "Invoke-PDACommandHandoff.ps1"
$QueueSearchRoots = @(
    Join-Path $Root "PDA-Tasks\pending"
    Join-Path $Root "PDA-Tasks\running"
    Join-Path $Root "PDA-Tasks\completed"
    Join-Path $Root "PDA-Tasks\failed"
    Join-Path $Root "PDA-Tasks\results"
    Join-Path $Root "PDA-Tasks\approvals\pending"
    Join-Path $Root "PDA-Tasks\approvals\approved"
    Join-Path $Root "PDA-Tasks\approvals\rejected"
)
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
if (Test-Path -Path $ParserPath -PathType Leaf) {
    . $ParserPath
}

if (-not (Test-Path -Path $HandoffScript -PathType Leaf)) {
    throw "Command handoff missing: $HandoffScript"
}

function Find-QueueArtifactByMarker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Marker
    )

    foreach ($SearchRoot in $QueueSearchRoots) {
        if (-not (Test-Path -Path $SearchRoot -PathType Container)) {
            continue
        }

        $Match = Get-ChildItem -Path $SearchRoot -Filter *.json -ErrorAction SilentlyContinue |
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

        if ($Match) {
            return $Match
        }
    }
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
        use_marker_suffix = $false
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
        name = "operator status"
        input = "/status"
        confirm = $false
        expect_status = "mapped"
        expect_ready = $false
        expect_confirm = $false
        expect_dispatch = $false
        expect_dispatch_status = "not_applicable"
        expect_command = "/status"
        expect_response_contains = "COOPER Operator Console: Status"
        marker = "handoff-status-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "operator tasks"
        input = "/tasks"
        confirm = $false
        expect_status = "mapped"
        expect_ready = $false
        expect_confirm = $false
        expect_dispatch = $false
        expect_dispatch_status = "not_applicable"
        expect_command = "/tasks"
        expect_response_contains = "COOPER Operator Console: Tasks"
        marker = "handoff-tasks-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "operator approvals"
        input = "/approvals"
        confirm = $false
        expect_status = "mapped"
        expect_ready = $false
        expect_confirm = $false
        expect_dispatch = $false
        expect_dispatch_status = "not_applicable"
        expect_command = "/approvals"
        expect_response_contains = "COOPER Operator Console: Approvals"
        marker = "handoff-approvals-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "operator workers"
        input = "/workers"
        confirm = $false
        expect_status = "mapped"
        expect_ready = $false
        expect_confirm = $false
        expect_dispatch = $false
        expect_dispatch_status = "not_applicable"
        expect_command = "/workers"
        expect_response_contains = "COOPER Operator Console: Workers"
        marker = "handoff-workers-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "operator reports"
        input = "/reports"
        confirm = $false
        expect_status = "mapped"
        expect_ready = $false
        expect_confirm = $false
        expect_dispatch = $false
        expect_dispatch_status = "not_applicable"
        expect_command = "/reports"
        expect_response_contains = "COOPER Operator Console: Reports"
        marker = "handoff-reports-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "operator memory"
        input = "/memory"
        confirm = $false
        expect_status = "mapped"
        expect_ready = $false
        expect_confirm = $false
        expect_dispatch = $false
        expect_dispatch_status = "not_applicable"
        expect_command = "/memory"
        expect_response_contains = "COOPER Operator Console: Memory"
        marker = "handoff-memory-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "operator help"
        input = "/help"
        confirm = $false
        expect_status = "mapped"
        expect_ready = $false
        expect_confirm = $false
        expect_dispatch = $false
        expect_dispatch_status = "not_applicable"
        expect_command = "/help"
        expect_response_contains = "COOPER Operator Console Commands"
        marker = "handoff-help-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "operator dispatch"
        input = "/dispatch"
        confirm = $false
        expect_status = "mapped"
        expect_ready = $false
        expect_confirm = $false
        expect_dispatch = $false
        expect_dispatch_status = "not_applicable"
        expect_command = "/dispatch"
        expect_response_contains = "COOPER Operator Console: Dispatch"
        marker = "handoff-dispatch-console-$([guid]::NewGuid().ToString())"
    }
    [pscustomobject]@{
        name = "exact research command"
        input = "/research"
        confirm = $false
        expect_status = "mapped"
        expect_ready = $true
        expect_confirm = $true
        expect_dispatch = $false
        expect_command = "/research"
        use_marker_suffix = $false
        marker = "handoff-research-exact-$([guid]::NewGuid().ToString())"
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
    [pscustomobject]@{
        name = "fabric research alias"
        input = "run fabric research on this note"
        confirm = $true
        expect_status = "mapped"
        expect_ready = $true
        expect_confirm = $false
        expect_dispatch = $true
        expect_command = "/fabric research"
        marker = "handoff-fabric-research-$([guid]::NewGuid().ToString())"
    }
)

if ($SkipOperatorConsole) {
    $Cases = @($Cases | Where-Object { [string]$_.name -notlike "operator *" })
}

if ($SkipDispatch) {
    $Cases = @($Cases | Where-Object { -not [bool]$_.expect_dispatch })
}

if ($DashboardMode) {
    $Cases = @($Cases | Where-Object { [string]$_.name -in @("known recommendation", "ambiguous clarification", "unknown closed", "exact research command") })
}

foreach ($Case in $Cases) {
    $UseMarkerSuffix = $true
    if ($Case.PSObject.Properties.Name -contains "use_marker_suffix") {
        $UseMarkerSuffix = [bool]$Case.use_marker_suffix
    }

    if ($UseMarkerSuffix -and -not $DashboardMode) {
        $MarkerInput = "$($Case.input) [$($Case.marker)]"
        $Before = Find-QueueArtifactByMarker -Marker $Case.marker
        if ($Before) {
            throw "Test marker already existed in pending queue: $($Case.marker)"
        }
    }
    else {
        $MarkerInput = $Case.input
        $Before = $null
    }

    $Args = @(
        "-Text", $MarkerInput,
        "-AsJson"
    )
    if ($Case.confirm) {
        $Args += "-ConfirmDispatch"
    }

    $Raw = & pwsh -NoProfile -File $HandoffScript @Args
    $Result = ConvertFrom-PDAMixedJson -Text ([string]($Raw -join "`n")) -SourceName $HandoffScript

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

    if ($Case.PSObject.Properties.Name -contains "expect_dispatch_status" -and $Case.expect_dispatch_status) {
        if ($Result.dispatch_status -ne $Case.expect_dispatch_status) {
            $CasePassed = $false
            $Issues.Add("Expected dispatch_status '$($Case.expect_dispatch_status)' but got '$($Result.dispatch_status)'.")
        }
    }

    if ($Case.PSObject.Properties.Name -contains "expect_response_contains" -and $Case.expect_response_contains) {
        if ([string]$Result.response_text -notlike "*$($Case.expect_response_contains)*") {
            $CasePassed = $false
            $Issues.Add("Response text did not include expected operator console summary.")
        }
    }

    if ($DashboardMode) {
        # Dashboard smoke mode intentionally avoids queue marker round-trips.
    }
    elseif ($UseMarkerSuffix) {
        if ($Result.original_input -notlike "*$($Case.marker)*") {
            $CasePassed = $false
            $Issues.Add("Original input did not round-trip through the handoff output.")
        }
    }
    elseif ([string]$Result.original_input -ne [string]$Case.input) {
        $CasePassed = $false
        $Issues.Add("Exact input did not round-trip through the handoff output.")
    }

    if ($Result.interpreter_status -in @("ambiguous", "unknown") -and [bool]$Result.dispatch_ready) {
        $CasePassed = $false
        $Issues.Add("Ambiguous/unknown input should not be dispatch ready.")
    }

    if ($Result.PSObject.Properties.Name -contains "capability_route" -and $Result.interpreter_status -eq "mapped" -and -not [string]::IsNullOrWhiteSpace([string]$Result.recommended_command) -and [string]$Result.dispatch_status -ne "not_applicable") {
        if ($null -eq $Result.capability_route) {
            $CasePassed = $false
            $Issues.Add("Mapped handoff should include a capability route.")
        }
        elseif ([string]::IsNullOrWhiteSpace([string]$Result.capability_route.selected_tool)) {
            $CasePassed = $false
            $Issues.Add("Mapped handoff should include a selected tool.")
        }
    }

    if (-not $DashboardMode -and $Result.dispatch_status -eq "submitted") {
        $PendingMatch = Find-QueueArtifactByMarker -Marker $Case.marker
        if (-not $PendingMatch) {
            $CasePassed = $false
            $Issues.Add("Confirmed dispatch did not create a canonical queue artifact.")
        }
        else {
            $Queued = Get-Content $PendingMatch.FullName -Raw | ConvertFrom-Json
            if ($Queued.command -ne $Case.expect_command) {
                $CasePassed = $false
                $Issues.Add("Queued task command mismatch: $($Queued.command).")
            }

            if ($PendingMatch.FullName -match '\\approvals\\pending\\' -and $Case.expect_dispatch) {
                $CasePassed = $false
                $Issues.Add("Confirmed dispatch should not remain in approvals\\pending.")
            }
        }
    }
    elseif (-not $DashboardMode) {
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
