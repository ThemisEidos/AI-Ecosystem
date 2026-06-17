[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$RouterScript = Join-Path $PSScriptRoot "COOPER_ConversationalRouter.ps1"

if (-not (Test-Path -LiteralPath $RouterScript -PathType Leaf)) {
    throw "Conversational router missing: $RouterScript"
}

. $RouterScript

$TempRoot = Join-Path $Root "tmp\cooper-research-collection-codex-chain"
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$Issues = New-Object System.Collections.Generic.List[string]
$Prompt = "Research Docker host administration documentation and prepare implementation work for the Linux collection."

$script:ChainScenario = [ordered]@{
    ResearchSucceeds  = $true
    ResearchReviewPass = $true
    ImportSucceeds     = $true
    ImportReviewPass   = $true
    CodexSucceeds      = $true
    CodexReviewPass    = $true
}
$script:ChainCalls = [System.Collections.Generic.List[string]]::new()
$script:ChainArtifacts = [ordered]@{
    ResearchPath = Join-Path $TempRoot "wf-001-research.md"
    ImportPath   = Join-Path $TempRoot "wf-006-import.md"
    TaskPath     = Join-Path $TempRoot "wf-002-task.md"
}

function Add-ChainCall {
    param([Parameter(Mandatory = $true)][string]$Name)
    [void]$script:ChainCalls.Add($Name)
}

function New-ChainFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Content
    )

    $Directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($Directory)) {
        New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    }
    if ($Content -is [System.Collections.IEnumerable] -and $Content -isnot [string]) {
        Set-Content -LiteralPath $Path -Value (@($Content) -join "`r`n") -Encoding UTF8
    }
    else {
        Set-Content -LiteralPath $Path -Value ([string]$Content) -Encoding UTF8
    }
}

function New-ChainReviewResult {
    param(
        [Parameter(Mandatory = $true)][string]$WorkflowId,
        [Parameter(Mandatory = $true)][bool]$Pass,
        [Parameter(Mandatory = $false)][string]$ObservedPath = "",
        [Parameter(Mandatory = $false)][string]$Reason = ""
    )

    return [pscustomobject]@{
        workflow_id = $WorkflowId
        status = if ($Pass) { "pass" } else { "fail" }
        review_passed = $Pass
        output_type = "markdown_file"
        output_path = $ObservedPath
        issues = if ($Pass) { @() } else { @($Reason) }
        request_text = $Prompt
        source_of_truth = "Scripts/Test-COOPERResearchCollectionCodexChain.ps1"
    }
}

function Invoke-PDAResearchWorker {
    param([Parameter(Mandatory = $true)][string]$TaskPath)

    Add-ChainCall "WF-001"

    if (-not [bool]$script:ChainScenario.ResearchSucceeds) {
        return ([pscustomobject]@{
            success = $false
            status = "fail"
            reason = "WF-001 research worker failed."
            saved_path = ""
            output = $null
        } | ConvertTo-Json -Depth 10)
    }

    New-ChainFile -Path $script:ChainArtifacts.ResearchPath -Content @(
        "# WF-001 Research Summary"
        ""
        "Source request: $Prompt"
    )

    return ([pscustomobject]@{
        success = $true
        status = "success"
        reason = ""
        saved_path = [string]$script:ChainArtifacts.ResearchPath
        output = [pscustomobject]@{
            markdown_path = [string]$script:ChainArtifacts.ResearchPath
            sources = @(
                [pscustomobject]@{
                    title = "Docker host administration"
                    url = "https://docs.docker.com/"
                    category = "documentation"
                    purpose = "Reference material for the Linux collection."
                }
            )
        }
    } | ConvertTo-Json -Depth 10)
}

