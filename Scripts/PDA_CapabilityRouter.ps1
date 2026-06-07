$ErrorActionPreference = "Stop"

function Get-PDACapabilityMatrixPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    return (Join-Path $Root "Scripts\PDA_CapabilityMatrix.json")
}

function Normalize-PDACapabilityTaskType {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value
    )

    $TaskTypeValue = [string]$Value
    if ([string]::IsNullOrWhiteSpace($TaskTypeValue)) {
        return ""
    }

    $Normalized = $TaskTypeValue.ToLowerInvariant().Trim()
    switch -Regex ($Normalized) {
        '^research(_synthesis)?$' { return "research" }
        '^report(_generation|ing)?$' { return "reporting" }
        '^reporter$' { return "reporting" }
        '^planning$' { return "planning" }
        '^review(_pattern)?$' { return "review" }
        '^security(_triage|_pattern)?$' { return "security_triage" }
        '^notebooklm(_package)?$' { return "notebooklm_package" }
        '^summarize(tion|_pattern)?$' { return "summarization" }
        '^execute(_manifest)?$' { return "coding" }
        '^fabric_research_pattern$' { return "research" }
        '^fabric_report_pattern$' { return "reporting" }
        '^fabric_review_pattern$' { return "review" }
        '^fabric_security_pattern$' { return "security_triage" }
        '^learning$' { return "learning" }
        '^automation$' { return "automation" }
        '^coding$' { return "coding" }
        '^local_only_restricted$' { return "local_only_restricted" }
        default { return $Normalized }
    }
}

function Resolve-PDACapabilityOutputLocation {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Paths
    )

    return @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Get-PDACapabilityMatrix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $MatrixPath = Get-PDACapabilityMatrixPath -Root $Root
    if (-not (Test-Path -LiteralPath $MatrixPath -PathType Leaf)) {
        return [pscustomobject]@{
            status        = "missing"
            matrix_path   = $MatrixPath
            schema_version = ""
            updated_at    = ""
            route_count   = 0
            local_only_count = 0
            cloud_allowed_count = 0
            matrix        = @()
            routes        = @()
        }
    }

    try {
        $Raw = Get-Content -LiteralPath $MatrixPath -Raw -ErrorAction Stop
        $Parsed = $Raw | ConvertFrom-Json -ErrorAction Stop
        $Rows = @($Parsed.matrix)
        $Routes = @(
            $Rows | ForEach-Object {
                [pscustomobject]@{
                    task_type = [string]$_.task_type
                    sensitivity_category = [string]$_.sensitivity_category
                    preferred_tool = [string]$_.preferred_tool
                    backup_tool = [string]$_.backup_tool
                    output_location = @($_.output_location)
                    automation_readiness = [string]$_.automation_readiness
                    cloud_allowed = [bool]$_.cloud_allowed
                    route_alias = [string]$_.route_alias
                    notes = [string]$_.notes
                }
            }
        )

        return [pscustomobject]@{
            status        = "pass"
            matrix_path   = $MatrixPath
            schema_version = [string]$Parsed.schema_version
            updated_at    = [string]$Parsed.updated_at
            route_count   = @($Rows).Count
            local_only_count = @($Rows | Where-Object { -not [bool]$_.cloud_allowed }).Count
            cloud_allowed_count = @($Rows | Where-Object { [bool]$_.cloud_allowed }).Count
            matrix        = @($Rows)
            routes        = $Routes
        }
    }
    catch {
        return [pscustomobject]@{
            status        = "error"
            matrix_path   = $MatrixPath
            schema_version = ""
            updated_at    = ""
            route_count   = 0
            local_only_count = 0
            cloud_allowed_count = 0
            matrix        = @()
            routes        = @()
            error         = $_.Exception.Message
        }
    }
}

