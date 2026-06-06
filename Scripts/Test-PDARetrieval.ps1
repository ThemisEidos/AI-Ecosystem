[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$IncludeTestRecords,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_Retrieval.ps1")

function New-PDARetrievalSandbox {
    param([string]$SourceRoot)

    $RunId = Get-Date -Format "yyyyMMdd-HHmmssfff"
    $SandboxRoot = Join-Path $SourceRoot "PDA-Tasks\temp\retrieval-test-records\$RunId\repo"
    $ScriptsDir = Join-Path $SandboxRoot "Scripts"
    $AssetsDir = Join-Path $SandboxRoot "PDA-Tasks\temp\retrieval-test-records\$RunId\assets"
    New-Item -ItemType Directory -Force -Path $ScriptsDir, $AssetsDir | Out-Null

    foreach ($Path in @(
        "Scripts\PDA_CategoryRouting.ps1",
        "Scripts\PDA_TaskOntology.json",
        "Scripts\PDA_TaskOntology.schema.json",
        "Scripts\PDA_TaskOntology.ps1",
        "Scripts\PDA_LifecyclePolicy.json",
        "Scripts\PDA_LifecyclePolicy.schema.json",
        "Scripts\PDA_WorkerRegistry.json",
        "PDA_ArtifactIndex.json",
        "PDA_MemoryIndex.json"
    )) {
        $Source = Join-Path $SourceRoot $Path
        if (Test-Path $Source -PathType Leaf) {
            Copy-Item -Path $Source -Destination (Join-Path $SandboxRoot $Path) -Force
        }
    }

    $SeedArtifactPath = Join-Path $AssetsDir "seed-artifact.md"
    $SeedMemoryPath = Join-Path $AssetsDir "seed-memory.md"
    $SeedLineagePath = Join-Path $AssetsDir "seed-lineage.md"
    @"
# PDA Retrieval Seed Artifact

This file is synthetic test data for deterministic retrieval validation.
"@ | Set-Content -Path $SeedArtifactPath -Encoding UTF8
    @"
# PDA Retrieval Seed Memory

This file is synthetic test data for deterministic retrieval validation.
"@ | Set-Content -Path $SeedMemoryPath -Encoding UTF8
    @"
# PDA Retrieval Seed Lineage Artifact

This file exists to validate source-artifact lineage joins.
"@ | Set-Content -Path $SeedLineagePath -Encoding UTF8

    $SeedArtifactId = "artifact-seeded-retrieval-001"
    $SeedLineageArtifactId = "artifact-seeded-retrieval-lineage-001"
    $SeedMemoryId = "memory-seeded-retrieval-001"
    $SeedTaskId = "task-seeded-retrieval-001"
    $SeedLineageTaskId = "task-seeded-retrieval-lineage-001"

    $ArtifactIndexPath = Join-Path $SandboxRoot "PDA_ArtifactIndex.json"
    $MemoryIndexPath = Join-Path $SandboxRoot "PDA_MemoryIndex.json"

    $ArtifactIndex = Get-Content -Path $ArtifactIndexPath -Raw | ConvertFrom-Json
    $MemoryIndex = Get-Content -Path $MemoryIndexPath -Raw | ConvertFrom-Json

    $ArtifactIndex.artifacts = @($ArtifactIndex.artifacts | Where-Object {
        -not (
            ([string]$_.category -eq "test") -or
            ([string]$_.artifact_type -match '^test')
        )
    })

    $MemoryIndex.memories = @($MemoryIndex.memories | Where-Object {
        -not (
            ([string]$_.category -eq "test") -or
            ([string]$_.memory_type -match '^test')
        )
    })

    $ArtifactIndex.artifacts += [pscustomobject]@{
        artifact_id    = $SeedArtifactId
        created_at     = "2026-06-03T11:30:00Z"
        artifact_path  = "PDA-Tasks/temp/retrieval-test-records/$RunId/assets/seed-artifact.md"
        source_task_id = $SeedTaskId
        worker_name    = "planner-worker"
        command        = "/planner"
        category       = "category_1"
        artifact_type  = "retrieval_seed_markdown"
        tags           = @("retrieval", "seed", "synthetic")
        lifecycle_state = "active"
        summary        = "Synthetic retrieval seed artifact for controlled debugging"
    }

    $ArtifactIndex.artifacts += [pscustomobject]@{
        artifact_id    = $SeedLineageArtifactId
        created_at     = "2026-06-03T11:30:01Z"
        artifact_path  = "PDA-Tasks/temp/retrieval-test-records/$RunId/assets/seed-lineage.md"
        source_task_id = $SeedLineageTaskId
        worker_name    = "planner-worker"
        command        = "/planner"
        category       = "category_1"
        artifact_type  = "retrieval_seed_lineage_markdown"
        source_artifact_id = $SeedArtifactId
        tags           = @("retrieval", "seed", "lineage", "synthetic")
        lifecycle_state = "archived"
        summary        = "Synthetic lineage artifact referencing the seeded retrieval artifact"
    }

    $ArtifactIndex.updated_at = "2026-06-03T11:30:02Z"
    $ArtifactIndex | ConvertTo-Json -Depth 20 | Set-Content -Path $ArtifactIndexPath -Encoding UTF8

    $MemoryIndex.memories += [pscustomobject]@{
        memory_id          = $SeedMemoryId
        created_at         = "2026-06-03T11:30:03Z"
        updated_at         = "2026-06-03T11:30:03Z"
        memory_type        = "retrieval-seed"
        title              = "Synthetic retrieval seed memory"
        summary            = "Synthetic retrieval seed memory for controlled debugging"
        category           = "category_1"
        source_artifact_id = $SeedArtifactId
        source_path        = "PDA-Tasks/temp/retrieval-test-records/$RunId/assets/seed-memory.md"
        tags               = @("retrieval", "seed", "synthetic")
        status             = "seeded"
        lifecycle_state    = "active"
    }

    $MemoryIndex.memories += [pscustomobject]@{
        memory_id          = "memory-seeded-retrieval-orphan-001"
        created_at         = "2026-06-03T11:30:04Z"
        updated_at         = "2026-06-03T11:30:04Z"
        memory_type        = "retrieval-seed"
        title              = "Synthetic lineage memory"
        summary            = "Synthetic memory used to validate source artifact lineage joins"
        category           = "category_1"
        source_artifact_id = $SeedLineageArtifactId
        source_path        = "PDA-Tasks/temp/retrieval-test-records/$RunId/assets/seed-memory.md"
        tags               = @("retrieval", "seed", "lineage", "synthetic")
        status             = "seeded"
        lifecycle_state    = "archived"
    }

    $MemoryIndex.updated_at = "2026-06-03T11:30:05Z"
    $MemoryIndex | ConvertTo-Json -Depth 20 | Set-Content -Path $MemoryIndexPath -Encoding UTF8

    return [pscustomobject]@{
        root = $SandboxRoot
        seed_artifact_id = $SeedArtifactId
        seed_lineage_artifact_id = $SeedLineageArtifactId
        seed_memory_id = $SeedMemoryId
        seed_task_id = $SeedTaskId
        seed_lineage_task_id = $SeedLineageTaskId
        seed_artifact_path = $SeedArtifactPath
        seed_memory_path = $SeedMemoryPath
        seed_lineage_path = $SeedLineagePath
    }
}

$EffectiveRoot = $Root
$SeedContext = $null
if ($IncludeTestRecords) {
    $SeedContext = New-PDARetrievalSandbox -SourceRoot $Root
    $EffectiveRoot = $SeedContext.root
}

$Integrity = Test-PDARetrievalIntegrity -Root $EffectiveRoot -IncludeTestRecords:$IncludeTestRecords

$ArtifactQueries = $null
$MemoryQueries = $null
$OntologyQueries = $null
$WorkerQueries = $null
if ($IncludeTestRecords) {
    $ArtifactQueries = [pscustomobject]@{
        by_worker = @(Get-PDAArtifacts -Root $EffectiveRoot -WorkerName "planner-worker" -Latest 10)
        by_category = @(Get-PDAArtifacts -Root $EffectiveRoot -Category "category_1" -Latest 10)
        by_type = @(Get-PDAArtifacts -Root $EffectiveRoot -ArtifactType "retrieval_seed_markdown")
        by_tags = @(Get-PDAArtifacts -Root $EffectiveRoot -Tags @("retrieval","synthetic"))
        by_lineage = @(Get-PDAArtifacts -Root $EffectiveRoot -Lineage $SeedContext.seed_artifact_id)
        by_lifecycle = @(Get-PDAArtifacts -Root $EffectiveRoot -LifecycleState "active")
    }

    $MemoryQueries = [pscustomobject]@{
        by_category = @(Get-PDAMemory -Root $EffectiveRoot -Category "category_1" -Latest 10)
        by_tags = @(Get-PDAMemory -Root $EffectiveRoot -Tags @("retrieval","synthetic"))
        by_source = @(Get-PDAMemory -Root $EffectiveRoot -SourceArtifactId $SeedContext.seed_artifact_id)
        by_status = @(Get-PDAMemory -Root $EffectiveRoot -Status "seeded")
        by_lifecycle = @(Get-PDAMemory -Root $EffectiveRoot -LifecycleState "active")
    }

    $OntologyQueries = [pscustomobject]@{
        by_command = @(Get-PDATaskOntologyEntry -Root $EffectiveRoot -Command "/planner")
        by_intent = @(Get-PDATaskOntologyEntry -Root $EffectiveRoot -Intent "planning")
        by_classification = @(Get-PDATaskOntologyEntry -Root $EffectiveRoot -Classification "category_1")
    }

    $WorkerQueries = [pscustomobject]@{
        by_command = @(Get-PDAWorkerCapability -Root $EffectiveRoot -Command "/planner" -Category "category_1")
        by_category = @(Get-PDAWorkerCapability -Root $EffectiveRoot -Category "category_1")
        by_approval = @(Get-PDAWorkerCapability -Root $EffectiveRoot -Command "/planner" -ApprovalRequirement "none")
    }
}

if ($AsJson) {
    [pscustomobject]@{
        include_test_records = [bool]$IncludeTestRecords
        effective_root = $EffectiveRoot
        seed_context = $SeedContext
        integrity = $Integrity
        artifact_queries = $ArtifactQueries
        memory_queries = $MemoryQueries
        ontology_queries = $OntologyQueries
        worker_queries = $WorkerQueries
    } | ConvertTo-Json -Depth 20
    if ($Integrity.status -ne "pass" -and -not $NoThrow) {
        throw "PDA retrieval integrity check failed."
    }

    return
}

if ($IncludeTestRecords) {
    Write-Host "[*] PDA retrieval integrity (seeded test-record mode)"
    Write-Host ("Sandbox root         : {0}" -f $EffectiveRoot)
    Write-Host ("Seed artifact        : {0}" -f $SeedContext.seed_artifact_id)
    Write-Host ("Seed memory          : {0}" -f $SeedContext.seed_memory_id)
    Write-Host ("Seed lineage artifact: {0}" -f $SeedContext.seed_lineage_artifact_id)
}
else {
    Write-Host "[*] PDA retrieval integrity (strict repo mode)"
}

Write-Host ("Artifacts            : {0}" -f $Integrity.artifact_count)
Write-Host ("Memories             : {0}" -f $Integrity.memory_count)
Write-Host ("Ontology entries     : {0}" -f $Integrity.ontology_count)
Write-Host ("Workers              : {0}" -f $Integrity.worker_count)
Write-Host ("Missing references   : {0}" -f $Integrity.missing_reference_count)
Write-Host ("Orphaned lineage     : {0}" -f $Integrity.orphan_count)
Write-Host ("Invalid ontology refs: {0}" -f $Integrity.invalid_ontology_reference_count)
Write-Host ("Invalid worker maps  : {0}" -f $Integrity.invalid_worker_mapping_count)
Write-Host ("Lineage health       : {0}" -f $Integrity.lineage_health)
Write-Host ("Status               : {0}" -f $Integrity.status)

if ($Integrity.missing_reference_count -gt 0) {
    Write-Host ""
    Write-Host "[Missing References]"
    foreach ($Issue in $Integrity.missing_references) {
        Write-Host ("- {0}: {1}" -f $Issue.type, ($Issue.detail ?? $Issue.memory_id ?? $Issue.artifact_id))
    }
}

if ($Integrity.orphan_count -gt 0) {
    Write-Host ""
    Write-Host "[Orphaned Lineage]"
    foreach ($Issue in $Integrity.orphaned_lineage) {
        Write-Host ("- {0}: {1}" -f $Issue.type, ($Issue.memory_id ?? $Issue.artifact_id))
    }
}

if ($Integrity.invalid_ontology_reference_count -gt 0) {
    Write-Host ""
    Write-Host "[Invalid Ontology References]"
    foreach ($Issue in $Integrity.invalid_ontology_references) {
        Write-Host ("- {0}: {1} ({2})" -f $Issue.type, $Issue.command, $Issue.reason)
    }
}

if ($Integrity.invalid_worker_mapping_count -gt 0) {
    Write-Host ""
    Write-Host "[Invalid Worker Mappings]"
    foreach ($Issue in $Integrity.invalid_worker_mappings) {
        Write-Host ("- {0}: {1} ({2})" -f $Issue.type, $Issue.command, $Issue.reason)
    }
}

if ($Integrity.status -ne "pass" -and -not $NoThrow) {
    throw "PDA retrieval integrity check failed."
}

if ($IncludeTestRecords) {
    if (($ArtifactQueries.by_worker.Count -eq 0) -or ($ArtifactQueries.by_category.Count -eq 0) -or ($ArtifactQueries.by_type.Count -eq 0) -or ($ArtifactQueries.by_tags.Count -eq 0) -or ($ArtifactQueries.by_lineage.Count -eq 0)) {
        throw "Seeded artifact queries did not return expected synthetic records."
    }

    if (($MemoryQueries.by_category.Count -eq 0) -or ($MemoryQueries.by_tags.Count -eq 0) -or ($MemoryQueries.by_source.Count -eq 0) -or ($MemoryQueries.by_status.Count -eq 0)) {
        throw "Seeded memory queries did not return expected synthetic records."
    }

    if (($OntologyQueries.by_command.Count -eq 0) -or ($OntologyQueries.by_intent.Count -eq 0) -or ($OntologyQueries.by_classification.Count -eq 0)) {
        throw "Seeded ontology queries did not return expected synthetic records."
    }

    if (($WorkerQueries.by_command.Count -eq 0) -or ($WorkerQueries.by_category.Count -eq 0) -or ($WorkerQueries.by_approval.Count -eq 0)) {
        throw "Seeded worker capability queries did not return expected synthetic records."
    }

    Write-Host ""
    Write-Host "[Seeded Retrieval Checks]"
    Write-Host ("Artifact queries passed : {0}" -f $ArtifactQueries.by_worker.Count)
    Write-Host ("Memory queries passed   : {0}" -f $MemoryQueries.by_source.Count)
    Write-Host ("Ontology queries passed : {0}" -f $OntologyQueries.by_command.Count)
    Write-Host ("Worker queries passed   : {0}" -f $WorkerQueries.by_command.Count)
}
