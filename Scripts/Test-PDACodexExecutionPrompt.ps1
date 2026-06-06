[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PDA_OutputParsing.ps1")

$Root = Split-Path -Parent $PSScriptRoot
$RoadmapPath = Join-Path $Root "Roadmap\PDA-Roadmap.json"
$HelperScript = Join-Path $PSScriptRoot "PDA_NightlyAutomation.ps1"
$StateScript = Join-Path $PSScriptRoot "Get-PDANightlyTaskState.ps1"
$UpdateScript = Join-Path $PSScriptRoot "Update-PDARoadmapStatus.ps1"
$PacketScript = Join-Path $PSScriptRoot "Generate-PDACodexWorkPacket.ps1"
$MorningScript = Join-Path $PSScriptRoot "Generate-PDAMorningReport.ps1"
$OrchestratorScript = Join-Path $PSScriptRoot "Invoke-PDABuildOrchestrator.ps1"
$StartScript = Join-Path $PSScriptRoot "Start-PDANightlyBuild.ps1"
$ExporterScript = Join-Path $PSScriptRoot "Export-PDACodexExecutionPrompt.ps1"

foreach ($Path in @($RoadmapPath, $HelperScript, $StateScript, $UpdateScript, $PacketScript, $MorningScript, $OrchestratorScript, $StartScript, $ExporterScript)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file missing: $Path"
    }
}

function Invoke-PDAJsonScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $Raw = & pwsh -NoProfile -File $Path @Arguments -AsJson 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Command returned empty output: $Path"
    }
    $Result = ConvertFrom-PDAMixedJson -Text $Text -SourceName $Path
    if ($LASTEXITCODE -ne 0 -and (-not $Result.PSObject.Properties.Name -contains "status" -or [string]$Result.status -ne "pass")) {
        throw "Command failed: $Path"
    }

    return $Result
}

function Initialize-PDATempRepo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot,

        [Parameter(Mandatory = $true)]
        [string]$SourceRoot
    )

    New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null
    foreach ($Folder in @("Roadmap", "Scripts")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $DestinationRoot $Folder) | Out-Null
    }

    & git init $DestinationRoot | Out-Null
    & git -C $DestinationRoot config user.name "Codex Test" | Out-Null
    & git -C $DestinationRoot config user.email "codex@example.com" | Out-Null
    & git -C $DestinationRoot commit --allow-empty -m "seed" | Out-Null
    & git -C $DestinationRoot branch -M main | Out-Null

    foreach ($Path in @(
        "Roadmap\PDA-Roadmap.json",
        "Scripts\PDA_OutputParsing.ps1",
        "Scripts\PDA_NightlyAutomation.ps1",
        "Scripts\PDA_BuildRunner.ps1",
        "Scripts\Get-PDANightlyTaskState.ps1",
        "Scripts\Get-PDABuildRunnerTaskState.ps1",
        "Scripts\Update-PDARoadmapStatus.ps1",
        "Scripts\Generate-PDACodexWorkPacket.ps1",
        "Scripts\Generate-PDAMorningReport.ps1",
        "Scripts\Generate-PDARunReport.ps1",
        "Scripts\Invoke-PDAQueueBacklogAudit.ps1",
        "Scripts\Test-PDAQueueBacklogAudit.ps1",
        "Scripts\Invoke-PDABuildOrchestrator.ps1",
        "Scripts\Invoke-PDABuildRunner.ps1",
        "Scripts\Start-PDANightlyBuild.ps1",
        "Scripts\Start-PDABuildRunner.ps1",
        "Scripts\Backup-PDARepo.ps1",
        "Scripts\Backup-PDAVolumes.ps1",
        "Scripts\Export-PDACodexExecutionPrompt.ps1",
        "Scripts\PDA_BuildRunnerPolicy.json"
    )) {
        Copy-Item -Force (Join-Path $SourceRoot $Path) (Join-Path $DestinationRoot $Path)
    }

    $ExcludePath = Join-Path $DestinationRoot ".git\info\exclude"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ExcludePath) | Out-Null
    @(
        "Roadmap/",
        "Roadmap/work-packets/",
        "Roadmap/codex-prompts/",
        "PDA-Tasks/",
        "PDA-Backups/",
        "Scripts/PDA_OutputParsing.ps1",
        "Scripts/PDA_NightlyAutomation.ps1",
        "Scripts/PDA_BuildRunner.ps1",
        "Scripts/Get-PDANightlyTaskState.ps1",
        "Scripts/Get-PDABuildRunnerTaskState.ps1",
        "Scripts/Update-PDARoadmapStatus.ps1",
        "Scripts/Generate-PDACodexWorkPacket.ps1",
        "Scripts/Generate-PDAMorningReport.ps1",
        "Scripts/Generate-PDARunReport.ps1",
        "Scripts/Invoke-PDAQueueBacklogAudit.ps1",
        "Scripts/Test-PDAQueueBacklogAudit.ps1",
        "Scripts/Invoke-PDABuildOrchestrator.ps1",
        "Scripts/Invoke-PDABuildRunner.ps1",
        "Scripts/Start-PDANightlyBuild.ps1",
        "Scripts/Start-PDABuildRunner.ps1",
        "Scripts/Backup-PDARepo.ps1",
        "Scripts/Backup-PDAVolumes.ps1",
        "Scripts/Export-PDACodexExecutionPrompt.ps1",
        "Scripts\PDA_BuildRunnerPolicy.json"
    ) | Add-Content -Path $ExcludePath
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pda-codex-prompt-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$TempRepoRoot = Join-Path $TempRoot "repo"
Initialize-PDATempRepo -DestinationRoot $TempRepoRoot -SourceRoot $Root

