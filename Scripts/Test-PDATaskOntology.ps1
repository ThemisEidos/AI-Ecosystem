$ErrorActionPreference = "Stop"

Write-Host "[*] Testing PDA task ontology..."

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_TaskOntology.ps1")

$Contract = Test-PDATaskOntologyContract -Root $Root

$Planner = Find-PDATaskTypes -Root $Root -Command "/planner" -Classification "category_1"
if (@($Planner).Count -ne 1) {
    throw "Expected exactly one planner task type."
}

$Category2Review = Get-PDATaskWorkerEligibility -Root $Root -Command "/review" -Classification "category_2" -Approved $true
foreach ($Worker in @($Category2Review.eligible_workers)) {
    if ($Worker.routing_surface -ne "local-only") {
        throw "Category 2 review routing escaped local-only confinement."
    }
}

$Category2Fabric = Get-PDATaskWorkerEligibility -Root $Root -Command "/fabric" -Classification "category_2" -Approved $true
if (@($Category2Fabric.eligible_workers).Count -gt 0) {
    throw "Fabric returned eligible Category 2 workers."
}

Write-Host "[OK] PDA task ontology tests passed."
Write-Host ("Intents   : {0}" -f $Contract.intent_count)
Write-Host ("Categories: {0}" -f $Contract.category_count)
