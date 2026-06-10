[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $true)]
    [string]$Capability,

    [Parameter(Mandatory = $true)]
    [string]$Agent,

    [Parameter(Mandatory = $true)]
    [string]$Provider,

    [Parameter(Mandatory = $true)]
    [ValidateSet("category_1", "category_2")]
    [string]$Category,

    [Parameter(Mandatory = $false)]
    [string]$RequestType = "",

    [Parameter(Mandatory = $false)]
    [string]$ApprovalId = "",

    [Parameter(Mandatory = $false)]
    [string]$ApprovalRationale = "",

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$ToolResolverScript = Join-Path $PSScriptRoot "Resolve-PDATool.ps1"
$PlanResolverScript = Join-Path $PSScriptRoot "Resolve-PDAExecutionPlan.ps1"
$RequestRegistryPath = Join-Path $PSScriptRoot "PDA_ExecutionRequestRegistry.json"
$ApprovalWorkflowScript = Join-Path $PSScriptRoot "PDA_ApprovalWorkflow.ps1"
if ((Test-Path -LiteralPath $ApprovalWorkflowScript -PathType Leaf) -and -not (Get-Command -Name New-PDAApprovalRequest -ErrorAction SilentlyContinue)) {
    . $ApprovalWorkflowScript
}

function ConvertFrom-PDAMixedJson {
    param([Parameter(Mandatory = $true)][string]$Text)

    $Trimmed = [string]$Text.Trim()
    if ([string]::IsNullOrWhiteSpace($Trimmed)) {
        return $null
    }

    try {
        return $Trimmed | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $Start = $Trimmed.LastIndexOf("{")
        $End = $Trimmed.LastIndexOf("}")
        if ($Start -ge 0 -and $End -gt $Start) {
            $Candidate = $Trimmed.Substring($Start, $End - $Start + 1)
            return $Candidate | ConvertFrom-Json -ErrorAction Stop
        }
        throw
    }
}

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

function Load-PDAExecutionRequestRegistry {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Execution request registry missing: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

function Invoke-PDAJsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$SourceName
    )

    $Raw = & pwsh -NoProfile -File $Path @Arguments 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "$SourceName returned empty output."
    }

    return ConvertFrom-PDAMixedJson -Text $Text
}

$Capability = [string]$Capability.Trim()
$Agent = [string]$Agent.Trim()
$Provider = [string]$Provider.Trim()
$Category = [string]$Category.Trim().ToLowerInvariant()

if ([string]::IsNullOrWhiteSpace($Capability) -or [string]::IsNullOrWhiteSpace($Agent) -or [string]::IsNullOrWhiteSpace($Provider) -or [string]::IsNullOrWhiteSpace($Category)) {
    throw "Capability, Agent, Provider, and Category are required."
}

$ToolResolution = Invoke-PDAJsonScript -Path $ToolResolverScript -Arguments @("-Capability", $Capability, "-Agent", $Agent, "-Provider", $Provider, "-Category", $Category, "-AsJson", "-NoThrow") -SourceName "PDA tool resolution"
if ([string]$ToolResolution.status -ne "pass") {
    throw "Tool resolution failed for capability '$Capability'."
}

$PlanResolution = Invoke-PDAJsonScript -Path $PlanResolverScript -Arguments @("-CapabilityId", $Capability, "-SelectedAgent", $Agent, "-SelectedProvider", $Provider, "-Category", $Category, "-AsJson", "-NoThrow") -SourceName "PDA execution plan resolution"
if ([string]$PlanResolution.status -ne "pass") {
    throw "Execution plan resolution failed for capability '$Capability'."
}

$Registry = Load-PDAExecutionRequestRegistry -Path $RequestRegistryPath
$Template = @($Registry.request_templates | Where-Object {
    [string]$_.capability -ieq $Capability -and
    [string]$_.agent -ieq $Agent -and
    [string]$_.provider -ieq $Provider -and
    [string]$_.tool -ieq $ToolResolution.selected_tool
} | Select-Object -First 1)[0]

