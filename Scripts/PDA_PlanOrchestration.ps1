$ErrorActionPreference = "Stop"

function ConvertTo-PDAPlanHashtable {
    param([Parameter(Mandatory = $false)]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string] -or
        $Value -is [datetime] -or
        $Value -is [guid] -or
        $Value -is [decimal] -or
        $Value.GetType().IsPrimitive -or
        $Value -is [enum]) {
        return $Value
    }

    if ($Value -is [hashtable] -or $Value -is [System.Collections.IDictionary]) {
        $Copy = @{}
        foreach ($Key in $Value.Keys) {
            $Copy[$Key] = ConvertTo-PDAPlanHashtable -Value $Value[$Key]
        }
        return $Copy
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $List = @()
        foreach ($Item in $Value) {
            $List += ,(ConvertTo-PDAPlanHashtable -Value $Item)
        }
        return $List
    }

    if ($Value -is [pscustomobject]) {
        $Copy = @{}
        foreach ($Prop in $Value.PSObject.Properties) {
            $Copy[$Prop.Name] = ConvertTo-PDAPlanHashtable -Value $Prop.Value
        }
        return $Copy
    }

    return $Value
}

function Get-PDAPlanRootPath {
    param([Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot))

    return [string]$Root
}

function Get-PDAPlanFolders {
    param([Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot))

    $PlanRoot = Join-Path $Root "PDA-Plans"
    return [pscustomobject]@{
        root = $PlanRoot
        pending = Join-Path $PlanRoot "pending"
        approved = Join-Path $PlanRoot "approved"
        running = Join-Path $PlanRoot "running"
        completed = Join-Path $PlanRoot "completed"
        failed = Join-Path $PlanRoot "failed"
    }
}

function Initialize-PDAPlanFolders {
    param([Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot))

    $Folders = Get-PDAPlanFolders -Root $Root
    foreach ($Path in @($Folders.PSObject.Properties.Value)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }

    return $Folders
}

function Get-PDAPlanFolderNameForStatus {
    param([Parameter(Mandatory = $true)][string]$Status)

    switch ([string]$Status) {
        { $_ -in @("pending", "pending_approval", "awaiting_approval", "waiting_approval") } { return "pending" }
        { $_ -in @("approved", "ready", "approved_for_orchestration") } { return "approved" }
        { $_ -in @("running", "dispatching", "orchestrating") } { return "running" }
        { $_ -in @("completed", "complete", "done") } { return "completed" }
        { $_ -in @("failed", "blocked", "error") } { return "failed" }
        default { return "pending" }
    }
}

