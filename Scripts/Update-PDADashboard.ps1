[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RootPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$ResolvedRoot = if ([string]::IsNullOrWhiteSpace($RootPath)) {
    Split-Path -Parent $PSScriptRoot
}
else {
    $RootPath
}

$ResolvedOutputDirectory = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    Join-Path $ResolvedRoot "Obsidian Vault\02_Projects\AI Tool Ecosystem"
}
else {
    $OutputDirectory
}

$DashboardPath = Join-Path $ResolvedOutputDirectory "PDA Dashboard.md"
$StatusScript = Join-Path $PSScriptRoot "Get-PDADashboardStatus.ps1"
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
if (Test-Path -LiteralPath $ParserPath -PathType Leaf) {
    . $ParserPath
}

function Get-PDAValueText {
    param([Parameter(Mandatory = $false)]$Value)

    if ($null -eq $Value) {
        return "-"
    }

    if ($Value -is [bool]) {
        return $(if ($Value) { "yes" } else { "no" })
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $Items = @($Value | ForEach-Object { Get-PDAValueText -Value $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne "-" })
        if ($Items.Count -eq 0) {
            return "-"
        }
        return ($Items -join ", ")
    }

    $Text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return "-"
    }

    return $Text.Replace("|", "\|")
}

function ConvertTo-PDAMarkdownTable {
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$Rows,

        [Parameter(Mandatory = $true)]
        [string[]]$Columns
    )

    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add("| " + ($Columns -join " | ") + " |")
    $Lines.Add("| " + (($Columns | ForEach-Object { "---" }) -join " | ") + " |")

    if ($null -eq $Rows -or @($Rows).Count -eq 0) {
        return ($Lines.ToArray() -join "`r`n")
    }

    foreach ($Row in $Rows) {
        $Values = foreach ($Column in $Columns) {
            Get-PDAValueText -Value $Row.$Column
        }

        $Lines.Add("| " + ($Values -join " | ") + " |")
    }

    return ($Lines.ToArray() -join "`r`n")
}

function Write-PDAMarkdownFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Lines
    )

    $Directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    ($Lines -join "`r`n") | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-PDAJsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$SourceName
    )

    $Raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "$SourceName returned empty output."
    }

    return ConvertFrom-PDAMixedJson -Text $Text -SourceName $SourceName
}

if (-not (Test-Path -LiteralPath $StatusScript -PathType Leaf)) {
    throw "Dashboard status script missing: $StatusScript"
}

$StatusReport = Invoke-PDAJsonScript -Path $StatusScript -Arguments @("-AsJson", "-NoThrow", "-RootPath", $ResolvedRoot) -SourceName "PDA dashboard status"

$GeneratedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
$Lines = New-Object System.Collections.Generic.List[string]
$Lines.Add("# PDA Dashboard v2")
$Lines.Add("")
$Lines.Add(("Updated: {0}" -f $GeneratedAt))
$Lines.Add(("Overall health: {0}" -f (Get-PDAValueText $StatusReport.dashboard_health.status)))
$Lines.Add("")

$Lines.Add("## System Health")
$Lines.Add("")
$Lines.Add((ConvertTo-PDAMarkdownTable -Rows @(
    [pscustomobject]@{ check = "PDA stack"; status = $StatusReport.system_health.status; passed = $StatusReport.system_health.passed_count; failed = $StatusReport.system_health.failed_count; details = "Open WebUI / n8n / LiteLLM / Ollama" }
    [pscustomobject]@{ check = "Deep validation"; status = $(if ($StatusReport.system_health.deep_validation_requested) { if ($StatusReport.system_health.failed_count -eq 0) { "pass" } else { "fail" } } else { "skipped" }); passed = ""; failed = ""; details = "Open WebUI chat completion" }
) -Columns @("check", "status", "passed", "failed", "details")))
$Lines.Add("")
if ($StatusReport.system_health.results) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.system_health.results) -Columns @("name", "passed", "type", "status_code")))
}
else {
    $Lines.Add("- No system health results available.")
}
$Lines.Add("")

