$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$RunId = Get-Date -Format "yyyyMMdd-HHmmssfff"
$TempRoot = Join-Path $Root "PDA-Tasks\temp\ontology-dispatch-tests\$RunId"
$StagingRoot = Join-Path $TempRoot "n8n-router"
$SourceRoot = Join-Path $TempRoot "sources"
$Processor = Join-Path $PSScriptRoot "Process-PDACommandStagedTasks.ps1"

. (Join-Path $PSScriptRoot "PDA_TaskOntology.ps1")

New-Item -ItemType Directory -Force -Path $StagingRoot, $SourceRoot | Out-Null

function New-DispatchTask {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string]$Route,

        [Parameter(Mandatory = $true)]
        [string]$Classification,

        [Parameter(Mandatory = $true)]
        [bool]$Approved,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $TaskId = [guid]::NewGuid().ToString()
    $TaskPath = Join-Path $StagingRoot "$Name.json"
    $SourcePath = Join-Path $SourceRoot "$Name-source.md"

    @"
# Dispatch Test Source

Task: $Name
Command: $Command
"@ | Set-Content -Path $SourcePath -Encoding UTF8

    $Task = [ordered]@{
        task_id         = $TaskId
        command         = $Command
        route           = $Route
        message         = $Message
        target          = $Message
        project         = "AI Ecosystem"
        classification  = $Classification
        requested_output = "markdown"
        source          = "test"
        source_path     = $SourcePath
        approved        = $Approved
        received_at     = (Get-Date).ToUniversalTime().ToString("o")
    }

    $Task | ConvertTo-Json -Depth 10 | Set-Content -Path $TaskPath -Encoding UTF8

    return [pscustomobject]@{
        task_id = $TaskId
        path    = $TaskPath
        source  = $SourcePath
        name    = $Name
        route   = $Route
        command = $Command
    }
}

function Invoke-DispatchProcessor {
    & pwsh -NoProfile -File $Processor -StagingRoot $StagingRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Process-PDACommandStagedTasks.ps1 failed with exit code $LASTEXITCODE"
    }
}

Write-Host "[*] Testing ontology-driven staged dispatch..."

$PlannerTask = New-DispatchTask -Name "planner-category1" -Command "/planner" -Route "planner" -Classification "category_1" -Approved $true -Message "Category 1 planner dispatch test"
Invoke-DispatchProcessor

$PlannerPending = Join-Path $Root "PDA-Tasks\pending\$($PlannerTask.task_id).json"
if (-not (Test-Path $PlannerPending)) {
    throw "Planner task did not reach pending queue: $PlannerPending"
}

$PlannerQueued = Get-Content -Path $PlannerPending -Raw | ConvertFrom-Json
if ($PlannerQueued.assigned_worker -ne "planner-worker") {
    throw "Planner task routed to unexpected worker: $($PlannerQueued.assigned_worker)"
}

if ($PlannerQueued.routing_surface -ne "local-only") {
    throw "Planner task did not stay local-only."
}

$ReviewTask = New-DispatchTask -Name "review-category2" -Command "/review" -Route "review" -Classification "category_2" -Approved $true -Message "Category 2 review dispatch test"
Invoke-DispatchProcessor

$ReviewApprovalPending = Join-Path $Root "PDA-Tasks\approvals\pending\$($ReviewTask.task_id).json"
if (-not (Test-Path $ReviewApprovalPending)) {
    throw "Category 2 review task did not reach approval-pending queue: $ReviewApprovalPending"
}

$ReviewQueued = Get-Content -Path $ReviewApprovalPending -Raw | ConvertFrom-Json
if ($ReviewQueued.assigned_worker -ne "review-worker") {
    throw "Category 2 review task routed to unexpected worker: $($ReviewQueued.assigned_worker)"
}

if ($ReviewQueued.routing_surface -ne "local-only") {
    throw "Category 2 review task did not stay local-only."
}

$FabricTask = New-DispatchTask -Name "fabric-category2" -Command "/fabric" -Route "fabric" -Classification "category_2" -Approved $true -Message "Blocked Category 2 fabric dispatch test"
Invoke-DispatchProcessor

$FabricFailed = Join-Path $Root "PDA-Tasks\staging\failed\$(Split-Path $FabricTask.path -Leaf)"
if (-not (Test-Path $FabricFailed)) {
    throw "Blocked Category 2 fabric task did not fail closed: $FabricFailed"
}

if (Test-Path (Join-Path $Root "PDA-Tasks\pending\$($FabricTask.task_id).json")) {
    throw "Blocked Category 2 fabric task was incorrectly dispatched to pending."
}

$UnknownTask = New-DispatchTask -Name "unknown-command" -Command "/does-not-exist" -Route "does-not-exist" -Classification "category_1" -Approved $true -Message "Unknown command dispatch test"
Invoke-DispatchProcessor

$UnknownFailed = Join-Path $Root "PDA-Tasks\staging\failed\$(Split-Path $UnknownTask.path -Leaf)"
if (-not (Test-Path $UnknownFailed)) {
    throw "Unknown command did not fail closed: $UnknownFailed"
}

if (Test-Path (Join-Path $Root "PDA-Tasks\pending\$($UnknownTask.task_id).json")) {
    throw "Unknown command was incorrectly dispatched to pending."
}

Write-Host "[OK] Ontology dispatch tests passed."
Write-Host ("Planner queued      : {0}" -f $PlannerQueued.assigned_worker)
Write-Host ("Review approval file: {0}" -f $ReviewApprovalPending)
Write-Host ("Fabric failed file  : {0}" -f $FabricFailed)
Write-Host ("Unknown failed file : {0}" -f $UnknownFailed)
