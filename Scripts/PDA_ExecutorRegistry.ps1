[CmdletBinding()]
param()

$script:PDAExecutorRegistryCache = $null

function Get-PDAExecutorRegistryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Join-Path $Root "Scripts\PDA_ExecutorRegistry.json")
}

function Normalize-PDAExecutorTaskType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $Normalized = [string]$Value
    $Normalized = $Normalized.ToLowerInvariant()
    $Normalized = $Normalized -replace '[^a-z0-9_]+', '_'
    $Normalized = $Normalized -replace '_+', '_'
    $Normalized = $Normalized.Trim('_')

    switch ($Normalized) {
        "report_generation" { return "reporting" }
        "research_synthesis" { return "research" }
        "fabric_research_pattern" { return "research" }
        "fabric_report_pattern" { return "reporting" }
        "fabric_review_pattern" { return "review" }
        "fabric_security_pattern" { return "security_triage" }
        "execution_manifest" { return "execute" }
        "operator_status" { return "administrative" }
        "operator_tasks" { return "administrative" }
        "operator_approvals" { return "administrative" }
        "operator_workers" { return "administrative" }
        "operator_reports" { return "administrative" }
        "operator_memory" { return "knowledge_management" }
        "operator_help" { return "operator_guidance" }
        "notebooklm_package" { return "knowledge_management" }
        "dispatch_guidance" { return "administrative" }
        "operator_dispatch" { return "administrative" }
        default { return $Normalized }
    }
}

function Get-PDAExecutorRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    if ($script:PDAExecutorRegistryCache) {
        return $script:PDAExecutorRegistryCache
    }

    $RegistryPath = Get-PDAExecutorRegistryPath -Root $Root
    if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) {
        throw "Executor registry missing: $RegistryPath"
    }

    $Registry = Get-Content -Path $RegistryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $Executors = @($Registry.executors)
    $Registry | Add-Member -NotePropertyName status -NotePropertyValue "pass" -Force
    $Registry | Add-Member -NotePropertyName registry_path -NotePropertyValue $RegistryPath -Force
    $Registry | Add-Member -NotePropertyName executor_count -NotePropertyValue @($Executors).Count -Force
    $Registry | Add-Member -NotePropertyName local_only_count -NotePropertyValue @($Executors | Where-Object { $_.supports_local_only }).Count -Force
    $Registry | Add-Member -NotePropertyName category2_capable_count -NotePropertyValue @($Executors | Where-Object { $_.supports_category2 }).Count -Force
    $Registry | Add-Member -NotePropertyName requires_approval_count -NotePropertyValue @($Executors | Where-Object { $_.requires_approval }).Count -Force
    $Registry | Add-Member -NotePropertyName cloud_capable_count -NotePropertyValue @($Executors | Where-Object { -not $_.supports_local_only }).Count -Force
    $script:PDAExecutorRegistryCache = $Registry
    return $Registry
}

function Get-PDAExecutorDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutorName,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Registry = Get-PDAExecutorRegistry -Root $Root
    $NormalizedName = [string]$ExecutorName.Trim().ToLowerInvariant()
    return @($Registry.executors | Where-Object { [string]$_.executor_name.Trim().ToLowerInvariant() -eq $NormalizedName } | Select-Object -First 1)[0]
}

function Test-PDAExecutorAllowedForCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutorName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("category_1", "category_2", "restricted_local")]
        [string]$Category,

        [Parameter(Mandatory = $false)]
        [switch]$RequiresLocalOnly,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Executor = Get-PDAExecutorDefinition -ExecutorName $ExecutorName -Root $Root
    if (-not $Executor) {
        return [pscustomobject]@{
            status              = "blocked"
            allowed             = $false
            blocked_reason      = "Executor '$ExecutorName' is not registered."
            executor_name       = [string]$ExecutorName
            display_name        = [string]$ExecutorName
            executor_type       = ""
            risk_level          = "unknown"
            requires_approval   = $false
            supports_category2  = $false
            supports_local_only = $false
            dispatch_method     = ""
            output_locations    = @()
            registry_path       = Get-PDAExecutorRegistryPath -Root $Root
        }
    }

    $Allowed = $true
    $BlockedReason = ""
    if ($RequiresLocalOnly -and -not [bool]$Executor.supports_local_only) {
        $Allowed = $false
        $BlockedReason = "Executor '$($Executor.executor_name)' is not local-only."
    }
    elseif ($Category -eq "category_2" -and -not [bool]$Executor.supports_category2) {
        $Allowed = $false
        $BlockedReason = "Executor '$($Executor.executor_name)' is not approved for Category 2."
    }

    $DisplayName = [string]$Executor.executor_name
    if ($Executor.PSObject.Properties.Name -contains "display_name") {
        $CandidateDisplayName = [string]$Executor.display_name
        if (-not [string]::IsNullOrWhiteSpace($CandidateDisplayName)) {
            $DisplayName = $CandidateDisplayName
        }
    }

    $SupportsFileModification = $false
    if ($Executor.PSObject.Properties.Name -contains "supports_file_modification") {
        $SupportsFileModification = [bool]$Executor.supports_file_modification
    }

    $SupportsRepositoryChanges = $false
    if ($Executor.PSObject.Properties.Name -contains "supports_repository_changes") {
        $SupportsRepositoryChanges = [bool]$Executor.supports_repository_changes
    }

    $SupportsResearch = $false
    if ($Executor.PSObject.Properties.Name -contains "supports_research") {
        $SupportsResearch = [bool]$Executor.supports_research
    }

    $SupportsReporting = $false
    if ($Executor.PSObject.Properties.Name -contains "supports_reporting") {
        $SupportsReporting = [bool]$Executor.supports_reporting
    }

    $SupportsAutomation = $false
    if ($Executor.PSObject.Properties.Name -contains "supports_automation") {
        $SupportsAutomation = [bool]$Executor.supports_automation
    }

    $DispatchMethod = ""
    if ($Executor.PSObject.Properties.Name -contains "dispatch_method") {
        $DispatchMethod = [string]$Executor.dispatch_method
    }

    $OutputLocations = @()
    if ($Executor.PSObject.Properties.Name -contains "output_locations") {
        $OutputLocations = @($Executor.output_locations)
    }

    return [pscustomobject]@{
        status                   = $(if ($Allowed) { "pass" } else { "blocked" })
        allowed                  = $Allowed
        blocked_reason           = $BlockedReason
        executor_name            = [string]$Executor.executor_name
        display_name             = $DisplayName
        executor_type            = [string]$Executor.executor_type
        risk_level               = [string]$Executor.risk_level
        requires_approval        = [bool]$Executor.requires_approval
        supports_category2       = [bool]$Executor.supports_category2
        supports_local_only      = [bool]$Executor.supports_local_only
        supports_file_modification = $SupportsFileModification
        supports_repository_changes = $SupportsRepositoryChanges
        supports_research        = $SupportsResearch
        supports_reporting       = $SupportsReporting
        supports_automation      = $SupportsAutomation
        dispatch_method          = $DispatchMethod
        output_locations         = $OutputLocations
        registry_path            = Get-PDAExecutorRegistryPath -Root $Root
        executor                 = $Executor
    }
}

