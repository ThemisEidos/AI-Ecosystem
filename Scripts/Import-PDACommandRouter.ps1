Write-Host "=== IMPORT PDA COMMAND ROUTER INTO N8N ==="

$WorkflowDir = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\n8n Workflow"
$WorkflowPath = Join-Path $WorkflowDir "PDA_Command_Router.json"

New-Item -ItemType Directory -Path $WorkflowDir -Force | Out-Null

Write-Host "Workflow file ready:"
Write-Host $WorkflowPath

docker cp $WorkflowPath pda-n8n:/tmp/PDA_Command_Router.json

Write-Host "Importing workflow..."
docker exec pda-n8n n8n import:workflow --input=/tmp/PDA_Command_Router.json

Write-Host ""
Write-Host "Done. Open n8n:"
Write-Host "http://localhost:5678"
