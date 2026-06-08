[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$SourceArtifactId = "",

    [Parameter(Mandatory = $false)]
    [string]$SourcePath = "",

    [Parameter(Mandatory = $false)]
    [string]$Title = "",

    [Parameter(Mandatory = $false)]
    [string]$Category = "",

    [Parameter(Mandatory = $false)]
    [string]$Summary = "",

    [Parameter(Mandatory = $false)]
    [string]$ProposedMemoryText = "",

    [Parameter(Mandatory = $false)]
    [double]$Confidence = 0.75,

    [Parameter(Mandatory = $false)]
    [string]$PromotionReason = "",

    [Parameter(Mandatory = $false)]
    [string]$SourceType = "",

    [Parameter(Mandatory = $false)]
    [string[]]$Tags = @(),

    [Parameter(Mandatory = $false)]
    [switch]$Discover,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 1000)]
    [int]$Limit = 1,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeRestricted,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

function Get-PDASlug {
    param([Parameter(Mandatory = $true)][string]$Text)

    $Slug = [string]$Text.Trim().ToLowerInvariant()
    $Slug = $Slug -replace '[^a-z0-9]+', '-'
    $Slug = $Slug -replace '-+', '-'
    $Slug = $Slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($Slug)) {
        return "candidate"
    }

    return $Slug
}

function Get-PDAMemoryCandidateStoreRoot {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    return (Join-Path $RootPath "PDA-Memory\candidates")
}

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
    param([Parameter(Mandatory = $true)][string]$Path)

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

function ConvertTo-PDAHashtable {
    param([Parameter(Mandatory = $false)]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string] -or
        $Value -is [char] -or
        $Value -is [bool] -or
        $Value -is [byte] -or
        $Value -is [sbyte] -or
        $Value -is [int16] -or
        $Value -is [int] -or
        $Value -is [int64] -or
        $Value -is [uint16] -or
        $Value -is [uint32] -or
        $Value -is [uint64] -or
        $Value -is [single] -or
        $Value -is [double] -or
        $Value -is [decimal] -or
        $Value -is [datetime] -or
        $Value -is [timespan] -or
        $Value -is [guid] -or
        $Value -is [uri] -or
        $Value.GetType().IsEnum) {
        return $Value
    }

    if ($Value -is [hashtable] -or $Value -is [System.Collections.IDictionary]) {
        $Copy = @{}
        foreach ($Key in $Value.Keys) {
            $Copy[$Key] = ConvertTo-PDAHashtable -Value $Value[$Key]
        }
        return $Copy
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $List = @()
        foreach ($Item in $Value) {
            $List += ,(ConvertTo-PDAHashtable -Value $Item)
        }
        return $List
    }

    if ($Value -is [psobject] -and $Value.PSObject.Properties.Name.Count -gt 0) {
        $Copy = @{}
        foreach ($Prop in $Value.PSObject.Properties) {
            $Copy[$Prop.Name] = ConvertTo-PDAHashtable -Value $Prop.Value
        }
        return $Copy
    }

    return $Value
}

function Get-PDARepositoryRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $Resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $RootResolved = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path
    $TrimmedRoot = $RootResolved.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $RootPrefix = $TrimmedRoot + [System.IO.Path]::DirectorySeparatorChar

    if ($Resolved.Equals($TrimmedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Source path must be inside the repository root: $Path"
    }

    if (-not $Resolved.StartsWith($RootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Source path must be inside the repository root: $Path"
    }

    return [string]$Resolved.Substring($RootPrefix.Length)
}

function Truncate-PDAString {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value,
        [Parameter(Mandatory = $false)]
        [int]$Length = 480
    )

    $Text = if ([string]::IsNullOrWhiteSpace($Value)) { "" } else { [string]$Value.Trim() }
    if ($Text.Length -le $Length) {
        return $Text
    }

    return $Text.Substring(0, $Length).Trim() + "..."
}

