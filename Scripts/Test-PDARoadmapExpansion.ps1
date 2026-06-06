[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PDA_NightlyAutomation.ps1")

$Root = Split-Path -Parent $PSScriptRoot
$RoadmapPath = Join-Path $Root "Roadmap\PDA-Roadmap.json"
$PacketRoot = Join-Path $Root "Roadmap\work-packets"

function Get-LatestPacketForTask {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskId
    )

    if (-not (Test-Path -LiteralPath $PacketRoot -PathType Container)) {
        return $null
    }

    $Files = @(
        Get-ChildItem -LiteralPath $PacketRoot -File -Filter "$TaskId-*.json" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending
    )
    return @($Files | Select-Object -First 1)[0]
}

$Issues = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $RoadmapPath -PathType Leaf)) {
    throw "Roadmap file not found: $RoadmapPath"
}

$Roadmap = Get-Content -LiteralPath $RoadmapPath -Raw | ConvertFrom-Json -ErrorAction Stop
$ExpectedTaskIds = @("task-002","task-003","task-004","task-005","task-006","task-007","task-008","task-009")
$ActualTaskIds = @($Roadmap.tasks | ForEach-Object { [string]$_.id })

if ($Roadmap.current_task_id -ne "task-001") {
    $Issues.Add("Roadmap current_task_id should remain task-001.")
}

foreach ($TaskId in $ExpectedTaskIds) {
    $Task = @($Roadmap.tasks | Where-Object { [string]$_.id -eq $TaskId } | Select-Object -First 1)[0]
    if (-not $Task) {
        $Issues.Add("Missing roadmap task: $TaskId")
        continue
    }

    foreach ($Field in @("title","description","objective","dependencies","allowed_files","required_tests","stop_conditions","commit_message","status")) {
        if (-not ($Task.PSObject.Properties.Name -contains $Field)) {
            $Issues.Add("$TaskId is missing field: $Field")
        }
    }

    if ([string]$Task.status -ne "backlog") {
        $Issues.Add("$TaskId should remain backlog.")
    }

    $PacketFile = Get-LatestPacketForTask -TaskId $TaskId
    if (-not $PacketFile) {
        $Issues.Add("No generated work packet found for $TaskId")
        continue
    }

    try {
        $Packet = Get-Content -LiteralPath $PacketFile.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
        if ([string]$Packet.task_id -ne $TaskId) {
            $Issues.Add("Work packet task_id mismatch for $TaskId.")
        }
    }
    catch {
        $Issues.Add("Work packet JSON could not be parsed for ${TaskId}: $($_.Exception.Message)")
    }

    $MarkdownPath = [System.IO.Path]::ChangeExtension($PacketFile.FullName, ".md")
    if (-not (Test-Path -LiteralPath $MarkdownPath -PathType Leaf)) {
        $Issues.Add("Missing work packet markdown for $TaskId")
    }
}

$DependencyIssues = @()
for ($Index = 0; $Index -lt $ExpectedTaskIds.Count; $Index++) {
    $TaskId = $ExpectedTaskIds[$Index]
    $Task = @($Roadmap.tasks | Where-Object { [string]$_.id -eq $TaskId } | Select-Object -First 1)[0]
    if (-not $Task) {
        continue
    }

    $ExpectedDependency = if ($Index -eq 0) { @("task-001") } else { @($ExpectedTaskIds[$Index - 1]) }
    if (@($Task.dependencies).Count -ne $ExpectedDependency.Count -or (@($Task.dependencies) -join ',') -ne ($ExpectedDependency -join ',')) {
        $DependencyIssues += "$TaskId dependencies should be $($ExpectedDependency -join ', ')"
    }
}

foreach ($Issue in $DependencyIssues) {
    $Issues.Add($Issue)
}

$Report = [pscustomobject]@{
    status           = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    roadmap_path     = $RoadmapPath
    packet_root      = $PacketRoot
    task_count       = @($Roadmap.tasks).Count
    expected_task_ids = @($ExpectedTaskIds)
    actual_task_ids   = @($ActualTaskIds)
    issues           = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA roadmap expansion validation failed."
    }
    return
}

Write-Host "[*] PDA roadmap expansion tests"
Write-Host ("Status : {0}" -f $Report.status)
Write-Host ("Tasks  : {0}" -f $Report.task_count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA roadmap expansion validation failed."
}