function Get-PDAPlanFilePath {
    param(
        [Parameter(Mandatory = $true)][string]$PlanId,
        [Parameter(Mandatory = $false)][string]$Status = "pending",
        [Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Folders = Get-PDAPlanFolders -Root $Root
    $FolderName = Get-PDAPlanFolderNameForStatus -Status $Status
    return (Join-Path $Folders.$FolderName "$PlanId.json")
}

function Find-PDAPlanFile {
    param(
        [Parameter(Mandatory = $true)][string]$PlanId,
        [Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Folders = Get-PDAPlanFolders -Root $Root
    foreach ($FolderName in @("pending", "approved", "running", "completed", "failed")) {
        $Path = Join-Path $Folders.$FolderName "$PlanId.json"
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            return $Path
        }
    }

    return ""
}

function Read-PDAPlanRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Plan record not found: $Path"
    }

    $Plan = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    return (Normalize-PDAPlanRecord -Plan $Plan -Path $Path)
}

function Write-PDAPlanRecord {
    param(
        [Parameter(Mandatory = $true)][object]$Plan,
        [Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot),
        [Parameter(Mandatory = $false)][string]$Status = ""
    )

    $NormalizedPlan = $Plan
    if ([string]::IsNullOrWhiteSpace($Status)) {
        $Status = [string]$NormalizedPlan.status
    }

    $Folders = Initialize-PDAPlanFolders -Root $Root
    $FolderName = Get-PDAPlanFolderNameForStatus -Status $Status
    $TargetPath = Join-Path $Folders.$FolderName ("{0}.json" -f [string]$NormalizedPlan.plan_id)

    if ($NormalizedPlan.PSObject.Properties.Name -contains "plan_path") {
        $ExistingPath = [string]$NormalizedPlan.plan_path
        if (-not [string]::IsNullOrWhiteSpace($ExistingPath) -and $ExistingPath -ne $TargetPath -and (Test-Path -LiteralPath $ExistingPath -PathType Leaf)) {
            Remove-Item -LiteralPath $ExistingPath -Force -ErrorAction SilentlyContinue
        }
    }

    $NormalizedPlan.plan_folder = $FolderName
    $NormalizedPlan.plan_path = $TargetPath
    $NormalizedPlan.updated_at = (Get-Date).ToUniversalTime().ToString("o")
    $NormalizedPlan | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $TargetPath -Encoding UTF8
    return $TargetPath
}

function Move-PDAPlanRecord {
    param(
        [Parameter(Mandatory = $true)][object]$Plan,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Write-PDAPlanRecord -Plan $Plan -Root $Root -Status $Status)
}

function Normalize-PDAPlanStepRecord {
    param(
        [Parameter(Mandatory = $true)]$Step,
        [Parameter(Mandatory = $false)][int]$Index = 1
    )

    if ($Step -is [System.Collections.IDictionary]) {
        $Step = [pscustomobject]$Step
    }

    $StepId = ""
    foreach ($Property in @("step_id", "task_id", "id")) {
        if ($Step.PSObject.Properties.Name -contains $Property -and -not [string]::IsNullOrWhiteSpace([string]$Step.$Property)) {
            $StepId = [string]$Step.$Property
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($StepId)) {
        $StepId = ("step-{0:00}" -f $Index)
    }

    $DependsOn = @()
    foreach ($Property in @("depends_on", "dependency_chain", "dependencies")) {
        if ($Step.PSObject.Properties.Name -contains $Property -and $null -ne $Step.$Property) {
            $DependsOn = @($Step.$Property)
            break
        }
    }

    $Executor = ""
    foreach ($Property in @("executor", "recommended_executor", "assigned_worker")) {
        if ($Step.PSObject.Properties.Name -contains $Property -and -not [string]::IsNullOrWhiteSpace([string]$Step.$Property)) {
            $Executor = [string]$Step.$Property
            break
        }
    }

    $TaskType = ""
    foreach ($Property in @("task_type", "intent")) {
        if ($Step.PSObject.Properties.Name -contains $Property -and -not [string]::IsNullOrWhiteSpace([string]$Step.$Property)) {
            $TaskType = [string]$Step.$Property
            break
        }
    }

    $Title = ""
    foreach ($Property in @("title", "name", "summary")) {
        if ($Step.PSObject.Properties.Name -contains $Property -and -not [string]::IsNullOrWhiteSpace([string]$Step.$Property)) {
            $Title = [string]$Step.$Property
            break
        }
    }

    $Output = ""
    foreach ($Property in @("output", "expected_output", "deliverable")) {
        if ($Step.PSObject.Properties.Name -contains $Property -and -not [string]::IsNullOrWhiteSpace([string]$Step.$Property)) {
            $Output = [string]$Step.$Property
            break
        }
    }

    return [pscustomobject]@{
        step_id        = $StepId
        title          = $Title
        task_type      = $(if ([string]::IsNullOrWhiteSpace($TaskType)) { "planning" } else { $TaskType })
        executor       = $Executor
        depends_on     = @($DependsOn | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        output         = $Output
        status         = $(if ($Step.PSObject.Properties.Name -contains "status" -and -not [string]::IsNullOrWhiteSpace([string]$Step.status)) { [string]$Step.status } else { "pending" })
        task_id        = $(if ($Step.PSObject.Properties.Name -contains "task_id") { [string]$Step.task_id } else { "" })
        task_path      = $(if ($Step.PSObject.Properties.Name -contains "task_path") { [string]$Step.task_path } else { "" })
        result_path    = $(if ($Step.PSObject.Properties.Name -contains "result_path") { [string]$Step.result_path } else { "" })
        blocked_reason = $(if ($Step.PSObject.Properties.Name -contains "blocked_reason") { [string]$Step.blocked_reason } else { "" })
        started_at     = $(if ($Step.PSObject.Properties.Name -contains "started_at") { [string]$Step.started_at } else { "" })
        completed_at   = $(if ($Step.PSObject.Properties.Name -contains "completed_at") { [string]$Step.completed_at } else { "" })
        approval_source = $(if ($Step.PSObject.Properties.Name -contains "approval_source") { [string]$Step.approval_source } else { "" })
    }
}

function Normalize-PDAPlanRecord {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $false)][string]$Path = ""
    )

    if ($Plan -is [System.Collections.IDictionary]) {
        $Plan = [pscustomobject]$Plan
    }

    $Steps = @()
    if ($Plan.PSObject.Properties.Name -contains "steps" -and $null -ne $Plan.steps) {
        $Steps = @($Plan.steps)
    }
    elseif ($Plan.PSObject.Properties.Name -contains "subtasks" -and $null -ne $Plan.subtasks) {
        $Steps = @($Plan.subtasks)
    }

    $NormalizedSteps = New-Object System.Collections.Generic.List[object]
    $Index = 1
    foreach ($Step in $Steps) {
        $NormalizedSteps.Add((Normalize-PDAPlanStepRecord -Step $Step -Index $Index))
        $Index++
    }

    $PlanId = ""
    foreach ($Property in @("plan_id", "goal_id", "plan_instance_id")) {
        if ($Plan.PSObject.Properties.Name -contains $Property -and -not [string]::IsNullOrWhiteSpace([string]$Plan.$Property)) {
            $PlanId = [string]$Plan.$Property
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($PlanId)) {
        $PlanId = "plan-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
    }

    $Goal = ""
    foreach ($Property in @("goal", "summary", "input_text")) {
        if ($Plan.PSObject.Properties.Name -contains $Property -and -not [string]::IsNullOrWhiteSpace([string]$Plan.$Property)) {
            $Goal = [string]$Plan.$Property
            break
        }
    }

    $Status = ""
    foreach ($Property in @("status", "plan_status")) {
        if ($Plan.PSObject.Properties.Name -contains $Property -and -not [string]::IsNullOrWhiteSpace([string]$Plan.$Property)) {
            $Status = [string]$Plan.$Property
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($Status)) {
        $Status = "pending"
    }

    $PlanFolder = $(if ($Plan.PSObject.Properties.Name -contains "plan_folder" -and -not [string]::IsNullOrWhiteSpace([string]$Plan.plan_folder)) { [string]$Plan.plan_folder } else { Get-PDAPlanFolderNameForStatus -Status $Status })

    $CreatedAt = ""
    foreach ($Property in @("created_at", "created", "approved_at")) {
        if ($Plan.PSObject.Properties.Name -contains $Property -and -not [string]::IsNullOrWhiteSpace([string]$Plan.$Property)) {
            $CreatedAt = [string]$Plan.$Property
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($CreatedAt)) {
        $CreatedAt = (Get-Date).ToUniversalTime().ToString("o")
    }

    $UpdatedAt = ""
    foreach ($Property in @("updated_at", "modified_at")) {
        if ($Plan.PSObject.Properties.Name -contains $Property -and -not [string]::IsNullOrWhiteSpace([string]$Plan.$Property)) {
            $UpdatedAt = [string]$Plan.$Property
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($UpdatedAt)) {
        $UpdatedAt = $CreatedAt
    }

    $CompletedCount = @($NormalizedSteps | Where-Object { [string]$_.status -eq "completed" }).Count
    $RunningCount = @($NormalizedSteps | Where-Object { [string]$_.status -eq "running" -or [string]$_.status -eq "dispatching" }).Count
    $FailedCount = @($NormalizedSteps | Where-Object { [string]$_.status -in @("failed", "blocked") }).Count
    $TotalCount = [int]$NormalizedSteps.Count
    $OverallProgress = if ($TotalCount -gt 0) { [math]::Round(($CompletedCount / $TotalCount) * 100, 0) } else { 0 }

    $NextReadyStep = Get-PDAPlanNextReadyStep -Steps $NormalizedSteps.ToArray()
    $CurrentStep = if ($Plan.PSObject.Properties.Name -contains "current_step" -and [int]$Plan.current_step -gt 0) { [int]$Plan.current_step } elseif ($null -ne $NextReadyStep) { [int]$NextReadyStep.step_index } elseif ($Status -eq "completed") { $TotalCount + 1 } else { 1 }

    $Deliverables = @()
    foreach ($Property in @("deliverables", "planned_deliverables", "outputs")) {
        if ($Plan.PSObject.Properties.Name -contains $Property -and $null -ne $Plan.$Property) {
            $Deliverables = @($Plan.$Property)
            break
        }
    }

    $ApprovedAt = ""
    if ($Plan.PSObject.Properties.Name -contains "approved_at") {
        $ApprovedAt = [string]$Plan.approved_at
    }

    $Category = ""
    foreach ($Property in @("category", "sensitivity")) {
        if ($Plan.PSObject.Properties.Name -contains $Property -and -not [string]::IsNullOrWhiteSpace([string]$Plan.$Property)) {
            $Category = [string]$Plan.$Property
            break
        }
    }

    $RecommendedExecutors = @()
    foreach ($Step in $NormalizedSteps) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Step.executor)) {
            $RecommendedExecutors += [string]$Step.executor
        }
    }

    $BlockedStep = @($NormalizedSteps | Where-Object { [string]$_.status -eq "blocked" -or [string]$_.status -eq "failed" } | Select-Object -First 1)
    $BlockedReason = if ($BlockedStep.Count -gt 0) { [string]$BlockedStep[0].blocked_reason } else { "" }

    return [pscustomobject]@{
        plan_id                 = $PlanId
        goal                    = $Goal
        category                = $Category
        status                  = $Status
        plan_folder             = $PlanFolder
        plan_path               = $(if (-not [string]::IsNullOrWhiteSpace($Path)) { $Path } else { if ($Plan.PSObject.Properties.Name -contains "plan_path") { [string]$Plan.plan_path } else { "" } })
        created_at              = $CreatedAt
        updated_at              = $UpdatedAt
        approved_at             = $ApprovedAt
        current_step            = $CurrentStep
        overall_progress        = $OverallProgress
        step_count              = $TotalCount
        completed_step_count    = $CompletedCount
        running_step_count      = $RunningCount
        failed_step_count       = $FailedCount
        blocked_reason          = $BlockedReason
        deliverables            = @($Deliverables)
        recommended_executors   = @($RecommendedExecutors | Select-Object -Unique)
        steps                   = @($NormalizedSteps.ToArray())
        source_execution_plan   = $(if ($Plan.PSObject.Properties.Name -contains "source_execution_plan") { ConvertTo-PDAPlanHashtable -Value $Plan.source_execution_plan } else { $null })
        execution_plan_path     = $(if ($Plan.PSObject.Properties.Name -contains "execution_plan_path") { [string]$Plan.execution_plan_path } else { "" })
        final_deliverable_package_path = $(if ($Plan.PSObject.Properties.Name -contains "final_deliverable_package_path") { [string]$Plan.final_deliverable_package_path } else { "" })
        results_path            = $(if ($Plan.PSObject.Properties.Name -contains "results_path") { [string]$Plan.results_path } else { "" })
    }
}

function Get-PDAPlanDependencyCompletion {
    param(
        [Parameter(Mandatory = $false)][object[]]$Steps
    )

    $Completion = @{}
    foreach ($Step in @($Steps)) {
        $Completion[[string]$Step.step_id] = ([string]$Step.status -eq "completed")
    }

    return $Completion
}

function Test-PDAPlanDependenciesSatisfied {
    param(
        [Parameter(Mandatory = $true)]$Step,
        [Parameter(Mandatory = $true)][hashtable]$CompletionMap
    )

    foreach ($Dependency in @($Step.depends_on)) {
        $DependencyId = [string]$Dependency
        if ([string]::IsNullOrWhiteSpace($DependencyId)) {
            continue
        }

        if (-not $CompletionMap.ContainsKey($DependencyId) -or -not [bool]$CompletionMap[$DependencyId]) {
            return $false
        }
    }

    return $true
}

function Get-PDAPlanNextReadyStep {
    param(
        [Parameter(Mandatory = $false)][object[]]$Steps
    )

    if (@($Steps).Count -eq 0) {
        return $null
    }

    $CompletionMap = Get-PDAPlanDependencyCompletion -Steps $Steps
    $Index = 1
    foreach ($Step in @($Steps)) {
        if ([string]$Step.status -in @("completed", "running", "dispatching", "blocked", "failed")) {
            $Index++
            continue
        }

        if (Test-PDAPlanDependenciesSatisfied -Step $Step -CompletionMap $CompletionMap) {
            return [pscustomobject]@{
                step_index = $Index
                step = $Step
            }
        }

        $Index++
    }

    return $null
}

function Get-PDAPlanStatusCollection {
    param(
        [Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Folders = Initialize-PDAPlanFolders -Root $Root
    $Records = New-Object System.Collections.Generic.List[object]
    foreach ($FolderName in @("pending", "approved", "running", "completed", "failed")) {
        $FolderPath = $Folders.($FolderName)
        if ([string]::IsNullOrWhiteSpace([string]$FolderPath)) {
            continue
        }
        if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
            continue
        }

        foreach ($File in Get-ChildItem -LiteralPath $FolderPath -Filter *.json -File -ErrorAction SilentlyContinue) {
            try {
                $Records.Add((Read-PDAPlanRecord -Path $File.FullName))
            }
            catch {
                $Records.Add([pscustomobject]@{
                    plan_id = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
                    goal = ""
                    category = ""
                    status = "error"
                    plan_folder = $FolderName
                    plan_path = $File.FullName
                    created_at = $File.CreationTimeUtc.ToString("o")
                    updated_at = $File.LastWriteTimeUtc.ToString("o")
                    approved_at = ""
                    current_step = 0
                    overall_progress = 0
                    step_count = 0
                    completed_step_count = 0
                    running_step_count = 0
                    failed_step_count = 0
                    blocked_reason = $_.Exception.Message
                    deliverables = @()
                    recommended_executors = @()
                    steps = @()
                    source_execution_plan = $null
                    execution_plan_path = ""
                    final_deliverable_package_path = ""
                    results_path = ""
                })
            }
        }
    }

    $Sorted = @($Records | Sort-Object updated_at -Descending)
    $Pending = @($Sorted | Where-Object { [string]$_.plan_folder -eq "pending" })
    $Approved = @($Sorted | Where-Object { [string]$_.plan_folder -eq "approved" })
    $Running = @($Sorted | Where-Object { [string]$_.plan_folder -eq "running" })
    $Completed = @($Sorted | Where-Object { [string]$_.plan_folder -eq "completed" })
    $Failed = @($Sorted | Where-Object { [string]$_.plan_folder -eq "failed" -or [string]$_.status -eq "error" })

    $WaitingApproval = @($Pending | Where-Object { [string]$_.status -in @("pending", "pending_approval", "awaiting_approval", "waiting_approval") })
    $Blocked = @(
        $Sorted |
            Where-Object {
                [string]$_.status -in @("blocked", "failed", "error") -or
                -not [string]::IsNullOrWhiteSpace([string]$_.blocked_reason)
            }
    )
    $RecentDeliverables = @(
        $Completed |
            Select-Object -First 10 |
            ForEach-Object {
                [pscustomobject]@{
                    plan_id = [string]$_.plan_id
                    goal = [string]$_.goal
                    final_deliverable_package_path = [string]$_.final_deliverable_package_path
                    results_path = [string]$_.results_path
                    updated_at = [string]$_.updated_at
                }
            }
    )

    $Summaries = @(
        $Sorted |
            Select-Object -First 20 |
            ForEach-Object {
                $StepItems = @($_.steps)
                $Next = if ($StepItems.Count -gt 0) { Get-PDAPlanNextReadyStep -Steps $StepItems } else { $null }
                [pscustomobject]@{
                    plan_id = [string]$_.plan_id
                    goal = [string]$_.goal
                    status = [string]$_.status
                    plan_folder = [string]$_.plan_folder
                    category = [string]$_.category
                    current_step = [int]$_.current_step
                    overall_progress = [int]$_.overall_progress
                    next_step = if ($Next) { [string]$Next.step.title } else { "" }
                    next_step_id = if ($Next) { [string]$Next.step.step_id } else { "" }
                    blocked_reason = [string]$_.blocked_reason
                    updated_at = [string]$_.updated_at
                    final_deliverable_package_path = [string]$_.final_deliverable_package_path
                }
            }
    )

    return [pscustomobject]@{
        status = $(if (@($Sorted).Count -gt 0) { "pass" } else { "empty" })
        root_path = $Root
        plan_root = $Folders.root
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        counts = [pscustomobject]@{
            total = @($Sorted).Count
            pending = @($Pending).Count
            approved = @($Approved).Count
            running = @($Running).Count
            completed = @($Completed).Count
            failed = @($Failed).Count
            waiting_approval = @($WaitingApproval).Count
            blocked = @($Blocked).Count
        }
        plans = @($Summaries)
        pending_approvals = @($WaitingApproval | Select-Object -First 10)
        running_plans = @($Running | Select-Object -First 10)
        blocked_plans = @($Blocked | Select-Object -First 10)
        completed_plans = @($Completed | Select-Object -First 10)
        failed_plans = @($Failed | Select-Object -First 10)
        recent_deliverables = @($RecentDeliverables)
        latest_plan = if (@($Summaries).Count -gt 0) { $Summaries[0] } else { $null }
    }
}
