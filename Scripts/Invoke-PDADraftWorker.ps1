param(
    [Parameter(Mandatory=$true)]
    [string]$TaskPath
)

$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"

$Task = Get-Content $TaskPath -Raw | ConvertFrom-Json

if (-not $Task.source_path) {

    [ordered]@{
        task_id        = $Task.task_id
        worker         = "draft-worker"
        status         = "failed"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "error"
        output         = @{
            error = "No source_path provided."
        }
        confidence     = 0
        warnings       = @("Draft worker requires findings source material.")
        next_worker    = ""
        saved_path     = ""
    } | ConvertTo-Json -Depth 20

    exit
}

$FindingsContent = Get-Content $Task.source_path -Raw

$Prompt = @"
You are draft-worker inside the PDA ecosystem.

Your job:
Convert analytical findings into a professional operational report draft.

Requirements:
- concise professional tone
- operational wording
- no hallucinations
- no invented facts
- preserve uncertainty
- markdown format
- organized sections
- suitable for later analyst review

Suggested sections:
- Overview
- Findings
- Observations
- Risks
- Recommendations

Return markdown only.

Findings Input:

$FindingsContent
"@

$Body = @{
    model = "local-llama"
    messages = @(
        @{
            role = "system"
            content = "You are a professional analytical report drafting worker."
        },
        @{
            role = "user"
            content = $Prompt
        }
    )
    temperature = 0.15
} | ConvertTo-Json -Depth 10

try {

    $Response = Invoke-RestMethod `
        -Uri "http://localhost:4000/v1/chat/completions" `
        -Method POST `
        -ContentType "application/json" `
        -Body $Body

    $Content = $Response.choices[0].message.content

    $OutputFolder = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Drafts"

    New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    $MarkdownPath = Join-Path $OutputFolder "draft-output-$Timestamp.md"

    $Content | Set-Content -Path $MarkdownPath -Encoding UTF8

    [ordered]@{
        task_id        = $Task.task_id
        worker         = "draft-worker"
        status         = "success"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "draft_markdown"
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
        worker         = "draft-worker"
        status         = "failed"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "error"
        output         = @{
            error = $_.Exception.Message
        }
        confidence     = 0
        warnings       = @("Draft worker execution failed.")
        next_worker    = ""
        saved_path     = ""
    } | ConvertTo-Json -Depth 20
}