if (-not $Template) {
    $Template = @($Registry.request_templates | Where-Object {
        [string]$_.capability -ieq $Capability -and
        [string]$_.agent -ieq $Agent
    } | Select-Object -First 1)[0]
}

$RequestType = if (-not [string]::IsNullOrWhiteSpace($RequestType)) {
    $RequestType
}
elseif ($Template) {
    [string]$Template.request_type
}
else {
    "{0}_execution_request" -f ($Capability.Trim().ToLowerInvariant() -replace "[^a-z0-9]+", "_")
}

$RequestId = "execution-request-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
$RequestRoot = Get-PDAExecutionRequestRoot -Root $Root
New-Item -ItemType Directory -Force -Path $RequestRoot | Out-Null
foreach ($Folder in @(Get-PDAExecutionRequestFolders -Root $Root).Values) {
    New-Item -ItemType Directory -Force -Path $Folder | Out-Null
}

$ApprovalRequired = [bool]$PlanResolution.approval_required
$RestrictedLocalOnly = [bool]$PlanResolution.restricted_local_only -or [bool]$ToolResolution.restricted_local_only
$RequestStatus = "draft"
$ApprovalStatus = "not_required"
$LinkedApprovalId = ""
$LinkedApprovalPath = ""
$ApprovalHistory = @()

