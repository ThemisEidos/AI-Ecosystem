[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Get-PDANightlyRoadmapPath {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Join-Path $Root "Roadmap\PDA-Roadmap.json")
}

function Read-PDANightlyJsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $Raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return $null
    }

    return $Raw | ConvertFrom-Json -ErrorAction Stop
}

function Import-PDANightlyRoadmap {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [string]$RoadmapPath = (Get-PDANightlyRoadmapPath -Root $Root)
    )

    if (-not (Test-Path -LiteralPath $RoadmapPath -PathType Leaf)) {
        throw "Nightly roadmap not found: $RoadmapPath"
    }

    return (Get-Content -LiteralPath $RoadmapPath -Raw | ConvertFrom-Json -ErrorAction Stop)
}

function Get-PDANightlyTask {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Roadmap,

        [Parameter(Mandatory = $false)]
        [string]$TaskId = ""
    )

    $Tasks = @($Roadmap.tasks)
    if ([string]::IsNullOrWhiteSpace($TaskId)) {
        $TaskId = [string]$Roadmap.current_task_id
    }

    if ([string]::IsNullOrWhiteSpace($TaskId)) {
        return $null
    }

    return @($Tasks | Where-Object { [string]$_.id -eq $TaskId } | Select-Object -First 1)[0]
}

function Get-PDANightlyStateModel {
    param([Parameter(Mandatory = $true)][object]$Roadmap)

    if ($Roadmap.PSObject.Properties.Name -contains "task_state_model" -and $Roadmap.task_state_model) {
        return $Roadmap.task_state_model
    }

    return [pscustomobject]@{
        states = @(
            "backlog",
            "eligible",
            "prepared",
            "assigned",
            "in_progress",
            "testing",
            "ready_for_review",
            "completed",
            "blocked",
            "failed"
        )
        allowed_transitions = [pscustomobject]@{
            backlog         = @("eligible")
            eligible        = @("prepared")
            prepared        = @("assigned")
            assigned        = @("in_progress")
            in_progress     = @("testing")
            testing         = @("ready_for_review")
            ready_for_review = @("completed")
            completed       = @()
            blocked         = @()
            failed          = @()
        }
    }
}

function Get-PDANightlyAllowedTransitions {
    param([Parameter(Mandatory = $true)][object]$Roadmap)

    $Model = Get-PDANightlyStateModel -Roadmap $Roadmap
    $Transitions = $Model.allowed_transitions
    if (-not $Transitions) {
        return [pscustomobject]@{}
    }

    return $Transitions
}

function Get-PDANightlyExecutionTransitionChain {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CurrentState
    )

    switch ($CurrentState) {
        "backlog" { return @("eligible", "prepared", "assigned") }
        "eligible" { return @("prepared", "assigned") }
        "prepared" { return @("assigned") }
        "assigned" { return @() }
        default {
            throw "Execution mode cannot advance task state from '$CurrentState'."
        }
    }
}

function Get-PDANightlyTaskState {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Roadmap,

        [Parameter(Mandatory = $false)]
        [string]$TaskId = ""
    )

    $Task = Get-PDANightlyTask -Roadmap $Roadmap -TaskId $TaskId
    if (-not $Task) {
        return $null
    }

    $StateModel = Get-PDANightlyStateModel -Roadmap $Roadmap
    $CurrentState = [string]$Task.status
    $AllowedTransitions = Get-PDANightlyAllowedTransitions -Roadmap $Roadmap
    $NextStates = @()
    if ($AllowedTransitions.PSObject.Properties.Name -contains $CurrentState) {
        $NextStates = @($AllowedTransitions.$CurrentState)
    }

    $History = @()
    if ($Roadmap.PSObject.Properties.Name -contains "task_state_history" -and $Roadmap.task_state_history) {
        $History = @($Roadmap.task_state_history | Where-Object { [string]$_.task_id -eq [string]$Task.id })
    }

    return [pscustomobject]@{
        task_id             = [string]$Task.id
        title               = [string]$Task.title
        objective           = [string]$Task.objective
        status              = $CurrentState
        dependencies        = @($Task.dependencies)
        allowed_files       = @($Task.allowed_files)
        required_tests      = @($Task.required_tests)
        stop_conditions     = @($Task.stop_conditions)
        completion_criteria = @($Task.completion_criteria)
        next_states         = @($NextStates)
        current_task_id     = [string]$Roadmap.current_task_id
        completed_task_ids  = @($Roadmap.completed_task_ids)
        history             = @($History)
        state_model         = $StateModel
    }
}

