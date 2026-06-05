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

$RoutingSummaryScript = Join-Path $PSScriptRoot "Get-PDARoutingSummary.ps1"
$AIECCommandsScript = Join-Path $PSScriptRoot "AIEcosystem.Commands.ps1"
$MemoryIndexPath = Join-Path $ResolvedRoot "PDA_MemoryIndex.json"
$ArtifactIndexPath = Join-Path $ResolvedRoot "PDA_ArtifactIndex.json"
$TaskRoot = Join-Path $ResolvedRoot "PDA-Tasks"

function Get-PDAJsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$CollectionProperty
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            exists = $false
            path = $Path
            data = $null
            items = @()
        }
    }

    $Raw = Get-Content -LiteralPath $Path -Raw
    $Parsed = $Raw | ConvertFrom-Json -ErrorAction Stop
    $Items = @()
    if ($Parsed.PSObject.Properties.Name -contains $CollectionProperty -and $Parsed.$CollectionProperty) {
        $Items = @($Parsed.$CollectionProperty)
    }

    return [pscustomobject]@{
        exists = $true
        path = $Path
        data = $Parsed
        items = $Items
    }
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

    if ($null -eq $Rows -or $Rows.Count -eq 0) {
        return ($Lines.ToArray() -join "`r`n")
    }

    foreach ($Row in $Rows) {
        $Values = foreach ($Column in $Columns) {
            $Value = $Row.$Column
            if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
                ""
            }
            else {
                ([string]$Value).Replace("|", "\|")
            }
        }

        $Lines.Add("| " + ($Values -join " | ") + " |")
    }

    return ($Lines.ToArray() -join "`r`n")
}

function Get-PDACountRows {
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$Items,

        [Parameter(Mandatory = $true)]
        [scriptblock]$KeySelector
    )

    $Counts = @{}
    foreach ($Item in @($Items)) {
        $Key = & $KeySelector $Item
        if ([string]::IsNullOrWhiteSpace([string]$Key)) {
            $Key = "(empty)"
        }

        if (-not $Counts.ContainsKey([string]$Key)) {
            $Counts[[string]$Key] = 0
        }

        $Counts[[string]$Key]++
    }

    return @($Counts.GetEnumerator() | Sort-Object @{ Expression = "Value"; Descending = $true }, @{ Expression = "Key"; Descending = $false } | ForEach-Object {
        [pscustomobject]@{
            name = [string]$_.Key
            count = [int]$_.Value
        }
    })
}

function Get-PDATaskQueueSummary {
    param([Parameter(Mandatory = $true)][string]$TaskRootPath)

    $QueueFolders = [ordered]@{
        pending = Join-Path $TaskRootPath "pending"
        running = Join-Path $TaskRootPath "running"
        completed = Join-Path $TaskRootPath "completed"
        failed = Join-Path $TaskRootPath "failed"
        results = Join-Path $TaskRootPath "results"
    }

    $Counts = [ordered]@{}
    $RecentTasks = @()
    foreach ($QueueName in $QueueFolders.Keys) {
        $Folder = $QueueFolders[$QueueName]
        $Files = if (Test-Path -LiteralPath $Folder -PathType Container) {
            @(Get-ChildItem -LiteralPath $Folder -Filter *.json -File -ErrorAction SilentlyContinue)
        }
        else {
            @()
        }

        $Counts[$QueueName] = $Files.Count

        foreach ($File in $Files) {
            $TaskId = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
            $Command = ""
            $Worker = ""
            $Category = ""
            $TaskStatus = $QueueName

            try {
                $Parsed = Get-Content -LiteralPath $File.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
                if ($Parsed.PSObject.Properties.Name -contains "task_id" -and $Parsed.task_id) {
                    $TaskId = [string]$Parsed.task_id
                }
                if ($Parsed.PSObject.Properties.Name -contains "command") {
                    $Command = [string]$Parsed.command
                }
                if ($Parsed.PSObject.Properties.Name -contains "worker_name") {
                    $Worker = [string]$Parsed.worker_name
                }
                elseif ($Parsed.PSObject.Properties.Name -contains "worker") {
                    $Worker = [string]$Parsed.worker
                }
                if ($Parsed.PSObject.Properties.Name -contains "category") {
                    $Category = [string]$Parsed.category
                }
                if ($Parsed.PSObject.Properties.Name -contains "task_status" -and $Parsed.task_status) {
                    $TaskStatus = [string]$Parsed.task_status
                }
                elseif ($Parsed.PSObject.Properties.Name -contains "status" -and $Parsed.status) {
                    $TaskStatus = [string]$Parsed.status
                }
            }
            catch {}

            $RecentTasks += [pscustomobject]@{
                task_id = $TaskId
                command = $Command
                worker = $Worker
                category = $Category
                queue = $QueueName
                status = $TaskStatus
                updated_at = $File.LastWriteTime.ToString("s")
                sort_time = $File.LastWriteTime
                path = $File.FullName
            }
        }
    }

    return [pscustomobject]@{
        counts = [pscustomobject]$Counts
        queue_depth = ([int]$Counts.pending + [int]$Counts.running)
        recent_tasks = @($RecentTasks | Sort-Object sort_time -Descending | Select-Object -First 10)
        dispatches_by_queue = @(
            $Counts.GetEnumerator() | ForEach-Object {
                [pscustomobject]@{
                    name = [string]$_.Key
                    count = [int]$_.Value
                }
            }
        )
    }
}

