[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$RoadmapPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\PDA-Roadmap.json"),

    [Parameter(Mandatory = $false)]
    [string]$PacketRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\work-packets"),

    [Parameter(Mandatory = $false)]
    [string]$StagingRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "PDA-Tasks\staging\nightly-build"),

    [Parameter(Mandatory = $false)]
    [string]$PromptRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\codex-prompts"),

    [Parameter(Mandatory = $false)]
    [string]$TaskId = "",

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PDA_NightlyAutomation.ps1")

function Get-PDAFirstExistingPath {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Paths
    )

    foreach ($Path in $Paths) {
        if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return $Path
        }
    }

    return ""
}

function Get-LatestPDANightlyPacketSource {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$RoadmapPath,

        [Parameter(Mandatory = $true)]
        [string]$PacketRoot,

        [Parameter(Mandatory = $true)]
        [string]$StagingRoot,

        [Parameter(Mandatory = $false)]
        [string]$TaskId = ""
    )

    $Roadmap = Import-PDANightlyRoadmap -Root $Root -RoadmapPath $RoadmapPath
    if ([string]::IsNullOrWhiteSpace($TaskId)) {
        $TaskId = [string]$Roadmap.current_task_id
    }

    $SummaryFile = $null
    if (Test-Path -LiteralPath $StagingRoot -PathType Container) {
        foreach ($Candidate in @(Get-ChildItem -LiteralPath $StagingRoot -Recurse -File -Filter "handoff-summary.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)) {
            if ([string]::IsNullOrWhiteSpace($TaskId)) {
                $SummaryFile = $Candidate
                break
            }

            try {
                $Content = Get-Content -LiteralPath $Candidate.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if ([string]$Content.task_id -eq $TaskId) {
                    $SummaryFile = $Candidate
                    break
                }
            }
            catch {
                continue
            }
        }
    }

    if ($SummaryFile) {
        $Summary = Read-PDANightlyJsonFile -Path $SummaryFile.FullName
        $SummaryTaskId = if ($Summary -and $Summary.PSObject.Properties.Name -contains "task_id") { [string]$Summary.task_id } else { $TaskId }
        $PacketJsonPath = [string]($Summary.work_packet_json_path)
        if ([string]::IsNullOrWhiteSpace($PacketJsonPath) -or -not (Test-Path -LiteralPath $PacketJsonPath -PathType Leaf)) {
            $PacketLookup = Find-PDANightlyWorkPacket -Root $Root -TaskId $SummaryTaskId -PacketRoot $PacketRoot
            if ($PacketLookup) {
                $PacketJsonPath = [string]$PacketLookup.json_path
                $MarkdownPath = [string]$PacketLookup.markdown_path
            }
        }

        if ([string]::IsNullOrWhiteSpace($PacketJsonPath)) {
            throw "Unable to resolve work packet from staged summary: $($SummaryFile.FullName)"
        }

        $Packet = Read-PDANightlyJsonFile -Path $PacketJsonPath
        if (-not $Packet) {
            throw "Work packet could not be read: $PacketJsonPath"
        }

        if ([string]::IsNullOrWhiteSpace($MarkdownPath)) {
            $MarkdownPath = Get-PDAFirstExistingPath -Paths @(
                [string]($Summary.work_packet_markdown_path),
                ([System.IO.Path]::ChangeExtension($PacketJsonPath, ".md"))
            )
        }

        return [pscustomobject]@{
            source_kind           = "staged_summary"
            summary_path          = $SummaryFile.FullName
            packet_json_path      = $PacketJsonPath
            packet_markdown_path  = $MarkdownPath
            summary               = $Summary
            packet                = $Packet
        }
    }

    $PacketLookup = Find-PDANightlyWorkPacket -Root $Root -TaskId $TaskId -PacketRoot $PacketRoot
    if ($PacketLookup) {
        return [pscustomobject]@{
            source_kind           = "work_packet"
            summary_path          = ""
            packet_json_path      = $PacketLookup.json_path
            packet_markdown_path  = $PacketLookup.markdown_path
            summary               = $null
            packet                = $PacketLookup.packet
        }
    }

    throw "No staged nightly task packet or work packet could be found."
}

