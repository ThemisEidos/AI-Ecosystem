[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Capability = "",

    [Parameter(Mandatory = $false)]
    [string]$WorkerName = "",

    [Parameter(Mandatory = $false)]
    [string]$Command = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("category_1", "category_2")]
    [string]$Category = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("none", "human_approval", "blocked")]
    [string]$ApprovalRequirement = "",

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_Retrieval.ps1")

$QueryArgs = @{
    Root = $Root
}
if (-not [string]::IsNullOrWhiteSpace($Capability)) { $QueryArgs.Capability = $Capability }
if (-not [string]::IsNullOrWhiteSpace($WorkerName)) { $QueryArgs.WorkerName = $WorkerName }
if (-not [string]::IsNullOrWhiteSpace($Command)) { $QueryArgs.Command = $Command }
if (-not [string]::IsNullOrWhiteSpace($Category)) { $QueryArgs.Category = $Category }
if (-not [string]::IsNullOrWhiteSpace($ApprovalRequirement)) { $QueryArgs.ApprovalRequirement = $ApprovalRequirement }

$Results = @(Get-PDAWorkerCapability @QueryArgs)
$Report = [pscustomobject]@{
    count = $Results.Count
    filters = [pscustomobject]@{
        capability = $Capability
        worker_name = $WorkerName
        command = $Command
        category = $Category
        approval_requirement = $ApprovalRequirement
    }
    workers = $Results
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] Worker capability results:"
Write-Host ("Count   : {0}" -f $Results.Count)
if ($Results.Count -eq 0) {
    Write-Host "No workers matched the query."
    return
}

$Results |
    Select-Object worker_name, command, routing_surface, cloud_capable, status, ontology_task_type, ontology_intent |
    Format-Table -AutoSize