function Get-PDAServiceStatusText {
    param([Parameter(Mandatory = $true)][string]$RepoRootPath)

    if (-not (Test-Path -LiteralPath $AIECCommandsScript -PathType Leaf)) {
        return "[WARN] AIEcosystem.Commands.ps1 not found."
    }

    $EscapedScript = $AIECCommandsScript.Replace("'", "''")
    $EscapedRoot = $RepoRootPath.Replace("'", "''")
    $Command = ". '$EscapedScript'; Invoke-AIECStatus -RepoRoot '$EscapedRoot'"
    $Output = & pwsh -NoProfile -Command $Command 2>&1
    return [string]($Output -join "`r`n").Trim()
}

function Get-PDARoutingSummaryData {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRootPath
    )

    if (-not (Test-Path -LiteralPath $RoutingSummaryScript -PathType Leaf)) {
        throw "Routing summary script missing: $RoutingSummaryScript"
    }

    $RoutingLogPath = Join-Path $RepoRootPath "PDA-Logs\routing"
    $Raw = & pwsh -NoProfile -File $RoutingSummaryScript -LogPath $RoutingLogPath -AsJson -NoThrow 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Routing summary returned empty output."
    }

    return $Text | ConvertFrom-Json
}

function Write-PDAMarkdownFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $false)][object[]]$Lines
    )

    $Directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    function Expand-PDALineValues {
        param([Parameter(Mandatory = $false)]$Value)

        if ($null -eq $Value) {
            return @("")
        }

        if ($Value -is [string]) {
            return @([string]$Value)
        }

        if ($Value -is [System.Collections.IEnumerable]) {
            $Expanded = @()
            foreach ($Entry in $Value) {
                $Expanded += @(Expand-PDALineValues -Value $Entry)
            }
            return $Expanded
        }

        return @([string]$Value)
    }

    $TextLines = @(Expand-PDALineValues -Value $Lines)
    ($TextLines -join "`r`n") | Set-Content -Path $Path -Encoding UTF8
}

$RoutingSummary = Get-PDARoutingSummaryData -RepoRootPath $ResolvedRoot
$TaskSummary = Get-PDATaskQueueSummary -TaskRootPath $TaskRoot
$MemoryIndex = Get-PDAJsonFile -Path $MemoryIndexPath -CollectionProperty "memories"
$ArtifactIndex = Get-PDAJsonFile -Path $ArtifactIndexPath -CollectionProperty "artifacts"
$ServiceStatusText = Get-PDAServiceStatusText -RepoRootPath $ResolvedRoot

