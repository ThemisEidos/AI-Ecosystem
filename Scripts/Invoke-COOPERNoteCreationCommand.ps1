[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Text,

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

function New-COOPERNoteMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$SourceText
    )

    $Now = (Get-Date).ToUniversalTime().ToString("o")

    return @(
        "# $Title"
        ""
        "- Workflow: WF-005"
        "- Created: $Now"
        "- Source: conversational request"
        ""
        "## Request"
        $SourceText
        ""
        "## Notes"
        "- Created by the governed COOPER note-creation workflow."
        "- Approval was required before the write."
    ) -join "`r`n"
}

function Get-COOPERNotePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    $Slug = ([regex]::Replace($Title.Trim().ToLowerInvariant(), '[^a-z0-9]+', '-')).Trim('-')
    if ([string]::IsNullOrWhiteSpace($Slug)) {
        $Slug = "wf-005-note-creation"
    }

    return (Join-Path $Root ("Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Drafts\{0}.md" -f $Slug))
}

$Title = "WF-005 Note Creation"
$MarkdownContent = New-COOPERNoteMarkdown -Title $Title -SourceText $Text
$NotePath = Get-COOPERNotePath -Root $Root -Title $Title

$RoutedTool = & $RouterScript -ToolId "obsidian_note_writer" -Workshop "Open Workshop" -WorkshopMode "Open Workshop" -DryRun
if ([string]$RoutedTool.status -ne "pass") {
    return [pscustomobject]@{
        success = $false
        workflow_id = "WF-005"
        tool_id = "obsidian_note_writer"
        note_path = $NotePath
        routed_tool = $RoutedTool
        approval_decision = $null
        workbench_result = $null
        response_text = [string]$RoutedTool.blocked_reason
        reason = [string]$RoutedTool.blocked_reason
        source_of_truth = "Scripts/Invoke-COOPERNoteCreationCommand.ps1"
    }
}

$ApprovalDecision = & $ApprovalScript -RoutedToolResult $RoutedTool -Approved:$Approved
if ([bool]$ApprovalDecision.blocked -eq $true -or [bool]$ApprovalDecision.allowed -ne $true -or [bool]$ApprovalDecision.execution_authorized -ne $true) {
    return [pscustomobject]@{
        success = $false
        workflow_id = "WF-005"
        tool_id = "obsidian_note_writer"
        note_path = $NotePath
        routed_tool = $RoutedTool
        approval_decision = $ApprovalDecision
        workbench_result = $null
        response_text = [string]$ApprovalDecision.reason
        reason = [string]$ApprovalDecision.reason
        source_of_truth = "Scripts/Invoke-COOPERNoteCreationCommand.ps1"
    }
}

$ApprovalDecision | Add-Member -NotePropertyName note_path -NotePropertyValue $NotePath -Force
$ApprovalDecision | Add-Member -NotePropertyName markdown_content -NotePropertyValue $MarkdownContent -Force

$WorkbenchResult = & $WorkbenchScript -ApprovalDecision $ApprovalDecision

if (-not (Test-Path -LiteralPath $ReviewScript -PathType Leaf)) {
    return [pscustomobject]@{
        success = $false
        workflow_id = "WF-005"
        tool_id = "obsidian_note_writer"
        note_path = $NotePath
        routed_tool = $RoutedTool
        approval_decision = $ApprovalDecision
        workbench_result = $WorkbenchResult
        workflow_review = $null
        response_text = "Workflow review script is unavailable."
        reason = "Workflow review script is unavailable."
        source_of_truth = "Scripts/Invoke-COOPERNoteCreationCommand.ps1"
    }
}

$WorkflowReview = & $ReviewScript -WorkflowId "WF-005" -WorkflowResult $([pscustomobject]@{
    success = [bool]$WorkbenchResult.success
    workflow_id = "WF-005"
    note_path = $NotePath
    approval_decision = $ApprovalDecision
    workbench_result = $WorkbenchResult
    response_text = if ($WorkbenchResult.success) { "Created note at $NotePath." } else { [string]$WorkbenchResult.reason }
    reason = [string]$WorkbenchResult.reason
    output_type = "markdown_file"
    result_artifact_path = $NotePath
}) -RequestText $Text -ExpectedOutputType "markdown_file" -ExpectedOutputPath $NotePath -ExpectedContent $Text

if (-not $WorkflowReview -or [string]$WorkflowReview.status -ne "pass") {
    if (Test-Path -LiteralPath $MemoryScript -PathType Leaf) {
        try {
            $null = & $MemoryScript -WorkflowId "WF-005" -ReviewResult $WorkflowReview -RequestText $Text -OutputPath $NotePath
        }
        catch {}
    }

    return [pscustomobject]@{
        success = $false
        workflow_id = "WF-005"
        tool_id = "obsidian_note_writer"
        note_path = $NotePath
        routed_tool = $RoutedTool
        approval_decision = $ApprovalDecision
        workbench_result = $WorkbenchResult
        workflow_review = $WorkflowReview
        response_text = if ($WorkflowReview -and $WorkflowReview.PSObject.Properties.Name -contains "issues" -and $WorkflowReview.issues) { [string]($WorkflowReview.issues -join "; ") } else { "Workflow review failed." }
        reason = if ($WorkflowReview -and $WorkflowReview.PSObject.Properties.Name -contains "issues" -and $WorkflowReview.issues) { [string]($WorkflowReview.issues -join "; ") } else { "Workflow review failed." }
        source_of_truth = "Scripts/Invoke-COOPERNoteCreationCommand.ps1"
    }
}

if (Test-Path -LiteralPath $MemoryScript -PathType Leaf) {
    try {
        $null = & $MemoryScript -WorkflowId "WF-005" -ReviewResult $WorkflowReview -RequestText $Text -OutputPath $NotePath
    }
    catch {}
}

if (Test-Path -LiteralPath $SkillsScript -PathType Leaf) {
    try {
        $ExampleOutput = [System.IO.Path]::GetFileName($NotePath)
        $null = & $SkillsScript -WorkflowId "WF-005" -ReviewResult $WorkflowReview -ExampleRequest $Text -ExampleOutput $ExampleOutput -SkillName "Note Creation"
    }
    catch {}
}

return [pscustomobject]@{
    success = $true
    workflow_id = "WF-005"
    tool_id = "obsidian_note_writer"
    note_path = $NotePath
    routed_tool = $RoutedTool
    approval_decision = $ApprovalDecision
    workbench_result = $WorkbenchResult
    workflow_review = $WorkflowReview
    response_text = "Created note at $NotePath."
    reason = [string]$WorkbenchResult.reason
    source_of_truth = "Scripts/Invoke-COOPERNoteCreationCommand.ps1"
}