function Get-PDAExecutorRecommendation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskType,

        [Parameter(Mandatory = $false)]
        [ValidateSet("category_1", "category_2", "restricted_local")]
        [string]$Category = "category_1",

        [Parameter(Mandatory = $false)]
        [string]$PreferredOutput = "",

        [Parameter(Mandatory = $false)]
        [switch]$RequiresLocalOnly,

        [Parameter(Mandatory = $false)]
        [string]$Text = "",

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $NormalizedTaskType = Normalize-PDAExecutorTaskType -Value $TaskType
    if (Get-Command -Name Normalize-PDACapabilityTaskType -ErrorAction SilentlyContinue) {
        try {
            $CapabilityType = Normalize-PDACapabilityTaskType -Value $TaskType
            if (-not [string]::IsNullOrWhiteSpace([string]$CapabilityType)) {
                $NormalizedTaskType = [string]$CapabilityType
            }
        }
        catch {}
    }

    $CandidateExecutors = switch ($NormalizedTaskType) {
        "research" { @("gemini-cli", "research-worker", "reporter-worker") }
        "reporting" { @("reporter-worker", "planner-worker") }
        "review" { @("review-worker", "reporter-worker") }
        "coding" { @("codex", "execute-worker") }
        "execute" { @("execute-worker", "codex") }
        "automation" { @("n8n", "execute-worker") }
        "knowledge_management" {
            if ($Category -eq "category_2" -or $RequiresLocalOnly) {
                @("notebooklm")
            }
            else {
                @("notebooklm", "operator-console-worker")
            }
        }
        "planning" { @("planner-worker", "operator-console-worker") }
        "security_triage" { @("review-worker", "reporter-worker") }
        "administrative" { @("operator-console-worker") }
        "operator_guidance" { @("operator-console-worker") }
        default { @("operator-console-worker") }
    }

    $Selected = $null
    $Backup = $null
    $SelectedCheck = $null
    $BlockedReason = ""

    foreach ($Candidate in $CandidateExecutors) {
        $Check = Test-PDAExecutorAllowedForCategory -ExecutorName $Candidate -Category $Category -RequiresLocalOnly:$RequiresLocalOnly -Root $Root
        if ($Check.allowed -and -not $Selected) {
            $Selected = $Check
            $SelectedCheck = $Check
            continue
        }

        if ($Check.allowed -and -not $Backup) {
            $Backup = $Check
        }

        if (-not $Check.allowed -and [string]::IsNullOrWhiteSpace($BlockedReason)) {
            $BlockedReason = [string]$Check.blocked_reason
        }
    }

    if (-not $Selected) {
        $SelectedCheck = Test-PDAExecutorAllowedForCategory -ExecutorName $CandidateExecutors[0] -Category $Category -RequiresLocalOnly:$RequiresLocalOnly -Root $Root
        $Selected = $SelectedCheck
        if ([string]::IsNullOrWhiteSpace($BlockedReason)) {
            $BlockedReason = [string]$SelectedCheck.blocked_reason
        }
    }

    if (-not $Backup) {
        $Backup = if ($CandidateExecutors.Count -gt 1) {
            Test-PDAExecutorAllowedForCategory -ExecutorName $CandidateExecutors[1] -Category $Category -RequiresLocalOnly:$RequiresLocalOnly -Root $Root
        }
        else {
            $Selected
        }
    }

    $Allowed = [bool]$Selected.allowed
    if (-not $Allowed -and [string]::IsNullOrWhiteSpace($BlockedReason)) {
        $BlockedReason = if ($Selected.blocked_reason) { [string]$Selected.blocked_reason } else { "No executor could be recommended." }
    }

    $ApprovalRequired = if ($Selected -and $Selected.PSObject.Properties.Name -contains "requires_approval") { [bool]$Selected.requires_approval } else { $true }
    if ($Category -eq "category_2") {
        $ApprovalRequired = $true
    }

    $Reason = switch ($NormalizedTaskType) {
        "research" { if ($Selected.executor_name -eq "gemini-cli") { "Category 1 research is best handled by Gemini CLI with a local research-worker backup." } else { "Research is restricted to a local-only executor for this category." } }
        "reporting" { "Reporting is handled by the local reporter-worker pipeline." }
        "review" { "Review tasks are best handled by the local review-worker pipeline." }
        "coding" { "Repository changes should use the local Codex execution path." }
        "execute" { "Execution tasks should use the local execute-worker or Codex path under approval." }
        "automation" { "Deterministic automation should use n8n." }
        "knowledge_management" { "Sanitized learning packages belong in NotebookLM before memory promotion." }
        "planning" { "Planning work should stay with the local planner-worker." }
        "security_triage" { "Security triage should stay in the local review pipeline." }
        "administrative" { "Operator console guidance remains local and read-only." }
        default { "No stronger executor match was found." }
    }

    $SelectedOutput = if ($Selected -and $Selected.output_locations) { @($Selected.output_locations) } else { @() }
    if ($SelectedOutput.Count -eq 0 -and $Selected.executor -and $Selected.executor.PSObject.Properties.Name -contains "output_locations") {
        $SelectedOutput = @($Selected.executor.output_locations)
    }

    return [pscustomobject]@{
        status               = $(if ($Allowed) { "pass" } else { "blocked" })
        task_type            = $NormalizedTaskType
        category             = $Category
        preferred_output     = $PreferredOutput
        requires_local_only  = [bool]$RequiresLocalOnly
        recommended_executor = $(if ($Selected) { [string]$Selected.executor_name } else { "" })
        selected_tool        = $(if ($Selected) { [string]$Selected.executor_name } else { "" })
        selected_display     = $(if ($Selected) { [string]$Selected.display_name } else { "" })
        backup_executor      = $(if ($Backup) { [string]$Backup.executor_name } else { "" })
        backup_tool          = $(if ($Backup) { [string]$Backup.executor_name } else { "" })
        backup_display       = $(if ($Backup) { [string]$Backup.display_name } else { "" })
        executor_type        = $(if ($Selected) { [string]$Selected.executor_type } else { "" })
        risk_level           = $(if ($Selected) { [string]$Selected.risk_level } else { "unknown" })
        approval_required    = [bool]$ApprovalRequired
        allowed              = [bool]$Allowed
        blocked_reason       = [string]$BlockedReason
        routing_reason       = [string]$Reason
        confidence           = $(if ($Allowed) { if ($ApprovalRequired) { 0.9 } else { 0.95 } } else { 0.35 })
        dispatch_ready       = $false
        dispatch_status      = $(if ($Allowed) { if ($ApprovalRequired) { "approval_required" } else { "ready_for_preparation" } } else { "blocked" })
        output_location      = @($SelectedOutput)
        executor_registry    = Get-PDAExecutorRegistry -Root $Root
        executor_record      = $(if ($Selected) { $Selected.executor } else { $null })
        backup_record        = $(if ($Backup) { $Backup.executor } else { $null })
        registry_path        = Get-PDAExecutorRegistryPath -Root $Root
        source_of_truth      = "Scripts/PDA_ExecutorRegistry.json"
    }
}

function Get-PDAExecutorRegistrySummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Registry = Get-PDAExecutorRegistry -Root $Root
    return [pscustomobject]@{
        status               = [string]$Registry.status
        registry_path        = [string]$Registry.registry_path
        executor_count       = [int]$Registry.executor_count
        local_only_count     = [int]$Registry.local_only_count
        category2_capable_count = [int]$Registry.category2_capable_count
        cloud_capable_count  = [int]$Registry.cloud_capable_count
        requires_approval_count = [int]$Registry.requires_approval_count
        executors            = @($Registry.executors | Select-Object executor_name, display_name, executor_type, risk_level, requires_approval, supports_category2, supports_local_only, dispatch_method)
    }
}