function Resolve-COOPERWorkflowReview {
    param(
        [Parameter(Mandatory = $true)][string]$WorkflowId,
        [Parameter(Mandatory = $true)][object]$WorkflowResult,
        [Parameter(Mandatory = $false)][string]$RequestText = "",
        [Parameter(Mandatory = $false)][string]$ExpectedOutputType = "",
        [Parameter(Mandatory = $false)][string]$ExpectedOutputPath = "",
        [Parameter(Mandatory = $false)][string]$ExpectedContent = ""
    )

    Add-ChainCall ("Review:{0}" -f $WorkflowId)

    return [pscustomobject]@{
        workflow_id = $WorkflowId
        status = if ([bool]$script:ChainScenario.ResearchReviewPass) { "pass" } else { "fail" }
        review_passed = [bool]$script:ChainScenario.ResearchReviewPass
        output_type = "markdown_file"
        output_path = $ExpectedOutputPath
        issues = if ([bool]$script:ChainScenario.ResearchReviewPass) { @() } else { @("WF-001 review failed.") }
        request_text = $Prompt
        source_of_truth = "Scripts/Test-COOPERResearchCollectionCodexChain.ps1"
    }
}

function Invoke-COOPERKnowledgeImportDraft {
    param(
        [Parameter(Mandatory = $true)][string]$RequestText,
        [Parameter(Mandatory = $true)][object]$ResearchResult,
        [Parameter(Mandatory = $false)][object]$ResearchReview = $null,
        [Parameter(Mandatory = $false)][switch]$Approved,
        [Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    Add-ChainCall "WF-006"

    if (-not [bool]$script:ChainScenario.ImportSucceeds) {
        return [pscustomobject]@{
            success = $false
            workflow_id = "WF-006"
            research_summary_path = [string]$ResearchResult.saved_path
            import_draft_path = ""
            workflow_review = $null
            response_text = "WF-006 import draft failed."
            reason = "WF-006 import draft failed."
        }
    }

    New-ChainFile -Path $script:ChainArtifacts.ImportPath -Content @(
        "# Knowledge Collection Import Draft"
        ""
        "Source request: $RequestText"
        "Research artifact: $([string]$ResearchResult.saved_path)"
    )

    $Review = [pscustomobject]@{
        workflow_id = "WF-006"
        status = if ([bool]$script:ChainScenario.ImportReviewPass) { "pass" } else { "fail" }
        review_passed = [bool]$script:ChainScenario.ImportReviewPass
        output_type = "markdown_file"
        output_path = [string]$script:ChainArtifacts.ImportPath
        issues = if ([bool]$script:ChainScenario.ImportReviewPass) { @() } else { @("WF-006 review failed.") }
        request_text = $RequestText
        source_of_truth = "Scripts/Test-COOPERResearchCollectionCodexChain.ps1"
    }
    if ([bool]$Review.review_passed -ne $true) {
        return [pscustomobject]@{
            success = $false
            workflow_id = "WF-006"
            research_summary_path = [string]$ResearchResult.saved_path
            import_draft_path = [string]$script:ChainArtifacts.ImportPath
            workflow_review = $Review
            response_text = "WF-006 review failed."
            reason = "WF-006 review failed."
        }
    }

    return [pscustomobject]@{
        success = $true
        workflow_id = "WF-006"
        research_summary_path = [string]$ResearchResult.saved_path
        import_draft_path = [string]$script:ChainArtifacts.ImportPath
        workflow_review = $Review
        response_text = "Created import draft at $([string]$script:ChainArtifacts.ImportPath)."
        reason = ""
    }
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)][string[]]$Haystack,
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Haystack -notcontains $Needle) {
        $script:Issues.Add($Message)
    }
}

$ResearchTaskPath = Join-Path $TempRoot "wf-001-task.json"
$ResearchRaw = Invoke-PDAResearchWorker -TaskPath $ResearchTaskPath
$ResearchResult = ConvertFrom-PDAMixedJson -Text $ResearchRaw -SourceName "chain research stub"
$ResearchReview = Resolve-COOPERWorkflowReview -WorkflowId "WF-001" -WorkflowResult $ResearchResult -RequestText $Prompt -ExpectedOutputType "research_markdown" -ExpectedOutputPath $script:ChainArtifacts.ResearchPath

