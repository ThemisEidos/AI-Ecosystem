function Get-PDAMemoryTaxonomyPath {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Join-Path $Root "Scripts\PDA_MemoryTaxonomy.json")
}

function Get-PDAMemoryTaxonomySchemaPath {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Join-Path $Root "Scripts\PDA_MemoryTaxonomy.schema.json")
}

function Read-PDAMemoryTaxonomyJsonFile {
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

function Import-PDAMemoryTaxonomy {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $TaxonomyPath = Get-PDAMemoryTaxonomyPath -Root $Root
    return Read-PDAMemoryTaxonomyJsonFile -Path $TaxonomyPath -NotFoundMessage "PDA memory taxonomy not found: $TaxonomyPath" -ParseMessage "PDA memory taxonomy JSON could not be parsed at '$TaxonomyPath'."
}

function Import-PDAMemoryIndexForTaxonomy {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $IndexPath = Join-Path $Root "PDA_MemoryIndex.json"
    return Read-PDAMemoryTaxonomyJsonFile -Path $IndexPath -NotFoundMessage "PDA memory index not found: $IndexPath" -ParseMessage "PDA memory index JSON could not be parsed at '$IndexPath'."
}

function Import-PDAArtifactIndexForTaxonomy {
    param(
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $IndexPath = Join-Path $Root "PDA_ArtifactIndex.json"
    return Read-PDAMemoryTaxonomyJsonFile -Path $IndexPath -NotFoundMessage "PDA artifact index not found: $IndexPath" -ParseMessage "PDA artifact index JSON could not be parsed at '$IndexPath'."
}

function Test-PDAMemoryTagValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tag,

        [Parameter(Mandatory = $true)]
        [object]$Taxonomy
    )

    $Policy = $Taxonomy.tag_policy
    $LegacyPattern = [string]$Policy.legacy_tag_pattern
    $NamespacedPattern = [string]$Policy.namespaced_tag_pattern
    $AllowedNamespaces = @($Policy.allowed_namespaces) | ForEach-Object { [string]$_ }

    if ([string]::IsNullOrWhiteSpace($Tag)) {
        return [pscustomobject]@{
            valid  = $false
            reason = "Tag is blank."
            namespace = ""
        }
    }

    if ($Tag -match ":") {
        if ($Tag -notmatch $NamespacedPattern) {
            return [pscustomobject]@{
                valid  = $false
                reason = "Namespaced tag does not match the taxonomy pattern."
                namespace = ""
            }
        }

        $Namespace = ($Tag -split ":", 2)[0]
        if (-not ($AllowedNamespaces -contains [string]$Namespace)) {
            return [pscustomobject]@{
                valid  = $false
                reason = "Tag namespace is not allowed by the taxonomy."
                namespace = [string]$Namespace
            }
        }

        return [pscustomobject]@{
            valid  = $true
            reason = ""
            namespace = [string]$Namespace
        }
    }

    if ($Tag -notmatch $LegacyPattern) {
        return [pscustomobject]@{
            valid  = $false
            reason = "Legacy tag does not match the taxonomy pattern."
            namespace = ""
        }
    }

    return [pscustomobject]@{
        valid  = $true
        reason = ""
        namespace = ""
    }
}

function Get-PDAMemoryTaxonomyDefaults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$MemoryType = "",

        [Parameter(Mandatory = $false)]
        [string]$Category = "",

        [Parameter(Mandatory = $false)]
        [string]$SourceArtifactId = "",

        [Parameter(Mandatory = $false)]
        [string]$SourcePath = ""
    )

    $IsTestRecord = (-not [string]::IsNullOrWhiteSpace($Category) -and $Category -eq "test") -or
        (-not [string]::IsNullOrWhiteSpace($MemoryType) -and ($MemoryType -match '^(?i:test|retrieval-seed)'))

    $SourceType = "manual"
    if (-not [string]::IsNullOrWhiteSpace($SourceArtifactId)) {
        $SourceType = "artifact"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
        $SourceType = "file"
    }

    if ($IsTestRecord) {
        return [pscustomobject]@{
            status          = "test"
            confidence      = 0.5
            sensitivity     = "test"
            source_type     = "seed"
            lifecycle_state = "test"
        }
    }

    return [pscustomobject]@{
        status          = "active"
        confidence      = 0.75
        sensitivity     = "standard"
        source_type     = $SourceType
        lifecycle_state = "active"
    }
}