function Test-PDANightlyStateTransition {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Roadmap,

        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [Parameter(Mandatory = $true)]
        [string]$FromState,

        [Parameter(Mandatory = $true)]
        [string]$ToState
    )

    $AllowedTransitions = Get-PDANightlyAllowedTransitions -Roadmap $Roadmap
    if (-not ($AllowedTransitions.PSObject.Properties.Name -contains $FromState)) {
        return [pscustomobject]@{
            valid   = $false
            reason  = "Unknown from-state: $FromState"
            allowed = @()
        }
    }

    $Allowed = @($AllowedTransitions.$FromState)
    if ($Allowed -notcontains $ToState) {
        return [pscustomobject]@{
            valid   = $false
            reason  = "Transition $FromState -> $ToState is not allowed."
            allowed = @($Allowed)
        }
    }

    return [pscustomobject]@{
        valid   = $true
        reason  = "Transition allowed."
        allowed = @($Allowed)
    }
}

function Set-PDANightlyRoadmapStatus {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [string]$RoadmapPath = (Get-PDANightlyRoadmapPath -Root $Root),

        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [Parameter(Mandatory = $true)]
        [string]$ToState,

        [Parameter(Mandatory = $false)]
        [string]$Actor = "PDA Nightly Automation",

        [Parameter(Mandatory = $false)]
        [string]$Reason = "",

        [Parameter(Mandatory = $false)]
        [switch]$NoWrite
    )

    $Roadmap = Import-PDANightlyRoadmap -Root $Root -RoadmapPath $RoadmapPath
    $Task = Get-PDANightlyTask -Roadmap $Roadmap -TaskId $TaskId
    if (-not $Task) {
        throw "Task not found in roadmap: $TaskId"
    }

    $FromState = [string]$Task.status
    if ([string]::IsNullOrWhiteSpace($FromState)) {
        $FromState = "backlog"
    }

    $Validation = Test-PDANightlyStateTransition -Roadmap $Roadmap -TaskId $TaskId -FromState $FromState -ToState $ToState
    if (-not $Validation.valid) {
        throw $Validation.reason
    }

    $UpdatedRoadmap = $Roadmap | ConvertTo-Json -Depth 40 | ConvertFrom-Json
    $UpdatedTask = @($UpdatedRoadmap.tasks | Where-Object { [string]$_.id -eq $TaskId } | Select-Object -First 1)[0]
    $UpdatedTask.status = $ToState
    $UpdatedRoadmap.last_updated = (Get-Date).ToUniversalTime().ToString("o")
    $UpdatedRoadmap.current_task_id = $TaskId

    if ($ToState -eq "completed") {
        $Completed = New-Object System.Collections.Generic.List[string]
        foreach ($ExistingId in @($UpdatedRoadmap.completed_task_ids)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$ExistingId)) {
                [void]$Completed.Add([string]$ExistingId)
            }
        }
        if ($Completed -notcontains $TaskId) {
            [void]$Completed.Add($TaskId)
        }
        $UpdatedRoadmap.completed_task_ids = @($Completed.ToArray())
    }

    $History = New-Object System.Collections.Generic.List[object]
    foreach ($Entry in @($UpdatedRoadmap.task_state_history)) {
        [void]$History.Add($Entry)
    }
    [void]$History.Add([pscustomobject]@{
        task_id    = $TaskId
        from_state  = $FromState
        to_state    = $ToState
        actor       = $Actor
        reason      = $Reason
        changed_at  = (Get-Date).ToUniversalTime().ToString("o")
    })
    $UpdatedRoadmap.task_state_history = @($History.ToArray())

    if (-not $NoWrite) {
        $UpdatedRoadmap | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $RoadmapPath -Encoding UTF8
    }

    return [pscustomobject]@{
        status        = "pass"
        roadmap_path  = $RoadmapPath
        task_id       = $TaskId
        from_state    = $FromState
        to_state      = $ToState
        transition    = $Validation
        updated       = (-not $NoWrite)
        roadmap       = $UpdatedRoadmap
    }
}

