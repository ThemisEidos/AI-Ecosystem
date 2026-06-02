$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Workers\research-worker"

$Inbox     = Join-Path $Root "inbox"
$Working   = Join-Path $Root "working"
$Completed = Join-Path $Root "completed"
$Failed    = Join-Path $Root "failed"

$MemoryFile = Join-Path $Root "memory\memory.md"

$OutputRoot = Join-Path $Root "outputs"

Write-Host ""
Write-Host "=== RESEARCH WORKER ACTIVE ==="
Write-Host ""

while ($true) {

    $Tasks = Get-ChildItem $Inbox -Filter *.json

    foreach ($TaskFile in $Tasks) {

        try {

            $WorkingTask = Join-Path $Working $TaskFile.Name

            Move-Item $TaskFile.FullName $WorkingTask -Force

            $Task = Get-Content $WorkingTask | ConvertFrom-Json

            Write-Host ""
            Write-Host "Research task:"
            Write-Host $Task.target
            Write-Host ""

            $Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

            $OutputFile = Join-Path $OutputRoot "$Timestamp-research.md"

            $Prompt = @"
You are the PDA Research Worker.

Focus on:
- research synthesis
- architecture analysis
- comparative evaluation
- operational recommendations

Task:
$($Task.target)
"@

            $Result = gemini $Prompt

            @"
# Research Worker Output

## Task
$($Task.target)

## Timestamp
$Timestamp

## Result

$Result
"@ | Set-Content $OutputFile -Encoding UTF8

            @"

---

## Timestamp
$Timestamp

## Task
$($Task.target)

## Result
$Result

"@ | Add-Content $MemoryFile

            Move-Item $WorkingTask (Join-Path $Completed $TaskFile.Name) -Force

            Write-Host "Research artifact created:"
            Write-Host $OutputFile
        }

        catch {

            if (Test-Path $WorkingTask) {

                Move-Item $WorkingTask (Join-Path $Failed $TaskFile.Name) -Force
            }
        }
    }

    Start-Sleep -Seconds 5
}
