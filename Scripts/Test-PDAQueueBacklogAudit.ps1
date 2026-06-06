[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$AuditScript = Join-Path $PSScriptRoot "Invoke-PDAQueueBacklogAudit.ps1"

if (-not (Test-Path -Path $AuditScript -PathType Leaf)) {
    throw "Audit script missing: $AuditScript"
}

$TempReportRoot = Join-Path $Root "PDA-Backups\nightly-build\reports"

$Raw = & pwsh -NoProfile -File $AuditScript -Root $Root -ReportRoot $TempReportRoot -AsJson 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Queue backlog audit failed."
}

$Text = [string]($Raw -join "`n").Trim()
if ([string]::IsNullOrWhiteSpace($Text)) {
    throw "Queue backlog audit returned empty output."
}

$Result = $Text | ConvertFrom-Json

$Issues = New-Object System.Collections.Generic.List[string]
if ($Result.status -ne "pass") {
    $Issues.Add("Audit status was not pass.")
}

if (-not (Test-Path -Path $Result.report_path -PathType Leaf)) {
    $Issues.Add("Audit markdown report was not written.")
}

$ReportText = Get-Content -Path $Result.report_path -Raw
foreach ($Heading in @(
    "# PDA Queue and Approval Backlog Audit",
    "## Queue Counts",
    "## Approval Counts",
    "## Stale Tasks",
    "## Orphaned Approvals",
    "## Failed Tasks",
    "## Dashboard Health Impact",
    "## Recommended Remediation"
)) {
    if ($ReportText -notmatch [regex]::Escape($Heading)) {
        $Issues.Add("Missing markdown heading: $Heading")
    }
}

if ($Result.report_path -notmatch [regex]::Escape("PDA-Backups\nightly-build\reports")) {
    $Issues.Add("Audit report path is not under the nightly-build reports folder.")
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    report_path = [string]$Result.report_path
    queue_counts = $Result.queue_counts
    approval_counts = $Result.approval_counts
    stale_task_count = [int]$Result.stale_task_count
    orphaned_approval_count = [int]$Result.orphaned_approval_count
    failed_task_count = [int]$Result.failed_task_count
    dashboard_health_impact = $Result.dashboard_health_impact
    recommended_remediation = @($Result.recommended_remediation)
    issues = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA queue backlog audit validation failed."
    }
    return
}

Write-Host "[*] PDA queue backlog audit tests"
Write-Host ("Status      : {0}" -f $Report.status)
Write-Host ("Report path : {0}" -f $Report.report_path)
Write-Host ("Stale tasks : {0}" -f $Report.stale_task_count)
Write-Host ("Orphans     : {0}" -f $Report.orphaned_approval_count)
Write-Host ("Failed      : {0}" -f $Report.failed_task_count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA queue backlog audit validation failed."
}
