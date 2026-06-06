[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $true)]
    [string]$MemoryId,

    [string]$SourcePath,

    [string]$SourceArtifactId,

    [string]$Title,

    [string]$Summary,

    [string]$Category,

    [string[]]$Tags,

    [string]$Status,

    [object]$Confidence,

    [string]$Sensitivity,

    [string]$SourceType,

    [string]$LifecycleState
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "PDA_MemoryTaxonomy.ps1")

$RepoRoot = $Root
$MemoryIndexPath = Join-Path $RepoRoot "PDA_MemoryIndex.json"
$ArtifactIndexPath = Join-Path $RepoRoot "PDA_ArtifactIndex.json"

function Read-PDAJson {
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
        return Get-Content -Path $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw $ParseMessage
    }
}

function Assert-PDAIndexShape {
    param(
        [Parameter(Mandatory = $true)]
        $Index,
        [Parameter(Mandatory = $true)]
        [string]$ArrayProperty
    )

    if (-not ($Index.PSObject.Properties.Name -contains "schema_version")) {
        throw "PDA index is missing 'schema_version'."
    }

    if (-not ($Index.PSObject.Properties.Name -contains $ArrayProperty)) {
        throw "PDA index is missing '$ArrayProperty'."
    }

    if ($null -eq $Index.$ArrayProperty -or $Index.$ArrayProperty -isnot [System.Array]) {
        throw "PDA index '$ArrayProperty' must be an array."
    }
}

function Get-PDAPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        $Record,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Record.PSObject.Properties.Name -contains $Name) {
        return $Record.$Name
    }

    return $null
}

$MemoryIndex = Read-PDAJson -Path $MemoryIndexPath -NotFoundMessage "PDA memory index not found: $MemoryIndexPath" -ParseMessage "PDA memory index JSON could not be parsed at '$MemoryIndexPath'."
Assert-PDAIndexShape -Index $MemoryIndex -ArrayProperty "memories"

$MemoryRecords = @($MemoryIndex.memories)
$MatchIndex = -1
for ($i = 0; $i -lt $MemoryRecords.Count; $i++) {
    if ([string](Get-PDAPropertyValue -Record $MemoryRecords[$i] -Name "memory_id") -eq $MemoryId) {
        $MatchIndex = $i
        break
    }
}

if ($MatchIndex -lt 0) {
    throw "Memory not found: $MemoryId"
}

$CurrentMemory = $MemoryRecords[$MatchIndex]

$ArtifactLookup = @{}
if (-not [string]::IsNullOrWhiteSpace($SourceArtifactId) -or [string]::IsNullOrWhiteSpace($SourcePath)) {
    $ArtifactIndex = Read-PDAJson -Path $ArtifactIndexPath -NotFoundMessage "PDA artifact index not found: $ArtifactIndexPath" -ParseMessage "PDA artifact index JSON could not be parsed at '$ArtifactIndexPath'."
    Assert-PDAIndexShape -Index $ArtifactIndex -ArrayProperty "artifacts"

    foreach ($Artifact in @($ArtifactIndex.artifacts)) {
        if ($Artifact.PSObject.Properties.Name -contains "artifact_id" -and -not [string]::IsNullOrWhiteSpace([string]$Artifact.artifact_id)) {
            $ArtifactLookup[[string]$Artifact.artifact_id] = $Artifact
        }
    }
}

if ([string]::IsNullOrWhiteSpace($SourcePath) -and -not [string]::IsNullOrWhiteSpace($SourceArtifactId)) {
    if (-not $ArtifactLookup.ContainsKey([string]$SourceArtifactId)) {
        throw "Artifact not found for source path lookup: $SourceArtifactId"
    }

    $ArtifactRecord = $ArtifactLookup[[string]$SourceArtifactId]
    if (-not ($ArtifactRecord.PSObject.Properties.Name -contains "artifact_path") -or [string]::IsNullOrWhiteSpace([string]$ArtifactRecord.artifact_path)) {
        throw "Artifact $SourceArtifactId does not contain an artifact_path."
    }

    $SourcePath = [string]$ArtifactRecord.artifact_path
}

$Taxonomy = Import-PDAMemoryTaxonomy -Root $RepoRoot
$CurrentMemoryType = [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "memory_type")
$CurrentCategory = if ($PSBoundParameters.ContainsKey("Category")) { $Category } else { [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "category") }
$CurrentSourceArtifactId = if ($PSBoundParameters.ContainsKey("SourceArtifactId")) { $SourceArtifactId } else { [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "source_artifact_id") }
$CurrentSourcePath = if ($PSBoundParameters.ContainsKey("SourcePath")) { $SourcePath } else { [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "source_path") }
$Defaults = Get-PDAMemoryTaxonomyDefaults -MemoryType $CurrentMemoryType -Category $CurrentCategory -SourceArtifactId $CurrentSourceArtifactId -SourcePath $CurrentSourcePath

$Before = [pscustomobject]@{
    memory_id          = [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "memory_id")
    source_path        = [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "source_path")
    source_artifact_id = [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "source_artifact_id")
    title              = [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "title")
    summary            = [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "summary")
    category           = [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "category")
    tags               = @((Get-PDAPropertyValue -Record $CurrentMemory -Name "tags"))
}

