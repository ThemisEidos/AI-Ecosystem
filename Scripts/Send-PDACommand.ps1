param(
    [Parameter(Mandatory = $true)]
    [string]$Command,

    [Parameter(Mandatory = $true)]
    [string]$Message
)

$WebhookUrl = "http://localhost:5678/webhook/pda-command-router"

$Body = @{
    command   = $Command
    message   = $Message
    timestamp = (Get-Date).ToString("s")
    source    = "PowerShell"
} | ConvertTo-Json -Depth 5

Write-Host "=== PDA COMMAND SENDER ==="
Write-Host "Command: $Command"
Write-Host "Message: $Message"
Write-Host ""

try {
    $Response = Invoke-RestMethod `
        -Uri $WebhookUrl `
        -Method Post `
        -ContentType "application/json" `
        -Body $Body

    Write-Host "=== RESPONSE ==="
    $Response | ConvertTo-Json -Depth 10
}
catch {
    Write-Host "=== ERROR ==="
    Write-Host $_.Exception.Message
}

