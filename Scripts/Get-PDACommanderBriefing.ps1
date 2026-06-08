param(
    [Parameter(Mandatory = $false)]
    [object]$DashboardStatus,

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$Focus = "default",

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$DashboardStatusScript = Join-Path $PSScriptRoot "Get-PDADashboardStatus.ps1"
$RecommendationScript = Join-Path $PSScriptRoot "Get-PDACommanderRecommendation.ps1"
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
if (Test-Path -LiteralPath $ParserPath -PathType Leaf) {
    . $ParserPath
}

function ConvertTo-PDACommanderInt {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Value,

        [Parameter(Mandatory = $false)]
        [int]$Default = 0
    )

    if ($null -eq $Value) {
        return $Default
    }

    if ($Value -is [int]) {
        return $Value
    }

    if ($Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        try {
            return [int]$Value
        }
        catch {
            return $Default
        }
    }

    $Text = [string]$Value
    $Parsed = 0
    if ([int]::TryParse($Text, [ref]$Parsed)) {
        return $Parsed
    }

    $ParsedLong = 0L
    if ([long]::TryParse($Text, [ref]$ParsedLong)) {
        try {
            return [int]$ParsedLong
        }
        catch {
            return $Default
        }
    }

    return $Default
}

function ConvertTo-PDACommanderString {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Value,

        [Parameter(Mandatory = $false)]
        [string]$Default = ""
    )

    if ($null -eq $Value) {
        return $Default
    }

    if ($Value -is [string]) {
        return $Value
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $First = @($Value | Select-Object -First 1)
        if ($First.Count -gt 0 -and $null -ne $First[0]) {
            try {
                return [System.Convert]::ToString($First[0], [System.Globalization.CultureInfo]::InvariantCulture)
            }
            catch {
                return $Default
            }
        }
        return $Default
    }

    try {
        return [System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return $Default
    }
}

if ($null -eq $DashboardStatus) {
    if (-not (Test-Path -LiteralPath $DashboardStatusScript -PathType Leaf)) {
        throw "Dashboard status script missing: $DashboardStatusScript"
    }

    $DashboardRaw = & pwsh -NoProfile -File $DashboardStatusScript -RootPath $Root -AsJson -NoThrow -SkipCommanderBriefing
    $DashboardStatus = ConvertFrom-PDAMixedJson -Text ([string]($DashboardRaw -join "`n")) -SourceName $DashboardStatusScript
}

$Queue = $DashboardStatus.queue_status
$Memory = $DashboardStatus.memory_summary
$RecentTasks = @($Queue.recent_tasks | Where-Object { [string]$_.status -in @("completed", "success") } | Select-Object -First 3)
$RecentMemories = @($Memory.recent | Select-Object -First 3)
$PendingApprovals = ConvertTo-PDACommanderInt -Value $Queue.counts.approvals_pending
$FailedCount = ConvertTo-PDACommanderInt -Value $Queue.counts.failed
$QueueDepth = ConvertTo-PDACommanderInt -Value $Queue.queue_depth
$CandidatePending = ConvertTo-PDACommanderInt -Value $Memory.pending_approval_count
$PromotedCount = ConvertTo-PDACommanderInt -Value $Memory.promoted_count
$QueuePending = ConvertTo-PDACommanderInt -Value $Queue.counts.pending
$QueueRunning = ConvertTo-PDACommanderInt -Value $Queue.counts.running
$QueueCompleted = ConvertTo-PDACommanderInt -Value $Queue.counts.completed
$QueueResults = ConvertTo-PDACommanderInt -Value $Queue.counts.results
$MemoryCandidateCount = if ($Memory.PSObject.Properties.Name -contains "candidate_count") { ConvertTo-PDACommanderInt -Value $Memory.candidate_count } else { 0 }
$MemoryCount = ConvertTo-PDACommanderInt -Value $Memory.count
$DashboardHealth = ConvertTo-PDACommanderString -Value $DashboardStatus.dashboard_health.status -Default "degraded"

$RecommendedActions = New-Object System.Collections.Generic.List[object]
if ($PendingApprovals -gt 0) {
    $RecommendedActions.Add([pscustomobject]@{
        action = "Review pending approvals"
        executor = "Human operator"
        reason = "{0} approval(s) are waiting." -f $PendingApprovals
    })
}

if ($FailedCount -gt 0) {
    $RecommendedActions.Add([pscustomobject]@{
        action = "Investigate failed tasks"
        executor = "PowerShell"
        reason = "{0} failed task(s) are present in the queue." -f $FailedCount
    })
}

if ($CandidatePending -gt 0) {
    $RecommendedActions.Add([pscustomobject]@{
        action = "Process memory candidates"
        executor = "Human operator"
        reason = "{0} memory candidate(s) are waiting for approval." -f $CandidatePending
    })
}

