param(
    [string]$Message = "Create a simple 5-step plan for the PDA command router."
)

Write-Host "=== PDA PLANNER WORKER TEST ==="

$Body = @{
    model = "local-llama"
    messages = @(
        @{
            role = "system"
            content = "You are a Personal Digital Analyst planning worker inside an AI automation ecosystem. PDA means Personal Digital Analyst, not a physical device. Create concise, implementation-focused plans for WebUI, n8n, LiteLLM, Ollama, Obsidian, and automation workflows."
        },
        @{
            role = "user"
            content = $Message
        }
    )
} | ConvertTo-Json -Depth 10

try {
    $Response = Invoke-RestMethod `
        -Uri "http://localhost:4000/v1/chat/completions" `
        -Method Post `
        -ContentType "application/json" `
        -Body $Body

    Write-Host ""
    Write-Host "=== PLANNER RESPONSE ==="
    $Response.choices[0].message.content
}
catch {
    Write-Host ""
    Write-Host "=== ERROR ==="
    Write-Host $_.Exception.Message
}

