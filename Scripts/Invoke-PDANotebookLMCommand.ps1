[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Text,

    [Parameter(Mandatory = $false)]
    [string]$Project = "AI Ecosystem",

    [Parameter(Mandatory = $false)]
    [string]$ConversationId,

    [Parameter(Mandatory = $false)]
    [string]$SessionId,

    [Parameter(Mandatory = $false)]
    [string]$UserId,

    [Parameter(Mandatory = $false)]
    [string]$ConversationTitle,

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "PDA_TaskOntology.ps1")
. (Join-Path $PSScriptRoot "PDA_OutputParsing.ps1")

$NotebookLMPackageScript = Join-Path $PSScriptRoot "New-PDANotebookLMPackage.ps1"

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

function Split-PDANotebookLMValueList {
    param([Parameter(Mandatory = $false)][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $Items = New-Object System.Collections.Generic.List[string]
    foreach ($Chunk in @($Text -split '(?:\r?\n|;|\|)')) {
        $Value = [string]$Chunk
        if ($Value -match '^\s*[-*]\s+(.*)$') {
            $Value = [string]$Matches[1]
        }

        $Value = $Value.Trim()
        if (-not [string]::IsNullOrWhiteSpace($Value)) {
            [void]$Items.Add($Value)
        }
    }

    return @($Items.ToArray())
}

function Set-PDANotebookLMField {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Payload,

        [Parameter(Mandatory = $true)]
        [string]$Field,

        [Parameter(Mandatory = $true)]
        [string[]]$Buffer
    )

    $Joined = (@($Buffer) -join "`n").Trim()
    switch ($Field) {
        "LearningArea" {
            if (-not [string]::IsNullOrWhiteSpace($Joined)) {
                $Payload.learning_area = $Joined.Split("`n")[0].Trim()
            }
        }
        "Topic" {
            if (-not [string]::IsNullOrWhiteSpace($Joined)) {
                $Payload.topic = $Joined.Split("`n")[0].Trim()
            }
        }
        "SourcePaths" {
            $Payload.source_paths = @(Split-PDANotebookLMValueList -Text $Joined)
        }
        "Summary" {
            $Payload.summary = $Joined
        }
        "Questions" {
            $Payload.questions = @(Split-PDANotebookLMValueList -Text $Joined)
        }
        "RedactionNotes" {
            $Payload.redaction_notes = @(Split-PDANotebookLMValueList -Text $Joined)
        }
    }
}

function Parse-PDANotebookLMCommandText {
    param([Parameter(Mandatory = $true)][string]$CommandText)

    $Payload = @{
        learning_area   = ""
        topic           = ""
        source_paths    = @()
        summary         = ""
        questions       = @()
        redaction_notes = @()
    }

    $CurrentField = ""
    $Buffer = New-Object System.Collections.Generic.List[string]
    $Lines = @($CommandText -split "`r?`n")

    foreach ($Line in $Lines) {
        $WorkingLine = [string]$Line
        if ($WorkingLine -match '^\s*/notebooklm\b(.*)$') {
            $WorkingLine = [string]$Matches[1]
        }

        $Trimmed = $WorkingLine.Trim()

        if ($Trimmed -match '^\s*(LearningArea|Topic|SourcePaths|Summary|Questions|RedactionNotes)\s*[:=]\s*(.*)$') {
            if ($CurrentField) {
                Set-PDANotebookLMField -Payload $Payload -Field $CurrentField -Buffer @($Buffer.ToArray())
            }

            $CurrentField = [string]$Matches[1]
            $Buffer.Clear()

            $InitialValue = [string]$Matches[2]
            if (-not [string]::IsNullOrWhiteSpace($InitialValue)) {
                [void]$Buffer.Add($InitialValue.Trim())
            }
            continue
        }

        if ([string]::IsNullOrWhiteSpace($Trimmed)) {
            if ($CurrentField -eq "Summary") {
                [void]$Buffer.Add("")
            }
            continue
        }

        if ($Trimmed -match '^\s*[-*]\s+(.*)$' -and $CurrentField) {
            [void]$Buffer.Add([string]$Matches[1])
            continue
        }

        if ($CurrentField) {
            [void]$Buffer.Add($Trimmed)
        }
    }

    if ($CurrentField) {
        Set-PDANotebookLMField -Payload $Payload -Field $CurrentField -Buffer @($Buffer.ToArray())
    }

    return [pscustomobject]$Payload
}

function Test-PDANotebookLMInput {
    param([Parameter(Mandatory = $true)]$Payload)

    if ([string]::IsNullOrWhiteSpace([string]$Payload.learning_area)) {
        throw "NotebookLM command is missing LearningArea."
    }
    if ([string]::IsNullOrWhiteSpace([string]$Payload.topic)) {
        throw "NotebookLM command is missing Topic."
    }
    if (-not $Payload.source_paths -or @($Payload.source_paths).Count -eq 0) {
        throw "NotebookLM command is missing SourcePaths."
    }
}

function New-PDANotebookLMResultMarkdown {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Payload
    )

    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add("# PDA NotebookLM Command Result")
    $Lines.Add("")
    $Lines.Add(("Status: {0}" -f $Result.status))
    $Lines.Add(("Task ID: {0}" -f $Result.task_id))
    $Lines.Add(("Command: {0}" -f $Result.command))
    $Lines.Add(("Learning area: {0}" -f $Payload.learning_area))
    $Lines.Add(("Topic: {0}" -f $Payload.topic))
    $Lines.Add(("NotebookLM notebook: {0}" -f $Result.notebooklm_notebook))
    $Lines.Add(("Package path: {0}" -f $Result.package_path))
    $Lines.Add(("Manifest path: {0}" -f $Result.manifest_path))
    $Lines.Add(("Summary path: {0}" -f $Result.package_summary_path))
    $Lines.Add(("Questions path: {0}" -f $Result.questions_path))
    $Lines.Add(("Result path: {0}" -f $Result.result_path))
    $Lines.Add(("Source count: {0}" -f $Result.source_count))
    $Lines.Add("")
    $Lines.Add("## Source Files")
    foreach ($Source in @($Result.source_files)) {
        $Lines.Add(("- {0}" -f [string]$Source.repository_path))
    }
    if ($Result.validation_notes -and @($Result.validation_notes).Count -gt 0) {
        $Lines.Add("")
        $Lines.Add("## Validation Notes")
        foreach ($Note in @($Result.validation_notes)) {
            $Lines.Add(("- {0}" -f [string]$Note))
        }
    }
    $Lines.Add("")
    $Lines.Add("## Next Action")
    $Lines.Add("Upload the package files to NotebookLM manually using the project notebook for the learning area.")

    return @($Lines)
}