function Assert-PDAMemoryRecordTaxonomyWritable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Record,

        [Parameter(Mandatory = $true)]
        [object]$Taxonomy,

        [Parameter(Mandatory = $true)]
        [hashtable]$ArtifactLookup,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $Validation = Test-PDAMemoryRecordAgainstTaxonomy -Record $Record -Taxonomy $Taxonomy -ArtifactLookup $ArtifactLookup -Root $Root
    if (-not $Validation.valid) {
        $IssueLines = @($Validation.issues | ForEach-Object {
            "- $($_.issue_type): $($_.field) $($_.detail)"
        })
        throw ("PDA memory record failed taxonomy validation.`n" + ($IssueLines -join [Environment]::NewLine))
    }

    return $Validation
}

function Test-PDAMemoryTaxonomyContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $TaxonomyPath = Get-PDAMemoryTaxonomyPath -Root $Root
    $SchemaPath = Get-PDAMemoryTaxonomySchemaPath -Root $Root
    $Issues = New-Object System.Collections.Generic.List[object]

    foreach ($Path in @($TaxonomyPath, $SchemaPath)) {
        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            $Issues.Add([pscustomobject]@{
                issue_type = "missing_file"
                path       = $Path
                detail     = "Missing required file"
            })
        }
    }

    if ($Issues.Count -gt 0) {
        return [pscustomobject]@{
            valid         = $false
            issue_count   = $Issues.Count
            issues        = @($Issues)
            taxonomy_path = $TaxonomyPath
            schema_path   = $SchemaPath
        }
    }

    $Taxonomy = Import-PDAMemoryTaxonomy -Root $Root
    $Schema = Read-PDAMemoryTaxonomyJsonFile -Path $SchemaPath -NotFoundMessage "PDA memory taxonomy schema not found: $SchemaPath" -ParseMessage "PDA memory taxonomy schema JSON could not be parsed at '$SchemaPath'."

    foreach ($Property in @(
        "schema_version",
        "taxonomy_name",
        "taxonomy_version",
        "generated_at",
        "required_fields",
        "memory_types",
        "categories",
        "statuses",
        "confidence_scale",
        "sensitivities",
        "source_types",
        "lifecycle_states",
        "tag_policy",
        "index_integration"
    )) {
        if (-not ($Taxonomy.PSObject.Properties.Name -contains $Property)) {
            $Issues.Add([pscustomobject]@{
                issue_type = "missing_property"
                path       = $TaxonomyPath
                property   = $Property
                detail     = "Missing taxonomy property"
            })
        }
    }

    $RequiredFields = @($Taxonomy.required_fields) | ForEach-Object { [string]$_ }
    $ExpectedRequiredFields = @(
        "memory_id",
        "created_at",
        "updated_at",
        "memory_type",
        "category",
        "title",
        "summary",
        "source_artifact_id",
        "source_path",
        "status",
        "confidence",
        "sensitivity",
        "source_type",
        "lifecycle_state",
        "tags"
    )
    foreach ($Field in $ExpectedRequiredFields) {
        if (-not ($RequiredFields -contains $Field)) {
            $Issues.Add([pscustomobject]@{
                issue_type = "missing_required_field_definition"
                field      = $Field
                detail     = "Required field is missing from the taxonomy."
            })
        }
    }

    $AllowedConfidence = $Taxonomy.confidence_scale
    if ($null -eq $AllowedConfidence -or $AllowedConfidence.minimum -gt $AllowedConfidence.maximum) {
        $Issues.Add([pscustomobject]@{
            issue_type = "invalid_confidence_scale"
            detail     = "Confidence scale is invalid."
        })
    }

    if (($Taxonomy.memory_types | Sort-Object -Unique).Count -ne @($Taxonomy.memory_types).Count) {
        $Issues.Add([pscustomobject]@{
            issue_type = "duplicate_memory_types"
            detail     = "Duplicate memory_type values were found."
        })
    }

    if (($Taxonomy.categories | Sort-Object -Unique).Count -ne @($Taxonomy.categories).Count) {
        $Issues.Add([pscustomobject]@{
            issue_type = "duplicate_categories"
            detail     = "Duplicate category values were found."
        })
    }

    if (($Taxonomy.statuses | Sort-Object -Unique).Count -ne @($Taxonomy.statuses).Count) {
        $Issues.Add([pscustomobject]@{
            issue_type = "duplicate_statuses"
            detail     = "Duplicate status values were found."
        })
    }

    if (($Taxonomy.sensitivities | Sort-Object -Unique).Count -ne @($Taxonomy.sensitivities).Count) {
        $Issues.Add([pscustomobject]@{
            issue_type = "duplicate_sensitivities"
            detail     = "Duplicate sensitivity values were found."
        })
    }

    if (($Taxonomy.source_types | Sort-Object -Unique).Count -ne @($Taxonomy.source_types).Count) {
        $Issues.Add([pscustomobject]@{
            issue_type = "duplicate_source_types"
            detail     = "Duplicate source_type values were found."
        })
    }

    if (($Taxonomy.lifecycle_states | Sort-Object -Unique).Count -ne @($Taxonomy.lifecycle_states).Count) {
        $Issues.Add([pscustomobject]@{
            issue_type = "duplicate_lifecycle_states"
            detail     = "Duplicate lifecycle_state values were found."
        })
    }

    return [pscustomobject]@{
        valid              = ($Issues.Count -eq 0)
        issue_count        = $Issues.Count
        issues             = @($Issues.ToArray())
        taxonomy_path      = $TaxonomyPath
        schema_path        = $SchemaPath
        taxonomy_name      = [string]$Taxonomy.taxonomy_name
        taxonomy_version   = [string]$Taxonomy.taxonomy_version
        required_field_count = @($Taxonomy.required_fields).Count
        memory_type_count  = @($Taxonomy.memory_types).Count
        category_count     = @($Taxonomy.categories).Count
        status_count       = @($Taxonomy.statuses).Count
        sensitivity_count  = @($Taxonomy.sensitivities).Count
        source_type_count  = @($Taxonomy.source_types).Count
        lifecycle_state_count = @($Taxonomy.lifecycle_states).Count
        allowed_namespace_count = @($Taxonomy.tag_policy.allowed_namespaces).Count
    }
}

