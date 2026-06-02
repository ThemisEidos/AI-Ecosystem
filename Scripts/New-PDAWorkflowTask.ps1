param(
    [Parameter(Mandatory=$true)]
    [string]$WorkflowName
)

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$TaskPath = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Tasks\pending\$Timestamp-workflow-builder.json"

$Task = [ordered]@{
    command  = "/gemini-cli"
    project  = "AI Ecosystem"
    target   = "Design and generate a new PDA workflow called: $WorkflowName"
    category = "category_1"
    approved = $true
    status   = "queued"
}

$Task | ConvertTo-Json -Depth 10 | Set-Content $TaskPath -Encoding UTF8

Write-Host ""
Write-Host "Workflow generation task created:"
Write-Host $TaskPath
