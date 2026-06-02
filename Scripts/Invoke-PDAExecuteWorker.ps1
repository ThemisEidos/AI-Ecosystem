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
You are execute-worker inside the PDA ecosystem.

Your job:
Transform an approved plan or instruction set into a deterministic execution manifest.

Requirements:
- do not perform external side effects
- do not invent steps
- preserve approval boundaries
- be explicit about assumptions and prerequisites
- markdown format
- keep the output human-reviewable

Task:
$SourceText
"@

$Body = @{
    model = "local-llama"
    messages = @(
        @{
            role = "system"
            content = "You are a deterministic execution planning worker."
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

    $OutputFolder = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Execution"
    New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $MarkdownPath = Join-Path $OutputFolder "execution-output-$Timestamp.md"

    $Content | Set-Content -Path $MarkdownPath -Encoding UTF8

    [ordered]@{
        task_id        = $Task.task_id
        worker         = "execute-worker"
        status         = "success"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "execution_markdown"
        output         = @{
            markdown_path = $MarkdownPath
            content       = $Content
        }
        confidence     = 0.84
        warnings       = @()
        next_worker    = ""
        saved_path     = $MarkdownPath
    } | ConvertTo-Json -Depth 20
}
catch {
    [ordered]@{
        task_id        = $Task.task_id
        worker         = "execute-worker"
        status         = "failed"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "error"
        output         = @{
            error = $_.Exception.Message
        }
        confidence     = 0
        warnings       = @("Execute worker execution failed.")
        next_worker    = ""
        saved_path     = ""
    } | ConvertTo-Json -Depth 20
}
