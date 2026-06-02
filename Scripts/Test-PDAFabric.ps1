$ErrorActionPreference = "Stop"

Write-Host "[*] Testing Fabric availability..."

if (-not (Get-Command fabric -ErrorAction SilentlyContinue)) {
    throw "Fabric is not installed or not in PATH."
}

fabric --version

Write-Host "[*] Checking available Fabric patterns..."
fabric --listpatterns | Select-Object -First 20

Write-Host "[OK] Fabric is available."