$Roadmap = Invoke-PDAJsonScript -Path $StateScript -Arguments @(
    "-Root", $TempRepoRoot,
    "-RoadmapPath", (Join-Path $TempRepoRoot "Roadmap\PDA-Roadmap.json"),
    "-TaskId", "task-001"
)

$Issues = New-Object System.Collections.Generic.List[string]
if ($Roadmap.task_state.status -ne "backlog") {
    $Issues.Add("Initial task state should be backlog.")
}

$OrchestratorPrepare = Invoke-PDAJsonScript -Path $OrchestratorScript -Arguments @(
    "-Root", $TempRepoRoot,
    "-RoadmapPath", (Join-Path $TempRepoRoot "Roadmap\PDA-Roadmap.json"),
    "-OutputRoot", $TempRoot,
    "-PrepareExecution"
)

& git -C $TempRepoRoot add -f Roadmap/PDA-Roadmap.json | Out-Null
& git -C $TempRepoRoot commit -m "prepare codex prompt source state" | Out-Null

$ExecuteRepoRoot = Join-Path $TempRoot "execute-repo"
Initialize-PDATempRepo -DestinationRoot $ExecuteRepoRoot -SourceRoot $TempRepoRoot
& git -C $ExecuteRepoRoot add -f Roadmap/PDA-Roadmap.json | Out-Null
& git -C $ExecuteRepoRoot commit -m "prepare execution state" | Out-Null

$OrchestratorExecute = Invoke-PDAJsonScript -Path $OrchestratorScript -Arguments @(
    "-Root", $ExecuteRepoRoot,
    "-RoadmapPath", (Join-Path $ExecuteRepoRoot "Roadmap\PDA-Roadmap.json"),
    "-OutputRoot", $TempRoot,
    "-ExecutePreparedTask",
    "-ExportCodexExecutionPrompt"
)

$Exporter = Invoke-PDAJsonScript -Path $ExporterScript -Arguments @(
    "-Root", $ExecuteRepoRoot,
    "-RoadmapPath", (Join-Path $ExecuteRepoRoot "Roadmap\PDA-Roadmap.json")
    "-PacketRoot", (Join-Path $ExecuteRepoRoot "Roadmap\work-packets"),
    "-StagingRoot", (Join-Path $ExecuteRepoRoot "PDA-Tasks\staging\nightly-build"),
    "-PromptRoot", (Join-Path $ExecuteRepoRoot "Roadmap\codex-prompts"),
    "-TaskId", "task-001"
)

if ($OrchestratorPrepare.selected_task_id -ne "task-001") {
    $Issues.Add("Prepare mode did not select task-001.")
}

if ($OrchestratorExecute.selected_task_id -ne "task-001") {
    $Issues.Add("Execution mode did not select task-001.")
}

if ($OrchestratorExecute.codex_prompt_path -and -not (Test-Path -LiteralPath $OrchestratorExecute.codex_prompt_path -PathType Leaf)) {
    $Issues.Add("Orchestrator did not write the Codex prompt JSON.")
}

if ($OrchestratorExecute.codex_prompt_markdown_path -and -not (Test-Path -LiteralPath $OrchestratorExecute.codex_prompt_markdown_path -PathType Leaf)) {
    $Issues.Add("Orchestrator did not write the Codex prompt markdown.")
}

if ($Exporter.source_kind -ne "staged_summary") {
    $Issues.Add("Exporter did not read the staged nightly summary.")
}

if (-not (Test-Path -LiteralPath $Exporter.json_path -PathType Leaf)) {
    $Issues.Add("Exporter did not write the Codex prompt JSON.")
}

if (-not (Test-Path -LiteralPath $Exporter.markdown_path -PathType Leaf)) {
    $Issues.Add("Exporter did not write the Codex prompt markdown.")
}

$PromptText = Get-Content -LiteralPath $Exporter.markdown_path -Raw
foreach ($Expected in @("Copy/Paste Prompt", "Allowed Files", "Required Tests", "Stop Conditions", "Expected Output Format")) {
    if ($PromptText -notmatch [regex]::Escape($Expected)) {
        $Issues.Add("Prompt markdown missing section: $Expected")
    }
}

if ($PromptText -notmatch [regex]::Escape("Progress: X%")) {
    $Issues.Add("Prompt output format should include Progress: X%.")
}

$Report = [pscustomobject]@{
    status                        = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    roadmap_path                  = (Join-Path $ExecuteRepoRoot "Roadmap\PDA-Roadmap.json")
    prepare_mode                  = $OrchestratorPrepare.mode
    execute_mode                  = $OrchestratorExecute.mode
    exporter_source_kind          = $Exporter.source_kind
    codex_prompt_json_path        = $Exporter.json_path
    codex_prompt_markdown_path    = $Exporter.markdown_path
    codex_prompt_text_contains    = @("Copy/Paste Prompt", "Allowed Files", "Required Tests", "Stop Conditions", "Expected Output Format")
    issues                        = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 40
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA Codex execution prompt validation failed."
    }
    return
}

Write-Host "[*] PDA Codex execution prompt tests"
Write-Host ("Status      : {0}" -f $Report.status)
Write-Host ("JSON path   : {0}" -f $Report.codex_prompt_json_path)
Write-Host ("Markdown path: {0}" -f $Report.codex_prompt_markdown_path)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA Codex execution prompt validation failed."
}
