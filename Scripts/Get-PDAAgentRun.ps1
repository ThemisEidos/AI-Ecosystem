[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$RunId = "",

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$Latest = 10,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$HelperPath = Join-Path $PSScriptRoot "PDA_AgentLoop.ps1"
if (-not (Test-Path -LiteralPath $HelperPath -PathType Leaf)) {
    throw "Agent loop helper missing: $HelperPath"
}
. $HelperPath

$Index = Get-PDAAgentRunIndex -Root $Root

if (-not [string]::IsNullOrWhiteSpace($RunId)) {
    $Run = Get-PDAAgentRunRecord -RunId $RunId -Root $Root
    if (-not $Run) {
        $Report = [pscustomobject]@{
            status = "missing"
            run_id = $RunId
            run = $null
        }
    }
    else {
        $Report = [pscustomobject]@{
            status = "pass"
            run_id = $RunId
            run = $Run
        }
    }
}
else {
    $Runs = @($Index.runs | Select-Object -First $Latest)
    $Report = [pscustomobject]@{
        status = [string]$Index.status
        run_count = [int]$Index.run_count
        active_run_count = [int]$Index.active_run_count
        pending_approval_count = [int]$Index.pending_approval_count
        completed_count = [int]$Index.completed_count
        blocked_count = [int]$Index.blocked_count
        latest_run = $Index.latest_run
        runs = $Runs
        index_path = $Index.index_path
        store_path = $Index.store_path
    }
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 30
    return
}

if (-not [string]::IsNullOrWhiteSpace($RunId)) {
    Write-Host "[PDA AGENT RUN]"
    Write-Host ("Run ID : {0}" -f $RunId)
    Write-Host ("Status : {0}" -f $Report.status)
}
else {
    Write-Host "[PDA AGENT RUN SUMMARY]"
    Write-Host ("Runs                : {0}" -f $Report.run_count)
    Write-Host ("Active              : {0}" -f $Report.active_run_count)
    Write-Host ("Pending approvals   : {0}" -f $Report.pending_approval_count)
    Write-Host ("Completed           : {0}" -f $Report.completed_count)
    Write-Host ("Blocked             : {0}" -f $Report.blocked_count)
}
