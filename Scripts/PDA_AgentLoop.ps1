function Get-PDAAgentRunRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Join-Path $Root "PDA-Agent-Runs")
}

function Get-PDAAgentRunIndexPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Join-Path (Get-PDAAgentRunRoot -Root $Root) "index.json")
}

function Get-PDAAgentRunPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Join-Path (Get-PDAAgentRunRoot -Root $Root) ("{0}.json" -f $RunId))
}

function Get-PDAAgentRunMarkdownPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Join-Path (Get-PDAAgentRunRoot -Root $Root) ("{0}.md" -f $RunId))
}

function ConvertTo-PDAAgentHashtable {
    param([Parameter(Mandatory = $false)]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string] -or
        $Value -is [char] -or
        $Value -is [bool] -or
        $Value -is [byte] -or
        $Value -is [sbyte] -or
        $Value -is [int16] -or
        $Value -is [int] -or
        $Value -is [int64] -or
        $Value -is [uint16] -or
        $Value -is [uint32] -or
        $Value -is [uint64] -or
        $Value -is [single] -or
        $Value -is [double] -or
        $Value -is [decimal] -or
        $Value -is [datetime] -or
        $Value -is [timespan] -or
        $Value -is [guid] -or
        $Value -is [uri] -or
        $Value.GetType().IsEnum) {
        return $Value
    }

    if ($Value -is [hashtable] -or $Value -is [System.Collections.IDictionary]) {
        $Copy = @{}
        foreach ($Key in $Value.Keys) {
            $Copy[$Key] = ConvertTo-PDAAgentHashtable -Value $Value[$Key]
        }
        return $Copy
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $List = @()
        foreach ($Item in $Value) {
            $List += ,(ConvertTo-PDAAgentHashtable -Value $Item)
        }
        return $List
    }

    if ($Value -is [psobject] -and $Value.PSObject.Properties.Name.Count -gt 0) {
        $Copy = @{}
        foreach ($Prop in $Value.PSObject.Properties) {
            $Copy[$Prop.Name] = ConvertTo-PDAAgentHashtable -Value $Prop.Value
        }
        return $Copy
    }

    return $Value
}

function Read-PDAAgentJsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

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

function Get-PDAAgentToolRegistryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Join-Path $Root "Scripts\PDA_AgentToolRegistry.json")
}

function Get-PDAAgentToolRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $RegistryPath = Get-PDAAgentToolRegistryPath -Root $Root
    if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) {
        throw "Agent tool registry missing: $RegistryPath"
    }

    $Registry = Get-Content -LiteralPath $RegistryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $Tools = @($Registry.tools)
    $Registry | Add-Member -NotePropertyName status -NotePropertyValue "pass" -Force
    $Registry | Add-Member -NotePropertyName registry_path -NotePropertyValue $RegistryPath -Force
    $Registry | Add-Member -NotePropertyName tool_count -NotePropertyValue @($Tools).Count -Force
    $Registry | Add-Member -NotePropertyName local_only_count -NotePropertyValue @($Tools | Where-Object { [bool]$_.supports_local_only }).Count -Force
    $Registry | Add-Member -NotePropertyName cloud_capable_count -NotePropertyValue @($Tools | Where-Object { -not [bool]$_.supports_local_only }).Count -Force
    $Registry | Add-Member -NotePropertyName requires_approval_count -NotePropertyValue @($Tools | Where-Object { [bool]$_.requires_approval }).Count -Force
    return $Registry
}

function Get-PDAAgentToolDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Registry = Get-PDAAgentToolRegistry -Root $Root
    $NormalizedName = [string]$ToolName.Trim().ToLowerInvariant()
    return @($Registry.tools | Where-Object { [string]$_.tool_name.Trim().ToLowerInvariant() -eq $NormalizedName } | Select-Object -First 1)[0]
}

function Test-PDAAgentToolAllowedForCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("category_1", "category_2", "restricted_local")]
        [string]$Category,

        [Parameter(Mandatory = $false)]
        [switch]$RequiresLocalOnly,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Tool = Get-PDAAgentToolDefinition -ToolName $ToolName -Root $Root
    if (-not $Tool) {
        return [pscustomobject]@{
            status              = "blocked"
            allowed             = $false
            blocked_reason      = "Tool '$ToolName' is not registered."
            tool_name           = [string]$ToolName
            display_name        = [string]$ToolName
            tool_type           = ""
            risk_level          = "unknown"
            requires_approval   = $false
            supports_category2  = $false
            supports_local_only = $false
            dispatch_method     = ""
            capability_path     = ""
            tool                = $null
        }
    }

    $Allowed = $true
    $BlockedReason = ""
    if ($RequiresLocalOnly -and -not [bool]$Tool.supports_local_only) {
        $Allowed = $false
        $BlockedReason = "Tool '$($Tool.tool_name)' is not local-only."
    }
    elseif ($Category -eq "category_2" -and -not [bool]$Tool.supports_category2) {
        $Allowed = $false
        $BlockedReason = "Tool '$($Tool.tool_name)' is not approved for Category 2."
    }

    $DisplayName = [string]$Tool.tool_name
    if ($Tool.PSObject.Properties.Name -contains "display_name") {
        $CandidateDisplayName = [string]$Tool.display_name
        if (-not [string]::IsNullOrWhiteSpace($CandidateDisplayName)) {
            $DisplayName = $CandidateDisplayName
        }
    }

    return [pscustomobject]@{
        status              = $(if ($Allowed) { "pass" } else { "blocked" })
        allowed             = $Allowed
        blocked_reason      = $BlockedReason
        tool_name           = [string]$Tool.tool_name
        display_name        = $DisplayName
        tool_type           = [string]$Tool.tool_type
        risk_level          = [string]$Tool.risk_level
        requires_approval   = [bool]$Tool.requires_approval
        supports_category2  = [bool]$Tool.supports_category2
        supports_local_only = [bool]$Tool.supports_local_only
        dispatch_method     = [string]$Tool.dispatch_method
        notes               = if ($Tool.PSObject.Properties.Name -contains "notes") { [string]$Tool.notes } else { "" }
        tool                = $Tool
    }
}

