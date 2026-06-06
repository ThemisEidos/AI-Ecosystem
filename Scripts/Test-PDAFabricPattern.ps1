[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$FabricScript = Join-Path $PSScriptRoot "Invoke-PDAFabricPattern.ps1"
$PatternRoot = Join-Path $Root "PDA-Fabric"

function Add-FabricTestResult {
    param(
        [System.Collections.Generic.List[object]]$Results,
        [string]$Name,
        [bool]$Passed,
        [string]$Detail = ""
    )

    $Results.Add([pscustomobject]@{
        name = $Name
        passed = $Passed
        detail = $Detail
    }) | Out-Null
}

$Results = New-Object System.Collections.Generic.List[object]
$BypassScan = [pscustomobject]@{
    model_call = $false
    queue_bypass = $false
    legacy_queue_reference = $false
}

try {
    $Source = Get-Content -Path $FabricScript -Raw
    $BypassScan.model_call = (
        ($Source -match '(?i)Invoke-PDAModel') -or
        ($Source -match '(?i)Invoke-RestMethod') -or
        ($Source -match '(?i)chat/completions') -or
        ($Source -match '(?i)v1/chat/completions') -or
        ($Source -match '(?i)Get-Command\s+fabric') -or
        ($Source -match '(?i)fabric\s+--pattern')
    )
    $BypassScan.queue_bypass = (
        ($Source -match '(?i)Resolve-PDATaskDispatchContext') -or
        ($Source -match '(?i)PDA-Tasks\\pending') -or
        ($Source -match '(?i)PDA-Tasks\\running') -or
        ($Source -match '(?i)PDA-Tasks\\completed') -or
        ($Source -match '(?i)PDA-Tasks\\failed') -or
        ($Source -match '(?i)PDA-Tasks\\results')
    )
    $BypassScan.legacy_queue_reference = ($Source -match '(?i)\bTasks\\')
}
catch {
    Add-FabricTestResult -Results $Results -Name "source_scan" -Passed $false -Detail $_.Exception.Message
}

foreach ($Path in @(
    $PatternRoot,
    (Join-Path $PatternRoot "Research"),
    (Join-Path $PatternRoot "Reporting"),
    (Join-Path $PatternRoot "Review"),
    (Join-Path $PatternRoot "Security")
)) {
    Add-FabricTestResult -Results $Results -Name "path_exists:$Path" -Passed (Test-Path $Path) -Detail $Path
}

$SampleInput = @"
PDA Fabric should render prompt templates without invoking a model.
This sample content verifies placeholder replacement and template loading.
"@
$SampleVariables = @{
    audience = "operators"
    focus = "status"
    tone = "concise"
}

$RenderCase = & pwsh -NoProfile -File $FabricScript -PatternName "Reporting/report-summary" -ContentInput $SampleInput -VariablesJson ($SampleVariables | ConvertTo-Json -Compress) -AsJson | ConvertFrom-Json

Add-FabricTestResult -Results $Results -Name "pattern_loads" -Passed ($RenderCase.status -eq "success" -and (Test-Path (Join-Path $PatternRoot "Reporting\report-summary.md"))) -Detail $RenderCase.pattern_path
Add-FabricTestResult -Results $Results -Name "variables_render" -Passed (
    $RenderCase.status -eq "success" -and
    $RenderCase.rendered_prompt -match 'operators' -and
    $RenderCase.rendered_prompt -match 'status' -and
    $RenderCase.rendered_prompt -match 'concise' -and
    $RenderCase.rendered_prompt -match [regex]::Escape($SampleInput.Trim())
) -Detail ("Rendered length: {0}" -f $RenderCase.rendered_prompt_length)

$MissingCase = & pwsh -NoProfile -File $FabricScript -PatternName "Missing/no-such-pattern" -ContentInput "missing pattern check" -AsJson | ConvertFrom-Json
Add-FabricTestResult -Results $Results -Name "missing_pattern_safe" -Passed ($MissingCase.status -eq "missing_pattern" -and -not [string]::IsNullOrWhiteSpace($MissingCase.error)) -Detail $MissingCase.error
Add-FabricTestResult -Results $Results -Name "no_model_calls" -Passed (-not $BypassScan.model_call) -Detail ("model_call={0}" -f $BypassScan.model_call)
Add-FabricTestResult -Results $Results -Name "no_queue_bypass" -Passed ((-not $BypassScan.queue_bypass) -and (-not $BypassScan.legacy_queue_reference)) -Detail ("queue_bypass={0}; legacy={1}" -f $BypassScan.queue_bypass, $BypassScan.legacy_queue_reference)

$PassedCount = 0
$FailedCount = 0
foreach ($Item in $Results) {
    if ($Item.passed) {
        $PassedCount++
    }
    else {
        $FailedCount++
    }
}
$Status = if ($FailedCount -eq 0) { "pass" } else { "fail" }

$Report = [pscustomobject]@{
    status = $Status
    test_case_count = $Results.Count
    passed_count = $PassedCount
    failed_count = $FailedCount
    pattern_root = $PatternRoot
    fabric_script = $FabricScript
    bypass_scan = $BypassScan
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    return
}

Write-Host "[*] Fabric pattern validation"
Write-Host ("Status   : {0}" -f $Report.status)
Write-Host ("Passed   : {0}" -f $Report.passed_count)
Write-Host ("Failed   : {0}" -f $Report.failed_count)
Write-Host ("Script   : {0}" -f $Report.fabric_script)
Write-Host ("Pattern root : {0}" -f $Report.pattern_root)

if ($FailedCount -gt 0 -and -not $NoThrow) {
    throw "Fabric pattern validation failed."
}
