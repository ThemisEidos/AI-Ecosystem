[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$UpdateScript = Join-Path $PSScriptRoot "Update-PDADashboard.ps1"
$StatusScript = Join-Path $PSScriptRoot "Get-PDADashboardStatus.ps1"
$DashboardPath = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\PDA Dashboard.md"
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
if (Test-Path -LiteralPath $ParserPath -PathType Leaf) {
    . $ParserPath
}

function Invoke-PDAJsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$SourceName
    )

    $Raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "$SourceName returned empty output."
    }

    return ConvertFrom-PDAMixedJson -Text $Text -SourceName $SourceName
}

$Issues = New-Object System.Collections.Generic.List[string]

try {
    if (-not (Test-Path -LiteralPath $StatusScript -PathType Leaf)) {
        throw "Dashboard status script missing: $StatusScript"
    }
    if (-not (Test-Path -LiteralPath $UpdateScript -PathType Leaf)) {
        throw "Dashboard update script missing: $UpdateScript"
    }

    $UpdateReport = Invoke-PDAJsonScript -Path $UpdateScript -Arguments @("-AsJson", "-NoThrow", "-RootPath", $Root) -SourceName "dashboard refresh"

    if ($UpdateReport.status -ne "pass") {
        $Issues.Add("Dashboard refresh did not return pass.")
    }
    elseif ($UpdateReport.PSObject.Properties.Name -contains "status_report" -and $UpdateReport.status_report.status -ne "pass") {
        $Issues.Add("Dashboard refresh embedded status report did not return pass.")
    }

    if (-not (Test-Path -LiteralPath $DashboardPath -PathType Leaf)) {
        $Issues.Add("Dashboard markdown file was not written.")
    }
    else {
        $Content = Get-Content -LiteralPath $DashboardPath -Raw
        if ([string]::IsNullOrWhiteSpace($Content)) {
            $Issues.Add("Dashboard markdown file is empty.")
        }

        foreach ($Heading in @(
            "# PDA Dashboard v2",
            "## System Health",
            "## Queue Status",
            "## Worker Status",
            "## Pending Approvals",
            "## Recent Tasks",
            "## Recent Reports / Artifacts",
            "## Model Status",
            "## Capability Router",
            "### Fabric CLI Status",
            "## PDA Commander Integration",
            "## PDA Commander Briefing",
            "## Memory Summary"
        )) {
            if ($Content -notmatch [regex]::Escape($Heading)) {
                $Issues.Add("Dashboard markdown file is missing heading: $Heading")
            }
        }

        if ($Content -notmatch '(?m)^Updated:\s+') {
            $Issues.Add("Dashboard markdown file is missing a refresh timestamp.")
        }
    }

    $Report = [pscustomobject]@{
        status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
        dashboard_script = $UpdateScript
        dashboard_path = $DashboardPath
        issues = @($Issues)
        update_report = $UpdateReport
    }
}
catch {
    $Issues.Add($_.Exception.Message)
    $Report = [pscustomobject]@{
        status = "fail"
        dashboard_script = $UpdateScript
        dashboard_path = $DashboardPath
        issues = @($Issues)
    }
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA dashboard refresh validation failed."
    }
    return
}

Write-Host "[*] PDA dashboard refresh tests"
Write-Host ("Dashboard path : {0}" -f $Report.dashboard_path)
Write-Host ("Status         : {0}" -f $Report.status)
Write-Host ("Issues         : {0}" -f @($Report.issues).Count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA dashboard refresh validation failed."
}
