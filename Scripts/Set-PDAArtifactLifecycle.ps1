[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $true)]
    [string]$ArtifactId,

    [Parameter(Mandatory = $true)]
    [ValidateSet("draft", "active", "promoted", "archived", "deprecated", "retired")]
    [string]$LifecycleState,

    [string]$Reason = "",
    [string]$Actor = "",
    [switch]$AsJson,
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PDA_Lifecycle.ps1")

$Report = Invoke-PDALifecycleTransition -Root $Root -RecordType "artifact" -RecordId $ArtifactId -LifecycleState $LifecycleState -Reason $Reason -Actor $Actor -WhatIf:$WhatIfPreference -NoThrow:$NoThrow

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -eq "fail") {
        throw "Artifact lifecycle transition failed."
    }
    return
}

Write-Host "[OK] Artifact lifecycle updated:"
Write-Host ("Artifact id   : {0}" -f $ArtifactId)
Write-Host ("From state    : {0}" -f $Report.from_state)
Write-Host ("To state      : {0}" -f $Report.to_state)
Write-Host ("Backup path   : {0}" -f $Report.backup_path)
Write-Host ("History count : {0}" -f $Report.history_count)
Write-Host ("Validation    : {0}" -f $Report.validation_valid)

if (-not $NoThrow -and $Report.status -eq "fail") {
    throw "Artifact lifecycle transition failed."
}
