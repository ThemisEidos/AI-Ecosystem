[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$TempRoot = Join-Path $Root "PDA-Tasks\temp\fabric-alias-tests"
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$Cases = @(
    [pscustomobject]@{
        alias = "research"
        command = "/fabric research"
        pattern = "Research/research-synthesis"
        message = "PDA fabric research alias test input."
    }
    [pscustomobject]@{
        alias = "report"
        command = "/fabric report"
        pattern = "Reporting/report-summary"
        message = "PDA fabric report alias test input."
    }
    [pscustomobject]@{
        alias = "review"
        command = "/fabric review"
        pattern = "Review/review-checklist"
        message = "PDA fabric review alias test input."
    }
    [pscustomobject]@{
        alias = "security"
        command = "/fabric security"
        pattern = "Security/security-triage"
        message = "PDA fabric security alias test input."
    }
)

$Results = @()

foreach ($Case in $Cases) {
    $TaskId = [guid]::NewGuid().ToString()
    $TaskPath = Join-Path $TempRoot "$TaskId-$($Case.alias).json"
    $Task = [pscustomobject]@{
        task_id = $TaskId
        command = $Case.command
        route = "fabric"
        assigned_worker = "fabric-worker"
        worker = "fabric-worker"
        routing_surface = "local-or-litellm"
        pattern = $Case.pattern
        pattern_alias = $Case.alias
        message = $Case.message
        source_path = ""
        category = "category_1"
        classification = "category_1"
        model = "llama3.2:latest"
        input_mode = "message-only-test"
        dry_run = $false
        approved = $true
        status = "pending"
        created_at = (Get-Date).ToString("s")
        task_type = "fabric_$($Case.alias)_pattern"
        intent = "fabric_$($Case.alias)_pattern"
        requires_approval = $false
    }

    $Task | ConvertTo-Json -Depth 8 | Set-Content $TaskPath -Encoding UTF8

    $WorkerResult = & pwsh -NoProfile -File (Join-Path $PSScriptRoot "Invoke-PDAFabricWorker.ps1") -TaskPath $TaskPath 2>&1
    $WorkerExit = $LASTEXITCODE
    $ResultPath = Join-Path $Root "PDA-Tasks\results\$TaskId-result.json"

    $ParsedResult = $null
    if (Test-Path $ResultPath) {
        try {
            $ParsedResult = Get-Content $ResultPath -Raw | ConvertFrom-Json
        }
        catch {
            $ParsedResult = $null
        }
    }

    $ArtifactOk = $ParsedResult -and (Test-Path ([string]$ParsedResult.artifact_path))
    $Pass = ($WorkerExit -eq 0 -and $ParsedResult -and [string]$ParsedResult.status -eq "success" -and [string]$ParsedResult.pattern -eq $Case.pattern -and [string]$ParsedResult.command -eq $Case.command -and $ArtifactOk)

    $Results += [pscustomobject]@{
        alias = $Case.alias
        command = $Case.command
        pattern = $Case.pattern
        exit_code = $WorkerExit
        status = if ($Pass) { "pass" } else { "fail" }
        result_path = $ResultPath
        artifact_path = if ($ParsedResult) { [string]$ParsedResult.artifact_path } else { "" }
    }
}

$PassedCount = @($Results | Where-Object { $_.status -eq "pass" }).Count
$FailedCount = @($Results | Where-Object { $_.status -eq "fail" }).Count
$Status = if ($FailedCount -eq 0) { "pass" } else { "fail" }

$Report = [pscustomobject]@{
    status = $Status
    test_case_count = $Results.Count
    passed_count = $PassedCount
    failed_count = $FailedCount
    results = @($Results)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 12
    return
}

Write-Host "[*] Fabric alias command validation"
Write-Host ("Status   : {0}" -f $Report.status)
Write-Host ("Passed   : {0}" -f $Report.passed_count)
Write-Host ("Failed   : {0}" -f $Report.failed_count)

if ($FailedCount -gt 0 -and -not $NoThrow) {
    throw "Fabric alias command validation failed."
}
