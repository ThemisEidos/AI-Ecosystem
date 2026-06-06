[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_MemoryTaxonomy.ps1")

$Report = Test-PDAMemoryTaxonomyContract -Root $Root

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and -not $Report.valid) {
        throw "PDA memory taxonomy validation failed."
    }

    return
}

Write-Host "[*] PDA memory taxonomy validation"
Write-Host ("Taxonomy          : {0}" -f $Report.taxonomy_name)
Write-Host ("Version           : {0}" -f $Report.taxonomy_version)
Write-Host ("Schema path       : {0}" -f $Report.schema_path)
Write-Host ("Taxonomy path     : {0}" -f $Report.taxonomy_path)
Write-Host ("Required fields   : {0}" -f $Report.required_field_count)
Write-Host ("Memory types      : {0}" -f $Report.memory_type_count)
Write-Host ("Categories        : {0}" -f $Report.category_count)
Write-Host ("Statuses          : {0}" -f $Report.status_count)
Write-Host ("Sensitivities     : {0}" -f $Report.sensitivity_count)
Write-Host ("Source types      : {0}" -f $Report.source_type_count)
Write-Host ("Lifecycle states  : {0}" -f $Report.lifecycle_state_count)
Write-Host ("Tag namespaces    : {0}" -f $Report.allowed_namespace_count)
Write-Host ("Issue count       : {0}" -f $Report.issue_count)
Write-Host ("Status            : {0}" -f ($(if ($Report.valid) { "pass" } else { "fail" })))

if ($Report.issue_count -gt 0) {
    Write-Host ""
    Write-Host "[Issues]"
    foreach ($Issue in $Report.issues) {
        Write-Host ("- {0}: {1}" -f $Issue.issue_type, ($Issue.detail ?? $Issue.path ?? $Issue.property ?? $Issue.field))
    }
}

if (-not $NoThrow -and -not $Report.valid) {
    throw "PDA memory taxonomy validation failed."
}
