[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$IndexPath = Join-Path $RepoRoot "PDA_MemoryIndex.json"
$DashboardPath = Join-Path $RepoRoot "PDA-Obsidian-Vault\01_Dashboard\Memory Index.md"
$RepairReportPath = Join-Path $RepoRoot "PDA-Obsidian-Vault\01_Dashboard\Memory Repair Report.md"
$LegacyRepairAllowlistPath = Join-Path $PSScriptRoot "PDA_LegacyMemoryRepairAllowlist.json"
$LegacyRepairToolPath = "Scripts/Repair-PDALegacyMemoryRecord.ps1"
$MemoryTaxonomyScript = Join-Path $PSScriptRoot "Test-PDAMemoryTaxonomy.ps1"
$MemoryWriterEnforcementScript = Join-Path $PSScriptRoot "Test-PDAMemoryWriterEnforcement.ps1"
. (Join-Path $PSScriptRoot "PDA_Lifecycle.ps1")

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

function ConvertTo-PDAMarkdownTable {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Rows,
        [Parameter(Mandatory = $true)]
        [string[]]$Columns
    )

    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add("| " + ($Columns -join " | ") + " |")
    $Lines.Add("| " + (($Columns | ForEach-Object { "---" }) -join " | ") + " |")

    foreach ($Row in $Rows) {
        $Values = foreach ($Column in $Columns) {
            $Value = $Row.$Column
            if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
                ""
            }
            else {
                ([string]$Value).Replace("|", "\|")
            }
        }

        $Lines.Add("| " + ($Values -join " | ") + " |")
    }

    return $Lines.ToArray()
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

$Memories = @($Index.memories) | Sort-Object -Property @{ Expression = { Get-PDAMemoryDate $_.created_at } } -Descending
$LatestMemories = @($Memories | Select-Object -First 10)
$LifecycleSummary = Get-PDALifecycleCounts -Root $RepoRoot -RecordType "memory"
$Issues = @()
$DuplicateTracker = @{}
$TestRecordCount = 0

foreach ($Memory in $Memories) {
    $MemoryId = if ($Memory.PSObject.Properties.Name -contains "memory_id" -and $Memory.memory_id) { [string]$Memory.memory_id } else { "(missing)" }
    $MemoryType = if ($Memory.PSObject.Properties.Name -contains "memory_type") { [string]$Memory.memory_type } else { "" }
    $Category = if ($Memory.PSObject.Properties.Name -contains "category") { [string]$Memory.category } else { "" }
    $SourceArtifactId = if ($Memory.PSObject.Properties.Name -contains "source_artifact_id") { [string]$Memory.source_artifact_id } else { "" }
    $SourcePath = if ($Memory.PSObject.Properties.Name -contains "source_path") { [string]$Memory.source_path } else { "" }
    $IsTestRecord = ($Category -eq "test") -or ($MemoryType -match '^test')

    if ($IsTestRecord) {
        $TestRecordCount++
    }

    if ($DuplicateTracker.ContainsKey($MemoryId)) {
        $Issues += [pscustomobject]@{
            issue_type = "duplicate_memory_id"
            memory_id  = $MemoryId
            detail     = "Duplicate memory_id detected"
        }
    }
    else {
        $DuplicateTracker[$MemoryId] = $true
    }

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        $Issues += [pscustomobject]@{
            issue_type = "missing_source_path"
            memory_id  = $MemoryId
            detail     = "Missing source_path"
        }
    }
    else {
        $ResolvedSourcePath = if ([System.IO.Path]::IsPathRooted($SourcePath)) { $SourcePath } else { Join-Path $RepoRoot $SourcePath }
        if (-not (Test-Path -Path $ResolvedSourcePath -PathType Leaf)) {
            $Issues += [pscustomobject]@{
                issue_type = "broken_source_path"
                memory_id  = $MemoryId
                detail     = $SourcePath
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($SourceArtifactId)) {
        $Issues += [pscustomobject]@{
            issue_type = "missing_source_artifact_id"
            memory_id  = $MemoryId
            detail     = "Missing source_artifact_id"
        }
    }
}

$GroupedByType = @(
    $Memories |
        Group-Object memory_type |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                memory_type = if ($_.Name) { $_.Name } else { "(blank)" }
                count       = $_.Count
            }
        }
)

