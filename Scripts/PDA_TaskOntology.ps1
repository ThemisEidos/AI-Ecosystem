function Get-PDATaskOntologyPath {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Join-Path $Root "Scripts\PDA_TaskOntology.json")
}

function Get-PDATaskOntologySchemaPath {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Join-Path $Root "Scripts\PDA_TaskOntology.schema.json")
}

. (Join-Path $PSScriptRoot "PDA_CategoryRouting.ps1")

function Import-PDATaskOntology {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $OntologyPath = Get-PDATaskOntologyPath -Root $Root
    if (-not (Test-Path -Path $OntologyPath -PathType Leaf)) {
        throw "PDA task ontology not found: $OntologyPath"
    }

    return Get-Content -Path $OntologyPath -Raw | ConvertFrom-Json
}

function Import-PDAWorkerRegistryForOntology {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return Get-PDAWorkerRegistry -Root $Root
}

function Find-PDATaskTypes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [string]$Command = "",

        [Parameter(Mandatory = $false)]
        [string]$Intent = "",

        [Parameter(Mandatory = $false)]
        [ValidateSet("category_1", "category_2")]
        [string]$Classification = ""
    )

    $Ontology = Import-PDATaskOntology -Root $Root
    $TaskTypes = @($Ontology.task_intents)

    if (-not [string]::IsNullOrWhiteSpace($Command)) {
        $TaskTypes = @($TaskTypes | Where-Object { [string]$_.command -eq $Command })
    }

    if (-not [string]::IsNullOrWhiteSpace($Intent)) {
        $TaskTypes = @($TaskTypes | Where-Object { [string]$_.intent -eq $Intent -or [string]$_.task_type -eq $Intent })
    }

    if (-not [string]::IsNullOrWhiteSpace($Classification)) {
        $TaskTypes = @($TaskTypes | Where-Object { @($_.supported_categories) -contains $Classification })
    }

    return $TaskTypes
}

