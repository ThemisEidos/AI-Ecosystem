param(
    [string]$StagingRoot = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Tasks\staging\n8n-router"
)

$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"
$QueueRoot = Join-Path $Root "PDA-Tasks"
$CategoryRoutingScript = Join-Path $Root "Scripts\PDA_CategoryRouting.ps1"
$PendingRoot = Join-Path $QueueRoot "pending"
$ProcessedRoot = Join-Path $QueueRoot "staging\processed"
$FailedRoot = Join-Path $QueueRoot "staging\failed"
$LogRoot = Join-Path $Root "PDA-Logs"

# Deprecated legacy queue paths are intentionally not used.
# This intake path stages planner/research/review/execute commands into canonical PDA-Tasks.

New-Item -ItemType Directory -Force -Path $StagingRoot, $PendingRoot, $ProcessedRoot, $FailedRoot, $LogRoot | Out-Null

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogFile = Join-Path $LogRoot "$Timestamp-router-staged-intake.log"

function Write-Log {
    param([string]$Message)
    $Line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $Line | Add-Content -Path $LogFile -Encoding UTF8
    Write-Host $Line
}

function Resolve-SourcePath {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $Candidates = @($Value)
    if (-not [System.IO.Path]::IsPathRooted($Value)) {
        $Candidates += (Join-Path $Root $Value)
    }

    foreach ($Candidate in $Candidates) {
        if (Test-Path $Candidate) {
            return (Resolve-Path $Candidate).Path
        }
    }

    return ""
}

function New-MessageOnlySourceFile {
    param(
        [string]$Route,
        [string]$TaskId,
        [string]$Message
    )

    $GeneratedRoot = Join-Path $QueueRoot "staging\generated\message-only\$Route"
    New-Item -ItemType Directory -Force -Path $GeneratedRoot | Out-Null

    $GeneratedPath = Join-Path $GeneratedRoot "$TaskId-message-only.md"
    $GeneratedContent = @"
# PDA Message-Only Test Input

- Route: $Route
- Task ID: $TaskId
- Mode: message-only test

## Message

$Message
"@

    $GeneratedContent | Out-File -FilePath $GeneratedPath -Encoding utf8
    return (Resolve-Path $GeneratedPath).Path
}

function Normalize-Route {
    param([string]$Route)
    if ([string]::IsNullOrWhiteSpace($Route)) {
        return ""
    }

    return $Route.Trim().ToLowerInvariant()
}

function Test-LooksLikeFilePath {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return ($Value -match '^[A-Za-z]:[\\/]' -or
            $Value -match '^\\\\' -or
            $Value -match '^[.]{1,2}[\\/]' -or
            $Value -match '[\\/]' -or
            $Value -match '^[^\\/:*?"<>|]+\.[A-Za-z0-9]{1,8}$')
}

function Get-WorkerForRoute {
    param([string]$Route)

    switch ($Route) {
        "planner" { "planner-worker" }
        "research" { "research-worker" }
        "review" { "review-worker" }
        "execute" { "execute-worker" }
        default { "" }
    }
}

function Get-NextWorkerForRoute {
    param([string]$Route)

    switch ($Route) {
        "planner" { "review-worker" }
        "research" { "review-worker" }
        "review" { "execute-worker" }
        "execute" { "" }
        default { "" }
    }
}

. $CategoryRoutingScript
$Registry = Get-PDAWorkerRegistry -Root $Root

Write-Log "Multi-agent staged-task intake started."
Write-Log "Staging root: $StagingRoot"

$StagedFiles = Get-ChildItem -Path $StagingRoot -Filter *.json -ErrorAction SilentlyContinue | Sort-Object CreationTime