$Lines.Add("## Queue Status")
$Lines.Add("")
$Lines.Add((ConvertTo-PDAMarkdownTable -Rows @(
    [pscustomobject]@{ metric = "Queue depth"; value = $StatusReport.queue_status.queue_depth }
    [pscustomobject]@{ metric = "Pending"; value = $StatusReport.queue_status.counts.pending }
    [pscustomobject]@{ metric = "Running"; value = $StatusReport.queue_status.counts.running }
    [pscustomobject]@{ metric = "Completed"; value = $StatusReport.queue_status.counts.completed }
    [pscustomobject]@{ metric = "Failed"; value = $StatusReport.queue_status.counts.failed }
    [pscustomobject]@{ metric = "Results"; value = $StatusReport.queue_status.counts.results }
    [pscustomobject]@{ metric = "Pending approvals"; value = $StatusReport.queue_status.counts.approvals_pending }
) -Columns @("metric", "value")))
$Lines.Add("")
$Lines.Add("### Latest Queue Files")
$Lines.Add("")
$LatestQueueRows = @(
    [pscustomobject]@{ queue = "pending"; task_id = $StatusReport.queue_status.latest.pending.task_id; command = $StatusReport.queue_status.latest.pending.command; status = $StatusReport.queue_status.latest.pending.status; updated_at = $StatusReport.queue_status.latest.pending.updated_at }
    [pscustomobject]@{ queue = "running"; task_id = $StatusReport.queue_status.latest.running.task_id; command = $StatusReport.queue_status.latest.running.command; status = $StatusReport.queue_status.latest.running.status; updated_at = $StatusReport.queue_status.latest.running.updated_at }
    [pscustomobject]@{ queue = "completed"; task_id = $StatusReport.queue_status.latest.completed.task_id; command = $StatusReport.queue_status.latest.completed.command; status = $StatusReport.queue_status.latest.completed.status; updated_at = $StatusReport.queue_status.latest.completed.updated_at }
    [pscustomobject]@{ queue = "failed"; task_id = $StatusReport.queue_status.latest.failed.task_id; command = $StatusReport.queue_status.latest.failed.command; status = $StatusReport.queue_status.latest.failed.status; updated_at = $StatusReport.queue_status.latest.failed.updated_at }
    [pscustomobject]@{ queue = "results"; task_id = $StatusReport.queue_status.latest.result.task_id; command = $StatusReport.queue_status.latest.result.command; status = $StatusReport.queue_status.latest.result.status; updated_at = $StatusReport.queue_status.latest.result.updated_at }
) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.task_id) -or -not [string]::IsNullOrWhiteSpace([string]$_.command) }
if ($LatestQueueRows.Count -gt 0) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows $LatestQueueRows -Columns @("queue", "task_id", "command", "status", "updated_at")))
}
else {
    $Lines.Add("- No queue files found.")
}
$Lines.Add("")

$Lines.Add("## Worker Status")
$Lines.Add("")
$Lines.Add((ConvertTo-PDAMarkdownTable -Rows $StatusReport.worker_status.registry.workers -Columns @("worker_name", "command", "status", "routing_surface", "cloud_capable", "accepted_input_modes")))
$Lines.Add("")
$Lines.Add("### Runtime States")
$Lines.Add("")
if ($StatusReport.worker_status.runtime_states) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.worker_status.runtime_states) -Columns @("component", "status", "pid", "started_at")))
}
else {
    $Lines.Add("- No worker runtime state files found.")
}
$Lines.Add("")
$Lines.Add("### Heartbeats")
$Lines.Add("")
if ($StatusReport.worker_status.heartbeats) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.worker_status.heartbeats) -Columns @("worker_name", "status", "state", "age_minutes", "process_live")))
}
else {
    $Lines.Add("- No worker heartbeat files found.")
}
$Lines.Add("")

