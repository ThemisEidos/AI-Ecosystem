param(
    [Parameter(Mandatory = $true)]
    [string]$TaskPath
)

$Root = Split-Path $PSScriptRoot -Parent
$QueueRoot = Join-Path $Root "PDA-Tasks"
$ResultsRoot = Join-Path $QueueRoot "results"
$ReporterRoot = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Reports"
$ConversationStateScript = Join-Path $Root "Scripts\Update-PDAConversationState.ps1"
$WorkerName = "reporter-worker"
. (Join-Path $Root "Scripts\PDA_OutputParsing.ps1")

function Register-PDAWorkerArtifact {
    param(
        [string]$ArtifactPath,
        [string]$TaskId,
        [string]$WorkerName,
        [string]$Command,
        [string]$Category,
        [string]$ArtifactType,
        [string]$Summary
    )

    try {
        $null = & "$Root\Scripts\Register-PDAArtifact.ps1" `
            -ArtifactPath $ArtifactPath `
            -SourceTaskId $TaskId `
            -WorkerName $WorkerName `
            -Command $Command `
            -Category $Category `
            -ArtifactType $ArtifactType `
            -Summary $Summary
    }
    catch {
        Write-Warning "Artifact registration skipped for ${WorkerName}: $($_.Exception.Message)"
    }
}

function ConvertTo-PDAHashtable {
    param([Parameter(Mandatory = $true)]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [hashtable] -or $Value -is [System.Collections.IDictionary]) {
        $Copy = @{}
        foreach ($Key in $Value.Keys) {
            if ($null -eq $Value[$Key]) {
                $Copy[$Key] = $null
            }
            else {
                $Copy[$Key] = ConvertTo-PDAHashtable -Value $Value[$Key]
            }
        }
        return $Copy
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $List = @()
        foreach ($Item in $Value) {
            if ($null -eq $Item) {
                $List += $null
            }
            else {
                $List += ,(ConvertTo-PDAHashtable -Value $Item)
            }
        }
        return $List
    }

    if ($Value -is [psobject] -and $Value.PSObject.Properties.Name.Count -gt 0) {
        $Copy = @{}
        foreach ($Prop in $Value.PSObject.Properties) {
            if ($null -eq $Prop.Value) {
                $Copy[$Prop.Name] = $null
            }
            else {
                $Copy[$Prop.Name] = ConvertTo-PDAHashtable -Value $Prop.Value
            }
        }
        return $Copy
    }

    return $Value
}

function Read-PDAWorkerJson {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Raw = & pwsh -NoProfile -Command "Get-Content -Path '$Path' -Raw" 2>&1
    $Text = [string]($Raw -join "`n")
    return ConvertFrom-PDAMixedJson -Text $Text -SourceName "Worker output"
}

function Write-PDAWorkerResultArtifact {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [Parameter(Mandatory = $true)]
        [object]$ResultObject
    )

    New-Item -ItemType Directory -Force -Path $ResultsRoot | Out-Null
    $ResultPath = Join-Path $ResultsRoot "$TaskId-result.json"
    $ResultObject | ConvertTo-Json -Depth 30 | Set-Content -Path $ResultPath -Encoding UTF8
    return $ResultPath
}

function Write-PDAReporterMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Stages = $null,

        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [Parameter(Mandatory = $true)]
        [string]$CommandText,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [string]$FinalReviewContent = "",
        [string]$FailureReason = ""
    )

    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add("# Reporter Pipeline Report")
    $Lines.Add("")
    $Lines.Add(("Task ID: {0}" -f $TaskId))
    $Lines.Add(("Command: {0}" -f $CommandText))
    $Lines.Add(("Status: {0}" -f $Status))
    if (-not [string]::IsNullOrWhiteSpace($FailureReason)) {
        $Lines.Add(("Failure reason: {0}" -f $FailureReason))
    }
    $Lines.Add("")
    $Lines.Add("## Stage Summary")
    $Lines.Add("")
    $Lines.Add("| Stage | Worker | Status | Saved Path |")
    $Lines.Add("|---|---|---|---|")

    $StageList = @()
    if ($null -ne $Stages) {
        $StageList = @($Stages)
    }

    foreach ($Stage in $StageList) {
        $Lines.Add("| " + [string]$Stage.stage + " | " + [string]$Stage.worker + " | " + [string]$Stage.status + " | " + [string]$Stage.saved_path + " |")
    }

    if (-not [string]::IsNullOrWhiteSpace($FinalReviewContent)) {
        $Lines.Add("")
        $Lines.Add("## Final Review Output")
        $Lines.Add("")
        $Lines.Add($FinalReviewContent.Trim())
    }

    if (-not [string]::IsNullOrWhiteSpace($FailureReason) -and [string]::IsNullOrWhiteSpace($FinalReviewContent)) {
        $Lines.Add("")
        $Lines.Add("## Failure Details")
        $Lines.Add("")
        $Lines.Add($FailureReason)
    }

    $Lines | Set-Content -Path $Path -Encoding UTF8
}

