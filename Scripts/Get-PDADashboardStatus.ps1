[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RootPath,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCoreIntegration,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCommanderBriefing
)

$ErrorActionPreference = "Stop"

$Root = if ([string]::IsNullOrWhiteSpace($RootPath)) {
    Split-Path -Parent $PSScriptRoot
}
else {
    $RootPath
}

$DashboardPath = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\PDA Dashboard.md"
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
$EnvironmentHelperScript = Join-Path $PSScriptRoot "PDA_Environment.ps1"
$COOPERProfileScript = Join-Path $PSScriptRoot "Get-COOPERIdentity.ps1"
$COOPERRuntimeStatusScript = Join-Path $PSScriptRoot "Get-COOPERRuntimeStatus.ps1"
$ApprovalWorkflowScript = Join-Path $PSScriptRoot "PDA_ApprovalWorkflow.ps1"
$ExecutionRequestScript = Join-Path $PSScriptRoot "Get-PDAExecutionRequest.ps1"
if (Test-Path -LiteralPath $ParserPath -PathType Leaf) {
    . $ParserPath
}
if (Test-Path -LiteralPath $EnvironmentHelperScript -PathType Leaf) {
    . $EnvironmentHelperScript
}
if (Test-Path -LiteralPath $COOPERProfileScript -PathType Leaf) {
    . $COOPERProfileScript
}
if (Test-Path -LiteralPath $COOPERRuntimeStatusScript -PathType Leaf) {
    . $COOPERRuntimeStatusScript
}
if (Test-Path -LiteralPath $ApprovalWorkflowScript -PathType Leaf) {
    . $ApprovalWorkflowScript
}

function ConvertTo-PDAHashtable {
    param([Parameter(Mandatory = $true)]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [hashtable] -or $Value -is [System.Collections.IDictionary]) {
        $Copy = @{}
        foreach ($Key in $Value.Keys) {
            $Copy[$Key] = ConvertTo-PDAHashtable -Value $Value[$Key]
        }
        return $Copy
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $List = @()
        foreach ($Item in $Value) {
            $List += ,(ConvertTo-PDAHashtable -Value $Item)
        }
        return $List
    }

    if ($Value -is [psobject] -and $Value.PSObject.Properties.Name.Count -gt 0) {
        $Copy = @{}
        foreach ($Prop in $Value.PSObject.Properties) {
            $Copy[$Prop.Name] = ConvertTo-PDAHashtable -Value $Prop.Value
        }
        return $Copy
    }

    return $Value
}

function Get-PDASafeString {
    param([Parameter(Mandatory = $false)]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return [string]$Value
}

function Get-PDADateValue {
    param([Parameter(Mandatory = $false)]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return [datetime]::MinValue
    }

    try {
        return [datetime]::Parse([string]$Value)
    }
    catch {
        return [datetime]::MinValue
    }
}

function Read-PDAJsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        $Raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($Raw)) {
            return $null
        }

        return $Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Get-PDAFriendlyHealthLabel {
    param([Parameter(Mandatory = $false)]$Value)

    $Text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return "Unknown"
    }

    switch ($Text.ToLowerInvariant()) {
        { $_ -in @("pass", "passed", "healthy", "healthy.", "online", "running", "running.") } { return "Healthy" }
        { $_ -in @("warning", "degraded", "degraded.") } { return "Degraded" }
        { $_ -in @("fail", "failed", "error", "unavailable") } { return "Unhealthy" }
        default { return $Text }
    }
}

function Get-PDAServiceHealth {
    param(
        [Parameter(Mandatory = $false)]
        [object]$EnvironmentServices,

        [Parameter(Mandatory = $true)]
        [string]$ServiceName,

        [Parameter(Mandatory = $false)]
        [string]$Default = "Unknown"
    )

    if ($null -eq $EnvironmentServices) {
        return $Default
    }

    $ServiceRows = @()
    if ($EnvironmentServices.PSObject.Properties.Name -contains "services" -and $EnvironmentServices.services) {
        $ServiceRows = @($EnvironmentServices.services)
    }

    $Match = @($ServiceRows | Where-Object { [string]$_.name -ieq $ServiceName } | Select-Object -First 1)[0]
    if ($null -eq $Match) {
        return $Default
    }

    $Label = Get-PDAFriendlyHealthLabel -Value $Match.status
    if ($Label -eq "Unknown") {
        return $Default
    }

    return $Label
}

function Invoke-PDAJsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $false)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$SourceName
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            status = "missing"
            issues = @("Script missing: $Path")
        }
    }

    try {
        $Raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1
        $Text = [string]($Raw -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($Text)) {
            throw "Script returned empty output."
        }

        return ConvertFrom-PDAMixedJson -Text $Text -SourceName $SourceName
    }
    catch {
        return [pscustomobject]@{
            status = "fail"
            issues = @($_.Exception.Message)
        }
    }
}

function Get-PDAQueueRecord {
    param(
        [Parameter(Mandatory = $true)][string]$QueueName,
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File
    )

    $Record = [ordered]@{
        queue = $QueueName
        file_name = $File.Name
        file_path = $File.FullName
        updated_at = $File.LastWriteTimeUtc.ToString("o")
        sort_time = $File.LastWriteTimeUtc
        task_id = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
        command = ""
        worker_name = ""
        category = ""
        status = $QueueName
        task_status = $QueueName
        approval_status = ""
        route_source = ""
        routing_surface = ""
        requires_confirmation = $false
        result_path = ""
    }

    try {
        $Parsed = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

        if ($Parsed.PSObject.Properties.Name -contains "task_id" -and -not [string]::IsNullOrWhiteSpace([string]$Parsed.task_id)) {
            $Record.task_id = [string]$Parsed.task_id
        }
        if ($Parsed.PSObject.Properties.Name -contains "command") {
            $Record.command = Get-PDASafeString $Parsed.command
        }
        if ($Parsed.PSObject.Properties.Name -contains "worker_name") {
            $Record.worker_name = Get-PDASafeString $Parsed.worker_name
        }
        elseif ($Parsed.PSObject.Properties.Name -contains "worker") {
            $Record.worker_name = Get-PDASafeString $Parsed.worker
        }
        elseif ($Parsed.PSObject.Properties.Name -contains "assigned_worker") {
            $Record.worker_name = Get-PDASafeString $Parsed.assigned_worker
        }
        if ($Parsed.PSObject.Properties.Name -contains "category") {
            $Record.category = Get-PDASafeString $Parsed.category
        }
        if ($Parsed.PSObject.Properties.Name -contains "status") {
            $Record.status = Get-PDASafeString $Parsed.status
        }
        if ($Parsed.PSObject.Properties.Name -contains "task_status") {
            $Record.task_status = Get-PDASafeString $Parsed.task_status
        }
        if ($Parsed.PSObject.Properties.Name -contains "approval_status") {
            $Record.approval_status = Get-PDASafeString $Parsed.approval_status
        }
        if ($Parsed.PSObject.Properties.Name -contains "route_source") {
            $Record.route_source = Get-PDASafeString $Parsed.route_source
        }
        if ($Parsed.PSObject.Properties.Name -contains "routing_surface") {
            $Record.routing_surface = Get-PDASafeString $Parsed.routing_surface
        }
        if ($Parsed.PSObject.Properties.Name -contains "requires_confirmation") {
            $Record.requires_confirmation = [bool]$Parsed.requires_confirmation
        }
        elseif ($QueueName -eq "approvals/pending") {
            $Record.requires_confirmation = $true
        }
        if ($Parsed.PSObject.Properties.Name -contains "result_path") {
            $Record.result_path = Get-PDASafeString $Parsed.result_path
        }

        if ($QueueName -eq "approvals/pending") {
            $Record.approval_status = "pending"
            $Record.task_status = "pending_approval"
            $Record.status = "pending_approval"
        }
        elseif ($QueueName -eq "approvals/approved") {
            $Record.approval_status = "approved"
        }
        elseif ($QueueName -eq "approvals/rejected") {
            $Record.approval_status = "rejected"
            $Record.task_status = "rejected"
            $Record.status = "rejected"
        }
        elseif ($QueueName -eq "results" -or $File.Name -match '-result\.json$') {
            $Record.task_status = "completed"
            $Record.status = "completed"
            if (-not [string]::IsNullOrWhiteSpace($Record.result_path)) {
                # keep parsed result path
            }
            else {
                $Record.result_path = $File.FullName
            }
        }
    }
    catch {
        $Record.status = "parse-error"
        $Record.task_status = "parse-error"
        $Record.parse_error = $_.Exception.Message
    }

    return [pscustomobject]$Record
}

