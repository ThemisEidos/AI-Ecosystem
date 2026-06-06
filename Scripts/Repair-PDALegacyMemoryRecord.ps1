[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $true)]
    [string]$MemoryId,

    [string]$Status,

    [object]$Confidence,

    [string]$Sensitivity,

    [string]$SourceType,

    [string]$LifecycleState,

    [string[]]$Tags,

    [string]$SourceArtifactId,

    [string]$SourcePath,

    [switch]$AllowBrokenSourceReference,

    [switch]$AsJson,

    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "PDA_MemoryTaxonomy.ps1")

$RepoRoot = $Root
$MemoryIndexPath = Join-Path $RepoRoot "PDA_MemoryIndex.json"
$ArtifactIndexPath = Join-Path $RepoRoot "PDA_ArtifactIndex.json"
$AllowlistPath = Join-Path $PSScriptRoot "PDA_LegacyMemoryRepairAllowlist.json"

function Read-PDARepairJson {
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

function Get-PDARepairPropertyValue {
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

function ConvertTo-PDARepairComparableText {
    param([Parameter(Mandatory = $false)]$Value)

    if ($null -eq $Value) {
        return ""
    }

    if ($Value -is [System.Array]) {
        return (($Value | ForEach-Object { [string]$_ }) -join " || ")
    }

    return [string]$Value
}

function Normalize-PDALegacyRepairTags {
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$InputTags
    )

    $Normalized = New-Object System.Collections.Generic.List[string]
    foreach ($Tag in @($InputTags)) {
        if ($null -eq $Tag) {
            continue
        }

        foreach ($Part in ([string]$Tag -split ',')) {
            $Trimmed = $Part.Trim()
            if (-not [string]::IsNullOrWhiteSpace($Trimmed)) {
                $Normalized.Add($Trimmed)
            }
        }
    }

    return @($Normalized.ToArray())
}

function Get-PDALegacyMemoryRepairAllowlist {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Allowlist = Read-PDARepairJson -Path $Path -NotFoundMessage "Legacy memory repair allowlist not found: $Path" -ParseMessage "Legacy memory repair allowlist JSON could not be parsed at '$Path'."
    if (-not ($Allowlist.PSObject.Properties.Name -contains "memory_ids") -or $null -eq $Allowlist.memory_ids -or $Allowlist.memory_ids -isnot [System.Array]) {
        throw "Legacy memory repair allowlist must contain a memory_ids array."
    }

    return [pscustomobject]@{
        path        = $Path
        memory_ids  = @($Allowlist.memory_ids | ForEach-Object { [string]$_ })
    }
}

function New-PDAMemoryRepairBackup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$IndexPath,

        [Parameter(Mandatory = $true)]
        [string]$MemoryId,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
    $SafeMemoryId = [regex]::Replace($MemoryId, '[^A-Za-z0-9._-]', '_')
    $BackupRoot = Join-Path $RepoRoot "PDA-Backups\legacy-memory-repairs"
    $BackupDir = Join-Path $BackupRoot "$Timestamp-$SafeMemoryId"
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

    $BackupIndexPath = Join-Path $BackupDir "PDA_MemoryIndex.json.bak"
    Copy-Item -LiteralPath $IndexPath -Destination $BackupIndexPath -Force

    return [pscustomobject]@{
        backup_root = $BackupRoot
        backup_dir  = $BackupDir
        backup_path = $BackupIndexPath
    }
}

if (-not (Test-Path -Path $MemoryIndexPath -PathType Leaf)) {
    throw "PDA memory index not found: $MemoryIndexPath"
}

$Allowlist = Get-PDALegacyMemoryRepairAllowlist -Path $AllowlistPath
if (-not ($Allowlist.memory_ids -contains [string]$MemoryId)) {
    throw "MemoryId '$MemoryId' is not on the legacy memory repair allowlist."
}

$Index = Read-PDARepairJson -Path $MemoryIndexPath -NotFoundMessage "PDA memory index not found: $MemoryIndexPath" -ParseMessage "PDA memory index JSON could not be parsed at '$MemoryIndexPath'."
if (-not ($Index.PSObject.Properties.Name -contains "schema_version")) {
    throw "PDA memory index is missing 'schema_version'."
}
if (-not ($Index.PSObject.Properties.Name -contains "memories")) {
    throw "PDA memory index is missing 'memories'."
}
if ($null -eq $Index.memories -or $Index.memories -isnot [System.Array]) {
    throw "PDA memory index 'memories' must be an array."
}

