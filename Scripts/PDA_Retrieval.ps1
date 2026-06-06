function Get-PDARetrievalRoot {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return $Root
}

. (Join-Path $PSScriptRoot "PDA_Lifecycle.ps1")

function Read-PDAJsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$NotFoundMessage,

        [Parameter(Mandatory = $true)]
        [string]$ParseMessage
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw $NotFoundMessage
    }

    try {
        return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
    }
    catch {
        throw $ParseMessage
    }
}

function Get-PDARetrievalDate {
    param(
        [Parameter(Mandatory = $false)]
        $Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return [datetime]::MinValue
    }

    try {
        return [datetime]::Parse([string]$Value)
    }
    catch {
        return [datetime]::MinValue
    }
}

function Get-PDAIndexLookup {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Records,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $Lookup = @{}
    foreach ($Record in $Records) {
        if ($Record.PSObject.Properties.Name -contains $Key -and -not [string]::IsNullOrWhiteSpace([string]$Record.$Key)) {
            $Lookup[[string]$Record.$Key] = $Record
        }
    }

    return $Lookup
}

function Get-PDARecordTags {
    param([object]$Record)

    if ($null -eq $Record -or -not ($Record.PSObject.Properties.Name -contains "tags")) {
        return @()
    }

    return @($Record.tags) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
}

function Test-PDARecordTagMatch {
    param(
        [object]$Record,
        [string[]]$Tags
    )

    if (-not $Tags -or @($Tags).Count -eq 0) {
        return $true
    }

    $RecordTags = @(Get-PDARecordTags -Record $Record)
    if ($RecordTags.Count -eq 0) {
        return $false
    }

    foreach ($Tag in $Tags) {
        $Matched = $false
        foreach ($RecordTag in $RecordTags) {
            if ([string]$RecordTag -ieq [string]$Tag) {
                $Matched = $true
                break
            }
        }

        if (-not $Matched) {
            return $false
        }
    }

    return $true
}