function Get-PDATaskWorkerEligibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [object]$Task,

        [Parameter(Mandatory = $false)]
        [string]$Command = "",

        [Parameter(Mandatory = $false)]
        [ValidateSet("category_1", "category_2")]
        [string]$Classification = "",

        [Parameter(Mandatory = $false)]
        [object]$Approved = $false
    )

    $Ontology = Import-PDATaskOntology -Root $Root
    $Registry = Import-PDAWorkerRegistryForOntology -Root $Root
    $TaskTypes = @($Ontology.task_intents)

    $ApprovedValue = $false
    if ($Approved -is [bool]) {
        $ApprovedValue = [bool]$Approved
    }
    elseif ($null -ne $Approved) {
        $ApprovedText = [string]$Approved
        if ($ApprovedText -match '^(?i:true|1|yes)$') {
            $ApprovedValue = $true
        }
    }

    if ($Task) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Task.command)) {
            $Command = [string]$Task.command
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$Task.classification)) {
            $Classification = [string]$Task.classification
        }

        if ($Task.PSObject.Properties.Name -contains "approved" -and $null -ne $Task.approved) {
            $TaskApproved = [string]$Task.approved
            $ApprovedValue = $TaskApproved -match '^(?i:true|1|yes)$'
        }
    }

    if ([string]::IsNullOrWhiteSpace($Classification)) {
        $Classification = "category_1"
    }

    $MatchedTaskType = $null
    if (-not [string]::IsNullOrWhiteSpace($Command)) {
        $MatchedTaskType = @($TaskTypes | Where-Object { [string]$_.command -eq $Command } | Select-Object -First 1)[0]
    }

    if (-not $MatchedTaskType -and $Task -and $Task.PSObject.Properties.Name -contains "intent" -and -not [string]::IsNullOrWhiteSpace([string]$Task.intent)) {
        $MatchedTaskType = @($TaskTypes | Where-Object { [string]$_.intent -eq [string]$Task.intent -or [string]$_.task_type -eq [string]$Task.intent } | Select-Object -First 1)[0]
    }

    if (-not $MatchedTaskType -and -not [string]::IsNullOrWhiteSpace($Command)) {
        return [pscustomobject]@{
            command           = $Command
            classification    = $Classification
            approved          = $ApprovedValue
            status            = "unmatched"
            reason            = "No ontology task type matched the command."
            task_type         = ""
            intent            = ""
            eligible_workers  = @()
            blocked_workers   = @()
            requires_approval = $false
        }
    }

    if (-not $MatchedTaskType) {
        $MatchedTaskType = @($TaskTypes | Where-Object { @($_.supported_categories) -contains $Classification } | Select-Object -First 1)[0]
    }

    if (-not $MatchedTaskType) {
        return [pscustomobject]@{
            command           = $Command
            classification    = $Classification
            approved          = $ApprovedValue
            status            = "unmatched"
            reason            = "No ontology task type matched the request."
            task_type         = ""
            intent            = ""
            eligible_workers  = @()
            blocked_workers   = @()
            requires_approval = $false
        }
    }

    $RequiresApproval = if ($Classification -eq "category_2") {
        $MatchedTaskType.required_approvals.category_2 -eq "human_approval"
    }
    else {
        $MatchedTaskType.required_approvals.category_1 -eq "human_approval"
    }

    $WorkerNames = @($MatchedTaskType.allowed_workers)
    $EligibleWorkers = @()
    $BlockedWorkers = @()

    foreach ($WorkerName in $WorkerNames) {
        $Worker = @($Registry.workers | Where-Object { [string]$_.worker_name -eq $WorkerName } | Select-Object -First 1)[0]
        if (-not $Worker) {
            $BlockedWorkers += [pscustomobject]@{
                worker_name = $WorkerName
                reason      = "Worker missing from registry."
            }
            continue
        }

        $RoutingDecision = Resolve-PDACategoryRouting -Task ([pscustomobject]@{ classification = $Classification }) -Worker $Worker
        $CategoryAllowed = $MatchedTaskType.supported_categories -contains $Classification
        $ApprovalAllowed = (-not $RequiresApproval) -or $ApprovedValue

        if (-not $CategoryAllowed) {
            $BlockedWorkers += [pscustomobject]@{
                worker_name      = $Worker.worker_name
                command          = $Worker.command
                routing_surface  = $Worker.routing_surface
                reason           = "Category not supported by ontology."
            }
            continue
        }

        if (-not $RoutingDecision.allowed) {
            $BlockedWorkers += [pscustomobject]@{
                worker_name      = $Worker.worker_name
                command          = $Worker.command
                routing_surface  = $Worker.routing_surface
                reason           = $RoutingDecision.reason
            }
            continue
        }

        if (-not $ApprovalAllowed) {
            $BlockedWorkers += [pscustomobject]@{
                worker_name      = $Worker.worker_name
                command          = $Worker.command
                routing_surface  = $Worker.routing_surface
                reason           = "Awaiting human approval."
            }
            continue
        }

        $EligibleWorkers += [pscustomobject]@{
            worker_name     = $Worker.worker_name
            command         = $Worker.command
            routing_surface = $RoutingDecision.routing_surface
            status          = $Worker.status
            input_modes     = @($Worker.accepted_input_modes)
            output_locations = @($Worker.output_locations)
        }
    }

    $Status = if ($EligibleWorkers.Count -gt 0) { "eligible" } elseif ($RequiresApproval -and -not $ApprovedValue) { "awaiting_approval" } else { "blocked" }
    $ReasonText = if ($EligibleWorkers.Count -gt 0) { "Eligible workers found." } elseif ($RequiresApproval -and -not $ApprovedValue) { "Human approval required." } else { "No eligible workers found." }

    return [pscustomobject]@{
        command           = $MatchedTaskType.command
        classification    = $Classification
        approved          = $ApprovedValue
        status            = $Status
        reason            = $ReasonText
        task_type         = $MatchedTaskType.task_type
        intent            = $MatchedTaskType.intent
        allowed_workers   = @($MatchedTaskType.allowed_workers)
        eligible_workers  = $EligibleWorkers
        blocked_workers   = $BlockedWorkers
        requires_approval = $RequiresApproval
        input_types       = @($MatchedTaskType.input_types)
        output_types      = @($MatchedTaskType.output_types)
    }
}

function Resolve-PDATaskDispatchContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [object]$Task,

        [Parameter(Mandatory = $false)]
        [string]$Command = "",

        [Parameter(Mandatory = $false)]
        [ValidateSet("category_1", "category_2")]
        [string]$Classification = "",

        [Parameter(Mandatory = $false)]
        [object]$Approved = $true
    )

    $null = Test-PDATaskOntologyContract -Root $Root

    $DecisionArgs = @{
        Root     = $Root
        Approved = $Approved
    }

    if ($null -ne $Task) {
        $DecisionArgs.Task = $Task
    }

    if (-not [string]::IsNullOrWhiteSpace($Command)) {
        $DecisionArgs.Command = $Command
    }

    if (-not [string]::IsNullOrWhiteSpace($Classification)) {
        $DecisionArgs.Classification = $Classification
    }

    $Decision = Get-PDATaskWorkerEligibility @DecisionArgs
    $EligibleWorkers = @($Decision.eligible_workers)

    if ($Decision.status -eq "unmatched" -or $EligibleWorkers.Count -eq 0) {
        $TaskLabel = if ($Command) { $Command } elseif ($Decision.command) { $Decision.command } else { "unknown command" }
        $CategoryLabel = if ($Decision.classification) { $Decision.classification } elseif ($Classification) { $Classification } else { "unknown classification" }
        throw "Ontology did not produce an eligible worker for $TaskLabel in ${CategoryLabel}: $($Decision.reason)"
    }

    $EligibleWorker = $EligibleWorkers | Select-Object -First 1

    return [pscustomobject]@{
        command           = $Decision.command
        classification    = $Decision.classification
        approved          = $Decision.approved
        task_type         = $Decision.task_type
        intent            = $Decision.intent
        status            = $Decision.status
        reason            = $Decision.reason
        requires_approval = $Decision.requires_approval
        eligible_worker   = $EligibleWorker
        assigned_worker   = [string]$EligibleWorker.worker_name
        routing_surface   = [string]$EligibleWorker.routing_surface
        input_types       = @($Decision.input_types)
        output_types      = @($Decision.output_types)
        allowed_workers   = @($Decision.allowed_workers)
        blocked_workers   = @($Decision.blocked_workers)
    }
}

