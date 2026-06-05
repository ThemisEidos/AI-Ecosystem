[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$DashboardScript = Join-Path $PSScriptRoot "Update-PDADashboard.ps1"
if (-not (Test-Path -LiteralPath $DashboardScript -PathType Leaf)) {
    throw "Dashboard refresh script missing: $DashboardScript"
}

function Invoke-DashboardRefresh {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$OutputDirectory
    )

    $Raw = & pwsh -NoProfile -File $DashboardScript -RootPath $RootPath -OutputDirectory $OutputDirectory -AsJson -NoThrow 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Dashboard refresh returned empty output."
    }

    return ($Text | ConvertFrom-Json)
}

function New-EmptyTestRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    New-Item -ItemType Directory -Force -Path (Join-Path $Path "Scripts") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Path "PDA-Logs\routing") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Path "PDA-Tasks") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Path "Obsidian Vault\02_Projects\AI Tool Ecosystem") | Out-Null
    @'
{
  "schema_version": "1.0",
  "created_at": "",
  "updated_at": "",
  "memories": []
}
'@ | Set-Content -Path (Join-Path $Path "PDA_MemoryIndex.json") -Encoding UTF8
    @'
{
  "schema_version": "1.0",
  "created_at": "",
  "updated_at": "",
  "artifacts": []
}
'@ | Set-Content -Path (Join-Path $Path "PDA_ArtifactIndex.json") -Encoding UTF8
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pda-dashboard-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

try {
    $EmptyRoot = Join-Path $TempRoot "empty-root"
    $EmptyOutput = Join-Path $EmptyRoot "Obsidian Vault\02_Projects\AI Tool Ecosystem"
    New-EmptyTestRoot -Path $EmptyRoot

    $LiveOutput = Join-Path $RepoRoot "Obsidian Vault\02_Projects\AI Tool Ecosystem"

    $EmptyResult = Invoke-DashboardRefresh -RootPath $EmptyRoot -OutputDirectory $EmptyOutput
    $LiveResult = Invoke-DashboardRefresh -RootPath $RepoRoot -OutputDirectory $LiveOutput

    $Results = @()

    $EmptyIssues = @()
    foreach ($ExpectedFile in @("PDA Operator Console.md", "Routing Summary.md", "System Status.md", "Task Summary.md")) {
        $Path = Join-Path $EmptyOutput $ExpectedFile
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            $EmptyIssues += "Missing dashboard output: $ExpectedFile"
            continue
        }

        $Content = Get-Content -LiteralPath $Path -Raw
        if ([string]::IsNullOrWhiteSpace($Content)) {
            $EmptyIssues += "Dashboard output is empty: $ExpectedFile"
        }
    }
    $Results += [pscustomobject]@{
        name = "empty system"
        passed = ($EmptyIssues.Count -eq 0)
        issues = @($EmptyIssues)
    }

    $LiveIssues = @()
    if ([string]$LiveResult.status -ne "pass") {
        $LiveIssues += "Live dashboard refresh did not return pass."
    }
    foreach ($ExpectedFile in @("PDA Operator Console.md", "Routing Summary.md", "System Status.md", "Task Summary.md")) {
        $Path = Join-Path $LiveOutput $ExpectedFile
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            $LiveIssues += "Missing live dashboard output: $ExpectedFile"
            continue
        }

        $Content = Get-Content -LiteralPath $Path -Raw
        if ($ExpectedFile -eq "System Status.md" -and $Content -notmatch "AI Ecosystem Status") {
            $LiveIssues += "System Status.md missing AI Ecosystem status section."
        }
        if ($ExpectedFile -eq "Routing Summary.md" -and $Content -notmatch "Dispatches By Model") {
            $LiveIssues += "Routing Summary.md missing routing metrics section."
        }
        if ($ExpectedFile -eq "Task Summary.md" -and $Content -notmatch "Queue Metrics") {
            $LiveIssues += "Task Summary.md missing queue metrics section."
        }
    }
    $Results += [pscustomobject]@{
        name = "active system"
        passed = ($LiveIssues.Count -eq 0)
        issues = @($LiveIssues)
    }

    $FailedCount = @($Results | Where-Object { -not $_.passed }).Count
    $Report = [pscustomobject]@{
        status = if ($FailedCount -eq 0) { "pass" } else { "fail" }
        dashboard_script = $DashboardScript
        result_count = $Results.Count
        failed_count = $FailedCount
        results = @($Results)
    }
}
finally {
    if (Test-Path -LiteralPath $TempRoot -PathType Container) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
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
Write-Host ("Test cases : {0}" -f $Report.result_count)
Write-Host ("Failed     : {0}" -f $Report.failed_count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA dashboard refresh validation failed."
}
