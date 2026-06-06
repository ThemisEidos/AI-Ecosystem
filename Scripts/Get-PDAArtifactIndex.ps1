[CmdletBinding()]
param(
    [string]$WorkerName,
    [string]$Category,
    [string]$ArtifactType,
    [string]$SourceTaskId,
    [ValidateRange(1, 10000)]
    [int]$Latest
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$IndexPath = Join-Path $RepoRoot "PDA_ArtifactIndex.json"

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

function Get-PDAArtifactDate {
    param(
        [Parameter(Mandatory = $false)]
        $Value
    )

    if ($null -eq $Value) {
        return [datetime]::MinValue
    }

    try {
        return [datetime]::Parse([string]$Value)
    }
    catch {
        return [datetime]::MinValue
    }
}

function Resolve-PDAArtifactPath {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return (Join-Path $RepoRoot $Path)
}

if (-not (Test-Path -Path $IndexPath -PathType Leaf)) {
    New-PDAArtifactIndexFile -Path $IndexPath
}

$Raw = Get-Content -Path $IndexPath -Raw
try {
    $Index = $Raw | ConvertFrom-Json
}
catch {
    throw "PDA artifact index JSON could not be parsed at '$IndexPath'."
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

$Artifacts = @($Index.artifacts)

if ($WorkerName) {
    $Artifacts = @($Artifacts | Where-Object { $_.worker_name -eq $WorkerName })
}

if ($Category) {
    $Artifacts = @($Artifacts | Where-Object { $_.category -eq $Category })
}

if ($ArtifactType) {
    $Artifacts = @($Artifacts | Where-Object { $_.artifact_type -eq $ArtifactType })
}

if ($SourceTaskId) {
    $Artifacts = @($Artifacts | Where-Object { $_.source_task_id -eq $SourceTaskId })
}

$Artifacts = @(
    $Artifacts |
        Sort-Object -Property @{ Expression = { Get-PDAArtifactDate $_.created_at } } -Descending
)

if ($PSBoundParameters.ContainsKey("Latest")) {
    $Artifacts = @($Artifacts | Select-Object -First $Latest)
}

$ArtifactCount = @($Index.artifacts).Count
$FilteredCount = @($Artifacts).Count
$LastUpdated = if ($Index.PSObject.Properties.Name -contains "updated_at" -and $Index.updated_at) { $Index.updated_at } else { "(blank)" }

Write-Host "Schema version: $($Index.schema_version)"
Write-Host "Artifact count: $ArtifactCount"
Write-Host "Last updated: $LastUpdated"

if ($WorkerName -or $Category -or $ArtifactType -or $SourceTaskId -or $PSBoundParameters.ContainsKey("Latest")) {
    Write-Host "Filtered count: $FilteredCount"
}

if ($FilteredCount -eq 0) {
    Write-Host "No artifacts matched the current filters."
    exit 0
}

$DisplayArtifacts = $Artifacts | Select-Object `
    artifact_id,
    created_at,
    worker_name,
    category,
    artifact_type,
    artifact_path,
    summary

Write-Host ""
Write-Host "Artifacts:"
$DisplayArtifacts | Format-Table -AutoSize

$BrokenArtifacts = foreach ($Artifact in $Artifacts) {
    $ResolvedPath = Resolve-PDAArtifactPath -Path $Artifact.artifact_path
    if ($null -eq $ResolvedPath -or -not (Test-Path -Path $ResolvedPath -PathType Leaf)) {
        [pscustomobject]@{
            artifact_id   = $Artifact.artifact_id
            artifact_path = $Artifact.artifact_path
            worker_name   = $Artifact.worker_name
            source_task_id = $Artifact.source_task_id
        }
    }
}

if ($BrokenArtifacts) {
    Write-Host ""
    Write-Host "Broken links: $(@($BrokenArtifacts).Count)"
    $BrokenArtifacts | Format-Table -AutoSize
}