function Get-PDAQueueSnapshot {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $QueueFolders = [ordered]@{
        pending = Join-Path $RootPath "PDA-Tasks\pending"
        running = Join-Path $RootPath "PDA-Tasks\running"
        completed = Join-Path $RootPath "PDA-Tasks\completed"
        failed = Join-Path $RootPath "PDA-Tasks\failed"
        results = Join-Path $RootPath "PDA-Tasks\results"
    }

    $ApprovalFolders = [ordered]@{
        "approvals/pending" = Join-Path $RootPath "PDA-Tasks\approvals\pending"
        "approvals/approved" = Join-Path $RootPath "PDA-Tasks\approvals\approved"
        "approvals/rejected" = Join-Path $RootPath "PDA-Tasks\approvals\rejected"
    }

    $Counts = [ordered]@{
        pending = 0
        running = 0
        completed = 0
        failed = 0
        results = 0
        approvals_pending = 0
        approvals_approved = 0
        approvals_rejected = 0
    }

    $RecentRecords = @()
    $LatestByQueue = @{}
    foreach ($QueueName in $QueueFolders.Keys) {
        $Folder = $QueueFolders[$QueueName]
        if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
            continue
        }

        $Files = @(Get-ChildItem -LiteralPath $Folder -Filter *.json -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
        $Counts[$QueueName] = $Files.Count
        if ($Files.Count -gt 0) {
            $LatestByQueue[$QueueName] = Get-PDAQueueRecord -QueueName $QueueName -File $Files[0]
        }

        foreach ($File in @($Files | Select-Object -First 20)) {
            $RecentRecords += Get-PDAQueueRecord -QueueName $QueueName -File $File
        }
    }

    foreach ($ApprovalKey in $ApprovalFolders.Keys) {
        $Folder = $ApprovalFolders[$ApprovalKey]
        if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
            continue
        }

        $Files = @(Get-ChildItem -LiteralPath $Folder -Filter *.json -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
        switch ($ApprovalKey) {
            "approvals/pending" { $Counts.approvals_pending = $Files.Count }
            "approvals/approved" { $Counts.approvals_approved = $Files.Count }
            "approvals/rejected" { $Counts.approvals_rejected = $Files.Count }
        }

        foreach ($File in @($Files | Select-Object -First 20)) {
            $Record = Get-PDAQueueRecord -QueueName $ApprovalKey -File $File
            if ([string]::IsNullOrWhiteSpace($Record.task_status)) {
                $Record.task_status = "pending_approval"
            }
            $RecentRecords += $Record
        }
    }

    $UniqueRecentTasks = @()
    foreach ($Record in @($RecentRecords | Sort-Object sort_time -Descending)) {
        if ([string]::IsNullOrWhiteSpace([string]$Record.task_id)) {
            continue
        }

        if ($UniqueRecentTasks | Where-Object { [string]$_.task_id -eq [string]$Record.task_id }) {
            continue
        }

        $UniqueRecentTasks += $Record
        if ($UniqueRecentTasks.Count -ge 15) {
            break
        }
    }

    $UniqueRecentApprovals = @()
    foreach ($Record in @($RecentRecords | Where-Object { [string]$_.approval_status -eq "pending" } | Sort-Object sort_time -Descending)) {
        if ([string]::IsNullOrWhiteSpace([string]$Record.task_id)) {
            continue
        }

        if ($UniqueRecentApprovals | Where-Object { [string]$_.task_id -eq [string]$Record.task_id }) {
            continue
        }

        $UniqueRecentApprovals += $Record
        if ($UniqueRecentApprovals.Count -ge 15) {
            break
        }
    }

    return [pscustomobject]@{
        counts = [pscustomobject]$Counts
        queue_depth = ([int]$Counts.pending + [int]$Counts.running)
        latest = [pscustomobject]@{
            pending = @($LatestByQueue["pending"])
            running = @($LatestByQueue["running"])
            completed = @($LatestByQueue["completed"])
            failed = @($LatestByQueue["failed"])
            result = @($LatestByQueue["results"])
        }
        recent_tasks = @($UniqueRecentTasks)
        pending_approvals = @($UniqueRecentApprovals)
    }
}

function Get-PDAWorkerSnapshot {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $RegistryPath = Join-Path $RootPath "Scripts\PDA_WorkerRegistry.json"
    $WorkerStateFiles = @(
        Join-Path $RootPath "PDA-Logs\workers\pda-worker-state.json"
        Join-Path $RootPath "PDA-Logs\workers\pda-reporter-intake-state.json"
        Join-Path $RootPath "PDA-Logs\workers\pda-multiagent-intake-state.json"
    )
    $HeartbeatDir = Join-Path $RootPath "PDA-Logs\heartbeats"

    $Registry = Read-PDAJsonFile -Path $RegistryPath
    $Workers = @()
    if ($Registry) {
        if ($Registry.PSObject.Properties.Name -contains "workers" -and $Registry.workers) {
            $Workers = @($Registry.workers)
        }
        elseif ($Registry -is [System.Collections.IEnumerable] -and $Registry -isnot [string]) {
            $Workers = @($Registry)
        }
    }

    $WorkerRows = @($Workers | ForEach-Object {
        [pscustomobject]@{
            worker_name = Get-PDASafeString $_.worker_name
            command = Get-PDASafeString $_.command
            purpose = Get-PDASafeString $_.purpose
            routing_surface = Get-PDASafeString $_.routing_surface
            status = Get-PDASafeString $_.status
            cloud_capable = [bool]($_.cloud_capable)
            accepted_input_modes = @($_.accepted_input_modes)
            category_support = @($_.category_support)
        }
    })

    $RuntimeStates = @()
    foreach ($Path in $WorkerStateFiles) {
        $State = Read-PDAJsonFile -Path $Path
        if ($null -eq $State) {
            continue
        }

        $RuntimeStates += [pscustomobject]@{
            component = [System.IO.Path]::GetFileNameWithoutExtension($Path)
            status = Get-PDASafeString $State.status
            pid = if ($State.PSObject.Properties.Name -contains "pid") { [int]$State.pid } else { $null }
            started_at = if ($State.PSObject.Properties.Name -contains "started_at") { Get-PDASafeString $State.started_at } else { "" }
            log_file = if ($State.PSObject.Properties.Name -contains "log_file") { Get-PDASafeString $State.log_file } else { "" }
            script = if ($State.PSObject.Properties.Name -contains "script") { Get-PDASafeString $State.script } else { "" }
        }
    }

    $HeartbeatRows = @()
    if (Test-Path -LiteralPath $HeartbeatDir -PathType Container) {
        foreach ($File in Get-ChildItem -LiteralPath $HeartbeatDir -File -Filter "*-heartbeat.json" -ErrorAction SilentlyContinue) {
            try {
                $Heartbeat = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $HeartbeatTime = [datetime]$Heartbeat.heartbeat_at
                $Age = New-TimeSpan -Start $HeartbeatTime -End (Get-Date)
                $ProcessLive = $false
                if ($Heartbeat.PSObject.Properties.Name -contains "process_id" -and $Heartbeat.process_id) {
                    $ProcessLive = $null -ne (Get-Process -Id $Heartbeat.process_id -ErrorAction SilentlyContinue)
                }

                $HeartbeatRows += [pscustomobject]@{
                    worker_name = Get-PDASafeString $Heartbeat.worker_name
                    status = Get-PDASafeString $Heartbeat.status
                    pid = if ($Heartbeat.PSObject.Properties.Name -contains "process_id") { [int]$Heartbeat.process_id } else { $null }
                    process_live = [bool]$ProcessLive
                    heartbeat_at = Get-PDASafeString $Heartbeat.heartbeat_at
                    age_minutes = [math]::Round($Age.TotalMinutes, 2)
                    state = if ($Age.TotalMinutes -gt 5) { "STALE" } else { "OK" }
                }
            }
            catch {
                $HeartbeatRows += [pscustomobject]@{
                    worker_name = $File.BaseName
                    status = "parse-error"
                    pid = $null
                    process_live = $false
                    heartbeat_at = ""
                    age_minutes = $null
                    state = "ERROR"
                }
            }
        }
    }

    return [pscustomobject]@{
        registry = [pscustomobject]@{
            path = $RegistryPath
            workers = @($WorkerRows)
            active_count = @($WorkerRows | Where-Object { [string]$_.status -eq "active" }).Count
            experimental_count = @($WorkerRows | Where-Object { [string]$_.status -eq "experimental" }).Count
        }
        runtime_states = @($RuntimeStates)
        heartbeats = @($HeartbeatRows)
    }
}

function Get-PDAArtifactSnapshot {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $IndexPath = Join-Path $RootPath "PDA_ArtifactIndex.json"
    $Index = Read-PDAJsonFile -Path $IndexPath
    $Artifacts = @()
    if ($Index -and ($Index.PSObject.Properties.Name -contains "artifacts") -and $Index.artifacts) {
        $Artifacts = @($Index.artifacts)
    }

    $Recent = @(
        $Artifacts |
            Sort-Object @{ Expression = { Get-PDADateValue $_.created_at } } -Descending |
            Select-Object -First 10 |
            ForEach-Object {
                [pscustomobject]@{
                    artifact_id = Get-PDASafeString $_.artifact_id
                    created_at = Get-PDASafeString $_.created_at
                    worker_name = Get-PDASafeString $_.worker_name
                    category = Get-PDASafeString $_.category
                    artifact_type = Get-PDASafeString $_.artifact_type
                    source_task_id = if ($_.PSObject.Properties.Name -contains "source_task_id") { Get-PDASafeString $_.source_task_id } else { "" }
                    artifact_path = if ($_.PSObject.Properties.Name -contains "artifact_path") { Get-PDASafeString $_.artifact_path } else { "" }
                    summary = Get-PDASafeString $_.summary
                }
            }
    )

    $ByWorker = @(
        $Artifacts |
            Group-Object worker_name |
            Sort-Object Count -Descending |
            ForEach-Object {
                [pscustomobject]@{
                    name = Get-PDASafeString $_.Name
                    count = [int]$_.Count
                }
            }
    )

    return [pscustomobject]@{
        path = $IndexPath
        status = $(if ($null -ne $Index) { "pass" } else { "missing" })
        count = @($Artifacts).Count
        updated_at = if ($Index -and $Index.PSObject.Properties.Name -contains "updated_at") { Get-PDASafeString $Index.updated_at } else { "" }
        recent = @($Recent)
        by_worker = @($ByWorker)
        artifacts = @($Artifacts)
    }
}

