[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$WorkflowScript = Join-Path $PSScriptRoot "Invoke-COOPERPrivateLocalAnalysis.ps1"
$StatusScript = Join-Path $PSScriptRoot "Get-COOPEROperationalStatus.ps1"
$MemoryStatePath = Join-Path $Root "State\COOPER_ProjectMemory.json"
$SkillsStatePath = Join-Path $Root "State\COOPER_Skills.json"

foreach ($Path in @($MemoryStatePath, $SkillsStatePath)) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Remove-Item -LiteralPath $Path -Force
    }
}

$Issues = New-Object System.Collections.Generic.List[string]
$Request = "Analyze the private workshop boundary, local routing, and restricted output path."
$PrivateResult = & $WorkflowScript -Text $Request -Approved -WorkshopMode "Private Workshop" -Root $Root

if ([bool]$PrivateResult.success -ne $true) {
    $Issues.Add("WF-007 private local analysis did not succeed.")
}
if ([string]$PrivateResult.workflow_id -ne "WF-007") {
    $Issues.Add("WF-007 workflow id mismatch.")
}
if ([string]$PrivateResult.output_type -ne "markdown_file") {
    $Issues.Add("WF-007 did not report markdown output.")
}

foreach ($Field in @("analysis_tool_route", "writer_tool_route", "model_route", "analysis_path", "restricted_dmz_path", "approval_decision", "writer_approval_decision", "workbench_result", "workflow_review", "result_artifact_path")) {
    if ($PrivateResult.PSObject.Properties.Name -notcontains $Field) {
        $Issues.Add("WF-007 result is missing '$Field'.")
    }
}

if ($PrivateResult.analysis_tool_route -and [string]$PrivateResult.analysis_tool_route.selected_tool -ne "qwen_local_assistant") {
    $Issues.Add("WF-007 did not route analysis through the private qwen tool.")
}
if ($PrivateResult.analysis_tool_route -and [string]$PrivateResult.analysis_tool_route.registry_path -notmatch 'private_tool_registry\.yaml$') {
    $Issues.Add("WF-007 analysis tool did not resolve from the private registry.")
}
if ($PrivateResult.writer_tool_route -and [string]$PrivateResult.writer_tool_route.selected_tool -ne "restricted_dmz_writer") {
    $Issues.Add("WF-007 did not route output through the restricted DMZ writer.")
}
if ($PrivateResult.writer_tool_route -and [string]$PrivateResult.writer_tool_route.registry_path -notmatch 'private_tool_registry\.yaml$') {
    $Issues.Add("WF-007 writer tool did not resolve from the private registry.")
}
if ($PrivateResult.model_route -and [string]$PrivateResult.model_route.selected_model -ne "local-llama") {
    $Issues.Add("WF-007 did not resolve the local-only model route.")
}
if ($PrivateResult.model_route -and [bool]$PrivateResult.model_route.cloud_allowed -ne $false) {
    $Issues.Add("WF-007 model route incorrectly allowed cloud fallback.")
}

if ($PrivateResult.approval_decision -and [bool]$PrivateResult.approval_decision.execution_authorized -ne $true) {
    $Issues.Add("WF-007 analysis approval did not authorize execution.")
}
if ($PrivateResult.writer_approval_decision -and [bool]$PrivateResult.writer_approval_decision.execution_authorized -ne $true) {
    $Issues.Add("WF-007 writer approval did not authorize execution.")
}

$AnalysisPath = [string]$PrivateResult.analysis_path
if ([string]::IsNullOrWhiteSpace($AnalysisPath)) {
    $Issues.Add("WF-007 did not return an analysis path.")
}
else {
    $ResolvedAnalysisPath = [System.IO.Path]::GetFullPath($AnalysisPath)
    $RestrictedRoot = [System.IO.Path]::GetFullPath((Join-Path $Root "Restricted DMZ Workspace"))
    $RestrictedPrefix = $RestrictedRoot.TrimEnd('\') + '\'
    if (-not ($ResolvedAnalysisPath -eq $RestrictedRoot -or $ResolvedAnalysisPath.StartsWith($RestrictedPrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
        $Issues.Add("WF-007 output path is not inside the Restricted DMZ Workspace.")
    }
    elseif (-not (Test-Path -LiteralPath $ResolvedAnalysisPath -PathType Leaf)) {
        $Issues.Add("WF-007 restricted artifact does not exist.")
    }
    else {
        $Content = Get-Content -LiteralPath $ResolvedAnalysisPath -Raw
        if ($Content -notmatch '(?i)^#\s+WF-007 Private Local Analysis') {
            $Issues.Add("WF-007 restricted artifact is missing the analysis title.")
        }
        if ($Content -notmatch '(?i)Private Workshop') {
            $Issues.Add("WF-007 restricted artifact does not mention Private Workshop.")
        }
        if ($Content -notmatch '(?i)Cloud allowed:\s*False') {
            $Issues.Add("WF-007 restricted artifact does not record the local-only route.")
        }
    }
}

$BlockedOpenResult = & $WorkflowScript -Text $Request -Approved -WorkshopMode "Open Workshop" -Root $Root
if ([bool]$BlockedOpenResult.success -ne $false) {
    $Issues.Add("WF-007 should not execute in Open Workshop.")
}
if ([string]$BlockedOpenResult.reason -notmatch '(?i)Private Workshop') {
    $Issues.Add("WF-007 open-workshop rejection did not explain the private-only boundary.")
}

$StatusResult = & $StatusScript -Root $Root -WorkshopMode "Private Workshop"
if ([string]$StatusResult.status -ne "pass") {
    $Issues.Add("WF-004 status helper did not pass after WF-007 execution.")
}
else {
    $WF007Status = @($StatusResult.workflow_statuses | Where-Object { [string]$_.workflow_id -eq "WF-007" } | Select-Object -First 1)
    if ($WF007Status.Count -eq 0) {
        $Issues.Add("WF-004 did not report WF-007 in the workflow status list.")
    }
    else {
        if ([string]$WF007Status[0].status -ne "pass") {
            $Issues.Add("WF-004 did not report WF-007 as pass.")
        }
        if ([string]$WF007Status[0].last_run_artifact_path -eq "") {
            $Issues.Add("WF-004 did not report a WF-007 artifact path.")
        }
    }
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    workflow = $PrivateResult
    blocked_open = $BlockedOpenResult
    status_result = $StatusResult
    issues = @($Issues)
}

Write-Host "[*] COOPER WF-007 private local analysis workflow"
Write-Host ("Status   : {0}" -f $Report.status)
Write-Host ("Artifact : {0}" -f $AnalysisPath)

if ($Report.status -ne "pass") {
    foreach ($Issue in @($Report.issues)) {
        Write-Host ("[FAIL] {0}" -f $Issue)
    }
    exit 1
}

Write-Host "[PASS] WF-007 private local analysis workflow validated."
exit 0
