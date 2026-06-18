function ConvertTo-PDAApprovalHashtable {
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
            $Copy[$Key] = ConvertTo-PDAApprovalHashtable -Value $Value[$Key]
        }
        return $Copy
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $List = @()
        foreach ($Item in $Value) {
            $List += ,(ConvertTo-PDAApprovalHashtable -Value $Item)
        }
        return $List
    }

    if ($Value -is [psobject] -and $Value.PSObject.Properties.Name.Count -gt 0) {
        $Copy = @{}
        foreach ($Prop in $Value.PSObject.Properties) {
            $Copy[$Prop.Name] = ConvertTo-PDAApprovalHashtable -Value $Prop.Value
        }
        return $Copy
    }

    return $Value
}

function Get-PDAApprovalWorkflowRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Join-Path $Root "PDA-Runtime\data\approval-workflows")
}

function Get-PDAApprovalWorkflowFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $WorkflowRoot = Get-PDAApprovalWorkflowRoot -Root $Root
    return [ordered]@{
        pending_approval     = Join-Path $WorkflowRoot "pending_approval"
        approved              = Join-Path $WorkflowRoot "approved"
        rejected              = Join-Path $WorkflowRoot "rejected"
        revision_requested    = Join-Path $WorkflowRoot "revision_requested"
        replan_requested      = Join-Path $WorkflowRoot "replan_requested"
        escalated             = Join-Path $WorkflowRoot "escalated"
        cancelled             = Join-Path $WorkflowRoot "cancelled"
        completed             = Join-Path $WorkflowRoot "completed"
    }
}

function Get-PDAApprovalWorkflowIndexPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Join-Path (Get-PDAApprovalWorkflowRoot -Root $Root) "index.json")
}

function Get-PDAApprovalWorkflowStatusSet {
    return @(
        "pending_approval",
        "approved",
        "rejected",
        "revision_requested",
        "replan_requested",
        "escalated",
        "cancelled",
        "completed"
    )
}

function New-PDAApprovalWorkflowStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return [ordered]@{
        schema_version = "1.0"
        created_at     = (Get-Date).ToUniversalTime().ToString("o")
        updated_at     = (Get-Date).ToUniversalTime().ToString("o")
        status_counts  = [ordered]@{
            pending_approval  = 0
            approved          = 0
            rejected          = 0
            revision_requested = 0
            replan_requested  = 0
            escalated         = 0
            cancelled         = 0
            completed         = 0
        }
        approval_count = 0
        pending_approval_count = 0
        blocked_count  = 0
        approvals      = @()
        store_path     = Get-PDAApprovalWorkflowIndexPath -Root $Root
    }
}

function Load-PDAApprovalWorkflowStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $IndexPath = Get-PDAApprovalWorkflowIndexPath -Root $Root
    if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
        return New-PDAApprovalWorkflowStore -Root $Root
    }

    try {
        $Json = Get-Content -LiteralPath $IndexPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($Json)) {
            return New-PDAApprovalWorkflowStore -Root $Root
        }

        $Store = $Json | ConvertFrom-Json -ErrorAction Stop
        if (-not $Store) {
            return New-PDAApprovalWorkflowStore -Root $Root
        }

        if (-not ($Store.PSObject.Properties.Name -contains "approvals")) {
            $Store | Add-Member -NotePropertyName approvals -NotePropertyValue @() -Force
        }
        if (-not ($Store.PSObject.Properties.Name -contains "status_counts")) {
            $Store | Add-Member -NotePropertyName status_counts -NotePropertyValue ([ordered]@{}) -Force
        }
        if (-not ($Store.PSObject.Properties.Name -contains "store_path")) {
            $Store | Add-Member -NotePropertyName store_path -NotePropertyValue $IndexPath -Force
        }
        return $Store
    }
    catch {
        return New-PDAApprovalWorkflowStore -Root $Root
    }
}

function Save-PDAApprovalWorkflowStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Store,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $WorkflowRoot = Get-PDAApprovalWorkflowRoot -Root $Root
    New-Item -ItemType Directory -Force -Path $WorkflowRoot | Out-Null
    $StorePath = Get-PDAApprovalWorkflowIndexPath -Root $Root
    $Store.updated_at = (Get-Date).ToUniversalTime().ToString("o")
    $Store.store_path = $StorePath
    $Store | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $StorePath -Encoding UTF8
    return $StorePath
}

function Get-PDAApprovalWorkflowRecordPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApprovalId,

        [Parameter(Mandatory = $false)]
        [string]$Status = "pending_approval",

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Folders = Get-PDAApprovalWorkflowFolders -Root $Root
    $FolderName = if ($Folders.Contains($Status)) { $Status } else { "pending_approval" }
    return (Join-Path $Folders[$FolderName] ("{0}.json" -f $ApprovalId))
}

function Test-PDAApprovalWorkflowTransitionAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FromStatus,
        [Parameter(Mandatory = $true)][string]$ToStatus
    )

    $From = [string]$FromStatus
    $To = [string]$ToStatus
    if ([string]::IsNullOrWhiteSpace($From)) {
        $From = "pending_approval"
    }

    $AllowedTransitions = [ordered]@{
        pending_approval   = @("approved", "rejected", "revision_requested", "replan_requested", "escalated", "cancelled")
        revision_requested  = @("pending_approval", "cancelled")
        replan_requested   = @("pending_approval", "cancelled")
        escalated          = @("pending_approval", "approved", "rejected", "cancelled")
        approved           = @("completed")
        rejected           = @()
        cancelled          = @()
        completed          = @()
    }

    if (-not $AllowedTransitions.Contains($From)) {
        return [pscustomobject]@{
            allowed = $false
            reason = "Unknown approval status '$From'."
        }
    }

    if ($AllowedTransitions[$From] -contains $To) {
        return [pscustomobject]@{
            allowed = $true
            reason = ""
        }
    }

    return [pscustomobject]@{
        allowed = $false
        reason = "Transition from '$From' to '$To' is not allowed."
    }
}

function Get-PDAApprovalWorkflowRecordCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Folders = Get-PDAApprovalWorkflowFolders -Root $Root
    $Records = New-Object System.Collections.Generic.List[object]
    foreach ($Folder in @($Folders.Values)) {
        if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
            continue
        }

        foreach ($File in @(Get-ChildItem -LiteralPath $Folder -Filter *.json -File -ErrorAction SilentlyContinue)) {
            try {
                $Json = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace($Json)) {
                    continue
                }

                $Record = $Json | ConvertFrom-Json -ErrorAction Stop
                if (-not $Record) {
                    continue
                }

                if (-not ($Record.PSObject.Properties.Name -contains "approval_id")) {
                    $Record | Add-Member -NotePropertyName approval_id -NotePropertyValue ([System.IO.Path]::GetFileNameWithoutExtension($File.Name)) -Force
                }
                if (-not ($Record.PSObject.Properties.Name -contains "approval_path")) {
                    $Record | Add-Member -NotePropertyName approval_path -NotePropertyValue $File.FullName -Force
                }
                $Records.Add($Record) | Out-Null
            }
            catch {}
        }
    }

    return @($Records.ToArray())
}

function Get-PDAApprovalWorkflowTimestamp {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)]$Value)

    if ($null -eq $Value) {
        return [datetime]::MinValue
    }

    foreach ($Property in @("updated_at", "requested_at", "response_timestamp", "request_timestamp", "created_at", "recorded_at", "timestamp")) {
        if ($Value.PSObject.Properties.Name -contains $Property -and -not [string]::IsNullOrWhiteSpace([string]$Value.$Property)) {
            try {
                return [datetime]::Parse([string]$Value.$Property).ToUniversalTime()
            }
            catch {}
        }
    }

    return [datetime]::MinValue
}