$Lines.Add("## Pending Approvals")
$Lines.Add("")
if ($StatusReport.pending_approvals -and @($StatusReport.pending_approvals).Count -gt 0) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.pending_approvals) -Columns @("task_id", "command", "worker", "category", "approval_status", "updated_at", "file_name")))
}
else {
    $Lines.Add("- No pending approvals.")
}
$Lines.Add("")

$Lines.Add("## Recent Tasks")
$Lines.Add("")
if ($StatusReport.recent_tasks -and @($StatusReport.recent_tasks).Count -gt 0) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.recent_tasks) -Columns @("task_id", "command", "worker", "category", "queue", "status", "updated_at")))
}
else {
    $Lines.Add("- No recent tasks.")
}
$Lines.Add("")

$Lines.Add("## Recent Reports / Artifacts")
$Lines.Add("")
if ($StatusReport.recent_artifacts -and @($StatusReport.recent_artifacts).Count -gt 0) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.recent_artifacts) -Columns @("artifact_id", "created_at", "worker_name", "category", "artifact_type", "summary")))
}
else {
    $Lines.Add("- No artifact records.")
}
$Lines.Add("")

$Lines.Add("## Model Status")
$Lines.Add("")
$Lines.Add((ConvertTo-PDAMarkdownTable -Rows @(
    [pscustomobject]@{ metric = "Routing policy"; status = $StatusReport.model_status.routing_policy.status; path = $StatusReport.model_status.routing_policy.path }
    [pscustomobject]@{ metric = "Provider validation"; status = $StatusReport.model_status.provider_validation.status; count = $StatusReport.model_status.provider_validation.provider_count; passed = $StatusReport.model_status.provider_validation.passed_count; failed = $StatusReport.model_status.provider_validation.failed_count }
    [pscustomobject]@{ metric = "Env validation"; status = $StatusReport.model_status.env_validation.status; loaded = $StatusReport.model_status.env_validation.loaded_key_count; blank = $StatusReport.model_status.env_validation.blank_key_count; missing = $StatusReport.model_status.env_validation.missing_key_count }
) -Columns @("metric", "status", "path", "count", "passed", "failed", "loaded", "blank", "missing")))
$Lines.Add("")
$Lines.Add("### Command Routes")
$Lines.Add("")
if ($StatusReport.model_status.routing_policy.command_routes -and @($StatusReport.model_status.routing_policy.command_routes).Count -gt 0) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.model_status.routing_policy.command_routes) -Columns @("command", "primary_model", "fallback_chain", "routing_surface", "cloud_allowed")))
}
else {
    $Lines.Add("- No command routes found.")
}
$Lines.Add("")
$Lines.Add("### Provider Availability")
$Lines.Add("")
if ($StatusReport.model_status.provider_validation.providers -and @($StatusReport.model_status.provider_validation.providers).Count -gt 0) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.model_status.provider_validation.providers) -Columns @("name", "configured", "env_reference_ok", "host_env_present", "live_available", "api_provider")))
}
  else {
      $Lines.Add("- No provider rows found.")
  }
  $Lines.Add("")

$Lines.Add("## Capability Router")
$Lines.Add("")
$Lines.Add((ConvertTo-PDAMarkdownTable -Rows @(
    [pscustomobject]@{ metric = "Status"; value = $StatusReport.capability_router.status }
    [pscustomobject]@{ metric = "Matrix path"; value = $StatusReport.capability_router.matrix_path }
    [pscustomobject]@{ metric = "Route count"; value = $StatusReport.capability_router.route_count }
    [pscustomobject]@{ metric = "Local-only routes"; value = $StatusReport.capability_router.local_only_count }
    [pscustomobject]@{ metric = "Cloud-allowed routes"; value = $StatusReport.capability_router.cloud_allowed_count }
) -Columns @("metric", "value")))
$Lines.Add("")

