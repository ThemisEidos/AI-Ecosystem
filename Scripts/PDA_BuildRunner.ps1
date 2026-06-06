[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "PDA_NightlyAutomation.ps1")

function Get-PDABuildRunnerRoadmapPath {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Get-PDANightlyRoadmapPath -Root $Root)
}

function Import-PDABuildRunnerRoadmap {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [string]$RoadmapPath = (Get-PDABuildRunnerRoadmapPath -Root $Root)
    )

    return (Import-PDANightlyRoadmap -Root $Root -RoadmapPath $RoadmapPath)
}

function Get-PDABuildRunnerTaskState {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Roadmap,

        [Parameter(Mandatory = $false)]
        [string]$TaskId = ""
    )

    return (Get-PDANightlyTaskState -Roadmap $Roadmap -TaskId $TaskId)
}

function Find-PDABuildRunnerWorkPacket {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [Parameter(Mandatory = $false)]
        [string]$PacketRoot = (Join-Path $Root "Roadmap\work-packets")
    )

    return (Find-PDANightlyWorkPacket -Root $Root -TaskId $TaskId -PacketRoot $PacketRoot)
}

function New-PDABuildRunnerWorkPacketObject {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [object]$Roadmap,

        [Parameter(Mandatory = $true)]
        [object]$Task,

        [Parameter(Mandatory = $false)]
        [string]$BranchName = ""
    )

    return (New-PDACodexWorkPacketObject -Root $Root -Roadmap $Roadmap -Task $Task -BranchName $BranchName)
}

function Save-PDABuildRunnerWorkPacket {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Packet,

        [Parameter(Mandatory = $true)]
        [string]$PacketRoot
    )

    return (Save-PDACodexWorkPacket -Packet $Packet -PacketRoot $PacketRoot)
}

function New-PDABuildRunnerExecutionSummaryObject {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Roadmap,

        [Parameter(Mandatory = $true)]
        [object]$Task,

        [Parameter(Mandatory = $true)]
        [object]$WorkPacket,

        [Parameter(Mandatory = $true)]
        [string]$BranchName,

        [Parameter(Mandatory = $true)]
        [string]$CurrentState,

        [Parameter(Mandatory = $true)]
        [string]$FinalState,

        [Parameter(Mandatory = $true)]
        [string[]]$TransitionChain,

        [Parameter(Mandatory = $false)]
        [string[]]$BackupManifests = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$TestsRequired = @()
    )

    return (New-PDANightlyExecutionSummaryObject -Roadmap $Roadmap -Task $Task -WorkPacket $WorkPacket -BranchName $BranchName -CurrentState $CurrentState -FinalState $FinalState -TransitionChain $TransitionChain -BackupManifests $BackupManifests -TestsRequired $TestsRequired)
}

function Save-PDABuildRunnerExecutionSummary {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Summary,

        [Parameter(Mandatory = $true)]
        [string]$OutputRoot
    )

    return (Save-PDANightlyExecutionSummary -Summary $Summary -OutputRoot $OutputRoot)
}
