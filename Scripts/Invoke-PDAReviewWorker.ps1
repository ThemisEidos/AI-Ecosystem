param(
    [Parameter(Mandatory=$true)]
    [string]$TaskPath
)

$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"

$Task = Get-Content $TaskPath -Raw | ConvertFrom-Json

if (-not $Task.source_path) {

    [ordered]@{
        task_id        = $Task.task_id
        worker         = "review-worker"
        status         = "failed"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "error"
        output         = @{
            error = "No source_path provided."
        }
        confidence     = 0
        warnings       = @("Review worker requires draft source material.")
        next_worker    = ""
        saved_path     = ""
    } | ConvertTo-Json -Depth 20

    exit
}

$DraftContent = Get-Content $Task.source_path -Raw

$Prompt = @"
You are review-worker inside the PDA ecosystem.

Your job:
Review an operational report draft for:

- unsupported claims
- hallucinations
- missing information
- formatting issues
- weak analytical reasoning
- unclear wording
- missing caveats
- operational inconsistencies

Requirements:
- concise operational wording
- markdown format
- preserve uncertainty
- do not invent facts
- clearly separate:
  - confirmed issues
  - possible concerns
  - recommendations

Return markdown only.

Draft Report:

$DraftContent
"@

$Body = @{
    model = "local-llama"
    messages = @(
        @{
            role = "system"
            content = "You are an analytical report review worker."
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

    $OutputFolder = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Reviews"

    New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    $MarkdownPath = Join-Path $OutputFolder "review-output-$Timestamp.md"

    $Content | Set-Content -Path $MarkdownPath -Encoding UTF8

    [ordered]@{
        task_id        = $Task.task_id
        worker         = "review-worker"
        status         = "success"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "review_markdown"
        output         = @{
            markdown_path = $MarkdownPath
            content       = $Content
        }
        confidence     = 0.90
        warnings       = @()
        next_worker    = ""
        saved_path     = $MarkdownPath
    } | ConvertTo-Json -Depth 20
}
catch {

    [ordered]@{
        task_id        = $Task.task_id
        worker         = "review-worker"
        status         = "failed"
        classification = $Task.classification
        input_summary  = $Task.command
        output_type    = "error"
        output         = @{
            error = $_.Exception.Message
        }
        confidence     = 0
        warnings       = @("Review worker execution failed.")
        next_worker    = ""
        saved_path     = ""
    } | ConvertTo-Json -Depth 20
}