function Test-PDAContainsAny {
    param(
        [string]$Value,
        [string[]]$Needles
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    foreach ($Needle in $Needles) {
        if ([string]::IsNullOrWhiteSpace([string]$Needle)) {
            continue
        }

        if ($Value -match [regex]::Escape([string]$Needle)) {
            return $true
        }
    }

    return $false
}

function Import-PDAArtifactIndexForRetrieval {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $IndexPath = Join-Path $Root "PDA_ArtifactIndex.json"
    return Read-PDAJsonFile -Path $IndexPath -NotFoundMessage "PDA artifact index not found: $IndexPath" -ParseMessage "PDA artifact index JSON could not be parsed at '$IndexPath'."
}

function Import-PDAMemoryIndexForRetrieval {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $IndexPath = Join-Path $Root "PDA_MemoryIndex.json"
    return Read-PDAJsonFile -Path $IndexPath -NotFoundMessage "PDA memory index not found: $IndexPath" -ParseMessage "PDA memory index JSON could not be parsed at '$IndexPath'."
}

function Import-PDATaskOntologyForRetrieval {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    . (Join-Path $PSScriptRoot "PDA_TaskOntology.ps1")
    return Import-PDATaskOntology -Root $Root
}

function Import-PDALifecycleForRetrieval {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return Import-PDALifecyclePolicy -Root $Root
}

function Import-PDAWorkerRegistryForRetrieval {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    . (Join-Path $PSScriptRoot "PDA_TaskOntology.ps1")
    return Get-PDAWorkerRegistry -Root $Root
}

function Get-PDAArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [string]$WorkerName = "",

        [Parameter(Mandatory = $false)]
        [string]$Category = "",

        [Parameter(Mandatory = $false)]
        [string[]]$Tags = @(),

        [Parameter(Mandatory = $false)]
        [string]$ArtifactType = "",

        [Parameter(Mandatory = $false)]
        [string]$Lineage = "",

        [Parameter(Mandatory = $false)]
        [string]$LifecycleState = "",

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10000)]
        [int]$Latest
    )

    $Index = Import-PDAArtifactIndexForRetrieval -Root $Root
    $LifecyclePolicy = Import-PDALifecycleForRetrieval -Root $Root
    if ($null -eq $Index.artifacts -or $Index.artifacts -isnot [System.Array]) {
        throw "PDA artifact index 'artifacts' must be an array."
    }

    $Artifacts = @($Index.artifacts)

    if (-not [string]::IsNullOrWhiteSpace($WorkerName)) {
        $Artifacts = @($Artifacts | Where-Object { [string]$_.worker_name -eq $WorkerName })
    }

    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        $Artifacts = @($Artifacts | Where-Object { [string]$_.category -eq $Category })
    }

    if (-not [string]::IsNullOrWhiteSpace($ArtifactType)) {
        $Artifacts = @($Artifacts | Where-Object { [string]$_.artifact_type -eq $ArtifactType })
    }

    if (-not [string]::IsNullOrWhiteSpace($Lineage)) {
        $Artifacts = @($Artifacts | Where-Object {
            ([string]$_.artifact_id -eq $Lineage) -or
            ([string]$_.source_task_id -eq $Lineage) -or
            ([string]$_.source_artifact_id -eq $Lineage) -or
            ([string]$_.lineage_id -eq $Lineage)
        })
    }

    if (-not [string]::IsNullOrWhiteSpace($LifecycleState)) {
        $Artifacts = @($Artifacts | Where-Object {
            [string](Get-PDALifecycleRecordState -Record $_ -Policy $LifecyclePolicy -RecordType "artifact") -eq $LifecycleState
        })
    }

    if ($Tags -and @($Tags).Count -gt 0) {
        $Artifacts = @($Artifacts | Where-Object { Test-PDARecordTagMatch -Record $_ -Tags $Tags })
    }

    $Artifacts = @($Artifacts | Sort-Object -Property @{ Expression = { Get-PDARetrievalDate $_.created_at } } -Descending)
    if ($PSBoundParameters.ContainsKey("Latest")) {
        $Artifacts = @($Artifacts | Select-Object -First $Latest)
    }

    return $Artifacts
}

function Get-PDAMemory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [string]$Category = "",

        [Parameter(Mandatory = $false)]
        [string[]]$Tags = @(),

        [Parameter(Mandatory = $false)]
        [string]$SourceArtifactId = "",

        [Parameter(Mandatory = $false)]
        [string]$Status = "",

        [Parameter(Mandatory = $false)]
        [string]$MemoryType = "",

        [Parameter(Mandatory = $false)]
        [string]$LifecycleState = "",

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10000)]
        [int]$Latest
    )

    $Index = Import-PDAMemoryIndexForRetrieval -Root $Root
    $LifecyclePolicy = Import-PDALifecycleForRetrieval -Root $Root
    if ($null -eq $Index.memories -or $Index.memories -isnot [System.Array]) {
        throw "PDA memory index 'memories' must be an array."
    }

    $Memories = @($Index.memories)

    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        $Memories = @($Memories | Where-Object { [string]$_.category -eq $Category })
    }

    if (-not [string]::IsNullOrWhiteSpace($MemoryType)) {
        $Memories = @($Memories | Where-Object { [string]$_.memory_type -eq $MemoryType })
    }

    if (-not [string]::IsNullOrWhiteSpace($LifecycleState)) {
        $Memories = @($Memories | Where-Object {
            [string](Get-PDALifecycleRecordState -Record $_ -Policy $LifecyclePolicy -RecordType "memory") -eq $LifecycleState
        })
    }

    if (-not [string]::IsNullOrWhiteSpace($SourceArtifactId)) {
        $Memories = @($Memories | Where-Object { [string]$_.source_artifact_id -eq $SourceArtifactId })
    }

    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        $Memories = @($Memories | Where-Object {
            ([string]$_.status -eq $Status) -or ([string]$_.memory_status -eq $Status)
        })
    }

    if ($Tags -and @($Tags).Count -gt 0) {
        $Memories = @($Memories | Where-Object { Test-PDARecordTagMatch -Record $_ -Tags $Tags })
    }

    $Memories = @($Memories | Sort-Object -Property @{ Expression = { Get-PDARetrievalDate $_.created_at } } -Descending)
    if ($PSBoundParameters.ContainsKey("Latest")) {
        $Memories = @($Memories | Select-Object -First $Latest)
    }

    return $Memories
}

