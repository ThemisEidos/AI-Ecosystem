[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath = "",

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_MemoryTaxonomy.ps1")

$Report = Test-PDAMemoryTaxonomyIndex -Root $Root

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportDir = Split-Path -Parent $ReportPath
    if (-not [string]::IsNullOrWhiteSpace($ReportDir)) {
        New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
    }

    $Report | ConvertTo-Json -Depth 20 | Set-Content -Path $ReportPath -Encoding UTF8
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA memory taxonomy validation failed."
    }

    return
}

Write-Host "[*] PDA memory taxonomy normalization check"
Write-Host ("Taxonomy          : {0} v{1}" -f $Report.taxonomy.name, $Report.taxonomy.version)
Write-Host ("Total records     : {0}" -f $Report.total_record_count)
Write-Host ("Valid records     : {0}" -f $Report.valid_record_count)
Write-Host ("Invalid records   : {0}" -f $Report.invalid_record_count)
Write-Host ("Missing fields    : {0}" -f $Report.missing_field_count)
Write-Host ("Invalid values    : {0}" -f $Report.invalid_value_count)
Write-Host ("Invalid tags      : {0}" -f $Report.invalid_tag_count)
Write-Host ("Source refs       : {0}" -f $Report.source_reference_issue_count)
Write-Host ("Orphans           : {0}" -f $Report.orphan_count)
Write-Host ("Duplicate IDs     : {0}" -f $Report.duplicate_memory_id_count)
Write-Host ("Status            : {0}" -f $Report.status)

if ($Report.records.Count -gt 0) {
    Write-Host ""
    Write-Host "Record details:"
    foreach ($Record in $Report.records) {
        if (-not $Record.valid) {
            Write-Host ("- {0}: {1} issue(s)" -f $Record.memory_id, $Record.issue_count)
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    Write-Host ""
    Write-Host ("JSON report     : {0}" -f $ReportPath)
}

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA memory taxonomy validation failed."
}
