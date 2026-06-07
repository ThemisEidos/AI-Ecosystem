[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Training", "AI Systems", "Research", "Leadership")]
    [string]$LearningArea,

    [Parameter(Mandatory = $true)]
    [string]$Topic,

    [Parameter(Mandatory = $true)]
    [string[]]$SourcePaths,

    [Parameter(Mandatory = $false)]
    [string]$Summary = "",

    [Parameter(Mandatory = $false)]
    [string[]]$Questions = @(),

    [Parameter(Mandatory = $false)]
    [string[]]$RedactionNotes = @(),

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot = "",

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
        return "package"
    }

    return $Slug
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

function Test-PDANoteContainsSecretLikeContent {
    param([Parameter(Mandatory = $true)][string]$Text)

    $Patterns = @(
        '(?i)\bapi[_-]?key\b',
        '(?i)\bpassword\b',
        '(?i)\bprivate key\b',
        '(?i)\bsecret\b',
        '(?i)\bcredential\b',
        '(?i)\bbearer\s+[A-Za-z0-9\-\._~\+/=]{8,}\b',
        '-----BEGIN [A-Z ]+PRIVATE KEY-----'
    )

    foreach ($Pattern in $Patterns) {
        if ($Text -match $Pattern) {
            return $true
        }
    }

    return $false
}

function Get-PDANoteCategoryValidation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $Frontmatter = @{}
    $Lines = @($Text -split "`r?`n")
    if ($Lines.Count -ge 3 -and $Lines[0].Trim() -eq '---') {
        $EndIndex = -1
        for ($i = 1; $i -lt $Lines.Count; $i++) {
            if ($Lines[$i].Trim() -eq '---') {
                $EndIndex = $i
                break
            }
        }

        if ($EndIndex -gt 1) {
            for ($j = 1; $j -lt $EndIndex; $j++) {
                $Line = $Lines[$j]
                if ($Line -match '^\s*([A-Za-z0-9_-]+)\s*:\s*(.*?)\s*$') {
                    $Key = $Matches[1].ToLowerInvariant()
                    $Value = [string]$Matches[2]
                    $Frontmatter[$Key] = $Value
                }
            }
        }
    }

    $FrontmatterCategory = ""
    foreach ($Key in @("category", "classification", "sensitivity")) {
        if ($Frontmatter.ContainsKey($Key)) {
            $FrontmatterCategory = [string]$Frontmatter[$Key]
            break
        }
    }

    $Sanitized = $false
    if ($Frontmatter.ContainsKey("sanitized")) {
        $Sanitized = [string]$Frontmatter["sanitized"].ToLowerInvariant() -eq "true"
    }

    $SecretLike = Test-PDANoteContainsSecretLikeContent -Text $Text

    if ($SecretLike) {
        return [pscustomobject]@{
            status        = "fail"
            mode          = "content_scan"
            issue         = "Potential Category 2 or secret-like content detected."
            category      = $FrontmatterCategory
            sanitized     = $Sanitized
            source_path   = $Path
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($FrontmatterCategory)) {
        if ($FrontmatterCategory -match '^(?i)category_2|restricted|confidential|secret$') {
            return [pscustomobject]@{
                status      = "fail"
                mode        = "frontmatter"
                issue       = "Source is marked as restricted."
                category    = $FrontmatterCategory
                sanitized   = $Sanitized
                source_path = $Path
            }
        }

        if ($FrontmatterCategory -match '^(?i)category_1$') {
            return [pscustomobject]@{
                status      = "pass"
                mode        = "frontmatter"
                issue       = ""
                category    = $FrontmatterCategory
                sanitized   = $Sanitized
                source_path = $Path
            }
        }
    }

    if ($Sanitized) {
        return [pscustomobject]@{
            status      = "pass"
            mode        = "sanitized_frontmatter"
            issue       = ""
            category    = if ($FrontmatterCategory) { $FrontmatterCategory } else { "category_1" }
            sanitized   = $true
            source_path = $Path
        }
    }

    return [pscustomobject]@{
        status      = "pass"
        mode        = "heuristic"
        issue       = "No explicit category marker found; validated by path and content scan."
        category    = "category_1"
        sanitized   = $false
        source_path = $Path
    }
}

