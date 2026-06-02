param(
    [Parameter(Mandatory=$true)]
    [string]$TaskPath
)

$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$ResultsDir = Join-Path $Root "PDA-Tasks\results"
$FabricOutDir = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Fabric"
$GeneratedDir = Join-Path $Root "PDA-Tasks\staging\generated\fabric"

New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
New-Item -ItemType Directory -Force -Path $FabricOutDir | Out-Null
New-Item -ItemType Directory -Force -Path $GeneratedDir | Out-Null

if (-not (Test-Path $TaskPath)) {
    throw "TaskPath not found: $TaskPath"
}

$Task = Get-Content $TaskPath -Raw | ConvertFrom-Json

if (-not $Task.task_id) {
    $Task | Add-Member -NotePropertyName task_id -NotePropertyValue ([guid]::NewGuid().ToString()) -Force
}

$TaskId = $Task.task_id
$Pattern = if ($Task.pattern) { $Task.pattern } else { "summarize" }
$Category = if ($Task.category) { $Task.category } else { "category_1" }
$Model = if ($Task.model) { $Task.model } else { "" }
$DryRun = $false
if ($null -ne $Task.dry_run) { $DryRun = [bool]$Task.dry_run }

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$SafePattern = $Pattern -replace '[^a-zA-Z0-9_-]', '_'
$ArtifactPath = Join-Path $FabricOutDir "fabric-$SafePattern-$Timestamp.md"
$ResultPath = Join-Path $ResultsDir "$TaskId-result.json"

Write-Host "[*] Fabric worker"
Write-Host "    Task ID:  $TaskId"
Write-Host "    Pattern:  $Pattern"
Write-Host "    Category: $Category"
Write-Host "    DryRun:   $DryRun"

# Category enforcement
if ($Category -eq "category_2") {
    if ([string]::IsNullOrWhiteSpace($Model)) {
        $Model = "local-llama"
    }

    if ($Model -notmatch "local|llama|ollama") {
        $Result = @{
            task_id = $TaskId
            status = "blocked"
            reason = "Category 2 Fabric task blocked because requested model is not local-only."
            requested_model = $Model
            category = $Category
            completed_at = (Get-Date).ToString("s")
        }
        $Result | ConvertTo-Json -Depth 8 | Set-Content $ResultPath -Encoding UTF8
        throw "Blocked Category 2 non-local model: $Model"
    }
}

# Resolve input
$InputText = ""

if ($Task.source_path -and (Test-Path $Task.source_path)) {
    $InputText = Get-Content $Task.source_path -Raw
    $InputMode = "file"
}
elseif ($Task.message) {
    $InputText = [string]$Task.message
    $InputMode = "message-only-test"

    $GeneratedInput = Join-Path $GeneratedDir "$TaskId-message-only.md"
    $InputText | Set-Content $GeneratedInput -Encoding UTF8
}
else {
    throw "Fabric task requires either source_path or message."
}

if ([string]::IsNullOrWhiteSpace($InputText)) {
    throw "Fabric input is empty."
}

# Execute
if ($DryRun) {
@"
# Fabric Dry Run

Task ID: $TaskId
Pattern: $Pattern
Category: $Category
Model: $Model
Input Mode: $InputMode
Completed: $(Get-Date -Format s)

## Input Preview

$InputText
"@ | Set-Content $ArtifactPath -Encoding UTF8
}
else {
    if (-not (Get-Command fabric -ErrorAction SilentlyContinue)) {
        throw "Fabric is not installed or not in PATH."
    }

    # Keep execution simple and version-tolerant.
    # Model routing is enforced by category policy and Fabric setup.
    $InputText | fabric --pattern $Pattern | Set-Content $ArtifactPath -Encoding UTF8
}

$Result = @{
    task_id = $TaskId
    command = "/fabric"
    assigned_worker = "fabric-worker"
    status = "success"
    pattern = $Pattern
    category = $Category
    model = $Model
    input_mode = $InputMode
    dry_run = $DryRun
    artifact_path = $ArtifactPath
    result_path = $ResultPath
    completed_at = (Get-Date).ToString("s")
}

$Result | ConvertTo-Json -Depth 8 | Set-Content $ResultPath -Encoding UTF8

Write-Host "[OK] Fabric artifact:"
Write-Host $ArtifactPath
Write-Host "[OK] Result:"
Write-Host $ResultPath
