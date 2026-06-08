function Normalize-PDAGoalPlanningText {
    param([Parameter(Mandatory = $true)][string]$Value)

    $Normalized = [string]$Value
    $Normalized = $Normalized.ToLowerInvariant()
    $Normalized = $Normalized -replace '[^a-z0-9/\s]+', ' '
    $Normalized = $Normalized -replace '\s+', ' '
    return $Normalized.Trim()
}

function Get-PDACommanderGoalStorePath {
    param([Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot))

    return (Join-Path $Root "PDA-Runtime\data\commander-goals.json")
}

function Get-PDACommanderGoalStore {
    param([Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot))

    $Path = Get-PDACommanderGoalStorePath -Root $Root
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            status = "empty"
            store_path = $Path
            updated_at = ""
            plans = @()
        }
    }

    try {
        $Json = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not ($Json.PSObject.Properties.Name -contains "plans")) {
            $Json | Add-Member -NotePropertyName "plans" -NotePropertyValue @() -Force
        }
        if (-not ($Json.PSObject.Properties.Name -contains "store_path")) {
            $Json | Add-Member -NotePropertyName "store_path" -NotePropertyValue $Path -Force
        }
        if (-not ($Json.PSObject.Properties.Name -contains "status")) {
            $Json | Add-Member -NotePropertyName "status" -NotePropertyValue "pass" -Force
        }
        return $Json
    }
    catch {
        return [pscustomobject]@{
            status = "error"
            store_path = $Path
            updated_at = ""
            plans = @()
            error = $_.Exception.Message
        }
    }
}

function Save-PDACommanderGoalStore {
    param(
        [Parameter(Mandatory = $true)]
        [object]$PlanRecord,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $StorePath = Get-PDACommanderGoalStorePath -Root $Root
    $StoreDirectory = Split-Path -Parent $StorePath
    New-Item -ItemType Directory -Force -Path $StoreDirectory | Out-Null

    $Store = Get-PDACommanderGoalStore -Root $Root
    $Plans = @($Store.plans)
    $PlanId = if ($PlanRecord.PSObject.Properties.Name -contains "plan_id") { [string]$PlanRecord.plan_id } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($PlanId)) {
        $Plans = @($Plans | Where-Object { [string]$_.plan_id -ne $PlanId })
    }

    $Plans = @($PlanRecord) + @($Plans)
    if ($Plans.Count -gt 25) {
        $Plans = @($Plans | Select-Object -First 25)
    }

    $Store.status = "pass"
    $Store.store_path = $StorePath
    $Store.updated_at = (Get-Date).ToUniversalTime().ToString("o")
    $Store.plans = @($Plans)
    $Store | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $StorePath -Encoding UTF8

    return $StorePath
}

