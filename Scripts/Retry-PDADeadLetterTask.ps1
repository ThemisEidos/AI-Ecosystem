param(
    [Parameter(Mandatory=$true)]
    [string]$TaskFile
)

$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$DeadDir = Join-Path $Root "PDA-Tasks\dead-letter"
$PendingDir = Join-Path $Root "PDA-Tasks\pending"
New-Item -ItemType Directory -Force -Path $PendingDir | Out-Null

$Source = if (Test-Path $TaskFile) { $TaskFile } else { Join-Path $DeadDir $TaskFile }

if (-not (Test-Path $Source)) {
    throw "Dead-letter task not found: $TaskFile"
}

$Task = Get-Content $Source -Raw | ConvertFrom-Json
$RetryCount = if ($Task.retry_count -ne $null) { [int]$Task.retry_count + 1 } else { 1 }

$Task | Add-Member -NotePropertyName retry_count -NotePropertyValue $RetryCount -Force
$Task | Add-Member -NotePropertyName status -NotePropertyValue "pending" -Force
$Task | Add-Member -NotePropertyName retried_at -NotePropertyValue (Get-Date).ToString("s") -Force

$Dest = Join-Path $PendingDir (Split-Path $Source -Leaf)
$Task | ConvertTo-Json -Depth 12 | Set-Content $Dest -Encoding UTF8
Remove-Item $Source -Force

Write-Host "[OK] Retried task moved to pending:"
Write-Host $Dest
