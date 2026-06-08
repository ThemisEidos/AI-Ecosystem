[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$PlanId = "",

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "PDA_PlanOrchestration.ps1")

$Collection = Get-PDAPlanStatusCollection -Root $Root

if (-not [string]::IsNullOrWhiteSpace($PlanId)) {
    $Collection.plans = @($Collection.plans | Where-Object { [string]$_.plan_id -eq $PlanId })
    $Collection.pending_approvals = @($Collection.pending_approvals | Where-Object { [string]$_.plan_id -eq $PlanId })
    $Collection.running_plans = @($Collection.running_plans | Where-Object { [string]$_.plan_id -eq $PlanId })
    $Collection.blocked_plans = @($Collection.blocked_plans | Where-Object { [string]$_.plan_id -eq $PlanId })
    $Collection.completed_plans = @($Collection.completed_plans | Where-Object { [string]$_.plan_id -eq $PlanId })
    $Collection.failed_plans = @($Collection.failed_plans | Where-Object { [string]$_.plan_id -eq $PlanId })
    $Collection.recent_deliverables = @($Collection.recent_deliverables | Where-Object { [string]$_.plan_id -eq $PlanId })
}

$Collection | Add-Member -NotePropertyName status -NotePropertyValue $(if ($Collection.counts.total -gt 0) { "pass" } else { "empty" }) -Force

if ($AsJson) {
    $Collection | ConvertTo-Json -Depth 40
    if (-not $NoThrow -and $Collection.status -eq "empty") {
        throw "No plan records found."
    }
    return
}

Write-Host "[PDA PLAN STATUS]"
Write-Host ("Plans     : {0}" -f $Collection.counts.total)
Write-Host ("Running   : {0}" -f $Collection.counts.running)
Write-Host ("Blocked   : {0}" -f $Collection.counts.blocked)
Write-Host ("Complete  : {0}" -f $Collection.counts.completed)