function Get-PDAArtifactCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $ArtifactIndexPath = Join-Path $RootPath "PDA_ArtifactIndex.json"
    $Index = Read-PDAJsonFile -Path $ArtifactIndexPath
    if (-not $Index -or -not ($Index.PSObject.Properties.Name -contains "artifacts") -or $null -eq $Index.artifacts) {
        return @()
    }

    $EligibleTypes = @(
        "research_markdown",
        "findings_markdown",
        "timeline_markdown",
        "report_pipeline_markdown",
        "fabric_markdown",
        "draft_markdown",
        "review_markdown",
        "planner_markdown",
        "operator_console_markdown"
    )

    $Artifacts = @($Index.artifacts)
    $Artifacts = @($Artifacts | Where-Object {
        $Type = if ($_.PSObject.Properties.Name -contains "artifact_type") { [string]$_.artifact_type } else { "" }
        $CategoryValue = if ($_.PSObject.Properties.Name -contains "category") { [string]$_.category } else { "" }
        $HasPath = $_.PSObject.Properties.Name -contains "artifact_path" -and -not [string]::IsNullOrWhiteSpace([string]$_.artifact_path)
        $HasSummary = $_.PSObject.Properties.Name -contains "summary" -and -not [string]::IsNullOrWhiteSpace([string]$_.summary)
        $IsCategory2 = $CategoryValue -eq "category_2"
        $IsEligible = $EligibleTypes -contains $Type
        return ($HasPath -and ($HasSummary -or $IsEligible) -and (-not $IsCategory2))
    })

    $Artifacts = @(
        $Artifacts |
            Sort-Object { [string]$_.created_at } -Descending
    )

    foreach ($Artifact in $Artifacts) {
        $TitleValue = if ($Artifact.PSObject.Properties.Name -contains "summary" -and -not [string]::IsNullOrWhiteSpace([string]$Artifact.summary)) {
            [string]$Artifact.summary
        }
        elseif ($Artifact.PSObject.Properties.Name -contains "artifact_type") {
            "{0} memory candidate" -f [string]$Artifact.artifact_type
        }
        else {
            "Artifact memory candidate"
        }

        $SourceArtifactIdValue = if ($Artifact.PSObject.Properties.Name -contains "artifact_id") { [string]$Artifact.artifact_id } else { "" }
        $SourcePathValue = if ($Artifact.PSObject.Properties.Name -contains "artifact_path") { [string]$Artifact.artifact_path } else { "" }
        $CategoryValue = if ($Artifact.PSObject.Properties.Name -contains "category") { [string]$Artifact.category } else { "category_1" }
        $ArtifactTypeValue = if ($Artifact.PSObject.Properties.Name -contains "artifact_type") { [string]$Artifact.artifact_type } else { "artifact" }
        $WorkerNameValue = if ($Artifact.PSObject.Properties.Name -contains "worker_name") { [string]$Artifact.worker_name } else { "" }
        $SummaryValue = if ($Artifact.PSObject.Properties.Name -contains "summary") { [string]$Artifact.summary } else { "" }
        $ProposedText = Truncate-PDAString -Value ("{0}. Source artifact {1} produced by {2}." -f $TitleValue, $SourceArtifactIdValue, $WorkerNameValue) -Length 520
        $PromotionReasonValue = switch -Regex ($ArtifactTypeValue.ToLowerInvariant()) {
            'research_markdown' { "Reusable research synthesis should inform future retrieval." ; break }
            'findings_markdown' { "Validated findings should be promoted for later reuse." ; break }
            'timeline_markdown' { "Timeline milestone context should be remembered." ; break }
            'report_pipeline_markdown' { "Report pipeline output captures reusable reporting knowledge." ; break }
            'fabric_markdown' { "Fabric output captures a reusable local pattern result." ; break }
            'draft_markdown' { "Draft output captures a reusable operational draft." ; break }
            'review_markdown' { "Review guidance can be reused as an evaluation heuristic." ; break }
            'planner_markdown' { "Planning output can inform future roadmap work." ; break }
            'operator_console_markdown' { "Operator console output captures a reusable operational summary." ; break }
            default { "Completed artifact should be considered for memory promotion." }
        }
        $CandidateTags = @()
        if ($WorkerNameValue) { $CandidateTags += "source:$WorkerNameValue" }
        if ($ArtifactTypeValue) { $CandidateTags += "artifact:$ArtifactTypeValue" }
        if ($CategoryValue) { $CandidateTags += "status:$CategoryValue" }

        [pscustomobject]@{
            candidate_source    = "artifact"
            title               = $TitleValue
            source_artifact_id  = $SourceArtifactIdValue
            source_path         = $SourcePathValue
            category            = $CategoryValue
            summary             = $SummaryValue
            proposed_memory_text = $ProposedText
            confidence          = if ($ArtifactTypeValue -eq "review_markdown") { 0.7 } elseif ($ArtifactTypeValue -eq "report_pipeline_markdown") { 0.8 } else { 0.85 }
            promotion_reason    = $PromotionReasonValue
            source_type         = "artifact"
            source_artifact_type = $ArtifactTypeValue
            source_metadata     = [pscustomobject]@{
                worker_name = $WorkerNameValue
                artifact_type = $ArtifactTypeValue
                source_task_id = if ($Artifact.PSObject.Properties.Name -contains "source_task_id") { [string]$Artifact.source_task_id } else { "" }
                artifact_path = $SourcePathValue
            }
            tags                = @($CandidateTags)
            discovery_key       = "artifact:$SourceArtifactIdValue"
            approval_required   = $true
        }
    }
}