function Get-PDAAgentRunIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $RunRoot = Get-PDAAgentRunRoot -Root $Root
    $IndexPath = Get-PDAAgentRunIndexPath -Root $Root
    $RunFiles = @()
    if (Test-Path -LiteralPath $RunRoot -PathType Container) {
        $RunFiles = @(Get-ChildItem -LiteralPath $RunRoot -File -Filter *.json -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "index.json" })
    }

    $Runs = @()
    foreach ($File in @($RunFiles | Sort-Object LastWriteTimeUtc -Descending)) {
        $Run = Read-PDAAgentJsonFile -Path $File.FullName
        if (-not $Run) {
            continue
        }

        $CurrentStep = $null
        if ($Run.PSObject.Properties.Name -contains "current_step" -and $Run.current_step) {
            $CurrentStep = $Run.current_step
        }

        $Runs += [pscustomobject]@{
            run_id             = if ($Run.PSObject.Properties.Name -contains "run_id") { [string]$Run.run_id } else { [string]$File.BaseName }
            goal               = if ($Run.PSObject.Properties.Name -contains "goal") { [string]$Run.goal } else { "" }
            category           = if ($Run.PSObject.Properties.Name -contains "category") { [string]$Run.category } else { "" }
            status             = if ($Run.PSObject.Properties.Name -contains "status") { [string]$Run.status } else { "unknown" }
            approval_status    = if ($Run.PSObject.Properties.Name -contains "approval_status") { [string]$Run.approval_status } else { "" }
            current_step_index  = if ($Run.PSObject.Properties.Name -contains "current_step_index") { [int]$Run.current_step_index } else { 0 }
            current_step_title  = if ($CurrentStep -and ($CurrentStep.PSObject.Properties.Name -contains "title")) { [string]$CurrentStep.title } else { "" }
            assigned_tool       = if ($Run.PSObject.Properties.Name -contains "assigned_tool") { [string]$Run.assigned_tool } else { "" }
            next_action         = if ($Run.PSObject.Properties.Name -contains "next_action") { [string]$Run.next_action } else { "" }
            iteration_count     = if ($Run.PSObject.Properties.Name -contains "iteration_count") { [int]$Run.iteration_count } else { 0 }
            max_iterations      = if ($Run.PSObject.Properties.Name -contains "max_iterations") { [int]$Run.max_iterations } else { 1 }
            created_at          = if ($Run.PSObject.Properties.Name -contains "created_at") { [string]$Run.created_at } else { "" }
            updated_at          = if ($Run.PSObject.Properties.Name -contains "updated_at") { [string]$Run.updated_at } else { "" }
            run_path            = $File.FullName
        }
    }

    $RunCount = @($Runs).Count
    $PendingApprovalCount = @($Runs | Where-Object { [string]$_.status -eq "pending_approval" -or [string]$_.approval_status -eq "pending" }).Count
    $ActiveRunCount = @($Runs | Where-Object { [string]$_.status -in @("pending_approval", "ready_for_action", "running", "reviewing") }).Count
    $BlockedCount = @($Runs | Where-Object { [string]$_.status -eq "blocked" }).Count
    $CompletedCount = @($Runs | Where-Object { [string]$_.status -eq "completed" }).Count
    $LatestRun = if ($RunCount -gt 0) { $Runs[0] } else { $null }

    $Index = [pscustomobject]@{
        status               = $(if ($RunCount -gt 0) { "pass" } else { "empty" })
        schema_version       = "1.0"
        store_path           = $RunRoot
        index_path           = $IndexPath
        run_count            = [int]$RunCount
        active_run_count     = [int]$ActiveRunCount
        pending_approval_count = [int]$PendingApprovalCount
        blocked_count        = [int]$BlockedCount
        completed_count      = [int]$CompletedCount
        latest_run           = $LatestRun
        runs                 = @($Runs)
        updated_at           = (Get-Date).ToUniversalTime().ToString("o")
    }

    return $Index
}

function Save-PDAAgentRunIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Index,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $RunRoot = Get-PDAAgentRunRoot -Root $Root
    New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
    $IndexPath = Get-PDAAgentRunIndexPath -Root $Root
    $Index.updated_at = (Get-Date).ToUniversalTime().ToString("o")
    $Index | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $IndexPath -Encoding UTF8
    return $IndexPath
}

function Get-PDAAgentRunRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $RunPath = Get-PDAAgentRunPath -RunId $RunId -Root $Root
    $Run = Read-PDAAgentJsonFile -Path $RunPath
    if ($Run -and (-not ($Run.PSObject.Properties.Name -contains "run_id"))) {
        $Run | Add-Member -NotePropertyName run_id -NotePropertyValue $RunId -Force
    }
    return $Run
}

