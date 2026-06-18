[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Text,

    [Parameter(Mandatory = $false)]
    [switch]$Approved,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Open Workshop", "Private Workshop")]
    [string]$WorkshopMode = "Private Workshop",

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
$ModelRouteScript = Join-Path $PSScriptRoot "Get-PDAModelRoute.ps1"
$IdentityScript = Join-Path $PSScriptRoot "Get-COOPERWorkshopIdentity.ps1"

function Get-COOPERPrivateLocalAnalysisPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $AnalysisFolder = Join-Path $Root "Restricted DMZ Workspace\WF-007 Private Local Analysis"
    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    return Join-Path $AnalysisFolder ("wf-007-private-local-analysis-{0}.md" -f $Timestamp)
}

function New-COOPERPrivateLocalAnalysisMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestText,

        [Parameter(Mandatory = $true)]
        [string]$AnalysisPath,

        [Parameter(Mandatory = $true)]
        [object]$AnalysisToolRoute,

        [Parameter(Mandatory = $true)]
        [object]$ModelRoute,

        [Parameter(Mandatory = $true)]
        [string]$WorkshopLabel
    )

    $RequestedAt = (Get-Date).ToUniversalTime().ToString("o")
    $SelectedModel = if ($ModelRoute.PSObject.Properties.Name -contains "selected_model") { [string]$ModelRoute.selected_model } else { "" }
    $CloudAllowed = if ($ModelRoute.PSObject.Properties.Name -contains "cloud_allowed") { [bool]$ModelRoute.cloud_allowed } else { $false }
    $AnalysisText = @(
        "# WF-007 Private Local Analysis"
        ""
        "Workshop: $WorkshopLabel"
        "Requested At: $RequestedAt"
        "Restricted DMZ Artifact: $AnalysisPath"
        ""
        "## Request"
        $RequestText
        ""
        "## Private Registry Validation"
        ("- Tool: {0}" -f [string]$AnalysisToolRoute.selected_tool)
        ("- Registry: {0}" -f [string]$AnalysisToolRoute.registry_path)
        ("- Workshop: {0}" -f [string]$AnalysisToolRoute.workshop)
        ""
        "## Local Model Route"
        ("- Selected model: {0}" -f $SelectedModel)
        ("- Cloud allowed: {0}" -f $CloudAllowed)
        ("- Route source: {0}" -f [string]$ModelRoute.route_source)
        ("- Routing reason: {0}" -f [string]$ModelRoute.routing_reason)
        ""
        "## Findings"
        "- The workflow executed entirely inside Private Workshop."
        "- The private registry tool resolved from the private registry."
        "- The model route remained local-only."
        "- No cloud fallback was permitted."
        ""
        "## Limitations"
        "- This analysis is intentionally deterministic and local-only."
        "- The Restricted DMZ Workspace is the only write target."
        ""
        "## Recommended Next Action"
        "- Review the restricted analysis or ask for a narrower private follow-up."
    ) -join "`r`n"

    return $AnalysisText
}

function New-COOPERPrivateLocalAnalysisFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reason,

        [Parameter(Mandatory = $false)]
        [object]$AnalysisToolRoute = $null,

        [Parameter(Mandatory = $false)]
        [object]$WriterRoute = $null,

        [Parameter(Mandatory = $false)]
        [object]$ModelRoute = $null
    )

    return [pscustomobject]@{
        success = $false
        workflow_id = "WF-007"
        workshop_mode = $WorkshopMode
        analysis_tool_route = $AnalysisToolRoute
        writer_tool_route = $WriterRoute
        model_route = $ModelRoute
        analysis_path = ""
        restricted_dmz_path = ""
        routed_tool = $AnalysisToolRoute
        approval_decision = $null
        writer_approval_decision = $null
        workbench_result = $null
        workflow_review = $null
        output_type = "markdown_file"
        result_artifact_path = ""
        response_text = $Reason
        reason = $Reason
        source_of_truth = "Scripts/Invoke-COOPERPrivateLocalAnalysis.ps1"
    }
}

if (-not (Test-Path -LiteralPath $IdentityScript -PathType Leaf)) {
    throw "Workshop identity resolver missing: $IdentityScript"
}