function Find-PDANightlyWorkPacket {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [Parameter(Mandatory = $false)]
        [string]$PacketRoot = (Join-Path $Root "Roadmap\work-packets")
    )

    if (-not (Test-Path -LiteralPath $PacketRoot -PathType Container)) {
        return $null
    }

    $PacketFile = @(
        Get-ChildItem -LiteralPath $PacketRoot -File -Filter "$TaskId-*.json" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
    )[0]

    if (-not $PacketFile) {
        return $null
    }

    $MarkdownPath = [System.IO.Path]::ChangeExtension($PacketFile.FullName, ".md")
    return [pscustomobject]@{
        json_path     = $PacketFile.FullName
        markdown_path = $MarkdownPath
        exists        = $true
        packet        = Read-PDANightlyJsonFile -Path $PacketFile.FullName
    }
}

function New-PDACodexWorkPacketObject {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [object]$Roadmap,

        [Parameter(Mandatory = $true)]
        [object]$Task,

        [Parameter(Mandatory = $false)]
        [string]$BranchName = ""
    )

    $TaskState = Get-PDANightlyTaskState -Roadmap $Roadmap -TaskId [string]$Task.id
    return [pscustomobject]@{
        schema_version      = "1.0"
        packet_type         = "pda_codex_work_packet"
        generated_at        = (Get-Date).ToUniversalTime().ToString("o")
        root_path           = $Root
        roadmap_path        = Get-PDANightlyRoadmapPath -Root $Root
        branch_name         = $BranchName
        task_id             = [string]$Task.id
        title               = [string]$Task.title
        objective           = [string]$Task.objective
        dependencies        = @($Task.dependencies)
        allowed_files       = @($Task.allowed_files)
        required_tests      = @($Task.required_tests)
        stop_conditions     = @($Task.stop_conditions)
        completion_criteria = @($Task.completion_criteria)
        current_state       = $TaskState.status
        next_states         = @($TaskState.next_states)
        roadmap_progress    = [pscustomobject]@{
            current_task_id    = [string]$Roadmap.current_task_id
            completed_task_ids = @($Roadmap.completed_task_ids)
            history_count      = @($Roadmap.task_state_history).Count
        }
        execution_notes     = @(
            "Human-governed only.",
            "No auto-commit.",
            "No auto-push.",
            "No unattended Codex execution."
        )
    }
}

function Save-PDACodexWorkPacket {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Packet,

        [Parameter(Mandatory = $true)]
        [string]$PacketRoot
    )

    New-Item -ItemType Directory -Force -Path $PacketRoot | Out-Null
    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $FileBase = "$($Packet.task_id)-$Timestamp"
    $JsonPath = Join-Path $PacketRoot "$FileBase.json"
    $MarkdownPath = Join-Path $PacketRoot "$FileBase.md"

    $Packet | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $JsonPath -Encoding UTF8

    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add("# PDA Codex Work Packet")
    $Lines.Add("")
    $Lines.Add(("Generated at: {0}" -f $Packet.generated_at))
    $Lines.Add(("Task ID: {0}" -f $Packet.task_id))
    $Lines.Add(("Title: {0}" -f $Packet.title))
    $Lines.Add(("Objective: {0}" -f $Packet.objective))
    $Lines.Add(("Branch: {0}" -f $Packet.branch_name))
    $Lines.Add("")
    $Lines.Add("## Completion Criteria")
    foreach ($Criterion in @($Packet.completion_criteria)) {
        $Lines.Add(("- {0}" -f $Criterion))
    }
    $Lines.Add("")
    $Lines.Add("## Required Tests")
    foreach ($Test in @($Packet.required_tests)) {
        $Lines.Add(("- {0}" -f $Test))
    }
    $Lines.Add("")
    $Lines.Add("## Stop Conditions")
    foreach ($Stop in @($Packet.stop_conditions)) {
        $Lines.Add(("- {0}" -f $Stop))
    }
    $Lines.Add("")
    $Lines.Add("## Allowed Files")
    foreach ($File in @($Packet.allowed_files)) {
        $Lines.Add(("- {0}" -f $File))
    }
    $Lines.Add("")
    $Lines.Add("## State")
    $Lines.Add(("Current state: {0}" -f $Packet.current_state))
    $Lines.Add(("Next states: {0}" -f (@($Packet.next_states) -join ", ")))
    $Lines.Add("")
    $Lines.Add("## Roadmap Progress")
    $Lines.Add(("Current task: {0}" -f $Packet.roadmap_progress.current_task_id))
    $Lines.Add(("Completed tasks: {0}" -f (@($Packet.roadmap_progress.completed_task_ids) -join ", ")))

    $Lines | Set-Content -LiteralPath $MarkdownPath -Encoding UTF8

    return [pscustomobject]@{
        status         = "pass"
        json_path      = $JsonPath
        markdown_path  = $MarkdownPath
        packet         = $Packet
    }
}

