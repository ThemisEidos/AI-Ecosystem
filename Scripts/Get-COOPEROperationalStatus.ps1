[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$WorkshopMode = "",

    [Parameter(Mandatory = $false)]
    [object]$WorkshopIdentity,

    [Parameter(Mandatory = $false)]
    [string]$RoadmapPath = "",

    [Parameter(Mandatory = $false)]
    [string]$ProjectMemoryPath = "",

    [Parameter(Mandatory = $false)]
    [string]$SkillsStatePath = "",

    [Parameter(Mandatory = $false)]
    [string]$MilestonePath = "",

    [Parameter(Mandatory = $false)]
    [string]$WorkflowDefinitionsPath = "",

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$WorkshopIdentityScript = Join-Path $PSScriptRoot "Get-COOPERWorkshopIdentity.ps1"
$DefinitionsScript = Join-Path $PSScriptRoot "Get-COOPERWorkflowDefinitions.ps1"
if (Test-Path -LiteralPath $DefinitionsScript -PathType Leaf) {
    . $DefinitionsScript
}

function Read-COOPERJsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Get-COOPERFirstMatch {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $Match = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($Match.Success -and $Match.Groups.Count -gt 1) {
        return [string]$Match.Groups[1].Value.Trim()
    }

    return ""
}

function ConvertTo-COOPERStatusList {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Value
    )

    if ($null -eq $Value) {
        return @()
    }

    return @(
        $Value |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )
}

$RoadmapPath = if ([string]::IsNullOrWhiteSpace($RoadmapPath)) { Join-Path $Root "07_Implementation Roadmap.md" } else { $RoadmapPath }
$ProjectMemoryPath = if ([string]::IsNullOrWhiteSpace($ProjectMemoryPath)) { Join-Path $Root "State\COOPER_ProjectMemory.json" } else { $ProjectMemoryPath }
$SkillsStatePath = if ([string]::IsNullOrWhiteSpace($SkillsStatePath)) { Join-Path $Root "State\COOPER_Skills.json" } else { $SkillsStatePath }
$MilestonePath = if ([string]::IsNullOrWhiteSpace($MilestonePath)) { Join-Path $Root "Docs\2026-06-16 Operational Workflow Milestone.md" } else { $MilestonePath }

$ResolvedWorkshopMode = [string]$WorkshopMode
if ([string]::IsNullOrWhiteSpace($ResolvedWorkshopMode) -and $WorkshopIdentity -and $WorkshopIdentity.PSObject.Properties.Name -contains "workshop_label") {
    $ResolvedWorkshopMode = [string]$WorkshopIdentity.workshop_label
}
if ([string]::IsNullOrWhiteSpace($ResolvedWorkshopMode)) {
    $ResolvedWorkshopMode = [string]$env:COOPER_WORKSHOP_MODE
}
if ([string]::IsNullOrWhiteSpace($ResolvedWorkshopMode)) {
    $ResolvedWorkshopMode = "Open Workshop"
}

$ResolvedWorkshopIdentity = $WorkshopIdentity
if (-not $ResolvedWorkshopIdentity -and (Test-Path -LiteralPath $WorkshopIdentityScript -PathType Leaf)) {
    try {
        $ResolvedWorkshopIdentity = & $WorkshopIdentityScript -WorkshopMode $ResolvedWorkshopMode
    }
    catch {
        $ResolvedWorkshopIdentity = $null
    }
}

if (-not $ResolvedWorkshopIdentity) {
    $ResolvedWorkshopIdentity = [pscustomobject]@{
        workshop_label = if ($ResolvedWorkshopMode) { $ResolvedWorkshopMode } else { "Open Workshop" }
        display_name = "COOPER"
        default_model = "Claude Sonnet"
        cloud_allowed = $true
        registry = "Config/general_tool_registry.yaml"
    }
}

