$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"

$Folders = @{
    pending   = Join-Path $Root "PDA-Tasks\pending"
    running   = Join-Path $Root "PDA-Tasks\running"
    completed = Join-Path $Root "PDA-Tasks\completed"
    failed    = Join-Path $Root "PDA-Tasks\failed"
    results   = Join-Path $Root "PDA-Tasks\results"
}

$Services = @(
    @{ Name = "Open WebUI"; Url = "http://localhost:3000" },
    @{ Name = "LiteLLM"; Url = "http://localhost:4000/v1/models" },
    @{ Name = "n8n"; Url = "http://localhost:5678" },
    @{ Name = "Ollama"; Url = "http://localhost:11434/api/tags" }
)

# Deprecated legacy queue paths:
# Tasks\queued, Tasks\running, Tasks\completed, Tasks\failed, and Tasks\results
# are no longer canonical. Keep them only if you need to compare migrated data.
$LegacyFolders = @{
    queued    = Join-Path $Root "Tasks\queued"
    running   = Join-Path $Root "Tasks\running"
    completed = Join-Path $Root "Tasks\completed"
    failed    = Join-Path $Root "Tasks\failed"
    results   = Join-Path $Root "Tasks\results"
}

Write-Host "=== PDA SYSTEM STATUS ==="
Write-Host ""

Write-Host "=== SERVICE STATUS ==="
foreach ($Service in $Services) {
    try {
        Invoke-WebRequest -Uri $Service.Url -UseBasicParsing -TimeoutSec 5 | Out-Null
        "[OK] {0}" -f $Service.Name
    }
    catch {
        "[WAIT] {0}" -f $Service.Name
    }
}
Write-Host ""

Write-Host "=== CANONICAL PDA-TASKS STATUS ==="
foreach ($Key in $Folders.Keys) {

    $Count = @(Get-ChildItem $Folders[$Key] -Filter *.json -ErrorAction SilentlyContinue).Count

    "{0,-10}: {1}" -f $Key, $Count
}

Write-Host ""
Write-Host "=== LEGACY / DEPRECATED TASKS SNAPSHOT ==="
Write-Host ""

foreach ($Key in $LegacyFolders.Keys) {
    if (Test-Path $LegacyFolders[$Key]) {
        $Count = @(Get-ChildItem $LegacyFolders[$Key] -Filter *.json -ErrorAction SilentlyContinue).Count
        "{0,-10}: {1}" -f ("LEGACY " + $Key), $Count
    }
}

Write-Host ""

$LatestCompleted = Get-ChildItem $Folders.completed -Filter *.json -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($LatestCompleted) {

    $Task = Get-Content $LatestCompleted.FullName -Raw | ConvertFrom-Json

    Write-Host "=== LAST COMPLETED TASK ==="
    Write-Host ""

    "Task ID   : {0}" -f $Task.task_id
    "Command   : {0}" -f $Task.command
    "Worker    : {0}" -f $Task.assigned_worker
    "Status    : {0}" -f $Task.status
    "Completed : {0}" -f $Task.completed

    if ($Task.result_path) {
        ""
        "Result:"
        $Task.result_path
    }
}

$LatestFailed = Get-ChildItem $Folders.failed -Filter *.json -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($LatestFailed) {

    Write-Host ""
    Write-Host "=== LAST FAILED TASK ==="

    $FailedTask = Get-Content $LatestFailed.FullName -Raw | ConvertFrom-Json

    ""
    "Task ID : $($FailedTask.task_id)"
    "Command : $($FailedTask.command)"
}
