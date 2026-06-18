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
$ApprovalWorkflowScript = Join-Path $PSScriptRoot "PDA_ApprovalWorkflow.ps1"
if (Test-Path -LiteralPath $DefinitionsScript -PathType Leaf) {
    . $DefinitionsScript
}
if (Test-Path -LiteralPath $ApprovalWorkflowScript -PathType Leaf) {
    . $ApprovalWorkflowScript
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

function Get-COOPERStatusTimestamp {
    param([Parameter(Mandatory = $false)]$Value)

    if ($null -eq $Value) {
        return [datetime]::MinValue
    }

    foreach ($Property in @("updated_at", "request_timestamp", "response_timestamp", "approval_checked_at", "created_at", "recorded_at", "timestamp")) {
        if ($Value.PSObject.Properties.Name -contains $Property -and -not [string]::IsNullOrWhiteSpace([string]$Value.$Property)) {
            try {
                return [datetime]::Parse([string]$Value.$Property).ToUniversalTime()
            }
            catch {}
        }
    }

    return [datetime]::MinValue
}

function Get-COOPERUniqueStrings {
    param([Parameter(Mandatory = $false)]$Values)

    $Seen = New-Object System.Collections.Generic.HashSet[string]
    $Unique = New-Object System.Collections.Generic.List[string]
    foreach ($Value in @($Values)) {
        $Text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($Text)) {
            continue
        }

        if ($Seen.Add($Text)) {
            $Unique.Add($Text) | Out-Null
        }
    }

    return @($Unique)
}

function Get-COOPERWorkflowStatusLabel {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkflowId,

        [Parameter(Mandatory = $false)]
        $ProjectMemory,

        [Parameter(Mandatory = $false)]
        $SkillsState
    )

    $BrokenWorkflows = @()
    if ($ProjectMemory -and $ProjectMemory.PSObject.Properties.Name -contains "broken_workflows") {
        $BrokenWorkflows = @(ConvertTo-COOPERStatusList -Value $ProjectMemory.broken_workflows)
    }

    $LastFailedWorkflowId = ""
    if ($ProjectMemory -and $ProjectMemory.PSObject.Properties.Name -contains "last_failed_workflow" -and $ProjectMemory.last_failed_workflow -and $ProjectMemory.last_failed_workflow.PSObject.Properties.Name -contains "workflow_id") {
        $LastFailedWorkflowId = [string]$ProjectMemory.last_failed_workflow.workflow_id
    }

    if ($BrokenWorkflows -contains $WorkflowId -or $LastFailedWorkflowId -eq $WorkflowId) {
        return "fail"
    }

    if ($SkillsState -and $SkillsState.PSObject.Properties.Name -contains "skills") {
        foreach ($Skill in @($SkillsState.skills)) {
            if ([string]$Skill.workflow_id -ne $WorkflowId) {
                continue
            }

            $SkillStatus = [string]$Skill.status
            if ($SkillStatus -match '^(operational|ready|pass)$') {
                return "pass"
            }
            if ($SkillStatus -match '^(fail|failed|blocked|unknown)$') {
                return "unknown"
            }
        }
    }

    if ($ProjectMemory -and $ProjectMemory.PSObject.Properties.Name -contains "last_successful_workflow" -and $ProjectMemory.last_successful_workflow -and $ProjectMemory.last_successful_workflow.PSObject.Properties.Name -contains "workflow_id") {
        if ([string]$ProjectMemory.last_successful_workflow.workflow_id -eq $WorkflowId) {
            return "pass"
        }
    }

    if ($ProjectMemory -and $ProjectMemory.PSObject.Properties.Name -contains "recent_decisions") {
        foreach ($Decision in @($ProjectMemory.recent_decisions)) {
            if ([string]$Decision.workflow_id -ne $WorkflowId) {
                continue
            }

            if ([string]$Decision.decision -match '(?i)\bcompleted successfully\b') {
                return "pass"
            }
            if ([string]$Decision.decision -match '(?i)\bfailed\b') {
                return "fail"
            }
        }
    }

    return "unknown"
}

