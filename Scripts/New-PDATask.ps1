param(
    [Parameter(Mandatory = $true)]
    [string]$Command,

    [string]$Project = "AI Tool Ecosystem",

    [ValidateSet("category_1", "category_2")]
    [string]$Classification = "category_1",

    [string]$RequestedOutput = "markdown",

    [string]$SourcePath = "",

    [string]$AssignedWorker = "planner-worker"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$QueueRoot = Join-Path $Root "PDA-Tasks"
$PendingPath = Join-Path $QueueRoot "pending"
$ApprovalGate = Join-Path $PSScriptRoot "Invoke-PDAApprovalGate.ps1"

. (Join-Path $PSScriptRoot "PDA_TaskOntology.ps1")

$DispatchContext = Resolve-PDATaskDispatchContext -Root $Root -Command $Command -Classification $Classification -Approved $true
if (-not [string]::IsNullOrWhiteSpace($AssignedWorker) -and $AssignedWorker -ne $DispatchContext.assigned_worker) {
    throw "AssignedWorker $AssignedWorker does not match ontology worker $($DispatchContext.assigned_worker) for $Command."
}

$TaskId = [guid]::NewGuid().ToString()
$Created = (Get-Date).ToUniversalTime().ToString("o")

# Deprecated legacy queue root:
# Tasks\queued is kept only for compatibility during migration.
# New task creation must write to PDA-Tasks\pending.
$LegacyQueueRoot = Join-Path $Root "Tasks"

$Task = [ordered]@{
    task_id           = $TaskId
    created           = $Created
    command           = $Command
    route             = $Command.TrimStart("/")
    project           = $Project
    classification    = $Classification
    status            = "queued"
    requested_output  = $RequestedOutput
    source_path       = $SourcePath
    assigned_worker   = $DispatchContext.assigned_worker
    routing_surface   = $DispatchContext.routing_surface
    task_type         = $DispatchContext.task_type
    intent            = $DispatchContext.intent
    requires_approval = $DispatchContext.requires_approval
    next_worker       = ""
    retry_count       = 0
}

New-Item -ItemType Directory -Force -Path $PendingPath | Out-Null

$OutPath = Join-Path $PendingPath "$TaskId.json"
$Task | ConvertTo-Json -Depth 10 | Set-Content -Path $OutPath -Encoding UTF8

if (Test-Path $ApprovalGate) {
    & pwsh -NoProfile -File $ApprovalGate -TaskPath $OutPath
    $ApprovalExit = $LASTEXITCODE

    if ($ApprovalExit -eq 2 -or $ApprovalExit -eq 3) {
        if (Test-Path $OutPath) {
            Remove-Item $OutPath -Force
        }
    }
    elseif ($ApprovalExit -ne 0) {
        throw "Approval gate failed unexpectedly with exit code $ApprovalExit"
    }
}

Write-Host "[OK] Created PDA task:"
Write-Host $OutPath