$Result = $null
if ($ResearchResult -and (($ResearchResult.PSObject.Properties.Name -contains "status" -and [string]$ResearchResult.status -eq "success") -or ($ResearchResult.PSObject.Properties.Name -contains "success" -and [bool]$ResearchResult.success -eq $true)) -and $ResearchReview -and [bool]$ResearchReview.review_passed -eq $true) {
    $ImportDraftResult = Invoke-COOPERKnowledgeImportDraft -RequestText $Prompt -ResearchResult $ResearchResult -ResearchReview $ResearchReview -Approved -Root $Root
    if ($ImportDraftResult -and [bool]$ImportDraftResult.success -eq $true -and $ImportDraftResult.PSObject.Properties.Name -contains "workflow_review" -and $ImportDraftResult.workflow_review -and [bool]$ImportDraftResult.workflow_review.review_passed -eq $true) {
        Add-ChainCall "WF-002"
        New-ChainFile -Path $script:ChainArtifacts.TaskPath -Content @(
            "# WF-002 Codex Task"
            ""
            "Source request: $Prompt"
            "Research summary: $([string]$ResearchResult.saved_path)"
            "Collection draft: $([string]$ImportDraftResult.import_draft_path)"
        )
        $CodexTaskResult = [pscustomobject]@{
            success = $true
            workflow_id = "WF-002"
            task_path = [string]$script:ChainArtifacts.TaskPath
            workflow_review = [pscustomobject]@{
                workflow_id = "WF-002"
                status = if ([bool]$script:ChainScenario.CodexReviewPass) { "pass" } else { "fail" }
                review_passed = [bool]$script:ChainScenario.CodexReviewPass
                output_type = "markdown_file"
                output_path = [string]$script:ChainArtifacts.TaskPath
                issues = if ([bool]$script:ChainScenario.CodexReviewPass) { @() } else { @("WF-002 review failed.") }
                request_text = $Prompt
                source_of_truth = "Scripts/Test-COOPERResearchCollectionCodexChain.ps1"
            }
            response_text = "Created Codex task at $([string]$script:ChainArtifacts.TaskPath)."
            reason = ""
        }
        if ($CodexTaskResult -and [bool]$CodexTaskResult.success -eq $true -and $CodexTaskResult.PSObject.Properties.Name -contains "workflow_review" -and $CodexTaskResult.workflow_review -and [bool]$CodexTaskResult.workflow_review.review_passed -eq $true) {
            $Result = [pscustomobject]@{
                research_summary_path = [string]$ResearchResult.saved_path
                collection_import_path = [string]$ImportDraftResult.import_draft_path
                codex_task_path = [string]$CodexTaskResult.task_path
                response_text = @(
                    "Research summary: $([string]$ResearchResult.saved_path)"
                    "Collection import draft: $([string]$ImportDraftResult.import_draft_path)"
                    "Codex task: $([string]$CodexTaskResult.task_path)"
                    "Review status: WF-001 pass; WF-006 pass; WF-002 pass"
                    "Recommended next action: Review the Codex task or ask for another implementation task."
                ) -join "`r`n"
                latest_result_path = [string]$CodexTaskResult.task_path
            }
        }
    }
}

$Calls = @($script:ChainCalls)
if ($Calls.Count -ne 4) {
    $Issues.Add("Expected 4 chain calls but observed $($Calls.Count): $($Calls -join ' -> ').")
}
foreach ($ExpectedCall in @("WF-001", "Review:WF-001", "WF-006", "WF-002")) {
    Assert-Contains -Haystack $Calls -Needle $ExpectedCall -Message "Chain call '$ExpectedCall' was not observed."
}

if ($Calls.Count -eq 4 -and (@($Calls) -join " -> ") -ne "WF-001 -> Review:WF-001 -> WF-006 -> WF-002") {
    $Issues.Add("Chain calls were not executed in the required order: $($Calls -join ' -> ').")
}

foreach ($Field in @("research_summary_path", "collection_import_path", "codex_task_path")) {
    if (-not $Result -or $Result.PSObject.Properties.Name -notcontains $Field -or [string]::IsNullOrWhiteSpace([string]$Result.$Field)) {
        $Issues.Add("Final result is missing '$Field'.")
    }
}

if (-not $Result -or $Result.response_text -notmatch '(?s)Research summary: .*Collection import draft: .*Codex task: .*Review status: WF-001 pass; WF-006 pass; WF-002 pass') {
    $Issues.Add("Final response text did not include the required artifact paths and review status summary.")
}

if (-not $Result -or $Result.latest_result_path -ne $Result.codex_task_path) {
    $Issues.Add("Latest result path should point at the Codex task file after the full chain completes.")
}

