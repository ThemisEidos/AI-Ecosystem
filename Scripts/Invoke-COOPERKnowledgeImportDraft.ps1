[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RequestText,

    [Parameter(Mandatory = $true)]
    [object]$ResearchResult,

    [Parameter(Mandatory = $false)]
    [object]$ResearchReview = $null,

    [Parameter(Mandatory = $false)]
    [switch]$Approved,

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$RouterScript = Join-Path $PSScriptRoot "Invoke-COOPERTool.ps1"
$ApprovalScript = Join-Path $PSScriptRoot "Resolve-COOPERApproval.ps1"
$WorkbenchScript = Join-Path $PSScriptRoot "Invoke-COOPERWorkbench.ps1"
$ReviewScript = Join-Path $PSScriptRoot "Resolve-COOPERWorkflowReview.ps1"
$MemoryScript = Join-Path $PSScriptRoot "Update-COOPERProjectMemory.ps1"
$SkillsScript = Join-Path $PSScriptRoot "Update-COOPERWorkflowSkills.ps1"
$EvidenceWriterScript = Join-Path $PSScriptRoot "Write-COOPERWorkflowEvidence.ps1"

function ConvertTo-COOPERHashtable {
    param([Parameter(Mandatory = $true)]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [hashtable] -or $Value -is [System.Collections.IDictionary]) {
        $Copy = @{}
        foreach ($Key in $Value.Keys) {
            $Copy[$Key] = ConvertTo-COOPERHashtable -Value $Value[$Key]
        }
        return $Copy
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $List = @()
        foreach ($Item in $Value) {
            $List += ,(ConvertTo-COOPERHashtable -Value $Item)
        }
        return $List
    }

    if ($Value -is [psobject] -and $Value.PSObject.Properties.Name.Count -gt 0) {
        $Copy = @{}
        foreach ($Prop in $Value.PSObject.Properties) {
            $Copy[$Prop.Name] = ConvertTo-COOPERHashtable -Value $Prop.Value
        }
        return $Copy
    }

    return $Value
}

function Get-COOPERKnowledgeImportDraftPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $DraftFolder = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Collection Imports"
    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    return [pscustomobject]@{
        folder = $DraftFolder
        path = Join-Path $DraftFolder "linux-infrastructure-popos-import-$Timestamp.md"
    }
}

function New-COOPERKnowledgeImportMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CollectionName,

        [Parameter(Mandatory = $true)]
        [string]$Topic,

        [Parameter(Mandatory = $true)]
        [string]$ResearchArtifactPath,

        [Parameter(Mandatory = $true)]
        [object[]]$Sources,

        [Parameter(Mandatory = $true)]
        [string]$SummaryText
    )

    $RetrievedAt = (Get-Date).ToUniversalTime().ToString("o")
    $SourceList = @($Sources | ForEach-Object {
        "- [{0}]({1})" -f [string]$_.title, [string]$_.url
    })

    $CollectionEntries = @()
    foreach ($Source in $Sources) {
        $CollectionEntries += "### $([string]$Source.title)"
        $CollectionEntries += "Source URL: $([string]$Source.url)"
        $CollectionEntries += "Category: $([string]$Source.category)"
        $CollectionEntries += "Use in Collection: Reference material for the $CollectionName knowledge collection."
        $CollectionEntries += "Key Notes: $([string]$Source.purpose)"
        $CollectionEntries += ""
    }

    return @(
        "# Knowledge Collection Import Draft"
        ""
        "## Collection"
        $CollectionName
        ""
        "## Topic"
        $Topic
        ""
        "## Source Research Artifact"
        $ResearchArtifactPath
        ""
        "## Retrieved At"
        $RetrievedAt
        ""
        "## Import Status"
        "Draft only. Not imported."
        ""
        "## Summary"
        $SummaryText
        ""
        "## Collection Entries"
        @($CollectionEntries)
        "## Source List"
        @($SourceList)
        ""
        "## Limitations"
        "- This draft is based only on the reviewed WF-001 research artifact."
        "- This draft is for manual collection preparation only."
    ) -join "`r`n"
}

if ($null -eq $ResearchReview) {
    return [pscustomobject]@{
        success = $false
        workflow_id = "WF-006"
        research_summary_path = ""
        import_draft_path = ""
        routed_tool = $null
        approval_decision = $null
        workbench_result = $null
        workflow_review = $null
        response_text = "WF-006 requires a passed WF-001 review."
        reason = "WF-006 requires a passed WF-001 review."
        source_of_truth = "Scripts/Invoke-COOPERKnowledgeImportDraft.ps1"
    }
}