function Update-PDAReporterConversationState {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Task,

        [Parameter(Mandatory = $true)]
        [string]$TaskStatus,

        [Parameter(Mandatory = $true)]
        [string]$ResultPath,

        [Parameter(Mandatory = $true)]
        [string]$ResultSummary
    )

    if ([string]::IsNullOrWhiteSpace([string]$Task.conversation_id) -and
        [string]::IsNullOrWhiteSpace([string]$Task.session_id) -and
        [string]::IsNullOrWhiteSpace([string]$Task.user_id) -and
        [string]::IsNullOrWhiteSpace([string]$Task.conversation_title)) {
        return
    }

    try {
        $CallArgs = @(
            "-NoProfile"
            "-File"
            $ConversationStateScript
            "-TaskId"
            ([string]$Task.task_id)
            "-TaskStatus"
            $TaskStatus
            "-ResultPath"
            $ResultPath
            "-ResultSummary"
            $ResultSummary
            "-Source"
            "reporter-worker"
        )

        if (-not [string]::IsNullOrWhiteSpace([string]$Task.conversation_id)) {
            $CallArgs += @("-ConversationId", [string]$Task.conversation_id)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$Task.session_id)) {
            $CallArgs += @("-SessionId", [string]$Task.session_id)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$Task.user_id)) {
            $CallArgs += @("-UserId", [string]$Task.user_id)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$Task.conversation_title)) {
            $CallArgs += @("-ConversationTitle", [string]$Task.conversation_title)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$Task.command)) {
            $CallArgs += @("-UserMessage", [string]$Task.command)
        }

        $null = & pwsh @CallArgs 2>&1
    }
    catch {
        Write-Warning "Conversation state update skipped: $($_.Exception.Message)"
    }
}