function Get-PDAAgentRunSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Run
    )

    $CurrentStep = if ($Run.PSObject.Properties.Name -contains "current_step" -and $Run.current_step) { $Run.current_step } else { $null }
    return [pscustomobject]@{
        run_id            = if ($Run.PSObject.Properties.Name -contains "run_id") { [string]$Run.run_id } else { "" }
        goal              = if ($Run.PSObject.Properties.Name -contains "goal") { [string]$Run.goal } else { "" }
        category          = if ($Run.PSObject.Properties.Name -contains "category") { [string]$Run.category } else { "" }
        status            = if ($Run.PSObject.Properties.Name -contains "status") { [string]$Run.status } else { "" }
        approval_status   = if ($Run.PSObject.Properties.Name -contains "approval_status") { [string]$Run.approval_status } else { "" }
        approval_id       = if ($Run.PSObject.Properties.Name -contains "approval_id") { [string]$Run.approval_id } else { "" }
        approval_path     = if ($Run.PSObject.Properties.Name -contains "approval_path") { [string]$Run.approval_path } else { "" }
        approval_required = if ($Run.PSObject.Properties.Name -contains "approval_required") { [bool]$Run.approval_required } else { $false }
        assigned_tool     = if ($Run.PSObject.Properties.Name -contains "assigned_tool") { [string]$Run.assigned_tool } else { "" }
        current_step_id   = if ($CurrentStep -and ($CurrentStep.PSObject.Properties.Name -contains "step_id")) { [string]$CurrentStep.step_id } else { "" }
        current_step      = if ($CurrentStep -and ($CurrentStep.PSObject.Properties.Name -contains "title")) { [string]$CurrentStep.title } else { "" }
        next_action       = if ($Run.PSObject.Properties.Name -contains "next_action") { [string]$Run.next_action } else { "" }
        iteration_count   = if ($Run.PSObject.Properties.Name -contains "iteration_count") { [int]$Run.iteration_count } else { 0 }
        max_iterations    = if ($Run.PSObject.Properties.Name -contains "max_iterations") { [int]$Run.max_iterations } else { 1 }
        created_at        = if ($Run.PSObject.Properties.Name -contains "created_at") { [string]$Run.created_at } else { "" }
        updated_at        = if ($Run.PSObject.Properties.Name -contains "updated_at") { [string]$Run.updated_at } else { "" }
    }
}

function Get-PDAAgentCurrentStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Run
    )

    $Steps = @()
    if ($Run.PSObject.Properties.Name -contains "plan" -and $Run.plan -and $Run.plan.PSObject.Properties.Name -contains "subtasks") {
        $Steps = @($Run.plan.subtasks)
    }

    $Index = 0
    if ($Run.PSObject.Properties.Name -contains "current_step_index") {
        $Index = [int]$Run.current_step_index
    }

    if ($Steps.Count -eq 0 -or $Index -lt 0 -or $Index -ge $Steps.Count) {
        return $null
    }

    $Step = $Steps[$Index]
    return [pscustomobject]@{
        step_id               = if ($Step.PSObject.Properties.Name -contains "task_id") { [string]$Step.task_id } else { if ($Step.PSObject.Properties.Name -contains "step_id") { [string]$Step.step_id } else { "" } }
        title                 = if ($Step.PSObject.Properties.Name -contains "title") { [string]$Step.title } else { "" }
        task_type             = if ($Step.PSObject.Properties.Name -contains "task_type") { [string]$Step.task_type } else { "" }
        recommended_executor  = if ($Step.PSObject.Properties.Name -contains "recommended_executor") { [string]$Step.recommended_executor } else { "" }
        required_capabilities = if ($Step.PSObject.Properties.Name -contains "required_capabilities") { @($Step.required_capabilities) } else { @() }
        dependency_chain      = if ($Step.PSObject.Properties.Name -contains "dependency_chain") { @($Step.dependency_chain) } else { @() }
        output                = if ($Step.PSObject.Properties.Name -contains "output") { [string]$Step.output } else { "" }
        status                = if ($Step.PSObject.Properties.Name -contains "status") { [string]$Step.status } else { "planned" }
        approval_required     = $true
    }
}

