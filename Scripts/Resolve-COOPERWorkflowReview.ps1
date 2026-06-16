[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkflowId,

    [Parameter(Mandatory = $true)]
    [object]$WorkflowResult,

    [Parameter(Mandatory = $false)]
    [string]$RequestText = "",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedOutputType = "",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedOutputPath = "",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedContent = ""
)

$ErrorActionPreference = "Stop"

function Test-COOPERReviewField {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($Name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $Name) {
            $Value = $Object.$Name
            if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)) {
                return $Value
            }
        }
    }

    return $null
}

function New-COOPERReviewResult {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Pass,

        [Parameter(Mandatory = $false)]
        [string[]]$Issues = @(),

        [Parameter(Mandatory = $false)]
        [string]$ObservedOutputType,

        [Parameter(Mandatory = $false)]
        [string]$ObservedOutputPath
    )

    if ([string]::IsNullOrWhiteSpace($ObservedOutputPath)) {
        $ObservedOutputPath = "(missing)"
    }
    if ([string]::IsNullOrWhiteSpace($ObservedOutputType)) {
        $ObservedOutputType = "unknown"
    }

    return [pscustomobject]@{
        workflow_id = $WorkflowId
        status = if ($Pass) { "pass" } else { "fail" }
        review_passed = $Pass
        output_type = $ObservedOutputType
        output_path = $ObservedOutputPath
        issues = @($Issues | ForEach-Object { [string]$_ })
        request_text = $RequestText
        source_of_truth = "Scripts/Resolve-COOPERWorkflowReview.ps1"
    }
}

function Get-COOPERReviewMarkdownContent {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Result
    )

    $CandidatePaths = New-Object System.Collections.Generic.List[string]
    foreach ($Name in @("saved_path", "result_artifact_path", "latest_result_path")) {
        $Value = Test-COOPERReviewField -Object $Result -Names @($Name)
        if (-not [string]::IsNullOrWhiteSpace([string]$Value)) {
            $CandidatePaths.Add([string]$Value)
        }
    }

    if ($Result.PSObject.Properties.Name -contains "output" -and $Result.output) {
        foreach ($Name in @("markdown_path", "note_path", "import_draft_path", "task_path")) {
            $Value = Test-COOPERReviewField -Object $Result.output -Names @($Name)
            if (-not [string]::IsNullOrWhiteSpace([string]$Value)) {
                $CandidatePaths.Add([string]$Value)
            }
        }
    }

    foreach ($Path in @($CandidatePaths | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return [pscustomobject]@{
                path = $Path
                content = [string](Get-Content -LiteralPath $Path -Raw)
            }
        }
    }

    return $null
}

$Issues = New-Object System.Collections.Generic.List[string]
$ObservedOutputType = ""
$ObservedOutputPath = ""
$Result = $WorkflowResult

if ($null -eq $Result) {
    return New-COOPERReviewResult -Pass:$false -Issues @("Workflow result was empty.") -ObservedOutputType "" -ObservedOutputPath ""
}

$WorkflowStatus = [string](Test-COOPERReviewField -Object $Result -Names @("status", "result_status"))
if (-not [string]::IsNullOrWhiteSpace($WorkflowStatus)) {
    if ($WorkflowStatus -notin @("success", "pass", "completed")) {
        $Issues.Add("Workflow status indicates failure.")
    }
}
else {
    $WorkflowSuccess = Test-COOPERReviewField -Object $Result -Names @("success")
    if ($null -ne $WorkflowSuccess -and [bool]$WorkflowSuccess -ne $true) {
        $Issues.Add("Workflow result did not report success.")
    }
}

