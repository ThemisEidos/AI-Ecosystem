[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ResultScript = Join-Path $PSScriptRoot "Get-PDATaskResult.ps1"
$BridgeScript = Join-Path $PSScriptRoot "Invoke-PDAChatBridge.ps1"
$PendingRoot = Join-Path $Root "PDA-Tasks\pending"

if (-not (Test-Path -Path $ResultScript -PathType Leaf)) {
    throw "Task result lookup script missing: $ResultScript"
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

function Invoke-JsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $Raw = & pwsh -NoProfile -File $Path @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Script failed: $Path"
    }

    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Script returned empty output: $Path"
    }

    return $Text | ConvertFrom-Json
}

$Results = @()
$Passed = 0
$Failed = 0

$CompletedTaskId = "ea5d19d8-4cc0-427f-9be0-8659b10ffe8a"
$CompletedResultPath = Join-Path $Root "PDA-Tasks\results\ea5d19d8-4cc0-427f-9be0-8659b10ffe8a-result.json"
$LiveConversationId = "conv-live-dispatch-001"
$LiveSessionId = "sess-live-dispatch-001"
$LiveTaskId = "e6deb443-580d-4d61-bf36-84f10125de9a"
$BridgeMarker = "task-result-bridge-$([guid]::NewGuid().ToString())"

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pda-task-result-tests\$(Get-Date -Format 'yyyyMMdd-HHmmssfff')"
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
$TempStatePath = Join-Path $TempRoot "conversation-state.json"

$TempState = [ordered]@{
    schema_version = "1.0"
    created_at     = (Get-Date).ToUniversalTime().ToString("o")
    updated_at     = (Get-Date).ToUniversalTime().ToString("o")
    conversations  = [ordered]@{
        "conv-task-result-test-001" = [ordered]@{
            conversation_id   = "conv-task-result-test-001"
            session_id        = "sess-task-result-test-001"
            latest_task_id    = $CompletedTaskId
            latest_task_status = "completed"
            updated_at        = (Get-Date).ToUniversalTime().ToString("o")
        }
    }
    tasks = [ordered]@{
        $CompletedTaskId = [ordered]@{
            task_id          = $CompletedTaskId
            conversation_id   = "conv-task-result-test-001"
            session_id        = "sess-task-result-test-001"
            command           = "/planner"
            intent            = "planning"
            task_status       = "completed"
            updated_at        = (Get-Date).ToUniversalTime().ToString("o")
            result_path       = $CompletedResultPath
        }
    }
    sessions = [ordered]@{
        "sess-task-result-test-001" = [ordered]@{
            conversation_id = "conv-task-result-test-001"
            session_id      = "sess-task-result-test-001"
            updated_at      = (Get-Date).ToUniversalTime().ToString("o")
        }
    }
}

$TempState | ConvertTo-Json -Depth 20 | Set-Content -Path $TempStatePath -Encoding UTF8