function Get-PDAMemorySnapshot {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $IndexPath = Join-Path $RootPath "PDA_MemoryIndex.json"
    $Index = Read-PDAJsonFile -Path $IndexPath
    $Memories = @()
    if ($Index -and ($Index.PSObject.Properties.Name -contains "memories") -and $Index.memories) {
        $Memories = @($Index.memories)
    }

    $Recent = @(
        $Memories |
            Sort-Object @{ Expression = { Get-PDADateValue $_.created_at } } -Descending |
            Select-Object -First 10 |
            ForEach-Object {
                [pscustomobject]@{
                    memory_id = Get-PDASafeString $_.memory_id
                    created_at = Get-PDASafeString $_.created_at
                    memory_type = Get-PDASafeString $_.memory_type
                    category = Get-PDASafeString $_.category
                    title = if ($_.PSObject.Properties.Name -contains "title") { Get-PDASafeString $_.title } else { "" }
                    summary = Get-PDASafeString $_.summary
                    source_artifact_id = if ($_.PSObject.Properties.Name -contains "source_artifact_id") { Get-PDASafeString $_.source_artifact_id } else { "" }
                }
            }
    )

    $ByType = @(
        $Memories |
            Group-Object memory_type |
            Sort-Object Count -Descending |
            ForEach-Object {
                [pscustomobject]@{
                    name = Get-PDASafeString $_.Name
                    count = [int]$_.Count
                }
            }
    )

    $ByCategory = @(
        $Memories |
            Group-Object category |
            Sort-Object Count -Descending |
            ForEach-Object {
                [pscustomobject]@{
                    name = Get-PDASafeString $_.Name
                    count = [int]$_.Count
                }
            }
    )

    return [pscustomobject]@{
        path = $IndexPath
        status = $(if ($null -ne $Index) { "pass" } else { "missing" })
        count = @($Memories).Count
        updated_at = if ($Index -and $Index.PSObject.Properties.Name -contains "updated_at") { Get-PDASafeString $Index.updated_at } else { "" }
        recent = @($Recent)
        by_type = @($ByType)
        by_category = @($ByCategory)
        memories = @($Memories)
    }
}

function Get-PDAAgentLoopSnapshot {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $RunRoot = Join-Path $RootPath "PDA-Agent-Runs"
    $IndexPath = Join-Path $RunRoot "index.json"
    $RunFiles = @()
    if (Test-Path -LiteralPath $RunRoot -PathType Container) {
        $RunFiles = @(Get-ChildItem -LiteralPath $RunRoot -File -Filter *.json -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "index.json" })
    }

    $Runs = New-Object System.Collections.Generic.List[object]
    foreach ($File in @($RunFiles | Sort-Object LastWriteTimeUtc -Descending)) {
        $Run = Read-PDAJsonFile -Path $File.FullName
        if (-not $Run) {
            continue
        }

        $CurrentStep = if ($Run.PSObject.Properties.Name -contains "current_step") { $Run.current_step } else { $null }
        $Runs.Add([pscustomobject]@{
            run_id             = if ($Run.PSObject.Properties.Name -contains "run_id") { Get-PDASafeString $Run.run_id } else { $File.BaseName }
            goal               = if ($Run.PSObject.Properties.Name -contains "goal") { Get-PDASafeString $Run.goal } else { "" }
            category           = if ($Run.PSObject.Properties.Name -contains "category") { Get-PDASafeString $Run.category } else { "" }
            status             = if ($Run.PSObject.Properties.Name -contains "status") { Get-PDASafeString $Run.status } else { "unknown" }
            approval_status    = if ($Run.PSObject.Properties.Name -contains "approval_status") { Get-PDASafeString $Run.approval_status } else { "" }
            current_step       = if ($CurrentStep -and $CurrentStep.PSObject.Properties.Name -contains "title") { Get-PDASafeString $CurrentStep.title } else { "" }
            assigned_tool      = if ($Run.PSObject.Properties.Name -contains "assigned_tool") { Get-PDASafeString $Run.assigned_tool } else { "" }
            next_action        = if ($Run.PSObject.Properties.Name -contains "next_action") { Get-PDASafeString $Run.next_action } else { "" }
            iteration_count    = if ($Run.PSObject.Properties.Name -contains "iteration_count") { [int]$Run.iteration_count } else { 0 }
            max_iterations     = if ($Run.PSObject.Properties.Name -contains "max_iterations") { [int]$Run.max_iterations } else { 0 }
            created_at         = if ($Run.PSObject.Properties.Name -contains "created_at") { Get-PDASafeString $Run.created_at } else { "" }
            updated_at         = if ($Run.PSObject.Properties.Name -contains "updated_at") { Get-PDASafeString $Run.updated_at } else { "" }
            plan_id            = if ($Run.PSObject.Properties.Name -contains "plan" -and $Run.plan.PSObject.Properties.Name -contains "plan_id") { Get-PDASafeString $Run.plan.plan_id } else { "" }
        })
    }

    $RunCount = @($Runs).Count
    $PendingApprovalCount = @($Runs | Where-Object { [string]$_.status -eq "pending_approval" -or [string]$_.approval_status -eq "pending" }).Count
    $ActiveRunCount = @($Runs | Where-Object { [string]$_.status -in @("pending_approval", "ready_for_action", "running", "reviewing") }).Count
    $BlockedCount = @($Runs | Where-Object { [string]$_.status -eq "blocked" }).Count
    $CompletedCount = @($Runs | Where-Object { [string]$_.status -eq "completed" }).Count
    $LatestRun = @($Runs | Select-Object -First 1)[0]

    return [pscustomobject]@{
        path                = $RunRoot
        index_path          = $IndexPath
        status              = $(if ($RunCount -gt 0) { "pass" } else { "empty" })
        run_count           = [int]$RunCount
        active_run_count    = [int]$ActiveRunCount
        pending_approval_count = [int]$PendingApprovalCount
        blocked_count       = [int]$BlockedCount
        completed_count     = [int]$CompletedCount
        latest_run          = $LatestRun
        recent_runs         = @($Runs | Select-Object -First 5)
        runs                = @($Runs)
    }
}

function Get-PDAModelStatus {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $RoutingPolicyPath = Join-Path $RootPath "Scripts\PDA_ModelRouting.json"
    $RoutingPolicy = Read-PDAJsonFile -Path $RoutingPolicyPath
    $RoutingSummary = [ordered]@{
        path = $RoutingPolicyPath
        status = $(if ($null -ne $RoutingPolicy) { "pass" } else { "missing" })
        command_routes = @()
        category_routes = @()
    }
    if ($RoutingPolicy) {
        if ($RoutingPolicy.PSObject.Properties.Name -contains "command_routes" -and $RoutingPolicy.command_routes) {
            foreach ($Key in @($RoutingPolicy.command_routes.PSObject.Properties.Name)) {
                $Route = $RoutingPolicy.command_routes.$Key
                $RoutingSummary.command_routes += [pscustomobject]@{
                    command = $Key
                    primary_model = Get-PDASafeString $Route.primary_model
                    fallback_chain = @($Route.fallback_chain)
                    routing_surface = Get-PDASafeString $Route.routing_surface
                    cloud_allowed = [bool]$Route.cloud_allowed
                }
            }
        }
        if ($RoutingPolicy.PSObject.Properties.Name -contains "category_routes" -and $RoutingPolicy.category_routes) {
            foreach ($Key in @($RoutingPolicy.category_routes.PSObject.Properties.Name)) {
                $Route = $RoutingPolicy.category_routes.$Key
                $RoutingSummary.category_routes += [pscustomobject]@{
                    category = $Key
                    primary_model = Get-PDASafeString $Route.primary_model
                    fallback_chain = @($Route.fallback_chain)
                    routing_surface = Get-PDASafeString $Route.routing_surface
                    cloud_allowed = [bool]$Route.cloud_allowed
                }
            }
        }
    }

    $ProvidersScript = Join-Path $PSScriptRoot "Test-PDALiteLLMProviders.ps1"
    $EnvScript = Join-Path $PSScriptRoot "Test-PDALiteLLMEnv.ps1"
    $Providers = Invoke-PDAJsonScript -Path $ProvidersScript -Arguments @("-AsJson", "-NoThrow") -SourceName "LiteLLM provider validation"
    $Env = Invoke-PDAJsonScript -Path $EnvScript -Arguments @("-AsJson", "-NoThrow") -SourceName "LiteLLM env validation"

    $ProviderRows = @()
    if ($Providers -and $Providers.PSObject.Properties.Name -contains "providers" -and $Providers.providers) {
        $ProviderRows = @($Providers.providers | ForEach-Object {
            [pscustomobject]@{
                name = Get-PDASafeString $_.name
                model_name = Get-PDASafeString $_.model_name
                configured = [bool]$_.configured
                env_reference_ok = [bool]$_.env_reference_ok
                host_env_present = if ($_.PSObject.Properties.Name -contains "host_env_present") { [bool]$_.host_env_present } else { $false }
                live_available = [bool]$_.live_available
                api_provider = Get-PDASafeString $_.api_provider
                env_name = Get-PDASafeString $_.env_name
                issues = @($_.issues)
            }
        })
    }

    return [pscustomobject]@{
        status = $(if (([string]$Providers.status -eq "pass" -or [string]$Providers.status -eq "warn") -and ([string]$Env.status -in @("pass", "warn")) -and $RoutingSummary.status -eq "pass") { "pass" } else { "degraded" })
        routing_policy = [pscustomobject]$RoutingSummary
        provider_validation = [pscustomobject]@{
            status = Get-PDASafeString $Providers.status
            endpoint = if ($Providers.PSObject.Properties.Name -contains "endpoint") { Get-PDASafeString $Providers.endpoint } else { "" }
            provider_count = if ($Providers.PSObject.Properties.Name -contains "provider_count") { [int]$Providers.provider_count } else { @($ProviderRows).Count }
            passed_count = if ($Providers.PSObject.Properties.Name -contains "provider_pass_count") { [int]$Providers.provider_pass_count } else { @($ProviderRows | Where-Object { $_.configured -and $_.live_available -and $_.env_reference_ok -and @($_.issues).Count -eq 0 }).Count }
            failed_count = if ($Providers.PSObject.Properties.Name -contains "provider_fail_count") { [int]$Providers.provider_fail_count } else { @($ProviderRows).Count - @($ProviderRows | Where-Object { $_.configured -and $_.live_available -and $_.env_reference_ok -and @($_.issues).Count -eq 0 }).Count }
            providers = @($ProviderRows)
            issues = @($Providers.issues)
        }
        env_validation = [pscustomobject]@{
            status = Get-PDASafeString $Env.status
            compose_path = if ($Env.PSObject.Properties.Name -contains "compose_path") { Get-PDASafeString $Env.compose_path } else { "" }
            env_path = if ($Env.PSObject.Properties.Name -contains "env_path") { Get-PDASafeString $Env.env_path } else { "" }
            example_path = if ($Env.PSObject.Properties.Name -contains "example_path") { Get-PDASafeString $Env.example_path } else { "" }
            loaded_key_count = if ($Env.PSObject.Properties.Name -contains "loaded_key_count") { [int]$Env.loaded_key_count } else { 0 }
            blank_key_count = if ($Env.PSObject.Properties.Name -contains "blank_key_count") { [int]$Env.blank_key_count } else { 0 }
            missing_key_count = if ($Env.PSObject.Properties.Name -contains "missing_key_count") { [int]$Env.missing_key_count } else { 0 }
            issues = @($Env.issues)
        }
    }
}

