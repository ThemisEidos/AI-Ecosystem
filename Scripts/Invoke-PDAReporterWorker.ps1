param(
    [Parameter(Mandatory=$true)]
    [string]$TaskPath
)

$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"
$QueueRoot = Join-Path $Root "PDA-Tasks"
$WorkerName = "reporter-worker"
$MaxRetries = 3

# Deprecated legacy queue/task paths are intentionally not used here.
# The reporter controller is canonical-only and writes all artifacts under PDA-Tasks
# and the Obsidian reporting workspace.

function Read-TaskJson {
    param([string]$Path)
    Get-Content $Path -Raw | ConvertFrom-Json
}

function Write-TaskJson {
    param(
        [string]$Path,
        [object]$Object
    )

    $Object | ConvertTo-Json -Depth 20 | Set-Content -Path $Path -Encoding UTF8
}

function Invoke-StageWorker {
    param(
        [string]$StageName,
        [string]$SourcePath,
        [string]$TaskId,
        [string]$Classification,
        [string]$Command
    )

    $StageTask = [ordered]@{
        task_id = "$TaskId-$StageName"
        created = (Get-Date).ToUniversalTime().ToString("o")
        command = $Command
        project = "AI Ecosystem"
        classification = $Classification
        status = "queued"
        requested_output = "markdown"
        source_path = $SourcePath
        assigned_worker = $StageName
        next_worker = ""
        retry_count = 0
    }

    $StageRunningRoot = Join-Path $QueueRoot "running\reporter-stages"
    $StageResultsRoot = Join-Path $QueueRoot "results\reporter-stages"
    $StageFailedRoot = Join-Path $QueueRoot "failed\reporter-stages"

    # Reporter-created stage tasks are not canonical queue items.
    # They live only under reporter-specific running/results/failed folders.
    New-Item -ItemType Directory -Force -Path $StageRunningRoot, $StageResultsRoot, $StageFailedRoot | Out-Null

    $StageTaskPath = Join-Path $StageRunningRoot "$($StageTask.task_id).json"
    Write-TaskJson -Path $StageTaskPath -Object $StageTask

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        $attempt++

        switch ($StageName) {
            "timeline-worker" {
                Write-Host "[REPORTER] Starting timeline-worker..."
                $ResultJson = & "$Root\Scripts\Invoke-PDATimelineWorker.ps1" -TaskPath $StageTaskPath
            }
            "findings-worker" {
                Write-Host "[REPORTER] Starting findings-worker..."
                $ResultJson = & "$Root\Scripts\Invoke-PDAFindingsWorker.ps1" -TaskPath $StageTaskPath
            }
            "draft-worker" {
                Write-Host "[REPORTER] Starting draft-worker..."
                $ResultJson = & "$Root\Scripts\Invoke-PDADraftWorker.ps1" -TaskPath $StageTaskPath
            }
            "review-worker" {
                Write-Host "[REPORTER] Starting review-worker..."
                $ResultJson = & "$Root\Scripts\Invoke-PDAReviewWorker.ps1" -TaskPath $StageTaskPath
            }
            default {
                throw "Unknown reporter stage: $StageName"
            }
        }

        if ($ResultJson) {
            $StageResult = $ResultJson | ConvertFrom-Json
            if ($StageResult.status -eq "success" -and $StageResult.saved_path) {
                Move-Item -Path $StageTaskPath -Destination (Join-Path $StageResultsRoot (Split-Path $StageTaskPath -Leaf)) -Force
                Write-Host "[REPORTER] Stage completed successfully: $StageName"
                return [ordered]@{
                    task_path = (Join-Path $StageResultsRoot (Split-Path $StageTaskPath -Leaf))
                    result = $StageResult
                }
            }
        }

        if ($attempt -lt $MaxRetries) {
            Write-Host "[REPORTER] Stage retry $attempt/$($MaxRetries): $StageName"
        }
    }

    if (Test-Path $StageTaskPath) {
        Move-Item -Path $StageTaskPath -Destination (Join-Path $StageFailedRoot (Split-Path $StageTaskPath -Leaf)) -Force
    }

    throw "Stage failed after $($MaxRetries) retries: $StageName"
}

$Task = Read-TaskJson -Path $TaskPath

if (-not $Task.source_path) {
    [ordered]@{
        task_id        = $Task.task_id
        worker         = $WorkerName
        status         = "failed"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "error"
        output         = @{
            error = "No source_path provided."
        }
        confidence     = 0
        warnings       = @("Reporter controller requires source material.")
        next_worker    = ""
        saved_path     = ""
    } | ConvertTo-Json -Depth 20

    exit
}

$ReporterRoot = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Reports"
New-Item -ItemType Directory -Force -Path $ReporterRoot | Out-Null

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

try {
    $Timeline = Invoke-StageWorker -StageName "timeline-worker" -SourcePath $Task.source_path -TaskId $Task.task_id -Classification $Task.classification -Command $Task.command
    $Findings = Invoke-StageWorker -StageName "findings-worker" -SourcePath $Timeline.result.saved_path -TaskId $Task.task_id -Classification $Task.classification -Command $Task.command
    $Draft = Invoke-StageWorker -StageName "draft-worker" -SourcePath $Findings.result.saved_path -TaskId $Task.task_id -Classification $Task.classification -Command $Task.command
    $Review = Invoke-StageWorker -StageName "review-worker" -SourcePath $Draft.result.saved_path -TaskId $Task.task_id -Classification $Task.classification -Command $Task.command

    $ManifestPath = Join-Path $ReporterRoot "reporter-manifest-$Timestamp.json"
    $Manifest = [ordered]@{
        task_id        = $Task.task_id
        worker         = $WorkerName
        status         = "success"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "report_manifest"
        output         = @{
            timeline = $Timeline.result.saved_path
            findings = $Findings.result.saved_path
            draft    = $Draft.result.saved_path
            review   = $Review.result.saved_path
        }
        confidence     = 0.9
        warnings       = @()
        next_worker    = ""
        saved_path     = $ManifestPath
    }

    Write-TaskJson -Path $ManifestPath -Object $Manifest
    $Manifest | ConvertTo-Json -Depth 20
}
catch {
    [ordered]@{
        task_id        = $Task.task_id
        worker         = $WorkerName
        status         = "failed"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "error"
        output         = @{
            error = $_.Exception.Message
        }
        confidence     = 0
        warnings       = @("Reporter controller failed before completion.")
        next_worker    = ""
        saved_path     = ""
    } | ConvertTo-Json -Depth 20
}
