[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TaskPath,

    [Parameter(Mandatory = $false)]
    [string]$RegistryPath = ""
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ResearchSourcesScript = Join-Path $PSScriptRoot "Get-COOPERResearchSources.ps1"
$ResearchOutputFolder = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Research"
$ResultsFolder = Join-Path $Root "PDA-Tasks\results"

if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $Root "Scripts\PDA_WorkerRegistry.json"
}

if (Test-Path -LiteralPath $ResearchSourcesScript -PathType Leaf) {
    . $ResearchSourcesScript
}
else {
    throw "Research source helper missing: $ResearchSourcesScript"
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

function Write-PDAWorkerResultArtifact {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [Parameter(Mandatory = $true)]
        [object]$ResultObject
    )

    New-Item -ItemType Directory -Force -Path $ResultsFolder | Out-Null
    $ResultPath = Join-Path $ResultsFolder "$TaskId-result.json"
    $ResultObject | ConvertTo-Json -Depth 20 | Set-Content -Path $ResultPath -Encoding UTF8
    return $ResultPath
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

function Test-PDAResearchDisclaimerText {
    param([Parameter(Mandatory = $true)][string]$Text)

    return [bool](
        $Text -match '(?i)cannot perform real-time research|knowledge cutoff|if you provide source material|as an ai|i can''t browse|i cannot browse|unable to access the web'
    )
}

function New-PDAResearchMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$RequestText,

        [Parameter(Mandatory = $true)]
        [string]$RetrievedAt,

        [Parameter(Mandatory = $true)]
        [object[]]$Sources
    )

    $CategoryMap = @{}
    foreach ($Source in $Sources) {
        $Category = if ($Source.PSObject.Properties.Name -contains "category" -and -not [string]::IsNullOrWhiteSpace([string]$Source.category)) {
            [string]$Source.category
        }
        else {
            "General"
        }

        if (-not $CategoryMap.ContainsKey($Category)) {
            $CategoryMap[$Category] = @()
        }

        $CategoryMap[$Category] += $Source
    }

    $SourceSummary = @($Sources | ForEach-Object {
        "- [{0}]({1}) - {2}" -f [string]$_.title, [string]$_.url, [string]$_.excerpt
    })

    $CategorizedFindings = @()
    foreach ($Category in ($CategoryMap.Keys | Sort-Object)) {
        $CategorizedFindings += "### $Category"
        foreach ($Source in @($CategoryMap[$Category])) {
            $Snippet = if ([string]::IsNullOrWhiteSpace([string]$Source.excerpt)) { [string]$Source.purpose } else { [string]$Source.excerpt }
            $CategorizedFindings += "- {0}: {1}" -f [string]$Source.title, $Snippet
        }
        $CategorizedFindings += ""
    }

    $SourceList = @($Sources | ForEach-Object {
        "- [{0}]({1})" -f [string]$_.title, [string]$_.url
    })

    $SummaryLines = @()
    $SummaryLines += "The request was answered using $($Sources.Count) approved official source(s)."
    $SummaryLines += "Primary topics covered: $((@($Sources | ForEach-Object { [string]$_.category }) | Select-Object -Unique) -join ', ')."

    return @(
        "# WF-001 Research Summary"
        ""
        "## Title"
        $Title
        ""
        "## Request"
        $RequestText
        ""
        "## Retrieved At"
        $RetrievedAt
        ""
        "## Source Summary"
        @($SourceSummary)
        ""
        "## Categorized Findings"
        @($CategorizedFindings)
        "## Synthesis"
        @($SummaryLines)
        ""
        "## Sources"
        @($SourceList)
        ""
        "## Limitations"
        "- Source collection is limited to approved official documentation."
        "- Findings are limited to the retrieved source set."
    ) -join "`r`n"
}

function New-PDAResearchFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [Parameter(Mandatory = $true)]
        [string]$CommandText,

        [Parameter(Mandatory = $true)]
        [string]$CategoryText,

        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    $FailureResult = [ordered]@{
        task_id        = $TaskId
        worker         = "research-worker"
        status         = "failed"
        classification = $CategoryText
        input_summary  = $CommandText
        output_type    = "error"
        reason         = $Reason
        output         = @{
            error = $Reason
            source_count = 0
            sources = @()
        }
        confidence     = 0
        warnings       = @("Research worker execution failed.")
        next_worker    = ""
        saved_path     = ""
        result_path    = ""
        source_of_truth = "Scripts/Invoke-PDAResearchWorker.ps1"
    }

    return $FailureResult
}

$Task = Get-Content $TaskPath -Raw | ConvertFrom-Json