function Test-PDAMemoryRecordAgainstTaxonomy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Record,

        [Parameter(Mandatory = $true)]
        [object]$Taxonomy,

        [Parameter(Mandatory = $true)]
        [hashtable]$ArtifactLookup,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $Issues = New-Object System.Collections.Generic.List[object]
    $RequiredFields = @($Taxonomy.required_fields) | ForEach-Object { [string]$_ }
    $RecordId = if ($Record.PSObject.Properties.Name -contains "memory_id" -and $Record.memory_id) { [string]$Record.memory_id } else { "(missing)" }

    foreach ($Field in $RequiredFields) {
        $HasField = $Record.PSObject.Properties.Name -contains $Field
        $Value = if ($HasField) { $Record.$Field } else { $null }

        if ($Field -eq "tags") {
            $TagValues = @()
            if ($HasField -and $null -ne $Value) {
                $TagValues = @($Value) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
            }

            if (-not $HasField -or $TagValues.Count -eq 0) {
                $Issues.Add([pscustomobject]@{
                    issue_type = "missing_field"
                    memory_id  = $RecordId
                    field      = $Field
                    detail     = "Missing required field"
                })
            }
            continue
        }

        if (-not $HasField -or [string]::IsNullOrWhiteSpace([string]$Value)) {
            $Issues.Add([pscustomobject]@{
                issue_type = "missing_field"
                memory_id  = $RecordId
                field      = $Field
                detail     = "Missing required field"
            })
        }
    }

    $AllowedMemoryTypes = @($Taxonomy.memory_types) | ForEach-Object { [string]$_ }
    $AllowedCategories = @($Taxonomy.categories) | ForEach-Object { [string]$_ }
    $AllowedStatuses = @($Taxonomy.statuses) | ForEach-Object { [string]$_ }
    $AllowedSensitivities = @($Taxonomy.sensitivities) | ForEach-Object { [string]$_ }
    $AllowedSourceTypes = @($Taxonomy.source_types) | ForEach-Object { [string]$_ }
    $AllowedLifecycleStates = @($Taxonomy.lifecycle_states) | ForEach-Object { [string]$_ }
    $AllowedConfidence = $Taxonomy.confidence_scale

    if (-not ($Record.PSObject.Properties.Name -contains "memory_type") -or [string]::IsNullOrWhiteSpace([string]$Record.memory_type)) {
        # Already captured as missing_field.
    }
    elseif (-not ($AllowedMemoryTypes -contains [string]$Record.memory_type)) {
        $Issues.Add([pscustomobject]@{
            issue_type = "invalid_value"
            memory_id  = $RecordId
            field      = "memory_type"
            detail     = [string]$Record.memory_type
        })
    }

    if (-not ($Record.PSObject.Properties.Name -contains "category") -or [string]::IsNullOrWhiteSpace([string]$Record.category)) {
        # Already captured as missing_field.
    }
    elseif (-not ($AllowedCategories -contains [string]$Record.category)) {
        $Issues.Add([pscustomobject]@{
            issue_type = "invalid_value"
            memory_id  = $RecordId
            field      = "category"
            detail     = [string]$Record.category
        })
    }

    if ($Record.PSObject.Properties.Name -contains "status" -and -not [string]::IsNullOrWhiteSpace([string]$Record.status)) {
        if (-not ($AllowedStatuses -contains [string]$Record.status)) {
            $Issues.Add([pscustomobject]@{
                issue_type = "invalid_value"
                memory_id  = $RecordId
                field      = "status"
                detail     = [string]$Record.status
            })
        }
    }

    if ($Record.PSObject.Properties.Name -contains "sensitivity" -and -not [string]::IsNullOrWhiteSpace([string]$Record.sensitivity)) {
        if (-not ($AllowedSensitivities -contains [string]$Record.sensitivity)) {
            $Issues.Add([pscustomobject]@{
                issue_type = "invalid_value"
                memory_id  = $RecordId
                field      = "sensitivity"
                detail     = [string]$Record.sensitivity
            })
        }
    }

    if ($Record.PSObject.Properties.Name -contains "source_type" -and -not [string]::IsNullOrWhiteSpace([string]$Record.source_type)) {
        if (-not ($AllowedSourceTypes -contains [string]$Record.source_type)) {
            $Issues.Add([pscustomobject]@{
                issue_type = "invalid_value"
                memory_id  = $RecordId
                field      = "source_type"
                detail     = [string]$Record.source_type
            })
        }
    }

    if ($Record.PSObject.Properties.Name -contains "lifecycle_state" -and -not [string]::IsNullOrWhiteSpace([string]$Record.lifecycle_state)) {
        if (-not ($AllowedLifecycleStates -contains [string]$Record.lifecycle_state)) {
            $Issues.Add([pscustomobject]@{
                issue_type = "invalid_value"
                memory_id  = $RecordId
                field      = "lifecycle_state"
                detail     = [string]$Record.lifecycle_state
            })
        }
    }

    if ($Record.PSObject.Properties.Name -contains "confidence" -and -not [string]::IsNullOrWhiteSpace([string]$Record.confidence)) {
        $ParsedConfidence = 0.0
        $ConfidenceText = [string]$Record.confidence
        if (-not [double]::TryParse($ConfidenceText, [ref]$ParsedConfidence)) {
            $Issues.Add([pscustomobject]@{
                issue_type = "invalid_value"
                memory_id  = $RecordId
                field      = "confidence"
                detail     = $ConfidenceText
            })
        }
        elseif ($ParsedConfidence -lt [double]$AllowedConfidence.minimum -or $ParsedConfidence -gt [double]$AllowedConfidence.maximum) {
            $Issues.Add([pscustomobject]@{
                issue_type = "invalid_value"
                memory_id  = $RecordId
                field      = "confidence"
                detail     = $ConfidenceText
            })
        }
    }

    if ($Record.PSObject.Properties.Name -contains "tags" -and $null -ne $Record.tags) {
        foreach ($Tag in @($Record.tags)) {
            $TagCheck = Test-PDAMemoryTagValue -Tag ([string]$Tag) -Taxonomy $Taxonomy
            if (-not $TagCheck.valid) {
                $Issues.Add([pscustomobject]@{
                    issue_type = "malformed_tag"
                    memory_id  = $RecordId
                    field      = "tags"
                    detail     = [string]$TagCheck.reason
                })
            }
        }
    }

    $SourcePath = if ($Record.PSObject.Properties.Name -contains "source_path") { [string]$Record.source_path } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
        $ResolvedSourcePath = if ([System.IO.Path]::IsPathRooted($SourcePath)) { $SourcePath } else { Join-Path $Root $SourcePath }
        if (-not (Test-Path -Path $ResolvedSourcePath -PathType Leaf)) {
            $Issues.Add([pscustomobject]@{
                issue_type = "broken_source_path"
                memory_id  = $RecordId
                field      = "source_path"
                detail     = $SourcePath
            })
        }
    }

    $SourceArtifactId = if ($Record.PSObject.Properties.Name -contains "source_artifact_id") { [string]$Record.source_artifact_id } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($SourceArtifactId)) {
        if (-not $ArtifactLookup.ContainsKey($SourceArtifactId)) {
            $Issues.Add([pscustomobject]@{
                issue_type = "orphaned_source_artifact_reference"
                memory_id  = $RecordId
                field      = "source_artifact_id"
                detail     = $SourceArtifactId
            })
        }
    }

    return [pscustomobject]@{
        memory_id           = $RecordId
        valid               = ($Issues.Count -eq 0)
        issue_count         = $Issues.Count
        issues              = @($Issues.ToArray())
        missing_field_count = @($Issues | Where-Object { $_.issue_type -eq "missing_field" }).Count
        invalid_value_count = @($Issues | Where-Object { $_.issue_type -eq "invalid_value" }).Count
        invalid_tag_count   = @($Issues | Where-Object { $_.issue_type -eq "malformed_tag" }).Count
        source_reference_issue_count = @($Issues | Where-Object { $_.issue_type -in @("broken_source_path", "orphaned_source_artifact_reference") }).Count
    }
}

function Test-PDAMemoryTaxonomyIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $TaxonomyReport = Test-PDAMemoryTaxonomyContract -Root $Root
    $Issues = New-Object System.Collections.Generic.List[object]

    if (-not $TaxonomyReport.valid) {
        foreach ($Issue in @($TaxonomyReport.issues)) {
            $Issues.Add($Issue)
        }
    }

    $Taxonomy = Import-PDAMemoryTaxonomy -Root $Root
    $ArtifactIndex = Import-PDAArtifactIndexForTaxonomy -Root $Root
    $MemoryIndex = Import-PDAMemoryIndexForTaxonomy -Root $Root

    if (-not ($ArtifactIndex.PSObject.Properties.Name -contains "artifacts")) {
        $Issues.Add([pscustomobject]@{
            issue_type = "missing_artifact_array"
            detail     = "Artifact index is missing artifacts array."
        })
        $ArtifactRecords = @()
    }
    else {
        $ArtifactRecords = @($ArtifactIndex.artifacts)
    }

    if (-not ($MemoryIndex.PSObject.Properties.Name -contains "memories")) {
        $Issues.Add([pscustomobject]@{
            issue_type = "missing_memory_array"
            detail     = "Memory index is missing memories array."
        })
        $MemoryRecords = @()
    }
    else {
        $MemoryRecords = @($MemoryIndex.memories)
    }

    $ArtifactLookup = @{}
    foreach ($Artifact in $ArtifactRecords) {
        if ($Artifact.PSObject.Properties.Name -contains "artifact_id" -and -not [string]::IsNullOrWhiteSpace([string]$Artifact.artifact_id)) {
            $ArtifactLookup[[string]$Artifact.artifact_id] = $Artifact
        }
    }

    $RecordReports = New-Object System.Collections.Generic.List[object]
    $DuplicateTracker = @{}

    foreach ($Record in $MemoryRecords) {
        $MemoryId = if ($Record.PSObject.Properties.Name -contains "memory_id" -and $Record.memory_id) { [string]$Record.memory_id } else { "(missing)" }
        if ($DuplicateTracker.ContainsKey($MemoryId)) {
            $Issues.Add([pscustomobject]@{
                issue_type = "duplicate_memory_id"
                memory_id  = $MemoryId
                field      = "memory_id"
                detail     = "Duplicate memory_id detected"
            })
        }
        else {
            $DuplicateTracker[$MemoryId] = $true
        }

        $RecordReport = Test-PDAMemoryRecordAgainstTaxonomy -Record $Record -Taxonomy $Taxonomy -ArtifactLookup $ArtifactLookup -Root $Root
        $RecordReports.Add($RecordReport)
        foreach ($Issue in @($RecordReport.issues)) {
            $Issues.Add($Issue)
        }
    }

    $TotalRecordCount = @($MemoryRecords).Count
    $ValidRecordCount = @($RecordReports | Where-Object { $_.valid }).Count
    $InvalidRecordCount = $TotalRecordCount - $ValidRecordCount
    $MissingFieldCount = @($Issues | Where-Object { $_.issue_type -eq "missing_field" }).Count
    $InvalidValueCount = @($Issues | Where-Object { $_.issue_type -eq "invalid_value" }).Count
    $InvalidTagCount = @($Issues | Where-Object { $_.issue_type -eq "malformed_tag" }).Count
    $SourceReferenceIssueCount = @($Issues | Where-Object { $_.issue_type -in @("broken_source_path", "orphaned_source_artifact_reference") }).Count
    $DuplicateMemoryIdCount = @($Issues | Where-Object { $_.issue_type -eq "duplicate_memory_id" }).Count
    $OrphanCount = @($Issues | Where-Object { $_.issue_type -eq "orphaned_source_artifact_reference" }).Count
    $Status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }

    return [pscustomobject]@{
        generated_at                  = (Get-Date).ToString("s")
        root                          = $Root
        status                        = $Status
        total_record_count            = $TotalRecordCount
        valid_record_count            = $ValidRecordCount
        invalid_record_count          = $InvalidRecordCount
        missing_field_count           = $MissingFieldCount
        invalid_value_count           = $InvalidValueCount
        invalid_tag_count             = $InvalidTagCount
        source_reference_issue_count  = $SourceReferenceIssueCount
        orphan_count                  = $OrphanCount
        duplicate_memory_id_count     = $DuplicateMemoryIdCount
        taxonomy                      = [pscustomobject]@{
            name        = [string]$TaxonomyReport.taxonomy_name
            version     = [string]$TaxonomyReport.taxonomy_version
            path        = [string]$TaxonomyReport.taxonomy_path
            schema_path = [string]$TaxonomyReport.schema_path
        }
        contract_valid                = [bool]$TaxonomyReport.valid
        contract_issue_count          = [int]$TaxonomyReport.issue_count
        contract_issues               = @($TaxonomyReport.issues)
        issues                        = @($Issues.ToArray())
        records                       = @($RecordReports.ToArray())
    }
}