$GroupedByCategory = @(
    $Memories |
        Group-Object category |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                category = if ($_.Name) { $_.Name } else { "(blank)" }
                count    = $_.Count
            }
        }
)

$TagCounts = @{}
foreach ($Memory in $Memories) {
    $Tags = @()
    if ($Memory.PSObject.Properties.Name -contains "tags" -and $Memory.tags) {
        $Tags = @($Memory.tags)
    }

    foreach ($Tag in $Tags) {
        $Key = if ([string]::IsNullOrWhiteSpace([string]$Tag)) { "(blank)" } else { [string]$Tag }
        if ($TagCounts.ContainsKey($Key)) {
            $TagCounts[$Key]++
        }
        else {
            $TagCounts[$Key] = 1
        }
    }
}

$GroupedByTag = @(
    $TagCounts.GetEnumerator() |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                tag   = $_.Name
                count = $_.Value
            }
        }
)

$MemoryCount = @($Index.memories).Count
$LastUpdated = if ($Index.PSObject.Properties.Name -contains "updated_at" -and $Index.updated_at) { $Index.updated_at } else { "(blank)" }
$BrokenPathCount = @($Issues | Where-Object { $_.issue_type -eq "broken_source_path" }).Count
$MissingPathCount = @($Issues | Where-Object { $_.issue_type -eq "missing_source_path" }).Count
$MissingArtifactCount = @($Issues | Where-Object { $_.issue_type -eq "missing_source_artifact_id" }).Count
$DuplicateCount = @($Issues | Where-Object { $_.issue_type -eq "duplicate_memory_id" }).Count

$TaxonomyReport = $null
if (Test-Path $MemoryTaxonomyScript) {
    try {
        $TaxonomyJson = & pwsh -NoProfile -File $MemoryTaxonomyScript -NoThrow -AsJson
        $TaxonomyReport = $TaxonomyJson | ConvertFrom-Json
    }
    catch {
        $TaxonomyReport = $null
    }
}

$TaxonomyStatusText = if ($null -ne $TaxonomyReport) { [string]$TaxonomyReport.status } else { "unknown" }
$TaxonomyValidRecordCountText = if ($null -ne $TaxonomyReport) { [string]$TaxonomyReport.valid_record_count } else { "unknown" }
$TaxonomyInvalidRecordCountText = if ($null -ne $TaxonomyReport) { [string]$TaxonomyReport.invalid_record_count } else { "unknown" }
$TaxonomyMissingFieldCountText = if ($null -ne $TaxonomyReport) { [string]$TaxonomyReport.missing_field_count } else { "unknown" }
$TaxonomyInvalidTagCountText = if ($null -ne $TaxonomyReport) { [string]$TaxonomyReport.invalid_tag_count } else { "unknown" }
$TaxonomySourceReferenceCountText = if ($null -ne $TaxonomyReport) { [string]$TaxonomyReport.source_reference_issue_count } else { "unknown" }

$WriterEnforcementReport = $null
if (Test-Path $MemoryWriterEnforcementScript) {
    try {
        $WriterEnforcementJson = & pwsh -NoProfile -File $MemoryWriterEnforcementScript -NoThrow -AsJson
        $WriterEnforcementReport = $WriterEnforcementJson | ConvertFrom-Json
    }
    catch {
        $WriterEnforcementReport = $null
    }
}

$WriterEnforcementStatusText = if ($null -ne $WriterEnforcementReport) { [string]$WriterEnforcementReport.status } else { "unknown" }
$WriterCountText = if ($null -ne $WriterEnforcementReport) { [string]$WriterEnforcementReport.writer_count } else { "unknown" }
$CompliantWriterCountText = if ($null -ne $WriterEnforcementReport) { [string]$WriterEnforcementReport.taxonomy_compliant_writer_count } else { "unknown" }
$LiveValidMemoryCountText = if ($null -ne $WriterEnforcementReport) { [string]$WriterEnforcementReport.live_valid_record_count } else { "unknown" }
$LiveInvalidMemoryCountText = if ($null -ne $WriterEnforcementReport) { [string]$WriterEnforcementReport.live_invalid_record_count } else { "unknown" }
$RepairNeededCountText = if ($null -ne $WriterEnforcementReport) { [string]$WriterEnforcementReport.repair_needed_count } else { "unknown" }