$Lines.Add("## Environment Awareness")
$Lines.Add("")
if ($StatusReport.environment_awareness) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @(
        [pscustomobject]@{ metric = "Environment status"; value = $StatusReport.environment_awareness.status }
        [pscustomobject]@{ metric = "Repository count"; value = $StatusReport.environment_awareness.counts.repositories }
        [pscustomobject]@{ metric = "Container count"; value = $StatusReport.environment_awareness.counts.containers }
        [pscustomobject]@{ metric = "Running containers"; value = $StatusReport.environment_awareness.counts.running_containers }
        [pscustomobject]@{ metric = "Online services"; value = $StatusReport.environment_awareness.counts.services_online }
        [pscustomobject]@{ metric = "Available tools"; value = $StatusReport.environment_awareness.counts.tools_available }
    ) -Columns @("metric", "value")))
    $Lines.Add("")

    $Lines.Add("### Repositories")
    $Lines.Add("")
    if ($StatusReport.environment_awareness.repositories.repositories -and @($StatusReport.environment_awareness.repositories.repositories).Count -gt 0) {
        $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.environment_awareness.repositories.repositories) -Columns @("path", "branch", "clean", "dirty", "project_state")))
    }
    else {
        $Lines.Add("- No repositories found.")
    }
    $Lines.Add("")

    $Lines.Add("### Containers")
    $Lines.Add("")
    if ($StatusReport.environment_awareness.containers.containers -and @($StatusReport.environment_awareness.containers.containers).Count -gt 0) {
        $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.environment_awareness.containers.containers) -Columns @("name", "image", "running", "status", "ports", "compose_project")))
    }
    else {
        $Lines.Add("- No containers found.")
    }
    $Lines.Add("")

    $Lines.Add("### Services")
    $Lines.Add("")
    if ($StatusReport.environment_awareness.services.services -and @($StatusReport.environment_awareness.services.services).Count -gt 0) {
        $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.environment_awareness.services.services) -Columns @("name", "status", "source", "endpoint", "container")))
    }
    else {
        $Lines.Add("- No services found.")
    }
    $Lines.Add("")

    $Lines.Add("### Workspaces")
    $Lines.Add("")
    if ($StatusReport.environment_awareness.workspace_summary.roots -and @($StatusReport.environment_awareness.workspace_summary.roots).Count -gt 0) {
        $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.environment_awareness.workspace_summary.roots) -Columns @("root", "project_count", "archive_count", "file_count", "folder_count", "size_mb")))
    }
    else {
        $Lines.Add("- No workspace rows found.")
    }
    $Lines.Add("")

    $Lines.Add("### Storage")
    $Lines.Add("")
    if ($StatusReport.environment_awareness.storage_summary.roots -and @($StatusReport.environment_awareness.storage_summary.roots).Count -gt 0) {
        $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.environment_awareness.storage_summary.roots) -Columns @("root", "name", "classification", "file_count", "folder_count", "size_mb")))
    }
    else {
        $Lines.Add("- No storage summary available.")
    }
    $Lines.Add("")
}

$Lines.Add("### Fabric CLI Status")
$Lines.Add("")
$Lines.Add((ConvertTo-PDAMarkdownTable -Rows @(
    [pscustomobject]@{ metric = "Status"; value = $StatusReport.fabric_status.status }
    [pscustomobject]@{ metric = "Message"; value = $StatusReport.fabric_status.message }
    [pscustomobject]@{ metric = "Executable path"; value = $StatusReport.fabric_status.executable_path }
    [pscustomobject]@{ metric = "Version"; value = $StatusReport.fabric_status.version }
    [pscustomobject]@{ metric = "Pattern count"; value = $StatusReport.fabric_status.pattern_count }
    [pscustomobject]@{ metric = "Pattern listing"; value = $StatusReport.fabric_status.pattern_list_status }
) -Columns @("metric", "value")))
$Lines.Add("")