function Invoke-PDAReporterStage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Stage,

        [Parameter(Mandatory = $true)]
        [string]$WorkerScript,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [object]$Task
    )

    $StageTask = [ordered]@{
        task_id             = "$([string]$Task.task_id)-$Stage"
        created             = (Get-Date).ToUniversalTime().ToString("o")
        command             = [string]$Task.command
        project             = if ($Task.project) { [string]$Task.project } else { "AI Ecosystem" }
        classification      = if ($Task.classification) { [string]$Task.classification } else { "category_1" }
        status              = "queued"
        requested_output    = "markdown"
        source_path         = $SourcePath
        assigned_worker     = $Stage
        next_worker         = ""
        retry_count         = 0
    }

    foreach ($Field in @("conversation_id", "session_id", "user_id", "conversation_title")) {
        if ($Task.PSObject.Properties.Name -contains $Field -and -not [string]::IsNullOrWhiteSpace([string]$Task.$Field)) {
            $StageTask[$Field] = [string]$Task.$Field
        }
    }

    $StageRunningRoot = Join-Path $QueueRoot "running\reporter-stages"
    $StageResultsRoot = Join-Path $QueueRoot "results\reporter-stages"
    $StageFailedRoot = Join-Path $QueueRoot "failed\reporter-stages"
    New-Item -ItemType Directory -Force -Path $StageRunningRoot, $StageResultsRoot, $StageFailedRoot | Out-Null

    $StageTaskPath = Join-Path $StageRunningRoot "$($StageTask.task_id).json"
    $StageTask | ConvertTo-Json -Depth 20 | Set-Content -Path $StageTaskPath -Encoding UTF8

    try {
        $Raw = & pwsh -NoProfile -File $WorkerScript -TaskPath $StageTaskPath 2>&1
        $Text = [string]($Raw -join "`n")
        $StageResult = ConvertFrom-PDAMixedJson -Text $Text -SourceName "Stage worker output"
        if (-not $StageResult -or [string]::IsNullOrWhiteSpace([string]$StageResult.status)) {
            throw "Stage worker did not return a valid result contract."
        }

        if ([string]$StageResult.status -ne "success") {
            $ErrorMessage = if ($StageResult.output -and $StageResult.output.error) { [string]$StageResult.output.error } else { "stage worker failed." }
            Move-Item -Path $StageTaskPath -Destination (Join-Path $StageFailedRoot (Split-Path $StageTaskPath -Leaf)) -Force
            return [ordered]@{
                stage      = $Stage
                worker     = [string]$StageResult.worker
                status     = [string]$StageResult.status
                saved_path = if ($StageResult.saved_path) { [string]$StageResult.saved_path } else { "" }
                error      = $ErrorMessage
                result     = $StageResult
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$StageResult.saved_path)) {
            Move-Item -Path $StageTaskPath -Destination (Join-Path $StageFailedRoot (Split-Path $StageTaskPath -Leaf)) -Force
            return [ordered]@{
                stage      = $Stage
                worker     = [string]$StageResult.worker
                status     = "failed"
                saved_path = ""
                error      = "Stage worker did not return a saved_path."
                result     = $StageResult
            }
        }

        Move-Item -Path $StageTaskPath -Destination (Join-Path $StageResultsRoot (Split-Path $StageTaskPath -Leaf)) -Force

        return [ordered]@{
            stage      = $Stage
            worker     = [string]$StageResult.worker
            status     = [string]$StageResult.status
            saved_path = [string]$StageResult.saved_path
            error      = ""
            result     = $StageResult
        }
    }
    catch {
        if (Test-Path -Path $StageTaskPath) {
            Move-Item -Path $StageTaskPath -Destination (Join-Path $StageFailedRoot (Split-Path $StageTaskPath -Leaf)) -Force
        }
        return [ordered]@{
            stage      = $Stage
            worker     = $Stage
            status     = "failed"
            saved_path = ""
            error      = $_.Exception.Message
            result     = $null
        }
    }
}

function New-PDAReporterFailureResult {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Task,

        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [Parameter(Mandatory = $true)]
        [string]$CommandText,

        [Parameter(Mandatory = $true)]
        [string]$CategoryText,

        [Parameter(Mandatory = $true)]
        [string]$ResultPath,

        [Parameter(Mandatory = $true)]
        [string]$ReportPath,

        [Parameter(Mandatory = $true)]
        [string]$FailureReason,

        [Parameter(Mandatory = $true)]
        [string]$FailedStage
    )

    $StageList = @()
    if ($null -ne $StageSummaries) {
        $StageList = @($StageSummaries)
    }

    Write-PDAReporterMarkdown -Path $ReportPath -Stages $StageList -TaskId $TaskId -CommandText $CommandText -Status "failed" -FailureReason $FailureReason

    $ResultObject = [ordered]@{
        task_id        = $TaskId
        worker         = $WorkerName
        status         = "failed"
        classification = $CategoryText
        input_summary  = $CommandText
        output_type    = "report_pipeline_error"
        output         = @{
            error       = $FailureReason
            failed_stage = $FailedStage
            stages      = @($StageList | ForEach-Object {
                [ordered]@{
                    stage      = $_.stage
                    worker     = $_.worker
                    status     = $_.status
                    saved_path = $_.saved_path
                }
            })
            artifacts   = @{}
            report_path = $ReportPath
            conversation = [ordered]@{
                conversation_id   = if ($Task.PSObject.Properties.Name -contains "conversation_id") { [string]$Task.conversation_id } else { "" }
                session_id        = if ($Task.PSObject.Properties.Name -contains "session_id") { [string]$Task.session_id } else { "" }
                user_id           = if ($Task.PSObject.Properties.Name -contains "user_id") { [string]$Task.user_id } else { "" }
                conversation_title = if ($Task.PSObject.Properties.Name -contains "conversation_title") { [string]$Task.conversation_title } else { "" }
            }
        }
        confidence     = 0
        warnings       = @("Reporter pipeline failed before completion.")
        next_worker    = ""
        saved_path     = $ReportPath
        result_path    = $ResultPath
    }

    $Artifacts = $ResultObject.output.artifacts
    foreach ($Stage in $StageList) {
        $Artifacts[$Stage.stage] = $Stage.saved_path
    }
    $Artifacts["final_report"] = $ReportPath

    $ResultObject | ConvertTo-Json -Depth 30 | Set-Content -Path $ResultPath -Encoding UTF8
    Register-PDAWorkerArtifact -ArtifactPath $ReportPath -TaskId $TaskId -WorkerName $WorkerName -Command $CommandText -Category $CategoryText -ArtifactType "report_pipeline_markdown" -Summary "Reporter pipeline failure summary"
    Register-PDAWorkerArtifact -ArtifactPath $ResultPath -TaskId $TaskId -WorkerName $WorkerName -Command $CommandText -Category $CategoryText -ArtifactType "worker_result_json" -Summary "Reporter canonical result contract"

    Update-PDAReporterConversationState -Task $Task -TaskStatus "failed" -ResultPath $ResultPath -ResultSummary ("Reporter pipeline failed: {0}" -f $FailureReason)

    return ($ResultObject | ConvertTo-Json -Depth 30)
}