function Test-PDATaskOntologyContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $OntologyPath = Get-PDATaskOntologyPath -Root $Root
    $SchemaPath = Get-PDATaskOntologySchemaPath -Root $Root
    $Ontology = Import-PDATaskOntology -Root $Root
    $Registry = Import-PDAWorkerRegistryForOntology -Root $Root
    $Issues = New-Object System.Collections.Generic.List[string]

    foreach ($Path in @($OntologyPath, $SchemaPath)) {
        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            $Issues.Add("Missing file: $Path")
        }
    }

    foreach ($Required in @("schema_version", "ontology_name", "ontology_version", "generated_at", "task_categories", "task_intents", "registry_integration")) {
        if (-not ($Ontology.PSObject.Properties.Name -contains $Required)) {
            $Issues.Add("Ontology missing property: $Required")
        }
    }

    $WorkersByName = @{}
    foreach ($Worker in @($Registry.workers)) {
        if ($Worker.PSObject.Properties.Name -contains "worker_name" -and -not [string]::IsNullOrWhiteSpace([string]$Worker.worker_name)) {
            $WorkersByName[[string]$Worker.worker_name] = $Worker
        }
    }

    foreach ($Intent in @($Ontology.task_intents)) {
        if (-not $Intent.command) {
            $Issues.Add("Intent missing command: $($Intent.intent)")
            continue
        }

        if (-not $Intent.allowed_workers -or @($Intent.allowed_workers).Count -eq 0) {
            $Issues.Add("Intent has no allowed workers: $($Intent.intent)")
            continue
        }

        foreach ($WorkerName in @($Intent.allowed_workers)) {
            if (-not $WorkersByName.ContainsKey([string]$WorkerName)) {
                $Issues.Add("Intent references missing worker: $($Intent.intent) -> $WorkerName")
                continue
            }

            $Worker = $WorkersByName[[string]$WorkerName]
            $RoutingSurface = if ($Worker.PSObject.Properties.Name -contains "routing_surface") { [string]$Worker.routing_surface } else { "" }
            $CloudCapable = if ($Worker.PSObject.Properties.Name -contains "cloud_capable") { [bool]$Worker.cloud_capable } else { $false }

            if (($Intent.supported_categories -contains "category_2") -and ($RoutingSurface -ne "local-only" -or $CloudCapable)) {
                $Issues.Add("Category 2 intent references non-local worker: $($Intent.intent) -> $WorkerName")
            }
        }

        $Category2Approval = [string]$Intent.required_approvals.category_2
        if (($Intent.supported_categories -contains "category_2") -and $Category2Approval -ne "human_approval" -and $Category2Approval -ne "blocked") {
            $Issues.Add("Category 2 approval profile must be human_approval or blocked: $($Intent.intent)")
        }
    }

    $Category2Workers = @(Get-PDATaskWorkerEligibility -Root $Root -Command "/review" -Classification "category_2" -Approved $true).eligible_workers
    foreach ($Worker in $Category2Workers) {
        if ($Worker.routing_surface -ne "local-only") {
            $Issues.Add("Category 2 resolver returned non-local worker: $($Worker.worker_name)")
        }
    }

    $FabricCategory2 = Get-PDATaskWorkerEligibility -Root $Root -Command "/fabric" -Classification "category_2" -Approved $true
    if (@($FabricCategory2.eligible_workers).Count -gt 0) {
        $Issues.Add("Fabric should not be eligible for category_2 routing in this phase.")
    }

    $Result = [pscustomobject]@{
        valid              = ($Issues.Count -eq 0)
        issue_count        = $Issues.Count
        issues             = @($Issues)
        ontology_path      = $OntologyPath
        schema_path        = $SchemaPath
        intent_count       = @($Ontology.task_intents).Count
        category_count     = @($Ontology.task_categories).Count
        registry_workers   = @($Registry.workers).Count
    }

    if (-not $Result.valid) {
        $IssueLines = $Issues -join [Environment]::NewLine
        throw "PDA task ontology validation failed.`n$IssueLines"
    }

    return $Result
}