$Lines.Add("## PDA Commander Integration")
$Lines.Add("")
$Lines.Add((ConvertTo-PDAMarkdownTable -Rows @(
    [pscustomobject]@{ component = "Command Interpreter"; status = $StatusReport.commander_integration.command_interpreter.status; passed = $StatusReport.commander_integration.command_interpreter.passed_count; failed = $StatusReport.commander_integration.command_interpreter.failed_count; details = "mapped / ambiguous / unknown routing" }
    [pscustomobject]@{ component = "Governed Handoff"; status = $StatusReport.commander_integration.command_handoff.status; passed = $StatusReport.commander_integration.command_handoff.passed_count; failed = $StatusReport.commander_integration.command_handoff.failed_count; details = "confirmation gate" }
    [pscustomobject]@{ component = "Chat Bridge"; status = $StatusReport.commander_integration.chat_bridge.status; passed = $StatusReport.commander_integration.chat_bridge.passed_count; failed = $StatusReport.commander_integration.chat_bridge.failed_count; details = "Open WebUI / n8n bridge" }
    [pscustomobject]@{ component = "Webhook Bridge"; status = $StatusReport.commander_integration.webhook_bridge.status; passed = $StatusReport.commander_integration.webhook_bridge.passed_count; failed = $StatusReport.commander_integration.webhook_bridge.failed_count; details = "webhook transport wrapper" }
) -Columns @("component", "status", "passed", "failed", "details")))
$Lines.Add("")
$Lines.Add("### Conversation Snapshot")
$Lines.Add("")
$Lines.Add((ConvertTo-PDAMarkdownTable -Rows @(
    [pscustomobject]@{ metric = "Conversation status"; value = $StatusReport.commander_integration.conversation_state.status }
    [pscustomobject]@{ metric = "Conversation ID"; value = $StatusReport.commander_integration.conversation_state.conversation_id }
    [pscustomobject]@{ metric = "Active tasks"; value = $StatusReport.commander_integration.conversation_state.active_task_count }
    [pscustomobject]@{ metric = "Pending approvals"; value = $StatusReport.commander_integration.conversation_state.pending_approval_count }
    [pscustomobject]@{ metric = "Submitted tasks"; value = $StatusReport.commander_integration.conversation_state.submitted_task_count }
    [pscustomobject]@{ metric = "Completed tasks"; value = $StatusReport.commander_integration.conversation_state.completed_task_count }
    [pscustomobject]@{ metric = "Latest task ID"; value = $StatusReport.commander_integration.conversation_state.latest_task_id }
    [pscustomobject]@{ metric = "Latest result path"; value = $StatusReport.commander_integration.conversation_state.latest_result_path }
) -Columns @("metric", "value")))
$Lines.Add("")
if (-not [string]::IsNullOrWhiteSpace([string]$StatusReport.commander_integration.task_result.response_text)) {
    $Lines.Add(("> {0}" -f (Get-PDAValueText $StatusReport.commander_integration.task_result.response_text)))
    $Lines.Add("")
}
if (-not [string]::IsNullOrWhiteSpace([string]$StatusReport.commander_integration.task_result.next_action)) {
    $Lines.Add(("> Next: {0}" -f (Get-PDAValueText $StatusReport.commander_integration.task_result.next_action)))
    $Lines.Add("")
}

