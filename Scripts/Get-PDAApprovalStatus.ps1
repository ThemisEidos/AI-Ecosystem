$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$ApprovalRoot = Join-Path $Root "PDA-Tasks\approvals"

$Folders = @{
    pending = Join-Path $ApprovalRoot "pending"
    approved = Join-Path $ApprovalRoot "approved"
    rejected = Join-Path $ApprovalRoot "rejected"
}

Write-Host "[PDA APPROVAL STATUS]"

foreach ($key in $Folders.Keys) {
    $path = $Folders[$key]
    $count = 0
    if (Test-Path $path) {
        $count = @(Get-ChildItem $path -File -Filter *.json -ErrorAction SilentlyContinue).Count
    }
    Write-Host "$key : $count"
}

Write-Host ""
Write-Host "[Pending approval tasks]"
if (Test-Path $Folders.pending) {
    Get-ChildItem $Folders.pending -File -Filter *.json -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 10 Name, LastWriteTime |
        Format-Table -AutoSize
}
