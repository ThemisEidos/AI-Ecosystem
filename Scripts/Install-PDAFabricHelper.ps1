$ErrorActionPreference = "Stop"

Write-Host "[*] Installing/checking Fabric..."

if (-not (Get-Command fabric -ErrorAction SilentlyContinue)) {
    iwr -useb https://raw.githubusercontent.com/danielmiessler/fabric/main/scripts/installer/install.ps1 | iex
    $LocalBin = Join-Path $env:USERPROFILE ".local\bin"
    if (Test-Path $LocalBin) {
        $env:PATH = "$LocalBin;$env:PATH"
    }
}

if (-not (Get-Command fabric -ErrorAction SilentlyContinue)) {
    throw "Fabric is still unavailable. Add %USERPROFILE%\.local\bin to PATH or open a new PowerShell terminal."
}

fabric --version

Write-Host "[NEXT] Run:"
Write-Host "fabric --setup"
Write-Host "Then configure providers/models."
Write-Host "[OK] Fabric helper check complete."