function Get-PDANotebookLMPackageCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $PackageRoot = Join-Path $RootPath "PDA-Backups\notebooklm"
    if (-not (Test-Path -LiteralPath $PackageRoot -PathType Container)) {
        return @()
    }

    $ManifestFiles = @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -File -Filter manifest.json -ErrorAction SilentlyContinue)
    foreach ($ManifestFile in $ManifestFiles) {
        $Manifest = Read-PDAJsonFile -Path $ManifestFile.FullName
        if (-not $Manifest) {
            continue
        }

        $PackageRootPath = Split-Path -Parent $ManifestFile.FullName
        $SummaryPath = Join-Path $PackageRootPath "summary.md"
        $SummaryText = if (Test-Path -LiteralPath $SummaryPath -PathType Leaf) {
            (Get-Content -LiteralPath $SummaryPath -Raw -ErrorAction SilentlyContinue)
        }
        else {
            ""
        }

        $PackageName = if ($Manifest.PSObject.Properties.Name -contains "package_name" -and $Manifest.package_name) { [string]$Manifest.package_name } else { Split-Path -Leaf $PackageRootPath }
        $LearningArea = if ($Manifest.PSObject.Properties.Name -contains "learning_area" -and $Manifest.learning_area) { [string]$Manifest.learning_area } else { "Training" }
        $Topic = if ($Manifest.PSObject.Properties.Name -contains "topic" -and $Manifest.topic) { [string]$Manifest.topic } else { $PackageName }
        $CandidateTitle = if ($Topic) { "NotebookLM: {0}" -f $Topic } else { "NotebookLM learning package" }
        $SourcePaths = @()
        if ($Manifest.PSObject.Properties.Name -contains "source_files" -and $Manifest.source_files) {
            $SourcePaths = @($Manifest.source_files | ForEach-Object {
                if ($_.PSObject.Properties.Name -contains "source_path") {
                    [string]$_.source_path
                }
                elseif ($_.PSObject.Properties.Name -contains "repository_path") {
                    [string]$_.repository_path
                }
                else {
                    ""
                }
            })
            $SourcePaths = @($SourcePaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        }
        $CandidateTags = @("source:notebooklm", "learning:$LearningArea", "package:$PackageName")

        [pscustomobject]@{
            candidate_source    = "notebooklm"
            title               = $CandidateTitle
            source_artifact_id  = "notebooklm:$PackageName"
            source_path         = $PackageRootPath
            category            = "category_1"
            summary             = Truncate-PDAString -Value $SummaryText -Length 1000
            proposed_memory_text = Truncate-PDAString -Value ("{0}. Source package {1} from {2}. {3}" -f $CandidateTitle, $PackageName, $LearningArea, $SummaryText) -Length 700
            confidence          = 0.8
            promotion_reason    = "Sanitized NotebookLM package captures reusable learning content."
            source_type         = "notebooklm"
            source_artifact_type = "notebooklm_package"
            source_metadata     = [pscustomobject]@{
                package_name  = $PackageName
                learning_area = $LearningArea
                topic         = $Topic
                manifest_path  = $ManifestFile.FullName
                summary_path   = $SummaryPath
                source_paths   = @($SourcePaths)
            }
            tags                = @($CandidateTags)
            discovery_key       = "notebooklm:$PackageName"
            approval_required   = $true
        }
    }
}