function New-PDACodexExecutionPromptObject {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$PromptRoot
    )

    $Packet = $Source.packet
    $AllowedFiles = @($Packet.allowed_files) | ForEach-Object { [string]$_ }
    $RequiredTests = @($Packet.required_tests) | ForEach-Object { [string]$_ }
    $StopConditions = @($Packet.stop_conditions) | ForEach-Object { [string]$_ }
    $ExpectedOutputFormat = @(
        "Progress: X%"
        "What Changed"
        "Validation Results"
        "Files Modified"
        "Remaining Risks"
        "Recommended Next Step"
    )

    $PromptLines = New-Object System.Collections.Generic.List[string]
    $PromptLines.Add("You are Codex working on the PDA Nightly Automation execution handoff.")
    $PromptLines.Add(("Task ID: {0}" -f [string]$Packet.task_id))
    $PromptLines.Add(("Title: {0}" -f [string]$Packet.title))
    $PromptLines.Add(("Objective: {0}" -f [string]$Packet.objective))
    if ($Packet.PSObject.Properties.Name -contains "branch_name" -and -not [string]::IsNullOrWhiteSpace([string]$Packet.branch_name)) {
        $PromptLines.Add(("Branch: {0}" -f [string]$Packet.branch_name))
    }
    $PromptLines.Add("")
    $PromptLines.Add("Rules:")
    $PromptLines.Add("- Work only within the allowed files listed below.")
    $PromptLines.Add("- Do not commit, push, auto-approve, or delete queue entries.")
    $PromptLines.Add("- Stop if a required test fails, a secret is encountered, or the scope expands beyond the packet.")
    $PromptLines.Add("- Return the requested output format exactly and keep diagnostics concise.")
    $PromptLines.Add("")
    $PromptLines.Add("Allowed files:")
    foreach ($Item in $AllowedFiles) {
        $PromptLines.Add(("- {0}" -f $Item))
    }
    $PromptLines.Add("")
    $PromptLines.Add("Required tests:")
    foreach ($Item in $RequiredTests) {
        $PromptLines.Add(("- {0}" -f $Item))
    }
    $PromptLines.Add("")
    $PromptLines.Add("Stop conditions:")
    foreach ($Item in $StopConditions) {
        $PromptLines.Add(("- {0}" -f $Item))
    }
    $PromptLines.Add("")
    $PromptLines.Add("Expected output format:")
    foreach ($Item in $ExpectedOutputFormat) {
        $PromptLines.Add(("- {0}" -f $Item))
    }

    $PromptText = $PromptLines -join "`n"
    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $FileBase = "$([string]$Packet.task_id)-$Timestamp"
    $JsonPath = Join-Path $PromptRoot "$FileBase.json"
    $MarkdownPath = Join-Path $PromptRoot "$FileBase.md"

    return [pscustomobject]@{
        schema_version            = "1.0"
        artifact_type             = "pda_codex_execution_prompt"
        generated_at              = (Get-Date).ToUniversalTime().ToString("o")
        root_path                 = $Root
        prompt_root               = $PromptRoot
        source_kind               = $Source.source_kind
        source_summary_path       = [string]$Source.summary_path
        source_packet_json_path   = [string]$Source.packet_json_path
        source_packet_markdown_path = [string]$Source.packet_markdown_path
        task_id                   = [string]$Packet.task_id
        title                     = [string]$Packet.title
        objective                 = [string]$Packet.objective
        branch_name               = [string]$Packet.branch_name
        allowed_files             = @($AllowedFiles)
        required_tests            = @($RequiredTests)
        stop_conditions           = @($StopConditions)
        expected_output_format    = @($ExpectedOutputFormat)
        copy_paste_prompt         = $PromptText
        json_path                 = $JsonPath
        markdown_path             = $MarkdownPath
        packet                    = $Packet
        summary                   = $Source.summary
    }
}