$RoadmapText = if (Test-Path -LiteralPath $RoadmapPath -PathType Leaf) { Get-Content -LiteralPath $RoadmapPath -Raw -ErrorAction SilentlyContinue } else { "" }
$MilestoneText = if (Test-Path -LiteralPath $MilestonePath -PathType Leaf) { Get-Content -LiteralPath $MilestonePath -Raw -ErrorAction SilentlyContinue } else { "" }
$ProjectMemory = Read-COOPERJsonFile -Path $ProjectMemoryPath
$SkillsState = Read-COOPERJsonFile -Path $SkillsStatePath
$WorkflowDefinitions = @()
$ResolvedWorkflowDefinitionsPath = if ([string]::IsNullOrWhiteSpace($WorkflowDefinitionsPath)) { Join-Path $Root "Config\workflows.yaml" } else { $WorkflowDefinitionsPath }
if (Test-Path -LiteralPath $ResolvedWorkflowDefinitionsPath -PathType Leaf) {
    if (Get-Command -Name Get-COOPERWorkflowDefinitions -ErrorAction SilentlyContinue) {
        try {
            $WorkflowDefinitions = @(Get-COOPERWorkflowDefinitions -Root $Root -Path $ResolvedWorkflowDefinitionsPath)
        }
        catch {
            $WorkflowDefinitions = @()
        }
    }
}
elseif (-not [string]::IsNullOrWhiteSpace($WorkflowDefinitionsPath)) {
    $WorkflowDefinitions = @()
}
elseif (Get-Command -Name Get-COOPERWorkflowDefinitions -ErrorAction SilentlyContinue) {
    try {
        $WorkflowDefinitions = @(Get-COOPERWorkflowDefinitions -Root $Root)
    }
    catch {
        $WorkflowDefinitions = @()
    }
}

$OperationalWorkflowDefinitions = @(
    $WorkflowDefinitions | Where-Object { [string]$_.status -eq "operational" }
)

$CurrentPhase = Get-COOPERFirstMatch -Text $RoadmapText -Pattern '^\s*-\s*Current Phase:\s*(.+?)\s*$'
if ([string]::IsNullOrWhiteSpace($CurrentPhase) -and $ProjectMemory -and $ProjectMemory.PSObject.Properties.Name -contains "current_phase") {
    $CurrentPhase = [string]$ProjectMemory.current_phase
}

$WorkflowChains = New-Object System.Collections.Generic.List[string]
foreach ($SourceText in @($RoadmapText, $MilestoneText)) {
    if ([string]::IsNullOrWhiteSpace([string]$SourceText)) {
        continue
    }

    foreach ($Match in ([regex]::Matches([string]$SourceText, 'WF-\d+\s*(?:->|→)\s*WF-\d+'))) {
        $Chain = [string]$Match.Value.Trim()
        if (-not [string]::IsNullOrWhiteSpace($Chain) -and $WorkflowChains -notcontains $Chain) {
            $WorkflowChains.Add($Chain)
        }
    }
}

$KnownBlockers = @()
if ($ProjectMemory -and $ProjectMemory.PSObject.Properties.Name -contains "open_blockers") {
    $KnownBlockers = @(ConvertTo-COOPERStatusList -Value $ProjectMemory.open_blockers)
}

$RecentDecisions = @()
if ($ProjectMemory -and $ProjectMemory.PSObject.Properties.Name -contains "recent_decisions") {
    $RecentDecisions = @(
        $ProjectMemory.recent_decisions |
            Select-Object -First 3 |
            ForEach-Object {
                $DecisionText = if ($_.PSObject.Properties.Name -contains "decision") { [string]$_.decision } else { "" }
                $DecisionDate = if ($_.PSObject.Properties.Name -contains "date") { [string]$_.date } else { "" }
                if (-not [string]::IsNullOrWhiteSpace($DecisionText)) {
                    if (-not [string]::IsNullOrWhiteSpace($DecisionDate)) {
                        "{0}: {1}" -f $DecisionDate, $DecisionText
                    }
                    else {
                        $DecisionText
                    }
                }
            } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )
}