function Get-PDATaskOntologyEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [string]$Command = "",

        [Parameter(Mandatory = $false)]
        [string]$Intent = "",

        [Parameter(Mandatory = $false)]
        [string]$AllowedWorker = "",

        [Parameter(Mandatory = $false)]
        [ValidateSet("category_1", "category_2")]
        [string]$Classification = ""
    )

    $Ontology = Import-PDATaskOntologyForRetrieval -Root $Root
    $Entries = @($Ontology.task_intents)

    if (-not [string]::IsNullOrWhiteSpace($Command)) {
        $Entries = @($Entries | Where-Object { [string]$_.command -eq $Command })
    }

    if (-not [string]::IsNullOrWhiteSpace($Intent)) {
        $Entries = @($Entries | Where-Object { [string]$_.intent -eq $Intent -or [string]$_.task_type -eq $Intent })
    }

    if (-not [string]::IsNullOrWhiteSpace($AllowedWorker)) {
        $Entries = @($Entries | Where-Object { @($_.allowed_workers) -contains $AllowedWorker })
    }

    if (-not [string]::IsNullOrWhiteSpace($Classification)) {
        $Entries = @($Entries | Where-Object { @($_.supported_categories) -contains $Classification })
    }

    return $Entries
}

function Get-PDAWorkerCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [string]$Capability = "",

        [Parameter(Mandatory = $false)]
        [string]$WorkerName = "",

        [Parameter(Mandatory = $false)]
        [string]$Command = "",

        [Parameter(Mandatory = $false)]
        [ValidateSet("category_1", "category_2")]
        [string]$Category = "",

        [Parameter(Mandatory = $false)]
        [ValidateSet("none", "human_approval", "blocked")]
        [string]$ApprovalRequirement = ""
    )

    $Registry = Import-PDAWorkerRegistryForRetrieval -Root $Root
    $Workers = @($Registry.workers)

    if (-not [string]::IsNullOrWhiteSpace($WorkerName)) {
        $Workers = @($Workers | Where-Object { [string]$_.worker_name -eq $WorkerName })
    }

    if (-not [string]::IsNullOrWhiteSpace($Command)) {
        $Workers = @($Workers | Where-Object { [string]$_.command -eq $Command })
    }

    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        $Workers = @($Workers | Where-Object { @($_.category_support) -contains $Category })
    }

    if (-not [string]::IsNullOrWhiteSpace($Capability)) {
        $Workers = @($Workers | Where-Object {
            $SearchText = @(
                [string]$_.worker_name,
                [string]$_.command,
                [string]$_.purpose,
                [string]$_.routing_surface,
                [string]$_.status,
                (@($_.accepted_input_modes) -join ' '),
                (@($_.safety_constraints) -join ' '),
                (@($_.output_locations) -join ' ')
            ) -join ' '

            $SearchText -match [regex]::Escape($Capability)
        })
    }

    $OntologyEntries = @()
    if (-not [string]::IsNullOrWhiteSpace($Command)) {
        $OntologyEntries = @(Get-PDATaskOntologyEntry -Root $Root -Command $Command)
    }
    else {
        $OntologyEntries = @(Get-PDATaskOntologyEntry -Root $Root)
    }

    $Results = foreach ($Worker in $Workers) {
        $WorkerOntology = @($OntologyEntries | Where-Object { [string]$_.command -eq [string]$Worker.command } | Select-Object -First 1)
        $WorkerOntology = if ($WorkerOntology.Count -gt 0) { $WorkerOntology[0] } else { $null }

        if ($null -eq $WorkerOntology -and -not [string]::IsNullOrWhiteSpace($Command)) {
            continue
        }

        $ApprovalMap = [ordered]@{}
        if ($WorkerOntology) {
            foreach ($CategoryName in @("category_1", "category_2")) {
                if ($WorkerOntology.PSObject.Properties.Name -contains "required_approvals") {
                    $ApprovalMap[$CategoryName] = [string]$WorkerOntology.required_approvals.$CategoryName
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($ApprovalRequirement)) {
            $ApprovalMatch = $false
            if ($ApprovalMap.Count -gt 0) {
                foreach ($Value in $ApprovalMap.Values) {
                    if ([string]$Value -eq $ApprovalRequirement) {
                        $ApprovalMatch = $true
                        break
                    }
                }
            }

            if (-not $ApprovalMatch) {
                continue
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($Category) -and $WorkerOntology) {
            $CategoryApproval = if ($WorkerOntology.PSObject.Properties.Name -contains "required_approvals") {
                [string]$WorkerOntology.required_approvals.$Category
            }
            else {
                ""
            }

            if (-not (@($Worker.category_support) -contains $Category)) {
                continue
            }
        }

        [pscustomobject]@{
            worker_name          = [string]$Worker.worker_name
            command              = [string]$Worker.command
            purpose              = [string]$Worker.purpose
            routing_surface      = [string]$Worker.routing_surface
            cloud_capable        = [bool]$Worker.cloud_capable
            status               = [string]$Worker.status
            category_support     = @($Worker.category_support)
            accepted_input_modes = @($Worker.accepted_input_modes)
            output_locations     = @($Worker.output_locations)
            matched_capability   = [string]$Capability
            ontology_task_type    = if ($WorkerOntology) { [string]$WorkerOntology.task_type } else { "" }
            ontology_intent      = if ($WorkerOntology) { [string]$WorkerOntology.intent } else { "" }
            approval_requirements = $ApprovalMap
        }
    }

    return @($Results)
}

function Test-PDARetrievalIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [switch]$IncludeTestRecords
    )

    $Artifacts = @(Get-PDAArtifacts -Root $Root)
    $Memories = @(Get-PDAMemory -Root $Root)
    $Ontology = Import-PDATaskOntologyForRetrieval -Root $Root
    $Registry = Import-PDAWorkerRegistryForRetrieval -Root $Root

    $ArtifactLookup = Get-PDAIndexLookup -Records $Artifacts -Key "artifact_id"
    $MemoryLookup = Get-PDAIndexLookup -Records $Memories -Key "memory_id"
    $WorkerLookup = Get-PDAIndexLookup -Records @($Registry.workers) -Key "worker_name"

    $MissingReferences = New-Object System.Collections.Generic.List[object]
    $OrphanedLineage = New-Object System.Collections.Generic.List[object]
    $InvalidOntologyReferences = New-Object System.Collections.Generic.List[object]
    $InvalidWorkerMappings = New-Object System.Collections.Generic.List[object]
    $SuppressedTestIssues = New-Object System.Collections.Generic.List[object]

    foreach ($Artifact in $Artifacts) {
        $IsTestRecord = ([string]$Artifact.category -eq "test") -or ([string]$Artifact.artifact_type -match '^test')
        $ResolvedPath = if ([System.IO.Path]::IsPathRooted([string]$Artifact.artifact_path)) { [string]$Artifact.artifact_path } else { Join-Path $Root ([string]$Artifact.artifact_path) }

        if ([string]::IsNullOrWhiteSpace([string]$Artifact.artifact_path)) {
            if ($IncludeTestRecords -or -not $IsTestRecord) {
                $MissingReferences.Add([pscustomobject]@{
                    type = "missing_artifact_path"
                    artifact_id = [string]$Artifact.artifact_id
                    detail = "Missing artifact_path"
                })
            }
            else {
                $SuppressedTestIssues.Add([pscustomobject]@{
                    type = "missing_artifact_path"
                    artifact_id = [string]$Artifact.artifact_id
                })
            }
        }
        elseif (-not (Test-Path -Path $ResolvedPath -PathType Leaf)) {
            if ($IncludeTestRecords -or -not $IsTestRecord) {
                $MissingReferences.Add([pscustomobject]@{
                    type = "broken_artifact_path"
                    artifact_id = [string]$Artifact.artifact_id
                    detail = [string]$Artifact.artifact_path
                })
            }
            else {
                $SuppressedTestIssues.Add([pscustomobject]@{
                    type = "broken_artifact_path"
                    artifact_id = [string]$Artifact.artifact_id
                })
            }
        }

        if ($Artifact.PSObject.Properties.Name -contains "source_artifact_id" -and -not [string]::IsNullOrWhiteSpace([string]$Artifact.source_artifact_id)) {
            if (-not $ArtifactLookup.ContainsKey([string]$Artifact.source_artifact_id)) {
                if ($IncludeTestRecords -or -not $IsTestRecord) {
                    $OrphanedLineage.Add([pscustomobject]@{
                        type = "orphaned_artifact_lineage"
                        artifact_id = [string]$Artifact.artifact_id
                        source_artifact_id = [string]$Artifact.source_artifact_id
                    })
                }
                else {
                    $SuppressedTestIssues.Add([pscustomobject]@{
                        type = "orphaned_artifact_lineage"
                        artifact_id = [string]$Artifact.artifact_id
                    })
                }
            }
        }
    }

    foreach ($Memory in $Memories) {
        $IsTestRecord = ([string]$Memory.category -eq "test") -or ([string]$Memory.memory_type -match '^test')
        $ResolvedPath = if ([System.IO.Path]::IsPathRooted([string]$Memory.source_path)) { [string]$Memory.source_path } else { Join-Path $Root ([string]$Memory.source_path) }

        if ([string]::IsNullOrWhiteSpace([string]$Memory.source_path)) {
            if ($IncludeTestRecords -or -not $IsTestRecord) {
                $MissingReferences.Add([pscustomobject]@{
                    type = "missing_source_path"
                    memory_id = [string]$Memory.memory_id
                    detail = "Missing source_path"
                })
            }
            else {
                $SuppressedTestIssues.Add([pscustomobject]@{
                    type = "missing_source_path"
                    memory_id = [string]$Memory.memory_id
                })
            }
        }
        elseif (-not (Test-Path -Path $ResolvedPath -PathType Leaf)) {
            if ($IncludeTestRecords -or -not $IsTestRecord) {
                $MissingReferences.Add([pscustomobject]@{
                    type = "broken_source_path"
                    memory_id = [string]$Memory.memory_id
                    detail = [string]$Memory.source_path
                })
            }
            else {
                $SuppressedTestIssues.Add([pscustomobject]@{
                    type = "broken_source_path"
                    memory_id = [string]$Memory.memory_id
                })
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$Memory.source_artifact_id)) {
            if ($IncludeTestRecords -or -not $IsTestRecord) {
                $MissingReferences.Add([pscustomobject]@{
                    type = "missing_source_artifact_id"
                    memory_id = [string]$Memory.memory_id
                    detail = "Missing source_artifact_id"
                })
            }
            else {
                $SuppressedTestIssues.Add([pscustomobject]@{
                    type = "missing_source_artifact_id"
                    memory_id = [string]$Memory.memory_id
                })
            }
        }
        elseif (-not $ArtifactLookup.ContainsKey([string]$Memory.source_artifact_id)) {
            if ($IncludeTestRecords -or -not $IsTestRecord) {
                $OrphanedLineage.Add([pscustomobject]@{
                    type = "orphaned_memory_lineage"
                    memory_id = [string]$Memory.memory_id
                    source_artifact_id = [string]$Memory.source_artifact_id
                })
            }
            else {
                $SuppressedTestIssues.Add([pscustomobject]@{
                    type = "orphaned_memory_lineage"
                    memory_id = [string]$Memory.memory_id
                })
            }
        }
    }

    foreach ($Entry in @($Ontology.task_intents)) {
        foreach ($WorkerName in @($Entry.allowed_workers)) {
            if (-not $WorkerLookup.ContainsKey([string]$WorkerName)) {
                $InvalidOntologyReferences.Add([pscustomobject]@{
                    type = "missing_worker_reference"
                    task_type = [string]$Entry.task_type
                    command = [string]$Entry.command
                    worker_name = [string]$WorkerName
                    reason = "Allowed worker is missing from registry."
                })
                continue
            }

            $Worker = $WorkerLookup[[string]$WorkerName]
            if (($Entry.supported_categories -contains "category_2") -and ([string]$Worker.routing_surface -ne "local-only" -or [bool]$Worker.cloud_capable)) {
                $InvalidOntologyReferences.Add([pscustomobject]@{
                    type = "category2_surface_violation"
                    task_type = [string]$Entry.task_type
                    command = [string]$Entry.command
                    worker_name = [string]$Worker.worker_name
                    reason = "Category 2 ontology entry must remain local-only."
                })
            }
        }
    }

    foreach ($Worker in @($Registry.workers)) {
        $MatchingEntry = @($Ontology.task_intents | Where-Object { [string]$_.command -eq [string]$Worker.command } | Select-Object -First 1)
        $MatchingEntry = if ($MatchingEntry.Count -gt 0) { $MatchingEntry[0] } else { $null }

        if ($null -eq $MatchingEntry) {
            $InvalidWorkerMappings.Add([pscustomobject]@{
                type = "missing_ontology_mapping"
                worker_name = [string]$Worker.worker_name
                command = [string]$Worker.command
                reason = "Worker command is not present in the ontology."
            })
            continue
        }

        if (-not (@($MatchingEntry.allowed_workers) -contains [string]$Worker.worker_name)) {
            $InvalidWorkerMappings.Add([pscustomobject]@{
                type = "missing_allowed_worker_link"
                worker_name = [string]$Worker.worker_name
                command = [string]$Worker.command
                reason = "Worker is not listed as an allowed worker for its ontology entry."
            })
        }
    }

    $ArtifactCount = @($Artifacts).Count
    $MemoryCount = @($Memories).Count
    $OntologyCount = @($Ontology.task_intents).Count
    $WorkerCount = @($Registry.workers).Count
    $MissingReferenceCount = $MissingReferences.Count
    $OrphanCount = $OrphanedLineage.Count
    $InvalidOntologyReferenceCount = $InvalidOntologyReferences.Count
    $InvalidWorkerMappingCount = $InvalidWorkerMappings.Count
    $Status = if ($MissingReferenceCount -eq 0 -and $OrphanCount -eq 0 -and $InvalidOntologyReferenceCount -eq 0 -and $InvalidWorkerMappingCount -eq 0) { "pass" } else { "fail" }

    return [pscustomobject]@{
        generated_at = (Get-Date).ToString("s")
        root = $Root
        artifact_count = $ArtifactCount
        memory_count = $MemoryCount
        ontology_count = $OntologyCount
        worker_count = $WorkerCount
        missing_reference_count = $MissingReferenceCount
        orphan_count = $OrphanCount
        invalid_ontology_reference_count = $InvalidOntologyReferenceCount
        invalid_worker_mapping_count = $InvalidWorkerMappingCount
        suppressed_test_issue_count = $SuppressedTestIssues.Count
        lineage_health = if ($OrphanCount -eq 0) { "healthy" } else { "degraded" }
        status = $Status
        missing_references = @($MissingReferences.ToArray())
        orphaned_lineage = @($OrphanedLineage.ToArray())
        invalid_ontology_references = @($InvalidOntologyReferences.ToArray())
        invalid_worker_mappings = @($InvalidWorkerMappings.ToArray())
        suppressed_test_issues = @($SuppressedTestIssues.ToArray())
    }
}