function Get-PDAApprovalRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ApprovalId,

        [Parameter(Mandatory = $false)]
        [string]$RunId,

        [Parameter(Mandatory = $false)]
        [string]$ConversationId,

        [Parameter(Mandatory = $false)]
        [string]$SessionId,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Records = @(Get-PDAApprovalWorkflowRecordCandidates -Root $Root)
    if ($Records.Count -eq 0) {
        return $null
    }

    if (-not [string]::IsNullOrWhiteSpace($ApprovalId)) {
        return @($Records | Where-Object { [string]$_.approval_id -eq $ApprovalId } | Select-Object -First 1)[0]
    }

    if (-not [string]::IsNullOrWhiteSpace($RunId)) {
        return @($Records | Where-Object { [string]$_.run_id -eq $RunId } | Select-Object -First 1)[0]
    }

    if (-not [string]::IsNullOrWhiteSpace($ConversationId)) {
        $ConversationMatches = @($Records | Where-Object { [string]$_.conversation_id -eq $ConversationId })
        if ($ConversationMatches.Count -gt 0) {
            return $ConversationMatches[0]
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $SessionMatches = @($Records | Where-Object { [string]$_.session_id -eq $SessionId })
        if ($SessionMatches.Count -gt 0) {
            return $SessionMatches[0]
        }
    }

    return $null
}

function Get-PDAApprovalWorkflowRecentSummaries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [int]$Latest = 10
    )

    $Records = @(Get-PDAApprovalWorkflowRecordCandidates -Root $Root)
    if ($Records.Count -eq 0) {
        return @()
    }

    return @(
        $Records |
            Sort-Object -Descending -Property @{
                Expression = { Get-PDAApprovalWorkflowTimestamp -Value $_ }
            } |
            Select-Object -First $Latest
    )
}

