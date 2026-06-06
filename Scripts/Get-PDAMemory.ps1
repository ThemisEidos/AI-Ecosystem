[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Category = "",

    [Parameter(Mandatory = $false)]
    [string[]]$Tags = @(),

    [Parameter(Mandatory = $false)]
    [string]$SourceArtifactId = "",

    [Parameter(Mandatory = $false)]
    [string]$Status = "",

    [Parameter(Mandatory = $false)]
    [string]$MemoryType = "",

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
if (-not [string]::IsNullOrWhiteSpace($Category)) { $QueryArgs.Category = $Category }
if ($Tags -and @($Tags).Count -gt 0) { $QueryArgs.Tags = $Tags }
if (-not [string]::IsNullOrWhiteSpace($SourceArtifactId)) { $QueryArgs.SourceArtifactId = $SourceArtifactId }
if (-not [string]::IsNullOrWhiteSpace($Status)) { $QueryArgs.Status = $Status }
if (-not [string]::IsNullOrWhiteSpace($MemoryType)) { $QueryArgs.MemoryType = $MemoryType }
if (-not [string]::IsNullOrWhiteSpace($LifecycleState)) { $QueryArgs.LifecycleState = $LifecycleState }
if ($PSBoundParameters.ContainsKey("Latest")) { $QueryArgs.Latest = $Latest }

$Results = @(Get-PDAMemory @QueryArgs)
$Report = [pscustomobject]@{
    count = $Results.Count
    filters = [pscustomobject]@{
        category = $Category
        tags = @($Tags)
        source_artifact_id = $SourceArtifactId
        status = $Status
        memory_type = $MemoryType
        lifecycle_state = $LifecycleState
        latest = if ($PSBoundParameters.ContainsKey("Latest")) { $Latest } else { $null }
    }
    memories = $Results
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] Memory retrieval results:"
Write-Host ("Count   : {0}" -f $Results.Count)
if ($Results.Count -eq 0) {
    Write-Host "No memories matched the query."
    return
}

$Results |
    Select-Object memory_id, created_at, memory_type, category, source_artifact_id, source_path, title, summary |
    Format-Table -AutoSize
