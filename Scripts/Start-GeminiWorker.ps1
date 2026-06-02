$WorkerRoot = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Workers\gemini-cli"

$Inbox     = Join-Path $WorkerRoot "inbox"
$Working   = Join-Path $WorkerRoot "working"
$Completed = Join-Path $WorkerRoot "completed"
$Failed    = Join-Path $WorkerRoot "failed"

$OutputRoot = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Outputs\gemini-cli"

$ThrottleFile = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Workers\gemini-throttle.json"

$FallbackRegistry = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Workers\fallback-routing.json"



Write-Host ""
Write-Host "=== GEMINI WORKER ACTIVE ==="
Write-Host ""

while ($true) {

    $Tasks = Get-ChildItem $Inbox -Filter *.json

    foreach ($TaskFile in $Tasks) {

        try {

            $WorkingTask = Join-Path $Working $TaskFile.Name

            Move-Item $TaskFile.FullName $WorkingTask -Force

            $Task = Get-Content $WorkingTask | ConvertFrom-Json

            Write-Host ""
            Write-Host "Processing Gemini task:"
            Write-Host $Task.target
            Write-Host ""

            $Throttle = Get-Content $ThrottleFile | ConvertFrom-Json

            if ($Throttle.active -eq $true) {

                Write-Host ""
                Write-Host "Gemini throttle active. Waiting..."

                Start-Sleep -Seconds $Throttle.cooldown_seconds
            }

            $Throttle.active = $true
            $Throttle.last_call = Get-Date

            $Throttle | ConvertTo-Json | Set-Content $ThrottleFile

            $Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

            $OutputFile = Join-Path $OutputRoot "$Timestamp-gemini-output.md"

            $Result = gemini $Task.target

            @"
# Gemini Worker Output

## Target
$($Task.target)

## Timestamp
$Timestamp

## Result

$Result
"@ | Set-Content $OutputFile -Encoding UTF8

            
            # -----------------------------
            # Persistent Memory
            # -----------------------------

            $MemoryFile = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Memory\gemini-cli\memory.md"

            @"

---

## Timestamp
$Timestamp

## Task
$($Task.target)

## Result
$Result

"@ | Add-Content $MemoryFile
            Write-Host ""
            Write-Host "Output written:"
            Write-Host $OutputFile

            $Throttle.active = $false
            $Throttle | ConvertTo-Json | Set-Content $ThrottleFile

            Move-Item $WorkingTask (Join-Path $Completed $TaskFile.Name) -Force
        }

        catch {

            Write-Host ""
            Write-Host "Task failed."

            if (Test-Path $WorkingTask) {

                Move-Item $WorkingTask (Join-Path $Failed $TaskFile.Name) -Force
            }
        }
    }

    Start-Sleep -Seconds 5
}