if (-not (Test-Path -Path $NotebookLMPackageScript -PathType Leaf)) {
    throw "NotebookLM package generator missing: $NotebookLMPackageScript"
}

$Payload = Parse-PDANotebookLMCommandText -CommandText $Text
Test-PDANotebookLMInput -Payload $Payload

$TaskId = "notebooklm-{0}" -f ([guid]::NewGuid().ToString())
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
$LearningAreaSlug = Get-PDASlug -Text $Payload.learning_area
$TopicSlug = Get-PDASlug -Text $Payload.topic
$ResultsRoot = Join-Path $Root "PDA-Tasks\results"
New-Item -ItemType Directory -Force -Path $ResultsRoot | Out-Null

$GeneratorInvocation = @{
    LearningArea = $Payload.learning_area
    Topic        = $Payload.topic
    SourcePaths  = @($Payload.source_paths)
    Root         = $Root
    AsJson       = $true
}

if (-not [string]::IsNullOrWhiteSpace([string]$Payload.summary)) {
    $GeneratorInvocation.Summary = [string]$Payload.summary
}
if ($Payload.questions -and @($Payload.questions).Count -gt 0) {
    $GeneratorInvocation.Questions = @($Payload.questions)
}
if ($Payload.redaction_notes -and @($Payload.redaction_notes).Count -gt 0) {
    $GeneratorInvocation.RedactionNotes = @($Payload.redaction_notes)
}

$RawGenerator = & $NotebookLMPackageScript @GeneratorInvocation 2>&1
$GeneratorText = [string]($RawGenerator -join "`n").Trim()
if ([string]::IsNullOrWhiteSpace($GeneratorText)) {
    throw "NotebookLM package generator returned no output."
}

$Package = ConvertFrom-PDAMixedJson -Text $GeneratorText -SourceName $NotebookLMPackageScript

$ResultBaseName = "{0}-{1}-notebooklm-result" -f $Timestamp, $TopicSlug
$ResultPath = Join-Path $ResultsRoot ("{0}.json" -f $ResultBaseName)
$ReportPath = Join-Path $ResultsRoot ("{0}.md" -f $ResultBaseName)

$Result = [pscustomobject]@{
    status               = "pass"
    command              = "/notebooklm"
    task_id              = $TaskId
    task_status          = "completed"
    dispatch_status      = "completed"
    bridge_status        = "completed"
    intent               = "notebooklm_package"
    task_type            = "notebooklm_package"
    recommended_command  = "/notebooklm"
    confidence           = 1
    requires_confirmation = $false
    response_text        = "NotebookLM package created for $($Payload.learning_area) / $($Payload.topic). Package path: $($Package.package_path)"
    next_action          = "Review the package metadata and upload the sanitized package to NotebookLM manually."
    learning_area        = $Package.learning_area
    topic                = $Package.topic
    notebooklm_notebook  = $Package.notebooklm_notebook
    package_name         = $Package.package_name
    package_path         = $Package.package_path
    manifest_path        = $Package.manifest_path
    package_summary_path = $Package.summary_path
    summary_path         = $Package.summary_path
    questions_path       = $Package.questions_path
    result_path          = $ResultPath
    result_report_path   = $ReportPath
    source_count         = [int]$Package.source_count
    source_files         = @($Package.source_files)
    validation_notes     = @($Package.validation_notes)
    source_of_truth      = "Scripts/New-PDANotebookLMPackage.ps1"
    conversation_id      = $(if ($ConversationId) { $ConversationId } else { "" })
    session_id           = $SessionId
    user_id              = $UserId
    conversation_title   = $ConversationTitle
    timestamp            = $Timestamp
}

$Result | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $ResultPath -Encoding UTF8
(New-PDANotebookLMResultMarkdown -Result $Result -Payload $Payload) | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 40
    return
}

Write-Host "[OK] NotebookLM package command completed"
Write-Host ("Learning area   : {0}" -f $Result.learning_area)
Write-Host ("Topic           : {0}" -f $Result.topic)
Write-Host ("NotebookLM      : {0}" -f $Result.notebooklm_notebook)
Write-Host ("Package path    : {0}" -f $Result.package_path)
Write-Host ("Result path     : {0}" -f $Result.result_path)
Write-Host ("Report path     : {0}" -f $Result.result_report_path)
Write-Host ("Source count    : {0}" -f $Result.source_count)