$ResearchReviewPassed = $false
if ($ResearchReview.PSObject.Properties.Name -contains "review_passed") {
    $ResearchReviewPassed = [bool]$ResearchReview.review_passed
}
elseif ($ResearchReview.PSObject.Properties.Name -contains "status" -and [string]$ResearchReview.status -eq "pass") {
    $ResearchReviewPassed = $true
}

if (-not $ResearchReviewPassed) {
    return [pscustomobject]@{
        success = $false
        workflow_id = "WF-006"
        research_summary_path = if ($ResearchResult.PSObject.Properties.Name -contains "saved_path") { [string]$ResearchResult.saved_path } else { "" }
        import_draft_path = ""
        routed_tool = $null
        approval_decision = $null
        workbench_result = $null
        workflow_review = $ResearchReview
        response_text = "WF-006 requires a passed WF-001 review."
        reason = "WF-001 review did not pass."
        source_of_truth = "Scripts/Invoke-COOPERKnowledgeImportDraft.ps1"
    }
}

if ($ResearchResult.PSObject.Properties.Name -contains "output" -and $ResearchResult.output) {
    $Sources = @()
    if ($ResearchResult.output.PSObject.Properties.Name -contains "sources") {
        $Sources = @($ResearchResult.output.sources)
    }
}
else {
    $Sources = @()
}

if (@($Sources).Count -eq 0) {
    return [pscustomobject]@{
        success = $false
        workflow_id = "WF-006"
        research_summary_path = if ($ResearchResult.PSObject.Properties.Name -contains "saved_path") { [string]$ResearchResult.saved_path } else { "" }
        import_draft_path = ""
        routed_tool = $null
        approval_decision = $null
        workbench_result = $null
        workflow_review = $null
        response_text = "WF-006 requires source URLs from the reviewed research artifact."
        reason = "no_source_urls"
        source_of_truth = "Scripts/Invoke-COOPERKnowledgeImportDraft.ps1"
    }
}

$ImportPathInfo = Get-COOPERKnowledgeImportDraftPath -Root $Root
$ImportDraftPath = [string]$ImportPathInfo.path
$ResearchSummaryPath = if ($ResearchResult.PSObject.Properties.Name -contains "saved_path") { [string]$ResearchResult.saved_path } elseif ($ResearchResult.PSObject.Properties.Name -contains "output" -and $ResearchResult.output -and $ResearchResult.output.PSObject.Properties.Name -contains "markdown_path") { [string]$ResearchResult.output.markdown_path } else { "" }
$Topic = "Pop!_OS Official Documentation"
$CollectionName = "Linux & Infrastructure"
$SummaryText = "This draft packages the reviewed WF-001 research artifact for manual collection ingestion without performing any automatic Workspace import."

$MarkdownContent = New-COOPERKnowledgeImportMarkdown -CollectionName $CollectionName -Topic $Topic -ResearchArtifactPath $ResearchSummaryPath -Sources $Sources -SummaryText $SummaryText

$RoutedTool = & $RouterScript -ToolId "obsidian_note_writer" -Workshop "Open Workshop" -WorkshopMode "Open Workshop" -DryRun
if ([string]$RoutedTool.status -ne "pass") {
    return [pscustomobject]@{
        success = $false
        workflow_id = "WF-006"
        research_summary_path = $ResearchSummaryPath
        import_draft_path = $ImportDraftPath
        routed_tool = $RoutedTool
        approval_decision = $null
        workbench_result = $null
        workflow_review = $null
        response_text = [string]$RoutedTool.blocked_reason
        reason = [string]$RoutedTool.blocked_reason
        source_of_truth = "Scripts/Invoke-COOPERKnowledgeImportDraft.ps1"
    }
}

$ApprovalDecision = & $ApprovalScript -RoutedToolResult $RoutedTool -Approved:$Approved
if ([bool]$ApprovalDecision.blocked -eq $true -or [bool]$ApprovalDecision.allowed -ne $true -or [bool]$ApprovalDecision.execution_authorized -ne $true) {
    return [pscustomobject]@{
        success = $false
        workflow_id = "WF-006"
        research_summary_path = $ResearchSummaryPath
        import_draft_path = $ImportDraftPath
        routed_tool = $RoutedTool
        approval_decision = $ApprovalDecision
        workbench_result = $null
        workflow_review = $null
        response_text = [string]$ApprovalDecision.reason
        reason = [string]$ApprovalDecision.reason
        source_of_truth = "Scripts/Invoke-COOPERKnowledgeImportDraft.ps1"
    }
}

$ApprovalDecision | Add-Member -NotePropertyName note_path -NotePropertyValue $ImportDraftPath -Force
$ApprovalDecision | Add-Member -NotePropertyName markdown_content -NotePropertyValue $MarkdownContent -Force

$WorkbenchResult = & $WorkbenchScript -ApprovalDecision $ApprovalDecision