foreach ($StagedFile in $StagedFiles) {
    $ProcessedPath = Join-Path $ProcessedRoot $StagedFile.Name
    $FailedPath = Join-Path $FailedRoot $StagedFile.Name

    try {
        $Task = Get-Content $StagedFile.FullName -Raw | ConvertFrom-Json
        $Route = Normalize-Route -Route ([string]$Task.route)

        if ([string]::IsNullOrWhiteSpace($Route)) {
            throw "Missing route in staged task."
        }

        $Worker = Get-WorkerForRoute -Route $Route
        if ([string]::IsNullOrWhiteSpace($Worker)) {
            throw "Unsupported staged route: $Route"
        }

        $RegistryWorker = Get-PDAWorkerRegistryEntry -Registry $Registry -Command ("/$Route")
        if (-not $RegistryWorker) {
            throw "Registry missing worker metadata for /$Route"
        }

        if (-not $Task.PSObject.Properties['task_id'] -or [string]::IsNullOrWhiteSpace([string]$Task.task_id)) {
            $GeneratedTaskId = [guid]::NewGuid().ToString()
            if ($Task.PSObject.Properties['task_id']) {
                $Task.task_id = $GeneratedTaskId
            }
            else {
                $Task | Add-Member -NotePropertyName task_id -NotePropertyValue $GeneratedTaskId
            }
            Write-Log "Generated missing task_id for staged file: $($StagedFile.Name) -> $($Task.task_id)"
        }

        $ResolvedSourcePath = Resolve-SourcePath -Value ([string]$Task.source_path)
        $SourcePathProvided = $Task.PSObject.Properties['source_path'] -and -not [string]::IsNullOrWhiteSpace([string]$Task.source_path)
        $MessageValue = if ($Task.PSObject.Properties['message']) { [string]$Task.message } else { "" }
        $MessageOnlyTestMode = $false

        if ($Route -in @('review', 'execute')) {
            if ($SourcePathProvided) {
                if ([string]::IsNullOrWhiteSpace($ResolvedSourcePath)) {
                    if (Test-LooksLikeFilePath -Value ([string]$Task.source_path)) {
                        throw "Invalid source_path for $Route task; staged file will not be dispatched."
                    }

                    if ([string]::IsNullOrWhiteSpace($MessageValue)) {
                        throw "Missing required source_path for $Route task; message-only test input requires a message."
                    }

                    $ResolvedSourcePath = New-MessageOnlySourceFile -Route $Route -TaskId ([string]$Task.task_id) -Message $MessageValue
                    $MessageOnlyTestMode = $true
                    Write-Log "Generated message-only source file for $Route task: $ResolvedSourcePath"
                }
            }
            elseif (-not [string]::IsNullOrWhiteSpace($MessageValue)) {
                $ResolvedSourcePath = New-MessageOnlySourceFile -Route $Route -TaskId ([string]$Task.task_id) -Message $MessageValue
                $MessageOnlyTestMode = $true
                Write-Log "Generated message-only source file for $Route task: $ResolvedSourcePath"
            }
            else {
                throw "Missing required source_path for $Route task; message-only test input requires a message."
            }
        }

        $RoutingDecision = Resolve-PDACategoryRouting -Task $Task -Worker $RegistryWorker
        if (-not $RoutingDecision.allowed) {
            throw "Category routing blocked for /${Route}: $($RoutingDecision.reason)"
        }

        $QueueTask = [ordered]@{
            task_id           = [string]$Task.task_id
            created           = if ($Task.PSObject.Properties['received_at'] -and -not [string]::IsNullOrWhiteSpace([string]$Task.received_at)) { [string]$Task.received_at } else { (Get-Date).ToUniversalTime().ToString("o") }
            command           = if ($Task.PSObject.Properties['command'] -and -not [string]::IsNullOrWhiteSpace([string]$Task.command)) { [string]$Task.command } else { "/$Route" }
            route             = $Route
            message           = if ($Task.PSObject.Properties['message']) { [string]$Task.message } else { "" }
            target            = if ($Task.PSObject.Properties['target'] -and -not [string]::IsNullOrWhiteSpace([string]$Task.target)) { [string]$Task.target } else { [string]$Task.message }
            source_path       = $ResolvedSourcePath
            project           = if ($Task.PSObject.Properties['project'] -and -not [string]::IsNullOrWhiteSpace([string]$Task.project)) { [string]$Task.project } else { "AI Ecosystem" }
            classification    = if ($Task.PSObject.Properties['classification'] -and -not [string]::IsNullOrWhiteSpace([string]$Task.classification)) { [string]$Task.classification } else { "category_1" }
            status            = "queued"
            requested_output  = if ($Task.PSObject.Properties['requested_output'] -and -not [string]::IsNullOrWhiteSpace([string]$Task.requested_output)) { [string]$Task.requested_output } else { "markdown" }
            source            = if ($Task.PSObject.Properties['source'] -and -not [string]::IsNullOrWhiteSpace([string]$Task.source)) { [string]$Task.source } else { "n8n" }
            assigned_worker   = $Worker
            next_worker       = Get-NextWorkerForRoute -Route ([string]$Task.route)
            retry_count       = 0
            category          = if ($Task.PSObject.Properties['category'] -and -not [string]::IsNullOrWhiteSpace([string]$Task.category)) { [string]$Task.category } else { "category_1" }
            approved          = if ($Task.PSObject.Properties['approved']) { [bool]$Task.approved } else { $true }
            origin            = "n8n-staged"
            input_mode        = if ($MessageOnlyTestMode) { "message-only-test" } else { "file" }
            routing_surface   = $RoutingDecision.routing_surface
            routing_profile   = $RoutingDecision.routing_profile
            routing_mode      = $RoutingDecision.routing_mode
            category_policy   = $RoutingDecision.reason
            staged_path       = $StagedFile.FullName
        }

        $PendingFile = Join-Path $PendingRoot "$($QueueTask.task_id).json"
        $QueueTask | ConvertTo-Json -Depth 20 | Set-Content -Path $PendingFile -Encoding UTF8
        Write-Log "Queued staged file: $($StagedFile.Name) -> $PendingFile"

        Move-Item -Path $StagedFile.FullName -Destination $ProcessedPath -Force
        Write-Log "Processed staged file moved to: $ProcessedPath"
    }
    catch {
        Write-Log "Failed staged file: $($StagedFile.Name)"
        Write-Log $_.Exception.Message

        if (Test-Path $StagedFile.FullName) {
            Move-Item -Path $StagedFile.FullName -Destination $FailedPath -Force
            Write-Log "Failed staged file moved to: $FailedPath"
        }
    }
}

Write-Log "Multi-agent staged-task intake complete."
