[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ReaderScript = Join-Path $PSScriptRoot "Get-COOPERRoadmapState.ps1"
$TempRoot = Join-Path $Root "tmp\cooper-roadmap-state-tests"
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$Issues = New-Object System.Collections.Generic.List[string]

function Add-Issue {
    param([Parameter(Mandatory = $true)][string]$Message)
    $Issues.Add($Message) | Out-Null
}

try {
    if (-not (Test-Path -LiteralPath $ReaderScript -PathType Leaf)) {
        throw "Roadmap state reader is missing: $ReaderScript"
    }

    $JsonText = @(& $ReaderScript -Root $Root -AsJson) -join [Environment]::NewLine
    $State = $JsonText | ConvertFrom-Json -ErrorAction Stop

    if ([string]$State.status -ne "pass") {
        Add-Issue "Roadmap state reader did not report pass."
    }
    if ([string]$State.current_phase -ne "Phase 8 - Open WebUI Workspace Knowledge Layer") {
        Add-Issue "Current phase did not resolve to Phase 8."
    }
    if ([string]$State.current_phase_status -ne "Current") {
        Add-Issue "Current phase status was not Current."
    }
    if ([string]$State.current_objective -notmatch '(?i)Open WebUI Workspace knowledge') {
        Add-Issue "Current objective did not describe the Open WebUI Workspace knowledge layer."
    }
    if ([string]$State.next_step -notmatch '(?i)Open WebUI Workspace knowledge') {
        Add-Issue "Next step did not describe the Open WebUI Workspace knowledge layer work."
    }
    if ($State.PSObject.Properties.Name -notcontains "completed_phases") {
        Add-Issue "Completed phases field is missing."
    }
    if ($State.PSObject.Properties.Name -notcontains "latest_exit_review") {
        Add-Issue "Latest exit review field is missing."
    }
    if ($State.PSObject.Properties.Name -notcontains "source_files") {
        Add-Issue "Source files field is missing."
    }
    if ($State.PSObject.Properties.Name -notcontains "generated_at_utc") {
        Add-Issue "Generated timestamp field is missing."
    }

    $CompletedPhases = @($State.completed_phases)
    if ($CompletedPhases.Count -eq 0) {
        Add-Issue "Completed phases list is empty."
    }
    else {
        $Phase7E = @($CompletedPhases | Where-Object { [string]$_.phase -eq "Phase 7E" } | Select-Object -First 1)
        if ($Phase7E.Count -eq 0 -or [string]$Phase7E[0].status -ne "Complete") {
            Add-Issue "Phase 7E was not marked complete."
        }
    }

    $LatestReview = $State.latest_exit_review
    if ($null -eq $LatestReview) {
        Add-Issue "Latest exit review was not resolved."
    }
    else {
        if ([string]$LatestReview.path -notmatch 'Docs[\\/]+Phase_7E_Exit_Review\.md$') {
            Add-Issue "Latest exit review did not resolve to Docs/Phase_7E_Exit_Review.md."
        }
        if ([string]$LatestReview.phase -ne "Phase 7E") {
            Add-Issue "Latest exit review phase was not Phase 7E."
        }
    }

    $SourceFiles = @($State.source_files)
    if ($SourceFiles.Count -lt 2) {
        Add-Issue "Source files did not include the roadmap and exit reviews."
    }

    $ExpectedPaths = @(
        (Join-Path $Root "07_Implementation Roadmap.md"),
        (Join-Path $Root "Docs\Phase_7B_Exit_Review.md"),
        (Join-Path $Root "Docs\Phase_7C_Exit_Review.md"),
        (Join-Path $Root "Docs\Phase_7D_Exit_Review.md")
    )
    foreach ($ExpectedPath in $ExpectedPaths) {
        if ($SourceFiles -notcontains [System.IO.Path]::GetFullPath($ExpectedPath)) {
            Add-Issue "Source files are missing $ExpectedPath."
        }
    }

    if ($State.deferred_items.Count -eq 0) {
        Add-Issue "Deferred items were not captured from the roadmap."
    }
    elseif (@($State.deferred_items | Where-Object { [string]$_ -match 'Hermes integration review' }).Count -eq 0) {
        Add-Issue "Deferred items did not include the backlog item list."
    }

    if ($State.blocked_items.Count -ne 0) {
        Add-Issue "Blocked items should be empty when none are explicitly listed."
    }

    $MissingRoadmapPath = Join-Path $TempRoot "missing-roadmap.md"
    $MissingResultText = @(& $ReaderScript -Root $Root -RoadmapPath $MissingRoadmapPath -AsJson) -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace([string]$MissingResultText)) {
        Add-Issue "Missing-roadmap invocation failed without returning a structured result."
    }
    else {
        try {
            $MissingResult = $MissingResultText | ConvertFrom-Json -ErrorAction Stop
            if ([string]$MissingResult.status -ne "fail") {
                Add-Issue "Missing-roadmap invocation did not fail safely."
            }
            if ([string]$MissingResult.error -notmatch 'Roadmap not found') {
                Add-Issue "Missing-roadmap invocation did not report the missing roadmap."
            }
        }
        catch {
            Add-Issue "Missing-roadmap invocation did not produce valid JSON."
        }
    }

    $Report = [pscustomobject]@{
        status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
        state = $State
        issues = @($Issues)
    }

    Write-Host "[*] COOPER roadmap state reader validation"
    Write-Host ("Status   : {0}" -f $Report.status)
    Write-Host ("Phase    : {0}" -f $State.current_phase)
    Write-Host ("Next     : {0}" -f $State.next_step)

    if ($Report.status -ne "pass") {
        foreach ($Issue in @($Report.issues)) {
            Write-Host ("[FAIL] {0}" -f $Issue)
        }
        exit 1
    }

    Write-Host "[PASS] Roadmap state reader validated."
    exit 0
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        try {
            Remove-Item -LiteralPath $TempRoot -Force -Recurse -ErrorAction SilentlyContinue
        }
        catch {}
    }
}