function Get-PDAGoalPlanningClassification {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $Normalized = Normalize-PDAGoalPlanningText -Value $Text
    $Category = "category_1"
    if ($Normalized -match '(?i)\b(api key|apikey|api_key|secret|credential|password|token|private|internal only|confidential)\b') {
        $Category = "category_2"
    }

    $GoalType = "general_goal"
    if ($Normalized -match '(?i)\b(filesystem|file system|repository|repositories|docker|container|containers|service inventory|service status|tool inventory|workspace inventory|environment awareness|environment inventory|file structure|organize folders|storage locations|scan c:\\|scan ~/|scan my filesystem|show my repositories|what ai services are running|help organize my folders|recommend a better project structure)\b') {
        $GoalType = "environment_awareness"
    }
    elseif ($Normalized -match '(?i)\b(classic literature|reading list|authors|books|synopses|synopsis|pdf)\b') {
        $GoalType = "research_report_pdf"
    }
    elseif ($Normalized -match '(?i)\b(research|investigate|sources|evidence)\b' -and $Normalized -match '(?i)\b(report|summary|summarize|brief)\b') {
        $GoalType = "research_report"
    }
    elseif ($Normalized -match '(?i)\b(study plan|learning plan|reading plan|book list)\b') {
        $GoalType = "learning_plan"
    }
    elseif ($Normalized -match '(?i)\b(roadmap|plan|strategy|what needs to happen|analyze my project)\b') {
        $GoalType = "goal_decomposition"
    }
    elseif ($Normalized -match '(?i)\b(research|investigate|sources|evidence)\b') {
        $GoalType = "research"
    }
    elseif ($Normalized -match '(?i)\b(report|summary|summarize|brief)\b') {
        $GoalType = "report"
    }

    $Deliverables = New-Object System.Collections.Generic.List[string]
    if ($GoalType -eq "environment_awareness") {
        $Deliverables.Add("filesystem inventory")
        $Deliverables.Add("repository inventory")
        $Deliverables.Add("docker inventory")
        $Deliverables.Add("service inventory")
        $Deliverables.Add("tool inventory")
        $Deliverables.Add("environment summary")
        $Deliverables.Add("organization recommendation")
        $Deliverables.Add("approval path")
    }
    if ($Normalized -match '(?i)\b(reading list|book list|classic literature|top books|books from famous authors|famous authors)\b') { $Deliverables.Add("reading list") }
    if ($Normalized -match '(?i)\b(authors?|author profiles?)\b') { $Deliverables.Add("author profiles") }
    if ($Normalized -match '(?i)\b(works?|books?|titles?)\b') { $Deliverables.Add("representative works") }
    if ($Normalized -match '(?i)\b(synopses?|synopsis|summaries?)\b') { $Deliverables.Add("book synopses") }
    if ($Normalized -match '(?i)\b(links?|sources?|references?|citations?)\b') { $Deliverables.Add("source links and references") }
    if ($Normalized -match '(?i)\b(report|summary|brief)\b') { $Deliverables.Add("written report") }
    if ($Normalized -match '(?i)\b(pdf)\b') { $Deliverables.Add("PDF export") }
    if ($Normalized -match '(?i)\b(guide|reading guide)\b') { $Deliverables.Add("reading guide") }
    if ($Normalized -match '(?i)\b(plan|roadmap|strategy)\b') { $Deliverables.Add("execution plan") }

    if ($Deliverables.Count -eq 0) {
        $Deliverables.Add("structured goal plan")
    }

    $UniqueDeliverables = @($Deliverables | Select-Object -Unique)

    $Complexity = "low"
    if ($UniqueDeliverables.Count -ge 5 -or $GoalType -eq "research_report_pdf") {
        $Complexity = "high"
    }
    elseif ($UniqueDeliverables.Count -ge 3 -or $GoalType -in @("research_report", "goal_decomposition")) {
        $Complexity = "medium"
    }

    $ApprovalRequired = $true
    if ($UniqueDeliverables.Count -eq 1 -and $GoalType -eq "general_goal") {
        $ApprovalRequired = $false
    }

    $RequiredCapabilities = New-Object System.Collections.Generic.List[string]
    switch ($GoalType) {
        "environment_awareness" {
            $RequiredCapabilities.Add("planning")
            $RequiredCapabilities.Add("reporting")
        }
        "research_report_pdf" {
            $RequiredCapabilities.Add("research")
            $RequiredCapabilities.Add("reporting")
            $RequiredCapabilities.Add("document_generation")
        }
        "research_report" {
            $RequiredCapabilities.Add("research")
            $RequiredCapabilities.Add("reporting")
        }
        "learning_plan" {
            $RequiredCapabilities.Add("knowledge_management")
            $RequiredCapabilities.Add("reporting")
        }
        "goal_decomposition" {
            $RequiredCapabilities.Add("planning")
            $RequiredCapabilities.Add("reporting")
        }
        "research" {
            $RequiredCapabilities.Add("research")
        }
        "report" {
            $RequiredCapabilities.Add("reporting")
        }
        default {
            $RequiredCapabilities.Add("planning")
        }
    }

    return [pscustomobject]@{
        status = "pass"
        category = $Category
        goal_type = $GoalType
        complexity = $Complexity
        deliverables = @($UniqueDeliverables)
        required_capabilities = @($RequiredCapabilities | Select-Object -Unique)
        approval_required = [bool]$ApprovalRequired
    }
}

function New-PDAGoalSubtaskRecord {
    param(
        [Parameter(Mandatory = $true)][int]$TaskNumber,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$TaskType,
        [Parameter(Mandatory = $true)][string[]]$Capabilities,
        [Parameter(Mandatory = $true)][string]$Executor,
        [Parameter(Mandatory = $false)][string[]]$Dependencies = @(),
        [Parameter(Mandatory = $true)][string]$Output
    )

    return [pscustomobject]@{
        task_id = ("goal-step-{0:00}" -f $TaskNumber)
        task_type = $TaskType
        title = $Title
        required_capabilities = @($Capabilities)
        recommended_executor = $Executor
        dependency_chain = @($Dependencies)
        output = $Output
    }
}

