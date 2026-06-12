param(
    [Parameter(Mandatory = $true)]
    [string]$TaskPath
)

$Root = Split-Path $PSScriptRoot -Parent
$AdapterScript = Join-Path $Root "Scripts\Invoke-PDAModel.ps1"
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

function Write-PDAWorkerResultArtifact {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [Parameter(Mandatory = $true)]
        [object]$ResultObject
    )

    $ResultsFolder = Join-Path $Root "PDA-Tasks\results"
    New-Item -ItemType Directory -Force -Path $ResultsFolder | Out-Null

    $ResultPath = Join-Path $ResultsFolder "$TaskId-result.json"
    $ResultObject | ConvertTo-Json -Depth 20 | Set-Content -Path $ResultPath -Encoding UTF8
    return $ResultPath
}

function New-PDATimelineFailure {
    param(
        [string]$TaskId,
        [string]$WorkerName,
        [string]$CategoryText,
        [string]$CommandText,
        [string]$ResultPath,
        [string]$Reason
    )

    $FailureResult = [ordered]@{
        task_id        = $TaskId
        worker         = $WorkerName
        status         = "failed"
        classification = $CategoryText
        input_summary  = $CommandText
        output_type    = "error"
        output         = @{
            error = $Reason
        }
        confidence     = 0
        warnings       = @("Timeline worker execution failed.")
        next_worker    = ""
        saved_path     = ""
        result_path    = $ResultPath
    }

    try {
        Write-PDAWorkerResultArtifact -TaskId $TaskId -ResultObject $FailureResult | Out-Null
        Register-PDAWorkerArtifact -ArtifactPath $ResultPath -TaskId $TaskId -WorkerName $WorkerName -Command $CommandText -Category $CategoryText -ArtifactType "worker_result_json" -Summary "Timeline worker canonical result contract"
    }
    catch {
        Write-Warning "Failed to write timeline worker failure result artifact: $($_.Exception.Message)"
    }

    return ($FailureResult | ConvertTo-Json -Depth 20)
}

$Task = Get-Content $TaskPath -Raw | ConvertFrom-Json

$TaskId = if ($Task.task_id) { [string]$Task.task_id } else { [guid]::NewGuid().ToString() }
$CommandText = if ($Task.command) { [string]$Task.command } elseif ($Task.target) { [string]$Task.target } else { "/timeline" }
$CategoryText = if ($Task.classification) { [string]$Task.classification } elseif ($Task.category) { [string]$Task.category } else { "category_1" }
$SourcePath = if ($Task.source_path) { [string]$Task.source_path } else { "" }
$MarkdownOutputFolder = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Timeline"
$ResultPath = Join-Path $Root "PDA-Tasks\results\$TaskId-result.json"

if ([string]::IsNullOrWhiteSpace($SourcePath) -or -not (Test-Path -Path $SourcePath -PathType Leaf)) {
    New-PDATimelineFailure -TaskId $TaskId -WorkerName "timeline-worker" -CategoryText $CategoryText -CommandText $CommandText -ResultPath $ResultPath -Reason "No valid source_path provided."
    return
}

$SourceContent = Get-Content $SourcePath -Raw

$Prompt = @"
You are timeline-worker inside the PDA ecosystem.

Your job:
Convert raw operational notes into structured chronological timeline entries.

Requirements:
- preserve chronology
- preserve timestamps
- preserve uncertainty
- concise operational wording
- no hallucinations
- no added facts
- markdown bullet timeline
- use approximate times if needed
- identify missing timestamps if unclear

Return ONLY timeline markdown.

Source Notes:

$SourceContent
"@

try {
    $RawInvocation = & pwsh -NoProfile -File $AdapterScript `
        -WorkerName "timeline-worker" `
        -TaskType "timeline" `
        -Sensitivity "restricted_local" `
        -Prompt $Prompt `
        -AsJson `
        -NoThrow 2>&1

    $JsonText = [string]($RawInvocation -join "`n")
    $Invocation = ConvertFrom-PDAMixedJson -Text $JsonText -SourceName "Model adapter output"
    if (-not $Invocation -or $Invocation.status -ne "pass") {
        $ErrorText = if ($Invocation.response -and $Invocation.response.error_message) { [string]$Invocation.response.error_message } elseif ($Invocation.next_action) { [string]$Invocation.next_action } else { "Model invocation failed." }
        throw $ErrorText
    }

    $Content = [string]$Invocation.response_text
    if ([string]::IsNullOrWhiteSpace($Content)) {
        throw "Timeline model returned empty content."
    }

    New-Item -ItemType Directory -Force -Path $MarkdownOutputFolder | Out-Null
    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $MarkdownPath = Join-Path $MarkdownOutputFolder "timeline-output-$Timestamp.md"
    $Content | Set-Content -Path $MarkdownPath -Encoding UTF8

    $TaskCommand = if ($Task.command) { [string]$Task.command } else { $CommandText }
    $ResultObject = [ordered]@{
        task_id        = $TaskId
        worker         = "timeline-worker"
        status         = "success"
        classification = $CategoryText
        input_summary  = $TaskCommand
        output_type    = "timeline_markdown"
        output         = @{
            markdown_path = $MarkdownPath
            content       = $Content
            model_route   = ConvertTo-PDAHashtable -Value $Invocation.routing
            model_response = ConvertTo-PDAHashtable -Value $Invocation.response
            fallback      = ConvertTo-PDAHashtable -Value $Invocation.fallback
        }
        confidence     = 0.90
        warnings       = @()
        next_worker    = "findings-worker"
        saved_path     = $MarkdownPath
        result_path    = $ResultPath
    }

    Write-PDAWorkerResultArtifact -TaskId $TaskId -ResultObject $ResultObject | Out-Null
    Register-PDAWorkerArtifact -ArtifactPath $MarkdownPath -TaskId $TaskId -WorkerName "timeline-worker" -Command $TaskCommand -Category $CategoryText -ArtifactType "timeline_markdown" -Summary "Timeline worker markdown output"
    Register-PDAWorkerArtifact -ArtifactPath $ResultPath -TaskId $TaskId -WorkerName "timeline-worker" -Command $TaskCommand -Category $CategoryText -ArtifactType "worker_result_json" -Summary "Timeline worker canonical result contract"

    $ResultObject | ConvertTo-Json -Depth 20
}
catch {
    New-PDATimelineFailure -TaskId $TaskId -WorkerName "timeline-worker" -CategoryText $CategoryText -CommandText $CommandText -ResultPath $ResultPath -Reason $_.Exception.Message
}