$WorkshopIdentity = & $IdentityScript -WorkshopMode $WorkshopMode
if ([string]$WorkshopIdentity.workshop_label -ne "Private Workshop") {
    return New-COOPERPrivateLocalAnalysisFailure -Reason "WF-007 Private Local Analysis is available only in Private Workshop."
}
if ([bool]$WorkshopIdentity.cloud_allowed -ne $false) {
    return New-COOPERPrivateLocalAnalysisFailure -Reason "WF-007 requires a private workshop identity with cloud fallback disabled."
}

$RequestedText = if ([string]::IsNullOrWhiteSpace($Text)) { "Private local analysis request." } else { [string]$Text }

$AnalysisToolRoute = & $RouterScript -ToolId "qwen_local_assistant" -Workshop "Private Workshop" -WorkshopMode "Private Workshop" -DryRun
if ([string]$AnalysisToolRoute.status -ne "pass") {
    return New-COOPERPrivateLocalAnalysisFailure -Reason [string]$AnalysisToolRoute.blocked_reason -AnalysisToolRoute $AnalysisToolRoute
}

$AnalysisApprovalDecision = & $ApprovalScript -RoutedToolResult $AnalysisToolRoute -Approved:$Approved
if ([bool]$AnalysisApprovalDecision.blocked -eq $true -or [bool]$AnalysisApprovalDecision.allowed -ne $true -or [bool]$AnalysisApprovalDecision.execution_authorized -ne $true) {
    return New-COOPERPrivateLocalAnalysisFailure -Reason [string]$AnalysisApprovalDecision.reason -AnalysisToolRoute $AnalysisToolRoute
}

$ModelRoute = & $ModelRouteScript -WorkerName "wf-007-private-local-analysis" -TaskType "analysis" -Command "/analysis" -Category "category_2" -Sensitivity "restricted_local" -AsJson | ConvertFrom-Json
if ([string]$ModelRoute.status -ne "pass") {
    return New-COOPERPrivateLocalAnalysisFailure -Reason "WF-007 could not resolve a local-only model route." -AnalysisToolRoute $AnalysisToolRoute -ModelRoute $ModelRoute
}
if ([string]$ModelRoute.selected_model -ne "local-llama" -or [bool]$ModelRoute.cloud_allowed -ne $false) {
    return New-COOPERPrivateLocalAnalysisFailure -Reason "WF-007 resolved an invalid model route." -AnalysisToolRoute $AnalysisToolRoute -ModelRoute $ModelRoute
}

$WriterToolRoute = & $RouterScript -ToolId "restricted_dmz_writer" -Workshop "Private Workshop" -WorkshopMode "Private Workshop" -DryRun
if ([string]$WriterToolRoute.status -ne "pass") {
    return New-COOPERPrivateLocalAnalysisFailure -Reason [string]$WriterToolRoute.blocked_reason -AnalysisToolRoute $AnalysisToolRoute -WriterRoute $WriterToolRoute -ModelRoute $ModelRoute
}

$WriterApprovalDecision = & $ApprovalScript -RoutedToolResult $WriterToolRoute -Approved:$Approved
if ([bool]$WriterApprovalDecision.blocked -eq $true -or [bool]$WriterApprovalDecision.allowed -ne $true -or [bool]$WriterApprovalDecision.execution_authorized -ne $true) {
    return New-COOPERPrivateLocalAnalysisFailure -Reason [string]$WriterApprovalDecision.reason -AnalysisToolRoute $AnalysisToolRoute -WriterRoute $WriterToolRoute -ModelRoute $ModelRoute
}

$AnalysisPath = Get-COOPERPrivateLocalAnalysisPath -Root $Root
$MarkdownContent = New-COOPERPrivateLocalAnalysisMarkdown -RequestText $RequestedText -AnalysisPath $AnalysisPath -AnalysisToolRoute $AnalysisToolRoute -ModelRoute $ModelRoute -WorkshopLabel $WorkshopIdentity.workshop_label

$WriterApprovalDecision | Add-Member -NotePropertyName file_path -NotePropertyValue $AnalysisPath -Force
$WriterApprovalDecision | Add-Member -NotePropertyName content -NotePropertyValue $MarkdownContent -Force
$WriterApprovalDecision | Add-Member -NotePropertyName markdown_content -NotePropertyValue $MarkdownContent -Force