function Get-PDACoreIntegrationStatus {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $ConversationStateScript = Join-Path $PSScriptRoot "Get-PDAConversationState.ps1"
    $TaskResultScript = Join-Path $PSScriptRoot "Get-PDATaskResult.ps1"
    $InterpreterScript = Join-Path $PSScriptRoot "Test-PDACommandInterpreter.ps1"
    $HandoffScript = Join-Path $PSScriptRoot "Test-PDACommandHandoff.ps1"
    $ChatBridgeScript = Join-Path $PSScriptRoot "Test-PDAChatBridge.ps1"
    $WebhookBridgeScript = Join-Path $PSScriptRoot "Test-PDAWebhookBridge.ps1"

    $ConversationState = Invoke-PDAJsonScript -Path $ConversationStateScript -Arguments @("-AsJson", "-NoThrow") -SourceName "Conversation state"
    $TaskResult = Invoke-PDAJsonScript -Path $TaskResultScript -Arguments @("-AsJson", "-NoThrow") -SourceName "Task result lookup"
    $Interpreter = Invoke-PDAJsonScript -Path $InterpreterScript -Arguments @("-AsJson", "-NoThrow", "-SkipOperatorConsole") -SourceName "Command interpreter"
    $Handoff = Invoke-PDAJsonScript -Path $HandoffScript -Arguments @("-AsJson", "-NoThrow", "-SkipOperatorConsole", "-SkipDispatch", "-DashboardMode") -SourceName "Command handoff"
    $ChatBridge = Invoke-PDAJsonScript -Path $ChatBridgeScript -Arguments @("-AsJson", "-NoThrow", "-SkipOperatorConsole", "-SkipDispatch", "-DashboardMode") -SourceName "Chat bridge"
    $WebhookBridge = Invoke-PDAJsonScript -Path $WebhookBridgeScript -Arguments @("-AsJson", "-NoThrow", "-SkipDispatch", "-DashboardMode") -SourceName "Webhook bridge"

    $ConversationSummary = [pscustomobject]@{
        status = Get-PDASafeString $ConversationState.status
        conversation_id = if ($ConversationState.PSObject.Properties.Name -contains "conversation_id") { Get-PDASafeString $ConversationState.conversation_id } else { "" }
        active_task_count = if ($ConversationState.PSObject.Properties.Name -contains "active_task_count") { [int]$ConversationState.active_task_count } else { 0 }
        pending_approval_count = if ($ConversationState.PSObject.Properties.Name -contains "pending_approval_count") { [int]$ConversationState.pending_approval_count } else { 0 }
        submitted_task_count = if ($ConversationState.PSObject.Properties.Name -contains "submitted_task_count") { [int]$ConversationState.submitted_task_count } else { 0 }
        completed_task_count = if ($ConversationState.PSObject.Properties.Name -contains "completed_task_count") { [int]$ConversationState.completed_task_count } else { 0 }
        latest_task_id = if ($ConversationState.PSObject.Properties.Name -contains "latest_task_id") { Get-PDASafeString $ConversationState.latest_task_id } else { "" }
        latest_result_path = if ($ConversationState.PSObject.Properties.Name -contains "latest_result_path") { Get-PDASafeString $ConversationState.latest_result_path } else { "" }
        response_text = if ($ConversationState.PSObject.Properties.Name -contains "response_text") { Get-PDASafeString $ConversationState.response_text } else { "" }
        next_action = if ($ConversationState.PSObject.Properties.Name -contains "next_action") { Get-PDASafeString $ConversationState.next_action } else { "" }
    }

    $TaskResultSummary = [pscustomobject]@{
        status = Get-PDASafeString $TaskResult.status
        conversation_id = if ($TaskResult.PSObject.Properties.Name -contains "conversation_id") { Get-PDASafeString $TaskResult.conversation_id } else { "" }
        task_id = if ($TaskResult.PSObject.Properties.Name -contains "task_id") { Get-PDASafeString $TaskResult.task_id } else { "" }
        latest_task_id = if ($TaskResult.PSObject.Properties.Name -contains "latest_task_id") { Get-PDASafeString $TaskResult.latest_task_id } else { "" }
        latest_result_path = if ($TaskResult.PSObject.Properties.Name -contains "latest_result_path") { Get-PDASafeString $TaskResult.latest_result_path } else { "" }
        response_text = if ($TaskResult.PSObject.Properties.Name -contains "response_text") { Get-PDASafeString $TaskResult.response_text } else { "" }
        next_action = if ($TaskResult.PSObject.Properties.Name -contains "next_action") { Get-PDASafeString $TaskResult.next_action } else { "" }
        active_task_count = if ($TaskResult.PSObject.Properties.Name -contains "active_task_count") { [int]$TaskResult.active_task_count } else { 0 }
        pending_approval_count = if ($TaskResult.PSObject.Properties.Name -contains "pending_approval_count") { [int]$TaskResult.pending_approval_count } else { 0 }
        completed_task_count = if ($TaskResult.PSObject.Properties.Name -contains "completed_task_count") { [int]$TaskResult.completed_task_count } else { 0 }
    }

    return [pscustomobject]@{
        status = $(if ($Interpreter.status -eq "pass" -and $Handoff.status -eq "pass" -and $ChatBridge.status -eq "pass") { "pass" } else { "degraded" })
        conversation_state = $ConversationSummary
        task_result = $TaskResultSummary
        command_interpreter = [pscustomobject]@{
            status = Get-PDASafeString $Interpreter.status
            test_case_count = if ($Interpreter.PSObject.Properties.Name -contains "test_case_count") { [int]$Interpreter.test_case_count } else { 0 }
            passed_count = if ($Interpreter.PSObject.Properties.Name -contains "passed_count") { [int]$Interpreter.passed_count } else { 0 }
            failed_count = if ($Interpreter.PSObject.Properties.Name -contains "failed_count") { [int]$Interpreter.failed_count } else { 0 }
            mapped_count = if ($Interpreter.PSObject.Properties.Name -contains "mapped_count") { [int]$Interpreter.mapped_count } else { 0 }
            ambiguous_count = if ($Interpreter.PSObject.Properties.Name -contains "ambiguous_count") { [int]$Interpreter.ambiguous_count } else { 0 }
            unknown_count = if ($Interpreter.PSObject.Properties.Name -contains "unknown_count") { [int]$Interpreter.unknown_count } else { 0 }
            results = if ($Interpreter.PSObject.Properties.Name -contains "results") { @($Interpreter.results) } else { @() }
        }
        command_handoff = [pscustomobject]@{
            status = Get-PDASafeString $Handoff.status
            test_case_count = if ($Handoff.PSObject.Properties.Name -contains "test_case_count") { [int]$Handoff.test_case_count } else { 0 }
            passed_count = if ($Handoff.PSObject.Properties.Name -contains "passed_count") { [int]$Handoff.passed_count } else { 0 }
            failed_count = if ($Handoff.PSObject.Properties.Name -contains "failed_count") { [int]$Handoff.failed_count } else { 0 }
            dispatch_confirmed_count = if ($Handoff.PSObject.Properties.Name -contains "dispatch_confirmed_count") { [int]$Handoff.dispatch_confirmed_count } else { 0 }
            dispatch_blocked_count = if ($Handoff.PSObject.Properties.Name -contains "dispatch_blocked_count") { [int]$Handoff.dispatch_blocked_count } else { 0 }
            results = if ($Handoff.PSObject.Properties.Name -contains "results") { @($Handoff.results) } else { @() }
        }
        chat_bridge = [pscustomobject]@{
            status = Get-PDASafeString $ChatBridge.status
            test_case_count = if ($ChatBridge.PSObject.Properties.Name -contains "test_case_count") { [int]$ChatBridge.test_case_count } else { 0 }
            passed_count = if ($ChatBridge.PSObject.Properties.Name -contains "passed_count") { [int]$ChatBridge.passed_count } else { 0 }
            failed_count = if ($ChatBridge.PSObject.Properties.Name -contains "failed_count") { [int]$ChatBridge.failed_count } else { 0 }
            dispatch_confirmed_count = if ($ChatBridge.PSObject.Properties.Name -contains "dispatch_confirmed_count") { [int]$ChatBridge.dispatch_confirmed_count } else { 0 }
            dispatch_blocked_count = if ($ChatBridge.PSObject.Properties.Name -contains "dispatch_blocked_count") { [int]$ChatBridge.dispatch_blocked_count } else { 0 }
            results = if ($ChatBridge.PSObject.Properties.Name -contains "results") { @($ChatBridge.results) } else { @() }
        }
        webhook_bridge = [pscustomobject]@{
            status = Get-PDASafeString $WebhookBridge.status
            test_case_count = if ($WebhookBridge.PSObject.Properties.Name -contains "test_case_count") { [int]$WebhookBridge.test_case_count } else { 0 }
            passed_count = if ($WebhookBridge.PSObject.Properties.Name -contains "passed_count") { [int]$WebhookBridge.passed_count } else { 0 }
            failed_count = if ($WebhookBridge.PSObject.Properties.Name -contains "failed_count") { [int]$WebhookBridge.failed_count } else { 0 }
            dispatch_confirmed_count = if ($WebhookBridge.PSObject.Properties.Name -contains "dispatch_confirmed_count") { [int]$WebhookBridge.dispatch_confirmed_count } else { 0 }
            dispatch_blocked_count = if ($WebhookBridge.PSObject.Properties.Name -contains "dispatch_blocked_count") { [int]$WebhookBridge.dispatch_blocked_count } else { 0 }
            results = if ($WebhookBridge.PSObject.Properties.Name -contains "results") { @($WebhookBridge.results) } else { @() }
        }
    }
}

