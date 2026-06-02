$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$FailedDir = Join-Path $Root "PDA-Tasks\failed"
$DeadDir = Join-Path $Root "PDA-Tasks\dead-letter"
New-Item -ItemType Directory -Force -Path $DeadDir | Out-Null

if (-not (Test-Path $FailedDir)) {
    Write-Host "[OK] No failed folder found."
    exit 0
}

$Files = Get-ChildItem $FailedDir -File -Filter *.json -ErrorAction SilentlyContinue

foreach ($file in $Files) {
    $dest = Join-Path $DeadDir $file.Name
    Move-Item $file.FullName $dest -Force
    Write-Host "[DEAD-LETTER] $($file.Name)"
}

Write-Host "[OK] Dead-letter sweep complete."