$LastSuccessfulWorkflow = $null
if ($ProjectMemory -and $ProjectMemory.PSObject.Properties.Name -contains "last_successful_workflow") {
    $LastSuccessfulWorkflow = $ProjectMemory.last_successful_workflow
}

$LastFailedWorkflow = $null
if ($ProjectMemory -and $ProjectMemory.PSObject.Properties.Name -contains "last_failed_workflow") {
    $LastFailedWorkflow = $ProjectMemory.last_failed_workflow
}

$OperationalWorkflows = @(
    $OperationalWorkflowDefinitions | ForEach-Object {
        [pscustomobject]@{
            workflow_id    = [string]$_.id
            name           = [string]$_.name
            status         = [string]$_.status
            executor       = [string]$_.executor
            permission_lvl = $_.permission_level
            storage_target = [string]$_.storage_target
        }
    }
)

$WorkflowDefinitionSummary = @(
    $WorkflowDefinitions | ForEach-Object {
        [pscustomobject]@{
            workflow_id    = [string]$_.id
            name           = [string]$_.name
            status         = [string]$_.status
            executor       = [string]$_.executor
            storage_target = [string]$_.storage_target
        }
    }
)

$KnownCapabilities = New-Object System.Collections.Generic.List[string]
foreach ($Workflow in $OperationalWorkflows) {
    if (-not [string]::IsNullOrWhiteSpace([string]$Workflow.name)) {
        $KnownCapabilities.Add([string]$Workflow.name)
    }
}
if ($KnownCapabilities -notcontains "Operational status reporting") {
    $KnownCapabilities.Add("Operational status reporting")
}

$SecuritySources = [pscustomobject]@{
    firewall_status = "Not Configured"
    ids_status      = "Not Configured"
    backup_status   = "Not Configured"
}

$SkillSummary = [pscustomobject]@{
    updated_at = if ($SkillsState -and $SkillsState.PSObject.Properties.Name -contains "updated_at") { [string]$SkillsState.updated_at } else { "" }
    skill_count = if ($SkillsState -and $SkillsState.PSObject.Properties.Name -contains "skills" -and $SkillsState.skills) { @($SkillsState.skills).Count } else { 0 }
    skills      = if ($SkillsState -and $SkillsState.PSObject.Properties.Name -contains "skills") { @($SkillsState.skills) } else { @() }
}

$OperationalWorkflowCount = @($OperationalWorkflows).Count
$WorkflowDefinitionCount = @($WorkflowDefinitionSummary).Count
$ResponseLines = New-Object System.Collections.Generic.List[string]

