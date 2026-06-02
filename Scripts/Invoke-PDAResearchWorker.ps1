param(
    [Parameter(Mandatory=$true)]
    [string]$TaskPath
)

$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"

$Task = Get-Content $TaskPath -Raw | ConvertFrom-Json

$SourceText = $Task.target
if ($Task.source_path -and (Test-Path $Task.source_path)) {
    $SourceText = Get-Content $Task.source_path -Raw
}

$Prompt = @"
You are research-worker inside the PDA ecosystem.

Your job:
Produce concise, operational research synthesis for the provided topic or source material.

Requirements:
- local-first
- no invented facts
- clearly label confirmed findings vs open questions
- keep output practical and deterministic
- markdown format

Task:
$SourceText
"@

$Body = @{
    model = "local-llama"
    messages = @(
        @{
            role = "system"
            content = "You are a structured operational research synthesis worker."
        },
        @{
            role = "user"
            content = $Prompt
        }
    )
    temperature = 0.2
} | ConvertTo-Json -Depth 10

try {
    $Response = Invoke-RestMethod `
        -Uri "http://localhost:4000/v1/chat/completions" `
        -Method POST `
        -ContentType "application/json" `
        -Body $Body

    $Content = $Response.choices[0].message.content

    $OutputFolder = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Research"
    New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $MarkdownPath = Join-Path $OutputFolder "research-output-$Timestamp.md"

    $Content | Set-Content -Path $MarkdownPath -Encoding UTF8

    [ordered]@{
        task_id        = $Task.task_id
        worker         = "research-worker"
        status         = "success"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "research_markdown"
        output         = @{
            markdown_path = $MarkdownPath
            content       = $Content
        }
        confidence     = 0.88
        warnings       = @()
        next_worker    = "review-worker"
        saved_path     = $MarkdownPath
    } | ConvertTo-Json -Depth 20
}
catch {
    [ordered]@{
        task_id        = $Task.task_id
        worker         = "research-worker"
        status         = "failed"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "error"
        output         = @{
            error = $_.Exception.Message
        }
        confidence     = 0
        warnings       = @("Research worker execution failed.")
        next_worker    = ""
        saved_path     = ""
    } | ConvertTo-Json -Depth 20
}