function Get-PDAMemoryCandidateContent {
    param([Parameter(Mandatory = $true)]$Candidate)

    $Now = (Get-Date).ToUniversalTime().ToString("o")
    $CandidateId = if ($Candidate.candidate_id) { [string]$Candidate.candidate_id } else { "memory-candidate-$([guid]::NewGuid().ToString())" }

    return [ordered]@{
        schema_version       = "1.0"
        candidate_id         = $CandidateId
        created_at           = $Now
        updated_at           = $Now
        approval_required    = [bool]$Candidate.approval_required
        approval_status      = "pending"
        promotion_status     = "pending_approval"
        source_type          = [string]$Candidate.source_type
        source_artifact_type = [string]$Candidate.source_artifact_type
        source_artifact_id   = [string]$Candidate.source_artifact_id
        source_path          = [string]$Candidate.source_path
        category             = [string]$Candidate.category
        title                = [string]$Candidate.title
        summary              = [string]$Candidate.summary
        proposed_memory_text = [string]$Candidate.proposed_memory_text
        confidence           = [math]::Round([double]$Candidate.confidence, 2)
        promotion_reason     = [string]$Candidate.promotion_reason
        tags                 = @($Candidate.tags)
        source_metadata      = ConvertTo-PDAHashtable -Value $Candidate.source_metadata
        discovery_key        = [string]$Candidate.discovery_key
        promoted_memory_id   = ""
        approval_requested_at = $Now
        approval_notes       = ""
    }
}

function Test-PDAMemoryCandidateExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CandidateRootPath,

        [Parameter(Mandatory = $true)]
        [string]$DiscoveryKey
    )

    if (-not (Test-Path -LiteralPath $CandidateRootPath -PathType Container)) {
        return $null
    }

    foreach ($File in @(Get-ChildItem -LiteralPath $CandidateRootPath -File -Filter *.json -ErrorAction SilentlyContinue)) {
        $Json = Read-PDAJsonFile -Path $File.FullName
        if (-not $Json) {
            continue
        }

        if ($Json.PSObject.Properties.Name -contains "discovery_key" -and [string]$Json.discovery_key -eq $DiscoveryKey) {
            return [pscustomobject]@{
                path = $File.FullName
                candidate = $Json
            }
        }
    }

    return $null
}

function Save-PDAMemoryCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CandidateRootPath,

        [Parameter(Mandatory = $true)]
        [object]$Candidate,

        [switch]$Force
    )

    New-Item -ItemType Directory -Force -Path $CandidateRootPath | Out-Null

    $Existing = Test-PDAMemoryCandidateExists -CandidateRootPath $CandidateRootPath -DiscoveryKey [string]$Candidate.discovery_key
    if ($Existing -and -not $Force) {
        return [pscustomobject]@{
            path = [string]$Existing.path
            candidate = $Existing.candidate
            created = $false
            skipped_reason = "Candidate already exists for discovery key."
        }
    }

    $Slug = Get-PDASlug -Text ([string]$Candidate.title)
    $Timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
    $BaseName = "memory-candidate-{0}-{1}" -f $Timestamp, $Slug
    $CandidatePath = Join-Path $CandidateRootPath ($BaseName + ".json")
    $Suffix = 2
    while (Test-Path -LiteralPath $CandidatePath -PathType Leaf) {
        $CandidatePath = Join-Path $CandidateRootPath ("{0}-{1}.json" -f $BaseName, $Suffix)
        $Suffix++
    }

    $CandidateContent = Get-PDAMemoryCandidateContent -Candidate $Candidate
    $CandidateContent | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $CandidatePath -Encoding UTF8

    return [pscustomobject]@{
        path = $CandidatePath
        candidate = (Read-PDAJsonFile -Path $CandidatePath)
        created = $true
        skipped_reason = ""
    }
}

$CandidateRoot = Get-PDAMemoryCandidateStoreRoot -RootPath $Root
$DiscoveryItems = New-Object System.Collections.Generic.List[object]