function Find-COOPERArtifactPathByName {
    param(
        [Parameter(Mandatory = $false)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($FileName)) {
        return ""
    }

    $SearchRoots = @(
        (Join-Path $Root "Codex_Tasks"),
        (Join-Path $Root "Outputs"),
        (Join-Path $Root "PDA-Outputs"),
        (Join-Path $Root "PDA-Tasks"),
        (Join-Path $Root "Obsidian Vault"),
        (Join-Path $Root "PDA-Obsidian-Vault")
    )

    foreach ($SearchRoot in $SearchRoots) {
        if (-not (Test-Path -LiteralPath $SearchRoot -PathType Container)) {
            continue
        }

        try {
            $Match = Get-ChildItem -Path $SearchRoot -Recurse -File -Filter $FileName -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($Match) {
                return [string]$Match.FullName
            }
        }
        catch {
            continue
        }
    }

    return ""
}

function Get-COOPERWorkflowArtifactPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkflowId,

        [Parameter(Mandatory = $false)]
        $ProjectMemory,

        [Parameter(Mandatory = $false)]
        $SkillsState,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    switch ([string]$WorkflowId) {
        "WF-001" {
            $SearchRoots = @(
                (Join-Path $Root "PDA-Tasks\results"),
                (Join-Path $Root "Outputs"),
                (Join-Path $Root "PDA-Outputs"),
                (Join-Path $Root "Obsidian Vault")
            )

            foreach ($SearchRoot in $SearchRoots) {
                if (-not (Test-Path -LiteralPath $SearchRoot -PathType Container)) {
                    continue
                }

                try {
                    $Candidates = @(
                        Get-ChildItem -Path $SearchRoot -Recurse -File -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -match 'WF-001|research-output|result\.json$' } |
                            Sort-Object -Descending -Property LastWriteTime
                    )

                    foreach ($File in $Candidates) {
                        try {
                            $Content = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop
                        }
                        catch {
                            continue
                        }

                        if ([string]::IsNullOrWhiteSpace($Content)) {
                            continue
                        }

                        if ($Content -match '(?i)"task_id"\s*:\s*"WF-001"' -or $Content -match '(?i)#\s*WF-001 Research Summary') {
                            try {
                                $Record = $Content | ConvertFrom-Json -ErrorAction Stop
                            }
                            catch {
                                $Record = $null
                            }

                            if ($Record) {
                                if ($Record.PSObject.Properties.Name -contains "saved_path" -and -not [string]::IsNullOrWhiteSpace([string]$Record.saved_path)) {
                                    return [string]$Record.saved_path
                                }
                                if ($Record.PSObject.Properties.Name -contains "output" -and $Record.output -and $Record.output.PSObject.Properties.Name -contains "markdown_path" -and -not [string]::IsNullOrWhiteSpace([string]$Record.output.markdown_path)) {
                                    return [string]$Record.output.markdown_path
                                }
                                if ($Record.PSObject.Properties.Name -contains "output_path" -and -not [string]::IsNullOrWhiteSpace([string]$Record.output_path)) {
                                    return [string]$Record.output_path
                                }
                                if ($Record.PSObject.Properties.Name -contains "result_path" -and -not [string]::IsNullOrWhiteSpace([string]$Record.result_path)) {
                                    return [string]$Record.result_path
                                }
                            }

                            return [string]$File.FullName
                        }
                    }
                }
                catch {}
            }
        }
        "WF-002" {
            if ($ProjectMemory -and $ProjectMemory.PSObject.Properties.Name -contains "last_successful_workflow" -and $ProjectMemory.last_successful_workflow -and [string]$ProjectMemory.last_successful_workflow.workflow_id -eq "WF-002" -and -not [string]::IsNullOrWhiteSpace([string]$ProjectMemory.last_successful_workflow.output_path)) {
                return [string]$ProjectMemory.last_successful_workflow.output_path
            }

            if ($SkillsState -and $SkillsState.PSObject.Properties.Name -contains "skills") {
                foreach ($Skill in @($SkillsState.skills)) {
                    if ([string]$Skill.workflow_id -eq "WF-002" -and -not [string]::IsNullOrWhiteSpace([string]$Skill.example_output)) {
                        $ArtifactPath = Find-COOPERArtifactPathByName -FileName [string]$Skill.example_output -Root $Root
                        if (-not [string]::IsNullOrWhiteSpace($ArtifactPath)) {
                            return $ArtifactPath
                        }
                    }
                }
            }
        }
        "WF-006" {
            if ($SkillsState -and $SkillsState.PSObject.Properties.Name -contains "skills") {
                foreach ($Skill in @($SkillsState.skills)) {
                    if ([string]$Skill.workflow_id -eq "WF-006" -and -not [string]::IsNullOrWhiteSpace([string]$Skill.example_output)) {
                        $ArtifactPath = Find-COOPERArtifactPathByName -FileName [string]$Skill.example_output -Root $Root
                        if (-not [string]::IsNullOrWhiteSpace($ArtifactPath)) {
                            return $ArtifactPath
                        }
                    }
                }
            }
        }
        "WF-007" {
            if ($ProjectMemory -and $ProjectMemory.PSObject.Properties.Name -contains "last_successful_workflow" -and $ProjectMemory.last_successful_workflow -and [string]$ProjectMemory.last_successful_workflow.workflow_id -eq "WF-007" -and -not [string]::IsNullOrWhiteSpace([string]$ProjectMemory.last_successful_workflow.output_path)) {
                return [string]$ProjectMemory.last_successful_workflow.output_path
            }

            if ($SkillsState -and $SkillsState.PSObject.Properties.Name -contains "skills") {
                foreach ($Skill in @($SkillsState.skills)) {
                    if ([string]$Skill.workflow_id -eq "WF-007" -and -not [string]::IsNullOrWhiteSpace([string]$Skill.example_output)) {
                        $ArtifactPath = Find-COOPERArtifactPathByName -FileName [string]$Skill.example_output -Root $Root
                        if (-not [string]::IsNullOrWhiteSpace($ArtifactPath)) {
                            return $ArtifactPath
                        }
                    }
                }
            }
        }
        "WF-005" {
            if ($SkillsState -and $SkillsState.PSObject.Properties.Name -contains "skills") {
                foreach ($Skill in @($SkillsState.skills)) {
                    if ([string]$Skill.workflow_id -eq "WF-005" -and -not [string]::IsNullOrWhiteSpace([string]$Skill.example_output)) {
                        $ArtifactPath = Find-COOPERArtifactPathByName -FileName [string]$Skill.example_output -Root $Root
                        if (-not [string]::IsNullOrWhiteSpace($ArtifactPath)) {
                            return $ArtifactPath
                        }
                    }
                }
            }
        }
    }

    return ""
}

function Get-COOPERWorkflowExecutionStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkflowId,

        [Parameter(Mandatory = $false)]
        $ProjectMemory,

        [Parameter(Mandatory = $false)]
        $SkillsState,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    switch ([string]$WorkflowId) {
        "WF-004" {
            return "pass"
        }
        "WF-002" {
            if ($ProjectMemory -and $ProjectMemory.PSObject.Properties.Name -contains "last_successful_workflow" -and $ProjectMemory.last_successful_workflow -and [string]$ProjectMemory.last_successful_workflow.workflow_id -eq "WF-002") {
                return "pass"
            }
        }
        "WF-005" {
            if ($SkillsState -and $SkillsState.PSObject.Properties.Name -contains "skills") {
                foreach ($Skill in @($SkillsState.skills)) {
                    if ([string]$Skill.workflow_id -eq "WF-005" -and [string]$Skill.status -match '^(operational|pass|ready)$') {
                        return "pass"
                    }
                }
            }
        }
        "WF-006" {
            if ($SkillsState -and $SkillsState.PSObject.Properties.Name -contains "skills") {
                foreach ($Skill in @($SkillsState.skills)) {
                    if ([string]$Skill.workflow_id -eq "WF-006" -and [string]$Skill.status -match '^(operational|pass|ready)$') {
                        return "pass"
                    }
                }
            }
        }
        "WF-007" {
            if ($ProjectMemory -and $ProjectMemory.PSObject.Properties.Name -contains "last_successful_workflow" -and $ProjectMemory.last_successful_workflow -and [string]$ProjectMemory.last_successful_workflow.workflow_id -eq "WF-007") {
                return "pass"
            }

            if ($SkillsState -and $SkillsState.PSObject.Properties.Name -contains "skills") {
                foreach ($Skill in @($SkillsState.skills)) {
                    if ([string]$Skill.workflow_id -eq "WF-007" -and [string]$Skill.status -match '^(operational|pass|ready)$') {
                        return "pass"
                    }
                }
            }
        }
        "WF-001" {
            $SearchRoots = @(
                (Join-Path $Root "PDA-Tasks\results"),
                (Join-Path $Root "Outputs"),
                (Join-Path $Root "PDA-Outputs"),
                (Join-Path $Root "Obsidian Vault")
            )

            foreach ($SearchRoot in $SearchRoots) {
                if (-not (Test-Path -LiteralPath $SearchRoot -PathType Container)) {
                    continue
                }

                try {
                    $Candidates = @(
                        Get-ChildItem -Path $SearchRoot -Recurse -File -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -match 'WF-001|research-output|result\.json$' } |
                            Sort-Object -Descending -Property LastWriteTime
                    )

                    foreach ($File in $Candidates) {
                        try {
                            $Content = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop
                        }
                        catch {
                            continue
                        }

                        if ([string]::IsNullOrWhiteSpace($Content)) {
                            continue
                        }

                        if ($Content -match '(?i)"task_id"\s*:\s*"WF-001"') {
                            if ($Content -match '(?i)"status"\s*:\s*"success"' -or $Content -match '# WF-001 Research Summary') {
                                return "pass"
                            }
                        }

                        if ($Content -match '(?i)#\s*WF-001 Research Summary' -and $Content -match '(?i)\bstatus\b.*\bsuccess\b') {
                            return "pass"
                        }
                    }
                }
                catch {}
            }

            if ($ProjectMemory -and $ProjectMemory.PSObject.Properties.Name -contains "recent_decisions") {
                foreach ($Decision in @($ProjectMemory.recent_decisions)) {
                    if ([string]$Decision.workflow_id -eq "WF-001" -and [string]$Decision.decision -match '(?i)\bcompleted successfully\b') {
                        return "pass"
                    }
                }
            }
        }
    }

    return "unknown"
}

