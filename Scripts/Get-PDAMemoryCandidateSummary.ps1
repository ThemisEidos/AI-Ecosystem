[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10000)]
    [int]$Latest = 10,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

function Get-PDAMemoryCandidateDate {
    param([Parameter(Mandatory = $false)]$Value)

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

function Read-PDAJsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
}

$CandidateRoot = Join-Path $Root "PDA-Memory\candidates"
$MemoryIndexPath = Join-Path $Root "PDA_MemoryIndex.json"
$CandidateFiles = @()
if (Test-Path -LiteralPath $CandidateRoot -PathType Container) {
    $CandidateFiles = @(Get-ChildItem -LiteralPath $CandidateRoot -File -Filter *.json -ErrorAction SilentlyContinue)
}

$Candidates = New-Object System.Collections.Generic.List[object]
foreach ($File in $CandidateFiles) {
    $Json = Read-PDAJsonFile -Path $File.FullName
    if (-not $Json) {
        continue
    }

    if ($Json.PSObject.Properties.Name -contains "candidate_id" -and [string]::IsNullOrWhiteSpace([string]$Json.candidate_id)) {
        continue
    }

    $Candidates.Add([pscustomobject]@{
        candidate_id       = if ($Json.PSObject.Properties.Name -contains "candidate_id") { [string]$Json.candidate_id } else { "" }
        created_at         = if ($Json.PSObject.Properties.Name -contains "created_at") { [string]$Json.created_at } else { "" }
        updated_at         = if ($Json.PSObject.Properties.Name -contains "updated_at") { [string]$Json.updated_at } else { "" }
        title              = if ($Json.PSObject.Properties.Name -contains "title") { [string]$Json.title } else { "" }
        category           = if ($Json.PSObject.Properties.Name -contains "category") { [string]$Json.category } else { "" }
        source_type        = if ($Json.PSObject.Properties.Name -contains "source_type") { [string]$Json.source_type } else { "" }
        source_artifact_id = if ($Json.PSObject.Properties.Name -contains "source_artifact_id") { [string]$Json.source_artifact_id } else { "" }
        source_path        = if ($Json.PSObject.Properties.Name -contains "source_path") { [string]$Json.source_path } else { "" }
        summary            = if ($Json.PSObject.Properties.Name -contains "summary") { [string]$Json.summary } else { "" }
        promotion_status   = if ($Json.PSObject.Properties.Name -contains "promotion_status") { [string]$Json.promotion_status } else { "pending_approval" }
        approval_status    = if ($Json.PSObject.Properties.Name -contains "approval_status") { [string]$Json.approval_status } else { "pending" }
        approval_required  = if ($Json.PSObject.Properties.Name -contains "approval_required") { [bool]$Json.approval_required } else { $true }
        confidence         = if ($Json.PSObject.Properties.Name -contains "confidence") { [double]$Json.confidence } else { 0 }
        promotion_reason   = if ($Json.PSObject.Properties.Name -contains "promotion_reason") { [string]$Json.promotion_reason } else { "" }
    })
}

$MemoryCount = 0
$MemoryIndex = Read-PDAJsonFile -Path $MemoryIndexPath
if ($MemoryIndex -and $MemoryIndex.PSObject.Properties.Name -contains "memories" -and $null -ne $MemoryIndex.memories) {
    $MemoryCount = @($MemoryIndex.memories).Count
}

$RecentCandidates = @()
foreach ($Candidate in @($Candidates | Sort-Object { [string]$_.created_at } -Descending | Select-Object -First $Latest)) {
    $RecentCandidates += [pscustomobject]@{
        candidate_id       = if ($Candidate.PSObject.Properties.Name -contains "candidate_id") { [string]$Candidate.candidate_id } else { "" }
        created_at         = if ($Candidate.PSObject.Properties.Name -contains "created_at") { [string]$Candidate.created_at } else { "" }
        updated_at         = if ($Candidate.PSObject.Properties.Name -contains "updated_at") { [string]$Candidate.updated_at } else { "" }
        title              = if ($Candidate.PSObject.Properties.Name -contains "title") { [string]$Candidate.title } else { "" }
        category           = if ($Candidate.PSObject.Properties.Name -contains "category") { [string]$Candidate.category } else { "" }
        source_type        = if ($Candidate.PSObject.Properties.Name -contains "source_type") { [string]$Candidate.source_type } else { "" }
        source_artifact_id = if ($Candidate.PSObject.Properties.Name -contains "source_artifact_id") { [string]$Candidate.source_artifact_id } else { "" }
        source_path        = if ($Candidate.PSObject.Properties.Name -contains "source_path") { [string]$Candidate.source_path } else { "" }
        promotion_status   = if ($Candidate.PSObject.Properties.Name -contains "promotion_status") { [string]$Candidate.promotion_status } else { "pending_approval" }
        approval_status    = if ($Candidate.PSObject.Properties.Name -contains "approval_status") { [string]$Candidate.approval_status } else { "pending" }
        approval_required  = if ($Candidate.PSObject.Properties.Name -contains "approval_required") { [bool]$Candidate.approval_required } else { $true }
        confidence         = if ($Candidate.PSObject.Properties.Name -contains "confidence") { [double]$Candidate.confidence } else { 0 }
        promotion_reason   = if ($Candidate.PSObject.Properties.Name -contains "promotion_reason") { [string]$Candidate.promotion_reason } else { "" }
    }
}