$GeneratedAt = (Get-Date).ToUniversalTime().ToString("o")
$StackScript = Join-Path $PSScriptRoot "Test-PDAStack.ps1"
$QueueSnapshot = Get-PDAQueueSnapshot -RootPath $Root
$WorkerSnapshot = Get-PDAWorkerSnapshot -RootPath $Root
$ArtifactSnapshot = Get-PDAArtifactSnapshot -RootPath $Root
$MemorySnapshot = Get-PDAMemorySnapshot -RootPath $Root
$MemoryCandidateSummaryScript = Join-Path $PSScriptRoot "Get-PDAMemoryCandidateSummary.ps1"
$CommanderBriefingScript = Join-Path $PSScriptRoot "Get-PDACommanderBriefing.ps1"
$DispatchStatusScript = Join-Path $PSScriptRoot "Get-PDADispatchStatus.ps1"
$MemoryCandidateSnapshot = if (Test-Path -Path $MemoryCandidateSummaryScript -PathType Leaf) {
    try {
        Invoke-PDAJsonScript -Path $MemoryCandidateSummaryScript -Arguments @("-AsJson", "-Latest", "10") -SourceName "PDA memory candidate summary"
    }
    catch {
        [pscustomobject]@{
            status = "error"
            candidate_root = Join-Path $Root "PDA-Memory\candidates"
            memory_index_path = Join-Path $Root "PDA_MemoryIndex.json"
            memory_count = 0
            candidate_count = 0
            pending_approval_count = 0
            promoted_count = 0
            recent_candidates = @()
            recent_memories = @()
            by_source_type = @()
            by_category = @()
            error = $_.Exception.Message
        }
    }
}
else {
    [pscustomobject]@{
        status = "missing"
        candidate_root = Join-Path $Root "PDA-Memory\candidates"
        memory_index_path = Join-Path $Root "PDA_MemoryIndex.json"
        memory_count = [int]$MemorySnapshot.count
        candidate_count = 0
        pending_approval_count = 0
        promoted_count = [int]$MemorySnapshot.count
        recent_candidates = @()
        recent_memories = @()
        by_source_type = @()
        by_category = @()
    }
}
$DispatchSnapshot = if (Test-Path -Path $DispatchStatusScript -PathType Leaf) {
    try {
        Invoke-PDAJsonScript -Path $DispatchStatusScript -Arguments @("-AsJson", "-NoThrow", "-Root", $Root) -SourceName "PDA dispatch status"
    }
    catch {
        [pscustomobject]@{
            status = "error"
            generated_at = $GeneratedAt
            root_path = $Root
            registry = [pscustomobject]@{
                status = "missing"
                registry_path = Join-Path $Root "Scripts\PDA_ExecutorRegistry.json"
                executor_count = 0
                local_only_count = 0
                category2_capable_count = 0
                cloud_capable_count = 0
                requires_approval_count = 0
                executors = @()
            }
            counts = [pscustomobject]@{
                pending_approval = 0
                approved = 0
                prepared = 0
                running = 0
                completed = 0
                failed = 0
            }
            pending_approval = @()
            approved = @()
            prepared = @()
            running = @()
            completed = @()
            failed = @()
            recent_items = @()
            error = $_.Exception.Message
        }
    }
}
else {
    [pscustomobject]@{
        status = "skipped"
        candidate_root = Join-Path $Root "PDA-Memory\candidates"
        memory_index_path = Join-Path $Root "PDA_MemoryIndex.json"
        memory_count = [int]$MemorySnapshot.count
        candidate_count = 0
        pending_approval_count = 0
        promoted_count = [int]$MemorySnapshot.count
        recent_candidates = @()
        recent_memories = @()
        by_source_type = @()
        by_category = @()
    }
}
$ModelSnapshot = Get-PDAModelStatus -RootPath $Root
$FabricHealthScript = Join-Path $PSScriptRoot "Invoke-PDAFabricHealthCheck.ps1"
$CapabilityRouterScript = Join-Path $PSScriptRoot "PDA_CapabilityRouter.ps1"
$CapabilityRouter = if (Test-Path -LiteralPath $CapabilityRouterScript -PathType Leaf) {
    try {
        if (-not (Get-Command -Name Get-PDACapabilityMatrix -ErrorAction SilentlyContinue)) {
            . $CapabilityRouterScript
        }

        Get-PDACapabilityMatrix -Root $Root
    }
    catch {
        [pscustomobject]@{
            status              = "error"
            matrix_path         = $CapabilityRouterScript
            route_count         = 0
            local_only_count    = 0
            cloud_allowed_count = 0
            error               = $_.Exception.Message
        }
    }
}
else {
    [pscustomobject]@{
        status              = "skipped"
        matrix_path         = $CapabilityRouterScript
        route_count         = 0
        local_only_count    = 0
        cloud_allowed_count = 0
    }
}
$FabricHealth = if (Test-Path -Path $FabricHealthScript -PathType Leaf) {
    try {
        Invoke-PDAJsonScript -Path $FabricHealthScript -Arguments @("-AsJson", "-NoThrow") -SourceName "PDA Fabric health check"
    }
    catch {
        [pscustomobject]@{
            status = "error"
            message = $_.Exception.Message
            executable_path = ""
            version = ""
            config_path = ""
            config_exists = $false
            pattern_list_status = "error"
            pattern_count = 0
            available_patterns = @()
            checked_at = (Get-Date).ToUniversalTime().ToString("o")
        }
    }
}
else {
    [pscustomobject]@{
        status = "skipped"
        message = "Fabric health check unavailable."
        executable_path = ""
        version = ""
        config_path = ""
        config_exists = $false
        pattern_list_status = "skipped"
        pattern_count = 0
        available_patterns = @()
        checked_at = (Get-Date).ToUniversalTime().ToString("o")
    }
}
$EnvironmentAwareness = if (Get-Command -Name Get-PDAEnvironmentSummary -ErrorAction SilentlyContinue) {
    try {
        Get-PDAEnvironmentSummary -Root $Root
    }
    catch {
        [pscustomobject]@{
            status = "error"
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            roots = @($Root)
            filesystem = [pscustomobject]@{ status = "error"; roots = @(); project_candidates = @(); archive_candidates = @() }
            repositories = [pscustomobject]@{ status = "error"; repo_count = 0; repositories = @(); active_projects = @(); archived_projects = @() }
            containers = [pscustomobject]@{ status = "error"; containers = @(); running_count = 0; total_count = 0; compose_projects = @() }
            services = [pscustomobject]@{ status = "error"; services = @(); online_count = 0; offline_count = 0 }
            tools = [pscustomobject]@{ status = "error"; tools = @(); available_count = 0 }
            workspace_summary = [pscustomobject]@{ roots = @(); project_count = 0; archive_count = 0 }
            storage_summary = [pscustomobject]@{ roots = @(); top_level_category_count = 0 }
            counts = [pscustomobject]@{ repositories = 0; containers = 0; running_containers = 0; services_online = 0; tools_available = 0 }
            error = $_.Exception.Message
        }
    }
}
else {
    [pscustomobject]@{
        status = "skipped"
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        roots = @($Root)
        filesystem = [pscustomobject]@{ status = "skipped"; roots = @(); project_candidates = @(); archive_candidates = @() }
        repositories = [pscustomobject]@{ status = "skipped"; repo_count = 0; repositories = @(); active_projects = @(); archived_projects = @() }
        containers = [pscustomobject]@{ status = "skipped"; containers = @(); running_count = 0; total_count = 0; compose_projects = @() }
        services = [pscustomobject]@{ status = "skipped"; services = @(); online_count = 0; offline_count = 0 }
        tools = [pscustomobject]@{ status = "skipped"; tools = @(); available_count = 0 }
        workspace_summary = [pscustomobject]@{ roots = @(); project_count = 0; archive_count = 0 }
        storage_summary = [pscustomobject]@{ roots = @(); top_level_category_count = 0 }
        counts = [pscustomobject]@{ repositories = 0; containers = 0; running_containers = 0; services_online = 0; tools_available = 0 }
    }
}
$CommanderSnapshot = if ($SkipCoreIntegration) {
    [pscustomobject]@{
        status = "skipped"
        conversation_state = [pscustomobject]@{}
        task_result = [pscustomobject]@{}
        command_interpreter = [pscustomobject]@{ status = "skipped"; test_case_count = 0; passed_count = 0; failed_count = 0; mapped_count = 0; ambiguous_count = 0; unknown_count = 0; results = @() }
        command_handoff = [pscustomobject]@{ status = "skipped"; test_case_count = 0; passed_count = 0; failed_count = 0; dispatch_confirmed_count = 0; dispatch_blocked_count = 0; results = @() }
        chat_bridge = [pscustomobject]@{ status = "skipped"; test_case_count = 0; passed_count = 0; failed_count = 0; dispatch_confirmed_count = 0; dispatch_blocked_count = 0; results = @() }
        webhook_bridge = [pscustomobject]@{ status = "skipped"; test_case_count = 0; passed_count = 0; failed_count = 0; dispatch_confirmed_count = 0; dispatch_blocked_count = 0; results = @() }
    }
}
else {
    Get-PDACoreIntegrationStatus -RootPath $Root
}
$StackReport = Invoke-PDAJsonScript -Path $StackScript -Arguments @("-Deep", "-AsJson", "-NoThrow") -SourceName "PDA stack validation"