$Task = Get-Content $TaskPath -Raw | ConvertFrom-Json
$TaskId = if ($Task.task_id) { [string]$Task.task_id } else { [guid]::NewGuid().ToString() }
$CommandText = if ($Task.command) { [string]$Task.command } else { "/reporter" }
$CategoryText = if ($Task.classification) { [string]$Task.classification } elseif ($Task.category) { [string]$Task.category } else { "category_1" }
$SourcePath = if ($Task.source_path) { [string]$Task.source_path } else { "" }
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ResultPath = Join-Path $ResultsRoot "$TaskId-result.json"
$ReportPath = Join-Path $ReporterRoot "reporter-output-$Timestamp.md"

New-Item -ItemType Directory -Force -Path $ReporterRoot, $ResultsRoot | Out-Null

$StageSummaries = @()
$FailedStage = ""
$FailureReason = ""

try {
    if ([string]::IsNullOrWhiteSpace($SourcePath) -or -not (Test-Path -Path $SourcePath -PathType Leaf)) {
        $FailedStage = "source"
        throw "No valid source_path provided."
    }

    $StageTimeline = Invoke-PDAReporterStage -Stage "timeline" -WorkerScript (Join-Path $Root "Scripts\Invoke-PDATimelineWorker.ps1") -SourcePath $SourcePath -Task $Task
    $StageSummaries += $StageTimeline
    if ($StageTimeline.status -ne "success") {
        $FailedStage = "timeline"
        throw $StageTimeline.error
    }

    $StageFindings = Invoke-PDAReporterStage -Stage "findings" -WorkerScript (Join-Path $Root "Scripts\Invoke-PDAFindingsWorker.ps1") -SourcePath $StageTimeline.saved_path -Task $Task
    $StageSummaries += $StageFindings
    if ($StageFindings.status -ne "success") {
        $FailedStage = "findings"
        throw $StageFindings.error
    }

    $StageResearch = Invoke-PDAReporterStage -Stage "research" -WorkerScript (Join-Path $Root "Scripts\Invoke-PDAResearchWorker.ps1") -SourcePath $StageFindings.saved_path -Task $Task
    $StageSummaries += $StageResearch
    if ($StageResearch.status -ne "success") {
        $FailedStage = "research"
        throw $StageResearch.error
    }

    $StageDraft = Invoke-PDAReporterStage -Stage "draft" -WorkerScript (Join-Path $Root "Scripts\Invoke-PDADraftWorker.ps1") -SourcePath $StageResearch.saved_path -Task $Task
    $StageSummaries += $StageDraft
    if ($StageDraft.status -ne "success") {
        $FailedStage = "draft"
        throw $StageDraft.error
    }

    $StageReview = Invoke-PDAReporterStage -Stage "review" -WorkerScript (Join-Path $Root "Scripts\Invoke-PDAReviewWorker.ps1") -SourcePath $StageDraft.saved_path -Task $Task
    $StageSummaries += $StageReview
    if ($StageReview.status -ne "success") {
        $FailedStage = "review"
        throw $StageReview.error
    }

    $ReviewResult = $StageReview.result
    $ReviewContent = if ($ReviewResult.output -and $ReviewResult.output.content) { [string]$ReviewResult.output.content } else { "" }
    $Artifacts = [ordered]@{
        timeline      = $StageTimeline.saved_path
        findings      = $StageFindings.saved_path
        research      = $StageResearch.saved_path
        draft         = $StageDraft.saved_path
        review        = $StageReview.saved_path
        final_report  = $ReportPath
    }

    Write-PDAReporterMarkdown -Path $ReportPath -Stages $StageSummaries -TaskId $TaskId -CommandText $CommandText -Status "success" -FinalReviewContent $ReviewContent

    $ResultObject = [ordered]@{
        task_id        = $TaskId
        worker         = $WorkerName
        status         = "success"
        classification = $CategoryText
        input_summary  = $CommandText
        output_type    = "report_pipeline"
        output         = @{
            pipeline = [ordered]@{
                stage_count           = $StageSummaries.Count
                completed_stage_count  = @($StageSummaries | Where-Object { $_.status -eq "success" }).Count
                stages                = @($StageSummaries | ForEach-Object {
                    $StageOutput = [ordered]@{
                        stage      = $_.stage
                        worker     = $_.worker
                        status     = $_.status
                        saved_path = $_.saved_path
                    }
                    if ($_.result.output -and $_.result.output.model_route) {
                        $StageOutput.model_route = ConvertTo-PDAHashtable -Value $_.result.output.model_route
                    }
                    if ($_.result.output -and $_.result.output.fallback) {
                        $StageOutput.fallback = ConvertTo-PDAHashtable -Value $_.result.output.fallback
                    }
                    $StageOutput
                })
                artifacts             = $Artifacts
                final_review          = [ordered]@{
                    worker     = [string]$StageReview.result.worker
                    saved_path = [string]$StageReview.saved_path
                    content    = $ReviewContent
                }
            }
            conversation = [ordered]@{
                conversation_id    = if ($Task.PSObject.Properties.Name -contains "conversation_id") { [string]$Task.conversation_id } else { "" }
                session_id         = if ($Task.PSObject.Properties.Name -contains "session_id") { [string]$Task.session_id } else { "" }
                user_id            = if ($Task.PSObject.Properties.Name -contains "user_id") { [string]$Task.user_id } else { "" }
                conversation_title = if ($Task.PSObject.Properties.Name -contains "conversation_title") { [string]$Task.conversation_title } else { "" }
            }
        }
        confidence     = 0.95
        warnings       = @()
        next_worker    = ""
        saved_path     = $ReportPath
        result_path    = $ResultPath
    }

    $ResultObject | ConvertTo-Json -Depth 30 | Set-Content -Path $ResultPath -Encoding UTF8
    Register-PDAWorkerArtifact -ArtifactPath $ReportPath -TaskId $TaskId -WorkerName $WorkerName -Command $CommandText -Category $CategoryText -ArtifactType "report_pipeline_markdown" -Summary "Reporter pipeline final report"
    Register-PDAWorkerArtifact -ArtifactPath $ResultPath -TaskId $TaskId -WorkerName $WorkerName -Command $CommandText -Category $CategoryText -ArtifactType "worker_result_json" -Summary "Reporter canonical result contract"

    Update-PDAReporterConversationState -Task $Task -TaskStatus "completed" -ResultPath $ResultPath -ResultSummary ("Reporter pipeline completed; final report at {0}" -f $ReportPath)

    $ResultObject | ConvertTo-Json -Depth 30
}
catch {
    if ([string]::IsNullOrWhiteSpace($FailedStage)) {
        $FailedStage = if ($StageSummaries.Count -gt 0) { [string]$StageSummaries[-1].stage } else { "source" }
    }
    $FailureReason = $_.Exception.Message
    $FailureResult = New-PDAReporterFailureResult -Task $Task -TaskId $TaskId -CommandText $CommandText -CategoryText $CategoryText -ResultPath $ResultPath -ReportPath $ReportPath -FailureReason $FailureReason -FailedStage $FailedStage
    $FailureResult
}