$RecentArtifacts = @($ArtifactIndex.items | Sort-Object @{ Expression = { Get-PDADateValue $_.created_at } } -Descending | Select-Object -First 10 | ForEach-Object {
    [pscustomobject]@{
        artifact_id = [string]$_.artifact_id
        created_at = [string]$_.created_at
        worker_name = [string]$_.worker_name
        category = [string]$_.category
        artifact_type = [string]$_.artifact_type
        summary = [string]$_.summary
    }
})

$RecentMemories = @($MemoryIndex.items | Sort-Object @{ Expression = { Get-PDADateValue $_.created_at } } -Descending | Select-Object -First 10 | ForEach-Object {
    [pscustomobject]@{
        memory_id = [string]$_.memory_id
        created_at = [string]$_.created_at
        memory_type = [string]$_.memory_type
        category = [string]$_.category
        title = [string]$_.title
        summary = [string]$_.summary
    }
})

$ArtifactByWorker = Get-PDACountRows -Items $ArtifactIndex.items -KeySelector { param($Item) $Item.worker_name }
$MemoryByCategory = Get-PDACountRows -Items $MemoryIndex.items -KeySelector { param($Item) $Item.category }
$GeneratedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

$OperatorConsolePath = Join-Path $ResolvedOutputDirectory "PDA Operator Console.md"
$RoutingSummaryPath = Join-Path $ResolvedOutputDirectory "Routing Summary.md"
$SystemStatusPath = Join-Path $ResolvedOutputDirectory "System Status.md"
$TaskSummaryPath = Join-Path $ResolvedOutputDirectory "Task Summary.md"

$OperatorConsoleLines = @(
    "# PDA Operator Console",
    "",
    "Updated: $GeneratedAt",
    "",
    "## Dashboard Index",
    "",
    "- [[System Status]]",
    "- [[Routing Summary]]",
    "- [[Task Summary]]",
    "",
    "## Snapshot",
    "",
    '- Service health source: `aiec-status`',
    "- Routing records: $($RoutingSummary.valid_records)",
    "- Dispatch success rate: $($RoutingSummary.success_rate)%",
    "- Queue depth: $($TaskSummary.queue_depth)",
    "- Memory records: $($MemoryIndex.items.Count)",
    "- Artifact records: $($ArtifactIndex.items.Count)",
    "",
    "## Key Metrics",
    ""
)
$OperatorConsoleLines += @(ConvertTo-PDAMarkdownTable -Rows @(
    [pscustomobject]@{ metric = "Cloud usage"; value = [string]$RoutingSummary.cloud_usage_count }
    [pscustomobject]@{ metric = "Local usage"; value = [string]$RoutingSummary.local_usage_count }
    [pscustomobject]@{ metric = "Fallback used"; value = [string]$RoutingSummary.fallback_usage_count }
    [pscustomobject]@{ metric = "Pending tasks"; value = [string]$TaskSummary.counts.pending }
    [pscustomobject]@{ metric = "Running tasks"; value = [string]$TaskSummary.counts.running }
    [pscustomobject]@{ metric = "Recent artifacts"; value = [string]$RecentArtifacts.Count }
) -Columns @("metric", "value"))
$OperatorConsoleLines += @(
    "",
    "## Recent Tasks",
    ""
)
if ($TaskSummary.recent_tasks.Count -gt 0) {
    $OperatorConsoleLines += @(ConvertTo-PDAMarkdownTable -Rows $TaskSummary.recent_tasks -Columns @("task_id", "command", "worker", "category", "queue", "status", "updated_at"))
}
else {
    $OperatorConsoleLines += "- No task files found."
}
$OperatorConsoleLines += @(
    "",
    "## Recent Artifacts",
    ""
)
if ($RecentArtifacts.Count -gt 0) {
    $OperatorConsoleLines += @(ConvertTo-PDAMarkdownTable -Rows $RecentArtifacts -Columns @("artifact_id", "created_at", "worker_name", "category", "artifact_type"))
}
else {
    $OperatorConsoleLines += "- No artifact records found."
}

