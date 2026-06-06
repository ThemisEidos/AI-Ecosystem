param(
    [Parameter(Mandatory = $true)]
    [string]$TaskPath
)

$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"
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

function New-PDAExecuteFailure {
    param(
        [string]$Reason,
        [string]$TaskId,
        [string]$CommandText,
        [string]$CategoryText,
        [string]$ResultPath
    )

    $FailureResult = [ordered]@{
        task_id        = $TaskId
        worker         = "execute-worker"
        status         = "failed"
        classification = $CategoryText
        input_summary  = $CommandText
        output_type    = "error"
        output         = @{
            error = $Reason
        }
        confidence     = 0
        warnings       = @("Execute worker execution failed.")
        next_worker    = ""
        saved_path     = ""
        result_path    = $ResultPath
    }

    try {
        Write-PDAWorkerResultArtifact -TaskId $TaskId -ResultObject $FailureResult | Out-Null
        Register-PDAWorkerArtifact -ArtifactPath $ResultPath -TaskId $TaskId -WorkerName "execute-worker" -Command $CommandText -Category $CategoryText -ArtifactType "worker_result_json" -Summary "Execute worker canonical result contract"
    }
    catch {
        Write-Warning "Failed to write execute worker failure artifact: $($_.Exception.Message)"
    }

    return ($FailureResult | ConvertTo-Json -Depth 20)
}

$Task = Get-Content $TaskPath -Raw | ConvertFrom-Json

$TaskId = if ($Task.task_id) { [string]$Task.task_id } else { [guid]::NewGuid().ToString() }
$CommandText = if ($Task.command) { [string]$Task.command } else { "/execute" }
$CategoryText = if ($Task.classification) { [string]$Task.classification } elseif ($Task.category) { [string]$Task.category } else { "category_1" }
$RoutingCategory = if ([string]$CategoryText -eq "category_2") { "category_2" } else { "category_1" }
$RoutingSensitivity = if ($RoutingCategory -eq "category_2") { "restricted_local" } else { "standard" }
$ResultPath = Join-Path $Root "PDA-Tasks\results\$TaskId-result.json"

$SourceText = $Task.target
if ($Task.source_path -and (Test-Path $Task.source_path)) {
    $SourceText = Get-Content $Task.source_path -Raw
}

if ([string]::IsNullOrWhiteSpace([string]$SourceText)) {
    New-PDAExecuteFailure -Reason "No valid source_path or target provided." -TaskId $TaskId -CommandText $CommandText -CategoryText $CategoryText -ResultPath $ResultPath
    return
}

$Prompt = @"
You are execute-worker inside the PDA ecosystem.

Your job:
Transform an approved plan or instruction set into a deterministic execution manifest.

Requirements:
- do not perform external side effects
- do not invent steps
- preserve approval boundaries
- be explicit about assumptions and prerequisites
- markdown format
- keep the output human-reviewable

Task:
$SourceText
"@

try {
    $RawInvocation = & pwsh -NoProfile -File $AdapterScript `
        -WorkerName "execute-worker" `
        -TaskType "execute" `
        -Command "/execute" `
        -Category $RoutingCategory `
        -Sensitivity $RoutingSensitivity `
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
        throw "Execute model returned empty content."
    }

    $OutputFolder = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Execution"
    New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $MarkdownPath = Join-Path $OutputFolder "execution-output-$Timestamp.md"

    $Content | Set-Content -Path $MarkdownPath -Encoding UTF8

    $ResultObject = [ordered]@{
        task_id        = $TaskId
        worker         = "execute-worker"
        status         = "success"
        classification = $CategoryText
        input_summary  = $CommandText
        output_type    = "execution_markdown"
        output         = @{
            markdown_path = $MarkdownPath
            content = $Content
            model_route = ConvertTo-PDAHashtable -Value $Invocation.routing
            fallback = ConvertTo-PDAHashtable -Value $Invocation.fallback
            model_response = ConvertTo-PDAHashtable -Value $Invocation.response
            model_request = @{
                prompt = $Prompt
                worker_name = "execute-worker"
                task_type = "execute"
                sensitivity = $RoutingSensitivity
                category = $RoutingCategory
            }
        }
        confidence     = 0.84
        warnings       = @()
        next_worker    = ""
        saved_path     = $MarkdownPath
        result_path    = $ResultPath
    }

    Write-PDAWorkerResultArtifact -TaskId $TaskId -ResultObject $ResultObject | Out-Null
    Register-PDAWorkerArtifact -ArtifactPath $MarkdownPath -TaskId $TaskId -WorkerName "execute-worker" -Command $CommandText -Category $CategoryText -ArtifactType "execution_markdown" -Summary "Execute worker markdown output"
    Register-PDAWorkerArtifact -ArtifactPath $ResultPath -TaskId $TaskId -WorkerName "execute-worker" -Command $CommandText -Category $CategoryText -ArtifactType "worker_result_json" -Summary "Execute worker canonical result contract"

    $ResultObject | ConvertTo-Json -Depth 20
}
catch {
    New-PDAExecuteFailure -Reason $_.Exception.Message -TaskId $TaskId -CommandText $CommandText -CategoryText $CategoryText -ResultPath $ResultPath
}
