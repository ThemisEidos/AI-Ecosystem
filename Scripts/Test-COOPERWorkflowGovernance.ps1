[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$RouterScript = Join-Path $PSScriptRoot "COOPER_ConversationalRouter.ps1"
$DefinitionsScript = Join-Path $PSScriptRoot "Get-COOPERWorkflowDefinitions.ps1"
$ReviewScript = Join-Path $PSScriptRoot "Resolve-COOPERWorkflowReview.ps1"
$SkillsScript = Join-Path $PSScriptRoot "Update-COOPERWorkflowSkills.ps1"
$TempRoot = Join-Path $Root "tmp\cooper-governance-tests"
$TempSkillsState = Join-Path $TempRoot "COOPER_Skills.failed-review.json"

if (-not (Test-Path -LiteralPath $TempRoot -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
}

. $RouterScript
. $DefinitionsScript

$Issues = New-Object System.Collections.Generic.List[string]

$Definitions = @(Get-COOPERWorkflowDefinitions -Root $Root)
$WF002 = @($Definitions | Where-Object { [string]$_.id -eq "WF-002" } | Select-Object -First 1)
$WF004 = @($Definitions | Where-Object { [string]$_.id -eq "WF-004" } | Select-Object -First 1)
$WF001 = @($Definitions | Where-Object { [string]$_.id -eq "WF-001" } | Select-Object -First 1)
$WF005 = @($Definitions | Where-Object { [string]$_.id -eq "WF-005" } | Select-Object -First 1)
$WF006 = @($Definitions | Where-Object { [string]$_.id -eq "WF-006" } | Select-Object -First 1)
$WF007 = @($Definitions | Where-Object { [string]$_.id -eq "WF-007" } | Select-Object -First 1)

if ($WF002.Count -eq 0) {
    $Issues.Add("WF-002 is missing from the workflow definitions loader.")
}
else {
    if ([string]$WF002[0].executor -ne "codex_task_generator") {
        $Issues.Add("WF-002 does not map to the codex_task_generator executor.")
    }
}

if ($WF004.Count -eq 0) {
    $Issues.Add("WF-004 is missing from the workflow definitions loader.")
}
else {
    if ([string]$WF004[0].executor -ne "operational_status") {
        $Issues.Add("WF-004 does not map to the operational_status executor.")
    }
    if ([string]$WF004[0].status -ne "operational") {
        $Issues.Add("WF-004 is not marked operational in the workflow definitions loader.")
    }
}

if ($WF001.Count -eq 0) {
    $Issues.Add("WF-001 is missing from the workflow definitions loader.")
}
else {
    if ([string]$WF001[0].executor -ne "research_summary") {
        $Issues.Add("WF-001 does not map to the research_summary executor.")
    }
}

if ($WF005.Count -eq 0) {
    $Issues.Add("WF-005 is missing from the workflow definitions loader.")
}
else {
    if ([string]$WF005[0].executor -ne "create_note") {
        $Issues.Add("WF-005 does not map to the create_note executor.")
    }
}

if ($WF006.Count -eq 0) {
    $Issues.Add("WF-006 is missing from the workflow definitions loader.")
}
else {
    if ([string]$WF006[0].executor -ne "knowledge_collection_import_draft") {
        $Issues.Add("WF-006 does not map to the knowledge_collection_import_draft executor.")
    }
}

if ($WF007.Count -eq 0) {
    $Issues.Add("WF-007 is missing from the workflow definitions loader.")
}
else {
    if ([string]$WF007[0].executor -ne "private_local_analysis") {
        $Issues.Add("WF-007 does not map to the private_local_analysis executor.")
    }
    if ([string]$WF007[0].workshop -ne "Private") {
        $Issues.Add("WF-007 is not marked as a Private workflow in the definitions loader.")
    }
}

$Catalog = Get-COOPERWorkflowCatalogSummary
if ([string]$Catalog.status -ne "pass") {
    $Issues.Add("Workflow catalog summary did not pass.")
}
else {
    $WorkflowIds = @($Catalog.workflows | ForEach-Object { [string]$_.workflow_id })
    foreach ($WorkflowId in @("WF-002", "WF-001", "WF-005", "WF-006", "WF-007")) {
        if ($WorkflowIds -notcontains $WorkflowId) {
            $Issues.Add("Workflow catalog summary is missing $WorkflowId.")
        }
    }
}

$CodexTaskRoute = Resolve-PDAConversationalRoute -Text "Create a Codex task to improve workflow routing." -Root $Root
$CodexTaskInterpreterRaw = & pwsh -NoProfile -File (Join-Path $PSScriptRoot "PDA_CommandInterpreter.ps1") -Text "Create a Codex task to improve workflow routing." -AsJson 2>&1
$CodexTaskInterpreter = ConvertFrom-PDAMixedJson -Text ([string]($CodexTaskInterpreterRaw -join "`n")) -SourceName (Join-Path $PSScriptRoot "PDA_CommandInterpreter.ps1")
$ResearchRoute = Resolve-PDAConversationalRoute -Text "Research official Pop!_OS documentation and create a structured summary note in the Linux & Infrastructure collection." -Root $Root
$NoteRoute = Resolve-PDAConversationalRoute -Text "Create an Obsidian note for WF-005." -Root $Root
$WorkflowListingRoute = Resolve-PDAConversationalRoute -Text "List available workflows." -Root $Root
$OperationalWorkflowsRoute = Resolve-PDAConversationalRoute -Text "COOPER, what workflows are operational?" -Root $Root
$WorkflowStatusRoute = Resolve-PDAConversationalRoute -Text "COOPER, show workflow status." -Root $Root
$OperationalStatusRoute = Resolve-PDAConversationalRoute -Text "What can you do?" -Root $Root
$StatusRoute = Resolve-PDAConversationalRoute -Text "How is the PDA doing?" -Root $Root
$SlashRoute = Resolve-PDAConversationalRoute -Text "/cooper status" -Root $Root

if ([string]$CodexTaskRoute.route_type -ne "codex_task_generator") {
    $Issues.Add("Codex task request did not route to codex_task_generator.")
}
if (-not $CodexTaskInterpreter -or [string]$CodexTaskInterpreter.status -ne "mapped" -or [string]$CodexTaskInterpreter.command -ne "/codex-task") {
    $Issues.Add("Codex task request did not map to the /codex-task governed command.")
}
if ([string]$ResearchRoute.route_type -ne "research_summary") {
    $Issues.Add("Research request did not route to research_summary.")
}
if ([string]$NoteRoute.route_type -ne "note_creation") {
    $Issues.Add("Note creation request did not route to note_creation.")
}
if ([string]$WorkflowListingRoute.route_type -ne "workflow_catalog") {
    $Issues.Add("Workflow listing request did not route to workflow_catalog.")
}
if ([string]$OperationalWorkflowsRoute.route_type -ne "direct_status") {
    $Issues.Add("Operational workflow request did not route to direct_status.")
}
if ([string]$WorkflowStatusRoute.route_type -ne "direct_status") {
    $Issues.Add("Workflow status request did not route to direct_status.")
}
if ([string]$OperationalStatusRoute.route_type -ne "direct_status") {
    $Issues.Add("Operational status request did not route to direct_status.")
}
if ([string]$StatusRoute.route_type -ne "direct_status") {
    $Issues.Add("Status request did not route to direct_status.")
}
if ([string]$SlashRoute.route_type -ne "legacy_cooper_slash_command") {
    $Issues.Add("Legacy slash-command UX was reintroduced or no longer classified as legacy.")
}

if (Test-Path -LiteralPath $TempSkillsState -PathType Leaf) {
    Remove-Item -LiteralPath $TempSkillsState -Force
}

$FailedReview = [pscustomobject]@{
    status = "fail"
    review_passed = $false
    reason = "Synthetic review failure for governance coverage."
    issues = @("Synthetic review failure for governance coverage.")
}

$FailedPromotion = & $SkillsScript -WorkflowId "WF-005" -ReviewResult $FailedReview -ExampleRequest "Create an Obsidian note for WF-005." -ExampleOutput "wf-005-note-creation.md" -SkillName "Note Creation" -StatePath $TempSkillsState

if ([string]$FailedPromotion.status -ne "fail") {
    $Issues.Add("Failed review did not stay in fail status.")
}
if ([bool]$FailedPromotion.promoted -ne $false) {
    $Issues.Add("Failed review incorrectly promoted the skill.")
}

if (-not (Test-Path -LiteralPath $TempSkillsState -PathType Leaf)) {
    $Issues.Add("Failed-review skills state file was not written.")
}
else {
    $SkillState = Get-Content -LiteralPath $TempSkillsState -Raw | ConvertFrom-Json
    $WF005Skill = @($SkillState.skills | Where-Object { [string]$_.workflow_id -eq "WF-005" } | Select-Object -First 1)
    if ($WF005Skill.Count -gt 0 -and [string]$WF005Skill[0].status -eq "operational") {
        $Issues.Add("Failed review promoted WF-005 to operational in the skills state.")
    }
}

$WF001Executor = if ($WF001.Count -gt 0) { [string]$WF001[0].executor } else { "<missing>" }
$WF005Executor = if ($WF005.Count -gt 0) { [string]$WF005[0].executor } else { "<missing>" }
$WF006Executor = if ($WF006.Count -gt 0) { [string]$WF006[0].executor } else { "<missing>" }

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    definitions = @($Definitions)
    workflow_catalog = $Catalog
    codex_task_route = $CodexTaskRoute
    research_route = $ResearchRoute
    note_route = $NoteRoute
    workflow_listing_route = $WorkflowListingRoute
    operational_workflows_route = $OperationalWorkflowsRoute
    workflow_status_route = $WorkflowStatusRoute
    operational_status_route = $OperationalStatusRoute
    status_route = $StatusRoute
    slash_route = $SlashRoute
    failed_promotion = $FailedPromotion
    issues = @($Issues)
}

Write-Host "[*] COOPER workflow governance test"
Write-Host ("Status   : {0}" -f $Report.status)
Write-Host ("WF-002   : {0}" -f $(if ($WF002.Count -gt 0) { [string]$WF002[0].executor } else { "<missing>" }))
Write-Host ("WF-001   : {0}" -f $WF001Executor)
Write-Host ("WF-005   : {0}" -f $WF005Executor)
Write-Host ("WF-006   : {0}" -f $WF006Executor)
Write-Host ("Route    : codex={0}, research={1}, note={2}, catalog={3}, opstatus={4}, status={5}" -f $CodexTaskRoute.route_type, $ResearchRoute.route_type, $NoteRoute.route_type, $WorkflowListingRoute.route_type, $OperationalStatusRoute.route_type, $StatusRoute.route_type)

if ($Report.status -ne "pass") {
    foreach ($Issue in @($Report.issues)) {
        Write-Host ("[FAIL] {0}" -f $Issue)
    }
    exit 1
}

Write-Host "[PASS] Workflow governance routing and promotion checks validated."
exit 0