$LegacyRepairAllowlistCountText = "unknown"
if (Test-Path $LegacyRepairAllowlistPath) {
    try {
        $LegacyRepairAllowlist = Get-Content -Path $LegacyRepairAllowlistPath -Raw | ConvertFrom-Json
        $LegacyRepairAllowlistCountText = if ($LegacyRepairAllowlist.memory_ids) { [string](@($LegacyRepairAllowlist.memory_ids).Count) } else { "0" }
    }
    catch {
        $LegacyRepairAllowlistCountText = "unknown"
    }
}

$Dashboard = New-Object System.Collections.Generic.List[string]
$Dashboard.Add("# PDA Memory Dashboard")
$Dashboard.Add("")
$Dashboard.Add("Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$Dashboard.Add("")
$Dashboard.Add("## Summary")
$Dashboard.Add("")
$Dashboard.Add("- Schema version: $($Index.schema_version)")
$Dashboard.Add("- Memory count: $MemoryCount")
$Dashboard.Add("- Last updated: $LastUpdated")
$Dashboard.Add("")

$Dashboard.Add("## Health Summary")
$Dashboard.Add("")
$Dashboard.Add("- Missing source_path count: $MissingPathCount")
$Dashboard.Add("- Broken source_path count: $BrokenPathCount")
$Dashboard.Add("- Missing source_artifact_id count: $MissingArtifactCount")
$Dashboard.Add("- Duplicate memory_id count: $DuplicateCount")
$Dashboard.Add("- Test record count: $TestRecordCount")
$Dashboard.Add("- Latest repair report path: $RepairReportPath")
$Dashboard.Add("- Memory taxonomy status: $TaxonomyStatusText")
$Dashboard.Add("- Memory taxonomy valid records: $TaxonomyValidRecordCountText")
$Dashboard.Add("- Memory taxonomy invalid records: $TaxonomyInvalidRecordCountText")
$Dashboard.Add("- Memory taxonomy missing fields: $TaxonomyMissingFieldCountText")
$Dashboard.Add("- Memory taxonomy invalid tags: $TaxonomyInvalidTagCountText")
$Dashboard.Add("- Memory taxonomy source refs: $TaxonomySourceReferenceCountText")
$Dashboard.Add("- Memory writer enforcement status: $WriterEnforcementStatusText")
$Dashboard.Add("- Memory writer count: $WriterCountText")
$Dashboard.Add("- Taxonomy-compliant writers: $CompliantWriterCountText")
$Dashboard.Add("- Live valid memory records: $LiveValidMemoryCountText")
$Dashboard.Add("- Live invalid memory records: $LiveInvalidMemoryCountText")
$Dashboard.Add("- Repair needed count: $RepairNeededCountText")
$Dashboard.Add("- Active count: $($LifecycleSummary.active)")
$Dashboard.Add("- Archived count: $($LifecycleSummary.archived)")
$Dashboard.Add("- Deprecated count: $($LifecycleSummary.deprecated)")
$Dashboard.Add("- Retired count: $($LifecycleSummary.retired)")
$Dashboard.Add("- Legacy repair tool: $LegacyRepairToolPath")
$Dashboard.Add("- Legacy repair allowlist count: $LegacyRepairAllowlistCountText")
$Dashboard.Add("")

$Dashboard.Add("## Latest 10 Memories")
$Dashboard.Add("")
if ($LatestMemories.Count -gt 0) {
    foreach ($Line in (ConvertTo-PDAMarkdownTable -Rows $LatestMemories -Columns @("memory_id","created_at","memory_type","title","category","lifecycle_state","source_artifact_id","source_path","summary"))) {
        $Dashboard.Add($Line)
    }
} else {
    $Dashboard.Add("- No memories available.")
}
$Dashboard.Add("")

$Dashboard.Add("## Grouped By Memory Type")
$Dashboard.Add("")
if ($GroupedByType.Count -gt 0) {
    foreach ($Line in (ConvertTo-PDAMarkdownTable -Rows $GroupedByType -Columns @("memory_type","count"))) {
        $Dashboard.Add($Line)
    }
} else {
    $Dashboard.Add("- No memory type groups available.")
}
$Dashboard.Add("")

$GroupedByLifecycle = @(
    $Memories |
        Group-Object { if ($_.PSObject.Properties.Name -contains "lifecycle_state" -and -not [string]::IsNullOrWhiteSpace([string]$_.lifecycle_state)) { [string]$_.lifecycle_state } else { "active" } } |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                lifecycle_state = if ($_.Name) { $_.Name } else { "(blank)" }
                count           = $_.Count
            }
        }
)