function New-PDANightlyExecutionSummaryObject {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Roadmap,

        [Parameter(Mandatory = $true)]
        [object]$Task,

        [Parameter(Mandatory = $true)]
        [object]$WorkPacket,

        [Parameter(Mandatory = $true)]
        [string]$BranchName,

        [Parameter(Mandatory = $true)]
        [string]$CurrentState,

        [Parameter(Mandatory = $true)]
        [string]$FinalState,

        [Parameter(Mandatory = $true)]
        [string[]]$TransitionChain,

        [Parameter(Mandatory = $false)]
        [string[]]$BackupManifests = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$TestsRequired = @()
    )

    return [pscustomobject]@{
        schema_version           = "1.0"
        artifact_type            = "pda_nightly_execution_summary"
        generated_at             = (Get-Date).ToUniversalTime().ToString("o")
        task_id                  = [string]$Task.id
        title                    = [string]$Task.title
        objective                = [string]$Task.objective
        branch_name              = $BranchName
        work_packet_json_path    = [string]$WorkPacket.json_path
        work_packet_markdown_path = [string]$WorkPacket.markdown_path
        state_before             = $CurrentState
        state_after              = $FinalState
        state_transition_chain   = @($TransitionChain)
        backups_created          = @($BackupManifests)
        tests_required           = @($TestsRequired)
        roadmap_progress         = [pscustomobject]@{
            current_task_id    = [string]$Roadmap.current_task_id
            completed_task_ids = @($Roadmap.completed_task_ids)
            history_count      = @($Roadmap.task_state_history).Count
        }
        status                   = "queued_for_human_review"
        review_required          = $true
        next_action              = "Human review required before Codex execution."
        execution_notes          = @(
            "Human-governed only.",
            "No auto-commit.",
            "No auto-push.",
            "No unattended Codex execution.",
            "No approval bypass.",
            "No queue deletion."
        )
    }
}

