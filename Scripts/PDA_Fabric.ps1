function Get-PDAFabricExecutablePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Command = Get-Command fabric -ErrorAction SilentlyContinue
    if ($Command -and -not [string]::IsNullOrWhiteSpace($Command.Source)) {
        return [string]$Command.Source
    }

    $HomeDir = if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { $env:USERPROFILE } else { $env:HOME }

    foreach ($Candidate in @(
        (Join-Path $HomeDir ".local/bin/fabric.exe"),
        (Join-Path $HomeDir ".local/bin/fabric"),
        (Join-Path $Root "fabric.exe"),
        (Join-Path $Root "fabric")
    )) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path -Path $Candidate -PathType Leaf)) {
            return $Candidate
        }
    }

    return ""
}

function Get-PDAFabricConfigPath {
    [CmdletBinding()]
    param()

    $HomeDir = if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { $env:USERPROFILE } else { $env:HOME }
    return (Join-Path $HomeDir ".config/fabric/.env")
}

function Get-PDAFabricPatternAliasMap {
    [CmdletBinding()]
    param()

    return [ordered]@{
        research = "Research/research-synthesis"
        report   = "Reporting/report-summary"
        review   = "Review/review-checklist"
        security = "Security/security-triage"
    }
}

function Resolve-PDAFabricPatternName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Alias = "",

        [Parameter(Mandatory = $false)]
        [string]$DefaultPattern = "Reporting/report-summary"
    )

    $AliasText = ([string]$Alias).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($AliasText)) {
        return $DefaultPattern
    }

    $Map = Get-PDAFabricPatternAliasMap
    if ($Map.Contains($AliasText)) {
        return [string]$Map[$AliasText]
    }

    return $DefaultPattern
}

function Resolve-PDAFabricPatternAlias {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Text = "",

        [Parameter(Mandatory = $false)]
        [string]$Command = ""
    )

    $Candidates = @(
        [string]$Command,
        [string]$Text
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    foreach ($Candidate in $Candidates) {
        $Normalized = ([string]$Candidate).Trim().ToLowerInvariant()
        if ($Normalized -match '(^|[^\w])\/fabric\s+(research|report|review|security)\b') {
            return [string]$Matches[2]
        }

        if ($Normalized -match '(^|[^\w])fabric\s+(research|report|review|security)\b') {
            return [string]$Matches[2]
        }
    }

    return ""
}

function Resolve-PDAFabricExecutionProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Text = "",

        [Parameter(Mandatory = $false)]
        [string]$Command = "",

        [Parameter(Mandatory = $false)]
        [string]$Pattern = ""
    )

    $Alias = Resolve-PDAFabricPatternAlias -Text $Text -Command $Command
    $ResolvedPattern = if (-not [string]::IsNullOrWhiteSpace($Pattern)) {
        $Pattern
    }
    else {
        Resolve-PDAFabricPatternName -Alias $Alias
    }

    return [pscustomobject]@{
        alias    = $Alias
        pattern  = $ResolvedPattern
        command  = if ([string]::IsNullOrWhiteSpace($Command)) { "/fabric" } else { $Command }
    }
}

function Test-PDAFabricCustomPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Pattern = ""
    )

    $Normalized = ([string]$Pattern).Trim().Replace('\', '/').ToLowerInvariant()
    return $Normalized -in @(
        "research/research-synthesis",
        "reporting/report-summary",
        "review/review-checklist",
        "security/security-triage"
    )
}

function Get-PDAFabricPatternMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Pattern = ""
    )

    $Normalized = ([string]$Pattern).Trim().Replace('\', '/').TrimStart("/")
    $Parts = @($Normalized -split "[\\/]" | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $PatternCategory = ""
    $PatternName = $Normalized

    if ($Parts.Count -ge 2) {
        $PatternCategory = [string]$Parts[0]
        $PatternName = [string]$Parts[-1]
    }

    return [pscustomobject]@{
        pattern_category = $PatternCategory
        pattern_name     = $PatternName
    }
}

function Get-PDAFabricVariableArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter(Mandatory = $true)]
        [string]$ContentInput,

        [Parameter(Mandatory = $false)]
        [string]$Audience = "operators",

        [Parameter(Mandatory = $false)]
        [string]$Focus = "status",

        [Parameter(Mandatory = $false)]
        [string]$Tone = "neutral",

        [Parameter(Mandatory = $false)]
        [string]$Priority = "high"
    )

    $Meta = Get-PDAFabricPatternMetadata -Pattern $Pattern
    return @(
        "-v", "content_input:$ContentInput",
        "-v", "pattern_name:$($Meta.pattern_name)",
        "-v", "pattern_category:$($Meta.pattern_category)",
        "-v", "audience:$Audience",
        "-v", "focus:$Focus",
        "-v", "tone:$Tone",
        "-v", "priority:$Priority"
    )
}