$TopPendingTask = @($Queue.latest.pending | Select-Object -First 1)[0]
$TopPendingCommand = ConvertTo-PDACommanderString -Value $TopPendingTask.command
if ($null -ne $TopPendingTask -and -not [string]::IsNullOrWhiteSpace($TopPendingCommand)) {
    $Recommendation = $null
    if (Test-Path -LiteralPath $RecommendationScript -PathType Leaf) {
        try {
            $TopPendingCategory = if (-not [string]::IsNullOrWhiteSpace((ConvertTo-PDACommanderString -Value $TopPendingTask.category))) { ConvertTo-PDACommanderString -Value $TopPendingTask.category } else { "category_1" }
            $Recommendation = & pwsh -NoProfile -File $RecommendationScript -Text $TopPendingCommand -Category $TopPendingCategory -AsJson
            $Recommendation = ConvertFrom-PDAMixedJson -Text ([string]$Recommendation) -SourceName $RecommendationScript
        }
        catch {
            $Recommendation = $null
        }
    }

    $RecommendedActions.Add([pscustomobject]@{
        action = "Work the next queued item: {0}" -f $TopPendingCommand
        executor = if ($Recommendation -and $Recommendation.recommended_executor) { ConvertTo-PDACommanderString -Value $Recommendation.recommended_executor } else { "Best matching local executor" }
        reason = if ($Recommendation -and $Recommendation.routing_reason) { ConvertTo-PDACommanderString -Value $Recommendation.routing_reason } else { "The next queued item is already classified." }
    })
}
elseif ($QueueDepth -gt 0) {
    $RecommendedActions.Add([pscustomobject]@{
        action = "Triage the queue"
        executor = "Human operator"
        reason = "The queue has pending work but no classified top item was available."
    })
}

if ($RecommendedActions.Count -eq 0) {
    $RecommendedActions.Add([pscustomobject]@{
        action = "Review the dashboard and continue normal operations"
        executor = "Human operator"
        reason = "No immediate blockers were found."
    })
}

$TopAction = $RecommendedActions[0]
$BriefingStatus = if ($DashboardHealth -eq "pass") { "pass" } elseif ($DashboardHealth -eq "warning") { "warning" } else { "degraded" }
$GeneratedAt = if ($DashboardStatus.generated_at) { ConvertTo-PDACommanderString -Value $DashboardStatus.generated_at } else { (Get-Date).ToUniversalTime().ToString("o") }
$NextAction = ConvertTo-PDACommanderString -Value $TopAction.action
$RecommendedExecutor = ConvertTo-PDACommanderString -Value $TopAction.executor
$FocusText = ConvertTo-PDACommanderString -Value $Focus -Default "default"
$BlockedItemsArray = @()
if ($BlockedItems.Count -gt 0) {
    $BlockedItemsArray = @($BlockedItems | ForEach-Object { $_ })
}

$RecommendedActionsArray = @()
if ($RecommendedActions.Count -gt 0) {
    $RecommendedActionsArray = @($RecommendedActions | ForEach-Object { $_ })
}

$BlockedItems = New-Object System.Collections.Generic.List[object]
if ($PendingApprovals -gt 0) {
    $BlockedItems.Add([pscustomobject]@{
        type = "approval_backlog"
        count = $PendingApprovals
        description = "Pending approvals need human review."
    })
}
if ($FailedCount -gt 0) {
    $BlockedItems.Add([pscustomobject]@{
        type = "failed_tasks"
        count = $FailedCount
        description = "Failed tasks need investigation."
    })
}

$Briefing = [pscustomobject]@{}
$BriefingQueue = [pscustomobject]@{
    pending = $QueuePending
    running = $QueueRunning
    failed = $FailedCount
    completed = $QueueCompleted
    results = $QueueResults
    depth = $QueueDepth
}
$BriefingMemory = [pscustomobject]@{
    candidates_pending_approval = $CandidatePending
    candidate_count = $MemoryCandidateCount
    promoted_count = $PromotedCount
    memory_count = $MemoryCount
}
$BriefingRecentActivity = [pscustomobject]@{
    completed_tasks = @($RecentTasks)
    promoted_memories = @($RecentMemories)
}