$WorkbenchResult = & $WorkbenchScript -ApprovalDecision $WriterApprovalDecision
if ([bool]$WorkbenchResult.success -ne $true) {
    return New-COOPERPrivateLocalAnalysisFailure -Reason [string]$WorkbenchResult.reason -AnalysisToolRoute $AnalysisToolRoute -WriterRoute $WriterToolRoute -ModelRoute $ModelRoute
}

if (-not (Test-Path -LiteralPath $ReviewScript -PathType Leaf)) {
    return New-COOPERPrivateLocalAnalysisFailure -Reason "Workflow review script is unavailable." -AnalysisToolRoute $AnalysisToolRoute -WriterRoute $WriterToolRoute -ModelRoute $ModelRoute
}

$WorkflowReview = & $ReviewScript -WorkflowId "WF-007" -WorkflowResult ([pscustomobject]@{
    success = [bool]$WorkbenchResult.success
    workflow_id = "WF-007"
    output_type = "markdown_file"
    result_artifact_path = $AnalysisPath
    approval_decision = $WriterApprovalDecision
    workbench_result = $WorkbenchResult
    response_text = "Created private local analysis at $AnalysisPath."
    reason = [string]$WorkbenchResult.reason
}) -RequestText $RequestedText -ExpectedOutputType "markdown_file" -ExpectedOutputPath $AnalysisPath -ExpectedContent $RequestedText

if (-not $WorkflowReview -or [string]$WorkflowReview.status -ne "pass") {
    return [pscustomobject]@{
        success = $false
        workflow_id = "WF-007"
        workshop_mode = $WorkshopMode
        analysis_tool_route = $AnalysisToolRoute
        writer_tool_route = $WriterToolRoute
        model_route = $ModelRoute
        analysis_path = $AnalysisPath
        restricted_dmz_path = $AnalysisPath
        routed_tool = $AnalysisToolRoute
        approval_decision = $AnalysisApprovalDecision
        writer_approval_decision = $WriterApprovalDecision
        workbench_result = $WorkbenchResult
        workflow_review = $WorkflowReview
        output_type = "markdown_file"
        result_artifact_path = $AnalysisPath
        response_text = if ($WorkflowReview -and $WorkflowReview.PSObject.Properties.Name -contains "issues" -and $WorkflowReview.issues) { [string]($WorkflowReview.issues -join "; ") } else { "Workflow review failed." }
        reason = if ($WorkflowReview -and $WorkflowReview.PSObject.Properties.Name -contains "issues" -and $WorkflowReview.issues) { [string]$WorkflowReview.issues -join "; " } else { "Workflow review failed." }
        source_of_truth = "Scripts/Invoke-COOPERPrivateLocalAnalysis.ps1"
    }
}

if (Test-Path -LiteralPath $MemoryScript -PathType Leaf) {
    try {
        $null = & $MemoryScript -WorkflowId "WF-007" -ReviewResult $WorkflowReview -RequestText $RequestedText -OutputPath $AnalysisPath
    }
    catch {}
}

if (Test-Path -LiteralPath $SkillsScript -PathType Leaf) {
    try {
        $ExampleOutput = [System.IO.Path]::GetFileName($AnalysisPath)
        $null = & $SkillsScript -WorkflowId "WF-007" -ReviewResult $WorkflowReview -ExampleRequest $RequestedText -ExampleOutput $ExampleOutput -SkillName "Private Local Analysis"
    }
    catch {}
}

return [pscustomobject]@{
    success = $true
    workflow_id = "WF-007"
    workshop_mode = $WorkshopMode
    analysis_tool_route = $AnalysisToolRoute
    writer_tool_route = $WriterToolRoute
    model_route = $ModelRoute
    analysis_path = $AnalysisPath
    restricted_dmz_path = $AnalysisPath
    routed_tool = $AnalysisToolRoute
    approval_decision = $AnalysisApprovalDecision
    writer_approval_decision = $WriterApprovalDecision
    workbench_result = $WorkbenchResult
    workflow_review = $WorkflowReview
    output_type = "markdown_file"
    result_artifact_path = $AnalysisPath
    response_text = "Created private local analysis at $AnalysisPath."
    reason = [string]$WorkbenchResult.reason
    source_of_truth = "Scripts/Invoke-COOPERPrivateLocalAnalysis.ps1"
}
