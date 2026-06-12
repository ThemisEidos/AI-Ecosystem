Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== IMPORT PDA COMMAND ROUTER INTO N8N ==="

$WorkflowDir = Join-Path (Split-Path $PSScriptRoot -Parent) "n8n Workflow"
$WorkflowPath = Join-Path $WorkflowDir "PDA_Command_Router.json"

New-Item -ItemType Directory -Path $WorkflowDir -Force | Out-Null

Write-Host "Workflow file ready:"
Write-Host $WorkflowPath

docker cp $WorkflowPath pda-n8n:/tmp/PDA_Command_Router.json

Write-Host "Importing workflow..."
docker exec pda-n8n n8n import:workflow --input=/tmp/PDA_Command_Router.json
if ($LASTEXITCODE -ne 0) {
    throw "n8n workflow import failed."
}

Write-Host "Publishing workflow..."
docker exec pda-n8n n8n publish:workflow --id pda-command-router
if ($LASTEXITCODE -ne 0) {
    throw "n8n workflow publish failed."
}

Write-Host "Restarting n8n so the production webhook registers immediately..."
docker restart pda-n8n | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to restart pda-n8n after publishing the workflow."
}

Start-Sleep -Seconds 5

Write-Host ""
Write-Host "Done. Open n8n:"
Write-Host "http://localhost:5678"
