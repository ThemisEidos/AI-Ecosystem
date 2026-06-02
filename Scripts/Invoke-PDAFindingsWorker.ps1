param(
    [Parameter(Mandatory=$true)]
    [string]$TaskPath
)

$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"

$Task = Get-Content $TaskPath -Raw | ConvertFrom-Json

if (-not $Task.source_path) {

    [ordered]@{
        task_id        = $Task.task_id
        worker         = "findings-worker"
        status         = "failed"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "error"
        output         = @{
            error = "No source_path provided."
        }
        confidence     = 0
        warnings       = @("Findings worker requires timeline source material.")
        next_worker    = ""
        saved_path     = ""
    } | ConvertTo-Json -Depth 20

    exit
}

$TimelineContent = Get-Content $Task.source_path -Raw

$Prompt = @"
You are findings-worker inside the PDA ecosystem.

Your job:
Analyze operational timeline notes and extract:

- findings
- vulnerabilities
- procedural gaps
- suspicious activity
- unresolved questions
- operational observations

Requirements:
- concise operational wording
- no hallucinations
- no invented facts
- markdown format
- preserve uncertainty
- clearly distinguish observations vs assumptions

Return markdown only.

Timeline Notes:

$TimelineContent
"@

$Body = @{
    model = "local-llama"
    messages = @(
        @{
            role = "system"
            content = "You are a structured analytical findings extraction worker."
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

    $OutputFolder = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Findings"

    New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    $MarkdownPath = Join-Path $OutputFolder "findings-output-$Timestamp.md"

    $Content | Set-Content -Path $MarkdownPath -Encoding UTF8

    [ordered]@{
        task_id        = $Task.task_id
        worker         = "findings-worker"
        status         = "success"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "findings_markdown"
        output         = @{
            markdown_path = $MarkdownPath
            content       = $Content
        }
        confidence     = 0.90
        warnings       = @()
        next_worker    = "draft-worker"
        saved_path     = $MarkdownPath
    } | ConvertTo-Json -Depth 20
}
catch {

    [ordered]@{
        task_id        = $Task.task_id
        worker         = "findings-worker"
        status         = "failed"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "error"
        output         = @{
            error = $_.Exception.Message
        }
        confidence     = 0
        warnings       = @("Findings worker execution failed.")
        next_worker    = ""
        saved_path     = ""
    } | ConvertTo-Json -Depth 20
}