$SystemHealthResults = @()
if ($StackReport -and $StackReport.PSObject.Properties.Name -contains "results") {
    $SystemHealthResults = @($StackReport.results | ForEach-Object {
        [pscustomobject]@{
            name = Get-PDASafeString $_.name
            passed = [bool]$_.passed
            type = Get-PDASafeString $_.type
            url = if ($_.PSObject.Properties.Name -contains "url") { Get-PDASafeString $_.url } else { "" }
            status_code = if ($_.PSObject.Properties.Name -contains "status_code") { $_.status_code } else { $null }
            issues = @($_.issues)
        }
    })
}

$RecentTasks = @(
    $QueueSnapshot.recent_tasks | Select-Object -First 10 | ForEach-Object {
        [pscustomobject]@{
            task_id = Get-PDASafeString $_.task_id
            command = Get-PDASafeString $_.command
            worker = Get-PDASafeString $_.worker_name
            category = Get-PDASafeString $_.category
            queue = Get-PDASafeString $_.queue
            status = Get-PDASafeString $_.status
            updated_at = Get-PDASafeString $_.updated_at
        }
    }
)

$PendingApprovals = @(
    $QueueSnapshot.pending_approvals | Select-Object -First 10 | ForEach-Object {
        [pscustomobject]@{
            task_id = Get-PDASafeString $_.task_id
            command = Get-PDASafeString $_.command
            worker = Get-PDASafeString $_.worker_name
            category = Get-PDASafeString $_.category
            approval_status = Get-PDASafeString $_.approval_status
            queue = Get-PDASafeString $_.queue
            updated_at = Get-PDASafeString $_.updated_at
            file_name = Get-PDASafeString $_.file_name
        }
    }
)

$OverallHealth = "pass"
foreach ($Candidate in @(
    $StackReport.status,
    $ModelSnapshot.status,
    $CommanderSnapshot.status,
    $ModelSnapshot.provider_validation.status,
    $ModelSnapshot.env_validation.status,
    $CapabilityRouter.status,
    $FabricHealth.status,
    $EnvironmentAwareness.status,
    $CommanderSnapshot.command_interpreter.status,
    $CommanderSnapshot.command_handoff.status,
    $CommanderSnapshot.chat_bridge.status,
    $CommanderSnapshot.webhook_bridge.status
)) {
    if ([string]$Candidate -in @("fail", "degraded")) {
        $OverallHealth = "degraded"
        break
    }
    elseif ([string]$Candidate -in @("warn", "partial", "unknown", "missing")) {
        if ($OverallHealth -ne "degraded") {
            $OverallHealth = "warning"
        }
    }
}

$COOPERProfile = Get-COOPERIdentity -Root $Root
$COOPERRuntimeStatus = if (Get-Command -Name Get-COOPERRuntimeStatus -ErrorAction SilentlyContinue) {
    try {
        Get-COOPERRuntimeStatus -Root $Root
    }
    catch {
        $null
    }
}
else {
    $null
}
$COOPERPersonalityFallback = [pscustomobject]@{
    humor_level = 25
    honesty_level = 100
    directness_level = 90
    formality_level = 55
    risk_tolerance = 20
    tars_inspired_not_copyrighted_imitation = $true
    truthfulness = 100
    humor_frequency = 25
    humor_style = @("dry", "deadpan", "military", "operational")
    directness = 90
    formality = 55
    autonomy = 25
    skepticism = 100
    mission_focus = 100
    diplomacy = 65
    humor = 25
    sarcasm = 30
    honesty = 100
    brevity = 55
    initiative = 70
    caution = 90
    persistence = 85
}
$COOPERSystems = [pscustomobject]@{
    docker = Get-PDAServiceHealth -EnvironmentServices $EnvironmentAwareness.services -ServiceName "Docker" -Default (Get-PDAFriendlyHealthLabel -Value $StackReport.status)
    open_webui = Get-PDAServiceHealth -EnvironmentServices $EnvironmentAwareness.services -ServiceName "Open WebUI"
    n8n = Get-PDAServiceHealth -EnvironmentServices $EnvironmentAwareness.services -ServiceName "n8n"
    litellm = Get-PDAServiceHealth -EnvironmentServices $EnvironmentAwareness.services -ServiceName "LiteLLM"
    ollama = Get-PDAServiceHealth -EnvironmentServices $EnvironmentAwareness.services -ServiceName "Ollama"
}
$COOPERHealthValues = @($COOPERSystems.docker, $COOPERSystems.open_webui, $COOPERSystems.n8n, $COOPERSystems.litellm, $COOPERSystems.ollama)
$COOPERStatusLabel = if (@($COOPERHealthValues | Where-Object { [string]$_ -ne "Healthy" }).Count -eq 0) {
    "pass"
}
elseif (@($COOPERHealthValues | Where-Object { [string]$_ -eq "Unhealthy" }).Count -gt 0) {
    "degraded"
}
else {
    "warning"
}

