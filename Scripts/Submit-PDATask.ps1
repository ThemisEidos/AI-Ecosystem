param(
    [Parameter(Mandatory = $true)]
    [string]$Command,

    [Parameter(Mandatory = $true)]
    [string]$Target,

    [string]$Project = "AI Ecosystem",

    [string]$Category = "category_1",

    [bool]$Approved = $true
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$QueueRoot = Join-Path $Root "PDA-Tasks"
$PendingPath = Join-Path $QueueRoot "pending"
$ApprovalGate = Join-Path $PSScriptRoot "Invoke-PDAApprovalGate.ps1"

. (Join-Path $PSScriptRoot "PDA_TaskOntology.ps1")

New-Item -ItemType Directory -Force -Path $PendingPath | Out-Null

$DispatchContext = Resolve-PDATaskDispatchContext -Root $Root -Command $Command -Classification $Category -Approved $true
$TaskId = [guid]::NewGuid().ToString()
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$SafeCommand = $Command.Replace("/", "").Replace("\", "").Replace(" ", "-")
$TaskFile = Join-Path $PendingPath "$Timestamp-$SafeCommand.json"

$Task = [ordered]@{
    task_id          = $TaskId
    created          = (Get-Date).ToUniversalTime().ToString("o")
    command          = $Command
    route            = $Command.TrimStart("/")
    project          = $Project
    target           = $Target
    category         = $Category
    classification   = $Category
    approved         = $Approved
    status           = "queued"
    assigned_worker  = $DispatchContext.assigned_worker
    routing_surface  = $DispatchContext.routing_surface
    task_type        = $DispatchContext.task_type
    intent           = $DispatchContext.intent
    requires_approval = $DispatchContext.requires_approval
    next_worker      = ""
    retry_count      = 0
}

$Task | ConvertTo-Json -Depth 12 | Set-Content -Path $TaskFile -Encoding UTF8

if (Test-Path $ApprovalGate) {
    & pwsh -NoProfile -File $ApprovalGate -TaskPath $TaskFile
    $ApprovalExit = $LASTEXITCODE

    if ($ApprovalExit -eq 2 -or $ApprovalExit -eq 3) {
        if (Test-Path $TaskFile) {
            Remove-Item $TaskFile -Force
        }
    }
    elseif ($ApprovalExit -ne 0) {
        throw "Approval gate failed unexpectedly with exit code $ApprovalExit"
    }
}

Write-Host ""
Write-Host "PDA task submitted:"
Write-Host $TaskFile