$Lines.Add("## PDA Commander Briefing")
$Lines.Add("")
if ($StatusReport.commander_briefing) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @(
        [pscustomobject]@{ metric = "Briefing status"; value = $StatusReport.commander_briefing.status }
        [pscustomobject]@{ metric = "Focus"; value = $StatusReport.commander_briefing.focus }
        [pscustomobject]@{ metric = "Dashboard health"; value = $StatusReport.commander_briefing.dashboard_health }
        [pscustomobject]@{ metric = "Queue depth"; value = $StatusReport.commander_briefing.queue.depth }
        [pscustomobject]@{ metric = "Pending approvals"; value = $StatusReport.commander_briefing.queue.pending }
        [pscustomobject]@{ metric = "Failed tasks"; value = $StatusReport.commander_briefing.queue.failed }
        [pscustomobject]@{ metric = "Memory candidates"; value = $StatusReport.commander_briefing.memory.candidate_count }
        [pscustomobject]@{ metric = "Memory approvals"; value = $StatusReport.commander_briefing.memory.candidates_pending_approval }
        [pscustomobject]@{ metric = "Recommended action"; value = $StatusReport.commander_briefing.next_action }
        [pscustomobject]@{ metric = "Recommended executor"; value = $StatusReport.commander_briefing.recommended_executor }
    ) -Columns @("metric", "value")))
    $Lines.Add("")
    $Lines.Add("### Commander Actions")
    $Lines.Add("")
    if ($StatusReport.commander_briefing.recommended_actions -and @($StatusReport.commander_briefing.recommended_actions).Count -gt 0) {
        $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.commander_briefing.recommended_actions) -Columns @("action", "executor", "reason")))
    }
    else {
        $Lines.Add("- No commander actions available.")
    }
    $Lines.Add("")
}

$Lines.Add("## Commander Planning")
$Lines.Add("")
if ($StatusReport.commander_planning) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @(
        [pscustomobject]@{ metric = "Planning status"; value = $StatusReport.commander_planning.status }
        [pscustomobject]@{ metric = "Plan count"; value = $StatusReport.commander_planning.plan_count }
        [pscustomobject]@{ metric = "Pending plans"; value = $StatusReport.commander_planning.pending_plan_count }
        [pscustomobject]@{ metric = "Latest goal"; value = $StatusReport.commander_planning.latest_goal.goal }
        [pscustomobject]@{ metric = "Latest goal type"; value = $StatusReport.commander_planning.latest_goal.goal_type }
        [pscustomobject]@{ metric = "Latest category"; value = $StatusReport.commander_planning.latest_goal.category }
        [pscustomobject]@{ metric = "Latest complexity"; value = $StatusReport.commander_planning.latest_goal.complexity }
    ) -Columns @("metric", "value")) )
    $Lines.Add("")
    $Lines.Add("### Recent Goals")
    $Lines.Add("")
    if ($StatusReport.commander_planning.recent_goals -and @($StatusReport.commander_planning.recent_goals).Count -gt 0) {
        $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.commander_planning.recent_goals) -Columns @("plan_id", "goal", "goal_type", "category", "complexity", "approval_required", "status", "created_at")))
    }
    else {
        $Lines.Add("- No goal plans found.")
    }
    $Lines.Add("")
    $Lines.Add("### Pending Plans")
    $Lines.Add("")
    if ($StatusReport.commander_planning.pending_plans -and @($StatusReport.commander_planning.pending_plans).Count -gt 0) {
        $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.commander_planning.pending_plans) -Columns @("plan_id", "goal", "goal_type", "category", "complexity", "status", "created_at")))
    }
    else {
        $Lines.Add("- No pending goal plans.")
    }
    $Lines.Add("")
    $Lines.Add("### Executor Chains")
    $Lines.Add("")
    if ($StatusReport.commander_planning.recommended_executor_chains -and @($StatusReport.commander_planning.recommended_executor_chains).Count -gt 0) {
        $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.commander_planning.recommended_executor_chains) -Columns @("plan_id", "goal", "recommended_executors")))
    }
    else {
        $Lines.Add("- No executor chains found.")
    }
    $Lines.Add("")
    $Lines.Add("### Planned Deliverables")
    $Lines.Add("")
    if ($StatusReport.commander_planning.planned_deliverables -and @($StatusReport.commander_planning.planned_deliverables).Count -gt 0) {
        $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.commander_planning.planned_deliverables) -Columns @("plan_id", "goal", "deliverables")))
    }
    else {
        $Lines.Add("- No planned deliverables found.")
    }
    $Lines.Add("")
}

