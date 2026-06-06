[CmdletBinding()]
param(
    [string]$MemoryType,
    [string]$SourceArtifactId,
    [string]$Category,
    [ValidateRange(1, 10000)]
    [int]$Latest
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$IndexPath = Join-Path $RepoRoot "PDA_MemoryIndex.json"

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

function Get-PDAMemoryDate {
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

if (-not (Test-Path -Path $IndexPath -PathType Leaf)) {
    New-PDAMemoryIndexFile -Path $IndexPath
}

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

$Memories = @($Index.memories)

if ($MemoryType) {
    $Memories = @($Memories | Where-Object { $_.memory_type -eq $MemoryType })
}

if ($SourceArtifactId) {
    $Memories = @($Memories | Where-Object { $_.source_artifact_id -eq $SourceArtifactId })
}

if ($Category) {
    $Memories = @($Memories | Where-Object { $_.category -eq $Category })
}

$Memories = @(
    $Memories |
        Sort-Object -Property @{ Expression = { Get-PDAMemoryDate $_.created_at } } -Descending
)

if ($PSBoundParameters.ContainsKey("Latest")) {
    $Memories = @($Memories | Select-Object -First $Latest)
}

$MemoryCount = @($Index.memories).Count
$FilteredCount = @($Memories).Count
$LastUpdated = if ($Index.PSObject.Properties.Name -contains "updated_at" -and $Index.updated_at) { $Index.updated_at } else { "(blank)" }

Write-Host "Schema version: $($Index.schema_version)"
Write-Host "Memory count: $MemoryCount"
Write-Host "Last updated: $LastUpdated"

if ($MemoryType -or $SourceArtifactId -or $Category -or $PSBoundParameters.ContainsKey("Latest")) {
    Write-Host "Filtered count: $FilteredCount"
}

if ($FilteredCount -eq 0) {
    Write-Host "No memories matched the current filters."
    exit 0
}

$DisplayMemories = $Memories | Select-Object `
    memory_id,
    created_at,
    memory_type,
    source_artifact_id,
    category,
    summary

Write-Host ""
Write-Host "Memories:"
$DisplayMemories | Format-Table -AutoSize