function Save-PDACodexExecutionPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Prompt
    )

    New-Item -ItemType Directory -Force -Path $Prompt.prompt_root | Out-Null
    $Prompt | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Prompt.json_path -Encoding UTF8

    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add("# PDA Codex Execution Prompt")
    $Lines.Add("")
    $Lines.Add(("Generated at: {0}" -f $Prompt.generated_at))
    $Lines.Add(("Task ID: {0}" -f $Prompt.task_id))
    $Lines.Add(("Title: {0}" -f $Prompt.title))
    $Lines.Add(("Objective: {0}" -f $Prompt.objective))
    if (-not [string]::IsNullOrWhiteSpace($Prompt.branch_name)) {
        $Lines.Add(("Branch: {0}" -f $Prompt.branch_name))
    }
    $Lines.Add("")
    $Lines.Add('## Copy/Paste Prompt')
    $Lines.Add('```text')
    $Lines.Add($Prompt.copy_paste_prompt)
    $Lines.Add('```')
    $Lines.Add("")
    $Lines.Add('## Allowed Files')
    foreach ($Item in @($Prompt.allowed_files)) {
        $Lines.Add(("- {0}" -f $Item))
    }
    $Lines.Add("")
    $Lines.Add('## Required Tests')
    foreach ($Item in @($Prompt.required_tests)) {
        $Lines.Add(("- {0}" -f $Item))
    }
    $Lines.Add("")
    $Lines.Add('## Stop Conditions')
    foreach ($Item in @($Prompt.stop_conditions)) {
        $Lines.Add(("- {0}" -f $Item))
    }
    $Lines.Add("")
    $Lines.Add('## Expected Output Format')
    foreach ($Item in @($Prompt.expected_output_format)) {
        $Lines.Add(("- {0}" -f $Item))
    }
    $Lines.Add("")
    $Lines.Add('## Source')
    if (-not [string]::IsNullOrWhiteSpace($Prompt.source_summary_path)) {
        $Lines.Add(("Staged summary: {0}" -f $Prompt.source_summary_path))
    }
    $Lines.Add(("Work packet JSON: {0}" -f $Prompt.source_packet_json_path))
    if (-not [string]::IsNullOrWhiteSpace($Prompt.source_packet_markdown_path)) {
        $Lines.Add(("Work packet markdown: {0}" -f $Prompt.source_packet_markdown_path))
    }

    $Lines | Set-Content -LiteralPath $Prompt.markdown_path -Encoding UTF8

    return [pscustomobject]@{
        status        = "pass"
        json_path     = $Prompt.json_path
        markdown_path = $Prompt.markdown_path
        prompt        = $Prompt
    }
}

$Source = Get-LatestPDANightlyPacketSource -Root $Root -RoadmapPath $RoadmapPath -PacketRoot $PacketRoot -StagingRoot $StagingRoot -TaskId $TaskId
$Prompt = New-PDACodexExecutionPromptObject -Source $Source -Root $Root -PromptRoot $PromptRoot
$Saved = Save-PDACodexExecutionPrompt -Prompt $Prompt

$Result = [pscustomobject]@{
    status                   = "pass"
    task_id                  = $Prompt.task_id
    source_kind              = $Prompt.source_kind
    source_summary_path      = $Prompt.source_summary_path
    source_packet_json_path  = $Prompt.source_packet_json_path
    source_packet_markdown_path = $Prompt.source_packet_markdown_path
    json_path                = $Saved.json_path
    markdown_path            = $Saved.markdown_path
    copy_paste_prompt        = $Prompt.copy_paste_prompt
    allowed_files            = @($Prompt.allowed_files)
    required_tests           = @($Prompt.required_tests)
    stop_conditions          = @($Prompt.stop_conditions)
    expected_output_format   = @($Prompt.expected_output_format)
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 40
    return
}

Write-Host "[OK] PDA Codex execution prompt exported."
Write-Host ("Task        : {0}" -f $Prompt.task_id)
Write-Host ("JSON path   : {0}" -f $Saved.json_path)
Write-Host ("Markdown path: {0}" -f $Saved.markdown_path)