if ($ApprovalRequired) {
    $RequestStatus = "pending_approval"
    $ApprovalStatus = "pending"

    if (-not [string]::IsNullOrWhiteSpace($ApprovalId)) {
        $ApprovalRecord = Get-PDAApprovalRequest -ApprovalId $ApprovalId -Root $Root
        if ($ApprovalRecord) {
            $LinkedApprovalId = [string]$ApprovalRecord.approval_id
            $LinkedApprovalPath = if ($ApprovalRecord.PSObject.Properties.Name -contains "approval_path") { [string]$ApprovalRecord.approval_path } else { "" }
            $ApprovalStatus = if ($ApprovalRecord.PSObject.Properties.Name -contains "status") { [string]$ApprovalRecord.status } else { "pending_approval" }
            if ($ApprovalStatus -eq "approved") {
                $RequestStatus = "approved"
            }
            elseif ($ApprovalStatus -eq "rejected") {
                $RequestStatus = "rejected"
            }
            elseif ($ApprovalStatus -eq "cancelled") {
                $RequestStatus = "cancelled"
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($LinkedApprovalId) -and (Get-Command -Name New-PDAApprovalRequest -ErrorAction SilentlyContinue)) {
        $Approval = New-PDAApprovalRequest -RunId $RequestId -ConversationId "" -SessionId "" -Goal "Execution request for $Capability" -RequestedAction "Prepare governed execution request for $Capability." -Category $Category -RouteType "execution_request" -RecommendedCommand "/approve" -RecommendedExecutor ([string]$ToolResolution.selected_tool) -DispatchCategory "governed_request" -UserMessage "Prepare execution request for $Capability." -ApprovalKind "execution_request" -ApprovalRationale $(if ([string]::IsNullOrWhiteSpace($ApprovalRationale)) { "Execution request requires approval before future execution." } else { [string]$ApprovalRationale }) -Root $Root
        if ($Approval -and $Approval.PSObject.Properties.Name -contains "approval_id") {
            $LinkedApprovalId = [string]$Approval.approval_id
            $LinkedApprovalPath = [string]$Approval.approval_path
            $ApprovalHistory = @($Approval.approval.history)
        }
    }
}

$ExpectedInputs = if ($Template -and $Template.PSObject.Properties.Name -contains "expected_inputs") { @($Template.expected_inputs) } else { @("capability", "agent", "provider", "tool") }
$ExpectedOutputs = if ($Template -and $Template.PSObject.Properties.Name -contains "expected_outputs") { @($Template.expected_outputs) } else { @($PlanResolution.outputs) }
$ExecutionPlan = [pscustomobject]@{
    execution_plan_id = [string]$PlanResolution.execution_plan_id
    execution_steps = @($PlanResolution.execution_steps)
    approval_required = [bool]$PlanResolution.approval_required
    restricted_local_only = [bool]$PlanResolution.restricted_local_only
    estimated_complexity = [string]$PlanResolution.estimated_complexity
    estimated_steps = [int]$PlanResolution.estimated_steps
    success_criteria = @($PlanResolution.success_criteria)
    outputs = @($PlanResolution.outputs)
    routing_reason = [string]$PlanResolution.routing_reason
    source_of_truth = "Scripts/Resolve-PDAExecutionPlan.ps1"
}

$ToolRecord = [pscustomobject]@{
    tool_id = [string]$ToolResolution.selected_tool
    display_name = [string]$ToolResolution.selected_tool_display_name
    approval_required = [bool]$ToolResolution.approval_required
    restricted_local_only = [bool]$ToolResolution.restricted_local_only
    candidate_tools = @($ToolResolution.candidate_tools)
    routing_reason = [string]$ToolResolution.routing_reason
    source_of_truth = "Scripts/Resolve-PDATool.ps1"
}

$Request = [ordered]@{
    schema_version = "1.0"
    request_id = $RequestId
    request_type = [string]$RequestType
    capability = $Capability
    agent = $Agent
    provider = $Provider
    tool = [string]$ToolRecord.tool_id
    tool_display_name = [string]$ToolRecord.display_name
    approval_required = [bool]$ApprovalRequired
    restricted_local_only = [bool]$RestrictedLocalOnly
    expected_inputs = @($ExpectedInputs)
    expected_outputs = @($ExpectedOutputs)
    execution_plan_id = [string]$ExecutionPlan.execution_plan_id
    execution_plan = $ExecutionPlan
    approval_status = [string]$ApprovalStatus
    request_status = [string]$RequestStatus
    approval_id = [string]$LinkedApprovalId
    approval_path = [string]$LinkedApprovalPath
    request_timestamp = (Get-Date).ToUniversalTime().ToString("o")
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    updated_at = (Get-Date).ToUniversalTime().ToString("o")
    notes = if ($Template -and $Template.PSObject.Properties.Name -contains "notes") { [string]$Template.notes } else { "Governed execution request prepared without dispatch." }
    tool_resolution = $ToolRecord
    approval_history = @($ApprovalHistory)
    source_of_truth = "Scripts/New-PDAExecutionRequest.ps1"
}

$RequestPath = Get-PDAExecutionRequestRecordPath -RequestId $RequestId -Status $RequestStatus -Root $Root
$Request.request_path = $RequestPath
$Request | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $RequestPath -Encoding UTF8

function Get-PDAExecutionRequestGetRecords {
    param([Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot))

    $Folders = Get-PDAExecutionRequestFolders -Root $Root
    $Records = New-Object System.Collections.Generic.List[object]

    foreach ($Folder in @($Folders.Values)) {
        if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
            continue
        }

        foreach ($File in @(Get-ChildItem -LiteralPath $Folder -Filter *.json -File -ErrorAction SilentlyContinue)) {
            try {
                $Record = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
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

$IndexPath = Get-PDAExecutionRequestIndexPath -Root $Root
$Index = [pscustomobject]@{
    schema_version = "1.0"
    created_at = if ($Request.PSObject.Properties.Name -contains "created_at") { [string]$Request.created_at } else { (Get-Date).ToUniversalTime().ToString("o") }
    updated_at = (Get-Date).ToUniversalTime().ToString("o")
    store_path = $RequestRoot
    index_path = $IndexPath
    requests = @()
    request_count = 0
    draft_count = 0
    pending_approval_count = 0
    approved_count = 0
    rejected_count = 0
    cancelled_count = 0
    completed_count = 0
    approval_required_count = 0
    restricted_local_only_count = 0
    latest_request = $null
    latest_pending_request = $null
    latest_approved_request = $null
}

$AllRequests = @(Get-PDAExecutionRequestGetRecords -Root $Root)
foreach ($StoredRequest in @($AllRequests | Sort-Object -Property @{
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
} -Descending)) {
    $Index.requests += [pscustomobject]@{
        request_id = [string]$StoredRequest.request_id
        request_type = [string]$StoredRequest.request_type
        capability = [string]$StoredRequest.capability
        agent = [string]$StoredRequest.agent
        provider = [string]$StoredRequest.provider
        tool = [string]$StoredRequest.tool
        request_status = [string]$StoredRequest.request_status
        approval_status = [string]$StoredRequest.approval_status
        approval_required = [bool]$StoredRequest.approval_required
        restricted_local_only = [bool]$StoredRequest.restricted_local_only
        execution_plan_id = [string]$StoredRequest.execution_plan_id
        approval_id = if ($StoredRequest.PSObject.Properties.Name -contains "approval_id") { [string]$StoredRequest.approval_id } else { "" }
        approval_path = if ($StoredRequest.PSObject.Properties.Name -contains "approval_path") { [string]$StoredRequest.approval_path } else { "" }
        request_path = [string]$StoredRequest.request_path
        created_at = if ($StoredRequest.PSObject.Properties.Name -contains "created_at") { [string]$StoredRequest.created_at } else { "" }
        updated_at = if ($StoredRequest.PSObject.Properties.Name -contains "updated_at") { [string]$StoredRequest.updated_at } else { "" }
    }
}

$Index.request_count = @($Index.requests).Count
$Index.draft_count = @($Index.requests | Where-Object { [string]$_.request_status -eq "draft" }).Count
$Index.pending_approval_count = @($Index.requests | Where-Object { [string]$_.request_status -eq "pending_approval" }).Count
$Index.approved_count = @($Index.requests | Where-Object { [string]$_.request_status -eq "approved" }).Count
$Index.rejected_count = @($Index.requests | Where-Object { [string]$_.request_status -eq "rejected" }).Count
$Index.cancelled_count = @($Index.requests | Where-Object { [string]$_.request_status -eq "cancelled" }).Count
$Index.completed_count = @($Index.requests | Where-Object { [string]$_.request_status -eq "completed" }).Count
$Index.approval_required_count = @($Index.requests | Where-Object { [bool]$_.approval_required }).Count
$Index.restricted_local_only_count = @($Index.requests | Where-Object { [bool]$_.restricted_local_only }).Count
$Index.latest_request = if ($Index.requests.Count -gt 0) { $Index.requests[0] } else { $null }
$Index.latest_pending_request = @($Index.requests | Where-Object { [string]$_.request_status -eq "pending_approval" } | Select-Object -First 1)[0]
$Index.latest_approved_request = @($Index.requests | Where-Object { [string]$_.request_status -eq "approved" } | Select-Object -First 1)[0]
$Index | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $IndexPath -Encoding UTF8

$Report = [pscustomobject]@{
    status = "pass"
    execution_request_id = $RequestId
    request_id = $RequestId
    request_type = [string]$RequestType
    capability = $Capability
    agent = $Agent
    provider = $Provider
    tool = [string]$ToolRecord.tool_id
    tool_display_name = [string]$ToolRecord.display_name
    execution_plan = $ExecutionPlan
    approval_status = [string]$ApprovalStatus
    approval_required = [bool]$ApprovalRequired
    request_status = [string]$RequestStatus
    request_path = $RequestPath
    approval_id = [string]$LinkedApprovalId
    approval_path = [string]$LinkedApprovalPath
    request = [pscustomobject]$Request
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 30
    return
}

Write-Host "[PDA EXECUTION REQUEST CREATED]"
Write-Host ("Request ID   : {0}" -f $Report.request_id)
Write-Host ("Capability   : {0}" -f $Report.capability)
Write-Host ("Tool         : {0}" -f $Report.tool_display_name)
Write-Host ("Status       : {0}" -f $Report.request_status)
Write-Host ("Approval     : {0}" -f $Report.approval_status)
