[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$RoadmapPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\PDA-Roadmap.json"),

    [Parameter(Mandatory = $false)]
    [string]$TaskId = "",

    [Parameter(Mandatory = $false)]
    [string]$BranchName = "",

    [Parameter(Mandatory = $false)]
    [string]$BackupManifests = "",

    [Parameter(Mandatory = $false)]
    [string]$TestsExecuted = "",

    [Parameter(Mandatory = $false)]
    [string]$GeneratedReports = "",

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "PDA-Backups\nightly-build\reports"),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PDA_NightlyAutomation.ps1")

function ConvertFrom-PDADelimitedList {
    param([Parameter(Mandatory = $false)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @($Value -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$Roadmap = Import-PDANightlyRoadmap -Root $Root -RoadmapPath $RoadmapPath
$State = Get-PDANightlyTaskState -Roadmap $Roadmap -TaskId $TaskId
if (-not $State) {
    throw "Task state not found for morning report."
}

$ReportInfo = New-PDAMorningReportMarkdown -State $State -BranchName $BranchName -BackupManifests (ConvertFrom-PDADelimitedList -Value $BackupManifests) -TestsExecuted (ConvertFrom-PDADelimitedList -Value $TestsExecuted) -GeneratedReports (ConvertFrom-PDADelimitedList -Value $GeneratedReports) -OutputRoot $OutputRoot

$Report = [pscustomobject]@{
    status      = $ReportInfo.status
    report_path = $ReportInfo.report_path
    task_state  = $State
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 40
    return
}

Write-Host "[OK] PDA morning report generated."
Write-Host ("Report : {0}" -f $ReportInfo.report_path)
Write-Host ("Task   : {0}" -f $State.task_id)
Write-Host ("State  : {0}" -f $State.status)