$MemoryRecords = @($Index.memories)
$MatchIndex = -1
for ($i = 0; $i -lt $MemoryRecords.Count; $i++) {
    if ([string](Get-PDARepairPropertyValue -Record $MemoryRecords[$i] -Name "memory_id") -eq [string]$MemoryId) {
        $MatchIndex = $i
        break
    }
}

if ($MatchIndex -lt 0) {
    throw "Memory not found: $MemoryId"
}

$CurrentMemory = $MemoryRecords[$MatchIndex]

$PatchableFields = @("Status", "Confidence", "Sensitivity", "SourceType", "LifecycleState", "Tags", "SourceArtifactId", "SourcePath")
$HasPatch = $false
foreach ($FieldName in $PatchableFields) {
    if ($PSBoundParameters.ContainsKey($FieldName)) {
        $HasPatch = $true
        break
    }
}

if (-not $HasPatch) {
    throw "No repair fields were supplied. Specify at least one repair field to patch."
}

$Taxonomy = Import-PDAMemoryTaxonomy -Root $RepoRoot
$WillWrite = -not $WhatIfPreference
$ArtifactLookup = @{}
$NeedArtifactIndex = $PSBoundParameters.ContainsKey("SourceArtifactId") -or ([string]::IsNullOrWhiteSpace([string](Get-PDARepairPropertyValue -Record $CurrentMemory -Name "source_artifact_id")) -eq $false)
if ($NeedArtifactIndex -and (Test-Path -Path $ArtifactIndexPath -PathType Leaf)) {
    $ArtifactIndex = Read-PDARepairJson -Path $ArtifactIndexPath -NotFoundMessage "PDA artifact index not found: $ArtifactIndexPath" -ParseMessage "PDA artifact index JSON could not be parsed at '$ArtifactIndexPath'."
    if (-not ($ArtifactIndex.PSObject.Properties.Name -contains "artifacts") -or $null -eq $ArtifactIndex.artifacts -or $ArtifactIndex.artifacts -isnot [System.Array]) {
        throw "PDA artifact index 'artifacts' must be an array."
    }

    foreach ($Artifact in @($ArtifactIndex.artifacts)) {
        if ($Artifact.PSObject.Properties.Name -contains "artifact_id" -and -not [string]::IsNullOrWhiteSpace([string]$Artifact.artifact_id)) {
            $ArtifactLookup[[string]$Artifact.artifact_id] = $Artifact
        }
    }
}

$UpdatedRecord = [ordered]@{}
foreach ($Property in $CurrentMemory.PSObject.Properties) {
    $UpdatedRecord[$Property.Name] = $Property.Value
}

$UpdatedRecord.updated_at = Get-Date -Format "o"

if ($PSBoundParameters.ContainsKey("Status")) { $UpdatedRecord.status = $Status }
if ($PSBoundParameters.ContainsKey("Confidence")) { $UpdatedRecord.confidence = $Confidence }
if ($PSBoundParameters.ContainsKey("Sensitivity")) { $UpdatedRecord.sensitivity = $Sensitivity }
if ($PSBoundParameters.ContainsKey("SourceType")) { $UpdatedRecord.source_type = $SourceType }
if ($PSBoundParameters.ContainsKey("LifecycleState")) { $UpdatedRecord.lifecycle_state = $LifecycleState }
if ($PSBoundParameters.ContainsKey("Tags")) { $UpdatedRecord.tags = @(Normalize-PDALegacyRepairTags -InputTags $Tags) }
if ($PSBoundParameters.ContainsKey("SourceArtifactId")) { $UpdatedRecord.source_artifact_id = $SourceArtifactId }
if ($PSBoundParameters.ContainsKey("SourcePath")) { $UpdatedRecord.source_path = $SourcePath }