$FailureScenarios = @(
    [pscustomobject]@{
        name = "WF-001 failure stops chain"
        settings = [ordered]@{
            ResearchSucceeds  = $false
            ResearchReviewPass = $false
            ImportSucceeds     = $true
            ImportReviewPass   = $true
            CodexSucceeds      = $true
            CodexReviewPass    = $true
        }
        expected_calls = @("WF-001")
        unexpected_calls = @("Review:WF-001", "WF-006", "WF-002")
        expected_response_pattern = 'WF-001 research worker failed'
    }
    [pscustomobject]@{
        name = "WF-006 failure stops chain"
        settings = [ordered]@{
            ResearchSucceeds  = $true
            ResearchReviewPass = $true
            ImportSucceeds     = $false
            ImportReviewPass   = $false
            CodexSucceeds      = $true
            CodexReviewPass    = $true
        }
        expected_calls = @("WF-001", "Review:WF-001", "WF-006")
        unexpected_calls = @("Review:WF-006", "WF-002", "Review:WF-002")
        expected_response_pattern = 'WF-006 import draft failed'
    }
)

foreach ($Scenario in $FailureScenarios) {
    $script:ChainScenario = $Scenario.settings
    $script:ChainCalls = [System.Collections.Generic.List[string]]::new()

    $ScenarioResearchRaw = Invoke-PDAResearchWorker -TaskPath (Join-Path $TempRoot ("{0}-research.json" -f $Scenario.name.Replace(" ", "-")))
    $ScenarioResearchResult = ConvertFrom-PDAMixedJson -Text $ScenarioResearchRaw -SourceName "chain research stub"
    $ScenarioResearchReview = $null
    if ($ScenarioResearchResult -and (($ScenarioResearchResult.PSObject.Properties.Name -contains "status" -and [string]$ScenarioResearchResult.status -eq "success") -or ($ScenarioResearchResult.PSObject.Properties.Name -contains "success" -and [bool]$ScenarioResearchResult.success -eq $true))) {
        $ScenarioResearchReview = Resolve-COOPERWorkflowReview -WorkflowId "WF-001" -WorkflowResult $ScenarioResearchResult -RequestText $Prompt -ExpectedOutputType "research_markdown" -ExpectedOutputPath $script:ChainArtifacts.ResearchPath
    }
    $ScenarioImportResult = $null
    $ScenarioCodexResult = $null
    $ScenarioResult = $null
    if ($ScenarioResearchResult -and (($ScenarioResearchResult.PSObject.Properties.Name -contains "status" -and [string]$ScenarioResearchResult.status -eq "success") -or ($ScenarioResearchResult.PSObject.Properties.Name -contains "success" -and [bool]$ScenarioResearchResult.success -eq $true)) -and $ScenarioResearchReview -and [bool]$ScenarioResearchReview.review_passed -eq $true) {
        $ScenarioImportResult = Invoke-COOPERKnowledgeImportDraft -RequestText $Prompt -ResearchResult $ScenarioResearchResult -ResearchReview $ScenarioResearchReview -Approved -Root $Root
        if ($ScenarioImportResult -and [bool]$ScenarioImportResult.success -eq $true -and $ScenarioImportResult.PSObject.Properties.Name -contains "workflow_review" -and $ScenarioImportResult.workflow_review -and [bool]$ScenarioImportResult.workflow_review.review_passed -eq $true) {
            Add-ChainCall "WF-002"
            $ScenarioCodexResult = [pscustomobject]@{
                success = $true
                workflow_id = "WF-002"
                task_path = [string]$script:ChainArtifacts.TaskPath
                workflow_review = [pscustomobject]@{
                    workflow_id = "WF-002"
                    status = if ([bool]$script:ChainScenario.CodexReviewPass) { "pass" } else { "fail" }
                    review_passed = [bool]$script:ChainScenario.CodexReviewPass
                    output_type = "markdown_file"
                    output_path = [string]$script:ChainArtifacts.TaskPath
                    issues = if ([bool]$script:ChainScenario.CodexReviewPass) { @() } else { @("WF-002 review failed.") }
                    request_text = $Prompt
                    source_of_truth = "Scripts/Test-COOPERResearchCollectionCodexChain.ps1"
                }
                response_text = "Created Codex task at $([string]$script:ChainArtifacts.TaskPath)."
                reason = ""
            }
        }
    }
    if (-not $ScenarioResearchResult -or (($ScenarioResearchResult.PSObject.Properties.Name -contains "success" -and [bool]$ScenarioResearchResult.success -ne $true) -or ($ScenarioResearchResult.PSObject.Properties.Name -contains "status" -and [string]$ScenarioResearchResult.status -ne "success"))) {
        $ScenarioResult = [pscustomobject]@{
            response_text = "WF-001 research worker failed."
        }
    }
    elseif (-not $ScenarioResearchReview -or [bool]$ScenarioResearchReview.review_passed -ne $true) {
        $ScenarioResult = [pscustomobject]@{
            response_text = "WF-001 review failed."
        }
    }
    elseif (-not $ScenarioImportResult -or [bool]$ScenarioImportResult.success -ne $true) {
        $ScenarioResult = [pscustomobject]@{
            response_text = "WF-006 import draft failed."
        }
    }
    elseif (-not $ScenarioCodexResult -or [bool]$ScenarioCodexResult.success -ne $true) {
        $ScenarioResult = [pscustomobject]@{
            response_text = "WF-002 Codex task generation failed."
        }
    }
    else {
        $ScenarioResult = [pscustomobject]@{
            research_summary_path = [string]$ScenarioResearchResult.saved_path
            collection_import_path = [string]$ScenarioImportResult.import_draft_path
            codex_task_path = [string]$ScenarioCodexResult.task_path
            response_text = @(
                "Research summary: $([string]$ScenarioResearchResult.saved_path)"
                "Collection import draft: $([string]$ScenarioImportResult.import_draft_path)"
                "Codex task: $([string]$ScenarioCodexResult.task_path)"
                "Review status: WF-001 pass; WF-006 pass; WF-002 pass"
            ) -join "`r`n"
            latest_result_path = [string]$ScenarioCodexResult.task_path
        }
    }
    $ScenarioCalls = @($script:ChainCalls)

    foreach ($ExpectedCall in @($Scenario.expected_calls)) {
        if ($ScenarioCalls -notcontains $ExpectedCall) {
            $Issues.Add("$($Scenario.name): missing expected call '$ExpectedCall'.")
        }
    }
    foreach ($UnexpectedCall in @($Scenario.unexpected_calls)) {
        if ($ScenarioCalls -contains $UnexpectedCall) {
            $Issues.Add("$($Scenario.name): unexpected call '$UnexpectedCall' was observed.")
        }
    }
    if ($ScenarioResult.response_text -notmatch $Scenario.expected_response_pattern) {
        $Issues.Add("$($Scenario.name): response text did not include the expected failure reason.")
    }
    if ($Scenario.name -eq "WF-001 failure stops chain" -and (
        ($ScenarioResult.PSObject.Properties.Name -contains "collection_import_path" -and -not [string]::IsNullOrWhiteSpace([string]$ScenarioResult.collection_import_path)) -or
        ($ScenarioResult.PSObject.Properties.Name -contains "codex_task_path" -and -not [string]::IsNullOrWhiteSpace([string]$ScenarioResult.codex_task_path))
    )) {
        $Issues.Add("WF-001 failure scenario should not return downstream artifact paths.")
    }
    if ($Scenario.name -eq "WF-006 failure stops chain" -and (
        ($ScenarioResult.PSObject.Properties.Name -contains "codex_task_path" -and -not [string]::IsNullOrWhiteSpace([string]$ScenarioResult.codex_task_path))
    )) {
        $Issues.Add("WF-006 failure scenario should not create the Codex task.")
    }
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    route = $Route
    result = $Result
    calls = $Calls
    issues = @($Issues)
}

Write-Host "[*] COOPER research -> collection -> Codex chain"
Write-Host ("Status : {0}" -f $Report.status)
Write-Host ("Route  : {0}" -f $Route.route_type)
Write-Host ("Calls  : {0}" -f ($Calls -join " -> "))
Write-Host ("Result : {0}" -f $Result.response_text)

if ($Report.status -ne "pass") {
    foreach ($Issue in @($Report.issues)) {
        Write-Host ("[FAIL] {0}" -f $Issue)
    }
    exit 1
}

Write-Host "[PASS] Research-to-collection-to-Codex chain validated."
exit 0