$RoutingSummaryLines = @(
    "# Routing Summary",
    "",
    "Updated: $GeneratedAt",
    "",
    "## Summary",
    ""
)
$RoutingSummaryLines += @(ConvertTo-PDAMarkdownTable -Rows @(
    [pscustomobject]@{ metric = "Valid records"; value = [string]$RoutingSummary.valid_records }
    [pscustomobject]@{ metric = "Success count"; value = [string]$RoutingSummary.success_count }
    [pscustomobject]@{ metric = "Failure count"; value = [string]$RoutingSummary.failure_count }
    [pscustomobject]@{ metric = "Success rate"; value = ("{0}%" -f $RoutingSummary.success_rate) }
    [pscustomobject]@{ metric = "Fallback usage count"; value = [string]$RoutingSummary.fallback_usage_count }
    [pscustomobject]@{ metric = "Category 1 volume"; value = [string]$RoutingSummary.category_1_volume }
    [pscustomobject]@{ metric = "Category 2 volume"; value = [string]$RoutingSummary.category_2_volume }
    [pscustomobject]@{ metric = "Cloud usage"; value = [string]$RoutingSummary.cloud_usage_count }
    [pscustomobject]@{ metric = "Local usage"; value = [string]$RoutingSummary.local_usage_count }
) -Columns @("metric", "value"))
$RoutingSummaryLines += @("", "## Dispatches By Command", "")
if ($RoutingSummary.dispatches_by_command.Count -gt 0) {
    $RoutingSummaryLines += @(ConvertTo-PDAMarkdownTable -Rows $RoutingSummary.dispatches_by_command -Columns @("name", "count"))
}
else {
    $RoutingSummaryLines += "- No routing records found."
}
$RoutingSummaryLines += @("", "## Dispatches By Model", "")
if ($RoutingSummary.dispatches_by_model.Count -gt 0) {
    $RoutingSummaryLines += @(ConvertTo-PDAMarkdownTable -Rows $RoutingSummary.dispatches_by_model -Columns @("name", "count"))
}
else {
    $RoutingSummaryLines += "- No model usage data found."
}
$RoutingSummaryLines += @("", "## Dispatches By Worker", "")
if ($RoutingSummary.dispatches_by_worker.Count -gt 0) {
    $RoutingSummaryLines += @(ConvertTo-PDAMarkdownTable -Rows $RoutingSummary.dispatches_by_worker -Columns @("name", "count"))
}
else {
    $RoutingSummaryLines += "- No worker usage data found."
}
$RoutingSummaryLines += @("", "## Top Routing Reasons", "")
if ($RoutingSummary.top_routing_reasons.Count -gt 0) {
    $RoutingSummaryLines += @(ConvertTo-PDAMarkdownTable -Rows $RoutingSummary.top_routing_reasons -Columns @("name", "count"))
}
else {
    $RoutingSummaryLines += "- No routing reasons found."
}

$SystemStatusLines = @(
    "# System Status",
    "",
    "Updated: $GeneratedAt",
    "",
    "## AI Ecosystem Status",
    "",
    '```text',
    $ServiceStatusText,
    '```',
    "",
    "## Data Stores",
    ""
)
$SystemStatusLines += @(ConvertTo-PDAMarkdownTable -Rows @(
    [pscustomobject]@{ store = "PDA_MemoryIndex.json"; exists = [string]$MemoryIndex.exists; count = [string]$MemoryIndex.items.Count }
    [pscustomobject]@{ store = "PDA_ArtifactIndex.json"; exists = [string]$ArtifactIndex.exists; count = [string]$ArtifactIndex.items.Count }
    [pscustomobject]@{ store = "Routing logs"; exists = [string](Test-Path -LiteralPath (Join-Path $ResolvedRoot "PDA-Logs\routing") -PathType Container); count = [string]$RoutingSummary.valid_records }
    [pscustomobject]@{ store = "Task queue"; exists = [string](Test-Path -LiteralPath $TaskRoot -PathType Container); count = [string]$TaskSummary.queue_depth }
) -Columns @("store", "exists", "count"))
$SystemStatusLines += @("", "## Memory By Category", "")
if ($MemoryByCategory.Count -gt 0) {
    $SystemStatusLines += @(ConvertTo-PDAMarkdownTable -Rows $MemoryByCategory -Columns @("name", "count"))
}
else {
    $SystemStatusLines += "- No memory records found."
}
$SystemStatusLines += @("", "## Artifacts By Worker", "")
if ($ArtifactByWorker.Count -gt 0) {
    $SystemStatusLines += @(ConvertTo-PDAMarkdownTable -Rows $ArtifactByWorker -Columns @("name", "count"))
}
else {
    $SystemStatusLines += "- No artifact records found."
}