$Cases = @(
    [pscustomobject]@{
        name = "completed task artifact"
        path = $ResultScript
        args = @(
            "-StatePath", $TempStatePath,
            "-ConversationId", "conv-task-result-test-001",
            "-SessionId", "sess-task-result-test-001",
            "-TaskId", $CompletedTaskId,
            "-UserMessage", "show latest result",
            "-AsJson"
        )
        validate = {
            param($Result)
            $Issues = New-Object System.Collections.Generic.List[string]
            if ($Result.status -ne "pass") { $Issues.Add("lookup status should be pass.") }
            if ($Result.conversation_id -ne "conv-task-result-test-001") { $Issues.Add("conversation id mismatch.") }
            if ($Result.latest_task.task_id -ne $CompletedTaskId) { $Issues.Add("latest task id mismatch.") }
            if ($Result.latest_task.task_status -ne "completed") { $Issues.Add("latest task status mismatch.") }
            if ($Result.latest_result.result_path -ne $CompletedResultPath) { $Issues.Add("latest result path mismatch.") }
            if (-not $Result.result_artifact.output.content) { $Issues.Add("result artifact content missing.") }
            if ($Result.response_text -notlike "*available*") { $Issues.Add("response text should mention result availability.") }
            if ($Result.latest_result_response_text -notlike "*available*") { $Issues.Add("result response text should mention availability.") }
            return $Issues
        }
    }
    [pscustomobject]@{
        name = "live latest task"
        path = $ResultScript
        args = @(
            "-ConversationId", $LiveConversationId,
            "-SessionId", $LiveSessionId,
            "-UserMessage", "what happened with my task?",
            "-AsJson"
        )
        validate = {
            param($Result)
            $Issues = New-Object System.Collections.Generic.List[string]
            if ($Result.latest_task_id -ne $LiveTaskId -and [string]$Result.latest_task.task_id -ne $LiveTaskId) { $Issues.Add("live latest task id mismatch.") }
            if ($Result.latest_task_status -ne "queued" -and [string]$Result.latest_task.task_status -ne "queued") { $Issues.Add("live latest task status mismatch.") }
            if ($Result.response_text -notlike "*waiting in the queue*") { $Issues.Add("response text should mention queue wait.") }
            return $Issues
        }
    }
    [pscustomobject]@{
        name = "bridge status lookup"
        path = $BridgeScript
        args = @(
            "-Message", "what happened with my task? [$BridgeMarker]",
            "-ConversationId", $LiveConversationId,
            "-SessionId", $LiveSessionId,
            "-AsJson"
        )
        marker = $BridgeMarker
        validate = {
            param($Result)
            $Issues = New-Object System.Collections.Generic.List[string]
            if ($Result.handoff_status -ne "status_lookup") { $Issues.Add("bridge should remain in status lookup mode.") }
            if ($Result.dispatch_status -ne "not_dispatched") { $Issues.Add("bridge must not dispatch on status lookup.") }
            if ($Result.bridge_status -ne "ready") { $Issues.Add("bridge status should be ready.") }
            if ($Result.response_text -notlike "*waiting in the queue*") { $Issues.Add("bridge response text should mention queue wait.") }
            if ($Result.latest_task_id -ne $LiveTaskId) { $Issues.Add("bridge should surface the latest task id.") }
            return $Issues
        }
    }
)

foreach ($Case in $Cases) {
    $Before = $null
    if ($Case.marker) {
        $Before = Find-QueueArtifactByMarker -Marker $Case.marker
        if ($Before) {
            throw "Test marker already existed in pending queue: $($Case.marker)"
        }
    }

    $Result = Invoke-JsonScript -Path $Case.path -Arguments $Case.args
    $Issues = & $Case.validate $Result
    $CasePassed = ($Issues.Count -eq 0)

    if ($Case.marker) {
        $After = Find-QueueArtifactByMarker -Marker $Case.marker
        if ($After) {
            $CasePassed = $false
            $Issues.Add("status lookup unexpectedly created queue work.")
        }
    }

    $Results += [pscustomobject]@{
        name = $Case.name
        passed = $CasePassed
        response_text = $Result.response_text
        dispatch_status = $Result.dispatch_status
        latest_task_id = if ($Result.latest_task_id) { $Result.latest_task_id } else { if ($Result.latest_task) { $Result.latest_task.task_id } else { "" } }
        latest_task_status = if ($Result.latest_task_status) { $Result.latest_task_status } else { if ($Result.latest_task) { $Result.latest_task.task_status } else { "" } }
        latest_result_path = if ($Result.latest_result_path) { $Result.latest_result_path } else { if ($Result.latest_result) { $Result.latest_result.result_path } else { "" } }
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
    test_case_count = $Cases.Count
    passed_count = $Passed
    failed_count = $Failed
    results = @($Results)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA task result validation failed."
    }
    return
}

Write-Host "[*] PDA task result tests"
Write-Host ("Test cases : {0}" -f $Report.test_case_count)
Write-Host ("Passed     : {0}" -f $Report.passed_count)
Write-Host ("Failed     : {0}" -f $Report.failed_count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA task result validation failed."
}
