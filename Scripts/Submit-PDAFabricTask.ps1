param(
    [Parameter(Mandatory=$false)]
    [string]$Message = "PDA Fabric dry-run test",

    [Parameter(Mandatory=$false)]
    [string]$SourcePath = "",

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
$PendingDir = Join-Path $Root "PDA-Tasks\pending"
New-Item -ItemType Directory -Force -Path $PendingDir | Out-Null

$TaskId = [guid]::NewGuid().ToString()
$InputMode = if ($SourcePath) { "file" } else { "message-only-test" }
$TaskPath = Join-Path $PendingDir "$TaskId-fabric-task.json"

$Task = @{
    task_id = $TaskId
    command = "/fabric"
    assigned_worker = "fabric-worker"
    worker = "fabric-worker"
    pattern = $Pattern
    message = $Message
    source_path = $SourcePath
    category = $Category
    model = $Model
    input_mode = $InputMode
    dry_run = [bool]$DryRun
    status = "pending"
    created_at = (Get-Date).ToString("s")
}

$Task | ConvertTo-Json -Depth 8 | Set-Content $TaskPath -Encoding UTF8

Write-Host "[OK] Fabric task submitted:"
Write-Host $TaskPath
Write-Host "[INFO] Task ID: $TaskId"