function New-PDAAgentActionRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Run,

        [Parameter(Mandatory = $true)]
        [object]$Step
    )

    $StepNumber = if ($Run.PSObject.Properties.Name -contains "current_step_index") { [int]$Run.current_step_index + 1 } else { 1 }
    $TaskType = if ($Step.PSObject.Properties.Name -contains "task_type") { [string]$Step.task_type } else { "" }
    $Executor = if ($Step.PSObject.Properties.Name -contains "recommended_executor") { [string]$Step.recommended_executor } else { "" }
    $Output = if ($Step.PSObject.Properties.Name -contains "output") { [string]$Step.output } else { "" }
    $Title = if ($Step.PSObject.Properties.Name -contains "title") { [string]$Step.title } else { "Agent step" }
    $ActionText = "Approve step {0}: {1}. Executor: {2}. Expected output: {3}" -f $StepNumber, $Title, $(if ($Executor) { $Executor } else { "unspecified" }), $(if ($Output) { $Output } else { "structured result" })

    return [pscustomobject]@{
        action_id           = if ($Run.PSObject.Properties.Name -contains "run_id") { "{0}-step-{1:00}" -f [string]$Run.run_id, $StepNumber } else { "agent-step-{0:00}" -f $StepNumber }
        run_id              = if ($Run.PSObject.Properties.Name -contains "run_id") { [string]$Run.run_id } else { "" }
        step_number         = [int]$StepNumber
        step_id             = if ($Step.PSObject.Properties.Name -contains "step_id") { [string]$Step.step_id } else { "" }
        title               = $Title
        task_type           = $TaskType
        assigned_tool       = $Executor
        action_request      = $ActionText
        required_capabilities = if ($Step.PSObject.Properties.Name -contains "required_capabilities") { @($Step.required_capabilities) } else { @() }
        completion_criteria = if ($Run.PSObject.Properties.Name -contains "completion_criteria") { @($Run.completion_criteria) } else { @() }
        approval_required   = $true
        dispatch_ready      = $false
        category            = if ($Run.PSObject.Properties.Name -contains "category") { [string]$Run.category } else { "category_1" }
        status              = "pending_approval"
        next_action         = "Approve the action before any tool execution."
    }
}

function Get-PDAAgentNextAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Run
    )

    if ($Run.PSObject.Properties.Name -contains "stop_reason" -and -not [string]::IsNullOrWhiteSpace([string]$Run.stop_reason)) {
        return [string]$Run.stop_reason
    }

    $Status = if ($Run.PSObject.Properties.Name -contains "status") { [string]$Run.status } else { "" }
    $CurrentStep = Get-PDAAgentCurrentStep -Run $Run
    if ($Status -eq "completed") {
        return "Agent run complete."
    }
    if ($Status -eq "blocked") {
        return $(if ($Run.PSObject.Properties.Name -contains "stop_reason") { [string]$Run.stop_reason } else { "Agent run blocked." })
    }
    if ($Status -eq "ready_for_action") {
        if ($CurrentStep) {
            return "Run the approved action with $([string]$Run.assigned_tool)."
        }
        return "Approve the next action before execution."
    }
    if ($Status -eq "reviewing") {
        if ($CurrentStep) {
            return "Review the result and approve the next step: $($CurrentStep.title)."
        }
        return "Review the result and decide whether to continue."
    }
    if ($Status -eq "pending_approval" -and $CurrentStep) {
        return "Approve step $((([int]$Run.current_step_index) + 1)): $($CurrentStep.title)."
    }
    return "Approve the current action to continue."
}