if ($Discover) {
    foreach ($Item in @(Get-PDAArtifactCandidates -RootPath $Root)) {
        if ($Item) {
            [void]$DiscoveryItems.Add($Item)
        }
    }
    foreach ($Item in @(Get-PDANotebookLMPackageCandidates -RootPath $Root)) {
        if ($Item) {
            [void]$DiscoveryItems.Add($Item)
        }
    }
}
elseif (-not [string]::IsNullOrWhiteSpace($SourceArtifactId) -or -not [string]::IsNullOrWhiteSpace($SourcePath)) {
    if (-not [string]::IsNullOrWhiteSpace($SourceArtifactId)) {
        $Artifacts = @(Get-PDAArtifactCandidates -RootPath $Root | Where-Object { [string]$_.source_artifact_id -eq $SourceArtifactId })
        if ($Artifacts.Count -gt 0) {
            $DiscoveryItems.Add($Artifacts[0])
        }
        else {
            $ArtifactIndexPath = Join-Path $Root "PDA_ArtifactIndex.json"
            $ArtifactIndex = Read-PDAJsonFile -Path $ArtifactIndexPath
            if (-not $ArtifactIndex -or -not ($ArtifactIndex.PSObject.Properties.Name -contains "artifacts")) {
                throw "Artifact index not found or invalid: $ArtifactIndexPath"
            }

            $Artifact = @($ArtifactIndex.artifacts | Where-Object { [string]$_.artifact_id -eq $SourceArtifactId } | Select-Object -First 1)
            if (-not $Artifact) {
                throw "Artifact not found: $SourceArtifactId"
            }

            if (-not $IncludeRestricted -and ($Artifact.PSObject.Properties.Name -contains "category") -and [string]$Artifact.category -eq "category_2") {
                throw "Category 2 artifacts are excluded by default. Use -IncludeRestricted only for local review."
            }

            $TitleValue = if ($Title) { $Title } elseif ($Artifact.PSObject.Properties.Name -contains "summary" -and $Artifact.summary) { [string]$Artifact.summary } else { [string]$Artifact.artifact_type }
            $DiscoveryItems.Add([pscustomobject]@{
                candidate_source    = "artifact"
                title               = $TitleValue
                source_artifact_id  = [string]$Artifact.artifact_id
                source_path         = if ($Artifact.PSObject.Properties.Name -contains "artifact_path") { [string]$Artifact.artifact_path } else { "" }
                category            = if ($Artifact.PSObject.Properties.Name -contains "category" -and $Artifact.category) { [string]$Artifact.category } else { "category_1" }
                summary             = if ($Summary) { $Summary } elseif ($Artifact.PSObject.Properties.Name -contains "summary") { [string]$Artifact.summary } else { "" }
                proposed_memory_text = if ($ProposedMemoryText) { $ProposedMemoryText } else { Truncate-PDAString -Value ([string]$Artifact.summary) -Length 520 }
                confidence          = if ($Confidence -gt 0) { $Confidence } else { 0.85 }
                promotion_reason    = if ($PromotionReason) { $PromotionReason } else { "Completed artifact selected for memory promotion consideration." }
                source_type         = "artifact"
                source_artifact_type = if ($Artifact.PSObject.Properties.Name -contains "artifact_type") { [string]$Artifact.artifact_type } else { "artifact" }
                source_metadata     = [pscustomobject]@{
                    worker_name   = if ($Artifact.PSObject.Properties.Name -contains "worker_name") { [string]$Artifact.worker_name } else { "" }
                    artifact_type = if ($Artifact.PSObject.Properties.Name -contains "artifact_type") { [string]$Artifact.artifact_type } else { "" }
                    artifact_path = if ($Artifact.PSObject.Properties.Name -contains "artifact_path") { [string]$Artifact.artifact_path } else { "" }
                    source_task_id = if ($Artifact.PSObject.Properties.Name -contains "source_task_id") { [string]$Artifact.source_task_id } else { "" }
                }
                tags                = @($Tags)
                discovery_key       = "artifact:$($Artifact.artifact_id)"
                approval_required   = $true
            })
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
        if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf -ErrorAction SilentlyContinue)) {
            if (-not (Test-Path -LiteralPath $SourcePath -PathType Container -ErrorAction SilentlyContinue)) {
                throw "Source path not found: $SourcePath"
            }
        }

        $Resolved = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
        $Relative = Get-PDARepositoryRelativePath -Path $Resolved -RootPath $Root
        if ($Relative -match '^(PDA-Backups[\\/].*[\\/]manifest\.json)$') {
            $DiscoveryItems.Add([pscustomobject]@{
                candidate_source    = "notebooklm"
                title               = if ($Title) { $Title } else { Split-Path -Leaf (Split-Path -Parent $Resolved) }
                source_artifact_id  = "notebooklm:{0}" -f (Split-Path -Leaf (Split-Path -Parent $Resolved))
                source_path         = Split-Path -Parent $Resolved
                category            = "category_1"
                summary             = if ($Summary) { $Summary } else { (Get-Content -LiteralPath (Join-Path (Split-Path -Parent $Resolved) "summary.md") -Raw -ErrorAction SilentlyContinue) }
                proposed_memory_text = if ($ProposedMemoryText) { $ProposedMemoryText } else { Truncate-PDAString -Value (Get-Content -LiteralPath (Join-Path (Split-Path -Parent $Resolved) "summary.md") -Raw -ErrorAction SilentlyContinue) -Length 700 }
                confidence          = if ($Confidence -gt 0) { $Confidence } else { 0.8 }
                promotion_reason    = if ($PromotionReason) { $PromotionReason } else { "Sanitized NotebookLM output should be considered for memory promotion." }
                source_type         = "notebooklm"
                source_artifact_type = "notebooklm_package"
                source_metadata     = [pscustomobject]@{
                    manifest_path = $Resolved
                    package_path  = Split-Path -Parent $Resolved
                }
                tags                = @($Tags)
                discovery_key       = "notebooklm:$Resolved"
                approval_required   = $true
            })
        }
        else {
            throw "SourcePath must point to a NotebookLM package manifest or use -SourceArtifactId."
        }
    }
}
else {
    foreach ($Item in @(Get-PDAArtifactCandidates -RootPath $Root)) {
        if ($Item) {
            [void]$DiscoveryItems.Add($Item)
        }
    }
    foreach ($Item in @(Get-PDANotebookLMPackageCandidates -RootPath $Root)) {
        if ($Item) {
            [void]$DiscoveryItems.Add($Item)
        }
    }
}

