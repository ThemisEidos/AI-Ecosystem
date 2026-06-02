param(
    [Parameter(Mandatory=$true)]
    [string]$TaskPath
)

$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"

$Task = Get-Content $TaskPath -Raw | ConvertFrom-Json

$Prompt = @"
You are planner-worker inside the PDA AI orchestration ecosystem.

The ecosystem architecture already exists and includes:

- PowerShell orchestration
- n8n workflow routing
- LiteLLM model gateway
- Ollama local models
- Open WebUI
- Obsidian integration
- task queues
- worker contracts
- markdown outputs
- local-first architecture
- structured JSON task objects

Your job:
Create an implementation-focused execution plan that BUILDS ON the existing PDA ecosystem.

DO NOT suggest:
- enterprise microservices
- kubernetes
- cassandra
- airflow
- apache nifi
- unrelated enterprise tooling
- unnecessary cloud complexity

Favor:
- PowerShell
- n8n
- JSON task objects
- markdown outputs
- worker chaining
- local-first architecture
- modular orchestration
- practical implementation steps
- incremental improvements

Task:
$($Task.command)

Return:
- concise markdown
- implementation-focused
- aligned to current PDA architecture
- operationally useful
- no fluff
"@

$Body = @{
    model = "local-llama"
    messages = @(
        @{
            role = "system"
            content = "You are an AI orchestration planning worker inside a modular local-first AI ecosystem."
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

    $OutputFolder = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Planner"

    New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    $MarkdownPath = Join-Path $OutputFolder "planner-output-$Timestamp.md"

    $Content | Set-Content -Path $MarkdownPath -Encoding UTF8

    [ordered]@{
        task_id        = $Task.task_id
        worker         = "planner-worker"
        status         = "success"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "markdown"
        output         = @{
            markdown_path = $MarkdownPath
            content       = $Content
        }
        confidence     = 0.92
        warnings       = @()
        next_worker    = ""
        saved_path     = $MarkdownPath
    } | ConvertTo-Json -Depth 20
}
catch {

    [ordered]@{
        task_id        = $Task.task_id
        worker         = "planner-worker"
        status         = "failed"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "error"
        output         = @{
            error = $_.Exception.Message
        }
        confidence     = 0
        warnings       = @("Planner worker execution failed.")
        next_worker    = ""
        saved_path     = ""
    } | ConvertTo-Json -Depth 20
}