if ($WorkflowId -eq "WF-006") {
    $ObservedContent = Get-COOPERReviewMarkdownContent -Result $Result
    if ($null -eq $ObservedContent -and -not [string]::IsNullOrWhiteSpace($ExpectedOutputPath) -and (Test-Path -LiteralPath $ExpectedOutputPath -PathType Leaf)) {
        $ObservedContent = [pscustomobject]@{
            path = $ExpectedOutputPath
            content = [string](Get-Content -LiteralPath $ExpectedOutputPath -Raw)
        }
    }

    if ($null -eq $ObservedContent) {
        $Issues.Add("WF-006 output markdown file was not found.")
    }
    else {
        $Content = [string]$ObservedContent.content
        $SourceArtifactPath = ""
        if ($Result.PSObject.Properties.Name -contains "source_research_artifact_path") {
            $SourceArtifactPath = [string]$Result.source_research_artifact_path
        }
        elseif ($Result.PSObject.Properties.Name -contains "research_summary_path") {
            $SourceArtifactPath = [string]$Result.research_summary_path
        }
        elseif ($Result.PSObject.Properties.Name -contains "output" -and $Result.output -and $Result.output.PSObject.Properties.Name -contains "source_research_artifact_path") {
            $SourceArtifactPath = [string]$Result.output.source_research_artifact_path
        }

        $SourceUrls = @()
        if ($Result.PSObject.Properties.Name -contains "source_urls") {
            $SourceUrls = @($Result.source_urls | ForEach-Object { [string]$_ })
        }
        elseif ($Result.PSObject.Properties.Name -contains "output" -and $Result.output -and $Result.output.PSObject.Properties.Name -contains "source_urls") {
            $SourceUrls = @($Result.output.source_urls | ForEach-Object { [string]$_ })
        }
        elseif ($Result.PSObject.Properties.Name -contains "output" -and $Result.output -and $Result.output.PSObject.Properties.Name -contains "sources") {
            $SourceUrls = @($Result.output.sources | ForEach-Object { [string]$_.url })
        }

        if ([string]::IsNullOrWhiteSpace($SourceArtifactPath)) {
            $Issues.Add("WF-006 import draft is missing the source research artifact path.")
        }
        if (@($SourceUrls | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0) {
            $Issues.Add("WF-006 import draft is missing source URLs.")
        }
        if ($Content -notmatch '(?m)^#\s+Knowledge Collection Import Draft') {
            $Issues.Add("WF-006 markdown missing title.")
        }
        if ($Content -notmatch '(?m)^##\s+Collection\s*$' -or $Content -notmatch '(?i)Linux & Infrastructure') {
            $Issues.Add("WF-006 markdown missing collection name.")
        }
        if ($Content -notmatch '(?m)^##\s+Source Research Artifact\s*$') {
            $Issues.Add("WF-006 markdown missing source research artifact section.")
        }
        if ($Content -notmatch '(?m)^##\s+Import Status\s*$') {
            $Issues.Add("WF-006 markdown missing import status section.")
        }
        if ($Content -notmatch '(?i)Draft only\. Not imported\.' -and $Content -notmatch '(?i)not imported') {
            $Issues.Add("WF-006 markdown missing draft-only import status.")
        }
        if ($Content -notmatch '(?i)Source URL:') {
            $Issues.Add("WF-006 markdown missing source URLs.")
        }
        if ($Content -match '(?i)Open WebUI Workspace import|imported into workspace|automatic import occurred') {
            $Issues.Add("WF-006 markdown suggests a workspace import occurred.")
        }
    }
}

if ($WorkflowId -eq "WF-002") {
    if ($Result.PSObject.Properties.Name -contains "output_type" -and -not [string]::IsNullOrWhiteSpace([string]$Result.output_type)) {
        $ObservedOutputType = [string]$Result.output_type
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ExpectedOutputType)) {
        $ObservedOutputType = [string]$ExpectedOutputType
    }
    else {
        $ObservedOutputType = "markdown_file"
    }

    $ObservedContent = Get-COOPERReviewMarkdownContent -Result $Result
    if ($null -eq $ObservedContent -and -not [string]::IsNullOrWhiteSpace($ExpectedOutputPath) -and (Test-Path -LiteralPath $ExpectedOutputPath -PathType Leaf)) {
        $ObservedContent = [pscustomobject]@{
            path = $ExpectedOutputPath
            content = [string](Get-Content -LiteralPath $ExpectedOutputPath -Raw)
        }
    }

    if ($null -eq $ObservedContent) {
        $Issues.Add("WF-002 output markdown file was not found.")
    }
    else {
        $Content = [string]$ObservedContent.content
        $FirstLine = ([string]$Content -split "`r?`n", 2)[0]
        if ($FirstLine -match '^\s*#\s*$' -or $FirstLine -match '(?i)^#\s*Task Title\s*$') {
            $Issues.Add("WF-002 markdown title is missing or still uses the placeholder.")
        }

        foreach ($Section in @("Objective", "Background", "Current State", "Required Work", "Constraints", "Validation", "Definition of Done")) {
            if ($Content -notmatch ("(?m)^##\s+{0}\s*$" -f [regex]::Escape($Section))) {
                $Issues.Add("WF-002 markdown missing '$Section' section.")
            }
        }
    }

    return New-COOPERReviewResult -Pass:($Issues.Count -eq 0) -Issues @($Issues.ToArray()) -ObservedOutputType $ObservedOutputType -ObservedOutputPath $(if ($ObservedContent) { [string]$ObservedContent.path } else { $ExpectedOutputPath })
}

