$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$DeadDir = Join-Path $Root "PDA-Tasks\dead-letter"

$count = 0
if (Test-Path $DeadDir) {
    $count = @(Get-ChildItem $DeadDir -File -Filter *.json -ErrorAction SilentlyContinue).Count
}

Write-Host "[PDA DEAD-LETTER STATUS]"
Write-Host "dead-letter : $count"

if ($count -gt 0) {
    Get-ChildItem $DeadDir -File -Filter *.json |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 10 Name, LastWriteTime
}
