[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$RoadmapPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\PDA-Roadmap.json"),

    [Parameter(Mandatory = $false)]
    [string]$TaskId = "",

    [Parameter(Mandatory = $false)]
    [string]$PacketRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "Roadmap\work-packets"),

    [Parameter(Mandatory = $false)]
    [string]$BranchName = "",

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PDA_NightlyAutomation.ps1")

$Roadmap = Import-PDANightlyRoadmap -Root $Root -RoadmapPath $RoadmapPath
if ([string]::IsNullOrWhiteSpace($TaskId)) {
    $TaskId = [string]$Roadmap.current_task_id
}

$Task = Get-PDANightlyTask -Roadmap $Roadmap -TaskId $TaskId
if (-not $Task) {
    throw "Task not found for work packet generation: $TaskId"
}

$Packet = New-PDACodexWorkPacketObject -Root $Root -Roadmap $Roadmap -Task $Task -BranchName $BranchName
$Saved = Save-PDACodexWorkPacket -Packet $Packet -PacketRoot $PacketRoot

$Result = [pscustomobject]@{
    status         = "pass"
    task_id        = $Packet.task_id
    packet_root    = $PacketRoot
    json_path      = $Saved.json_path
    markdown_path  = $Saved.markdown_path
    packet         = $Packet
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 40
    return
}

Write-Host "[OK] PDA Codex work packet generated."
Write-Host ("Task        : {0}" -f $Packet.task_id)
Write-Host ("JSON path   : {0}" -f $Saved.json_path)
Write-Host ("Markdown path: {0}" -f $Saved.markdown_path)