$ResponseLines.Add("COOPER Operational Status")
$ResponseLines.Add("")
$ResponseLines.Add(("Active Workshop: {0}" -f $(if ($ResolvedWorkshopIdentity.PSObject.Properties.Name -contains "display_name" -and -not [string]::IsNullOrWhiteSpace([string]$ResolvedWorkshopIdentity.display_name)) { [string]$ResolvedWorkshopIdentity.display_name } else { "COOPER" })))
$ResponseLines.Add(("Workshop Mode: {0}" -f $(if ($ResolvedWorkshopIdentity.PSObject.Properties.Name -contains "workshop_label" -and -not [string]::IsNullOrWhiteSpace([string]$ResolvedWorkshopIdentity.workshop_label)) { [string]$ResolvedWorkshopIdentity.workshop_label } else { $ResolvedWorkshopMode })))
$ResponseLines.Add(("Default Model: {0}" -f $(if ($ResolvedWorkshopIdentity.PSObject.Properties.Name -contains "default_model" -and -not [string]::IsNullOrWhiteSpace([string]$ResolvedWorkshopIdentity.default_model)) { [string]$ResolvedWorkshopIdentity.default_model } else { "Claude Sonnet" })))
$ResponseLines.Add("")
$ResponseLines.Add(("Current Phase: {0}" -f $(if ([string]::IsNullOrWhiteSpace($CurrentPhase)) { "Unknown" } else { $CurrentPhase })))
$ResponseLines.Add("")
$ResponseLines.Add("Operational Workflows")
foreach ($Workflow in $OperationalWorkflows) {
    $ResponseLines.Add(("- {0} {1}" -f $Workflow.workflow_id, $Workflow.name))
}
$ResponseLines.Add("")
$ResponseLines.Add("Operational Chains")
if ($WorkflowChains.Count -gt 0) {
    foreach ($Chain in $WorkflowChains) {
        $ResponseLines.Add(("- {0}" -f $Chain))
    }
}
else {
    $ResponseLines.Add("- none recorded")
}
$ResponseLines.Add("")
$ResponseLines.Add("Known Capabilities")
foreach ($Capability in @($KnownCapabilities | Select-Object -Unique)) {
    $ResponseLines.Add(("- {0}" -f $Capability))
}
$ResponseLines.Add("")
$ResponseLines.Add("Known Issues")
if ($KnownBlockers.Count -gt 0) {
    foreach ($Blocker in $KnownBlockers) {
        $ResponseLines.Add(("- {0}" -f $Blocker))
    }
}
else {
    $ResponseLines.Add("- none recorded")
}
$ResponseLines.Add("")
$ResponseLines.Add("Recent Activity")
if ($LastSuccessfulWorkflow) {
    $SuccessText = [string]$LastSuccessfulWorkflow.workflow_id
    if ($LastSuccessfulWorkflow.PSObject.Properties.Name -contains "review_status" -and -not [string]::IsNullOrWhiteSpace([string]$LastSuccessfulWorkflow.review_status)) {
        $SuccessText = "{0} ({1})" -f $SuccessText, [string]$LastSuccessfulWorkflow.review_status
    }
    if ($LastSuccessfulWorkflow.PSObject.Properties.Name -contains "output_path" -and -not [string]::IsNullOrWhiteSpace([string]$LastSuccessfulWorkflow.output_path)) {
        $SuccessText = "{0} -> {1}" -f $SuccessText, [string]$LastSuccessfulWorkflow.output_path
    }
    $ResponseLines.Add(("- Last successful workflow: {0}" -f $SuccessText))
}
else {
    $ResponseLines.Add("- Last successful workflow: none recorded")
}

if ($LastFailedWorkflow) {
    $FailureText = [string]$LastFailedWorkflow.workflow_id
    if ($LastFailedWorkflow.PSObject.Properties.Name -contains "reason" -and -not [string]::IsNullOrWhiteSpace([string]$LastFailedWorkflow.reason)) {
        $FailureText = "{0} -> {1}" -f $FailureText, [string]$LastFailedWorkflow.reason
    }
    $ResponseLines.Add(("- Last failed workflow: {0}" -f $FailureText))
}
else {
    $ResponseLines.Add("- Last failed workflow: none recorded")
}

if ($RecentDecisions.Count -gt 0) {
    foreach ($Decision in $RecentDecisions) {
        $ResponseLines.Add(("- Recent decision: {0}" -f $Decision))
    }
}

$ResponseLines.Add("")
$ResponseLines.Add("Recommended Next Action")
if ($OperationalWorkflowCount -gt 0) {
    $ResponseLines.Add(("- Ask for a research summary, Codex task, note creation, or collection import draft."))
}
else {
    $ResponseLines.Add(("- Restore workflow definitions before dispatching governed work."))
}

$StatusLines = @($ResponseLines | ForEach-Object { [string]$_ })
$ResponseText = $StatusLines -join "`r`n"

