[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$RoadmapPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\PDA-Roadmap.json"),

    [Parameter(Mandatory = $false)]
    [string]$TaskId = "",

    [Parameter(Mandatory = $true)]
    [string]$ToState,

    [Parameter(Mandatory = $false)]
    [string]$Actor = "PDA Nightly Automation",

    [Parameter(Mandatory = $false)]
    [string]$Reason = "",

    [Parameter(Mandatory = $false)]
    [switch]$NoWrite,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PDA_NightlyAutomation.ps1")

$Roadmap = Import-PDANightlyRoadmap -Root $Root -RoadmapPath $RoadmapPath
if ([string]::IsNullOrWhiteSpace($TaskId)) {
    $TaskId = [string]$Roadmap.current_task_id
}

$Result = Set-PDANightlyRoadmapStatus -Root $Root -RoadmapPath $RoadmapPath -TaskId $TaskId -ToState $ToState -Actor $Actor -Reason $Reason -NoWrite:$NoWrite
$Report = [pscustomobject]@{
    status     = $Result.status
    task_id    = $Result.task_id
    from_state = $Result.from_state
    to_state   = $Result.to_state
    updated    = $Result.updated
    roadmap    = $Result.roadmap
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 40
    return
}

Write-Host "[OK] PDA roadmap status updated."
Write-Host ("Task  : {0}" -f $Report.task_id)
Write-Host ("From  : {0}" -f $Report.from_state)
Write-Host ("To    : {0}" -f $Report.to_state)
Write-Host ("Write : {0}" -f $Report.updated)