$Lines.Add("## Commander Plan Orchestration")
$Lines.Add("")
if ($StatusReport.commander_plan_orchestration) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @(
        [pscustomobject]@{ metric = "Orchestration status"; value = $StatusReport.commander_plan_orchestration.status }
        [pscustomobject]@{ metric = "Total plans"; value = $StatusReport.commander_plan_orchestration.counts.total }
        [pscustomobject]@{ metric = "Running"; value = $StatusReport.commander_plan_orchestration.counts.running }
        [pscustomobject]@{ metric = "Blocked"; value = $StatusReport.commander_plan_orchestration.counts.blocked }
        [pscustomobject]@{ metric = "Waiting approval"; value = $StatusReport.commander_plan_orchestration.counts.waiting_approval }
        [pscustomobject]@{ metric = "Completed"; value = $StatusReport.commander_plan_orchestration.counts.completed }
    ) -Columns @("metric", "value")))
    $Lines.Add("")
    $Lines.Add("### Running Plans")
    $Lines.Add("")
    if ($StatusReport.commander_plan_orchestration.running_plans -and @($StatusReport.commander_plan_orchestration.running_plans).Count -gt 0) {
        $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.commander_plan_orchestration.running_plans) -Columns @("plan_id", "goal", "plan_folder", "status", "current_step", "overall_progress", "next_step", "updated_at")))
    }
    else {
        $Lines.Add("- No running plans.")
    }
    $Lines.Add("")
    $Lines.Add("### Blocked Plans")
    $Lines.Add("")
    if ($StatusReport.commander_plan_orchestration.blocked_plans -and @($StatusReport.commander_plan_orchestration.blocked_plans).Count -gt 0) {
        $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.commander_plan_orchestration.blocked_plans) -Columns @("plan_id", "goal", "plan_folder", "status", "blocked_reason", "updated_at")))
    }
    else {
        $Lines.Add("- No blocked plans.")
    }
    $Lines.Add("")
    $Lines.Add("### Waiting Approval")
    $Lines.Add("")
    if ($StatusReport.commander_plan_orchestration.pending_approvals -and @($StatusReport.commander_plan_orchestration.pending_approvals).Count -gt 0) {
        $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.commander_plan_orchestration.pending_approvals) -Columns @("plan_id", "goal", "plan_folder", "status", "current_step", "updated_at")))
    }
    else {
        $Lines.Add("- No plans waiting for approval.")
    }
    $Lines.Add("")
    $Lines.Add("### Recent Deliverables")
    $Lines.Add("")
    if ($StatusReport.commander_plan_orchestration.recent_deliverables -and @($StatusReport.commander_plan_orchestration.recent_deliverables).Count -gt 0) {
        $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.commander_plan_orchestration.recent_deliverables) -Columns @("plan_id", "goal", "final_deliverable_package_path", "updated_at")))
    }
    else {
        $Lines.Add("- No recent deliverables.")
    }
    $Lines.Add("")
}

$Lines.Add("## Dispatch Queue")
$Lines.Add("")
$Lines.Add((ConvertTo-PDAMarkdownTable -Rows @(
    [pscustomobject]@{ metric = "Status"; value = $StatusReport.dispatch_status.status }
    [pscustomobject]@{ metric = "Executor count"; value = $StatusReport.dispatch_status.registry.executor_count }
    [pscustomobject]@{ metric = "Pending approvals"; value = $StatusReport.dispatch_status.counts.pending_approval }
    [pscustomobject]@{ metric = "Approved"; value = $StatusReport.dispatch_status.counts.approved }
    [pscustomobject]@{ metric = "Prepared"; value = $StatusReport.dispatch_status.counts.prepared }
    [pscustomobject]@{ metric = "Running"; value = $StatusReport.dispatch_status.counts.running }
    [pscustomobject]@{ metric = "Completed"; value = $StatusReport.dispatch_status.counts.completed }
    [pscustomobject]@{ metric = "Failed"; value = $StatusReport.dispatch_status.counts.failed }
    ) -Columns @("metric", "value")))
