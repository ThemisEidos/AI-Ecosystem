$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ExportRoot = Join-Path $Root "PDA-Backups\workflow-bundles"
$BundleDir = Join-Path $ExportRoot "pda-workflow-bundle-$Timestamp"

Write-Host "[*] Exporting PDA workflow bundle..."
New-Item -ItemType Directory -Force -Path $BundleDir | Out-Null

$Items = @(
    "n8n Workflow",
    "Scripts\PDA_WorkerRegistry.json",
    "Scripts\PDA_TaskOntology.json",
    "Scripts\PDA_TaskOntology.schema.json",
    "Scripts\PDA_TaskOntology.ps1",
    "Scripts\PDA_MemoryTaxonomy.json",
    "Scripts\PDA_MemoryTaxonomy.schema.json",
    "Scripts\PDA_MemoryTaxonomy.ps1",
    "Scripts\PDA_LegacyMemoryRepairAllowlist.json",
    "Scripts\PDA_LifecyclePolicy.json",
    "Scripts\PDA_LifecyclePolicy.schema.json",
    "Scripts\PDA_Lifecycle.ps1",
    "Scripts\PDA_Retrieval.ps1",
    "Scripts\PDA_ApprovedEntrypoints.json",
    "Scripts\Validate-PDATaskOntology.ps1",
    "Scripts\Validate-PDAMemoryTaxonomy.ps1",
    "Scripts\Validate-PDALifecyclePolicy.ps1",
    "Scripts\Get-PDATaskType.ps1",
    "Scripts\Resolve-PDATaskWorkers.ps1",
    "Scripts\Get-PDAArtifacts.ps1",
    "Scripts\Get-PDAMemory.ps1",
    "Scripts\Get-PDATaskOntologyEntry.ps1",
    "Scripts\Get-PDAWorkerCapability.ps1",
    "Scripts\PDA_CommandInterpreter.ps1",
    "Scripts\Invoke-PDACommandHandoff.ps1",
    "Scripts\Invoke-PDAChatBridge.ps1",
    "Scripts\Invoke-PDAWebhookBridge.ps1",
    "Scripts\New-PDAHttpBridgeWorkflow.ps1",
    "Scripts\New-PDAN8nClipboardWorkflow.ps1",
    "Scripts\Start-PDAWebhookServer.ps1",
    "Scripts\Get-PDAMemoryRepairReport.ps1",
    "Scripts\Set-PDAArtifactLifecycle.ps1",
    "Scripts\Set-PDAMemoryLifecycle.ps1",
    "Scripts\Test-PDATaskOntology.ps1",
    "Scripts\Test-PDAMemoryTaxonomy.ps1",
    "Scripts\Test-PDAMemoryWriterEnforcement.ps1",
    "Scripts\Test-PDALegacyMemoryRepair.ps1",
    "Scripts\Test-PDALifecycle.ps1",
    "Scripts\Test-PDAOntologyDispatch.ps1",
    "Scripts\Test-PDAPreDispatchBypass.ps1",
    "Scripts\Test-PDAOntologyGovernance.ps1",
    "Scripts\Test-PDAOntologyGovernanceDrift.ps1",
    "Scripts\Test-PDARepoGovernance.ps1",
    "Scripts\Test-PDARetrieval.ps1",
    "Scripts\Test-PDACommandInterpreter.ps1",
    "Scripts\Test-PDACommandHandoff.ps1",
    "Scripts\Test-PDAChatBridge.ps1",
    "Scripts\Test-PDAChatBridgeIntegration.ps1",
    "Scripts\Test-PDAWebhookBridge.ps1",
    "Scripts\Test-PDAHttpBridgeWorkflow.ps1",
    "Scripts\Test-PDAN8nClipboardWorkflow.ps1",
    "Scripts\Test-PDAWebhookServerReachability.ps1",
    "Documentation\OpenWebUI-Integration.md",
    "n8n Workflow\PDA-ChatBridge.json",
    "n8n Workflow\PDA-ChatBridge-HTTP.json",
    "n8n Workflow\PDA-ChatBridge-HTTP-Clipboard.json",
    "Scripts\PDA_MultiAgentTask.schema.json",
    "Scripts\PDA_TaskRequest.schema.json",
    "Scripts\PDA_WorkerContract.schema.json",
    "Scripts\PDA_CategoryRouting.ps1",
    "PDA-Runtime\docker-compose.yml",
    "README.md",
    "CHANGELOG.md"
)

foreach ($item in $Items) {
    $Source = Join-Path $Root $item
    if (Test-Path $Source) {
        $Dest = Join-Path $BundleDir $item
        $Parent = Split-Path $Dest -Parent
        New-Item -ItemType Directory -Force -Path $Parent | Out-Null
        Copy-Item $Source $Dest -Recurse -Force
        Write-Host "[OK] Exported: $item"
    }
}

$Manifest = @{
    exported_at = (Get-Date).ToString("s")
    root        = $Root
    bundle      = $BundleDir
    purpose     = "PDA workflow restore bundle"
} | ConvertTo-Json -Depth 4

$Manifest | Set-Content (Join-Path $BundleDir "bundle-manifest.json") -Encoding UTF8

Write-Host "[OK] Bundle exported:"
Write-Host $BundleDir
