[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RequestId = "",

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

function Get-PDAExecutionRequestRoot {
    param([Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot))
    return (Join-Path $Root "PDA-Runtime\data\execution-requests")
}

function Get-PDAExecutionRequestIndexPath {
    param([Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot))
    return (Join-Path (Get-PDAExecutionRequestRoot -Root $Root) "index.json")
}

function Get-PDAExecutionRequestFolders {
    param([Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot))

    $RequestRoot = Get-PDAExecutionRequestRoot -Root $Root
    return [ordered]@{
        draft = Join-Path $RequestRoot "draft"
        pending_approval = Join-Path $RequestRoot "pending_approval"
        approved = Join-Path $RequestRoot "approved"
        rejected = Join-Path $RequestRoot "rejected"
        cancelled = Join-Path $RequestRoot "cancelled"
        completed = Join-Path $RequestRoot "completed"
    }
}

function Read-PDAExecutionRequestJson {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        $Raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($Raw)) {
            return $null
        }

        return $Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Get-PDAExecutionRequestStore {
    param([Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot))

    $IndexPath = Get-PDAExecutionRequestIndexPath -Root $Root
    if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
        return [pscustomobject]@{
            schema_version = "1.0"
            created_at = (Get-Date).ToUniversalTime().ToString("o")
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            request_count = 0
            draft_count = 0
            pending_approval_count = 0
            approved_count = 0
            rejected_count = 0
            cancelled_count = 0
            completed_count = 0
            approval_required_count = 0
            restricted_local_only_count = 0
            requests = @()
            store_path = Get-PDAExecutionRequestRoot -Root $Root
            index_path = $IndexPath
        }
    }

    try {
        $Store = Get-Content -LiteralPath $IndexPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return $Store
    }
    catch {
        return [pscustomobject]@{
            schema_version = "1.0"
            created_at = (Get-Date).ToUniversalTime().ToString("o")
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            request_count = 0
            draft_count = 0
            pending_approval_count = 0
            approved_count = 0
            rejected_count = 0
            cancelled_count = 0
            completed_count = 0
            approval_required_count = 0
            restricted_local_only_count = 0
            requests = @()
            store_path = Get-PDAExecutionRequestRoot -Root $Root
            index_path = $IndexPath
            error = $_.Exception.Message
        }
    }
}

function Get-PDAExecutionRequestRecordPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestId,

        [Parameter(Mandatory = $false)]
        [string]$Status = "draft",

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Folders = Get-PDAExecutionRequestFolders -Root $Root
    $FolderName = if ($Folders.Contains($Status)) { $Status } else { "draft" }
    return (Join-Path $Folders[$FolderName] ("{0}.json" -f $RequestId))
}

function Get-PDAExecutionRequestRecords {
    param([Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot))

    $Folders = Get-PDAExecutionRequestFolders -Root $Root
    $Records = New-Object System.Collections.Generic.List[object]

    foreach ($Folder in @($Folders.Values)) {
        if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
            continue
        }

        foreach ($File in @(Get-ChildItem -LiteralPath $Folder -Filter *.json -File -ErrorAction SilentlyContinue)) {
            try {
                $Record = Read-PDAExecutionRequestJson -Path $File.FullName
                if (-not $Record) {
                    continue
                }

                if (-not ($Record.PSObject.Properties.Name -contains "request_id")) {
                    $Record | Add-Member -NotePropertyName request_id -NotePropertyValue ([System.IO.Path]::GetFileNameWithoutExtension($File.Name)) -Force
                }
                if (-not ($Record.PSObject.Properties.Name -contains "request_path")) {
                    $Record | Add-Member -NotePropertyName request_path -NotePropertyValue $File.FullName -Force
                }
                if (-not ($Record.PSObject.Properties.Name -contains "request_status")) {
                    $Record | Add-Member -NotePropertyName request_status -NotePropertyValue ([string]$Folder.Name) -Force
                }

                $Records.Add($Record) | Out-Null
            }
            catch {}
        }
    }

    return @($Records.ToArray())
}