if ($WorkflowId -eq "WF-005") {
    $ExpectedOutputType = if ([string]::IsNullOrWhiteSpace($ExpectedOutputType)) { "markdown_file" } else { $ExpectedOutputType }
    $ObservedOutputType = "markdown_file"
    $ObservedOutputPath = [string](Test-COOPERReviewField -Object $Result -Names @("note_path", "latest_result_path", "result_artifact_path"))
    if ([string]::IsNullOrWhiteSpace($ObservedOutputPath) -and $Result.PSObject.Properties.Name -contains "workbench_result" -and $Result.workbench_result) {
        $ObservedOutputPath = [string](Test-COOPERReviewField -Object $Result.workbench_result -Names @("note_path"))
        if ([string]::IsNullOrWhiteSpace($ObservedOutputPath) -and $Result.workbench_result.PSObject.Properties.Name -contains "output" -and $Result.workbench_result.output) {
            $ObservedOutputPath = [string](Test-COOPERReviewField -Object $Result.workbench_result.output -Names @("note_path"))
        }
    }

    if ([string]::IsNullOrWhiteSpace($ObservedOutputPath)) {
        $Issues.Add("Expected note path was not returned.")
    }
    elseif (-not (Test-Path -LiteralPath $ObservedOutputPath -PathType Leaf)) {
        $Issues.Add("Expected markdown file does not exist.")
    }

    if ([string]::IsNullOrWhiteSpace($ExpectedContent)) {
        $ExpectedContent = [string]$RequestText
    }

    if (-not [string]::IsNullOrWhiteSpace($ObservedOutputPath) -and (Test-Path -LiteralPath $ObservedOutputPath -PathType Leaf)) {
        $Content = Get-Content -LiteralPath $ObservedOutputPath -Raw
        if ([string]::IsNullOrWhiteSpace($Content)) {
            $Issues.Add("Markdown file is empty.")
        }
        if ($Content -notmatch '(?m)^#\s+WF-005 Note Creation') {
            $Issues.Add("Markdown file missing WF-005 title.")
        }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedContent) -and $Content -notmatch [regex]::Escape($ExpectedContent.Trim())) {
            $Issues.Add("Markdown file does not contain the user-provided content.")
        }
    }

    if ($Result.PSObject.Properties.Name -contains "workbench_result" -and $Result.workbench_result) {
        $WorkbenchSuccess = [bool](Test-COOPERReviewField -Object $Result.workbench_result -Names @("success"))
        if ($WorkbenchSuccess -ne $true) {
            $Issues.Add("Workbench result did not report success.")
        }

        $WorkbenchAction = [string](Test-COOPERReviewField -Object $Result.workbench_result -Names @("action_taken"))
        if ($WorkbenchAction -ne "create_markdown_note") {
            $Issues.Add("Workbench did not report create_markdown_note.")
        }
    }
    else {
        $Issues.Add("Workbench result was missing.")
    }

    if ($Result.PSObject.Properties.Name -contains "approval_decision" -and $Result.approval_decision) {
        $ApprovalAuthorized = [bool](Test-COOPERReviewField -Object $Result.approval_decision -Names @("execution_authorized"))
        if ($ApprovalAuthorized -ne $true) {
            $Issues.Add("Approval gate did not authorize execution.")
        }
    }

    return New-COOPERReviewResult -Pass:($Issues.Count -eq 0) -Issues @($Issues.ToArray()) -ObservedOutputType $ObservedOutputType -ObservedOutputPath $ObservedOutputPath
}

$ObservedOutputType = if ([string]::IsNullOrWhiteSpace($ExpectedOutputType)) { "unknown" } else { $ExpectedOutputType }
$ObservedOutputPath = [string](Test-COOPERReviewField -Object $Result -Names @("result_artifact_path", "latest_result_path"))

