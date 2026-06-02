param(
    [Parameter(Mandatory=$true)]
    [string]$TaskPath
)

$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"

$Task = Get-Content $TaskPath -Raw | ConvertFrom-Json

if (-not $Task.source_path) {

    [ordered]@{
        task_id        = $Task.task_id
        worker         = "timeline-worker"
        status         = "failed"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "error"
        output         = @{
            error = "No source_path provided."
        }
        confidence     = 0
        warnings       = @("Timeline worker requires source material.")
        next_worker    = ""
        saved_path     = ""
    } | ConvertTo-Json -Depth 20

    exit
}

$SourceContent = Get-Content $Task.source_path -Raw

$Prompt = @"
You are timeline-worker inside the PDA ecosystem.

Your job:
Convert raw operational notes into structured chronological timeline entries.

Requirements:
- preserve chronology
- preserve timestamps
- preserve uncertainty
- concise operational wording
- no hallucinations
- no added facts
- markdown bullet timeline
- use approximate times if needed
- identify missing timestamps if unclear

Return ONLY timeline markdown.

Source Notes:

$SourceContent
"@

$Body = @{
    model = "local-llama"
    messages = @(
        @{
            role = "system"
            content = "You are a structured operational timeline extraction worker."
        },
        @{
            role = "user"
            content = $Prompt
        }
    )
    temperature = 0.1
} | ConvertTo-Json -Depth 10

try {

    $Response = Invoke-RestMethod `
        -Uri "http://localhost:4000/v1/chat/completions" `
        -Method POST `
        -ContentType "application/json" `
        -Body $Body

    $Content = $Response.choices[0].message.content

    $OutputFolder = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Timeline"

    New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    $MarkdownPath = Join-Path $OutputFolder "timeline-output-$Timestamp.md"

    $Content | Set-Content -Path $MarkdownPath -Encoding UTF8

    [ordered]@{
        task_id        = $Task.task_id
        worker         = "timeline-worker"
        status         = "success"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "timeline_markdown"
        output         = @{
            markdown_path = $MarkdownPath
            content       = $Content
        }
        confidence     = 0.90
        warnings       = @()
        next_worker    = "findings-worker"
        saved_path     = $MarkdownPath
    } | ConvertTo-Json -Depth 20
}
catch {

    [ordered]@{
        task_id        = $Task.task_id
        worker         = "timeline-worker"
        status         = "failed"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "error"
        output         = @{
            error = $_.Exception.Message
        }
        confidence     = 0
        warnings       = @("Timeline worker execution failed.")
        next_worker    = ""
        saved_path     = ""
    } | ConvertTo-Json -Depth 20
}
