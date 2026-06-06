[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$RoadmapPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\PDA-Roadmap.json"),

    [Parameter(Mandatory = $false)]
    [string]$TaskId = "",

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PDA_BuildRunner.ps1")

$Roadmap = Import-PDABuildRunnerRoadmap -Root $Root -RoadmapPath $RoadmapPath
$State = Get-PDABuildRunnerTaskState -Roadmap $Roadmap -TaskId $TaskId
if (-not $State) {
    throw "Task state not found."
}

$Report = [pscustomobject]@{
    status       = "pass"
    roadmap_path = $RoadmapPath
    task_state   = $State
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 40
    return
}

Write-Host "[OK] PDA build runner task state loaded."
Write-Host ("Task   : {0}" -f $State.task_id)
Write-Host ("State  : {0}" -f $State.status)
Write-Host ("Next   : {0}" -f (@($State.next_states) -join ", "))
