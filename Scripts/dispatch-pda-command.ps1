param(
    [Parameter(Mandatory = $true)]
    [string]$TaskFile
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $TaskFile)) {
    throw "Task file not found."
}

$Root = Split-Path $PSScriptRoot -Parent
$Runner = Join-Path $Root "Scripts\Invoke-PDAWorker.ps1"

. (Join-Path $Root "Scripts\PDA_TaskOntology.ps1")

$Task = Get-Content $TaskFile -Raw | ConvertFrom-Json
$Command = if ($Task.PSObject.Properties['command']) { [string]$Task.command } else { "" }
$Classification = if ($Task.PSObject.Properties['classification'] -and -not [string]::IsNullOrWhiteSpace([string]$Task.classification)) {
    [string]$Task.classification
}
elseif ($Task.PSObject.Properties['category'] -and -not [string]::IsNullOrWhiteSpace([string]$Task.category)) {
    [string]$Task.category
}
else {
    "category_1"
}
$Approved = if ($Task.PSObject.Properties['approved']) { [bool]$Task.approved } else { $true }

$DispatchContext = Resolve-PDATaskDispatchContext -Root $Root -Task $Task -Command $Command -Classification $Classification -Approved $Approved

if (-not $Task.PSObject.Properties['task_id'] -or [string]::IsNullOrWhiteSpace([string]$Task.task_id)) {
    $Task | Add-Member -NotePropertyName task_id -NotePropertyValue ([guid]::NewGuid().ToString()) -Force
}

if (-not $Task.PSObject.Properties['assigned_worker'] -or [string]::IsNullOrWhiteSpace([string]$Task.assigned_worker)) {
    $Task | Add-Member -NotePropertyName assigned_worker -NotePropertyValue $DispatchContext.assigned_worker -Force
}
elseif ([string]$Task.assigned_worker -ne $DispatchContext.assigned_worker) {
    throw "Assigned worker mismatch for $TaskFile. Task has $($Task.assigned_worker) but ontology resolved $($DispatchContext.assigned_worker)."
}

if (-not $Task.PSObject.Properties['routing_surface'] -or [string]::IsNullOrWhiteSpace([string]$Task.routing_surface)) {
    $Task | Add-Member -NotePropertyName routing_surface -NotePropertyValue $DispatchContext.routing_surface -Force
}
elseif ([string]$Task.routing_surface -ne $DispatchContext.routing_surface) {
    throw "Routing surface mismatch for $TaskFile. Task has $($Task.routing_surface) but ontology resolved $($DispatchContext.routing_surface)."
}

$Task | Add-Member -NotePropertyName route -NotePropertyValue $Command.TrimStart("/") -Force
$Task | Add-Member -NotePropertyName status -NotePropertyValue "queued" -Force
$Task | Add-Member -NotePropertyName task_type -NotePropertyValue $DispatchContext.task_type -Force
$Task | Add-Member -NotePropertyName intent -NotePropertyValue $DispatchContext.intent -Force

$Task | ConvertTo-Json -Depth 20 | Set-Content -Path $TaskFile -Encoding UTF8

Write-Host "[OK] Ontology-dispatched task:"
Write-Host "Worker: $($DispatchContext.assigned_worker)"
Write-Host "Surface: $($DispatchContext.routing_surface)"

& pwsh -NoProfile -File $Runner -TaskPath $TaskFile
if ($LASTEXITCODE -ne 0) {
    throw "Worker dispatch failed with exit code $LASTEXITCODE"
}
