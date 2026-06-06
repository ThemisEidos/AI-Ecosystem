$ProjectRoot = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"
$RuntimeRoot = Join-Path $ProjectRoot "PDA-Runtime"
$ProfilePath = $PROFILE
$ProfileDir = Split-Path -Parent $ProfilePath

$Folders = @(
    $RuntimeRoot,
    (Join-Path $RuntimeRoot "configs"),
    (Join-Path $RuntimeRoot "data"),
    (Join-Path $RuntimeRoot "logs")
)

foreach ($Folder in $Folders) {
    if (-not (Test-Path -LiteralPath $Folder)) {
        New-Item -ItemType Directory -Path $Folder -Force | Out-Null
    }
}

if (-not (Test-Path -LiteralPath $ProfileDir)) {
    New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $ProfilePath)) {
    New-Item -ItemType File -Path $ProfilePath -Force | Out-Null
}

$ComposeCandidates = @(@(
    (Join-Path $RuntimeRoot "docker-compose.yml"),
    (Join-Path $ProjectRoot "docker-compose.yml"),
    (Join-Path $ProjectRoot "compose.yml")
) | Where-Object { Test-Path -LiteralPath $_ })

if ($ComposeCandidates.Count -eq 0) {
    Write-Host "[ERROR] No compose file found in expected locations." -ForegroundColor Red
    exit 1
}

$ProfileStart = "# >>> AI Ecosystem Commands >>>"
$ProfileEnd = "# <<< AI Ecosystem Commands <<<"
$ProfileBlock = @"
$ProfileStart
function aiec {
    Set-Location "$ProjectRoot"
}

function aiec-start {
    pwsh -NoProfile -ExecutionPolicy Bypass -File "$RuntimeRoot\launch-pda.ps1" @args
}

function pda-go {
    pwsh -NoProfile -ExecutionPolicy Bypass -File "$ProjectRoot\Scripts\Start-PDABuildRunner.ps1" @args
}

function aiec-status {
    pwsh -NoProfile -ExecutionPolicy Bypass -File "$RuntimeRoot\status-pda.ps1" @args
}

function pda-dashboard {
    pwsh -NoProfile -ExecutionPolicy Bypass -File "$RuntimeRoot\dashboard-pda.ps1" @args
}

function pda-console {
    pda-dashboard @args
}

function pda {
    aiec-start @args
}

function pda-status {
    aiec-status @args
}

function pdadown {
    pwsh -NoProfile -ExecutionPolicy Bypass -File "$RuntimeRoot\stop-pda.ps1" @args
}

function pdaroot {
    Set-Location "$RuntimeRoot"
}
$ProfileEnd
"@

$ProfileContent = Get-Content -Path $ProfilePath -Raw -ErrorAction SilentlyContinue
if (-not $ProfileContent) {
    $ProfileContent = ""
}

$Pattern = "(?s)$([regex]::Escape($ProfileStart)).*?$([regex]::Escape($ProfileEnd))"
if ($ProfileContent -match $Pattern) {
    $UpdatedProfile = [regex]::Replace($ProfileContent, $Pattern, $ProfileBlock.Trim())
}
else {
    $Separator = if ([string]::IsNullOrWhiteSpace($ProfileContent)) { "" } else { "`r`n`r`n" }
    $UpdatedProfile = $ProfileContent.TrimEnd() + $Separator + $ProfileBlock.Trim() + "`r`n"
}

Set-Content -Path $ProfilePath -Value $UpdatedProfile -Encoding UTF8

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "    AI Ecosystem Profile Commands Ready" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[OK] Profile updated: $ProfilePath" -ForegroundColor Green
Write-Host "[OK] Compose file: $($ComposeCandidates[0])" -ForegroundColor Green
Write-Host ""
Write-Host "Commands:" -ForegroundColor Cyan
Write-Host "  aiec         - jump to the repo root"
Write-Host "  aiec-start   - start Docker Desktop if needed, then start and verify the stack"
Write-Host "  pda-go       - start the PDA Build Runner on demand"
Write-Host "  aiec-status  - stack status and troubleshooting"
Write-Host "  pda-dashboard - refresh and open the PDA Operator Console note"
Write-Host "  pda-console  - compatibility alias for pda-dashboard"
Write-Host "  pda          - compatibility wrapper for aiec-start"
Write-Host "  pda-go       - compatibility wrapper for the Build Runner"
Write-Host "  pda-status   - compatibility wrapper for aiec-status"
Write-Host "  pdadown      - stop the compose stack"
Write-Host ""
Write-Host "Reload the profile with:" -ForegroundColor Yellow
Write-Host ". `$PROFILE"
