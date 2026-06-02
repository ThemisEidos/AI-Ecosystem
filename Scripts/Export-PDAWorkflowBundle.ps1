$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ExportRoot = Join-Path $Root "PDA-Backups\workflow-bundles"
$BundleDir = Join-Path $ExportRoot "pda-workflow-bundle-$Timestamp"

Write-Host "[*] Exporting PDA workflow bundle..."
New-Item -ItemType Directory -Force -Path $BundleDir | Out-Null

$Items = @(
    "n8n Workflow",
    "Scripts\PDA_WorkerRegistry.json",
    "Scripts\PDA_MultiAgentTask.schema.json",
    "Scripts\PDA_TaskRequest.schema.json",
    "Scripts\PDA_WorkerContract.schema.json",
    "Scripts\PDA_CategoryRouting.ps1",
    "PDA-Runtime\docker-compose.yml",
    "README.md",
    "CHANGELOG.md"
)

foreach ($item in $Items) {
    $Source = Join-Path $Root $item
    if (Test-Path $Source) {
        $Dest = Join-Path $BundleDir $item
        $Parent = Split-Path $Dest -Parent
        New-Item -ItemType Directory -Force -Path $Parent | Out-Null
        Copy-Item $Source $Dest -Recurse -Force
        Write-Host "[OK] Exported: $item"
    }
}

$Manifest = @{
    exported_at = (Get-Date).ToString("s")
    root        = $Root
    bundle      = $BundleDir
    purpose     = "PDA workflow restore bundle"
} | ConvertTo-Json -Depth 4

$Manifest | Set-Content (Join-Path $BundleDir "bundle-manifest.json") -Encoding UTF8

Write-Host "[OK] Bundle exported:"
Write-Host $BundleDir
