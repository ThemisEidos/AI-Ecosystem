$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"

$CanonicalResults = Join-Path $Root "PDA-Tasks\results"

# Deprecated legacy result store:
# Tasks\results is retained as a read-only fallback during migration.
$LegacyResults = Join-Path $Root "Tasks\results"

if (Test-Path $CanonicalResults) {
    $Results = $CanonicalResults
} elseif (Test-Path $LegacyResults) {
    $Results = $LegacyResults
} else {
    $Results = $CanonicalResults
}

$Latest = Get-ChildItem $Results -Filter *.json |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $Latest) {
    Write-Host "[INFO] No result files found."
    exit
}

Write-Host "=== LATEST RESULT ==="
Write-Host ""

$Json = Get-Content $Latest.FullName -Raw | ConvertFrom-Json

$Json | ConvertTo-Json -Depth 20

Write-Host ""
Write-Host "Result File:"
Write-Host $Latest.FullName

if ($Json.saved_path) {
    Write-Host ""
    Write-Host "Markdown Output:"
    Write-Host $Json.saved_path
}
