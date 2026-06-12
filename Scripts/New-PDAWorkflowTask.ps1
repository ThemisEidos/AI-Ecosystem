param(
    [Parameter(Mandatory = $true)]
    [string]$WorkflowName
)

$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$QueueRoot = Join-Path $Root "PDA-Tasks"
$PendingPath = Join-Path $QueueRoot "pending"
$ApprovalGate = Join-Path $PSScriptRoot "Invoke-PDAApprovalGate.ps1"

. (Join-Path $PSScriptRoot "PDA_TaskOntology.ps1")

$Command = "/planner"
$DispatchContext = Resolve-PDATaskDispatchContext -Root $Root -Command $Command -Classification "category_1" -Approved $true
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$TaskId = [guid]::NewGuid().ToString()
$TaskPath = Join-Path $PendingPath "$Timestamp-workflow-builder.json"

$Task = [ordered]@{
    task_id           = $TaskId
    created           = (Get-Date).ToUniversalTime().ToString("o")
    command           = $Command
    route             = "planner"
    project           = "AI Ecosystem"
    target            = "Design and generate a new PDA workflow called: $WorkflowName"
    category          = "category_1"
    classification    = "category_1"
    approved          = $true
    status            = "queued"
    assigned_worker   = $DispatchContext.assigned_worker
    routing_surface   = $DispatchContext.routing_surface
    task_type         = $DispatchContext.task_type
    intent            = $DispatchContext.intent
    requires_approval = $DispatchContext.requires_approval
    next_worker       = ""
    retry_count       = 0
}

New-Item -ItemType Directory -Force -Path $PendingPath | Out-Null
$Task | ConvertTo-Json -Depth 10 | Set-Content $TaskPath -Encoding UTF8

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

Write-Host ""
Write-Host "Workflow generation task created:"
Write-Host $TaskPath
