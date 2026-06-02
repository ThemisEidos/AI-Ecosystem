param(
    [Parameter(Mandatory=$true)]
    [string]$TaskFile
)

$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$ApprovalRoot = Join-Path $Root "PDA-Tasks\approvals"
$PendingApprovalDir = Join-Path $ApprovalRoot "pending"
$ApprovedDir = Join-Path $ApprovalRoot "approved"
$PendingQueueDir = Join-Path $Root "PDA-Tasks\pending"

New-Item -ItemType Directory -Force -Path $ApprovedDir | Out-Null
New-Item -ItemType Directory -Force -Path $PendingQueueDir | Out-Null

$Source = if (Test-Path $TaskFile) { $TaskFile } else { Join-Path $PendingApprovalDir $TaskFile }

if (-not (Test-Path $Source)) {
    throw "Approval task not found: $TaskFile"
}

$Task = Get-Content $Source -Raw | ConvertFrom-Json
$Task | Add-Member -NotePropertyName approved -NotePropertyValue $true -Force
$Task | Add-Member -NotePropertyName approval_status -NotePropertyValue "approved" -Force
$Task | Add-Member -NotePropertyName approved_at -NotePropertyValue (Get-Date).ToString("s") -Force
$Task | Add-Member -NotePropertyName status -NotePropertyValue "pending" -Force

$FileName = Split-Path $Source -Leaf
$ApprovedCopy = Join-Path $ApprovedDir $FileName
$QueueDest = Join-Path $PendingQueueDir $FileName

$Task | ConvertTo-Json -Depth 12 | Set-Content $ApprovedCopy -Encoding UTF8
$Task | ConvertTo-Json -Depth 12 | Set-Content $QueueDest -Encoding UTF8
Remove-Item $Source -Force

Write-Host "[APPROVED] Task moved to pending queue:"
Write-Host $QueueDest
