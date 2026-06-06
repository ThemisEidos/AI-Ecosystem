[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $true)]
    [string]$MemoryType,

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [string]$Summary,

    [Parameter(Mandatory = $true)]
    [string]$Category,

    [Parameter(Mandatory = $false)]
    [string]$SourceArtifactId = "",

    [Parameter(Mandatory = $false)]
    [string]$SourcePath = "",

    [Parameter(Mandatory = $false)]
    [string[]]$Tags = @(),

    [Parameter(Mandatory = $false)]
    [string]$Status = "",

    [Parameter(Mandatory = $false)]
    [object]$Confidence = "",

    [Parameter(Mandatory = $false)]
    [string]$Sensitivity = "",

    [Parameter(Mandatory = $false)]
    [string]$SourceType = "",

    [Parameter(Mandatory = $false)]
    [string]$LifecycleState = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "PDA_MemoryTaxonomy.ps1")

$RepoRoot = $Root
$IndexPath = Join-Path $RepoRoot "PDA_MemoryIndex.json"
$ArtifactIndexPath = Join-Path $RepoRoot "PDA_ArtifactIndex.json"

function New-PDAMemoryIndexFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Now = Get-Date -Format "o"
    $Index = [ordered]@{
        schema_version = "1.0"
        created_at     = $Now
        updated_at     = $Now
        memories       = @()
    }

    $Index | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

if (-not (Test-Path -Path $IndexPath -PathType Leaf)) {
    New-PDAMemoryIndexFile -Path $IndexPath
}

$Now = Get-Date -Format "o"

$Raw = Get-Content -Path $IndexPath -Raw
try {
    $Index = $Raw | ConvertFrom-Json
}
catch {
    throw "PDA memory index JSON could not be parsed at '$IndexPath'."
}

if (-not ($Index.PSObject.Properties.Name -contains "schema_version")) {
    throw "PDA memory index is missing 'schema_version'."
}

if (-not ($Index.PSObject.Properties.Name -contains "memories")) {
    throw "PDA memory index is missing 'memories'."
}

if ($null -eq $Index.memories -or $Index.memories -isnot [System.Array]) {
    throw "PDA memory index 'memories' must be an array."
}

$Taxonomy = Import-PDAMemoryTaxonomy -Root $RepoRoot
$RequiredTaxonomyValues = @($Taxonomy.memory_types) | ForEach-Object { [string]$_ }
if (-not ($RequiredTaxonomyValues -contains [string]$MemoryType)) {
    throw "Invalid memory_type '$MemoryType'."
}

$AllowedCategories = @($Taxonomy.categories) | ForEach-Object { [string]$_ }
if (-not ($AllowedCategories -contains [string]$Category)) {
    throw "Invalid category '$Category'."
}

$ArtifactLookup = @{}
if (-not [string]::IsNullOrWhiteSpace($SourceArtifactId)) {
    if (-not (Test-Path -Path $ArtifactIndexPath -PathType Leaf)) {
        throw "PDA artifact index not found for memory registration: $ArtifactIndexPath"
    }

    $ArtifactIndex = Get-Content -Path $ArtifactIndexPath -Raw | ConvertFrom-Json
    if (-not ($ArtifactIndex.PSObject.Properties.Name -contains "artifacts") -or $null -eq $ArtifactIndex.artifacts -or $ArtifactIndex.artifacts -isnot [System.Array]) {
        throw "PDA artifact index 'artifacts' must be an array."
    }

    foreach ($Artifact in @($ArtifactIndex.artifacts)) {
        if ($Artifact.PSObject.Properties.Name -contains "artifact_id" -and -not [string]::IsNullOrWhiteSpace([string]$Artifact.artifact_id)) {
            $ArtifactLookup[[string]$Artifact.artifact_id] = $Artifact
        }
    }

    if (-not $ArtifactLookup.ContainsKey([string]$SourceArtifactId)) {
        throw "Artifact not found for memory registration: $SourceArtifactId"
    }
}

$Defaults = Get-PDAMemoryTaxonomyDefaults -MemoryType $MemoryType -Category $Category -SourceArtifactId $SourceArtifactId -SourcePath $SourcePath
$EffectiveStatus = if (-not [string]::IsNullOrWhiteSpace($Status)) { $Status } else { [string]$Defaults.status }
$EffectiveConfidence = if ($PSBoundParameters.ContainsKey("Confidence") -and -not [string]::IsNullOrWhiteSpace([string]$Confidence)) { [double]$Confidence } else { [double]$Defaults.confidence }
$EffectiveSensitivity = if (-not [string]::IsNullOrWhiteSpace($Sensitivity)) { $Sensitivity } else { [string]$Defaults.sensitivity }
$EffectiveSourceType = if (-not [string]::IsNullOrWhiteSpace($SourceType)) { $SourceType } else { [string]$Defaults.source_type }
$EffectiveLifecycleState = if (-not [string]::IsNullOrWhiteSpace($LifecycleState)) { $LifecycleState } else { [string]$Defaults.lifecycle_state }
$EffectiveTags = if ($Tags -and @($Tags).Count -gt 0) {
    @($Tags)
}
else {
    @($Category, $MemoryType, $EffectiveSourceType) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
}