$Dashboard.Add("## Grouped By Lifecycle State")
$Dashboard.Add("")
if ($GroupedByLifecycle.Count -gt 0) {
    foreach ($Line in (ConvertTo-PDAMarkdownTable -Rows $GroupedByLifecycle -Columns @("lifecycle_state","count"))) {
        $Dashboard.Add($Line)
    }
} else {
    $Dashboard.Add("- No lifecycle groups available.")
}
$Dashboard.Add("")

$Dashboard.Add("## Grouped By Category")
$Dashboard.Add("")
if ($GroupedByCategory.Count -gt 0) {
    foreach ($Line in (ConvertTo-PDAMarkdownTable -Rows $GroupedByCategory -Columns @("category","count"))) {
        $Dashboard.Add($Line)
    }
} else {
    $Dashboard.Add("- No category groups available.")
}
$Dashboard.Add("")

$Dashboard.Add("## Grouped By Tag")
$Dashboard.Add("")
if ($GroupedByTag.Count -gt 0) {
    foreach ($Line in (ConvertTo-PDAMarkdownTable -Rows $GroupedByTag -Columns @("tag","count"))) {
        $Dashboard.Add($Line)
    }
} else {
    $Dashboard.Add("- No tags available.")
}
$Dashboard.Add("")

$DashboardDir = Split-Path -Parent $DashboardPath
New-Item -ItemType Directory -Force -Path $DashboardDir | Out-Null
$Dashboard -join "`r`n" | Set-Content -Path $DashboardPath -Encoding UTF8

Write-Host "Dashboard updated:"
Write-Host $DashboardPath
Write-Host "Memory count: $MemoryCount"
Write-Host "Missing source_path count: $MissingPathCount"
Write-Host "Broken source_path count: $BrokenPathCount"
Write-Host "Missing source_artifact_id count: $MissingArtifactCount"
Write-Host "Duplicate memory_id count: $DuplicateCount"
Write-Host "Test record count: $TestRecordCount"
if ($null -ne $TaxonomyReport) {
    Write-Host "Memory taxonomy status: $TaxonomyStatusText"
    Write-Host "Memory taxonomy valid records: $TaxonomyValidRecordCountText"
    Write-Host "Memory taxonomy invalid records: $TaxonomyInvalidRecordCountText"
    Write-Host "Memory taxonomy missing fields: $TaxonomyMissingFieldCountText"
    Write-Host "Memory taxonomy invalid tags: $TaxonomyInvalidTagCountText"
    Write-Host "Memory taxonomy source refs: $TaxonomySourceReferenceCountText"
}
if ($null -ne $WriterEnforcementReport) {
    Write-Host "Memory writer enforcement status: $WriterEnforcementStatusText"
    Write-Host "Memory writer count: $WriterCountText"
    Write-Host "Taxonomy-compliant writers: $CompliantWriterCountText"
    Write-Host "Live valid memory records: $LiveValidMemoryCountText"
    Write-Host "Live invalid memory records: $LiveInvalidMemoryCountText"
    Write-Host "Repair needed count: $RepairNeededCountText"
}
