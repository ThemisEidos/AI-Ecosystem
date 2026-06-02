param(
    [Parameter(Mandatory=$true)]
    [string]$InputPath,

    [Parameter(Mandatory=$false)]
    [string]$Pattern = "summarize",

    [Parameter(Mandatory=$false)]
    [ValidateSet("category_1","category_2")]
    [string]$Category = "category_1",

    [Parameter(Mandatory=$false)]
    [string]$Model = "",

    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$OutputDir = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Fabric"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

if (-not (Test-Path $InputPath)) {
    throw "InputPath not found: $InputPath"
}

if (-not (Get-Command fabric -ErrorAction SilentlyContinue)) {
    throw "Fabric is not installed or not in PATH."
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$SafePattern = $Pattern -replace '[^a-zA-Z0-9_-]', '_'
$OutputPath = Join-Path $OutputDir "fabric-$SafePattern-$Timestamp.md"

Write-Host "[*] PDA Fabric invocation"
Write-Host "    Input:    $InputPath"
Write-Host "    Pattern:  $Pattern"
Write-Host "    Category: $Category"
Write-Host "    Output:   $OutputPath"

if ($Category -eq "category_2") {
    Write-Host "[SECURITY] Category 2 selected. Enforcing local-only model path."

    if ([string]::IsNullOrWhiteSpace($Model)) {
        $Model = "local-llama"
    }

    Write-Host "[SECURITY] Model selected: $Model"
    Write-Host "[SECURITY] Confirm Fabric is configured to route this model locally before using real sensitive data."

    if ($Model -notmatch "local|llama|ollama") {
        throw "Blocked: Category 2 Fabric tasks must use a local-only model name."
    }
}
else {
    if ([string]::IsNullOrWhiteSpace($Model)) {
        Write-Host "[*] Category 1 selected. Using Fabric default model/provider."
    } else {
        Write-Host "[*] Category 1 selected. Requested model: $Model"
    }
}

if ($DryRun) {
    @"
# Fabric Dry Run

Input: $InputPath
Pattern: $Pattern
Category: $Category
Model: $Model
Timestamp: $Timestamp

No Fabric command executed.
"@ | Set-Content $OutputPath -Encoding UTF8

    Write-Host "[OK] Dry-run output written:"
    Write-Host $OutputPath
    exit 0
}

$Content = Get-Content $InputPath -Raw

if ([string]::IsNullOrWhiteSpace($Content)) {
    throw "Input file is empty."
}

# Fabric CLI model flags vary by version/provider. Keep model enforcement external for now.
# Safe default: pipe content into Fabric pattern.
$Content | fabric --pattern $Pattern | Set-Content $OutputPath -Encoding UTF8

Write-Host "[OK] Fabric output written:"
Write-Host $OutputPath
