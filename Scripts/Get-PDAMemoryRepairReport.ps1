[CmdletBinding()]
param(
    [switch]$WriteMarkdown,
    [switch]$IncludeTaxonomy
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$IndexPath = Join-Path $Root "PDA_MemoryIndex.json"
$ReportPath = Join-Path $Root "PDA-Obsidian-Vault\01_Dashboard\Memory Repair Report.md"

. (Join-Path $PSScriptRoot "PDA_MemoryTaxonomy.ps1")

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
$Issues = @()
$TestRecords = @()
$DuplicateTracker = @{}
$TaxonomySuggestions = @()

foreach ($Memory in $Memories) {
    $MemoryId = if ($Memory.PSObject.Properties.Name -contains "memory_id" -and $Memory.memory_id) { [string]$Memory.memory_id } else { "(missing)" }
    $MemoryType = if ($Memory.PSObject.Properties.Name -contains "memory_type") { [string]$Memory.memory_type } else { "" }
    $Category = if ($Memory.PSObject.Properties.Name -contains "category") { [string]$Memory.category } else { "" }
    $Title = if ($Memory.PSObject.Properties.Name -contains "title") { [string]$Memory.title } else { "" }
    $Summary = if ($Memory.PSObject.Properties.Name -contains "summary") { [string]$Memory.summary } else { "" }
    $SourceArtifactId = if ($Memory.PSObject.Properties.Name -contains "source_artifact_id") { [string]$Memory.source_artifact_id } else { "" }
    $SourcePath = if ($Memory.PSObject.Properties.Name -contains "source_path") { [string]$Memory.source_path } else { "" }
    $IsTestRecord = ($Category -eq "test") -or ($MemoryType -match '^test')

    if ($IsTestRecord) {
        $TestRecords += [pscustomobject]@{
            memory_id   = $MemoryId
            memory_type = $MemoryType
            category    = $Category
            title       = $Title
        }
    }

    if ($DuplicateTracker.ContainsKey($MemoryId)) {
        $Issues += [pscustomobject]@{
            issue_type = "duplicate_memory_id"
            memory_id   = $MemoryId
            detail      = "Duplicate memory_id detected"
        }
    }
    else {
        $DuplicateTracker[$MemoryId] = $true
    }

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        $Issues += [pscustomobject]@{
            issue_type = "missing_source_path"
            memory_id   = $MemoryId
            detail      = "Missing source_path"
        }
    }
    else {
        $ResolvedSourcePath = Resolve-PDAMemoryPath -Path $SourcePath
        if ($null -eq $ResolvedSourcePath -or -not (Test-Path -Path $ResolvedSourcePath -PathType Leaf)) {
            $Issues += [pscustomobject]@{
                issue_type = "broken_source_path"
                memory_id   = $MemoryId
                detail      = $SourcePath
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($SourceArtifactId)) {
        $Issues += [pscustomobject]@{
            issue_type = "missing_source_artifact_id"
            memory_id   = $MemoryId
            detail      = "Missing source_artifact_id"
        }
    }

    if ($IncludeTaxonomy) {
        $TaxonomyDefaults = Get-PDAMemoryTaxonomyDefaults -MemoryType $MemoryType -Category $Category -SourceArtifactId $SourceArtifactId -SourcePath $SourcePath
        $MissingTaxonomyFields = @()
        foreach ($Field in @("status", "confidence", "sensitivity", "source_type", "lifecycle_state")) {
            if (-not ($Memory.PSObject.Properties.Name -contains $Field) -or [string]::IsNullOrWhiteSpace([string]$Memory.$Field)) {
                $MissingTaxonomyFields += $Field
            }
        }

        if ($MissingTaxonomyFields.Count -gt 0) {
            $TaxonomySuggestions += [pscustomobject]@{
                memory_id = $MemoryId
                missing_taxonomy_fields = @($MissingTaxonomyFields)
                suggested_values = [pscustomobject]@{
                    status          = [string]$TaxonomyDefaults.status
                    confidence      = [double]$TaxonomyDefaults.confidence
                    sensitivity     = [string]$TaxonomyDefaults.sensitivity
                    source_type     = [string]$TaxonomyDefaults.source_type
                    lifecycle_state = [string]$TaxonomyDefaults.lifecycle_state
                }
            }
        }
    }
}

$MemoryCount = @($Memories).Count
$IssueCount = @($Issues).Count
$BrokenPathCount = @($Issues | Where-Object { $_.issue_type -eq "broken_source_path" }).Count
$MissingPathCount = @($Issues | Where-Object { $_.issue_type -eq "missing_source_path" }).Count
$MissingArtifactCount = @($Issues | Where-Object { $_.issue_type -eq "missing_source_artifact_id" }).Count
$DuplicateCount = @($Issues | Where-Object { $_.issue_type -eq "duplicate_memory_id" }).Count
$LastUpdated = if ($Index.PSObject.Properties.Name -contains "updated_at" -and $Index.updated_at) { $Index.updated_at } else { "(blank)" }

$Lines = New-Object System.Collections.Generic.List[string]
$Lines.Add("Schema version: $($Index.schema_version)")
$Lines.Add("Memory count: $MemoryCount")
$Lines.Add("Last updated: $LastUpdated")
$Lines.Add("Issue count: $IssueCount")
$Lines.Add("Missing source_path: $MissingPathCount")
$Lines.Add("Broken source_path: $BrokenPathCount")
$Lines.Add("Missing source_artifact_id: $MissingArtifactCount")
$Lines.Add("Duplicate memory_id: $DuplicateCount")
$Lines.Add("Test records: $(@($TestRecords).Count)")
$Lines.Add("Taxonomy suggestions: $(@($TaxonomySuggestions).Count)")
$Lines.Add("")

Write-Host "Schema version: $($Index.schema_version)"
Write-Host "Memory count: $MemoryCount"
Write-Host "Last updated: $LastUpdated"
Write-Host "Issue count: $IssueCount"
Write-Host "Missing source_path: $MissingPathCount"
Write-Host "Broken source_path: $BrokenPathCount"
Write-Host "Missing source_artifact_id: $MissingArtifactCount"
Write-Host "Duplicate memory_id: $DuplicateCount"
Write-Host "Test records: $(@($TestRecords).Count)"

if ($Issues.Count -gt 0) {
    $Lines.Add("## Issues")
    $Lines.Add("")
    foreach ($Issue in ($Issues | Sort-Object issue_type, memory_id)) {
        $Lines.Add("- [$($Issue.issue_type)] $($Issue.memory_id): $($Issue.detail)")
    }
    $Lines.Add("")
}

if ($TestRecords.Count -gt 0) {
    $Lines.Add("## Test Records")
    $Lines.Add("")
    foreach ($Record in $TestRecords) {
        $Lines.Add("- $($Record.memory_id) | $($Record.memory_type) | $($Record.category) | $($Record.title)")
    }
    $Lines.Add("")
}

if ($IncludeTaxonomy -and $TaxonomySuggestions.Count -gt 0) {
    $Lines.Add("## Taxonomy Suggestions")
    $Lines.Add("")
    foreach ($Suggestion in $TaxonomySuggestions) {
        $Lines.Add("- $($Suggestion.memory_id): missing $($Suggestion.missing_taxonomy_fields -join ', ')")
        $Lines.Add("  - status: $($Suggestion.suggested_values.status)")
        $Lines.Add("  - confidence: $($Suggestion.suggested_values.confidence)")
        $Lines.Add("  - sensitivity: $($Suggestion.suggested_values.sensitivity)")
        $Lines.Add("  - source_type: $($Suggestion.suggested_values.source_type)")
        $Lines.Add("  - lifecycle_state: $($Suggestion.suggested_values.lifecycle_state)")
    }
    $Lines.Add("")
}

if ($WriteMarkdown) {
    $DashboardDir = Split-Path -Parent $ReportPath
    New-Item -ItemType Directory -Force -Path $DashboardDir | Out-Null
    $Lines -join "`r`n" | Set-Content -Path $ReportPath -Encoding UTF8
    Write-Host "Markdown report: $ReportPath"
}

if ($IssueCount -eq 0) {
    Write-Host "No repair actions required."
    exit 0
}

Write-Host ""
Write-Host "Repair report:"
$Issues |
    Sort-Object issue_type, memory_id |
    Format-Table -AutoSize issue_type, memory_id, detail