function New-NotebookLMPackagePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LearningAreaRoot,

        [Parameter(Mandatory = $true)]
        [string]$TopicSlug,

        [Parameter(Mandatory = $true)]
        [string]$Timestamp
    )

    $TopicRoot = Join-Path $LearningAreaRoot $TopicSlug
    New-Item -ItemType Directory -Force -Path $TopicRoot | Out-Null

    $BaseName = "{0}-{1}" -f $TopicSlug, $Timestamp
    $Candidate = Join-Path $TopicRoot $BaseName
    $Suffix = 2
    while (Test-Path -LiteralPath $Candidate) {
        $Candidate = Join-Path $TopicRoot ("{0}-{1}" -f $BaseName, $Suffix)
        $Suffix++
    }

    return $Candidate
}

$RepoRoot = $Root
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $RepoRoot "PDA-Backups\notebooklm"
}

$LearningAreaSlug = Get-PDASlug -Text $LearningArea
$TopicSlug = Get-PDASlug -Text $Topic
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$PackageRoot = New-NotebookLMPackagePath -LearningAreaRoot (Join-Path $OutputRoot $LearningAreaSlug) -TopicSlug $TopicSlug -Timestamp $Timestamp

New-Item -ItemType Directory -Force -Path $PackageRoot | Out-Null
$SourcesRoot = Join-Path $PackageRoot "sources"
New-Item -ItemType Directory -Force -Path $SourcesRoot | Out-Null

$SourceManifest = New-Object System.Collections.Generic.List[object]
$ValidationNotes = New-Object System.Collections.Generic.List[string]

foreach ($SourcePath in @($SourcePaths)) {
    if ([string]::IsNullOrWhiteSpace([string]$SourcePath)) {
        throw "Source paths cannot contain blank entries."
    }

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "Source file not found: $SourcePath"
    }

    $RelativePath = Get-PDARepositoryRelativePath -Path $SourcePath -RootPath $RepoRoot
    if ($RelativePath -notmatch '^(Obsidian Vault|PDA-Obsidian-Vault)[\\/]' ) {
        throw "Source file must come from an Obsidian vault path: $SourcePath"
    }

    $Content = Get-Content -LiteralPath $SourcePath -Raw -ErrorAction Stop
    $Validation = Get-PDANoteCategoryValidation -Path $SourcePath -Text $Content
    if ($Validation.status -ne "pass") {
        throw "Category 1 validation failed for '$SourcePath': $($Validation.issue)"
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Validation.issue)) {
        [void]$ValidationNotes.Add(("Source '{0}': {1}" -f $RelativePath, [string]$Validation.issue))
    }

    $DestinationPath = Join-Path $SourcesRoot $RelativePath
    $DestinationDir = Split-Path -Parent $DestinationPath
    New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force

    [void]$SourceManifest.Add([pscustomobject]@{
        source_path        = $SourcePath
        repository_path    = $RelativePath
        copied_path        = $DestinationPath
        category_validation = $Validation
    })
}

$NotebookMap = @{
    "Training"   = "PDA - Training"
    "AI Systems" = "PDA - AI Systems"
    "Research"   = "PDA - Research"
    "Leadership" = "PDA - Leadership"
}

$PackageName = Split-Path -Leaf $PackageRoot
$ManifestPath = Join-Path $PackageRoot "manifest.json"
$SummaryPath = Join-Path $PackageRoot "summary.md"
$QuestionsPath = Join-Path $PackageRoot "questions.md"

$PackageManifest = [pscustomobject]@{}
$PackageManifest | Add-Member -NotePropertyName package_name -NotePropertyValue $PackageName
$PackageManifest | Add-Member -NotePropertyName learning_area -NotePropertyValue $LearningArea
$PackageManifest | Add-Member -NotePropertyName notebooklm_notebook -NotePropertyValue $NotebookMap[$LearningArea]
$PackageManifest | Add-Member -NotePropertyName topic -NotePropertyValue $Topic
$PackageManifest | Add-Member -NotePropertyName category -NotePropertyValue "category_1"
$PackageManifest | Add-Member -NotePropertyName sanitized -NotePropertyValue $true
$PackageManifest | Add-Member -NotePropertyName created_at -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("o"))
$PackageManifest | Add-Member -NotePropertyName source_count -NotePropertyValue ([int]$SourceManifest.Count)
$PackageManifest | Add-Member -NotePropertyName source_files -NotePropertyValue (@($SourceManifest.ToArray()))
$PackageManifest | Add-Member -NotePropertyName redaction_notes -NotePropertyValue (@($RedactionNotes))
$PackageManifest | Add-Member -NotePropertyName validation_notes -NotePropertyValue (@($ValidationNotes))
$PackageManifest | Add-Member -NotePropertyName package_path -NotePropertyValue $PackageRoot