function Test-PDAToolAllowedForCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("category_1", "category_2", "restricted_local")]
        [string]$SensitivityCategory,

        [Parameter(Mandatory = $false)]
        [string]$TaskType = "",

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Matrix = Get-PDACapabilityMatrix -Root $Root
    if ($Matrix.status -ne "pass") {
        return [pscustomobject]@{
            allowed          = $false
            cloud_allowed    = $false
            category         = $SensitivityCategory
            task_type        = Normalize-PDACapabilityTaskType -Value $TaskType
            tool_name        = $ToolName
            reason           = "Capability matrix is unavailable."
            matrix_status    = $Matrix.status
            matrix_path      = $Matrix.matrix_path
        }
    }

    $Matched = @($Matrix.routes | Where-Object {
        [string]$_.preferred_tool -eq $ToolName -or [string]$_.backup_tool -eq $ToolName
    } | Select-Object -First 1)[0]

    if (-not $Matched) {
        $ImplicitLocalTool = $ToolName -match '(?i)(fabric|ollama|powershell|python|local)'
        $Allowed = $ImplicitLocalTool -or ($SensitivityCategory -eq "category_1")
        if ($SensitivityCategory -eq "restricted_local") {
            $Allowed = $ImplicitLocalTool
        }

        return [pscustomobject]@{
            allowed          = [bool]$Allowed
            cloud_allowed    = -not $ImplicitLocalTool
            category         = $SensitivityCategory
            task_type        = Normalize-PDACapabilityTaskType -Value $TaskType
            tool_name        = $ToolName
            reason           = if ($Allowed) { "Tool allowed by heuristic fallback." } else { "Tool is not allowed for this category." }
            matrix_status    = $Matrix.status
            matrix_path      = $Matrix.matrix_path
        }
    }

    $Allowed = $true
    $Reason = "Tool is allowed for this category."
    if ($SensitivityCategory -in @("category_2", "restricted_local") -and [bool]$Matched.cloud_allowed) {
        $Allowed = $false
        $Reason = "Cloud-backed tool is not allowed for restricted categories."
    }

    return [pscustomobject]@{
        allowed          = [bool]$Allowed
        cloud_allowed    = [bool]$Matched.cloud_allowed
        category         = $SensitivityCategory
        task_type        = Normalize-PDACapabilityTaskType -Value $TaskType
        tool_name        = $ToolName
        reason           = $Reason
        matrix_status    = $Matrix.status
        matrix_path      = $Matrix.matrix_path
    }
}

