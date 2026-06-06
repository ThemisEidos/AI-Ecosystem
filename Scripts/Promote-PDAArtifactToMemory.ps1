[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $true)]
    [string]$ArtifactId,

    [Parameter(Mandatory = $true)]
    [string]$MemoryType,

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [string]$Summary,

    [Parameter(Mandatory = $false)]
    [string[]]$Tags = @(),

    [Parameter(Mandatory = $false)]
    [string]$CategoryOverride = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = $Root
$ArtifactIndexPath = Join-Path $RepoRoot "PDA_ArtifactIndex.json"
$RegisterMemoryScript = Join-Path $PSScriptRoot "Register-PDAMemory.ps1"

function New-PDAArtifactIndexFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Now = Get-Date -Format "o"
    $Index = [ordered]@{
        schema_version = "1.0"
        created_at     = $Now
        updated_at     = $Now
        artifacts      = @()
    }

    $Index | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

if (-not (Test-Path -Path $ArtifactIndexPath -PathType Leaf)) {
    New-PDAArtifactIndexFile -Path $ArtifactIndexPath
}

$Raw = Get-Content -Path $ArtifactIndexPath -Raw
try {
    $Index = $Raw | ConvertFrom-Json
}
catch {
    throw "PDA artifact index JSON could not be parsed at '$ArtifactIndexPath'."
}

if (-not ($Index.PSObject.Properties.Name -contains "schema_version")) {
    throw "PDA artifact index is missing 'schema_version'."
}

if (-not ($Index.PSObject.Properties.Name -contains "artifacts")) {
    throw "PDA artifact index is missing 'artifacts'."
}

if ($null -eq $Index.artifacts -or $Index.artifacts -isnot [System.Array]) {
    throw "PDA artifact index 'artifacts' must be an array."
}

$Artifact = @($Index.artifacts | Where-Object { $_.artifact_id -eq $ArtifactId } | Select-Object -First 1)
if (-not $Artifact) {
    throw "Artifact not found: $ArtifactId"
}

$Category = if ([string]::IsNullOrWhiteSpace($CategoryOverride)) { [string]$Artifact.category } else { $CategoryOverride }
$SourcePath = if ($Artifact.PSObject.Properties.Name -contains "artifact_path" -and $Artifact.artifact_path) { [string]$Artifact.artifact_path } else { "" }
$SourceArtifactId = [string]$Artifact.artifact_id
$PromotionTags = @()
if ($Artifact.PSObject.Properties.Name -contains "worker_name" -and $Artifact.worker_name) {
    $PromotionTags += [string]$Artifact.worker_name
}
if ($Artifact.PSObject.Properties.Name -contains "artifact_type" -and $Artifact.artifact_type) {
    $PromotionTags += [string]$Artifact.artifact_type
}
if ($Artifact.PSObject.Properties.Name -contains "source_task_id" -and $Artifact.source_task_id) {
    $PromotionTags += [string]$Artifact.source_task_id
}
if ($Tags) {
    $PromotionTags += @($Tags)
}

& $RegisterMemoryScript `
    -Root $RepoRoot `
    -MemoryType $MemoryType `
    -Title $Title `
    -Summary $Summary `
    -Category $Category `
    -SourceArtifactId $SourceArtifactId `
    -SourcePath $SourcePath `
    -Tags $PromotionTags