$RecentMemories = @()
if ($MemoryIndex -and $MemoryIndex.PSObject.Properties.Name -contains "memories" -and $MemoryIndex.memories) {
    foreach ($Memory in @($MemoryIndex.memories | Sort-Object { [string]$_.created_at } -Descending | Select-Object -First $Latest)) {
        $RecentMemories += [pscustomobject]@{
            memory_id          = if ($Memory.PSObject.Properties.Name -contains "memory_id") { [string]$Memory.memory_id } else { "" }
            created_at         = if ($Memory.PSObject.Properties.Name -contains "created_at") { [string]$Memory.created_at } else { "" }
            memory_type        = if ($Memory.PSObject.Properties.Name -contains "memory_type") { [string]$Memory.memory_type } else { "" }
            category           = if ($Memory.PSObject.Properties.Name -contains "category") { [string]$Memory.category } else { "" }
            title              = if ($Memory.PSObject.Properties.Name -contains "title") { [string]$Memory.title } else { "" }
            summary            = if ($Memory.PSObject.Properties.Name -contains "summary") { [string]$Memory.summary } else { "" }
            source_artifact_id = if ($Memory.PSObject.Properties.Name -contains "source_artifact_id") { [string]$Memory.source_artifact_id } else { "" }
        }
    }
}

$PendingApprovalCount = @($Candidates | Where-Object {
    [string]$_.approval_status -in @("pending", "awaiting_approval", "awaiting_review") -or [bool]$_.approval_required
}).Count
$PromotedCount = @($MemoryIndex.memories).Count

$BySourceType = @(
    $Candidates |
        Group-Object source_type |
        Sort-Object Count -Descending |
        ForEach-Object {
            [pscustomobject]@{
                source_type = if ($_.Name) { $_.Name } else { "(blank)" }
                count       = [int]$_.Count
            }
        }
)

$ByCategory = @(
    $Candidates |
        Group-Object category |
        Sort-Object Count -Descending |
        ForEach-Object {
            [pscustomobject]@{
                category = if ($_.Name) { $_.Name } else { "(blank)" }
                count    = [int]$_.Count
            }
        }
)

$CandidateRootExists = Test-Path -LiteralPath $CandidateRoot -PathType Container
$ReportStatus = if ($CandidateRootExists) { "pass" } else { "missing" }

$Report = [pscustomobject]@{
    status                 = $ReportStatus
    candidate_root         = $CandidateRoot
    memory_index_path      = $MemoryIndexPath
    memory_count           = [int]$MemoryCount
    candidate_count        = [int]$Candidates.Count
    pending_approval_count = [int]$PendingApprovalCount
    promoted_count         = [int]$PromotedCount
    recent_candidates      = [object[]]@($RecentCandidates)
    recent_memories        = [object[]]@($RecentMemories)
    by_source_type         = [object[]]@($BySourceType)
    by_category            = [object[]]@($ByCategory)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    return
}

Write-Host "[PDA MEMORY CANDIDATE SUMMARY]"
Write-Host ("Candidate root      : {0}" -f $Report.candidate_root)
Write-Host ("Memory count        : {0}" -f $Report.memory_count)
Write-Host ("Candidate count     : {0}" -f $Report.candidate_count)
Write-Host ("Promoted count      : {0}" -f $Report.promoted_count)
Write-Host ("Pending approvals   : {0}" -f $Report.pending_approval_count)

if (@($Report.recent_candidates).Count -gt 0) {
    Write-Host ""
    Write-Host "Recent candidates:"
    $Report.recent_candidates |
        Select-Object candidate_id, created_at, title, category, source_type, approval_status, promotion_status |
        Format-Table -AutoSize
}

if (@($Report.recent_memories).Count -gt 0) {
    Write-Host ""
    Write-Host "Recent memories:"
    $Report.recent_memories |
        Select-Object memory_id, created_at, title, memory_type, category, source_artifact_id |
        Format-Table -AutoSize
}
