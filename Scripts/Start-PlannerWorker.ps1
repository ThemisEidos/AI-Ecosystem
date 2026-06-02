$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Workers\planner-worker"

$Inbox     = Join-Path $Root "inbox"
$Working   = Join-Path $Root "working"
$Completed = Join-Path $Root "completed"
$Failed    = Join-Path $Root "failed"
$Outputs   = Join-Path $Root "outputs"

$MemoryFile = Join-Path $Root "memory\memory.md"

Write-Host ""
Write-Host "=== PLANNER WORKER ACTIVE ==="
Write-Host ""

while ($true) {

    $Tasks = Get-ChildItem $Inbox -Filter *.json

    foreach ($TaskFile in $Tasks) {

        try {

            $WorkingTask = Join-Path $Working $TaskFile.Name

            Move-Item $TaskFile.FullName $WorkingTask -Force

            $Task = Get-Content $WorkingTask | ConvertFrom-Json

            Write-Host ""
            Write-Host "Planner task:"
            Write-Host $Task.target
            Write-Host ""

            $Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

            $OutputFile = Join-Path $Outputs "$Timestamp-plan.md"

            $Prompt = @"
You are the PDA Planner Worker.

Your role:
- decompose large objectives
- create execution phases
- identify dependencies
- assign specialist workers
- create orchestration plans

Output format:
- Objective
- Subtasks
- Recommended Workers
- Dependencies
- Execution Order
- Risks
- Recommended Next Action

Task:
$($Task.target)
"@

            $Result = gemini $Prompt

            @"
# Planner Worker Output

## Task
$($Task.target)

## Timestamp
$Timestamp

## Plan

$Result
"@ | Set-Content $OutputFile -Encoding UTF8

            @"

---

## Timestamp
$Timestamp

## Task
$($Task.target)

## Plan
$Result

"@ | Add-Content $MemoryFile

            Move-Item $WorkingTask (Join-Path $Completed $TaskFile.Name) -Force

            Write-Host "Planner artifact created:"
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
