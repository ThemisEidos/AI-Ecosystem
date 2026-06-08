[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$PlanInstancePath = "",

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

if ([string]::IsNullOrWhiteSpace($PlanInstancePath)) {
    if ([string]::IsNullOrWhiteSpace($PlanId)) {
        throw "Provide either -PlanInstancePath or -PlanId."
    }

    $PlanInstancePath = Find-PDAPlanFile -PlanId $PlanId -Root $Root
}

if ([string]::IsNullOrWhiteSpace($PlanInstancePath) -or -not (Test-Path -LiteralPath $PlanInstancePath -PathType Leaf)) {
    throw "Plan instance not found."
}

$Plan = Read-PDAPlanRecord -Path $PlanInstancePath
$ResultFiles = New-Object System.Collections.Generic.List[object]
$CollectedOutputs = New-Object System.Collections.Generic.List[object]

foreach ($Step in @($Plan.steps)) {
    $Result = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$Step.result_path) -and (Test-Path -LiteralPath [string]$Step.result_path -PathType Leaf)) {
        try {
            $Result = Get-Content -LiteralPath [string]$Step.result_path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            $Result = [pscustomobject]@{
                status = "error"
                error = $_.Exception.Message
            }
        }
    }

    if ($null -eq $Result -and -not [string]::IsNullOrWhiteSpace([string]$Step.task_id)) {
        $FallbackResultPath = Join-Path (Join-Path $Root "PDA-Tasks\results") ("{0}-result.json" -f [string]$Step.task_id)
        if (Test-Path -LiteralPath $FallbackResultPath -PathType Leaf) {
            try {
                $Result = Get-Content -LiteralPath $FallbackResultPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $Step.result_path = $FallbackResultPath
            }
            catch {
                $Result = [pscustomobject]@{
                    status = "error"
                    error = $_.Exception.Message
                }
            }
        }
    }

    $ResultFiles.Add([pscustomobject]@{
        step_id = [string]$Step.step_id
        title = [string]$Step.title
        status = [string]$Step.status
        task_id = [string]$Step.task_id
        result_path = [string]$Step.result_path
        executor = [string]$Step.executor
        output = if ($Result) { ConvertTo-PDAPlanHashtable -Value $Result } else { $null }
    })

    if ($Result -and $Result.PSObject.Properties.Name -contains "output") {
        $CollectedOutputs.Add([pscustomobject]@{
            step_id = [string]$Step.step_id
            title = [string]$Step.title
            task_id = [string]$Step.task_id
            executor = [string]$Step.executor
            output = ConvertTo-PDAPlanHashtable -Value $Result.output
            result_path = [string]$Step.result_path
        })
    }
}

$CompletedSteps = @($Plan.steps | Where-Object { [string]$_.status -eq "completed" })
$FailedSteps = @($Plan.steps | Where-Object { [string]$_.status -in @("failed", "blocked") })
$IsComplete = ($CompletedSteps.Count -eq $StepTotal -and $StepTotal -gt 0)
$Plan.status = if ($FailedSteps.Count -gt 0) { "failed" } elseif ($IsComplete) { "completed" } else { [string]$Plan.status }
$Plan.plan_folder = Get-PDAPlanFolderNameForStatus -Status $Plan.status
$Plan.completed_step_count = $CompletedSteps.Count
$Plan.failed_step_count = $FailedSteps.Count
$StepTotal = [int]@($Plan.steps).Count
$Plan.overall_progress = if ($StepTotal -gt 0) { [math]::Round(($CompletedSteps.Count / $StepTotal) * 100, 0) } else { 0 }
$Plan.results_path = Join-Path (Join-Path $Root "PDA-Plans\$($Plan.plan_folder)") ("{0}-results.json" -f [string]$Plan.plan_id)
$Plan.final_deliverable_package_path = $Plan.results_path
$Plan.updated_at = (Get-Date).ToUniversalTime().ToString("o")
$Plan.current_step = if ($IsComplete) { $StepTotal + 1 } else { $Plan.current_step }

$ResultStatus = if ($FailedSteps.Count -gt 0) { "blocked" } elseif ($IsComplete) { "completed" } else { "partial" }

$BlockedReason = if ($FailedSteps.Count -gt 0) { ([string]$FailedSteps[0].blocked_reason) } else { "" }

$ResultPackage = [pscustomobject]@{}
$ResultPackage | Add-Member -NotePropertyName status -NotePropertyValue $ResultStatus -Force
$ResultPackage | Add-Member -NotePropertyName plan_id -NotePropertyValue ([string]$Plan.plan_id) -Force
$ResultPackage | Add-Member -NotePropertyName goal -NotePropertyValue ([string]$Plan.goal) -Force
$ResultPackage | Add-Member -NotePropertyName plan_path -NotePropertyValue ([string]$Plan.plan_path) -Force
$ResultPackage | Add-Member -NotePropertyName plan_folder -NotePropertyValue ([string]$Plan.plan_folder) -Force
$ResultPackage | Add-Member -NotePropertyName created_at -NotePropertyValue ([string]$Plan.created_at) -Force
$ResultPackage | Add-Member -NotePropertyName updated_at -NotePropertyValue ([string]$Plan.updated_at) -Force
$ResultPackage | Add-Member -NotePropertyName step_count -NotePropertyValue $StepTotal -Force
$ResultPackage | Add-Member -NotePropertyName completed_step_count -NotePropertyValue $CompletedSteps.Count -Force
$ResultPackage | Add-Member -NotePropertyName failed_step_count -NotePropertyValue $FailedSteps.Count -Force
$ResultPackage | Add-Member -NotePropertyName overall_progress -NotePropertyValue ([int]$Plan.overall_progress) -Force
$ResultPackage | Add-Member -NotePropertyName deliverables -NotePropertyValue @($Plan.deliverables) -Force
$ResultPackage | Add-Member -NotePropertyName step_results -NotePropertyValue $ResultFiles.ToArray() -Force
$ResultPackage | Add-Member -NotePropertyName collected_outputs -NotePropertyValue $CollectedOutputs.ToArray() -Force
$ResultPackage | Add-Member -NotePropertyName final_deliverable_package_path -NotePropertyValue ([string]$Plan.results_path) -Force
$ResultPackage | Add-Member -NotePropertyName blocked_reason -NotePropertyValue $BlockedReason -Force

$Plan | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $PlanInstancePath -Encoding UTF8
if ($Plan.status -in @("completed", "failed")) {
    $FinalPlanPath = Move-PDAPlanRecord -Plan $Plan -Status $Plan.status -Root $Root
    $ResultPackage.plan_path = $FinalPlanPath
    $PlanInstancePath = $FinalPlanPath
    $ResultPackage.final_deliverable_package_path = $Plan.results_path
}

$ResultPackage | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Plan.results_path -Encoding UTF8

if ($AsJson) {
    $ResultPackage | ConvertTo-Json -Depth 40
    if (-not $NoThrow -and $ResultPackage.status -eq "blocked") {
        throw "Plan results aggregation reported a failure."
    }
    return
}

Write-Host "[PDA PLAN RESULTS]"
Write-Host ("Plan ID   : {0}" -f $ResultPackage.plan_id)
Write-Host ("Status    : {0}" -f $ResultPackage.status)
Write-Host ("Outputs   : {0}" -f @($CollectedOutputs).Count)