$ReviewPassed = $true
$ReviewReasons = New-Object System.Collections.Generic.List[string]
if ($WorkflowDefinitionCount -eq 0 -or $OperationalWorkflowCount -eq 0) {
    $ReviewPassed = $false
    $ReviewReasons.Add("no workflow data found")
}
if ([string]::IsNullOrWhiteSpace($CurrentPhase)) {
    $ReviewPassed = $false
    $ReviewReasons.Add("no phase data found")
}
if ([string]::IsNullOrWhiteSpace($ResponseText) -or @($StatusLines | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0) {
    $ReviewPassed = $false
    $ReviewReasons.Add("status report is empty")
}

$Result = [pscustomobject]@{
    status                   = $(if ($ReviewPassed) { "pass" } else { "fail" })
    review_passed            = [bool]$ReviewPassed
    review_reason            = if ($ReviewReasons.Count -gt 0) { $ReviewReasons -join "; " } else { "Operational status summary complete." }
    workspace_root           = $Root
    config_exists            = (Test-Path -LiteralPath (Join-Path $Root "Config") -PathType Container)
    scripts_exists           = (Test-Path -LiteralPath (Join-Path $Root "Scripts") -PathType Container)
    registry_exists          = (Test-Path -LiteralPath (Join-Path $Root "Config\general_tool_registry.yaml") -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $Root "Config\private_tool_registry.yaml") -PathType Leaf)
    workshop_mode            = if ($ResolvedWorkshopIdentity.PSObject.Properties.Name -contains "workshop_label" -and -not [string]::IsNullOrWhiteSpace([string]$ResolvedWorkshopIdentity.workshop_label)) { [string]$ResolvedWorkshopIdentity.workshop_label } else { $ResolvedWorkshopMode }
    workshop_name            = if ($ResolvedWorkshopIdentity.PSObject.Properties.Name -contains "display_name" -and -not [string]::IsNullOrWhiteSpace([string]$ResolvedWorkshopIdentity.display_name)) { [string]$ResolvedWorkshopIdentity.display_name } else { "COOPER" }
    default_model            = if ($ResolvedWorkshopIdentity.PSObject.Properties.Name -contains "default_model" -and -not [string]::IsNullOrWhiteSpace([string]$ResolvedWorkshopIdentity.default_model)) { [string]$ResolvedWorkshopIdentity.default_model } else { "Claude Sonnet" }
    cloud_allowed            = if ($ResolvedWorkshopIdentity.PSObject.Properties.Name -contains "cloud_allowed") { [bool]$ResolvedWorkshopIdentity.cloud_allowed } else { $true }
    active_registry          = if ($ResolvedWorkshopIdentity.PSObject.Properties.Name -contains "registry" -and -not [string]::IsNullOrWhiteSpace([string]$ResolvedWorkshopIdentity.registry)) { [string]$ResolvedWorkshopIdentity.registry } else { "Config/general_tool_registry.yaml" }
    status_workflow          = "WF-004 Operational Status"
    status_source            = "Scripts/Get-COOPEROperationalStatus.ps1"
    current_phase            = $CurrentPhase
    operational_workflow_count = [int]$OperationalWorkflowCount
    workflow_definition_count  = [int]$WorkflowDefinitionCount
    workflow_definitions     = @($WorkflowDefinitionSummary)
    operational_workflows    = @($OperationalWorkflows)
    operational_chains       = @($WorkflowChains)
    known_capabilities       = @($KnownCapabilities | Select-Object -Unique)
    known_issues             = @($KnownBlockers)
    recent_activity          = @($RecentDecisions)
    recommended_next_action  = if ($OperationalWorkflowCount -gt 0) { "Ask for a research summary, Codex task, note creation, or collection import draft." } else { "Restore workflow definitions before dispatching governed work." }
    project_memory           = $ProjectMemory
    skill_state              = $SkillSummary
    last_successful_workflow = $LastSuccessfulWorkflow
    last_failed_workflow     = $LastFailedWorkflow
    security_sources         = $SecuritySources
    summary_lines            = @($StatusLines)
    status_lines             = @($StatusLines)
    response_text            = $ResponseText
    source_of_truth          = "Scripts/Get-COOPEROperationalStatus.ps1"
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    return
}

return $Result
