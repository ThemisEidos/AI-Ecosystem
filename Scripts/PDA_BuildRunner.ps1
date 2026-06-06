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

        [Parameter(Mandatory = $false)]
        [string[]]$TransitionChain = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$BackupManifests = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$TestsRequired = @()
    )

    if ($null -eq $TransitionChain) {
        $TransitionChain = @()
    }

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

function Get-PDABuildRunnerPolicyPath {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $RoadmapPolicy = Join-Path $Root "Roadmap\PDA-BuildRunnerPolicy.json"
    if (Test-Path -LiteralPath $RoadmapPolicy -PathType Leaf) {
        return $RoadmapPolicy
    }

    $LegacyPolicy = Join-Path $PSScriptRoot "PDA_BuildRunnerPolicy.json"
    if (Test-Path -LiteralPath $LegacyPolicy -PathType Leaf) {
        return $LegacyPolicy
    }

    throw "Build Runner policy file not found."
}

function Import-PDABuildRunnerPolicy {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [string]$PolicyPath = (Get-PDABuildRunnerPolicyPath -Root $Root)
    )

    if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
        throw "Build Runner policy file not found: $PolicyPath"
    }

    return (Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json -ErrorAction Stop)
}

function Test-PDABuildRunnerPolicy {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Policy
    )

    $Issues = New-Object System.Collections.Generic.List[string]
    foreach ($Name in @(
        "max_tasks_per_run",
        "max_runtime_minutes",
        "stop_on_failed_tests",
        "allowed_file_globs",
        "blocked_file_globs",
        "require_clean_start",
        "branch_prefix",
        "allow_commit_to_branch",
        "allow_push_branch",
        "allow_main_mod",
        "allow_secret_changes"
    )) {
        if (-not ($Policy.PSObject.Properties.Name -contains $Name)) {
            $Issues.Add("Missing policy key: $Name")
        }
    }

    if ($Issues.Count -gt 0) {
        return [pscustomobject]@{
            valid  = $false
            issues = @($Issues)
        }
    }

    return [pscustomobject]@{
        valid  = $true
        issues = @()
    }
}

function Test-PDABuildRunnerPathMatchesGlob {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Glob
    )

    $NormalizedPath = ([string]$Path).Replace("\", "/")
    $NormalizedGlob = ([string]$Glob).Replace("\", "/")
    return ($NormalizedPath -like $NormalizedGlob)
}

function Test-PDABuildRunnerPolicyAllowsPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Policy
    )

    $Allowed = @($Policy.allowed_file_globs)
    $Blocked = @($Policy.blocked_file_globs)
    $AllowedMatch = $false
    foreach ($Glob in $Allowed) {
        if (Test-PDABuildRunnerPathMatchesGlob -Path $Path -Glob ([string]$Glob)) {
            $AllowedMatch = $true
            break
        }
    }

    if (-not $AllowedMatch) {
        return $false
    }

    foreach ($Glob in $Blocked) {
        if (Test-PDABuildRunnerPathMatchesGlob -Path $Path -Glob ([string]$Glob)) {
            return $false
        }
    }

    return $true
}

function Test-PDATaskDependenciesSatisfied {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Task,

        [Parameter(Mandatory = $true)]
        [object]$Roadmap
    )

    $Dependencies = @($Task.dependencies) | ForEach-Object { [string]$_ }
    if ($Dependencies.Count -eq 0) {
        return $true
    }

    $Completed = @($Roadmap.completed_task_ids) | ForEach-Object { [string]$_ }
    foreach ($Dependency in $Dependencies) {
        if ($Completed -notcontains $Dependency) {
            return $false
        }
    }

    return $true
}

function Get-PDABuildRunnerNextEligibleTask {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Roadmap
    )

    foreach ($Task in @($Roadmap.tasks)) {
        $Status = [string]$Task.status
        if ($Status -in @("backlog", "eligible") -and (Test-PDATaskDependenciesSatisfied -Task $Task -Roadmap $Roadmap)) {
            return $Task
        }
    }

    return $null
}

function Get-PDABuildRunnerExecutionDirectories {
    param(
        [Parameter(Mandatory = $false)]
        [string]$ExecutionRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "PDA-Backups\build-runner\executions")
    )

    if (-not (Test-Path -LiteralPath $ExecutionRoot -PathType Container)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $ExecutionRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending
    )
}

function Get-PDABuildRunnerLatestExecutionDirectory {
    param(
        [Parameter(Mandatory = $false)]
        [string]$ExecutionRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "PDA-Backups\build-runner\executions")
    )

    return @(Get-PDABuildRunnerExecutionDirectories -ExecutionRoot $ExecutionRoot | Select-Object -First 1)[0]
}

function Get-PDABuildRunnerRecoveryReportRoot {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    return (Join-Path $Root "PDA-Backups\build-runner\logs")
}

function Get-PDABuildRunnerPolicyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Policy,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        $Default = $null
    )

    if ($Policy -and ($Policy.PSObject.Properties.Name -contains $Name)) {
        return $Policy.$Name
    }

    return $Default
}

function Get-PDABuildRunnerPolicyNumber {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Policy,

        [Parameter(Mandatory = $true)]
        [string[]]$Names,

        [Parameter(Mandatory = $false)]
        [int]$Default = 0
    )

    foreach ($Name in $Names) {
        $Value = Get-PDABuildRunnerPolicyValue -Policy $Policy -Name $Name -Default $null
        if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)) {
            return [int]$Value
        }
    }

    return $Default
}

function Get-PDABuildRunnerPolicyBoolean {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Policy,

        [Parameter(Mandatory = $true)]
        [string[]]$Names,

        [Parameter(Mandatory = $false)]
        [bool]$Default = $false
    )

    foreach ($Name in $Names) {
        if ($Policy -and ($Policy.PSObject.Properties.Name -contains $Name)) {
            return [bool]$Policy.$Name
        }
    }

    return $Default
}

function Resolve-PDABuildRunnerCodexExecutablePath {
    param(
        [Parameter(Mandatory = $false)]
        [string]$ProvidedPath = ""
    )

    $Candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($ProvidedPath)) {
        [void]$Candidates.Add($ProvidedPath)
        $ProvidedCommand = Get-Command $ProvidedPath -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ProvidedCommand -and -not [string]::IsNullOrWhiteSpace([string]$ProvidedCommand.Source)) {
            [void]$Candidates.Add([string]$ProvidedCommand.Source)
        }
    }

    foreach ($Name in @("codex.exe", "codex", "openai.exe", "openai")) {
        $Resolved = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($Resolved -and -not [string]::IsNullOrWhiteSpace([string]$Resolved.Source)) {
            [void]$Candidates.Add([string]$Resolved.Source)
        }
    }

    $UniqueCandidates = @($Candidates | Select-Object -Unique)
    foreach ($Candidate in $UniqueCandidates) {
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            return [pscustomobject]@{
                status          = "pass"
                executable_path = $Candidate
                source          = if (-not [string]::IsNullOrWhiteSpace($ProvidedPath)) { "provided" } else { "local" }
            }
        }
    }

    return [pscustomobject]@{
        status          = "fail"
        executable_path = ""
        source          = ""
        issue           = "Codex CLI not found locally. Install codex.exe or pass -CodexExecutable."
        candidates      = @($UniqueCandidates)
    }
}

function Test-PDABuildRunnerCodexAvailable {
    param(
        [Parameter(Mandatory = $false)]
        [string]$ProvidedPath = ""
    )

    return (Resolve-PDABuildRunnerCodexExecutablePath -ProvidedPath $ProvidedPath)
}