if ($DiscoveryItems.Count -eq 0) {
    $Result = [pscustomobject]@{
        status            = "empty"
        created_count     = 0
        skipped_count     = 0
        candidate_root    = $CandidateRoot
        candidate_files   = @()
        candidates        = @()
        note              = "No eligible completed artifacts or NotebookLM packages were found."
    }

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 40
        return
    }

    Write-Host "[PDA MEMORY CANDIDATES]"
    Write-Host $Result.note
    return
}

$CandidatesToWrite = @($DiscoveryItems | Select-Object -First $Limit)
$CreatedCandidates = New-Object System.Collections.Generic.List[object]
$CreatedPaths = New-Object System.Collections.Generic.List[string]
$SkippedCount = 0
foreach ($Candidate in $CandidatesToWrite) {
    $Saved = Save-PDAMemoryCandidate -CandidateRootPath $CandidateRoot -Candidate $Candidate -Force:$Force
    if ($Saved.created) {
        $CreatedCandidates.Add($Saved.candidate)
        if ($Saved.path) {
            $CreatedPaths.Add([string]$Saved.path)
        }
    }
    else {
        $SkippedCount++
        if ($Saved.candidate) {
            $CreatedCandidates.Add($Saved.candidate)
        }
        if ($Saved.path) {
            $CreatedPaths.Add([string]$Saved.path)
        }
    }
}

$CreatedCandidateCount = [int]$CreatedCandidates.Count

$CandidateFiles = @(
    $CreatedCandidates |
        ForEach-Object {
            if (-not $_) {
                return
            }

            if ($_.PSObject.Properties.Name -contains "candidate_id") {
                $CandidateIdValue = [string]$_.candidate_id
                if (-not [string]::IsNullOrWhiteSpace($CandidateIdValue)) {
                    $CandidateIdValue
                }
            }
        }
)

$ResultStatus = if ($CreatedCandidateCount -gt 0) { "pass" } else { "empty" }

$Result = [pscustomobject]@{
    status           = $ResultStatus
    created_count    = [int]$CreatedCandidateCount
    skipped_count    = [int]$SkippedCount
    discovered_count = [int]$DiscoveryItems.Count
    candidate_root   = $CandidateRoot
    candidate_paths  = [string[]]@($CreatedPaths)
    candidate_files  = [string[]]@($CandidateFiles)
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 40
    return
}

Write-Host "[OK] PDA memory candidate(s) generated"
Write-Host ("Candidate root  : {0}" -f $Result.candidate_root)
Write-Host ("Discovered      : {0}" -f $Result.discovered_count)
Write-Host ("Created         : {0}" -f $Result.created_count)
Write-Host ("Skipped         : {0}" -f $Result.skipped_count)
foreach ($Candidate in $CreatedCandidates) {
    Write-Host ("- {0} ({1})" -f $Candidate.title, $Candidate.candidate_id)
}
