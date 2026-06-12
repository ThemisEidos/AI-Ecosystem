param(
    [Parameter(Mandatory = $true)]
    [string]$TaskPath,

    [Parameter(Mandatory = $false)]
    [string]$RegistryPath = ""
)

$Root = Split-Path $PSScriptRoot -Parent
$AdapterScript = Join-Path $Root "Scripts\Invoke-PDAModel.ps1"
$FabricScript = Join-Path $Root "Scripts\Invoke-PDAFabricPattern.ps1"
. (Join-Path $Root "Scripts\PDA_OutputParsing.ps1")
if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $Root "Scripts\PDA_WorkerRegistry.json"
}

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

function Get-PDAWorkerDefaultPattern {
    param([Parameter(Mandatory = $true)][string]$WorkerName)

    if (-not (Test-Path -Path $RegistryPath -PathType Leaf)) {
        return ""
    }

    try {
        $Registry = Get-Content -Path $RegistryPath -Raw | ConvertFrom-Json
    }
    catch {
        return ""
    }

    $WorkerEntry = @($Registry.workers | Where-Object { [string]$_.worker_name -eq $WorkerName } | Select-Object -First 1)
    if ($WorkerEntry.Count -eq 0) {
        return ""
    }

    $WorkerEntry = $WorkerEntry[0]
    if ($WorkerEntry.PSObject.Properties.Name -contains "default_pattern" -and -not [string]::IsNullOrWhiteSpace([string]$WorkerEntry.default_pattern)) {
        return [string]$WorkerEntry.default_pattern
    }

    return ""
}

function Invoke-PDAFabricPromptRender {
    param(
        [Parameter(Mandatory = $false)]
        [string]$PatternName,

        [Parameter(Mandatory = $true)]
        [string]$WorkerName,

        [Parameter(Mandatory = $true)]
        [string]$TaskType,

        [Parameter(Mandatory = $true)]
        [string]$Sensitivity,

        [Parameter(Mandatory = $true)]
        [string]$PromptText,

        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $false)]
        [string]$SourcePath = ""
    )

    if ([string]::IsNullOrWhiteSpace($PatternName)) {
        return [pscustomobject]@{
            used = $false
            status = "not_configured"
            pattern_name = ""
            pattern_path = ""
            pattern_category = ""
            rendered_prompt = ""
            error = ""
        }
    }

    if (-not (Test-Path -Path $FabricScript -PathType Leaf)) {
        return [pscustomobject]@{
            used = $false
            status = "missing_renderer"
            pattern_name = $PatternName
            pattern_path = ""
            pattern_category = ""
            rendered_prompt = ""
            error = "Fabric renderer not found."
        }
    }

    $VariablesJson = @{
        worker_name = $WorkerName
        task_type = $TaskType
        sensitivity = $Sensitivity
        classification = $Category
        source_path = $SourcePath
        content_input = $PromptText
        content = $PromptText
        default_pattern = $PatternName
    } | ConvertTo-Json -Depth 8 -Compress

    try {
        $RawRender = & pwsh -NoProfile -File $FabricScript -PatternName $PatternName -ContentInput $PromptText -VariablesJson $VariablesJson -AsJson 2>&1
        $JsonText = [string]($RawRender -join "`n")
        $Render = ConvertFrom-PDAMixedJson -Text $JsonText -SourceName "Fabric renderer output"

        if ($Render.status -eq "success") {
            return [pscustomobject]@{
                used = $true
                status = [string]$Render.status
                pattern_name = [string]$Render.pattern_name
                pattern_path = [string]$Render.pattern_path
                pattern_category = [string]$Render.pattern_category
                rendered_prompt = [string]$Render.rendered_prompt
                error = ""
            }
        }

        return [pscustomobject]@{
            used = $false
            status = [string]$Render.status
            pattern_name = [string]$Render.pattern_name
            pattern_path = [string]$Render.pattern_path
            pattern_category = [string]$Render.pattern_category
            rendered_prompt = ""
            error = [string]$Render.error
        }
    }
    catch {
        return [pscustomobject]@{
            used = $false
            status = "error"
            pattern_name = $PatternName
            pattern_path = ""
            pattern_category = ""
            rendered_prompt = ""
            error = $_.Exception.Message
        }
    }
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

$Task = Get-Content $TaskPath -Raw | ConvertFrom-Json

$TaskId = if ($Task.task_id) { [string]$Task.task_id } else { [guid]::NewGuid().ToString() }
$CommandText = if ($Task.command) { [string]$Task.command } else { "/review" }
$CategoryText = if ($Task.classification) { [string]$Task.classification } elseif ($Task.category) { [string]$Task.category } else { "category_1" }
$RoutingCategory = if ([string]$CategoryText -eq "category_2") { "category_2" } else { "category_1" }
$RoutingSensitivity = if ($RoutingCategory -eq "category_2") { "restricted_local" } else { "standard" }
$SourcePath = if ($Task.source_path) { [string]$Task.source_path } else { "" }
$MarkdownOutputFolder = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Reviews"
$ResultPath = Join-Path $Root "PDA-Tasks\results\$TaskId-result.json"
$DefaultPattern = Get-PDAWorkerDefaultPattern -WorkerName "review-worker"

