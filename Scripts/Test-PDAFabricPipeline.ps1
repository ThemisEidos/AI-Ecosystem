$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$TempTaskDir = Join-Path $Root "PDA-Tasks\temp"
New-Item -ItemType Directory -Force -Path $TempTaskDir | Out-Null

$TaskId = [guid]::NewGuid().ToString()
$TaskPath = Join-Path $TempTaskDir "$TaskId-fabric-test.json"

$Task = @{
    task_id = $TaskId
    command = "/fabric"
    assigned_worker = "fabric-worker"
    pattern = "summarize"
    message = "This is a non-sensitive PDA Fabric dry-run test. Summarize this content and confirm the worker path is functioning."
    category = "category_2"
    model = "local-llama"
    input_mode = "message-only-test"
    dry_run = $true
    status = "test"
    created_at = (Get-Date).ToString("s")
}

$Task | ConvertTo-Json -Depth 8 | Set-Content $TaskPath -Encoding UTF8

Write-Host "[*] Running Fabric worker dry-run test..."
pwsh -NoProfile -File (Join-Path $PSScriptRoot "Invoke-PDAFabricWorker.ps1") -TaskPath $TaskPath

Write-Host "[OK] Fabric pipeline dry-run test complete."