$Briefing | Add-Member -NotePropertyName "status" -NotePropertyValue $BriefingStatus -Force
$Briefing | Add-Member -NotePropertyName "generated_at" -NotePropertyValue $GeneratedAt -Force
$Briefing | Add-Member -NotePropertyName "focus" -NotePropertyValue $FocusText -Force
$Briefing | Add-Member -NotePropertyName "dashboard_health" -NotePropertyValue $DashboardHealth -Force
$Briefing | Add-Member -NotePropertyName "queue" -NotePropertyValue $BriefingQueue -Force
$Briefing | Add-Member -NotePropertyName "memory" -NotePropertyValue $BriefingMemory -Force
$Briefing | Add-Member -NotePropertyName "recent_activity" -NotePropertyValue $BriefingRecentActivity -Force
$Briefing | Add-Member -NotePropertyName "blocked_items" -NotePropertyValue $BlockedItemsArray -Force
$Briefing | Add-Member -NotePropertyName "recommended_actions" -NotePropertyValue $RecommendedActionsArray -Force
$Briefing | Add-Member -NotePropertyName "next_action" -NotePropertyValue $NextAction -Force
$Briefing | Add-Member -NotePropertyName "recommended_executor" -NotePropertyValue $RecommendedExecutor -Force
$Briefing | Add-Member -NotePropertyName "briefing_text" -NotePropertyValue "" -Force

$BriefingLines = New-Object System.Collections.Generic.List[string]
$BriefingLines.Add("PDA DAILY BRIEF")
$BriefingLines.Add("")
if (-not [string]::IsNullOrWhiteSpace($Briefing.focus)) {
    $BriefingLines.Add(("Focus: {0}" -f $Briefing.focus))
    $BriefingLines.Add("")
}
$BriefingLines.Add("Queue:")
$BriefingLines.Add(("- Pending: {0}" -f (ConvertTo-PDACommanderString -Value $Briefing.queue.pending)))
$BriefingLines.Add(("- Running: {0}" -f (ConvertTo-PDACommanderString -Value $Briefing.queue.running)))
$BriefingLines.Add(("- Failed: {0}" -f (ConvertTo-PDACommanderString -Value $Briefing.queue.failed)))
$BriefingLines.Add("")
$BriefingLines.Add("Memory:")
$BriefingLines.Add(("- Candidates awaiting approval: {0}" -f (ConvertTo-PDACommanderString -Value $Briefing.memory.candidates_pending_approval)))
$BriefingLines.Add(("- Promoted memories: {0}" -f (ConvertTo-PDACommanderString -Value $Briefing.memory.promoted_count)))
$BriefingLines.Add("")
$BriefingLines.Add("Recent Activity:")
if (@($Briefing.recent_activity.completed_tasks).Count -gt 0) {
    foreach ($Task in @($Briefing.recent_activity.completed_tasks | Select-Object -First 3)) {
        $TaskId = if ($null -ne $Task -and $Task.PSObject.Properties.Name -contains "task_id") { ConvertTo-PDACommanderString -Value $Task.task_id } else { "" }
        $Command = if ($null -ne $Task -and $Task.PSObject.Properties.Name -contains "command") { ConvertTo-PDACommanderString -Value $Task.command } else { "" }
        $Label = if (-not [string]::IsNullOrWhiteSpace($Command)) {
            if (-not [string]::IsNullOrWhiteSpace($TaskId)) { "$Command [$TaskId]" } else { $Command }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($TaskId)) {
            $TaskId
        }
        else {
            "unknown task"
        }
        $BriefingLines.Add(("- Completed: {0}" -f $Label))
    }
}
else {
    $BriefingLines.Add("- Completed: none recently")
}
if (@($Briefing.recent_activity.promoted_memories).Count -gt 0) {
    foreach ($MemoryItem in @($Briefing.recent_activity.promoted_memories | Select-Object -First 3)) {
        $MemoryTitle = if ($null -ne $MemoryItem -and $MemoryItem.PSObject.Properties.Name -contains "title" -and -not [string]::IsNullOrWhiteSpace((ConvertTo-PDACommanderString -Value $MemoryItem.title))) {
            ConvertTo-PDACommanderString -Value $MemoryItem.title
        }
        elseif ($null -ne $MemoryItem -and $MemoryItem.PSObject.Properties.Name -contains "memory_id") {
            ConvertTo-PDACommanderString -Value $MemoryItem.memory_id
        }
        else {
            "unknown memory"
        }
        $BriefingLines.Add(("- Promoted memory: {0}" -f $MemoryTitle))
    }
}
else {
    $BriefingLines.Add("- Promoted memory: none recently")
}
$BriefingLines.Add("")
$BriefingLines.Add("Recommended Actions:")
foreach ($Action in @($Briefing.recommended_actions)) {
    $BriefingLines.Add(("- {0}" -f (ConvertTo-PDACommanderString -Value $Action.action)))
    $BriefingLines.Add(("  Executor: {0}" -f (ConvertTo-PDACommanderString -Value $Action.executor)))
    $BriefingLines.Add(("  Reason: {0}" -f (ConvertTo-PDACommanderString -Value $Action.reason)))
}
$Briefing.briefing_text = ($BriefingLines -join "`r`n")

if ($AsJson) {
    $Briefing | ConvertTo-Json -Depth 20
    return
}

Write-Host "[PDA COMMANDER BRIEFING]"
Write-Host $Briefing.briefing_text

$Briefing