function Get-PDAToolForTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskType,

        [Parameter(Mandatory = $true)]
        [ValidateSet("category_1", "category_2", "restricted_local")]
        [string]$Category,

        [Parameter(Mandatory = $false)]
        [string]$PreferredOutput = "",

        [Parameter(Mandatory = $false)]
        [switch]$RequiresLocalOnly,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Matrix = Get-PDACapabilityMatrix -Root $Root
    $NormalizedTaskType = Normalize-PDACapabilityTaskType -Value $TaskType
    $NormalizedOutput = [string]$PreferredOutput
    $NormalizedOutputLower = $NormalizedOutput.ToLowerInvariant().Trim()
    $NeedsLocalOnly = [bool]$RequiresLocalOnly -or $Category -in @("category_2", "restricted_local")

    if ($Matrix.status -ne "pass") {
        return [pscustomobject]@{
            selected_tool    = ""
            backup_tool      = ""
            routing_reason   = "Capability matrix is unavailable."
            allowed          = $false
            blocked_reason   = "Capability matrix is unavailable."
            output_location  = @()
            task_type        = $NormalizedTaskType
            category         = $Category
            preferred_output = $NormalizedOutput
            requires_local_only = $NeedsLocalOnly
            cloud_allowed    = $false
            matrix_status    = $Matrix.status
            matrix_path      = $Matrix.matrix_path
            route_count      = 0
            matrix_loaded    = $false
        }
    }

    $MatchedRow = $null
    switch ($NormalizedTaskType) {
        "notebooklm_package" {
            $MatchedRow = [pscustomobject]@{
                task_type = "notebooklm_package"
                sensitivity_category = "category_1"
                preferred_tool = "NotebookLM package generation"
                backup_tool = "Obsidian notes + Fabric summary"
                output_location = @(
                    "04_Resources/Learning/"
                    "08_Prompts/"
                    "05_Reports/Learning/"
                )
                automation_readiness = "assisted"
                cloud_allowed = $true
                route_alias = "/notebooklm"
                notes = "NotebookLM only receives sanitized Category 1 material."
            }
            if ($Category -in @("category_2", "restricted_local")) {
                return [pscustomobject]@{
                    selected_tool    = ""
                    backup_tool      = [string]$MatchedRow.backup_tool
                    routing_reason   = "NotebookLM package generation is Category 1 only."
                    allowed          = $false
                    blocked_reason   = "NotebookLM packages are blocked for Category 2 and restricted-local work."
                    output_location  = @($MatchedRow.output_location)
                    task_type        = $NormalizedTaskType
                    category         = $Category
                    preferred_output = $NormalizedOutput
                    requires_local_only = $NeedsLocalOnly
                    cloud_allowed    = $false
                    matrix_status    = $Matrix.status
                    matrix_path      = $Matrix.matrix_path
                    route_count      = [int]$Matrix.route_count
                    matrix_loaded    = $true
                }
            }
        }
        default {
            $TaskRows = @($Matrix.routes | Where-Object { [string]$_.task_type -eq $NormalizedTaskType })
            if ($TaskRows.Count -eq 0) {
                $TaskRows = @($Matrix.routes | Where-Object {
                    [string]$_.route_alias -and [string]$_.route_alias -eq "/$NormalizedTaskType"
                })
            }

            if ($TaskRows.Count -gt 0) {
                $MatchedRow = @($TaskRows | Where-Object { [string]$_.sensitivity_category -eq $Category } | Select-Object -First 1)[0]
                if (-not $MatchedRow) {
                    $MatchedRow = @($TaskRows | Select-Object -First 1)[0]
                }
            }
        }
    }

    if (-not $MatchedRow) {
        $FallbackTool = if ($NeedsLocalOnly) { "PowerShell or Python local-only" } else { "" }
        return [pscustomobject]@{
            selected_tool    = $FallbackTool
            backup_tool      = ""
            routing_reason   = "No capability matrix row matched the request."
            allowed          = [bool](-not [string]::IsNullOrWhiteSpace($FallbackTool))
            blocked_reason   = if ([string]::IsNullOrWhiteSpace($FallbackTool)) { "No route could be selected." } else { "" }
            output_location  = @()
            task_type        = $NormalizedTaskType
            category         = $Category
            preferred_output = $NormalizedOutput
            requires_local_only = $NeedsLocalOnly
            cloud_allowed    = $false
            matrix_status    = $Matrix.status
            matrix_path      = $Matrix.matrix_path
            route_count      = [int]$Matrix.route_count
            matrix_loaded    = $true
        }
    }

    $SelectedTool = [string]$MatchedRow.preferred_tool
    $BackupTool = [string]$MatchedRow.backup_tool
    $Allowed = $true
    $BlockedReason = ""
    $RoutingReason = [string]$MatchedRow.notes

    if ($NeedsLocalOnly -and [bool]$MatchedRow.cloud_allowed) {
        $LocalFallback = switch ($NormalizedTaskType) {
            "research" { "Fabric research-synthesis local" }
            "reporting" { "Fabric report-summary local" }
            "review" { "Fabric review-checklist local" }
            "summarization" { "Fabric report-summary local" }
            "learning" { "Obsidian local synthesis + Fabric summary" }
            "coding" { "PowerShell or Python local-only" }
            "automation" { "n8n + PowerShell + Python local-only" }
            "security_triage" { "Fabric security-triage" }
            default { "" }
        }

        if ([string]::IsNullOrWhiteSpace($LocalFallback)) {
            $Allowed = $false
            $BlockedReason = "No local-only fallback is available for this route."
        }
        else {
            $SelectedTool = $LocalFallback
            $RoutingReason = "Local-only routing requested. Falling back from '$([string]$MatchedRow.preferred_tool)' to '$SelectedTool'."
        }
    }

    if ($Allowed -and $Category -in @("category_2", "restricted_local") -and [bool]$MatchedRow.cloud_allowed) {
        $Allowed = $false
        $BlockedReason = "Cloud-backed tool is not allowed for restricted categories."
    }

    if ($Allowed -and $PreferredOutput) {
        if ($NormalizedTaskType -eq "learning" -and $NormalizedOutputLower -match 'package') {
            $SelectedTool = "NotebookLM package generation"
            $RoutingReason = "Preferred output indicates NotebookLM package generation."
        }
    }

    if ($Allowed -and [string]::IsNullOrWhiteSpace($SelectedTool)) {
        $Allowed = $false
        $BlockedReason = "Selected tool could not be resolved."
    }

    return [pscustomobject]@{
        selected_tool    = $SelectedTool
        backup_tool      = $BackupTool
        routing_reason   = $RoutingReason
        allowed          = [bool]$Allowed
        blocked_reason   = $BlockedReason
        output_location  = Resolve-PDACapabilityOutputLocation -Paths @($MatchedRow.output_location)
        task_type        = $NormalizedTaskType
        category         = $Category
        preferred_output = $NormalizedOutput
        requires_local_only = $NeedsLocalOnly
        cloud_allowed    = [bool]$MatchedRow.cloud_allowed
        matrix_status    = $Matrix.status
        matrix_path      = $Matrix.matrix_path
        route_count      = [int]$Matrix.route_count
        matrix_loaded    = $true
    }
}