function New-PDAReviewFailure {
    param(
        [string]$Reason,
        [string]$OutputType = "error"
    )

    $FailureResult = [ordered]@{
        task_id        = $TaskId
        worker         = "review-worker"
        status         = "failed"
        classification = $CategoryText
        input_summary  = $CommandText
        output_type    = $OutputType
        output         = @{
            error = $Reason
        }
        confidence     = 0
        warnings       = @("Review worker execution failed.")
        next_worker    = ""
        saved_path     = ""
        result_path    = $ResultPath
    }

    try {
        Write-PDAWorkerResultArtifact -TaskId $TaskId -ResultObject $FailureResult | Out-Null
        Register-PDAWorkerArtifact -ArtifactPath $ResultPath -TaskId $TaskId -WorkerName "review-worker" -Command $CommandText -Category $CategoryText -ArtifactType "worker_result_json" -Summary "Review worker canonical result contract"
    }
    catch {
        Write-Warning "Failed to write review worker failure result artifact: $($_.Exception.Message)"
    }

    return ($FailureResult | ConvertTo-Json -Depth 20)
}

if ([string]::IsNullOrWhiteSpace($SourcePath) -or -not (Test-Path -Path $SourcePath -PathType Leaf)) {
    New-PDAReviewFailure -Reason "No valid source_path provided." -OutputType "error"
    return
}

$DraftContent = Get-Content $SourcePath -Raw

$Prompt = @"
You are review-worker inside the PDA ecosystem.

Your job:
Review an operational report draft for:

- unsupported claims
- hallucinations
- missing information
- formatting issues
- weak analytical reasoning
- unclear wording
- missing caveats
- operational inconsistencies

Requirements:
- concise operational wording
- markdown format
- preserve uncertainty
- do not invent facts
- clearly separate:
  - confirmed issues
  - possible concerns
  - recommendations

Return markdown only.

Draft Report:

$DraftContent
"@

$FabricRender = Invoke-PDAFabricPromptRender -PatternName $DefaultPattern -WorkerName "review-worker" -TaskType "review" -Sensitivity $RoutingSensitivity -PromptText $Prompt -Category $CategoryText -SourcePath $SourcePath
$PromptSource = "legacy"
if ($FabricRender.used -and -not [string]::IsNullOrWhiteSpace([string]$FabricRender.rendered_prompt)) {
    $Prompt = [string]$FabricRender.rendered_prompt
    $PromptSource = "fabric"
}
elseif (-not [string]::IsNullOrWhiteSpace($DefaultPattern)) {
    $PromptSource = "fabric_fallback"
}

try {
    $RawInvocation = & pwsh -NoProfile -File $AdapterScript `
        -WorkerName "review-worker" `
        -TaskType "review" `
        -Command "/review" `
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
        throw "Review model returned empty content."
    }

    New-Item -ItemType Directory -Force -Path $MarkdownOutputFolder | Out-Null
    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $MarkdownPath = Join-Path $MarkdownOutputFolder "review-output-$Timestamp.md"
    $Content | Set-Content -Path $MarkdownPath -Encoding UTF8

    $TaskCommand = if ($Task.command) { [string]$Task.command } else { $CommandText }
    $ResultObject = [ordered]@{
        task_id        = $TaskId
        worker         = "review-worker"
        status         = "success"
        classification = $CategoryText
        input_summary  = $TaskCommand
        output_type    = "review_markdown"
        output         = @{
            markdown_path = $MarkdownPath
            content       = $Content
            model_route   = ConvertTo-PDAHashtable -Value $Invocation.routing
            model_response = ConvertTo-PDAHashtable -Value $Invocation.response
            fabric        = @{
                default_pattern = $DefaultPattern
                used = [bool]$FabricRender.used
                render_status = [string]$FabricRender.status
                pattern_path = [string]$FabricRender.pattern_path
                pattern_category = [string]$FabricRender.pattern_category
                prompt_source = $PromptSource
                error = [string]$FabricRender.error
            }
            model_request = @{
                prompt = $Prompt
                prompt_source = $PromptSource
                worker_name = "review-worker"
                task_type = "review"
                sensitivity = $RoutingSensitivity
                category = $RoutingCategory
            }
        }
        confidence     = 0.90
        warnings       = @()
        next_worker    = ""
        saved_path     = $MarkdownPath
        result_path    = $ResultPath
    }

    Write-PDAWorkerResultArtifact -TaskId $TaskId -ResultObject $ResultObject | Out-Null
    Register-PDAWorkerArtifact -ArtifactPath $MarkdownPath -TaskId $TaskId -WorkerName "review-worker" -Command $TaskCommand -Category $CategoryText -ArtifactType "review_markdown" -Summary "Review worker markdown output"
    Register-PDAWorkerArtifact -ArtifactPath $ResultPath -TaskId $TaskId -WorkerName "review-worker" -Command $TaskCommand -Category $CategoryText -ArtifactType "worker_result_json" -Summary "Review worker canonical result contract"

    $ResultObject | ConvertTo-Json -Depth 20
}
catch {
    New-PDAReviewFailure -Reason $_.Exception.Message -OutputType "error"
}