if ($Result.PSObject.Properties.Name -contains "output_type" -and -not [string]::IsNullOrWhiteSpace([string]$Result.output_type)) {
    $ObservedOutputType = [string]$Result.output_type
}

if ($Result.PSObject.Properties.Name -contains "output" -and $Result.output -and $Result.output.PSObject.Properties.Name -contains "markdown_path") {
    $ObservedOutputPath = [string]$Result.output.markdown_path
}

if ([string]::IsNullOrWhiteSpace($ObservedOutputPath)) {
    if ($Result.PSObject.Properties.Name -contains "saved_path" -and -not [string]::IsNullOrWhiteSpace([string]$Result.saved_path)) {
        $ObservedOutputPath = [string]$Result.saved_path
    }
}

if ([string]::IsNullOrWhiteSpace($ObservedOutputPath) -and -not [string]::IsNullOrWhiteSpace($ExpectedOutputPath)) {
    $ObservedOutputPath = [string]$ExpectedOutputPath
}

if ([string]::IsNullOrWhiteSpace($ObservedOutputPath)) {
    $Issues.Add("Workflow output path is missing.")
}
elseif (-not (Test-Path -LiteralPath $ObservedOutputPath -PathType Leaf)) {
    $Issues.Add("Workflow output path does not exist.")
}

if ($Result.PSObject.Properties.Name -contains "output_type" -and -not [string]::IsNullOrWhiteSpace($ExpectedOutputType) -and [string]$Result.output_type -ne $ExpectedOutputType) {
    $Issues.Add("Output type '$([string]$Result.output_type)' did not match expected '$ExpectedOutputType'.")
}

if ($WorkflowId -eq "WF-001" -and -not [string]::IsNullOrWhiteSpace($RequestText)) {
    $ObservedContent = Get-COOPERReviewMarkdownContent -Result $Result
    if ($null -eq $ObservedContent -and -not [string]::IsNullOrWhiteSpace($ExpectedOutputPath) -and (Test-Path -LiteralPath $ExpectedOutputPath -PathType Leaf)) {
        $ObservedContent = [pscustomobject]@{
            path = $ExpectedOutputPath
            content = [string](Get-Content -LiteralPath $ExpectedOutputPath -Raw)
        }
    }
    if ($null -eq $ObservedContent) {
        $Issues.Add("WF-001 output markdown file was not found.")
    }
    else {
        $Content = [string]$ObservedContent.content
        $SourceCount = 0
        if ($Result.PSObject.Properties.Name -contains "output" -and $Result.output) {
            if ($Result.output.PSObject.Properties.Name -contains "source_count") {
                $SourceCount = [int]$Result.output.source_count
            }
            elseif ($Result.output.PSObject.Properties.Name -contains "sources") {
                $SourceCount = @($Result.output.sources).Count
            }
        }
        elseif ($Result.PSObject.Properties.Name -contains "source_count") {
            $SourceCount = [int]$Result.source_count
        }

        if ($SourceCount -le 0) {
            $Issues.Add("WF-001 review requires at least one collected source.")
        }

        if ($Content -notmatch '(?i)https?://') {
            $Issues.Add("WF-001 markdown does not contain any source URLs.")
        }
        if ($Content -notmatch '(?im)^##\s+Retrieved At' -and $Content -notmatch '(?i)retrieved_at') {
            $Issues.Add("WF-001 markdown is missing a retrieved_at timestamp.")
        }
        if ($Content -match '(?i)cannot perform real-time research|knowledge cutoff|if you provide source material|as an ai|i can''t browse|i cannot browse|unable to access the web') {
            $Issues.Add("WF-001 markdown contains disclaimer-only language.")
        }
        if ($Content -notmatch '(?i)pop!?_?os|system76|linux & infrastructure|summary') {
            $Issues.Add("WF-001 markdown does not appear to address the original request.")
        }
    }
}

if ($Result.PSObject.Properties.Name -contains "reason" -and -not [string]::IsNullOrWhiteSpace([string]$Result.reason)) {
    if ([string]$Result.reason -match '(?i)failed|error|blocked|unavailable' -and $Issues.Count -eq 0) {
        $Issues.Add("Workflow result reason indicates an execution problem.")
    }
}

return New-COOPERReviewResult -Pass:($Issues.Count -eq 0) -Issues @($Issues.ToArray()) -ObservedOutputType $ObservedOutputType -ObservedOutputPath $ObservedOutputPath