$AllowedStatuses = @($Taxonomy.statuses) | ForEach-Object { [string]$_ }
$AllowedSensitivities = @($Taxonomy.sensitivities) | ForEach-Object { [string]$_ }
$AllowedSourceTypes = @($Taxonomy.source_types) | ForEach-Object { [string]$_ }
$AllowedLifecycleStates = @($Taxonomy.lifecycle_states) | ForEach-Object { [string]$_ }
$ConfidenceBand = $Taxonomy.confidence_scale

if (-not ($AllowedStatuses -contains $EffectiveStatus)) { throw "Invalid status '$EffectiveStatus'." }
if (-not ($AllowedSensitivities -contains $EffectiveSensitivity)) { throw "Invalid sensitivity '$EffectiveSensitivity'." }
if (-not ($AllowedSourceTypes -contains $EffectiveSourceType)) { throw "Invalid source_type '$EffectiveSourceType'." }
if (-not ($AllowedLifecycleStates -contains $EffectiveLifecycleState)) { throw "Invalid lifecycle_state '$EffectiveLifecycleState'." }
if ($EffectiveConfidence -lt [double]$ConfidenceBand.minimum -or $EffectiveConfidence -gt [double]$ConfidenceBand.maximum) { throw "Invalid confidence '$EffectiveConfidence'." }

if ([string]::IsNullOrWhiteSpace($SourceArtifactId)) {
    throw "SourceArtifactId is required for taxonomy-compliant memory writes."
}

$ResolvedSourcePath = $SourcePath
if ([string]::IsNullOrWhiteSpace($ResolvedSourcePath)) {
    if (-not $ArtifactLookup.ContainsKey([string]$SourceArtifactId)) {
        throw "Unable to resolve source_path for memory registration."
    }

    $ArtifactRecord = $ArtifactLookup[[string]$SourceArtifactId]
    if (-not ($ArtifactRecord.PSObject.Properties.Name -contains "artifact_path") -or [string]::IsNullOrWhiteSpace([string]$ArtifactRecord.artifact_path)) {
        throw "Artifact $SourceArtifactId does not contain an artifact_path."
    }

    $ResolvedSourcePath = [string]$ArtifactRecord.artifact_path
}

if (-not [System.IO.Path]::IsPathRooted($ResolvedSourcePath)) {
    $ResolvedSourcePath = Join-Path $RepoRoot $ResolvedSourcePath
}

if (-not (Test-Path -Path $ResolvedSourcePath -PathType Leaf)) {
    throw "SourcePath does not exist: $ResolvedSourcePath"
}

$Candidate = [ordered]@{
    memory_id          = "memory-$([guid]::NewGuid().ToString())"
    created_at         = $Now
    updated_at         = $Now
    memory_type        = $MemoryType
    title              = $Title
    summary            = $Summary
    category           = $Category
    source_artifact_id = $SourceArtifactId
    source_path        = $ResolvedSourcePath
    status             = $EffectiveStatus
    confidence         = [math]::Round([double]$EffectiveConfidence, [int]$ConfidenceBand.precision)
    sensitivity        = $EffectiveSensitivity
    source_type        = $EffectiveSourceType
    lifecycle_state    = $EffectiveLifecycleState
    tags               = @($EffectiveTags)
}

$Validation = Assert-PDAMemoryRecordTaxonomyWritable -Record ([pscustomobject]$Candidate) -Taxonomy $Taxonomy -ArtifactLookup $ArtifactLookup -Root $RepoRoot

$Memories = @($Index.memories)
$Memories += [pscustomobject]$Candidate

$UpdatedIndex = [ordered]@{
    schema_version = [string]$Index.schema_version
    created_at     = if ($Index.PSObject.Properties.Name -contains "created_at") { [string]$Index.created_at } else { "" }
    updated_at     = $Now
    memories       = @($Memories)
}

$UpdatedIndex | ConvertTo-Json -Depth 20 | Set-Content -Path $IndexPath -Encoding UTF8

Write-Host "Registered memory: $($Candidate.memory_id)"
Write-Host "Memory count: $(@($UpdatedIndex.memories).Count)"
Write-Host "Memory taxonomy validation: $($Validation.valid)"