function Update-PDAApprovalRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApprovalId,

        [Parameter(Mandatory = $false)]
        [ValidateSet("pending_approval", "approved", "rejected", "revision_requested", "replan_requested", "escalated", "cancelled", "completed")]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [string]$Approver = "",

        [Parameter(Mandatory = $false)]
        [string]$Rationale = "",

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [switch]$NoThrow
    )

    $Record = Get-PDAApprovalRequest -ApprovalId $ApprovalId -Root $Root
    if (-not $Record) {
        $Result = [pscustomobject]@{
            status = "missing"
            approval_id = $ApprovalId
            allowed = $false
            blocked_reason = "Approval record not found."
        }
        if (-not $NoThrow) {
            throw $Result.blocked_reason
        }
        return $Result
    }

    $CurrentStatus = if ($Record.PSObject.Properties.Name -contains "status") { [string]$Record.status } else { "pending_approval" }
    $TargetStatus = if ([string]::IsNullOrWhiteSpace($Status)) { $CurrentStatus } else { [string]$Status }

    $Transition = Test-PDAApprovalWorkflowTransitionAllowed -FromStatus $CurrentStatus -ToStatus $TargetStatus
    if (-not $Transition.allowed) {
        $Result = [pscustomobject]@{
            status = "blocked"
            approval_id = [string]$Record.approval_id
            allowed = $false
            blocked_reason = [string]$Transition.reason
            approval = $Record
        }
        if (-not $NoThrow) {
            throw $Transition.reason
        }
        return $Result
    }

    $PreviousStatus = $CurrentStatus
    $Now = (Get-Date).ToUniversalTime().ToString("o")
    $History = @()
    if ($Record.PSObject.Properties.Name -contains "history" -and $Record.history) {
        $History = @($Record.history)
    }

    $HistoryEntry = [pscustomobject]@{
        from_status = $PreviousStatus
        to_status = $TargetStatus
        actor = $(if ([string]::IsNullOrWhiteSpace($Approver)) { "human" } else { $Approver })
        rationale = [string]$Rationale
        timestamp = $Now
        event = "status_transition"
    }
    $History = @($History) + @($HistoryEntry)

    $Record.status = $TargetStatus
    $Record.updated_at = $Now
    $Record.response_timestamp = if ($TargetStatus -in @("approved", "rejected", "revision_requested", "replan_requested", "escalated", "cancelled", "completed")) { $Now } else { if ($Record.PSObject.Properties.Name -contains "response_timestamp" -and -not [string]::IsNullOrWhiteSpace([string]$Record.response_timestamp)) { [string]$Record.response_timestamp } else { "" } }
    $Record.approver = if ([string]::IsNullOrWhiteSpace($Approver)) { $(if ($Record.PSObject.Properties.Name -contains "approver") { [string]$Record.approver } else { "" }) } else { $Approver }
    $Record.rationale = if ([string]::IsNullOrWhiteSpace($Rationale)) { $(if ($Record.PSObject.Properties.Name -contains "rationale") { [string]$Record.rationale } else { "" }) } else { $Rationale }
    $Record.history = @($History)
    $Record.approved = [bool]($TargetStatus -in @("approved", "completed"))
    $Record.dispatch_ready = [bool]($TargetStatus -eq "approved")
    $PendingRecordStatus = if ($TargetStatus -eq "pending_approval") { "awaiting_confirmation" } else { $TargetStatus }
    if ($Record.PSObject.Properties.Name -contains "pending_status") {
        $Record.pending_status = $PendingRecordStatus
    }
    else {
        $Record | Add-Member -NotePropertyName pending_status -NotePropertyValue $PendingRecordStatus -Force
    }
    $Record.approval_history = @($History)

    $Folders = Get-PDAApprovalWorkflowFolders -Root $Root
    foreach ($Folder in @($Folders.Values)) {
        New-Item -ItemType Directory -Force -Path $Folder | Out-Null
    }

    $OldPath = if ($Record.PSObject.Properties.Name -contains "approval_path" -and -not [string]::IsNullOrWhiteSpace([string]$Record.approval_path)) {
        [string]$Record.approval_path
    }
    else {
        Get-PDAApprovalWorkflowRecordPath -ApprovalId $ApprovalId -Status $PreviousStatus -Root $Root
    }
    $NewPath = Get-PDAApprovalWorkflowRecordPath -ApprovalId $ApprovalId -Status $TargetStatus -Root $Root

    $Record.approval_path = $NewPath
    $Record | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $NewPath -Encoding UTF8
    if ($OldPath -and (Test-Path -LiteralPath $OldPath -PathType Leaf) -and ($OldPath -ne $NewPath)) {
        Remove-Item -LiteralPath $OldPath -Force -ErrorAction SilentlyContinue
    }

    $Store = Load-PDAApprovalWorkflowStore -Root $Root
    $Approvals = @($Store.approvals | Where-Object { [string]$_.approval_id -ne $ApprovalId })
    $Summary = [pscustomobject]@{
        approval_id = [string]$Record.approval_id
        run_id = if ($Record.PSObject.Properties.Name -contains "run_id") { [string]$Record.run_id } else { "" }
        conversation_id = if ($Record.PSObject.Properties.Name -contains "conversation_id") { [string]$Record.conversation_id } else { "" }
        session_id = if ($Record.PSObject.Properties.Name -contains "session_id") { [string]$Record.session_id } else { "" }
        goal = if ($Record.PSObject.Properties.Name -contains "goal") { [string]$Record.goal } else { "" }
        requested_action = if ($Record.PSObject.Properties.Name -contains "requested_action") { [string]$Record.requested_action } else { "" }
        status = $TargetStatus
        category = if ($Record.PSObject.Properties.Name -contains "category") { [string]$Record.category } else { "" }
        route_type = if ($Record.PSObject.Properties.Name -contains "route_type") { [string]$Record.route_type } else { "" }
        recommended_command = if ($Record.PSObject.Properties.Name -contains "recommended_command") { [string]$Record.recommended_command } else { "" }
        recommended_executor = if ($Record.PSObject.Properties.Name -contains "recommended_executor") { [string]$Record.recommended_executor } else { "" }
        requested_at = if ($Record.PSObject.Properties.Name -contains "request_timestamp") { [string]$Record.request_timestamp } else { "" }
        response_timestamp = [string]$Record.response_timestamp
        updated_at = [string]$Record.updated_at
        approval_path = [string]$Record.approval_path
    }
    $Approvals = @($Summary) + @($Approvals)
    $Store.approvals = @($Approvals)
    $Store.approval_count = @($Approvals).Count
    $Store.pending_approval_count = @($Approvals | Where-Object { [string]$_.status -eq "pending_approval" }).Count
    $Store.blocked_count = @($Approvals | Where-Object { [string]$_.status -in @("rejected", "cancelled") }).Count
    $Counts = [ordered]@{
        pending_approval   = @($Approvals | Where-Object { [string]$_.status -eq "pending_approval" }).Count
        approved           = @($Approvals | Where-Object { [string]$_.status -eq "approved" }).Count
        rejected           = @($Approvals | Where-Object { [string]$_.status -eq "rejected" }).Count
        revision_requested  = @($Approvals | Where-Object { [string]$_.status -eq "revision_requested" }).Count
        replan_requested    = @($Approvals | Where-Object { [string]$_.status -eq "replan_requested" }).Count
        escalated           = @($Approvals | Where-Object { [string]$_.status -eq "escalated" }).Count
        cancelled           = @($Approvals | Where-Object { [string]$_.status -eq "cancelled" }).Count
        completed           = @($Approvals | Where-Object { [string]$_.status -eq "completed" }).Count
    }
    $Store.status_counts = $Counts
    Save-PDAApprovalWorkflowStore -Store $Store -Root $Root | Out-Null

    return [pscustomobject]@{
        status = "pass"
        approval_id = [string]$Record.approval_id
        approval_path = [string]$Record.approval_path
        approval = $Record
        allowed = $true
        blocked_reason = ""
        previous_status = $PreviousStatus
        current_status = $TargetStatus
        approval_history = @($History)
    }
}

