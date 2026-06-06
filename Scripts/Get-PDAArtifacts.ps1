[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$WorkerName = "",

    [Parameter(Mandatory = $false)]
    [string]$Category = "",

    [Parameter(Mandatory = $false)]
    [string[]]$Tags = @(),

    [Parameter(Mandatory = $false)]
    [string]$ArtifactType = "",

    [Parameter(Mandatory = $false)]
    [string]$Lineage = "",

    [Parameter(Mandatory = $false)]
    [string]$LifecycleState = "",

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10000)]
    [int]$Latest,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_Retrieval.ps1")

$QueryArgs = @{
    Root = $Root
}
if (-not [string]::IsNullOrWhiteSpace($WorkerName)) { $QueryArgs.WorkerName = $WorkerName }
if (-not [string]::IsNullOrWhiteSpace($Category)) { $QueryArgs.Category = $Category }
if ($Tags -and @($Tags).Count -gt 0) { $QueryArgs.Tags = $Tags }
if (-not [string]::IsNullOrWhiteSpace($ArtifactType)) { $QueryArgs.ArtifactType = $ArtifactType }
if (-not [string]::IsNullOrWhiteSpace($Lineage)) { $QueryArgs.Lineage = $Lineage }
if (-not [string]::IsNullOrWhiteSpace($LifecycleState)) { $QueryArgs.LifecycleState = $LifecycleState }
if ($PSBoundParameters.ContainsKey("Latest")) { $QueryArgs.Latest = $Latest }

$Results = @(Get-PDAArtifacts @QueryArgs)
$Report = [pscustomobject]@{
    count = $Results.Count
    filters = [pscustomobject]@{
        worker_name = $WorkerName
        category = $Category
        tags = @($Tags)
        artifact_type = $ArtifactType
        lineage = $Lineage
        lifecycle_state = $LifecycleState
        latest = if ($PSBoundParameters.ContainsKey("Latest")) { $Latest } else { $null }
    }
    artifacts = $Results
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] Artifact retrieval results:"
Write-Host ("Count   : {0}" -f $Results.Count)
if ($Results.Count -eq 0) {
    Write-Host "No artifacts matched the query."
    return
}

$Results |
    Select-Object artifact_id, created_at, worker_name, category, artifact_type, artifact_path, summary |
    Format-Table -AutoSize
