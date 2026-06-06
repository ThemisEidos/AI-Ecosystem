$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_TaskOntology.ps1")

Write-Host "[*] Validating PDA task ontology..."
$Result = Test-PDATaskOntologyContract -Root $Root

Write-Host "[OK] Ontology validation passed."
Write-Host ("Schema path   : {0}" -f $Result.schema_path)
Write-Host ("Ontology path : {0}" -f $Result.ontology_path)
Write-Host ("Categories    : {0}" -f $Result.category_count)
Write-Host ("Intents       : {0}" -f $Result.intent_count)
Write-Host ("Registry refs : {0}" -f $Result.registry_workers)
