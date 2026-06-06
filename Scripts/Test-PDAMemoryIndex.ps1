[CmdletBinding()]
param(
    [switch]$IncludeTestRecords
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$IndexPath = Join-Path $Root "PDA_MemoryIndex.json"

function Resolve-PDAMemoryPath {
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

    return (Join-Path $Root $Path)
}

if (-not (Test-Path -Path $IndexPath -PathType Leaf)) {
    throw "PDA memory index not found: $IndexPath"
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
$RequiredFields = @("memory_id", "created_at", "memory_type", "title", "summary", "category")
$Issues = @()
$DuplicateIds = New-Object System.Collections.Generic.HashSet[string]
$TestRecords = @()

foreach ($Memory in $Memories) {
    $MemoryId = if ($Memory.PSObject.Properties.Name -contains "memory_id" -and $Memory.memory_id) { [string]$Memory.memory_id } else { "(missing)" }
    $IsTestRecord = ($Memory.PSObject.Properties.Name -contains "category" -and [string]$Memory.category -eq "test") -or
        ($Memory.PSObject.Properties.Name -contains "memory_type" -and [string]$Memory.memory_type -match '^test')

    if ($IsTestRecord) {
        $TestMemoryType = if ($Memory.PSObject.Properties.Name -contains "memory_type") { [string]$Memory.memory_type } else { "" }
        $TestCategory = if ($Memory.PSObject.Properties.Name -contains "category") { [string]$Memory.category } else { "" }
        $TestTitle = if ($Memory.PSObject.Properties.Name -contains "title") { [string]$Memory.title } else { "" }

        $TestRecords += [pscustomobject]@{
            memory_id   = $MemoryId
            memory_type = $TestMemoryType
            category    = $TestCategory
            title       = $TestTitle
        }
    }

    if (-not $IncludeTestRecords -and $IsTestRecord) {
        continue
    }

    foreach ($Field in $RequiredFields) {
        if (-not ($Memory.PSObject.Properties.Name -contains $Field) -or [string]::IsNullOrWhiteSpace([string]$Memory.$Field)) {
            $Issues += [pscustomobject]@{
                issue_type = "missing_field"
                memory_id   = $MemoryId
                field       = $Field
                detail      = "Missing required field"
            }
        }
    }

    if ($Memory.PSObject.Properties.Name -contains "memory_id" -and $Memory.memory_id) {
        if (-not $DuplicateIds.Add([string]$Memory.memory_id)) {
            $Issues += [pscustomobject]@{
                issue_type = "duplicate_memory_id"
                memory_id   = [string]$Memory.memory_id
                field       = "memory_id"
                detail      = "Duplicate memory_id detected"
            }
        }
    }

    if (-not ($Memory.PSObject.Properties.Name -contains "source_path") -or [string]::IsNullOrWhiteSpace([string]$Memory.source_path)) {
        $Issues += [pscustomobject]@{
            issue_type = "missing_source_path"
            memory_id   = $MemoryId
            field       = "source_path"
            detail      = "Missing source_path"
        }
    }
    else {
        $ResolvedSourcePath = Resolve-PDAMemoryPath -Path ([string]$Memory.source_path)
        if ($null -eq $ResolvedSourcePath -or -not (Test-Path -Path $ResolvedSourcePath -PathType Leaf)) {
            $Issues += [pscustomobject]@{
                issue_type = "broken_source_path"
                memory_id   = $MemoryId
                field       = "source_path"
                detail      = [string]$Memory.source_path
            }
        }
    }

    if (-not ($Memory.PSObject.Properties.Name -contains "source_artifact_id") -or [string]::IsNullOrWhiteSpace([string]$Memory.source_artifact_id)) {
        $Issues += [pscustomobject]@{
            issue_type = "missing_source_artifact_id"
            memory_id   = $MemoryId
            field       = "source_artifact_id"
            detail      = "Missing source_artifact_id"
        }
    }
}

$MemoryCount = @($Memories).Count
$IssueCount = @($Issues).Count
$LastUpdated = if ($Index.PSObject.Properties.Name -contains "updated_at" -and $Index.updated_at) { $Index.updated_at } else { "(blank)" }

Write-Host "Schema version: $($Index.schema_version)"
Write-Host "Memory count: $MemoryCount"
Write-Host "Last updated: $LastUpdated"
Write-Host "Include test records: $([bool]$IncludeTestRecords)"
Write-Host "Issue count: $IssueCount"

if ($IncludeTestRecords -and $TestRecords.Count -gt 0) {
    Write-Host ""
    Write-Host "Test records included:"
    $TestRecords | Format-Table -AutoSize memory_id, memory_type, category, title
}

if ($Issues.Count -eq 0) {
    Write-Host "No memory health issues detected."
    exit 0
}

Write-Host ""
Write-Host "Memory health issues:"
$Issues |
    Sort-Object issue_type, memory_id, field |
    Format-Table -AutoSize issue_type, memory_id, field, detail
