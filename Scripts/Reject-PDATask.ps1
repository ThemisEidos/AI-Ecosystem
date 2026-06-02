param(
    [Parameter(Mandatory=$true)]
    [string]$TaskFile,

    [Parameter(Mandatory=$false)]
    [string]$Reason = "Rejected by operator."
)

$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$ApprovalRoot = Join-Path $Root "PDA-Tasks\approvals"
$PendingApprovalDir = Join-Path $ApprovalRoot "pending"
$RejectedDir = Join-Path $ApprovalRoot "rejected"

New-Item -ItemType Directory -Force -Path $RejectedDir | Out-Null

$Source = if (Test-Path $TaskFile) { $TaskFile } else { Join-Path $PendingApprovalDir $TaskFile }

if (-not (Test-Path $Source)) {
    throw "Approval task not found: $TaskFile"
}

$Task = Get-Content $Source -Raw | ConvertFrom-Json
$Task | Add-Member -NotePropertyName approved -NotePropertyValue $false -Force
$Task | Add-Member -NotePropertyName approval_status -NotePropertyValue "rejected" -Force
$Task | Add-Member -NotePropertyName rejection_reason -NotePropertyValue $Reason -Force
$Task | Add-Member -NotePropertyName rejected_at -NotePropertyValue (Get-Date).ToString("s") -Force

$Dest = Join-Path $RejectedDir (Split-Path $Source -Leaf)
$Task | ConvertTo-Json -Depth 12 | Set-Content $Dest -Encoding UTF8
Remove-Item $Source -Force

Write-Host "[REJECTED] Task moved to rejected approvals:"
Write-Host $Dest