$UpdatedMemory = [pscustomobject]$UpdatedRecord
$Validation = Test-PDAMemoryRecordAgainstTaxonomy -Record $UpdatedMemory -Taxonomy $Taxonomy -ArtifactLookup $ArtifactLookup -Root $RepoRoot
$ValidationIssues = @($Validation.issues)
if ($AllowBrokenSourceReference) {
    $ValidationIssues = @($ValidationIssues | Where-Object { $_.issue_type -ne "orphaned_source_artifact_reference" })
}

$RepairStatus = if ($WillWrite) { "pass" } else { "dry-run" }
$RepairMode = if ($WillWrite) { "write" } else { "dry-run" }
$RepairBackupPath = ""
$RepairBackupDir = ""
$RepairValidationValid = $true
$RepairValidationIssueCount = 0
$RepairValidationIssues = @()
$RepairIndexHealthStatus = "unknown"
$RepairIndexHealthIssueCount = 0
$RepairNote = ""

if ($ValidationIssues.Count -gt 0) {
    $IssueLines = @($ValidationIssues | ForEach-Object { "- $($_.issue_type): $($_.field) $($_.detail)" })
    $Result = [pscustomobject]@{}
    $Result | Add-Member NoteProperty status "fail"
    $Result | Add-Member NoteProperty memory_id ([string]$MemoryId)
    $Result | Add-Member NoteProperty allowlist_path $Allowlist.path
    $Result | Add-Member NoteProperty allowlist_count $Allowlist.memory_ids.Count
    $Result | Add-Member NoteProperty mode $RepairMode
    $Result | Add-Member NoteProperty backup_path $RepairBackupPath
    $Result | Add-Member NoteProperty backup_dir $RepairBackupDir
    $Result | Add-Member NoteProperty updated_at ([string]$UpdatedMemory.updated_at)
    $Result | Add-Member NoteProperty changed_fields @()
    $Result | Add-Member NoteProperty validation_valid $false
    $Result | Add-Member NoteProperty validation_issue_count (@($ValidationIssues).Count)
    $Result | Add-Member NoteProperty validation_issues @($ValidationIssues)
    $Result | Add-Member NoteProperty index_health_status $RepairIndexHealthStatus
    $Result | Add-Member NoteProperty index_health_issue_count $RepairIndexHealthIssueCount
    $Result | Add-Member NoteProperty source_reference_override ([bool]$AllowBrokenSourceReference)
    $Result | Add-Member NoteProperty repair_note ""
    $Result | Add-Member NoteProperty error ($IssueLines -join [Environment]::NewLine)

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        if (-not $NoThrow) {
            throw "PDA legacy memory repair validation failed."
        }
        return
    }

    Write-Host "[FAIL] PDA legacy memory repair validation failed."
    Write-Host ("Memory id: {0}" -f $MemoryId)
    Write-Host ("Mode: {0}" -f $Result.mode)
    Write-Host ("Error: {0}" -f $Result.error)
    if (-not $NoThrow) {
        throw "PDA legacy memory repair validation failed."
    }
    return
}

$ChangeSet = New-Object System.Collections.Generic.List[object]
foreach ($FieldName in @(
    "title",
    "summary",
    "category",
    "status",
    "confidence",
    "sensitivity",
    "source_type",
    "lifecycle_state",
    "source_artifact_id",
    "source_path",
    "tags"
)) {
    $BeforeValue = Get-PDARepairPropertyValue -Record $CurrentMemory -Name $FieldName
    $AfterValue = Get-PDARepairPropertyValue -Record $UpdatedMemory -Name $FieldName
    if ((ConvertTo-PDARepairComparableText -Value $BeforeValue) -ne (ConvertTo-PDARepairComparableText -Value $AfterValue)) {
        $ChangeSet.Add([pscustomobject]@{
            field = $FieldName
            before = ConvertTo-PDARepairComparableText -Value $BeforeValue
            after  = ConvertTo-PDARepairComparableText -Value $AfterValue
        })
    }
}

$RepairNote = if ($ChangeSet.Count -gt 0) { "Patched selected fields for a single allowlisted legacy record." } else { "No field changes were required." }

