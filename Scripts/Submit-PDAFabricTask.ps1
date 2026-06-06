param(
    [Parameter(Mandatory = $false)]
    [string]$Message = "PDA Fabric dry-run test",

    [Parameter(Mandatory = $false)]
    [string]$SourcePath = "",

    [Parameter(Mandatory = $false)]
    [string]$Pattern = "summarize",

    [Parameter(Mandatory = $false)]
    [ValidateSet("category_1", "category_2")]
    [string]$Category = "category_1",

    [Parameter(Mandatory = $false)]
    [string]$Model = "",

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$QueueRoot = Join-Path $Root "PDA-Tasks"
$PendingDir = Join-Path $QueueRoot "pending"
$ApprovalGate = Join-Path $PSScriptRoot "Invoke-PDAApprovalGate.ps1"

. (Join-Path $PSScriptRoot "PDA_TaskOntology.ps1")

$DispatchContext = Resolve-PDATaskDispatchContext -Root $Root -Command "/fabric" -Classification $Category -Approved $true

New-Item -ItemType Directory -Force -Path $PendingDir | Out-Null

$TaskId = [guid]::NewGuid().ToString()
$InputMode = if ($SourcePath) { "file" } else { "message-only-test" }
$TaskPath = Join-Path $PendingDir "$TaskId-fabric-task.json"

$Task = @{
    task_id           = $TaskId
    command           = "/fabric"
    route             = "fabric"
    assigned_worker   = $DispatchContext.assigned_worker
    worker            = $DispatchContext.assigned_worker
    routing_surface   = $DispatchContext.routing_surface
    pattern           = $Pattern
    message           = $Message
    source_path       = $SourcePath
    category          = $Category
    classification    = $Category
    model             = $Model
    input_mode        = $InputMode
    dry_run           = [bool]$DryRun
    approved          = $true
    status            = "pending"
    created_at        = (Get-Date).ToString("s")
    task_type         = $DispatchContext.task_type
    intent            = $DispatchContext.intent
    requires_approval = $DispatchContext.requires_approval
}

$Task | ConvertTo-Json -Depth 8 | Set-Content $TaskPath -Encoding UTF8

if (Test-Path $ApprovalGate) {
    & pwsh -NoProfile -File $ApprovalGate -TaskPath $TaskPath
    $ApprovalExit = $LASTEXITCODE

    if ($ApprovalExit -eq 2 -or $ApprovalExit -eq 3) {
        if (Test-Path $TaskPath) {
            Remove-Item $TaskPath -Force
        }
    }
    elseif ($ApprovalExit -ne 0) {
        throw "Approval gate failed unexpectedly with exit code $ApprovalExit"
    }
}

Write-Host "[OK] Fabric task submitted:"
Write-Host $TaskPath
Write-Host "[INFO] Task ID: $TaskId"