function Write-PDAAgentRunMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Run,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $RunId = if ($Run.PSObject.Properties.Name -contains "run_id") { [string]$Run.run_id } else { "" }
    $Goal = if ($Run.PSObject.Properties.Name -contains "goal") { [string]$Run.goal } else { "" }
    $Status = if ($Run.PSObject.Properties.Name -contains "status") { [string]$Run.status } else { "" }
    $ApprovalStatus = if ($Run.PSObject.Properties.Name -contains "approval_status") { [string]$Run.approval_status } else { "" }
    $Category = if ($Run.PSObject.Properties.Name -contains "category") { [string]$Run.category } else { "" }
    $AssignedTool = if ($Run.PSObject.Properties.Name -contains "assigned_tool") { [string]$Run.assigned_tool } else { "" }
    $IterationCount = if ($Run.PSObject.Properties.Name -contains "iteration_count") { [int]$Run.iteration_count } else { 0 }
    $MaxIterations = if ($Run.PSObject.Properties.Name -contains "max_iterations") { [int]$Run.max_iterations } else { 0 }
    $ActionRequestText = ""
    if ($Run.PSObject.Properties.Name -contains "action_request" -and $Run.action_request) {
        if ($Run.action_request.PSObject.Properties.Name -contains "action_request") {
            $ActionRequestText = [string]$Run.action_request.action_request
        }
        elseif ($Run.action_request.PSObject.Properties.Name -contains "action_request_text") {
            $ActionRequestText = [string]$Run.action_request.action_request_text
        }
    }

    $GoalType = ""
    if ($Run.PSObject.Properties.Name -contains "plan" -and $Run.plan -and $Run.plan.PSObject.Properties.Name -contains "goal_type") {
        $GoalType = [string]$Run.plan.goal_type
    }

    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add("# PDA Agent Run")
    $Lines.Add("")
    $Lines.Add(("Run ID: {0}" -f $RunId))
    $Lines.Add(("Goal: {0}" -f $Goal))
    $Lines.Add(("Status: {0}" -f $Status))
    $Lines.Add(("Approval status: {0}" -f $ApprovalStatus))
    $ApprovalId = if ($Run.PSObject.Properties.Name -contains "approval_id") { [string]$Run.approval_id } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($ApprovalId)) {
        $Lines.Add(("Approval ID: {0}" -f $ApprovalId))
    }
    $Lines.Add(("Category: {0}" -f $Category))
    $Lines.Add(("Assigned tool: {0}" -f $AssignedTool))
    $Lines.Add(("Iteration count: {0}" -f $IterationCount))
    $Lines.Add(("Max iterations: {0}" -f $MaxIterations))
    $Lines.Add(("Next action: {0}" -f (Get-PDAAgentNextAction -Run $Run)))
    $Lines.Add("")
    $Lines.Add("## Current Step")
    $Lines.Add("")
    $CurrentStep = Get-PDAAgentCurrentStep -Run $Run
    if ($CurrentStep) {
        $Lines.Add(("Step: {0}" -f $CurrentStep.step_id))
        $Lines.Add(("Title: {0}" -f $CurrentStep.title))
        $Lines.Add(("Task type: {0}" -f $CurrentStep.task_type))
        $Lines.Add(("Recommended executor: {0}" -f $CurrentStep.recommended_executor))
        $Lines.Add(("Action request: {0}" -f $ActionRequestText))
        $Lines.Add(("Completion criteria: {0}" -f (($Run.completion_criteria | ForEach-Object { [string]$_ }) -join ", ")))
    }
    else {
        $Lines.Add("- No current step selected.")
    }
    $Lines.Add("")
    $Lines.Add("## Plan")
    $Lines.Add("")
    if ($Run.PSObject.Properties.Name -contains "plan" -and $Run.plan) {
        $Lines.Add(("Goal type: {0}" -f $GoalType))
        $Lines.Add(("Deliverables: {0}" -f (($Run.plan.deliverables | ForEach-Object { [string]$_ }) -join ", ")))
        $Lines.Add("")
        if ($Run.plan.PSObject.Properties.Name -contains "subtasks" -and @($Run.plan.subtasks).Count -gt 0) {
            $Lines.Add("Subtasks:")
            foreach ($Step in @($Run.plan.subtasks)) {
                $TaskId = if ($Step.PSObject.Properties.Name -contains "task_id") { [string]$Step.task_id } else { "" }
                $Title = if ($Step.PSObject.Properties.Name -contains "title") { [string]$Step.title } else { "" }
                $Executor = if ($Step.PSObject.Properties.Name -contains "recommended_executor") { [string]$Step.recommended_executor } else { "" }
                $Lines.Add(("- {0} | {1} | {2}" -f $TaskId, $Title, $Executor))
            }
        }
    }
    else {
        $Lines.Add("- No plan available.")
    }

    $Directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    ($Lines -join "`r`n") | Set-Content -LiteralPath $Path -Encoding UTF8
}
