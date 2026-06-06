[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$IndexPath = Join-Path $RepoRoot "PDA_ArtifactIndex.json"
$DashboardPath = Join-Path $RepoRoot "PDA-Obsidian-Vault\01_Dashboard\Artifact Index.md"
. (Join-Path $PSScriptRoot "PDA_Lifecycle.ps1")

function New-PDAArtifactIndexFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Now = Get-Date -Format "o"
    $Index = [ordered]@{
        schema_version = "1.0"
        created_at     = $Now
        updated_at     = $Now
        artifacts      = @()
    }

    $Index | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

function Get-PDAArtifactDate {
    param(
        [Parameter(Mandatory = $false)]
        $Value
    )

    if ($null -eq $Value) {
        return [datetime]::MinValue
    }

    try {
        return [datetime]::Parse([string]$Value)
    }
    catch {
        return [datetime]::MinValue
    }
}

function Resolve-PDAArtifactPath {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return (Join-Path $RepoRoot $Path)
}

function ConvertTo-PDAMarkdownTable {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Rows,
        [Parameter(Mandatory = $true)]
        [string[]]$Columns
    )

    $Header = "| " + ($Columns -join " | ") + " |"
    $Separator = "| " + (($Columns | ForEach-Object { "---" }) -join " | ") + " |"
    $Lines = @($Header, $Separator)

    foreach ($Row in $Rows) {
        $Values = foreach ($Column in $Columns) {
            $Value = $Row.$Column
            if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
                ""
            }
            else {
                ([string]$Value).Replace("|", "\|")
            }
        }

        $Lines += "| " + ($Values -join " | ") + " |"
    }

    return ,$Lines
}

if (-not (Test-Path -Path $IndexPath -PathType Leaf)) {
    New-PDAArtifactIndexFile -Path $IndexPath
}

$Raw = Get-Content -Path $IndexPath -Raw
try {
    $Index = $Raw | ConvertFrom-Json
}
catch {
    throw "PDA artifact index JSON could not be parsed at '$IndexPath'."
}

if (-not ($Index.PSObject.Properties.Name -contains "schema_version")) {
    throw "PDA artifact index is missing 'schema_version'."
}

if (-not ($Index.PSObject.Properties.Name -contains "artifacts")) {
    throw "PDA artifact index is missing 'artifacts'."
}

if ($null -eq $Index.artifacts -or $Index.artifacts -isnot [System.Array]) {
    throw "PDA artifact index 'artifacts' must be an array."
}

$Artifacts = @($Index.artifacts) | Sort-Object -Property @{ Expression = { Get-PDAArtifactDate $_.created_at } } -Descending
$LatestArtifacts = @($Artifacts | Select-Object -First 10)
$LifecycleSummary = Get-PDALifecycleCounts -Root $RepoRoot -RecordType "artifact"

$BrokenArtifacts = foreach ($Artifact in $Artifacts) {
    $ResolvedPath = Resolve-PDAArtifactPath -Path $Artifact.artifact_path
    if ($null -eq $ResolvedPath -or -not (Test-Path -Path $ResolvedPath -PathType Leaf)) {
        [pscustomobject]@{
            artifact_id   = $Artifact.artifact_id
            artifact_path = $Artifact.artifact_path
            worker_name   = $Artifact.worker_name
            source_task_id = $Artifact.source_task_id
        }
    }
}

$BrokenCount = @($BrokenArtifacts).Count
$GroupedByWorker = @(
    $Artifacts |
        Group-Object worker_name |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                worker_name = if ($_.Name) { $_.Name } else { "(blank)" }
                count       = $_.Count
            }
        }
)

$GroupedByCategory = @(
    $Artifacts |
        Group-Object category |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                category = if ($_.Name) { $_.Name } else { "(blank)" }
                count    = $_.Count
            }
        }
)

$GroupedByType = @(
    $Artifacts |
        Group-Object artifact_type |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                artifact_type = if ($_.Name) { $_.Name } else { "(blank)" }
                count         = $_.Count
            }
        }
)

