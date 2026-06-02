param(
    [Parameter(Mandatory=$true)]
    [string]$TaskPath
)

$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"

$Task = Get-Content $TaskPath -Raw | ConvertFrom-Json

switch ($Task.assigned_worker) {

    "planner-worker" {
        & "$Root\Scripts\Invoke-PDAPlannerWorker.ps1" -TaskPath $TaskPath
    }

    "timeline-worker" {
        & "$Root\Scripts\Invoke-PDATimelineWorker.ps1" -TaskPath $TaskPath
    }

    "findings-worker" {
        & "$Root\Scripts\Invoke-PDAFindingsWorker.ps1" -TaskPath $TaskPath
    }

    "draft-worker" {
        & "$Root\Scripts\Invoke-PDADraftWorker.ps1" -TaskPath $TaskPath
    }

    "review-worker" {
        & "$Root\Scripts\Invoke-PDAReviewWorker.ps1" -TaskPath $TaskPath
    }

    "research-worker" {
        & "$Root\Scripts\Invoke-PDAResearchWorker.ps1" -TaskPath $TaskPath
    }

    "execute-worker" {
        & "$Root\Scripts\Invoke-PDAExecuteWorker.ps1" -TaskPath $TaskPath
    }

    "reporter-worker" {
        & "$Root\Scripts\Invoke-PDAReporterWorker.ps1" -TaskPath $TaskPath
    }

    default {

        [ordered]@{
            task_id        = $Task.task_id
            worker         = $Task.assigned_worker
            status         = "failed"
            classification = $Task.classification
            input_summary  = $Task.command
            output_type    = "error"
            output         = @{
                error = "Unknown worker: $($Task.assigned_worker)"
            }
            confidence     = 0
            warnings       = @("Worker not found.")
            next_worker    = ""
            saved_path     = ""
        } | ConvertTo-Json -Depth 20
    }
}