$TaskId = if ($Task.task_id) { [string]$Task.task_id } else { [guid]::NewGuid().ToString() }
$CommandText = if ($Task.command) { [string]$Task.command } elseif ($Task.target) { [string]$Task.target } else { "/research" }
$CategoryText = if ($Task.classification) { [string]$Task.classification } elseif ($Task.category) { [string]$Task.category } else { "category_3" }
$SourcePath = if ($Task.source_path) { [string]$Task.source_path } else { "" }
$TargetText = if ($Task.target) { [string]$Task.target } else { "" }
$SourceText = if (-not [string]::IsNullOrWhiteSpace($SourcePath) -and (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    Get-Content -LiteralPath $SourcePath -Raw
}
else {
    $TargetText
}

if ([string]::IsNullOrWhiteSpace($SourceText)) {
    $Failure = New-PDAResearchFailure -TaskId $TaskId -CommandText $CommandText -CategoryText $CategoryText -Reason "No valid source_path or target provided."
    $Failure.result_path = Write-PDAWorkerResultArtifact -TaskId $TaskId -ResultObject $Failure
    Register-PDAWorkerArtifact -ArtifactPath $Failure.result_path -TaskId $TaskId -WorkerName "research-worker" -Command $CommandText -Category $CategoryText -ArtifactType "worker_result_json" -Summary "Research worker canonical result contract"
    ($Failure | ConvertTo-Json -Depth 20)
    return
}

$ResearchRequest = [string]$SourceText
$SourcesResult = Get-COOPERResearchSources -RequestText $ResearchRequest -Root $Root -MaxSources 5

if ($null -eq $SourcesResult -or [string]$SourcesResult.status -ne "pass" -or [int]$SourcesResult.source_count -le 0) {
    $Reason = if ($SourcesResult -and $SourcesResult.PSObject.Properties.Name -contains "reason" -and -not [string]::IsNullOrWhiteSpace([string]$SourcesResult.reason)) {
        [string]$SourcesResult.reason
    }
    else {
        "no_sources_collected"
    }

    $Failure = New-PDAResearchFailure -TaskId $TaskId -CommandText $CommandText -CategoryText $CategoryText -Reason $Reason
    $Failure.output.source_catalog_path = if ($SourcesResult -and $SourcesResult.PSObject.Properties.Name -contains "source_catalog_path") { [string]$SourcesResult.source_catalog_path } else { "" }
    $Failure.output.retrieved_at = if ($SourcesResult -and $SourcesResult.PSObject.Properties.Name -contains "retrieved_at") { [string]$SourcesResult.retrieved_at } else { (Get-Date).ToUniversalTime().ToString("o") }
    $Failure.result_path = Write-PDAWorkerResultArtifact -TaskId $TaskId -ResultObject $Failure
    Register-PDAWorkerArtifact -ArtifactPath $Failure.result_path -TaskId $TaskId -WorkerName "research-worker" -Command $CommandText -Category $CategoryText -ArtifactType "worker_result_json" -Summary "Research worker canonical result contract"
    ($Failure | ConvertTo-Json -Depth 20)
    return
}

$RetrievedAt = [string]$SourcesResult.retrieved_at
$Sources = @($SourcesResult.sources)
$Title = "WF-001 Research Summary"
$MarkdownContent = New-PDAResearchMarkdown -Title $Title -RequestText $ResearchRequest -RetrievedAt $RetrievedAt -Sources $Sources

if (Test-PDAResearchDisclaimerText -Text $MarkdownContent) {
    $Failure = New-PDAResearchFailure -TaskId $TaskId -CommandText $CommandText -CategoryText $CategoryText -Reason "disclaimer_only_output"
    $Failure.output.source_count = $Sources.Count
    $Failure.output.sources = @($Sources | ForEach-Object { ConvertTo-PDAHashtable -Value $_ })
    $Failure.output.retrieved_at = $RetrievedAt
    $Failure.result_path = Write-PDAWorkerResultArtifact -TaskId $TaskId -ResultObject $Failure
    Register-PDAWorkerArtifact -ArtifactPath $Failure.result_path -TaskId $TaskId -WorkerName "research-worker" -Command $CommandText -Category $CategoryText -ArtifactType "worker_result_json" -Summary "Research worker canonical result contract"
    ($Failure | ConvertTo-Json -Depth 20)
    return
}

New-Item -ItemType Directory -Force -Path $ResearchOutputFolder | Out-Null
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$MarkdownPath = Join-Path $ResearchOutputFolder "research-output-$Timestamp.md"
$MarkdownContent | Set-Content -LiteralPath $MarkdownPath -Encoding UTF8

$TaskCommand = if ($Task.command) { [string]$Task.command } else { $CommandText }
$ResultObject = [ordered]@{
    task_id        = $TaskId
    worker         = "research-worker"
    status         = "success"
    classification = $CategoryText
    input_summary  = $TaskCommand
    output_type    = "research_markdown"
    output         = @{
        markdown_path = $MarkdownPath
        content       = $MarkdownContent
        source_count  = $Sources.Count
        retrieved_at  = $RetrievedAt
        sources       = @($Sources | ForEach-Object { ConvertTo-PDAHashtable -Value $_ })
        source_catalog_path = [string]$SourcesResult.source_catalog_path
        source_of_truth = "Scripts/Get-COOPERResearchSources.ps1"
    }
    confidence     = 0.94
    warnings       = @()
    next_worker    = "review-worker"
    saved_path     = $MarkdownPath
    result_path    = ""
    source_of_truth = "Scripts/Invoke-PDAResearchWorker.ps1"
}

$ResultObject.result_path = Write-PDAWorkerResultArtifact -TaskId $TaskId -ResultObject $ResultObject
Register-PDAWorkerArtifact -ArtifactPath $MarkdownPath -TaskId $TaskId -WorkerName "research-worker" -Command $TaskCommand -Category $CategoryText -ArtifactType "research_markdown" -Summary "Research worker markdown output"
Register-PDAWorkerArtifact -ArtifactPath $ResultObject.result_path -TaskId $TaskId -WorkerName "research-worker" -Command $TaskCommand -Category $CategoryText -ArtifactType "worker_result_json" -Summary "Research worker canonical result contract"

$ResultObject | ConvertTo-Json -Depth 20
