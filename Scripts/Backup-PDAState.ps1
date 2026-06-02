$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupRoot = Join-Path $Root "PDA-Backups"
$BackupDir = Join-Path $BackupRoot "pda-state-$Timestamp"

Write-Host "[*] Creating PDA safe local backup..."
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

$Items = @(
    "Scripts",
    "PDA-Runtime",
    "n8n Workflow",
    "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Registry",
    "Obsidian Vault\02_Projects\AI Tool Ecosystem\Checkpoints",
    "Obsidian Vault\02_Projects\AI Tool Ecosystem\PDA Dashboard.md",
    ".gitignore",
    "README.md",
    "CHANGELOG.md"
)

foreach ($item in $Items) {
    $Source = Join-Path $Root $item
    if (Test-Path $Source) {
        $Dest = Join-Path $BackupDir $item
        $Parent = Split-Path $Dest -Parent
        New-Item -ItemType Directory -Force -Path $Parent | Out-Null
        Copy-Item $Source $Dest -Recurse -Force
        Write-Host "[OK] Backed up: $item"
    }
}

Write-Host "[OK] Backup created:"
Write-Host $BackupDir
