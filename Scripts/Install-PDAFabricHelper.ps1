$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_Fabric.ps1")
$HomeDir = if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { $env:USERPROFILE } else { $env:HOME }

Write-Host "[*] Installing/checking Fabric..."

if (-not (Get-PDAFabricExecutablePath -Root $Root)) {
    iwr -useb https://raw.githubusercontent.com/danielmiessler/fabric/main/scripts/installer/install.ps1 | iex
    $LocalBin = Join-Path $HomeDir ".local/bin"
    if (Test-Path $LocalBin) {
        $env:PATH = "$LocalBin;$env:PATH"
    }
}

if (-not (Get-PDAFabricExecutablePath -Root $Root)) {
    throw "Fabric is still unavailable. Add %USERPROFILE%\.local\bin to PATH or open a new PowerShell terminal."
}

$FabricExe = Get-PDAFabricExecutablePath -Root $Root
& $FabricExe --version

$FabricPatternsRoot = Join-Path $HomeDir ".config/fabric/patterns"
New-Item -ItemType Directory -Force -Path $FabricPatternsRoot | Out-Null

foreach ($PatternDir in @("Research", "Reporting", "Review", "Security")) {
    $SourceDir = Join-Path (Join-Path $Root "PDA-Fabric") $PatternDir
    $TargetGroupDir = Join-Path $FabricPatternsRoot $PatternDir
    if (Test-Path $SourceDir) {
        New-Item -ItemType Directory -Force -Path $TargetGroupDir | Out-Null
        $PatternFiles = Get-ChildItem -Path $SourceDir -File -Filter *.md -ErrorAction SilentlyContinue
        foreach ($PatternFile in $PatternFiles) {
            $PatternName = [System.IO.Path]::GetFileNameWithoutExtension($PatternFile.Name)
            $TargetPatternDir = Join-Path $TargetGroupDir $PatternName
            New-Item -ItemType Directory -Force -Path $TargetPatternDir | Out-Null
            Copy-Item -Path $PatternFile.FullName -Destination (Join-Path $TargetPatternDir "system.md") -Force
        }
    }
}

Write-Host "[OK] Synced PDA Fabric patterns to $FabricPatternsRoot"

Write-Host "[NEXT] Run:"
Write-Host "fabric --setup"
Write-Host "Then configure providers/models."
Write-Host "[OK] Fabric helper check complete."
