$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ScriptsToCheck = @(
    "Scripts\Submit-PDATask.ps1",
    "Scripts\New-PDATask.ps1",
    "Scripts\Submit-PDAFabricTask.ps1",
    "Scripts\New-PDAWorkflowTask.ps1",
    "Scripts\Approve-PDATask.ps1",
    "Scripts\Retry-PDADeadLetterTask.ps1",
    "Scripts\Invoke-PDAApprovalGate.ps1",
    "Scripts\Process-PDACommandStagedTasks.ps1",
    "Scripts\Process-PDAReporterStagedTasks.ps1",
    "Scripts\process-pda-queue.ps1",
    "Scripts\Start-PDAQueueWorker.ps1",
    "Scripts\dispatch-pda-command.ps1"
)

foreach ($Script in $ScriptsToCheck) {
    $Path = Join-Path $Root $Script
    if (-not (Test-Path $Path)) {
        throw "Missing audited script: $Path"
    }

    $Content = Get-Content $Path -Raw
    if ($Content -notmatch 'Resolve-PDATaskDispatchContext|Get-PDATaskWorkerEligibility') {
        throw "Ontology resolver missing from audited script: $Script"
    }
}

function Find-QueueTaskByMarker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Marker,

        [Parameter(Mandatory = $true)]
        [string]$Folder
    )

    Get-ChildItem -Path (Join-Path $Root $Folder) -Filter *.json -ErrorAction SilentlyContinue |
        Where-Object { (Get-Content $_.FullName -Raw) -match [regex]::Escape($Marker) } |
        Select-Object -First 1
}

Write-Host "[*] Testing pre-dispatch bypass coverage..."

$PlannerMarker = "pre-dispatch-planner-$([guid]::NewGuid().ToString())"
& pwsh -NoProfile -File (Join-Path $PSScriptRoot "Submit-PDATask.ps1") -Command /planner -Target $PlannerMarker -Category category_1 -Approved:$true
if ($LASTEXITCODE -ne 0) {
    throw "Submit-PDATask.ps1 planner path failed with exit code $LASTEXITCODE"
}

$PlannerTask = Find-QueueTaskByMarker -Marker $PlannerMarker -Folder "PDA-Tasks\pending"
if (-not $PlannerTask) {
    throw "Planner submit task was not found in PDA-Tasks\pending."
}

$PlannerJson = Get-Content $PlannerTask.FullName -Raw | ConvertFrom-Json
if ($PlannerJson.assigned_worker -ne "planner-worker") {
    throw "Planner submit task routed to unexpected worker: $($PlannerJson.assigned_worker)"
}

if ($PlannerJson.routing_surface -ne "local-only") {
    throw "Planner submit task did not stay local-only."
}

$UnknownCommandFailed = $false
try {
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot "Submit-PDATask.ps1") -Command /does-not-exist -Target "unknown-command-$([guid]::NewGuid().ToString())" -Category category_1 -Approved:$true 2>$null
    if ($LASTEXITCODE -ne 0) {
        $UnknownCommandFailed = $true
    }
}
catch {
    $UnknownCommandFailed = $true
}

if (-not $UnknownCommandFailed) {
    throw "Submit-PDATask.ps1 did not fail closed for unknown commands."
}

$WorkflowName = "Ontology Guard $([guid]::NewGuid().ToString())"
& pwsh -NoProfile -File (Join-Path $PSScriptRoot "New-PDAWorkflowTask.ps1") -WorkflowName $WorkflowName
if ($LASTEXITCODE -ne 0) {
    throw "New-PDAWorkflowTask.ps1 failed with exit code $LASTEXITCODE"
}

$WorkflowTask = Get-ChildItem -Path (Join-Path $Root "PDA-Tasks\pending") -Filter *.json -ErrorAction SilentlyContinue |
    Where-Object { (Get-Content $_.FullName -Raw) -match [regex]::Escape($WorkflowName) } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $WorkflowTask) {
    throw "Workflow submit task was not found in PDA-Tasks\pending."
}

$WorkflowJson = Get-Content $WorkflowTask.FullName -Raw | ConvertFrom-Json
if ($WorkflowJson.command -ne "/planner") {
    throw "Workflow task did not normalize to /planner."
}

if ($WorkflowJson.assigned_worker -ne "planner-worker") {
    throw "Workflow task routed to unexpected worker: $($WorkflowJson.assigned_worker)"
}

$FabricBlocked = $false
try {
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot "Submit-PDAFabricTask.ps1") -Category category_2 -DryRun 2>$null
    if ($LASTEXITCODE -ne 0) {
        $FabricBlocked = $true
    }
}
catch {
    $FabricBlocked = $true
}

if (-not $FabricBlocked) {
    throw "Submit-PDAFabricTask.ps1 did not fail closed for category_2."
}

$ApprovalLeaf = "pre-dispatch-approval-$([guid]::NewGuid().ToString()).json"
$ApprovalPath = Join-Path $Root "PDA-Tasks\approvals\pending\$ApprovalLeaf"
$ApprovalTask = [ordered]@{
    task_id         = [guid]::NewGuid().ToString()
    command         = "/planner"
    project         = "AI Ecosystem"
    classification  = "category_1"
    category        = "category_1"
    target          = "Approval path bypass coverage"
    message         = "Approval path bypass coverage"
    approved        = $true
    status          = "pending"
}

New-Item -ItemType Directory -Force -Path (Split-Path $ApprovalPath -Parent) | Out-Null
$ApprovalTask | ConvertTo-Json -Depth 10 | Set-Content -Path $ApprovalPath -Encoding UTF8

& pwsh -NoProfile -File (Join-Path $PSScriptRoot "Approve-PDATask.ps1") -TaskFile $ApprovalLeaf
if ($LASTEXITCODE -ne 0) {
    throw "Approve-PDATask.ps1 failed with exit code $LASTEXITCODE"
}

$ApprovedPending = Join-Path $Root "PDA-Tasks\pending\$ApprovalLeaf"
if (-not (Test-Path $ApprovedPending)) {
    throw "Approved task was not moved to PDA-Tasks\pending."
}

$ApprovedJson = Get-Content $ApprovedPending -Raw | ConvertFrom-Json
if ($ApprovedJson.assigned_worker -ne "planner-worker") {
    throw "Approved task routed to unexpected worker: $($ApprovedJson.assigned_worker)"
}

if ($ApprovedJson.routing_surface -ne "local-only") {
    throw "Approved task did not remain local-only."
}

Write-Host "[OK] Pre-dispatch bypass coverage tests passed."