if (-not (Test-Path -LiteralPath $ReviewScript -PathType Leaf)) {
    return [pscustomobject]@{
        success = $false
        workflow_id = "WF-006"
        research_summary_path = $ResearchSummaryPath
        import_draft_path = $ImportDraftPath
        routed_tool = $RoutedTool
        approval_decision = $ApprovalDecision
        workbench_result = $WorkbenchResult
        workflow_review = $null
        response_text = "Workflow review script is unavailable."
        reason = "Workflow review script is unavailable."
        source_of_truth = "Scripts/Invoke-COOPERKnowledgeImportDraft.ps1"
    }
}

$WorkflowReview = & $ReviewScript -WorkflowId "WF-006" -WorkflowResult $([pscustomobject]@{
    success = [bool]$WorkbenchResult.success
    workflow_id = "WF-006"
    import_draft_path = $ImportDraftPath
    research_summary_path = $ResearchSummaryPath
    source_research_artifact_path = $ResearchSummaryPath
    source_count = @($Sources).Count
    source_urls = @($Sources | ForEach-Object { [string]$_.url })
    collection_name = $CollectionName
    approval_decision = $ApprovalDecision
    workbench_result = $WorkbenchResult
    response_text = if ($WorkbenchResult.success) { "Created knowledge collection import draft at $ImportDraftPath." } else { [string]$WorkbenchResult.reason }
    reason = [string]$WorkbenchResult.reason
    output_type = "markdown_file"
    result_artifact_path = $ImportDraftPath
}) -RequestText $RequestText -ExpectedOutputType "markdown_file" -ExpectedOutputPath $ImportDraftPath -ExpectedContent $RequestText

if (-not $WorkflowReview -or [string]$WorkflowReview.status -ne "pass") {
    return [pscustomobject]@{
        success = $false
        workflow_id = "WF-006"
        research_summary_path = $ResearchSummaryPath
        import_draft_path = $ImportDraftPath
        routed_tool = $RoutedTool
        approval_decision = $ApprovalDecision
        workbench_result = $WorkbenchResult
        workflow_review = $WorkflowReview
        response_text = if ($WorkflowReview -and $WorkflowReview.PSObject.Properties.Name -contains "issues" -and $WorkflowReview.issues) { [string]($WorkflowReview.issues -join "; ") } else { "Workflow review failed." }
        reason = if ($WorkflowReview -and $WorkflowReview.PSObject.Properties.Name -contains "issues" -and $WorkflowReview.issues) { [string]($WorkflowReview.issues -join "; ") } else { "Workflow review failed." }
        source_of_truth = "Scripts/Invoke-COOPERKnowledgeImportDraft.ps1"
    }
}

if (Test-Path -LiteralPath $MemoryScript -PathType Leaf) {
    try {
        $null = & $MemoryScript -WorkflowId "WF-006" -ReviewResult $WorkflowReview -RequestText $RequestText -OutputPath $ImportDraftPath
    }
    catch {}
}

if (Test-Path -LiteralPath $SkillsScript -PathType Leaf) {
    try {
        $ExampleOutput = [System.IO.Path]::GetFileName($ImportDraftPath)
        $null = & $SkillsScript -WorkflowId "WF-006" -ReviewResult $WorkflowReview -ExampleRequest $RequestText -ExampleOutput $ExampleOutput -SkillName "Knowledge Collection Import Draft"
    }
    catch {}
}

if (-not (Test-Path -LiteralPath $EvidenceWriterScript -PathType Leaf)) {
    throw "Workflow evidence writer is unavailable."
}

$EvidenceExecutionId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ")
$EvidenceResult = & $EvidenceWriterScript `
    -Root $Root `
    -RecordType "completion" `
    -WorkshopId "open" `
    -WorkflowId "WF-006" `
    -WorkflowName "Knowledge Collection Import Draft" `
    -ExecutionId $EvidenceExecutionId `
    -Status "pass" `
    -CompletionTime (Get-Date).ToUniversalTime().ToString("o") `
    -ApprovalId "" `
    -ArtifactPaths @($ImportDraftPath) `
    -ReviewStatus "pass" `
    -UserAccepted:$false `
    -Notes "WF-006 knowledge collection import draft completed; review passed."

return [pscustomobject]@{
    success = $true
    workflow_id = "WF-006"
    research_summary_path = $ResearchSummaryPath
    import_draft_path = $ImportDraftPath
    evidence_path = [string]$EvidenceResult.path
    routed_tool = $RoutedTool
    approval_decision = $ApprovalDecision
    workbench_result = $WorkbenchResult
    workflow_review = $WorkflowReview
    response_text = "Created knowledge collection import draft at $ImportDraftPath."
    reason = [string]$WorkbenchResult.reason
    source_of_truth = "Scripts/Invoke-COOPERKnowledgeImportDraft.ps1"
}