function New-PDAApprovalRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$RunId = "",

        [Parameter(Mandatory = $false)]
        [string]$ConversationId = "",

        [Parameter(Mandatory = $false)]
        [string]$SessionId = "",

        [Parameter(Mandatory = $false)]
        [string]$Goal = "",

        [Parameter(Mandatory = $false)]
        [string]$RequestedAction = "",

        [Parameter(Mandatory = $false)]
        [string]$Category = "category_1",

        [Parameter(Mandatory = $false)]
        [string]$RouteType = "",

        [Parameter(Mandatory = $false)]
        [string]$RecommendedCommand = "",

        [Parameter(Mandatory = $false)]
        [string]$RecommendedExecutor = "",

        [Parameter(Mandatory = $false)]
        [string]$DispatchCategory = "",

        [Parameter(Mandatory = $false)]
        [string]$UserMessage = "",

        [Parameter(Mandatory = $false)]
        [string]$ApprovalKind = "goal_plan",

        [Parameter(Mandatory = $false)]
        [string]$ApprovalRationale = "",

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Now = (Get-Date).ToUniversalTime().ToString("o")
    $ApprovalId = "approval-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
    $Folders = Get-PDAApprovalWorkflowFolders -Root $Root
    foreach ($Folder in @($Folders.Values)) {
        New-Item -ItemType Directory -Force -Path $Folder | Out-Null
    }

    $Record = [ordered]@{
        schema_version = "1.0"
        approval_id = $ApprovalId
        run_id = [string]$RunId
        conversation_id = [string]$ConversationId
        session_id = [string]$SessionId
        goal = [string]$Goal
        requested_action = [string]$RequestedAction
        category = [string]$Category
        route_type = [string]$RouteType
        recommended_command = [string]$RecommendedCommand
        recommended_executor = [string]$RecommendedExecutor
        dispatch_category = [string]$DispatchCategory
        user_message = [string]$UserMessage
        approval_kind = [string]$ApprovalKind
        approval_required = $true
        status = "pending_approval"
        approved = $false
        dispatch_ready = $false
        request_timestamp = $Now
        response_timestamp = ""
        approver = ""
        rationale = [string]$ApprovalRationale
        created_at = $Now
        updated_at = $Now
        history = @(
            [pscustomobject]@{
                from_status = ""
                to_status = "pending_approval"
                actor = "system"
                rationale = [string]$ApprovalRationale
                timestamp = $Now
                event = "created"
            }
        )
        approval_history = @()
    }

    $ApprovalPath = Get-PDAApprovalWorkflowRecordPath -ApprovalId $ApprovalId -Status "pending_approval" -Root $Root
    $Record.approval_path = $ApprovalPath
    $Record | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $ApprovalPath -Encoding UTF8

    $Store = Load-PDAApprovalWorkflowStore -Root $Root
    $Summary = [pscustomobject]@{
        approval_id = $ApprovalId
        run_id = [string]$RunId
        conversation_id = [string]$ConversationId
        session_id = [string]$SessionId
        goal = [string]$Goal
        requested_action = [string]$RequestedAction
        status = "pending_approval"
        category = [string]$Category
        route_type = [string]$RouteType
        recommended_command = [string]$RecommendedCommand
        recommended_executor = [string]$RecommendedExecutor
        requested_at = $Now
        response_timestamp = ""
        updated_at = $Now
        approval_path = [string]$ApprovalPath
    }
    $Store.approvals = @($Summary) + @(@($Store.approvals | Where-Object { [string]$_.approval_id -ne $ApprovalId }))
    $Store.approval_count = @($Store.approvals).Count
    $Store.pending_approval_count = @($Store.approvals | Where-Object { [string]$_.status -eq "pending_approval" }).Count
    $Store.blocked_count = @($Store.approvals | Where-Object { [string]$_.status -in @("rejected", "cancelled") }).Count
    $Store.status_counts = [ordered]@{
        pending_approval   = @($Store.approvals | Where-Object { [string]$_.status -eq "pending_approval" }).Count
        approved           = @($Store.approvals | Where-Object { [string]$_.status -eq "approved" }).Count
        rejected           = @($Store.approvals | Where-Object { [string]$_.status -eq "rejected" }).Count
        revision_requested  = @($Store.approvals | Where-Object { [string]$_.status -eq "revision_requested" }).Count
        replan_requested    = @($Store.approvals | Where-Object { [string]$_.status -eq "replan_requested" }).Count
        escalated           = @($Store.approvals | Where-Object { [string]$_.status -eq "escalated" }).Count
        cancelled           = @($Store.approvals | Where-Object { [string]$_.status -eq "cancelled" }).Count
        completed           = @($Store.approvals | Where-Object { [string]$_.status -eq "completed" }).Count
    }
    Save-PDAApprovalWorkflowStore -Store $Store -Root $Root | Out-Null

    return [pscustomobject]@{
        status = "pass"
        approval_id = $ApprovalId
        approval_path = $ApprovalPath
        approval = [pscustomobject]$Record
        summary = $Summary
    }
}

function Get-PDAApprovalWorkflowStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [int]$Latest = 10
    )

    $Store = Load-PDAApprovalWorkflowStore -Root $Root
    $AllRecords = @(Get-PDAApprovalWorkflowRecordCandidates -Root $Root)
    $DedupedRecords = New-Object System.Collections.Generic.List[object]
    if ($AllRecords.Count -gt 0) {
        foreach ($Group in @($AllRecords | Group-Object -Property { [string]$_.approval_id })) {
            $LatestRecord = @(
                $Group.Group |
                    Sort-Object -Descending -Property @{
                        Expression = { Get-PDAApprovalWorkflowTimestamp -Value $_ }
                    } |
                    Select-Object -First 1
            )[0]
            if ($LatestRecord) {
                $DedupedRecords.Add($LatestRecord) | Out-Null
            }
        }
    }

    $PendingApprovalCount = [int](@($DedupedRecords | Where-Object { [string]$_.status -eq "pending_approval" }).Count)
    $ApprovedCount = [int](@($DedupedRecords | Where-Object { [string]$_.status -eq "approved" }).Count)
    $RejectedCount = [int](@($DedupedRecords | Where-Object { [string]$_.status -eq "rejected" }).Count)
    $RevisionRequestedCount = [int](@($DedupedRecords | Where-Object { [string]$_.status -eq "revision_requested" }).Count)
    $ReplanRequestedCount = [int](@($DedupedRecords | Where-Object { [string]$_.status -eq "replan_requested" }).Count)
    $EscalatedCount = [int](@($DedupedRecords | Where-Object { [string]$_.status -eq "escalated" }).Count)
    $CancelledCount = [int](@($DedupedRecords | Where-Object { [string]$_.status -eq "cancelled" }).Count)
    $CompletedCount = [int](@($DedupedRecords | Where-Object { [string]$_.status -in @("approved", "completed") }).Count)

    $StaleCount = 0
    foreach ($Group in @($AllRecords | Group-Object -Property { [string]$_.approval_id })) {
        $Statuses = @($Group.Group | ForEach-Object { [string]$_.status } | Select-Object -Unique)
        if ($Statuses.Count -gt 1 -and $Statuses -contains "pending_approval") {
            $LatestStatus = [string]((@($Group.Group | Sort-Object -Descending -Property @{ Expression = { Get-PDAApprovalWorkflowTimestamp -Value $_ } } | Select-Object -First 1)[0]).status)
            if ($LatestStatus -ne "pending_approval") {
                $StaleCount++
            }
        }
    }

    $ApprovalCount = if ($null -eq $DedupedRecords) { 0 } else { [int]$DedupedRecords.Count }
    $Index = Get-PDAApprovalWorkflowIndexPath -Root $Root
    $AgentRunIndexPath = Join-Path $Root "PDA-Agent-Runs\index.json"
    $BlockedAgentRuns = 0
    $PendingAgentRuns = 0
    if (Test-Path -LiteralPath $AgentRunIndexPath -PathType Leaf) {
        try {
            $AgentIndex = Get-Content -LiteralPath $AgentRunIndexPath -Raw | ConvertFrom-Json
            if ($AgentIndex -and $AgentIndex.PSObject.Properties.Name -contains "runs") {
                $Runs = @($AgentIndex.runs)
                $BlockedAgentRuns = @($Runs | Where-Object { [string]$_.status -eq "blocked" }).Count
                $PendingAgentRuns = @($Runs | Where-Object { [string]$_.status -eq "pending_approval" -or [string]$_.approval_status -eq "pending" }).Count
            }
        }
        catch {}
    }

    $BlockedCount = [int](($RejectedCount + $CancelledCount + $BlockedAgentRuns))
    $RecentApprovals = @($AllRecords | Sort-Object -Descending -Property @{ Expression = { Get-PDAApprovalWorkflowTimestamp -Value $_ } } | Select-Object -First $Latest)
    $RecentPending = @($DedupedRecords | Where-Object { [string]$_.status -eq "pending_approval" } | Sort-Object -Descending -Property @{ Expression = { Get-PDAApprovalWorkflowTimestamp -Value $_ } } | Select-Object -First $Latest)

    return [pscustomobject]@{
        status = "pass"
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        root_path = $Root
        store_path = $Store.store_path
        index_path = $Index
        counts = [pscustomobject]@{
            pending_approval = $PendingApprovalCount
            approved = $ApprovedCount
            rejected = $RejectedCount
            revision_requested = $RevisionRequestedCount
            replan_requested = $ReplanRequestedCount
            escalated = $EscalatedCount
            cancelled = $CancelledCount
            completed = $CompletedCount
            stale = [int]$StaleCount
            blocked = $BlockedCount
            blocked_agent_runs = [int]$BlockedAgentRuns
            pending_agent_runs = [int]$PendingAgentRuns
        }
        approval_count = $ApprovalCount
        pending_approval_count = $PendingApprovalCount
        blocked_count = $BlockedCount
        stale_count = [int]$StaleCount
        recent_approvals = $RecentApprovals
        recent_pending = $RecentPending
    }
}
