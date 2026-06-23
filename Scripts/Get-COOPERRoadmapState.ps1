[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$RoadmapPath = "",

    [Parameter(Mandatory = $false)]
    [string]$DocsRoot = "",

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

function New-COOPERRoadmapStateFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string[]]$SourceFiles
    )

    [pscustomobject]@{
        status              = "fail"
        error               = $Message
        current_phase       = ""
        current_phase_status = ""
        current_objective   = ""
        completed_phases    = @()
        next_step           = ""
        latest_exit_review  = $null
        deferred_items      = @()
        blocked_items       = @()
        source_files        = @($SourceFiles | Select-Object -Unique)
        generated_at_utc    = [datetime]::UtcNow.ToString("o")
    }
}

function Get-COOPERPhaseLetterIndex {
    param([Parameter(Mandatory = $false)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return -1
    }

    $Letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    return $Letters.IndexOf($Value.ToUpperInvariant())
}

function Get-COOPERPhaseParts {
    param([Parameter(Mandatory = $true)][string]$PhaseText)

    if ($PhaseText -notmatch '^Phase\s+(?<major>\d+)(?<suffix>[A-Z]?)') {
        return $null
    }

    [pscustomobject]@{
        major  = [int]$Matches.major
        suffix = [string]$Matches.suffix
    }
}

function Get-COOPERRoadmapState {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RoadmapPath,
        [Parameter(Mandatory = $true)][string]$DocsRoot
    )

    if (-not (Test-Path -LiteralPath $RoadmapPath -PathType Leaf)) {
        return (New-COOPERRoadmapStateFailure -Message "Roadmap not found: $RoadmapPath" -SourceFiles @($RoadmapPath))
    }

    $RoadmapText = Get-Content -LiteralPath $RoadmapPath -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($RoadmapText)) {
        return (New-COOPERRoadmapStateFailure -Message "Roadmap is empty: $RoadmapPath" -SourceFiles @($RoadmapPath))
    }

    $Lines = @($RoadmapText -split "`r?`n")

    $CurrentPhase = ""
    $CurrentObjective = ""
    $SequenceEntries = New-Object System.Collections.Generic.List[object]
    $DeferredItems = New-Object System.Collections.Generic.List[string]

    for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        $Line = [string]$Lines[$Index]

        if ([string]::IsNullOrWhiteSpace($CurrentPhase) -and $Line -match '^### Current Phase\s*$') {
            for ($LookAhead = $Index + 1; $LookAhead -lt $Lines.Count; $LookAhead++) {
                $LookLine = [string]$Lines[$LookAhead]
                if ($LookLine -match '^###\s+') { break }
                if ($LookLine -match '^Phase\s+\d+[A-Z]?(?:\.\d+)*\s*-\s*.+$') {
                    $CurrentPhase = ([string]$LookLine).Trim()
                    break
                }
                if ($LookLine -match '^\-\s*Current Phase:\s*(?<phase>.+)$') {
                    $CurrentPhase = ([string]$Matches.phase).Trim()
                    break
                }
            }
            continue
        }

        if ([string]::IsNullOrWhiteSpace($CurrentObjective) -and $Line -match '^### Current Objective\s*$') {
            $Paragraph = New-Object System.Collections.Generic.List[string]
            $Started = $false
            for ($LookAhead = $Index + 1; $LookAhead -lt $Lines.Count; $LookAhead++) {
                $LookLine = [string]$Lines[$LookAhead]
                if ($LookLine -match '^###\s+' -and $Started) { break }
                if ([string]::IsNullOrWhiteSpace($LookLine)) {
                    if ($Started) { break }
                    continue
                }
                if ($LookLine -match '^```') { continue }
                $Started = $true
                $Paragraph.Add($LookLine.Trim()) | Out-Null
            }
            $CurrentObjective = (($Paragraph -join ' ') -replace '\s+', ' ').Trim()
            continue
        }

        if ($Line -match '^## Roadmap Sequence\s*$') {
            for ($LookAhead = $Index + 1; $LookAhead -lt $Lines.Count; $LookAhead++) {
                $LookLine = [string]$Lines[$LookAhead]
                if ($LookLine -match '^##\s+' -and $LookAhead -gt $Index + 1) { break }
                if ($LookLine -match '^(?<phase>Phase\s+[0-9A-Z.]+)\s+-\s+(?<title>.+?)\s+(?<status>COMPLETE|CURRENT|FUTURE|DEFERRED)$') {
                    $SequenceEntries.Add([pscustomobject]@{
                        phase  = [string]$Matches.phase
                        title  = [string]$Matches.title
                        status = [string]$Matches.status
                    }) | Out-Null
                }
            }
            continue
        }

        if ($Line -match '^### Future Backlog - Deferred Capability Expansion\s*$') {
            $Capture = $false
            for ($LookAhead = $Index + 1; $LookAhead -lt $Lines.Count; $LookAhead++) {
                $LookLine = [string]$Lines[$LookAhead]
                if ($LookLine -match '^###\s+' -and $LookAhead -gt $Index + 1) { break }
                if ($LookLine -match '^\s*-\s*Candidate Items:\s*$') { $Capture = $true; continue }
                if ($LookLine -match '^\s*-\s*Entry Criteria:\s*$') { break }
                if ($Capture -and $LookLine -match '^\s*-\s*(?<item>.+)$') {
                    $DeferredItems.Add(([string]$Matches.item).Trim()) | Out-Null
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($CurrentPhase)) {
        return (New-COOPERRoadmapStateFailure -Message "Roadmap is malformed: current phase not found." -SourceFiles @($RoadmapPath))
    }
    if ($SequenceEntries.Count -eq 0) {
        return (New-COOPERRoadmapStateFailure -Message "Roadmap is malformed: no roadmap sequence entries found." -SourceFiles @($RoadmapPath))
    }

    $CurrentPhasePrefix = if ($CurrentPhase -match '^(Phase\s+\d+[A-Z]?(?:\.\d+)?)') { [string]$Matches[1] } else { $CurrentPhase }
    $CurrentEntry = $SequenceEntries | Where-Object { [string]$_.phase -eq $CurrentPhasePrefix } | Select-Object -First 1
    if (-not $CurrentEntry) {
        return (New-COOPERRoadmapStateFailure -Message "Roadmap is malformed: current phase '$CurrentPhase' does not match a roadmap sequence entry." -SourceFiles @($RoadmapPath))
    }

    $CompletedPhases = @(
        $SequenceEntries |
            Where-Object { [string]$_.status -eq "COMPLETE" } |
            ForEach-Object {
                [pscustomobject]@{
                    phase  = [string]$_.phase
                    title  = [string]$_.title
                    status = [string]$_.status
                }
            }
    )

    $CurrentParts = Get-COOPERPhaseParts -PhaseText $CurrentPhasePrefix
    $LatestExitReview = $null
    $BestRank = [int]::MinValue
    $ExitReviewFiles = @()
    if (Test-Path -LiteralPath $DocsRoot -PathType Container) {
        $ExitReviewFiles = @(Get-ChildItem -LiteralPath $DocsRoot -File -Filter 'Phase_*_Exit_Review.md' -ErrorAction SilentlyContinue)
    }

    foreach ($File in $ExitReviewFiles) {
        if ($File.Name -notmatch '^Phase_(?<phase>[0-9A-Z.]+)_Exit_Review\.md$') { continue }

        $ReviewPhase = "Phase $([string]$Matches.phase)"
        $ReviewParts = Get-COOPERPhaseParts -PhaseText $ReviewPhase
        if (-not $ReviewParts) { continue }

        $IsRelevant = $false
        if ($ReviewParts.major -lt $CurrentParts.major) {
            $IsRelevant = $true
        }
        elseif ($ReviewParts.major -eq $CurrentParts.major) {
            $CurrentSuffixIndex = Get-COOPERPhaseLetterIndex -Value $CurrentParts.suffix
            $ReviewSuffixIndex = Get-COOPERPhaseLetterIndex -Value $ReviewParts.suffix
            if ($ReviewSuffixIndex -ge 0 -and $CurrentSuffixIndex -ge 0 -and $ReviewSuffixIndex -lt $CurrentSuffixIndex) {
                $IsRelevant = $true
            }
        }

        if (-not $IsRelevant) { continue }

        $Rank = ($ReviewParts.major * 100) + (Get-COOPERPhaseLetterIndex -Value $ReviewParts.suffix)
        if ($Rank -gt $BestRank) {
            $BestRank = $Rank
            $LatestExitReview = [pscustomobject]@{
                phase = $ReviewPhase
                path  = [string]$File.FullName
                title = (([string](Split-Path -LeafBase $File.Name)) -replace '_', ' ')
            }
        }
    }

    $SourceFiles = New-Object System.Collections.Generic.List[string]
    [void]$SourceFiles.Add([System.IO.Path]::GetFullPath($RoadmapPath))
    foreach ($File in ($ExitReviewFiles | Sort-Object Name)) {
        [void]$SourceFiles.Add([System.IO.Path]::GetFullPath($File.FullName))
    }

    [pscustomobject]@{
        status              = "pass"
        current_phase       = [string]$CurrentPhase
        current_phase_status = [string]$CurrentEntry.status
        current_objective   = [string]$CurrentObjective
        completed_phases    = @($CompletedPhases)
        next_step           = [string]$CurrentObjective
        latest_exit_review  = $LatestExitReview
        deferred_items      = @($DeferredItems)
        blocked_items       = @()
        source_files        = @($SourceFiles | Select-Object -Unique)
        generated_at_utc    = [datetime]::UtcNow.ToString("o")
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($RoadmapPath)) {
        $RoadmapPath = Join-Path $Root "07_Implementation Roadmap.md"
    }
    if ([string]::IsNullOrWhiteSpace($DocsRoot)) {
        $DocsRoot = Join-Path $Root "Docs"
    }

    $Result = Get-COOPERRoadmapState -Root $Root -RoadmapPath $RoadmapPath -DocsRoot $DocsRoot

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 10
    }
    else {
        $Result
    }
}
catch {
    $ErrorMessage = if ($_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber) {
        "Line $($_.InvocationInfo.ScriptLineNumber): $([string]$_.Exception.Message)"
    }
    else {
        [string]$_.Exception.Message
    }
    $Failure = New-COOPERRoadmapStateFailure -Message $ErrorMessage -SourceFiles @($RoadmapPath)
    if ($AsJson) {
        $Failure | ConvertTo-Json -Depth 10
    }
    else {
        $Failure
    }
}
