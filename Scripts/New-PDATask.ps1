param(
    [Parameter(Mandatory=$true)]
    [string]$Command,

    [string]$Project = "AI Tool Ecosystem",

    [ValidateSet("category_1","category_2")]
    [string]$Classification = "category_1",

    [string]$RequestedOutput = "markdown",

    [string]$SourcePath = "",

    [string]$AssignedWorker = "planner-worker"
)

$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"
$TaskId = [guid]::NewGuid().ToString()
$Created = (Get-Date).ToUniversalTime().ToString("o")
$QueueRoot = Join-Path $Root "PDA-Tasks"

# Deprecated legacy queue root:
# Tasks\queued is kept only for compatibility during migration.
# New task creation must write to PDA-Tasks\pending.
$LegacyQueueRoot = Join-Path $Root "Tasks"

$Task = [ordered]@{
    task_id = $TaskId
    created = $Created
    command = $Command
    project = $Project
    classification = $Classification
    status = "queued"
    requested_output = $RequestedOutput
    source_path = $SourcePath
    assigned_worker = $AssignedWorker
    next_worker = ""
    retry_count = 0
}

$PendingPath = Join-Path $QueueRoot "pending"
New-Item -ItemType Directory -Force -Path $PendingPath | Out-Null

$OutPath = Join-Path $PendingPath "$TaskId.json"
$Task | ConvertTo-Json -Depth 10 | Set-Content -Path $OutPath -Encoding UTF8

Write-Host "[OK] Created PDA task:"
Write-Host $OutPath