$Dashboard = New-Object System.Collections.Generic.List[string]
$Dashboard.Add("# PDA Artifact Dashboard")
$Dashboard.Add("")
$Dashboard.Add("Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$Dashboard.Add("")
$Dashboard.Add("## Summary")
$Dashboard.Add("")
$Dashboard.Add("- Schema version: $($Index.schema_version)")
$Dashboard.Add("- Artifact count: $(@($Index.artifacts).Count)")
$Dashboard.Add("- Last updated: $(if ($Index.updated_at) { $Index.updated_at } else { '(blank)' })")
$Dashboard.Add("- Broken link count: $BrokenCount")
$Dashboard.Add("- Active count: $($LifecycleSummary.active)")
$Dashboard.Add("- Archived count: $($LifecycleSummary.archived)")
$Dashboard.Add("- Deprecated count: $($LifecycleSummary.deprecated)")
$Dashboard.Add("- Retired count: $($LifecycleSummary.retired)")
$Dashboard.Add("")

$Dashboard.Add("## Latest 10 Artifacts")
$Dashboard.Add("")
if ($LatestArtifacts.Count -gt 0) {
    foreach ($Line in (ConvertTo-PDAMarkdownTable -Rows $LatestArtifacts -Columns @("artifact_id","created_at","worker_name","category","artifact_type","lifecycle_state","artifact_path","summary"))) {
        $Dashboard.Add($Line)
    }
} else {
    $Dashboard.Add("- No artifacts available.")
}
$Dashboard.Add("")

$Dashboard.Add("## Grouped By Worker")
$Dashboard.Add("")
if ($GroupedByWorker.Count -gt 0) {
    foreach ($Line in (ConvertTo-PDAMarkdownTable -Rows $GroupedByWorker -Columns @("worker_name","count"))) {
        $Dashboard.Add($Line)
    }
} else {
    $Dashboard.Add("- No worker groups available.")
}
$Dashboard.Add("")

$Dashboard.Add("## Grouped By Category")
$Dashboard.Add("")
if ($GroupedByCategory.Count -gt 0) {
    foreach ($Line in (ConvertTo-PDAMarkdownTable -Rows $GroupedByCategory -Columns @("category","count"))) {
        $Dashboard.Add($Line)
    }
} else {
    $Dashboard.Add("- No category groups available.")
}
$Dashboard.Add("")

$Dashboard.Add("## Grouped By Artifact Type")
$Dashboard.Add("")
if ($GroupedByType.Count -gt 0) {
    foreach ($Line in (ConvertTo-PDAMarkdownTable -Rows $GroupedByType -Columns @("artifact_type","count"))) {
        $Dashboard.Add($Line)
    }
} else {
    $Dashboard.Add("- No artifact type groups available.")
}
$Dashboard.Add("")

$GroupedByLifecycle = @(
    $Artifacts |
        Group-Object { if ($_.PSObject.Properties.Name -contains "lifecycle_state" -and -not [string]::IsNullOrWhiteSpace([string]$_.lifecycle_state)) { [string]$_.lifecycle_state } else { "active" } } |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                lifecycle_state = if ($_.Name) { $_.Name } else { "(blank)" }
                count           = $_.Count
            }
        }
)

$Dashboard.Add("## Grouped By Lifecycle State")
$Dashboard.Add("")
if ($GroupedByLifecycle.Count -gt 0) {
    foreach ($Line in (ConvertTo-PDAMarkdownTable -Rows $GroupedByLifecycle -Columns @("lifecycle_state","count"))) {
        $Dashboard.Add($Line)
    }
} else {
    $Dashboard.Add("- No lifecycle groups available.")
}
$Dashboard.Add("")

$Dashboard.Add("## Broken Links")
$Dashboard.Add("")
if ($BrokenCount -gt 0) {
    foreach ($Line in (ConvertTo-PDAMarkdownTable -Rows @($BrokenArtifacts) -Columns @("artifact_id","worker_name","source_task_id","artifact_path"))) {
        $Dashboard.Add($Line)
    }
} else {
    $Dashboard.Add("- No broken artifact paths detected.")
}

$DashboardDir = Split-Path -Parent $DashboardPath
New-Item -ItemType Directory -Force -Path $DashboardDir | Out-Null
$Dashboard -join "`r`n" | Set-Content -Path $DashboardPath -Encoding UTF8

Write-Host "Dashboard updated:"
Write-Host $DashboardPath
Write-Host "Artifact count: $(@($Index.artifacts).Count)"
Write-Host "Broken link count: $BrokenCount"
