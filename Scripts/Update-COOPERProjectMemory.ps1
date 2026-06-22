[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkflowId,

    [Parameter(Mandatory = $false)]
    [object]$ReviewResult = $null,

    [Parameter(Mandatory = $false)]
    [string]$RequestText = "",

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "",

    [Parameter(Mandatory = $false)]
    [string]$StatePath = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = Join-Path $Root "State\COOPER_ProjectMemory.json"
}

function New-COOPERProjectMemorySnapshot {
    return [ordered]@{
        current_phase = "Phase 6 - Private Workshop Hardening"
        operational_workflows = @()
        broken_workflows = @()
        recent_decisions = @()
        open_blockers = @(
            "WF-001 research requests require the research workflow route and review layer."
        )
        last_successful_workflow = $null
        last_failed_workflow = $null
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
        source_of_truth = "State/COOPER_ProjectMemory.json"
    }
}

function Read-COOPERProjectMemorySnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return New-COOPERProjectMemorySnapshot
    }

    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        return New-COOPERProjectMemorySnapshot
    }
}

function ConvertTo-COOPERMemoryList {
    param([Parameter(Mandatory = $false)]$Value)

    if ($null -eq $Value) {
        return @()
    }

    return @(
        @($Value) |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { [string]$_ }
    )
}

function ConvertTo-COOPERWorkflowIdList {
    param([Parameter(Mandatory = $false)]$Value)

    $Items = ConvertTo-COOPERMemoryList -Value $Value
    $WorkflowIds = New-Object System.Collections.Generic.List[string]
    foreach ($Item in $Items) {
        $Matches = [regex]::Matches([string]$Item, 'WF-\d+')
        if ($Matches.Count -gt 0) {
            foreach ($Match in $Matches) {
                $WorkflowId = [string]$Match.Value
                if (-not [string]::IsNullOrWhiteSpace($WorkflowId) -and $WorkflowIds -notcontains $WorkflowId) {
                    $WorkflowIds.Add($WorkflowId)
                }
            }
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$Item) -and $WorkflowIds -notcontains [string]$Item) {
            $WorkflowIds.Add([string]$Item)
        }
    }

    return @($WorkflowIds)
}

$Memory = Read-COOPERProjectMemorySnapshot -Path $StatePath
$Now = (Get-Date).ToUniversalTime().ToString("o")
$ReviewStatus = ""
$ReviewReason = ""
$ReviewPassed = $false

if ($ReviewResult) {
    if ($ReviewResult.PSObject.Properties.Name -contains "status") {
        $ReviewStatus = [string]$ReviewResult.status
    }
    if ($ReviewResult.PSObject.Properties.Name -contains "reason") {
        $ReviewReason = [string]$ReviewResult.reason
    }
    if ($ReviewResult.PSObject.Properties.Name -contains "review_passed") {
        $ReviewPassed = [bool]$ReviewResult.review_passed
    }
    elseif ($ReviewStatus -eq "pass") {
        $ReviewPassed = $true
    }
}

if ($ReviewPassed) {
    $Memory.current_phase = "Phase 6 - Private Workshop Hardening"
    $Operational = ConvertTo-COOPERWorkflowIdList -Value $Memory.operational_workflows
    if ($Operational -notcontains $WorkflowId) {
        $Operational += $WorkflowId
    }
    $Memory.operational_workflows = @($Operational | Select-Object -Unique)

    $Memory.last_successful_workflow = [pscustomobject]@{
        workflow_id = $WorkflowId
        review_status = "pass"
        request_text = $RequestText
        output_path = $OutputPath
        recorded_at = $Now
    }

    $RecentDecisions = @($Memory.recent_decisions)
    $RecentDecisions += [pscustomobject]@{
        date = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
        decision = "Workflow $WorkflowId completed successfully after review."
        workflow_id = $WorkflowId
    }
    $Memory.recent_decisions = @($RecentDecisions | Where-Object { $null -ne $_ })
}
else {
    $Broken = ConvertTo-COOPERMemoryList -Value $Memory.broken_workflows
    if ($Broken -notcontains $WorkflowId) {
        $Broken += $WorkflowId
    }
    $Memory.broken_workflows = @($Broken | Select-Object -Unique)

    $Memory.last_failed_workflow = [pscustomobject]@{
        workflow_id = $WorkflowId
        review_status = if ($ReviewStatus) { $ReviewStatus } else { "fail" }
        reason = $ReviewReason
        request_text = $RequestText
        output_path = $OutputPath
        recorded_at = $Now
    }

    if (-not [string]::IsNullOrWhiteSpace($ReviewReason)) {
        $Memory.open_blockers = @(@($Memory.open_blockers) + $ReviewReason | Select-Object -Unique)
    }
}

$Memory.updated_at = $Now

$Parent = Split-Path -Parent $StatePath
if (-not (Test-Path -LiteralPath $Parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null
}

$Memory | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $StatePath -Encoding UTF8

return [pscustomobject]@{
    status = if ($ReviewPassed) { "pass" } else { "fail" }
    workflow_id = $WorkflowId
    state_path = $StatePath
    project_memory = $Memory
    source_of_truth = "Scripts/Update-COOPERProjectMemory.ps1"
}