$BackupInfo = $null
if ($WillWrite) {
    $BackupInfo = New-PDAMemoryRepairBackup -IndexPath $MemoryIndexPath -MemoryId $MemoryId -RepoRoot $RepoRoot

    $MemoryRecords[$MatchIndex] = $UpdatedMemory
    $UpdatedIndex = [ordered]@{
        schema_version = [string]$Index.schema_version
        created_at     = if ($Index.PSObject.Properties.Name -contains "created_at") { [string]$Index.created_at } else { "" }
        updated_at     = [string]$UpdatedMemory.updated_at
        memories       = @($MemoryRecords)
    }

    $UpdatedIndex | ConvertTo-Json -Depth 20 | Set-Content -Path $MemoryIndexPath -Encoding UTF8
}

$IndexHealth = $null
try {
    $IndexHealthJson = & pwsh -NoProfile -File (Join-Path $PSScriptRoot "Test-PDAMemoryTaxonomy.ps1") -NoThrow -AsJson
    $IndexHealth = $IndexHealthJson | ConvertFrom-Json
}
catch {
    $IndexHealth = $null
}

$RepairBackupPathValue = if ($BackupInfo) { [string]$BackupInfo.backup_path } else { $RepairBackupPath }
$RepairBackupDirValue = if ($BackupInfo) { [string]$BackupInfo.backup_dir } else { $RepairBackupDir }
$RepairIndexHealthStatusValue = if ($null -ne $IndexHealth) { [string]$IndexHealth.status } else { $RepairIndexHealthStatus }
$RepairIndexHealthIssueCountValue = if ($null -ne $IndexHealth) { [int]$IndexHealth.invalid_record_count } else { $RepairIndexHealthIssueCount }
$ChangeSetValue = @($ChangeSet.ToArray())
$ValidationIssuesValue = @($ValidationIssues)

$Result = [pscustomobject]@{}
$Result | Add-Member NoteProperty status $RepairStatus
$Result | Add-Member NoteProperty memory_id ([string]$MemoryId)
$Result | Add-Member NoteProperty allowlist_path $Allowlist.path
$Result | Add-Member NoteProperty allowlist_count $Allowlist.memory_ids.Count
$Result | Add-Member NoteProperty mode $RepairMode
$Result | Add-Member NoteProperty backup_path $RepairBackupPathValue
$Result | Add-Member NoteProperty backup_dir $RepairBackupDirValue
$Result | Add-Member NoteProperty updated_at ([string]$UpdatedMemory.updated_at)
$Result | Add-Member NoteProperty changed_fields $ChangeSetValue
$Result | Add-Member NoteProperty validation_valid $RepairValidationValid
$Result | Add-Member NoteProperty validation_issue_count $RepairValidationIssueCount
$Result | Add-Member NoteProperty validation_issues $ValidationIssuesValue
$Result | Add-Member NoteProperty index_health_status $RepairIndexHealthStatusValue
$Result | Add-Member NoteProperty index_health_issue_count $RepairIndexHealthIssueCountValue
$Result | Add-Member NoteProperty source_reference_override ([bool]$AllowBrokenSourceReference)
$Result | Add-Member NoteProperty repair_note $RepairNote
$Result | Add-Member NoteProperty error ""

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Result.status -eq "fail") {
        throw "PDA legacy memory repair failed."
    }
    return
}

if ($Result.mode -eq "dry-run") {
    Write-Host "[DRY-RUN] Legacy memory repair validated."
} else {
    Write-Host "[OK] Legacy memory repaired."
}
Write-Host ("Memory id: {0}" -f $MemoryId)
Write-Host ("Allowlist count: {0}" -f $Result.allowlist_count)
Write-Host ("Backup path: {0}" -f $Result.backup_path)
Write-Host ("Updated at: {0}" -f $Result.updated_at)
Write-Host ("Validation status: {0}" -f $Result.validation_valid)
Write-Host ("Index health status: {0}" -f $Result.index_health_status)
if ($ChangeSet.Count -gt 0) {
    Write-Host "Changed fields:"
    foreach ($Change in $ChangeSet) {
        Write-Host ("- {0}: '{1}' -> '{2}'" -f $Change.field, $Change.before, $Change.after)
    }
}

if (-not $NoThrow -and $Result.status -eq "fail") {
    throw "PDA legacy memory repair failed."
}
