param(
    [Parameter(Mandatory=$true)]
    [string]$TaskFile
)

$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$OntologyScript = Join-Path $PSScriptRoot "PDA_TaskOntology.ps1"
$DeadDir = Join-Path $Root "PDA-Tasks\dead-letter"
$PendingDir = Join-Path $Root "PDA-Tasks\pending"
New-Item -ItemType Directory -Force -Path $PendingDir | Out-Null

. $OntologyScript

$Source = if (Test-Path $TaskFile) { $TaskFile } else { Join-Path $DeadDir $TaskFile }

if (-not (Test-Path $Source)) {
    throw "Dead-letter task not found: $TaskFile"
}

$Task = Get-Content $Source -Raw | ConvertFrom-Json
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
$Task | Add-Member -NotePropertyName assigned_worker -NotePropertyValue $DispatchContext.assigned_worker -Force
$Task | Add-Member -NotePropertyName routing_surface -NotePropertyValue $DispatchContext.routing_surface -Force
$Task | Add-Member -NotePropertyName task_type -NotePropertyValue $DispatchContext.task_type -Force
$Task | Add-Member -NotePropertyName intent -NotePropertyValue $DispatchContext.intent -Force
$Task | Add-Member -NotePropertyName route -NotePropertyValue $Command.TrimStart("/") -Force
$Task | Add-Member -NotePropertyName status -NotePropertyValue "pending" -Force

$RetryCount = if ($Task.retry_count -ne $null) { [int]$Task.retry_count + 1 } else { 1 }

$Task | Add-Member -NotePropertyName retry_count -NotePropertyValue $RetryCount -Force
$Task | Add-Member -NotePropertyName retried_at -NotePropertyValue (Get-Date).ToString("s") -Force

$Dest = Join-Path $PendingDir (Split-Path $Source -Leaf)
$Task | ConvertTo-Json -Depth 12 | Set-Content $Dest -Encoding UTF8
Remove-Item $Source -Force

Write-Host "[OK] Retried task moved to pending:"
Write-Host $Dest
