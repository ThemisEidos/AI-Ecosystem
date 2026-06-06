[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ArtifactPath,

    [Parameter(Mandatory = $true)]
    [string]$SourceTaskId,

    [Parameter(Mandatory = $true)]
    [string]$WorkerName,

    [Parameter(Mandatory = $true)]
    [string]$Command,

    [Parameter(Mandatory = $true)]
    [string]$Category,

    [Parameter(Mandatory = $true)]
    [string]$ArtifactType,

    [Parameter(Mandatory = $true)]
    [string]$Summary
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

$Now = Get-Date -Format "o"
$Artifact = [ordered]@{
    artifact_id   = "artifact-$([guid]::NewGuid().ToString())"
    created_at    = $Now
    artifact_path = $ArtifactPath
    source_task_id = $SourceTaskId
    worker_name   = $WorkerName
    command       = $Command
    category      = $Category
    artifact_type = $ArtifactType
    summary       = $Summary
}

$Artifacts = @($Index.artifacts)
$Artifacts += [pscustomobject]$Artifact

$UpdatedIndex = [ordered]@{
    schema_version = [string]$Index.schema_version
    created_at     = if ($Index.PSObject.Properties.Name -contains "created_at") { [string]$Index.created_at } else { "" }
    updated_at     = $Now
    artifacts      = @($Artifacts)
}

$UpdatedIndex | ConvertTo-Json -Depth 20 | Set-Content -Path $IndexPath -Encoding UTF8

Write-Host "Registered artifact: $($Artifact.artifact_id)"
Write-Host "Artifact count: $(@($UpdatedIndex.artifacts).Count)"