$Now = Get-Date -Format "o"
$UpdatedTitle = if ($PSBoundParameters.ContainsKey("Title")) { $Title } else { [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "title") }
$UpdatedSummary = if ($PSBoundParameters.ContainsKey("Summary")) { $Summary } else { [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "summary") }
$UpdatedCategory = if ($PSBoundParameters.ContainsKey("Category")) { $Category } else { [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "category") }
$UpdatedSourceArtifactId = if ($PSBoundParameters.ContainsKey("SourceArtifactId")) { $SourceArtifactId } else { [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "source_artifact_id") }
$UpdatedSourcePath = if ($PSBoundParameters.ContainsKey("SourcePath") -or (-not [string]::IsNullOrWhiteSpace($SourcePath))) { $SourcePath } else { [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "source_path") }
$UpdatedStatus = if ($PSBoundParameters.ContainsKey("Status")) { $Status } else { if ([string]::IsNullOrWhiteSpace([string](Get-PDAPropertyValue -Record $CurrentMemory -Name "status"))) { [string]$Defaults.status } else { [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "status") } }
$UpdatedConfidence = if ($PSBoundParameters.ContainsKey("Confidence") -and -not [string]::IsNullOrWhiteSpace([string]$Confidence)) { [math]::Round([double]$Confidence, 2) } else { if ([string]::IsNullOrWhiteSpace([string](Get-PDAPropertyValue -Record $CurrentMemory -Name "confidence"))) { [double]$Defaults.confidence } else { [double](Get-PDAPropertyValue -Record $CurrentMemory -Name "confidence") } }
$UpdatedSensitivity = if ($PSBoundParameters.ContainsKey("Sensitivity")) { $Sensitivity } else { if ([string]::IsNullOrWhiteSpace([string](Get-PDAPropertyValue -Record $CurrentMemory -Name "sensitivity"))) { [string]$Defaults.sensitivity } else { [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "sensitivity") } }
$UpdatedSourceType = if ($PSBoundParameters.ContainsKey("SourceType")) { $SourceType } else { if ([string]::IsNullOrWhiteSpace([string](Get-PDAPropertyValue -Record $CurrentMemory -Name "source_type"))) { [string]$Defaults.source_type } else { [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "source_type") } }
$UpdatedLifecycleState = if ($PSBoundParameters.ContainsKey("LifecycleState")) { $LifecycleState } else { if ([string]::IsNullOrWhiteSpace([string](Get-PDAPropertyValue -Record $CurrentMemory -Name "lifecycle_state"))) { [string]$Defaults.lifecycle_state } else { [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "lifecycle_state") } }
$UpdatedTags = if ($PSBoundParameters.ContainsKey("Tags")) { @($Tags) } elseif (@((Get-PDAPropertyValue -Record $CurrentMemory -Name "tags")).Count -gt 0 -and @((Get-PDAPropertyValue -Record $CurrentMemory -Name "tags") | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) { @((Get-PDAPropertyValue -Record $CurrentMemory -Name "tags")) } else { @((Get-PDAPropertyValue -Record $CurrentMemory -Name "category"), [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "memory_type"), [string]$Defaults.source_type) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } }

$UpdatedRecord = [ordered]@{
    memory_id          = [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "memory_id")
    created_at         = [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "created_at")
    updated_at         = $Now
    memory_type        = [string](Get-PDAPropertyValue -Record $CurrentMemory -Name "memory_type")
    title              = $UpdatedTitle
    summary            = $UpdatedSummary
    category           = $UpdatedCategory
    source_artifact_id = $UpdatedSourceArtifactId
    source_path        = $UpdatedSourcePath
    status             = $UpdatedStatus
    confidence         = $UpdatedConfidence
    sensitivity        = $UpdatedSensitivity
    source_type        = $UpdatedSourceType
    lifecycle_state    = $UpdatedLifecycleState
    tags               = $UpdatedTags
}

$MemoryRecords[$MatchIndex] = [pscustomobject]$UpdatedRecord

$Validation = Assert-PDAMemoryRecordTaxonomyWritable -Record ([pscustomobject]$UpdatedRecord) -Taxonomy $Taxonomy -ArtifactLookup $ArtifactLookup -Root $RepoRoot

$UpdatedIndex = [ordered]@{
    schema_version = [string](Get-PDAPropertyValue -Record $MemoryIndex -Name "schema_version")
    created_at     = [string](Get-PDAPropertyValue -Record $MemoryIndex -Name "created_at")
    updated_at     = $Now
    memories       = @($MemoryRecords)
}

$UpdatedIndex | ConvertTo-Json -Depth 20 | Set-Content -Path $MemoryIndexPath -Encoding UTF8

$After = [pscustomobject]@{
    memory_id          = [string](Get-PDAPropertyValue -Record $MemoryRecords[$MatchIndex] -Name "memory_id")
    source_path        = [string](Get-PDAPropertyValue -Record $MemoryRecords[$MatchIndex] -Name "source_path")
    source_artifact_id = [string](Get-PDAPropertyValue -Record $MemoryRecords[$MatchIndex] -Name "source_artifact_id")
    title              = [string](Get-PDAPropertyValue -Record $MemoryRecords[$MatchIndex] -Name "title")
    summary            = [string](Get-PDAPropertyValue -Record $MemoryRecords[$MatchIndex] -Name "summary")
    category           = [string](Get-PDAPropertyValue -Record $MemoryRecords[$MatchIndex] -Name "category")
    tags               = @((Get-PDAPropertyValue -Record $MemoryRecords[$MatchIndex] -Name "tags"))
}

Write-Host "Patched memory: $MemoryId"
Write-Host "Before:"
$Before | Format-List
Write-Host "After:"
$After | Format-List
Write-Host "Taxonomy validation: $($Validation.valid)"
