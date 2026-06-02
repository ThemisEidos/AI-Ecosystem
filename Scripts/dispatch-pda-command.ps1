param(
    [string]$TaskFile
)

if (-not (Test-Path $TaskFile)) {
    Write-Error "Task file not found."
    exit 1
}

$Task = Get-Content $TaskFile | ConvertFrom-Json

Write-Host ""
Write-Host "=== PDA COMMAND DISPATCHER ==="
Write-Host "Command:  $($Task.command)"
Write-Host "Target:   $($Task.target)"
Write-Host "Category: $($Task.category)"
Write-Host "Approved: $($Task.approved)"
Write-Host "Project:  $($Task.project)"
Write-Host ""


# -----------------------------
# Worker Paths
# -----------------------------

$WorkerRoot = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Workers"

$GeminiInbox = Join-Path $WorkerRoot "gemini-cli\inbox"

$ResearchInbox = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Workers\research-worker\inbox" 

$PlannerInbox = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Workers\planner-worker\inbox"

$QueueRoot = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Tasks"
$PendingInbox = Join-Path $QueueRoot "pending"



# -----------------------------
# Project Working Directories
# -----------------------------

$ProjectPaths = @{
    "AI Ecosystem" = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"
    "AegisPasswordManager" = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AegisPasswordManager"
}

$WorkingDirectory = $null

if ($Task.project -and $ProjectPaths.ContainsKey($Task.project)) {
    $WorkingDirectory = $ProjectPaths[$Task.project]
}


# -----------------------------
# Logging
# -----------------------------

$LogPath = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Logs"

if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath | Out-Null
}

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$LogFile = Join-Path $LogPath "$Timestamp.log"

@"
Timestamp: $Timestamp
Command:   $($Task.command)
Project:   $($Task.project)
Target:    $($Task.target)
Category:  $($Task.category)
Approved:  $($Task.approved)
"@ | Set-Content $LogFile

Write-Host "Log created:"
Write-Host $LogFile
Write-Host ""


# -----------------------------
# Output File
# -----------------------------

$OutputRoot = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Outputs"

if (-not (Test-Path $OutputRoot)) {

    New-Item -ItemType Directory -Path $OutputRoot | Out-Null
}

$OutputFile = Join-Path $OutputRoot "$Timestamp-output.md"

@"
# PDA Task Output

## Command
$($Task.command)

## Project
$($Task.project)

## Target
$($Task.target)

## Category
$($Task.category)

## Status
Task dispatched successfully.

## Timestamp
$Timestamp
"@ | Set-Content $OutputFile

Write-Host "Output file created:"
Write-Host $OutputFile
Write-Host ""

switch ($Task.command) {

    "/debug-project" {

        Write-Host "Launching Codex workflow..."

        Start-Process "codex" -WorkingDirectory $WorkingDirectory
    }

    "/review-report" {

        Write-Host "Routing to Claude review workflow..."
    }

    "/research-topic" {

        Write-Host "Launching research workflow..."

        Start-Process "https://www.perplexity.ai/search?q=$($Task.target)"
    }

    "/gemini-cli" {

        Write-Host "Routing task to Gemini worker..."

        $WorkerTask = Join-Path $GeminiInbox "$Timestamp-gemini-task.json"

        $Task | ConvertTo-Json -Depth 10 | Set-Content $WorkerTask -Encoding UTF8

        Write-Host "Gemini worker task created:"
        Write-Host $WorkerTask
    }

    
    "/multi-agent-research" {

        Write-Host "Launching multi-agent research workflow..."

        $PerplexityOutput = Join-Path "$OutputRoot\perplexity" "$Timestamp-perplexity.md"
        $GeminiOutput     = Join-Path "$OutputRoot\gemini-cli" "$Timestamp-gemini.md"

        if ($Task.agents -contains "perplexity") {

            @"
# Perplexity Research Task

Target:
$($Task.target)

Timestamp:
$Timestamp

Status:
Launched
"@ | Set-Content $PerplexityOutput

            Start-Process "https://www.perplexity.ai/search?q=$($Task.target)"
        }

        if ($Task.agents -contains "gemini-cli") {

            @"
# Gemini CLI Research Task

Target:
$($Task.target)

Timestamp:
$Timestamp

Status:
Launched
"@ | Set-Content $GeminiOutput

            $Prompt = "Research and summarize: $($Task.target)"

            Start-Process pwsh `
                -WorkingDirectory $WorkingDirectory `
                -ArgumentList "-NoExit", "-Command", "gemini `"$Prompt`""
        }
    }
    
    "/research-worker" {

        Write-Host "Routing task to Research Worker..."

        $WorkerTask = Join-Path $ResearchInbox "$Timestamp-research-task.json"

        $Task | ConvertTo-Json -Depth 10 | Set-Content $WorkerTask -Encoding UTF8

        Write-Host "Research worker task created:"
        Write-Host $WorkerTask
    }
    
    "/planner-worker" {

        Write-Host "Routing task to Planner Worker..."

        $WorkerTask = Join-Path $PlannerInbox "$Timestamp-planner-task.json"

        $Task | ConvertTo-Json -Depth 10 | Set-Content $WorkerTask -Encoding UTF8

        Write-Host "Planner worker task created:"
        Write-Host $WorkerTask
    }

    "/reporter" {
        Write-Host "Routing task to Reporter Worker..."

        $WorkerTask = Join-Path $PendingInbox "$Timestamp-reporter-task.json"

        $Task | Add-Member -NotePropertyName assigned_worker -NotePropertyValue "reporter-worker" -Force
        $Task | Add-Member -NotePropertyName status -NotePropertyValue "queued" -Force
        $Task | Add-Member -NotePropertyName next_worker -NotePropertyValue "" -Force

        New-Item -ItemType Directory -Force -Path $PendingInbox | Out-Null

        $Task | ConvertTo-Json -Depth 10 | Set-Content $WorkerTask -Encoding UTF8

        Write-Host "Reporter worker task created:"
        Write-Host $WorkerTask
    }
    default {

        Write-Warning "Unknown command."
    }
}