function Get-PDAGoalPlanningSubtasks {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GoalType,

        [Parameter(Mandatory = $true)]
        [object[]]$Deliverables,

        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $false)]
        [string]$Text = ""
    )

    $Subtasks = New-Object System.Collections.Generic.List[object]
    $TaskNumber = 1

    switch ($GoalType) {
        "environment_awareness" {
            $Subtasks.Add((New-PDAGoalSubtaskRecord -TaskNumber $TaskNumber -Title "Analyze the filesystem and operating context" -TaskType "environment_awareness" -Capabilities @("planning", "reporting") -Executor "planner-worker" -Dependencies @() -Output "environment scope and root selection"))
            $TaskNumber++
            $Subtasks.Add((New-PDAGoalSubtaskRecord -TaskNumber $TaskNumber -Title "Collect filesystem, repository, docker, service, and tool inventories" -TaskType "environment_awareness" -Capabilities @("planning", "reporting") -Executor "operator-console-worker" -Dependencies @("goal-step-01") -Output "current-state environment inventory"))
            $TaskNumber++
            $Subtasks.Add((New-PDAGoalSubtaskRecord -TaskNumber $TaskNumber -Title "Draft the file organization recommendation and migration plan" -TaskType "reporting" -Capabilities @("planning", "reporting") -Executor "reporter-worker" -Dependencies @("goal-step-02") -Output "recommended structure and phased cleanup plan"))
        }
        "research_report_pdf" {
            $Subtasks.Add((New-PDAGoalSubtaskRecord -TaskNumber $TaskNumber -Title "Research major authors and representative works" -TaskType "research" -Capabilities @("research") -Executor "gemini-cli" -Dependencies @() -Output "author shortlist and source notes"))
            $TaskNumber++
            $Subtasks.Add((New-PDAGoalSubtaskRecord -TaskNumber $TaskNumber -Title "Collect links, references, and synopses" -TaskType "research" -Capabilities @("research") -Executor "gemini-cli" -Dependencies @("goal-step-01") -Output "references and synopses"))
            $TaskNumber++
            $Subtasks.Add((New-PDAGoalSubtaskRecord -TaskNumber $TaskNumber -Title "Draft the report" -TaskType "reporting" -Capabilities @("reporting") -Executor "reporter-worker" -Dependencies @("goal-step-01", "goal-step-02") -Output "report draft"))
            $TaskNumber++
            $Subtasks.Add((New-PDAGoalSubtaskRecord -TaskNumber $TaskNumber -Title "Prepare the PDF export" -TaskType "document_generation" -Capabilities @("reporting", "document_generation") -Executor "reporter-worker" -Dependencies @("goal-step-03") -Output "PDF-ready document"))
        }
        "research_report" {
            $Subtasks.Add((New-PDAGoalSubtaskRecord -TaskNumber $TaskNumber -Title "Research the source material" -TaskType "research" -Capabilities @("research") -Executor "gemini-cli" -Dependencies @() -Output "source notes"))
            $TaskNumber++
            $Subtasks.Add((New-PDAGoalSubtaskRecord -TaskNumber $TaskNumber -Title "Draft the report" -TaskType "reporting" -Capabilities @("reporting") -Executor "reporter-worker" -Dependencies @("goal-step-01") -Output "report draft"))
        }
        "learning_plan" {
            $Subtasks.Add((New-PDAGoalSubtaskRecord -TaskNumber $TaskNumber -Title "Collect learning sources" -TaskType "knowledge_management" -Capabilities @("knowledge_management") -Executor "notebooklm" -Dependencies @() -Output "sanitized learning package"))
            $TaskNumber++
            $Subtasks.Add((New-PDAGoalSubtaskRecord -TaskNumber $TaskNumber -Title "Summarize learning outcomes" -TaskType "reporting" -Capabilities @("reporting") -Executor "reporter-worker" -Dependencies @("goal-step-01") -Output "study summary"))
        }
        "goal_decomposition" {
            $Subtasks.Add((New-PDAGoalSubtaskRecord -TaskNumber $TaskNumber -Title "Analyze the goal and break it into work items" -TaskType "planning" -Capabilities @("planning") -Executor "planner-worker" -Dependencies @() -Output "execution-ready task decomposition"))
            $TaskNumber++
            $Subtasks.Add((New-PDAGoalSubtaskRecord -TaskNumber $TaskNumber -Title "Assign deliverable-aligned executors" -TaskType "planning" -Capabilities @("planning") -Executor "planner-worker" -Dependencies @("goal-step-01") -Output "executor recommendations"))
        }
        "report" {
            $Subtasks.Add((New-PDAGoalSubtaskRecord -TaskNumber $TaskNumber -Title "Draft the report" -TaskType "reporting" -Capabilities @("reporting") -Executor "reporter-worker" -Dependencies @() -Output "report draft"))
        }
        "research" {
            $Subtasks.Add((New-PDAGoalSubtaskRecord -TaskNumber $TaskNumber -Title "Research the topic" -TaskType "research" -Capabilities @("research") -Executor "gemini-cli" -Dependencies @() -Output "research notes"))
        }
        default {
            $Subtasks.Add((New-PDAGoalSubtaskRecord -TaskNumber $TaskNumber -Title "Plan the requested goal" -TaskType "planning" -Capabilities @("planning") -Executor "planner-worker" -Dependencies @() -Output "structured plan"))
        }
    }

    return @($Subtasks.ToArray())
}