$Lines.Add("")

$Lines.Add("### Executor Registry")
$Lines.Add("")
if ($StatusReport.dispatch_status.registry.executors -and @($StatusReport.dispatch_status.registry.executors).Count -gt 0) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.dispatch_status.registry.executors) -Columns @("executor_name", "display_name", "executor_type", "risk_level", "requires_approval", "supports_category2", "supports_local_only", "dispatch_method")))
}
else {
    $Lines.Add("- No executor registry entries found.")
}
$Lines.Add("")

$Lines.Add("### Recent Dispatches")
$Lines.Add("")
if ($StatusReport.dispatch_status.recent_items -and @($StatusReport.dispatch_status.recent_items).Count -gt 0) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.dispatch_status.recent_items) -Columns @("task_id", "command", "executor_name", "dispatch_state", "approval_status", "updated_at", "file_name")))
}
else {
    $Lines.Add("- No recent dispatch items found.")
}
$Lines.Add("")

$Lines.Add("## Memory Summary")
$Lines.Add("")
$Lines.Add((ConvertTo-PDAMarkdownTable -Rows @(
    [pscustomobject]@{ metric = "Memory count"; value = $StatusReport.memory_summary.count }
    [pscustomobject]@{ metric = "Updated at"; value = $StatusReport.memory_summary.updated_at }
    [pscustomobject]@{ metric = "By type"; value = ($StatusReport.memory_summary.by_type | ForEach-Object { "$($_.name): $($_.count)" }) }
    [pscustomobject]@{ metric = "By category"; value = ($StatusReport.memory_summary.by_category | ForEach-Object { "$($_.name): $($_.count)" }) }
) -Columns @("metric", "value")))
$Lines.Add("")
$Lines.Add("### Memory Types")
$Lines.Add("")
if ($StatusReport.memory_summary.by_type -and @($StatusReport.memory_summary.by_type).Count -gt 0) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.memory_summary.by_type) -Columns @("name", "count")))
}
else {
    $Lines.Add("- No memory type data.")
}
$Lines.Add("")
$Lines.Add("### Memory Categories")
$Lines.Add("")
if ($StatusReport.memory_summary.by_category -and @($StatusReport.memory_summary.by_category).Count -gt 0) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.memory_summary.by_category) -Columns @("name", "count")))
}
else {
    $Lines.Add("- No memory category data.")
}
$Lines.Add("")
$Lines.Add("### Recent Memories")
$Lines.Add("")
if ($StatusReport.memory_summary.recent -and @($StatusReport.memory_summary.recent).Count -gt 0) {
    $Lines.Add((ConvertTo-PDAMarkdownTable -Rows @($StatusReport.memory_summary.recent) -Columns @("memory_id", "created_at", "memory_type", "category", "title", "summary")))
}
else {
    $Lines.Add("- No memory records.")
}

Write-PDAMarkdownFile -Path $DashboardPath -Lines $Lines

$Report = [pscustomobject]@{
    status = "pass"
    dashboard_path = $DashboardPath
    generated_at = $StatusReport.generated_at
    root_path = $ResolvedRoot
    output_directory = $ResolvedOutputDirectory
    dashboard_health = $StatusReport.dashboard_health
    source = $StatusReport
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 30
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA dashboard refresh failed."
    }
    return
}

if ($Report.status -eq "pass") {
    Write-Host "[OK] PDA dashboard updated:"
    Write-Host $Report.dashboard_path
}
else {
    Write-Host "[FAIL] PDA dashboard update failed:"
    foreach ($Issue in @($Report.issues)) {
        Write-Host ("  {0}" -f $Issue)
    }
}

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA dashboard refresh failed."
}