$Report = [pscustomobject]@{
    status = "pass"
    generated_at = $GeneratedAt
    root_path = $Root
    dashboard_path = $DashboardPath
    dashboard_health = [pscustomobject]@{
        status = $OverallHealth
        note = $(if ($OverallHealth -eq "pass") { "All tracked dashboard surfaces are healthy." } elseif ($OverallHealth -eq "warning") { "At least one tracked surface is degraded or unavailable." } else { "One or more critical surfaces failed validation." })
    }
    cooper_status = [pscustomobject]@{
        status = $COOPERStatusLabel
        display_name = $(if ($COOPERRuntimeStatus -and $COOPERRuntimeStatus.PSObject.Properties.Name -contains "assistant_identity") { [string]$COOPERRuntimeStatus.assistant_identity } elseif ($COOPERProfile -and $COOPERProfile.PSObject.Properties.Name -contains "display_name") { [string]$COOPERProfile.display_name } else { "COOPER" })
        official_name = $(if ($COOPERProfile -and $COOPERProfile.PSObject.Properties.Name -contains "official_name") { [string]$COOPERProfile.official_name } else { "Command Operations Orchestrator for Planning, Execution, and Reporting" })
        secondary_expansion = $(if ($COOPERProfile -and $COOPERProfile.PSObject.Properties.Name -contains "secondary_expansion") { [string]$COOPERProfile.secondary_expansion } else { "Collaborative Operational Planning, Execution, and Reasoning" })
        tagline = $(if ($COOPERRuntimeStatus -and $COOPERRuntimeStatus.PSObject.Properties.Name -contains "tagline") { [string]$COOPERRuntimeStatus.tagline } elseif ($COOPERProfile -and $COOPERProfile.PSObject.Properties.Name -contains "tagline") { [string]$COOPERProfile.tagline } else { "Chief Officer of Preventing Everything from Randomly Exploding" })
        identity_note = $(if ($COOPERRuntimeStatus -and $COOPERRuntimeStatus.PSObject.Properties.Name -contains "identity_note") { [string]$COOPERRuntimeStatus.identity_note } elseif ($COOPERProfile -and $COOPERProfile.PSObject.Properties.Name -contains "identity_note") { [string]$COOPERProfile.identity_note } else { "TARS-inspired, not copyrighted imitation" })
        current_model = $(if ($COOPERRuntimeStatus -and $COOPERRuntimeStatus.PSObject.Properties.Name -contains "current_model") { [string]$COOPERRuntimeStatus.current_model } else { "local-llama" })
        provider = $(if ($COOPERRuntimeStatus -and $COOPERRuntimeStatus.PSObject.Properties.Name -contains "provider") { [string]$COOPERRuntimeStatus.provider } else { "Ollama" })
        gateway = $(if ($COOPERRuntimeStatus -and $COOPERRuntimeStatus.PSObject.Properties.Name -contains "gateway") { [string]$COOPERRuntimeStatus.gateway } else { "LiteLLM" })
        interface = $(if ($COOPERRuntimeStatus -and $COOPERRuntimeStatus.PSObject.Properties.Name -contains "interface") { [string]$COOPERRuntimeStatus.interface } else { "Open WebUI" })
        backend = $(if ($COOPERRuntimeStatus -and $COOPERRuntimeStatus.PSObject.Properties.Name -contains "backend") { [string]$COOPERRuntimeStatus.backend } else { "ollama/llama3.2" })
        current_explosions = $(if ($COOPERRuntimeStatus -and $COOPERRuntimeStatus.PSObject.Properties.Name -contains "current_explosions") { [int]$COOPERRuntimeStatus.current_explosions } else { 0 })
        modes = $(if ($COOPERProfile -and $COOPERProfile.PSObject.Properties.Name -contains "operational_modes") { @($COOPERProfile.operational_modes) } else { @("Analyst Mode", "Operator Mode", "TARS Mode", "Overlord Mode", "Emergency Mode") })
        personality = $(if ($COOPERProfile -and $COOPERProfile.PSObject.Properties.Name -contains "personality") { $COOPERProfile.personality } else { $COOPERPersonalityFallback })
        runtime_layers = $(if ($COOPERProfile -and $COOPERProfile.PSObject.Properties.Name -contains "runtime_layers") { $COOPERProfile.runtime_layers } else { $null })
        systems = $COOPERSystems
        summary_lines = @(
            "COOPER Status"
            ("Current Model: {0}" -f $(if ($COOPERRuntimeStatus -and $COOPERRuntimeStatus.PSObject.Properties.Name -contains "current_model") { [string]$COOPERRuntimeStatus.current_model } else { "local-llama" }))
            ("Provider: {0}" -f $(if ($COOPERRuntimeStatus -and $COOPERRuntimeStatus.PSObject.Properties.Name -contains "provider") { [string]$COOPERRuntimeStatus.provider } else { "Ollama" }))
            ("Gateway: {0}" -f $(if ($COOPERRuntimeStatus -and $COOPERRuntimeStatus.PSObject.Properties.Name -contains "gateway") { [string]$COOPERRuntimeStatus.gateway } else { "LiteLLM" }))
            ("Interface: {0}" -f $(if ($COOPERRuntimeStatus -and $COOPERRuntimeStatus.PSObject.Properties.Name -contains "interface") { [string]$COOPERRuntimeStatus.interface } else { "Open WebUI" }))
            $(if ($COOPERProfile -and $COOPERProfile.PSObject.Properties.Name -contains "tagline") { [string]$COOPERProfile.tagline } else { "Chief Officer of Preventing Everything from Randomly Exploding" })
            ("Docker health: {0}" -f $COOPERSystems.docker)
            ("Open WebUI health: {0}" -f $COOPERSystems.open_webui)
            ("n8n health: {0}" -f $COOPERSystems.n8n)
            ("LiteLLM health: {0}" -f $COOPERSystems.litellm)
            "Current Explosions: 0"
        )
        runtime_status = $COOPERRuntimeStatus
    }
    system_health = [pscustomobject]@{
        status = Get-PDASafeString $StackReport.status
        deep_validation_requested = if ($StackReport.PSObject.Properties.Name -contains "deep_validation_requested") { [bool]$StackReport.deep_validation_requested } else { $false }
        service_check_count = if ($StackReport.PSObject.Properties.Name -contains "service_check_count") { [int]$StackReport.service_check_count } else { 0 }
        total_check_count = if ($StackReport.PSObject.Properties.Name -contains "total_check_count") { [int]$StackReport.total_check_count } else { 0 }
        passed_count = if ($StackReport.PSObject.Properties.Name -contains "passed_count") { [int]$StackReport.passed_count } else { 0 }
        failed_count = if ($StackReport.PSObject.Properties.Name -contains "failed_count") { [int]$StackReport.failed_count } else { 0 }
        results = @($SystemHealthResults)
        raw = if ($StackReport) { $StackReport } else { $null }
    }
    queue_status = [pscustomobject]@{
        counts = $QueueSnapshot.counts
        queue_depth = [int]$QueueSnapshot.queue_depth
        latest = $QueueSnapshot.latest
        recent_tasks = @($RecentTasks)
    }
    worker_status = [pscustomobject]@{
        registry = $WorkerSnapshot.registry
        runtime_states = @($WorkerSnapshot.runtime_states)
        heartbeats = @($WorkerSnapshot.heartbeats)
    }
    pending_approvals = @($PendingApprovals)
    recent_tasks = @($RecentTasks)
    recent_artifacts = @($ArtifactSnapshot.recent)
    model_status = [pscustomobject]@{
        status = Get-PDASafeString $ModelSnapshot.status
        routing_policy = $ModelSnapshot.routing_policy
        provider_validation = $ModelSnapshot.provider_validation
        env_validation = $ModelSnapshot.env_validation
    }
    capability_router = [pscustomobject]@{
        status = Get-PDASafeString $CapabilityRouter.status
        matrix_path = Get-PDASafeString $CapabilityRouter.matrix_path
        route_count = if ($CapabilityRouter.PSObject.Properties.Name -contains "route_count") { [int]$CapabilityRouter.route_count } else { 0 }
        local_only_count = if ($CapabilityRouter.PSObject.Properties.Name -contains "local_only_count") { [int]$CapabilityRouter.local_only_count } else { 0 }
        cloud_allowed_count = if ($CapabilityRouter.PSObject.Properties.Name -contains "cloud_allowed_count") { [int]$CapabilityRouter.cloud_allowed_count } else { 0 }
    }
    fabric_status = $FabricHealth
    commander_integration = [pscustomobject]@{
        status = Get-PDASafeString $CommanderSnapshot.status
        conversation_state = $CommanderSnapshot.conversation_state
        task_result = $CommanderSnapshot.task_result
        command_interpreter = $CommanderSnapshot.command_interpreter
    command_handoff = $CommanderSnapshot.command_handoff
    chat_bridge = $CommanderSnapshot.chat_bridge
    webhook_bridge = $CommanderSnapshot.webhook_bridge
    dispatch_status = $DispatchSnapshot
    }
    commander_briefing = $null
    commander_planning = $null
    commander_plan_orchestration = $null
    commander_agent_loop = $null
    approval_workflow = $null
    execution_requests = $null
    environment_awareness = $EnvironmentAwareness
    dispatch_status = $DispatchSnapshot
    memory_summary = [pscustomobject]@{
        status = Get-PDASafeString $MemorySnapshot.status
        count = [int]$MemorySnapshot.count
        updated_at = Get-PDASafeString $MemorySnapshot.updated_at
        candidate_summary = $MemoryCandidateSnapshot
        candidate_count = if ($MemoryCandidateSnapshot.PSObject.Properties.Name -contains "candidate_count") { [int]$MemoryCandidateSnapshot.candidate_count } else { 0 }
        pending_approval_count = if ($MemoryCandidateSnapshot.PSObject.Properties.Name -contains "pending_approval_count") { [int]$MemoryCandidateSnapshot.pending_approval_count } else { 0 }
        promoted_count = if ($MemoryCandidateSnapshot.PSObject.Properties.Name -contains "promoted_count") { [int]$MemoryCandidateSnapshot.promoted_count } else { [int]$MemorySnapshot.count }
        by_type = @($MemorySnapshot.by_type)
        by_category = @($MemorySnapshot.by_category)
        recent = @($MemorySnapshot.recent)
        recent_candidates = if ($MemoryCandidateSnapshot.PSObject.Properties.Name -contains "recent_candidates") { @($MemoryCandidateSnapshot.recent_candidates) } else { @() }
    }
    artifacts_summary = [pscustomobject]@{
        status = Get-PDASafeString $ArtifactSnapshot.status
        count = [int]$ArtifactSnapshot.count
        updated_at = Get-PDASafeString $ArtifactSnapshot.updated_at
        by_worker = @($ArtifactSnapshot.by_worker)
        recent = @($ArtifactSnapshot.recent)
    }
}