function Save-PDANightlyExecutionSummary {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Summary,

        [Parameter(Mandatory = $true)]
        [string]$OutputRoot
    )

    New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $SummaryDir = Join-Path $OutputRoot "$($Summary.task_id)-$Timestamp"
    New-Item -ItemType Directory -Force -Path $SummaryDir | Out-Null

    $JsonPath = Join-Path $SummaryDir "handoff-summary.json"
    $MarkdownPath = Join-Path $SummaryDir "handoff-summary.md"

    $Summary | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $JsonPath -Encoding UTF8

    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add("# PDA Nightly Handoff Summary")
    $Lines.Add("")
    $Lines.Add(("Generated at: {0}" -f $Summary.generated_at))
    $Lines.Add(("Task ID: {0}" -f $Summary.task_id))
    $Lines.Add(("Title: {0}" -f $Summary.title))
    $Lines.Add(("Objective: {0}" -f $Summary.objective))
    $Lines.Add(("Branch: {0}" -f $Summary.branch_name))
    $Lines.Add("")
    $Lines.Add("## State Transition")
    $Lines.Add(("Before: {0}" -f $Summary.state_before))
    $Lines.Add(("After: {0}" -f $Summary.state_after))
    $Lines.Add(("Chain: {0}" -f (@($Summary.state_transition_chain) -join " -> ")))
    $Lines.Add("")
    $Lines.Add("## Work Packet")
    $Lines.Add(("JSON: {0}" -f $Summary.work_packet_json_path))
    $Lines.Add(("Markdown: {0}" -f $Summary.work_packet_markdown_path))
    $Lines.Add("")
    $Lines.Add("## Backups Created")
    if (@($Summary.backups_created).Count -gt 0) {
        foreach ($Item in @($Summary.backups_created)) {
            $Lines.Add(("- {0}" -f $Item))
        }
    }
    else {
        $Lines.Add("- None recorded.")
    }
    $Lines.Add("")
    $Lines.Add("## Required Tests")
    if (@($Summary.tests_required).Count -gt 0) {
        foreach ($Item in @($Summary.tests_required)) {
            $Lines.Add(("- {0}" -f $Item))
        }
    }
    else {
        $Lines.Add("- None recorded.")
    }
    $Lines.Add("")
    $Lines.Add("## Review")
    $Lines.Add(("Status: {0}" -f $Summary.status))
    $Lines.Add(("Next action: {0}" -f $Summary.next_action))
    $Lines.Add("")
    $Lines.Add("## Execution Notes")
    foreach ($Note in @($Summary.execution_notes)) {
        $Lines.Add(("- {0}" -f $Note))
    }

    $Lines | Set-Content -LiteralPath $MarkdownPath -Encoding UTF8

    return [pscustomobject]@{
        status        = "pass"
        summary_root  = $SummaryDir
        json_path     = $JsonPath
        markdown_path = $MarkdownPath
        summary       = $Summary
    }
}

function New-PDAMorningReportMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $false)]
        [string]$BranchName = "",

        [Parameter(Mandatory = $false)]
        [string[]]$BackupManifests = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$TestsExecuted = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$GeneratedReports = @(),

        [Parameter(Mandatory = $false)]
        [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "PDA-Backups\nightly-build\reports")
    )

    New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $ReportPath = Join-Path $OutputRoot "morning-report-$Timestamp.md"

    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add("# PDA Morning Report")
    $Lines.Add("")
    $Lines.Add(("Generated at: {0}" -f (Get-Date).ToUniversalTime().ToString("o")))
    $Lines.Add("")
    $Lines.Add("## Nightly Summary")
    $Lines.Add(("Selected task: {0}" -f $State.task_id))
    $Lines.Add(("Branch name: {0}" -f $(if ([string]::IsNullOrWhiteSpace($BranchName)) { "(none)" } else { $BranchName })))
    $Lines.Add(("Current task status: {0}" -f $State.status))
    $Lines.Add(("Roadmap progress: {0}" -f ($State.roadmap_progress.current_task_id)))
    $Lines.Add("")
    $Lines.Add("### Backups Created")
    if (@($BackupManifests).Count -gt 0) {
        foreach ($Item in $BackupManifests) { $Lines.Add(("- {0}" -f $Item)) }
    }
    else {
        $Lines.Add("- None recorded.")
    }
    $Lines.Add("")
    $Lines.Add("### Tests Executed")
    if (@($TestsExecuted).Count -gt 0) {
        foreach ($Item in $TestsExecuted) { $Lines.Add(("- {0}" -f $Item)) }
    }
    else {
        $Lines.Add("- None recorded.")
    }
    $Lines.Add("")
    $Lines.Add("### Generated Reports")
    if (@($GeneratedReports).Count -gt 0) {
        foreach ($Item in $GeneratedReports) { $Lines.Add(("- {0}" -f $Item)) }
    }
    else {
        $Lines.Add("- None recorded.")
    }
    $Lines.Add("")
    $Lines.Add("### Roadmap Progress")
    $Lines.Add(("Completed tasks: {0}" -f (@($State.completed_task_ids) -join ", ")))
    $Lines.Add(("Allowed next states: {0}" -f (@($State.next_states) -join ", ")))

    $Lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

    return [pscustomobject]@{
        status      = "pass"
        report_path = $ReportPath
        markdown    = ($Lines -join "`n")
    }
}