function Get-PDAExecutionRequestById {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestId,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $RequestRoot = Get-PDAExecutionRequestRoot -Root $Root
    if (-not (Test-Path -LiteralPath $RequestRoot -PathType Container)) {
        return $null
    }

    $Candidates = @(Get-ChildItem -LiteralPath $RequestRoot -Recurse -File -Filter ("{0}.json" -f $RequestId) -ErrorAction SilentlyContinue)
    foreach ($Candidate in $Candidates) {
        $Record = Read-PDAExecutionRequestJson -Path $Candidate.FullName
        if ($Record) {
            if (-not ($Record.PSObject.Properties.Name -contains "request_id")) {
                $Record | Add-Member -NotePropertyName request_id -NotePropertyValue $RequestId -Force
            }
            if (-not ($Record.PSObject.Properties.Name -contains "request_path")) {
                $Record | Add-Member -NotePropertyName request_path -NotePropertyValue $Candidate.FullName -Force
            }
            return $Record
        }
    }

    return $null
}

function Get-PDAExecutionRequestSummary {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Requests,

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $SortedRequests = @(
        $Requests | Sort-Object -Property @{
            Expression = {
                if ($_.PSObject.Properties.Name -contains "updated_at" -and -not [string]::IsNullOrWhiteSpace([string]$_.updated_at)) {
                    [datetime]::Parse([string]$_.updated_at)
                }
                elseif ($_.PSObject.Properties.Name -contains "request_timestamp" -and -not [string]::IsNullOrWhiteSpace([string]$_.request_timestamp)) {
                    [datetime]::Parse([string]$_.request_timestamp)
                }
                else {
                    [datetime]::MinValue
                }
            }
        } -Descending
    )

    $RequestCount = @($SortedRequests).Count
    $DraftCount = @($SortedRequests | Where-Object { [string]$_.request_status -eq "draft" }).Count
    $PendingCount = @($SortedRequests | Where-Object { [string]$_.request_status -eq "pending_approval" }).Count
    $ApprovedCount = @($SortedRequests | Where-Object { [string]$_.request_status -eq "approved" }).Count
    $RejectedCount = @($SortedRequests | Where-Object { [string]$_.request_status -eq "rejected" }).Count
    $CancelledCount = @($SortedRequests | Where-Object { [string]$_.request_status -eq "cancelled" }).Count
    $CompletedCount = @($SortedRequests | Where-Object { [string]$_.request_status -eq "completed" }).Count
    $ApprovalRequiredCount = @($SortedRequests | Where-Object { [bool]$_.approval_required }).Count
    $RestrictedLocalOnlyCount = @($SortedRequests | Where-Object { [bool]$_.restricted_local_only }).Count

    $RecentRequests = @(
        $SortedRequests |
            Select-Object -First 10 |
            ForEach-Object {
                [pscustomobject]@{
                    request_id = [string]$_.request_id
                    request_type = [string]$_.request_type
                    capability = [string]$_.capability
                    agent = [string]$_.agent
                    provider = [string]$_.provider
                    tool = [string]$_.tool
                    request_status = [string]$_.request_status
                    approval_status = [string]$_.approval_status
                    approval_required = [bool]$_.approval_required
                    execution_plan_id = if ($_.PSObject.Properties.Name -contains "execution_plan_id") { [string]$_.execution_plan_id } else { "" }
                    request_path = [string]$_.request_path
                    updated_at = if ($_.PSObject.Properties.Name -contains "updated_at") { [string]$_.updated_at } else { "" }
                }
            }
    )

    $RecentPending = @(
        $SortedRequests |
            Where-Object { [string]$_.request_status -eq "pending_approval" } |
            Select-Object -First 10 |
            ForEach-Object {
                [pscustomobject]@{
                    request_id = [string]$_.request_id
                    capability = [string]$_.capability
                    agent = [string]$_.agent
                    provider = [string]$_.provider
                    tool = [string]$_.tool
                    approval_status = [string]$_.approval_status
                    request_path = [string]$_.request_path
                    updated_at = if ($_.PSObject.Properties.Name -contains "updated_at") { [string]$_.updated_at } else { "" }
                }
            }
    )

    $RecentApproved = @(
        $SortedRequests |
            Where-Object { [string]$_.request_status -eq "approved" } |
            Select-Object -First 10 |
            ForEach-Object {
                [pscustomobject]@{
                    request_id = [string]$_.request_id
                    capability = [string]$_.capability
                    agent = [string]$_.agent
                    provider = [string]$_.provider
                    tool = [string]$_.tool
                    approval_status = [string]$_.approval_status
                    request_path = [string]$_.request_path
                    updated_at = if ($_.PSObject.Properties.Name -contains "updated_at") { [string]$_.updated_at } else { "" }
                }
            }
    )

    return [pscustomobject]@{
        status = $(if ($RequestCount -gt 0) { "pass" } else { "empty" })
        request_count = [int]$RequestCount
        draft_count = [int]$DraftCount
        pending_approval_count = [int]$PendingCount
        approved_count = [int]$ApprovedCount
        rejected_count = [int]$RejectedCount
        cancelled_count = [int]$CancelledCount
        completed_count = [int]$CompletedCount
        approval_required_count = [int]$ApprovalRequiredCount
        restricted_local_only_count = [int]$RestrictedLocalOnlyCount
        recent_requests = @($RecentRequests)
        recent_pending_requests = @($RecentPending)
        recent_approved_requests = @($RecentApproved)
    }
}

