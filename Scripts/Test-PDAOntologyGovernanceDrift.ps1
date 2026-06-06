$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Scanner = Join-Path $PSScriptRoot "Test-PDAOntologyGovernance.ps1"
$TempRoot = Join-Path $Root "PDA-Tasks\temp\ontology-governance-drift"
$TempScriptRoot = Join-Path $TempRoot "Scripts"
$SyntheticScript = Join-Path $TempScriptRoot "Test-PDAUnauthorizedWriter.ps1"

New-Item -ItemType Directory -Force -Path $TempScriptRoot | Out-Null

Write-Host "[*] Testing ontology governance drift detection..."

$Baseline = & pwsh -NoProfile -File $Scanner -NoThrow -AsJson
$BaselineReport = $Baseline | ConvertFrom-Json
if ($BaselineReport.status -ne "pass") {
    throw "Baseline governance scan did not pass."
}

@"
param()

`$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"
`$Task = @{
    task_id = [guid]::NewGuid().ToString()
    command = "/planner"
    classification = "category_1"
}

`$Task | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path `$Root "PDA-Tasks\pending\synthetic-governance-writer.json") -Encoding UTF8
"@ | Set-Content -Path $SyntheticScript -Encoding UTF8

$DriftDetected = $false
& pwsh -NoProfile -File $Scanner -AdditionalScriptRoots $TempScriptRoot 2>$null
if ($LASTEXITCODE -ne 0) {
    $DriftDetected = $true
}

if (-not $DriftDetected) {
    throw "Synthetic unauthorized writer was not detected."
}

Write-Host "[OK] Governance drift detection tests passed."