$PackageManifest | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8

$SummaryLines = New-Object System.Collections.Generic.List[string]
$SummaryLines.Add("# NotebookLM Package Summary")
$SummaryLines.Add("")
$SummaryLines.Add(("Learning area: {0}" -f $LearningArea))
$SummaryLines.Add(("Topic: {0}" -f $Topic))
$SummaryLines.Add(("Created at: {0}" -f $PackageManifest.created_at))
$SummaryLines.Add(("NotebookLM notebook: {0}" -f $PackageManifest.notebooklm_notebook))
$SummaryLines.Add("")
if (-not [string]::IsNullOrWhiteSpace($Summary)) {
    $SummaryLines.Add($Summary.Trim())
}
else {
    $SummaryLines.Add("Sanitized learning package prepared for NotebookLM upload.")
}
if ($ValidationNotes.Count -gt 0) {
    $SummaryLines.Add("")
    $SummaryLines.Add("## Validation Notes")
    foreach ($Note in $ValidationNotes) {
        $SummaryLines.Add(("- {0}" -f $Note))
    }
}
$SummaryLines | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

$QuestionLines = New-Object System.Collections.Generic.List[string]
$QuestionLines.Add("# NotebookLM Questions")
$QuestionLines.Add("")
if ($Questions -and @($Questions).Count -gt 0) {
    foreach ($Question in @($Questions)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Question)) {
            $QuestionLines.Add(("- {0}" -f $Question.Trim()))
        }
    }
}
else {
    $QuestionLines.Add("- What are the main ideas?")
    $QuestionLines.Add("- Which patterns repeat across the sources?")
    $QuestionLines.Add("- What should I remember later?")
    $QuestionLines.Add("- What can be reused in future work?")
    $QuestionLines.Add("- What are the open questions or gaps?")
}
$QuestionLines | Set-Content -LiteralPath $QuestionsPath -Encoding UTF8

$Result = [pscustomobject]@{}
$Result | Add-Member -NotePropertyName status -NotePropertyValue "pass"
$Result | Add-Member -NotePropertyName learning_area -NotePropertyValue $LearningArea
$Result | Add-Member -NotePropertyName topic -NotePropertyValue $Topic
$Result | Add-Member -NotePropertyName package_name -NotePropertyValue $PackageName
$Result | Add-Member -NotePropertyName package_path -NotePropertyValue $PackageRoot
$Result | Add-Member -NotePropertyName manifest_path -NotePropertyValue $ManifestPath
$Result | Add-Member -NotePropertyName summary_path -NotePropertyValue $SummaryPath
$Result | Add-Member -NotePropertyName questions_path -NotePropertyValue $QuestionsPath
$Result | Add-Member -NotePropertyName source_count -NotePropertyValue ([int]$SourceManifest.Count)
$Result | Add-Member -NotePropertyName notebooklm_notebook -NotePropertyValue $NotebookMap[$LearningArea]
$Result | Add-Member -NotePropertyName validation_notes -NotePropertyValue (@($ValidationNotes))
$Result | Add-Member -NotePropertyName source_files -NotePropertyValue (@($SourceManifest.ToArray()))

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 40
    return
}

Write-Host "[OK] NotebookLM package created"
Write-Host ("Learning area : {0}" -f $Result.learning_area)
Write-Host ("Topic         : {0}" -f $Result.topic)
Write-Host ("Package path  : {0}" -f $Result.package_path)
Write-Host ("Sources       : {0}" -f $Result.source_count)
Write-Host ("NotebookLM    : {0}" -f $Result.notebooklm_notebook)
if ($ValidationNotes.Count -gt 0) {
    Write-Host "Validation notes:"
    foreach ($Note in $ValidationNotes) {
        Write-Host ("- {0}" -f $Note)
    }
}