$TaskSummaryLines = @(
    "# Task Summary",
    "",
    "Updated: $GeneratedAt",
    "",
    "## Queue Metrics",
    ""
)
$TaskSummaryLines += @(ConvertTo-PDAMarkdownTable -Rows @(
    [pscustomobject]@{ metric = "Queue depth"; value = [string]$TaskSummary.queue_depth }
    [pscustomobject]@{ metric = "Pending"; value = [string]$TaskSummary.counts.pending }
    [pscustomobject]@{ metric = "Running"; value = [string]$TaskSummary.counts.running }
    [pscustomobject]@{ metric = "Completed"; value = [string]$TaskSummary.counts.completed }
    [pscustomobject]@{ metric = "Failed"; value = [string]$TaskSummary.counts.failed }
    [pscustomobject]@{ metric = "Results"; value = [string]$TaskSummary.counts.results }
) -Columns @("metric", "value"))
$TaskSummaryLines += @("", "## Recent Tasks", "")
if ($TaskSummary.recent_tasks.Count -gt 0) {
    $TaskSummaryLines += @(ConvertTo-PDAMarkdownTable -Rows $TaskSummary.recent_tasks -Columns @("task_id", "command", "worker", "category", "queue", "status", "updated_at"))
}
else {
    $TaskSummaryLines += "- No task records found."
}
$TaskSummaryLines += @("", "## Recent Memory Records", "")
if ($RecentMemories.Count -gt 0) {
    $TaskSummaryLines += @(ConvertTo-PDAMarkdownTable -Rows $RecentMemories -Columns @("memory_id", "created_at", "memory_type", "category", "title"))
}
else {
    $TaskSummaryLines += "- No memory records found."
}
$TaskSummaryLines += @("", "## Recent Artifacts", "")
if ($RecentArtifacts.Count -gt 0) {
    $TaskSummaryLines += @(ConvertTo-PDAMarkdownTable -Rows $RecentArtifacts -Columns @("artifact_id", "created_at", "worker_name", "category", "artifact_type"))
}
else {
    $TaskSummaryLines += "- No artifact records found."
}

Write-PDAMarkdownFile -Path $OperatorConsolePath -Lines $OperatorConsoleLines
Write-PDAMarkdownFile -Path $RoutingSummaryPath -Lines $RoutingSummaryLines
Write-PDAMarkdownFile -Path $SystemStatusPath -Lines $SystemStatusLines
Write-PDAMarkdownFile -Path $TaskSummaryPath -Lines $TaskSummaryLines

$Result = [pscustomobject]@{
    status = "pass"
    root_path = $ResolvedRoot
    output_directory = $ResolvedOutputDirectory
    generated_at = $GeneratedAt
    outputs = @(
        $OperatorConsolePath,
        $RoutingSummaryPath,
        $SystemStatusPath,
        $TaskSummaryPath
    )
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 10
    if (-not $NoThrow -and $Result.status -ne "pass") {
        throw "PDA dashboard refresh failed."
    }
    return
}

Write-Host "[OK] PDA dashboard files updated:"
foreach ($Path in $Result.outputs) {
    Write-Host $Path
}
