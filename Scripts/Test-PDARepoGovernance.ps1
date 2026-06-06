[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "Scripts\PDA_ApprovedEntrypoints.json"),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$OntologyGovernanceScript = Join-Path $PSScriptRoot "Test-PDAOntologyGovernance.ps1"

if (-not (Test-Path $ManifestPath -PathType Leaf)) {
    throw "Approved entrypoint manifest not found: $ManifestPath"
}

if (-not (Test-Path $OntologyGovernanceScript -PathType Leaf)) {
    throw "Ontology governance script not found: $OntologyGovernanceScript"
}

$Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$ApprovedEntries = @($Manifest.approved_entrypoints)
$ApprovedMap = @{}
foreach ($Entry in $ApprovedEntries) {
    $Normalized = ([string]$Entry.path -replace '/', '\')
    $ApprovedMap[$Normalized] = $Entry
}

$ApprovedCount = $ApprovedEntries.Count
$MissingApprovedScripts = New-Object System.Collections.Generic.List[object]
foreach ($Entry in $ApprovedEntries) {
    $Relative = ([string]$Entry.path -replace '/', '\')
    $FullPath = Join-Path $Root $Relative
    if (-not (Test-Path $FullPath -PathType Leaf)) {
        $MissingApprovedScripts.Add([pscustomobject]@{
            path = $Relative
            full_path = $FullPath
            reason = "Approved manifest entry points to a missing script."
        })
    }
}

$OntologyGovernanceJson = & pwsh -NoProfile -File $OntologyGovernanceScript -Root $Root -ManifestPath $ManifestPath -NoThrow -AsJson
$OntologyGovernance = $OntologyGovernanceJson | ConvertFrom-Json

$UnknownWriters = New-Object System.Collections.Generic.List[object]
$NoncompliantApprovedWriters = New-Object System.Collections.Generic.List[object]

foreach ($Violation in @($OntologyGovernance.violations)) {
    $Path = [string]$Violation.path
    $Entry = $ApprovedMap[$Path]

    switch ([string]$Violation.type) {
        "unknown_writer" {
            $UnknownWriters.Add([pscustomobject]@{
                path = $Path
                reason = [string]$Violation.reason
            })
        }
        "missing_guard" {
            $NoncompliantApprovedWriters.Add([pscustomobject]@{
                path = $Path
                type = [string]$Violation.type
                reason = [string]$Violation.reason
                governance_class = if ($Entry) { [string]$Entry.governance_class } else { "" }
            })
        }
        "unobserved_writer" {
            $NoncompliantApprovedWriters.Add([pscustomobject]@{
                path = $Path
                type = [string]$Violation.type
                reason = [string]$Violation.reason
                governance_class = if ($Entry) { [string]$Entry.governance_class } else { "" }
            })
        }
        "missing_writer" {
            $NoncompliantApprovedWriters.Add([pscustomobject]@{
                path = $Path
                type = [string]$Violation.type
                reason = [string]$Violation.reason
                governance_class = if ($Entry) { [string]$Entry.governance_class } else { "" }
            })
        }
    }
}

$Status = if ($MissingApprovedScripts.Count -eq 0 -and $UnknownWriters.Count -eq 0 -and $NoncompliantApprovedWriters.Count -eq 0) { "pass" } else { "fail" }
$Report = [pscustomobject]@{
    generated_at             = (Get-Date).ToString("s")
    root                     = $Root
    manifest_path            = $ManifestPath
    approved_count           = $ApprovedCount
    observed_writer_count    = [int]$OntologyGovernance.observed_writer_count
    missing_approved_scripts = @($MissingApprovedScripts.ToArray())
    unknown_writers          = @($UnknownWriters.ToArray())
    noncompliant_approved_writers = @($NoncompliantApprovedWriters.ToArray())
    status                   = $Status
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
}
else {
    Write-Host "[*] PDA repo governance preflight"
    Write-Host ("Approved count       : {0}" -f $Report.approved_count)
    Write-Host ("Observed writers     : {0}" -f $Report.observed_writer_count)
    Write-Host ("Missing scripts      : {0}" -f $Report.missing_approved_scripts.Count)
    Write-Host ("Unknown writers      : {0}" -f $Report.unknown_writers.Count)
    Write-Host ("Noncompliant writers : {0}" -f $Report.noncompliant_approved_writers.Count)
    Write-Host ("Status               : {0}" -f $Report.status)

    if ($MissingApprovedScripts.Count -gt 0) {
        Write-Host ""
        Write-Host "[Missing Scripts]"
        foreach ($Item in $MissingApprovedScripts) {
            Write-Host ("- {0}: {1}" -f $Item.path, $Item.reason)
        }
    }

    if ($UnknownWriters.Count -gt 0) {
        Write-Host ""
        Write-Host "[Unknown Writers]"
        foreach ($Item in $UnknownWriters) {
            Write-Host ("- {0}: {1}" -f $Item.path, $Item.reason)
        }
    }

    if ($NoncompliantApprovedWriters.Count -gt 0) {
        Write-Host ""
        Write-Host "[Noncompliant Approved Writers]"
        foreach ($Item in $NoncompliantApprovedWriters) {
            Write-Host ("- {0}: {1} ({2})" -f $Item.path, $Item.type, $Item.reason)
        }
    }
}

if ($Status -ne "pass" -and -not $NoThrow) {
    throw "PDA repo governance preflight failed."
}
