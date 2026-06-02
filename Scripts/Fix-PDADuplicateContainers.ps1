Write-Host "=== FIX PDA DUPLICATE CONTAINERS ==="

$Duplicates = @(
    "pda-open-webui",
    "pda-n8n",
    "pda-litellm"
)

foreach ($Name in $Duplicates) {
    $Exists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $Name }

    if ($Exists) {
        Write-Host "Stopping duplicate container: $Name"
        docker stop $Name | Out-Null
    }
    else {
        Write-Host "Not found: $Name"
    }
}

Write-Host ""
Write-Host "=== ACTIVE CONTAINERS ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
