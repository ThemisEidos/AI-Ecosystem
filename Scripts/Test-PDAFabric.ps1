$ErrorActionPreference = "Stop"

Write-Host "[*] Testing Fabric availability..."

 $Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_Fabric.ps1")

$FabricExe = Get-PDAFabricExecutablePath -Root $Root
if ([string]::IsNullOrWhiteSpace($FabricExe)) {
    throw "Fabric is not installed or not in PATH."
}

& $FabricExe --version

Write-Host "[*] Checking available Fabric patterns..."
& $FabricExe --listpatterns | Select-Object -First 20

Write-Host "[OK] Fabric is available."