function Get-COOPERApprovalWorkflowHealth {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $Summary = [ordered]@{
        pending_approval = 0
        approved = 0
        rejected = 0
        revision_requested = 0
        replan_requested = 0
        escalated = 0
        cancelled = 0
        completed = 0
        stale = 0
        blocked = 0
        pending = 0
        counts = [ordered]@{}
        source_of_truth = "PDA-Runtime/data/approval-workflows"
    }

    if (-not (Get-Command -Name Get-PDAApprovalWorkflowRecordCandidates -ErrorAction SilentlyContinue)) {
        return [pscustomobject]$Summary
    }

    $Store = $null
    if (Get-Command -Name Load-PDAApprovalWorkflowStore -ErrorAction SilentlyContinue) {
        try {
            $Store = Load-PDAApprovalWorkflowStore -Root $Root
        }
        catch {
            $Store = $null
        }
    }

    if ($Store -and $Store.PSObject.Properties.Name -contains "status_counts") {
        foreach ($Key in @("pending_approval", "approved", "rejected", "revision_requested", "replan_requested", "escalated", "cancelled", "completed")) {
            if ($Store.status_counts.PSObject.Properties.Name -contains $Key) {
                $Summary[$Key] = [int]$Store.status_counts.$Key
            }
        }
        if ($Store.PSObject.Properties.Name -contains "pending_approval_count") {
            $Summary.pending = [int]$Store.pending_approval_count
        }
        if ($Store.PSObject.Properties.Name -contains "blocked_count") {
            $Summary.blocked = [int]$Store.blocked_count
        }
    }

    $Records = @(Get-PDAApprovalWorkflowRecordCandidates -Root $Root)
    if ($Records.Count -eq 0) {
        return [pscustomobject]$Summary
    }

    $Grouped = @($Records | Group-Object -Property { [string]$_.approval_id })
    $CurrentRecords = New-Object System.Collections.Generic.List[object]
    foreach ($Group in $Grouped) {
        $Latest = @(
            $Group.Group |
                Sort-Object -Descending -Property @{
                    Expression = { Get-COOPERStatusTimestamp -Value $_ }
                } |
                Select-Object -First 1
        )[0]
        if ($Latest) {
            $CurrentRecords.Add($Latest) | Out-Null
        }
    }

    $Stale = 0
    foreach ($Group in $Grouped) {
        $Statuses = @($Group.Group | ForEach-Object { [string]$_.status } | Select-Object -Unique)
        if ($Statuses.Count -gt 1 -and $Statuses -contains "pending_approval") {
            $LatestStatus = [string]((@($Group.Group | Sort-Object -Descending -Property @{ Expression = { Get-COOPERStatusTimestamp -Value $_ } } | Select-Object -First 1)[0]).status)
            if ($LatestStatus -ne "pending_approval") {
                $Stale++
            }
        }
    }

    if ($Summary.pending_approval -eq 0) { $Summary.pending_approval = @($CurrentRecords | Where-Object { [string]$_.status -eq "pending_approval" }).Count }
    if ($Summary.approved -eq 0) { $Summary.approved = @($CurrentRecords | Where-Object { [string]$_.status -eq "approved" }).Count }
    if ($Summary.rejected -eq 0) { $Summary.rejected = @($CurrentRecords | Where-Object { [string]$_.status -eq "rejected" }).Count }
    if ($Summary.revision_requested -eq 0) { $Summary.revision_requested = @($CurrentRecords | Where-Object { [string]$_.status -eq "revision_requested" }).Count }
    if ($Summary.replan_requested -eq 0) { $Summary.replan_requested = @($CurrentRecords | Where-Object { [string]$_.status -eq "replan_requested" }).Count }
    if ($Summary.escalated -eq 0) { $Summary.escalated = @($CurrentRecords | Where-Object { [string]$_.status -eq "escalated" }).Count }
    if ($Summary.cancelled -eq 0) { $Summary.cancelled = @($CurrentRecords | Where-Object { [string]$_.status -eq "cancelled" }).Count }
    if ($Summary.completed -eq 0) { $Summary.completed = @($CurrentRecords | Where-Object { [string]$_.status -eq "completed" }).Count }
    if ($Summary.blocked -eq 0) { $Summary.blocked = @($CurrentRecords | Where-Object { [string]$_.status -in @("rejected", "cancelled") }).Count }
    $Summary.stale = [int]$Stale
    $Summary.counts = [ordered]@{
        pending_approval = [int]$Summary.pending_approval
        approved = [int]$Summary.approved
        rejected = [int]$Summary.rejected
        revision_requested = [int]$Summary.revision_requested
        replan_requested = [int]$Summary.replan_requested
        escalated = [int]$Summary.escalated
        cancelled = [int]$Summary.cancelled
        completed = [int]$Summary.completed
        stale = [int]$Stale
        blocked = [int]$Summary.blocked
        pending = [int]$Summary.pending_approval
    }

    return [pscustomobject]$Summary
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

    $NormalizedSourceText = ([string]$SourceText) -replace ([char]0x2192), '->'
    foreach ($Match in ([regex]::Matches([string]$NormalizedSourceText, 'WF-\d+\s*->\s*WF-\d+'))) {
        $Chain = ([string]$Match.Value.Trim()) -replace '\s*->\s*', ' -> '
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
            Sort-Object -Descending -Property @{
                Expression = {
                    if ($_.PSObject.Properties.Name -contains "date" -and -not [string]::IsNullOrWhiteSpace([string]$_.date)) {
                        try {
                            [datetime]::Parse([string]$_.date)
                        }
                        catch {
                            [datetime]::MinValue
                        }
                    }
                    else {
                        [datetime]::MinValue
                    }
                }
            } |
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
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Select-Object -Unique |
            Select-Object -First 3
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

$ApprovalHealth = Get-COOPERApprovalWorkflowHealth -Root $Root
$PendingApprovalCount = [int]$ApprovalHealth.pending_approval
$CompletedApprovalCount = [int]$ApprovalHealth.completed
$StaleApprovalCount = [int]$ApprovalHealth.stale
$BlockedApprovalCount = [int]$ApprovalHealth.blocked
$ApprovalStatusSummary = "pending: {0} | completed: {1} | stale: {2} | blocked: {3}" -f $PendingApprovalCount, $CompletedApprovalCount, $StaleApprovalCount, $BlockedApprovalCount

$WorkflowStatusEntries = @(
    $OperationalWorkflowDefinitions | ForEach-Object {
        $WorkflowId = [string]$_.id
        $WorkflowStatus = Get-COOPERWorkflowExecutionStatus -WorkflowId $WorkflowId -ProjectMemory $ProjectMemory -SkillsState $SkillsState -Root $Root
        $ArtifactPath = Get-COOPERWorkflowArtifactPath -WorkflowId $WorkflowId -ProjectMemory $ProjectMemory -SkillsState $SkillsState -Root $Root
        [pscustomobject]@{
            workflow_id         = $WorkflowId
            name                = [string]$_.name
            status              = $WorkflowStatus
            definition_status    = [string]$_.status
            approval_status     = if ([bool]$_.approval_required) { "approval required" } else { "approval not required" }
            last_run_artifact    = $ArtifactPath
            last_run_artifact_path = $ArtifactPath
        }
    }
)

$OperationalWorkflows = @(
    $OperationalWorkflowDefinitions | ForEach-Object {
        $WorkflowId = [string]$_.id
        $WorkflowStatus = @($WorkflowStatusEntries | Where-Object { [string]$_.workflow_id -eq $WorkflowId } | Select-Object -First 1)
        [pscustomobject]@{
            workflow_id        = $WorkflowId
            name               = [string]$_.name
            status             = if ($WorkflowStatus.Count -gt 0) { [string]$WorkflowStatus[0].status } else { "unknown" }
            definition_status  = [string]$_.status
            executor           = [string]$_.executor
            permission_lvl     = $_.permission_level
            storage_target     = [string]$_.storage_target
            approval_status    = if ($WorkflowStatus.Count -gt 0) { [string]$WorkflowStatus[0].approval_status } else { "approval required" }
            last_run_artifact  = if ($WorkflowStatus.Count -gt 0) { [string]$WorkflowStatus[0].last_run_artifact } else { "" }
        }
    }
)

$WorkflowDefinitionSummary = @(
    $WorkflowDefinitions | ForEach-Object {
        $WorkflowId = [string]$_.id
        $WorkflowStatus = @($WorkflowStatusEntries | Where-Object { [string]$_.workflow_id -eq $WorkflowId } | Select-Object -First 1)
        [pscustomobject]@{
            workflow_id       = $WorkflowId
            name              = [string]$_.name
            status            = [string]$_.status
            definition_status = [string]$_.status
            workflow_status   = if ($WorkflowStatus.Count -gt 0) { [string]$WorkflowStatus[0].status } else { "unknown" }
            executor          = [string]$_.executor
            storage_target    = [string]$_.storage_target
            approval_status   = if ($WorkflowStatus.Count -gt 0) { [string]$WorkflowStatus[0].approval_status } else { "approval required" }
            last_run_artifact = if ($WorkflowStatus.Count -gt 0) { [string]$WorkflowStatus[0].last_run_artifact } else { "" }
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
$ResponseLines.Add(("Approval / Pending Action: {0}" -f $ApprovalStatusSummary))
$ResponseLines.Add("")
$ResponseLines.Add(("Current Phase: {0}" -f $(if ([string]::IsNullOrWhiteSpace($CurrentPhase)) { "Unknown" } else { $CurrentPhase })))
$ResponseLines.Add("")
$ResponseLines.Add("Operational Workflow Status")
foreach ($Workflow in $OperationalWorkflows) {
    $ArtifactText = if (-not [string]::IsNullOrWhiteSpace([string]$Workflow.last_run_artifact)) { $Workflow.last_run_artifact } else { "unavailable" }
    $ResponseLines.Add(("- {0} {1} | status: {2} | approval: {3} | last artifact: {4}" -f $Workflow.workflow_id, $Workflow.name, $Workflow.status, $Workflow.approval_status, $ArtifactText))
}
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
    if ($PendingApprovalCount -gt 0) {
        $ResponseLines.Add(("- Review or clear the pending approval queue, then ask for a specific workflow.")) 
    }
    else {
        $ResponseLines.Add(("- Ask for a research summary, Codex task, note creation, or collection import draft."))
    }
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

$KnownLimitations = @()
$KnownLimitations += @($KnownBlockers)
if ($PendingApprovalCount -gt 0) {
    $KnownLimitations += "Pending approval queue contains $PendingApprovalCount item(s)."
}
$KnownLimitations += "Artifact paths are only reported when workflow state or local files expose them."

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
    workflow_statuses        = @($WorkflowStatusEntries)
    operational_chains       = @($WorkflowChains)
    known_capabilities       = @($KnownCapabilities | Select-Object -Unique)
    known_issues             = @($KnownBlockers)
    known_limitations        = @($KnownLimitations | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    approval_health          = $ApprovalHealth
    approval_or_pending_action_status = $ApprovalStatusSummary
    recent_activity          = @($RecentDecisions)
    recommended_next_action  = if ($OperationalWorkflowCount -gt 0) { if ($PendingApprovalCount -gt 0) { "Review or clear the pending approval queue, then ask for a specific workflow." } else { "Ask for a research summary, Codex task, note creation, or collection import draft." } } else { "Restore workflow definitions before dispatching governed work." }
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