$Store = Get-PDAExecutionRequestStore -Root $Root
$Requests = @(Get-PDAExecutionRequestRecords -Root $Root)

if (-not [string]::IsNullOrWhiteSpace($RequestId)) {
    $Record = Get-PDAExecutionRequestById -RequestId $RequestId -Root $Root
    if (-not $Record) {
        $Result = [pscustomobject]@{
            status = "missing"
            request_id = $RequestId
            request = $null
        }
    }
    else {
        $Result = [pscustomobject]@{
            status = "pass"
            request_id = [string]$Record.request_id
            request = $Record
        }
    }
}
else {
    $Summary = Get-PDAExecutionRequestSummary -Requests $Requests -Root $Root
    $Result = [pscustomobject]@{
        status = [string]$Summary.status
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        root_path = $Root
        store_path = if ($Store.PSObject.Properties.Name -contains "store_path") { [string]$Store.store_path } else { Get-PDAExecutionRequestRoot -Root $Root }
        index_path = if ($Store.PSObject.Properties.Name -contains "index_path") { [string]$Store.index_path } else { Get-PDAExecutionRequestIndexPath -Root $Root }
        request_count = [int]$Summary.request_count
        draft_count = [int]$Summary.draft_count
        pending_approval_count = [int]$Summary.pending_approval_count
        approved_count = [int]$Summary.approved_count
        rejected_count = [int]$Summary.rejected_count
        cancelled_count = [int]$Summary.cancelled_count
        completed_count = [int]$Summary.completed_count
        approval_required_count = [int]$Summary.approval_required_count
        restricted_local_only_count = [int]$Summary.restricted_local_only_count
        recent_requests = @($Summary.recent_requests)
        recent_pending_requests = @($Summary.recent_pending_requests)
        recent_approved_requests = @($Summary.recent_approved_requests)
    }
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 30
    if (-not $NoThrow -and $Result.status -eq "fail") {
        throw "PDA execution request lookup failed."
    }
    return
}

if (-not [string]::IsNullOrWhiteSpace($RequestId)) {
    Write-Host "[PDA EXECUTION REQUEST]"
    Write-Host ("Request ID : {0}" -f $RequestId)
    Write-Host ("Status     : {0}" -f $Result.status)
}
else {
    Write-Host "[PDA EXECUTION REQUEST SUMMARY]"
    Write-Host ("Requests            : {0}" -f $Result.request_count)
    Write-Host ("Draft               : {0}" -f $Result.draft_count)
    Write-Host ("Pending approval    : {0}" -f $Result.pending_approval_count)
    Write-Host ("Approved            : {0}" -f $Result.approved_count)
    Write-Host ("Approval required   : {0}" -f $Result.approval_required_count)
    Write-Host ("Restricted local only: {0}" -f $Result.restricted_local_only_count)
}