function Get-PDAGoalPlanningExecutorChain {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Subtasks
    )

    $Chain = New-Object System.Collections.Generic.List[object]
    foreach ($Subtask in @($Subtasks)) {
        $Chain.Add([pscustomobject]@{
            step = [int]($Chain.Count + 1)
            executor = [string]$Subtask.recommended_executor
            task_type = [string]$Subtask.task_type
            reason = [string]$Subtask.title
            depends_on = @($Subtask.dependency_chain)
        })
    }

    return @($Chain.ToArray())
}

function New-PDAExecutionPlanFromGoalPlan {
    param(
        [Parameter(Mandatory = $true)]
        [object]$GoalPlan
    )

    $Subtasks = @($GoalPlan.subtasks)
    $ExecutorChain = Get-PDAGoalPlanningExecutorChain -Subtasks $Subtasks

    $Dependencies = @($Subtasks | ForEach-Object {
        [pscustomobject]@{
            task_id = [string]$_.task_id
            depends_on = @($_.dependency_chain)
        }
    })

    $Deliverables = @($GoalPlan.deliverables)

    $ResponseLines = New-Object System.Collections.Generic.List[string]
    $ResponseLines.Add("Goal Assessment")
    $ResponseLines.Add(("Goal: {0}" -f [string]$GoalPlan.goal))
    $ResponseLines.Add(("Goal Type: {0}" -f [string]$GoalPlan.goal_type))
    $ResponseLines.Add(("Category: {0}" -f [string]$GoalPlan.category))
    $ResponseLines.Add(("Complexity: {0}" -f [string]$GoalPlan.complexity))
    $ResponseLines.Add(("Approval Required: {0}" -f $(if ([bool]$GoalPlan.approval_required) { "Yes" } else { "No" })))
    $ResponseLines.Add("")
    $ResponseLines.Add("Deliverables")
    foreach ($Deliverable in $Deliverables) {
        $ResponseLines.Add(("- {0}" -f [string]$Deliverable))
    }
    $ResponseLines.Add("")
    $ResponseLines.Add("Execution Plan")
    foreach ($Subtask in $Subtasks) {
        $ResponseLines.Add(("{0}. {1}" -f $Subtask.task_id, [string]$Subtask.title))
        $ResponseLines.Add(("   Executor: {0}" -f [string]$Subtask.recommended_executor))
        $ResponseLines.Add(("   Dependencies: {0}" -f $(if (@($Subtask.dependency_chain).Count -gt 0) { @($Subtask.dependency_chain) -join ", " } else { "none" })))
        $ResponseLines.Add(("   Output: {0}" -f [string]$Subtask.output))
    }
    $ResponseLines.Add("")
    $ResponseLines.Add("Executor Recommendations")
    foreach ($Step in $ExecutorChain) {
        $ResponseLines.Add(("- {0}: {1}" -f [string]$Step.task_type, [string]$Step.executor))
    }
    $ResponseLines.Add("")
    $ResponseLines.Add("Approval Path")
    $ApprovalLine = if ([bool]$GoalPlan.approval_required) { "- Human approval required before dispatch." } else { "- No approval required for planning only." }
    $ResponseLines.Add($ApprovalLine)
    $ResponseLines.Add("- No auto-dispatch, auto-approval, or queue creation will occur.")

    return [pscustomobject]@{
        status = "pass"
        plan_id = [string]$GoalPlan.plan_id
        goal = [string]$GoalPlan.goal
        goal_type = [string]$GoalPlan.goal_type
        category = [string]$GoalPlan.category
        complexity = [string]$GoalPlan.complexity
        approval_required = [bool]$GoalPlan.approval_required
        deliverables = @($Deliverables)
        subtasks = @($Subtasks)
        executor_chain = @($ExecutorChain)
        dependencies = @($Dependencies)
        recommended_executors = @($ExecutorChain | ForEach-Object { $_.executor } | Select-Object -Unique)
        response_text = ($ResponseLines -join "`r`n")
        next_action = if ([bool]$GoalPlan.approval_required) { "Review the goal plan and ask for refinements or dispatch preparation." } else { "Review the goal plan and continue." }
        source_of_truth = "Scripts/PDA_GoalPlanning.ps1"
        output_location = if ($GoalPlan.PSObject.Properties.Name -contains "store_path") { [string]$GoalPlan.store_path } else { "" }
    }
}

function Get-PDAGoalPlanningResponseText {
    param([Parameter(Mandatory = $true)][object]$GoalPlan)

    $ExecutionPlan = if ($GoalPlan.PSObject.Properties.Name -contains "execution_plan" -and $GoalPlan.execution_plan) { $GoalPlan.execution_plan } else { New-PDAExecutionPlanFromGoalPlan -GoalPlan $GoalPlan }
    return [string]$ExecutionPlan.response_text
}