if (-not $SkipCommanderBriefing -and (Test-Path -LiteralPath $CommanderBriefingScript -PathType Leaf)) {
    try {
        $CommanderBriefingRaw = & pwsh -NoProfile -File $CommanderBriefingScript -DashboardStatus $Report -Root $Root -AsJson 2>&1
        $CommanderBriefingText = [string]($CommanderBriefingRaw -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($CommanderBriefingText)) {
            throw "Commander briefing returned empty output."
        }
        $Report.commander_briefing = ConvertFrom-PDAMixedJson -Text $CommanderBriefingText -SourceName $CommanderBriefingScript
    }
    catch {
        $Report.commander_briefing = [pscustomobject]@{
                status = "error"
                generated_at = $GeneratedAt
                focus = "default"
                dashboard_health = $OverallHealth
                error = $_.Exception.Message
                queue = [pscustomobject]@{
                    pending = [int]$QueueSnapshot.counts.pending
                    running = [int]$QueueSnapshot.counts.running
                    failed = [int]$QueueSnapshot.counts.failed
                    completed = [int]$QueueSnapshot.counts.completed
                    results = [int]$QueueSnapshot.counts.results
                    depth = [int]$QueueSnapshot.queue_depth
                }
                memory = [pscustomobject]@{
                    candidates_pending_approval = if ($MemoryCandidateSnapshot.PSObject.Properties.Name -contains "pending_approval_count") { [int]$MemoryCandidateSnapshot.pending_approval_count } else { 0 }
                    candidate_count = if ($MemoryCandidateSnapshot.PSObject.Properties.Name -contains "candidate_count") { [int]$MemoryCandidateSnapshot.candidate_count } else { 0 }
                    promoted_count = if ($MemoryCandidateSnapshot.PSObject.Properties.Name -contains "promoted_count") { [int]$MemoryCandidateSnapshot.promoted_count } else { [int]$MemorySnapshot.count }
                    memory_count = [int]$MemorySnapshot.count
                }
                recent_activity = [pscustomobject]@{
                    completed_tasks = @($RecentTasks)
                    promoted_memories = @($MemorySnapshot.recent)
                }
                blocked_items = @()
                recommended_actions = @()
                next_action = ""
                recommended_executor = ""
                briefing_text = ""
            }
        }
    }

    $AgentLoopScript = Join-Path $PSScriptRoot "Get-PDAAgentRun.ps1"
    if (Test-Path -LiteralPath $AgentLoopScript -PathType Leaf) {
        try {
            $Report.commander_agent_loop = Get-PDAAgentLoopSnapshot -RootPath $Root
        }
        catch {
            $Report.commander_agent_loop = [pscustomobject]@{
                path = Join-Path $Root "PDA-Agent-Runs"
                index_path = Join-Path $Root "PDA-Agent-Runs\index.json"
                status = "error"
                run_count = 0
                active_run_count = 0
                pending_approval_count = 0
                blocked_count = 0
                completed_count = 0
                latest_run = $null
                recent_runs = @()
                runs = @()
                error = $_.Exception.Message
            }
        }
    }

    $ApprovalWorkflowScriptPath = Join-Path $PSScriptRoot "Get-PDAApprovalWorkflowStatus.ps1"
    if (Get-Command -Name Get-PDAApprovalWorkflowStatus -ErrorAction SilentlyContinue -or (Test-Path -LiteralPath $ApprovalWorkflowScriptPath -PathType Leaf)) {
        try {
            if (-not (Get-Command -Name Get-PDAApprovalWorkflowStatus -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $ApprovalWorkflowScriptPath -PathType Leaf)) {
                . $ApprovalWorkflowScriptPath
            }
    if (Get-Command -Name Get-PDAApprovalWorkflowStatus -ErrorAction SilentlyContinue) {
                $Report.approval_workflow = Get-PDAApprovalWorkflowStatus -Root $Root -Latest 10
            }
        }
        catch {
            $Report.approval_workflow = [pscustomobject]@{
                status = "error"
                generated_at = (Get-Date).ToUniversalTime().ToString("o")
                root_path = $Root
                store_path = Join-Path $Root "PDA-Runtime\data\approval-workflows\index.json"
                index_path = Join-Path $Root "PDA-Runtime\data\approval-workflows\index.json"
                counts = [pscustomobject]@{
                    pending_approval = 0
                    approved = 0
                    rejected = 0
                    revision_requested = 0
                    replan_requested = 0
                    escalated = 0
                    cancelled = 0
                    completed = 0
                    blocked_agent_runs = 0
                    pending_agent_runs = 0
                }
                approval_count = 0
                pending_approval_count = 0
                blocked_count = 0
                recent_approvals = @()
                recent_pending = @()
                error = $_.Exception.Message
            }
        }
    }

    if (Test-Path -LiteralPath $ExecutionRequestScript -PathType Leaf) {
        try {
            $ExecutionRequestRaw = & pwsh -NoProfile -File $ExecutionRequestScript -Root $Root -AsJson -NoThrow 2>&1
            $ExecutionRequestText = [string]($ExecutionRequestRaw -join "`n").Trim()
            if (-not [string]::IsNullOrWhiteSpace($ExecutionRequestText)) {
                $Report.execution_requests = ConvertFrom-PDAMixedJson -Text $ExecutionRequestText -SourceName $ExecutionRequestScript
            }
        }
        catch {
            $Report.execution_requests = [pscustomobject]@{
                status = "error"
                error = $_.Exception.Message
                generated_at = (Get-Date).ToUniversalTime().ToString("o")
                root_path = $Root
                store_path = Join-Path $Root "PDA-Runtime\data\execution-requests"
                index_path = Join-Path $Root "PDA-Runtime\data\execution-requests\index.json"
                request_count = 0
                draft_count = 0
                pending_approval_count = 0
                approved_count = 0
                rejected_count = 0
                cancelled_count = 0
                completed_count = 0
                approval_required_count = 0
                restricted_local_only_count = 0
                recent_requests = @()
                recent_pending_requests = @()
                recent_approved_requests = @()
            }
        }
    }

    $CommanderPlanningStorePath = Join-Path $Root "PDA-Runtime\data\commander-goals.json"
    if (Test-Path -LiteralPath $CommanderPlanningStorePath -PathType Leaf) {
        try {
            $CommanderPlanningStore = Get-Content -LiteralPath $CommanderPlanningStorePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $CommanderPlans = @($CommanderPlanningStore.plans)
            $RecentGoals = @(
                $CommanderPlans |
                    Select-Object -First 5 |
                    ForEach-Object {
                        [pscustomobject]@{
                            plan_id = [string]$_.plan_id
                            goal = [string]$_.goal
                            goal_type = [string]$_.goal_type
                            category = [string]$_.category
                            complexity = [string]$_.complexity
                            approval_required = [bool]$_.approval_required
                            status = [string]$_.status
                            created_at = [string]$_.created_at
                        }
                    }
            )
            $PendingPlans = @($CommanderPlans | Where-Object { [string]$_.status -in @("pending_review", "pending_approval", "planned") } | Select-Object -First 5)
            $ExecutorChains = @(
                $CommanderPlans |
                    Select-Object -First 5 |
                    ForEach-Object {
                        [pscustomobject]@{
                            plan_id = [string]$_.plan_id
                            goal = [string]$_.goal
                            recommended_executors = @($_.recommended_executor_chain | ForEach-Object { $_.executor })
                        }
                    }
            )
            $PlannedDeliverables = @(
                $CommanderPlans |
                    Select-Object -First 5 |
                    ForEach-Object {
                        [pscustomobject]@{
                            plan_id = [string]$_.plan_id
                            goal = [string]$_.goal
                            deliverables = @($_.deliverables)
                        }
                    }
            )

            $Report.commander_planning = [pscustomobject]@{
                status = $(if (@($CommanderPlans).Count -gt 0) { "pass" } else { "empty" })
                store_path = $CommanderPlanningStorePath
                plan_count = [int]@($CommanderPlans).Count
                pending_plan_count = [int]@($PendingPlans).Count
                recent_goals = @($RecentGoals)
                pending_plans = @($PendingPlans)
                recommended_executor_chains = @($ExecutorChains)
                planned_deliverables = @($PlannedDeliverables)
                latest_goal = if ($RecentGoals.Count -gt 0) { $RecentGoals[0] } else { $null }
            }
        }
        catch {
            $Report.commander_planning = [pscustomobject]@{
                status = "error"
                store_path = $CommanderPlanningStorePath
                plan_count = 0
                pending_plan_count = 0
                recent_goals = @()
                pending_plans = @()
                recommended_executor_chains = @()
                planned_deliverables = @()
                latest_goal = $null
                error = $_.Exception.Message
            }
        }
    }

    $CommanderPlanOrchestrationScript = Join-Path $PSScriptRoot "Get-PDAPlanStatus.ps1"
    if (Test-Path -LiteralPath $CommanderPlanOrchestrationScript -PathType Leaf) {
        try {
            $CommanderPlanOrchestrationRaw = & pwsh -NoProfile -File $CommanderPlanOrchestrationScript -Root $Root -AsJson -NoThrow 2>&1
            $CommanderPlanOrchestrationText = [string]($CommanderPlanOrchestrationRaw -join "`n").Trim()
            if (-not [string]::IsNullOrWhiteSpace($CommanderPlanOrchestrationText)) {
                $Report.commander_plan_orchestration = ConvertFrom-PDAMixedJson -Text $CommanderPlanOrchestrationText -SourceName $CommanderPlanOrchestrationScript
            }
        }
        catch {
            $Report.commander_plan_orchestration = [pscustomobject]@{
                status = "error"
                error = $_.Exception.Message
                counts = [pscustomobject]@{
                    total = 0
                    pending = 0
                    approved = 0
                    running = 0
                    completed = 0
                    failed = 0
                    waiting_approval = 0
                    blocked = 0
                }
                plans = @()
                pending_approvals = @()
                running_plans = @()
                blocked_plans = @()
                completed_plans = @()
                failed_plans = @()
                recent_deliverables = @()
            }
        }
    }
if ($AsJson) {
    $Report | ConvertTo-Json -Depth 30
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA dashboard status collection failed."
    }
    return
}

Write-Host "[PDA DASHBOARD STATUS]"
Write-Host ("Generated at    : {0}" -f $Report.generated_at)
Write-Host ("Dashboard path  : {0}" -f $Report.dashboard_path)
Write-Host ("Overall health   : {0}" -f $Report.dashboard_health.status)
Write-Host ("Queue depth      : {0}" -f $Report.queue_status.queue_depth)
Write-Host ("Pending approvals: {0}" -f @($Report.pending_approvals).Count)
Write-Host ("Recent tasks     : {0}" -f @($Report.recent_tasks).Count)
Write-Host ("Recent artifacts : {0}" -f @($Report.recent_artifacts).Count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA dashboard status collection failed."
}
