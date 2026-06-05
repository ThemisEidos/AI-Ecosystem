[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$SummaryScript = Join-Path $PSScriptRoot "Get-PDARoutingSummary.ps1"

if (-not (Test-Path -LiteralPath $SummaryScript -PathType Leaf)) {
    throw "Routing summary script missing: $SummaryScript"
}

function Invoke-RoutingSummary {
    param([Parameter(Mandatory = $true)][string]$LogPath)

    $Raw = & pwsh -NoProfile -File $SummaryScript -LogPath $LogPath -AsJson -NoThrow 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Routing summary returned empty output."
    }

    return $Text | ConvertFrom-Json
}

$Root = Split-Path -Parent $PSScriptRoot
$RealLogPath = Join-Path $Root "PDA-Logs\routing"
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pda-routing-summary-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

try {
    $EmptyPath = Join-Path $TempRoot "empty"
    $SyntheticPath = Join-Path $TempRoot "synthetic"
    New-Item -ItemType Directory -Path $EmptyPath -Force | Out-Null
    New-Item -ItemType Directory -Path $SyntheticPath -Force | Out-Null

    $SyntheticRecords = @(
        [ordered]@{
            command = "/research"
            category = "category_1"
            selected_model = "gemini"
            transport_model = "gemini"
            fallback_chain = @("openrouter")
            fallback_used = $false
            routing_reason = "Research primary"
            routing_surface = "cloud-capable"
            cloud_allowed = $true
            worker = "research-worker"
            timestamp = "2026-06-05T20:00:00Z"
            outcome = "pass"
        }
        [ordered]@{
            command = "/review"
            category = "category_1"
            selected_model = "openai"
            transport_model = "openai"
            fallback_chain = @("openai")
            fallback_used = $true
            routing_reason = "Review fallback"
            routing_surface = "cloud-capable"
            cloud_allowed = $true
            worker = "review-worker"
            timestamp = "2026-06-05T20:01:00Z"
            outcome = "pass"
        }
        [ordered]@{
            command = "/execute"
            category = "category_2"
            selected_model = "local-llama"
            transport_model = "local-llama"
            fallback_chain = @()
            fallback_used = $false
            routing_reason = "Local only"
            routing_surface = "local-only"
            cloud_allowed = $false
            worker = "execute-worker"
            timestamp = "2026-06-05T20:02:00Z"
            outcome = "fail"
        }
        [ordered]@{
            command = "/execute"
            category = "restricted_local"
            selected_model = "local-llama"
            transport_model = "local-llama"
            fallback_chain = @()
            fallback_used = $false
            routing_reason = "Local only"
            routing_surface = "local-only"
            cloud_allowed = $false
            worker = "review-worker"
            timestamp = "2026-06-05T20:03:00Z"
            outcome = "pass"
        }
    )

    $Index = 1
    foreach ($Record in $SyntheticRecords) {
        $Path = Join-Path $SyntheticPath ("synthetic-{0:00}.json" -f $Index)
        $Record | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
        $Index++
    }

    $EmptyResult = Invoke-RoutingSummary -LogPath $EmptyPath
    $SyntheticResult = Invoke-RoutingSummary -LogPath $SyntheticPath
    $RealResult = Invoke-RoutingSummary -LogPath $RealLogPath

    $Results = @()

    $EmptyIssues = @()
    if ($EmptyResult.valid_records -ne 0) { $EmptyIssues += "Empty directory should produce zero valid records." }
    if ($EmptyResult.success_count -ne 0) { $EmptyIssues += "Empty directory should produce zero successes." }
    if ($EmptyResult.failure_count -ne 0) { $EmptyIssues += "Empty directory should produce zero failures." }
    if ($EmptyResult.dispatches_by_command.Count -ne 0) { $EmptyIssues += "Empty directory should produce no command counts." }
    $Results += [pscustomobject]@{
        name = "empty log directory"
        passed = ($EmptyIssues.Count -eq 0)
        issues = @($EmptyIssues)
    }

    $SyntheticIssues = @()
    if ($SyntheticResult.valid_records -ne 4) { $SyntheticIssues += "Synthetic dataset should produce 4 valid records." }
    if ($SyntheticResult.success_count -ne 3) { $SyntheticIssues += "Synthetic dataset should produce 3 successes." }
    if ($SyntheticResult.failure_count -ne 1) { $SyntheticIssues += "Synthetic dataset should produce 1 failure." }
    if ($SyntheticResult.fallback_usage_count -ne 1) { $SyntheticIssues += "Synthetic dataset should produce 1 fallback usage." }
    if ($SyntheticResult.category_1_volume -ne 2) { $SyntheticIssues += "Synthetic dataset should produce 2 category_1 records." }
    if ($SyntheticResult.category_2_volume -ne 2) { $SyntheticIssues += "Synthetic dataset should produce 2 category_2/restricted_local records." }
    if ($SyntheticResult.cloud_usage_count -ne 2) { $SyntheticIssues += "Synthetic dataset should produce 2 cloud records." }
    if ($SyntheticResult.local_usage_count -ne 2) { $SyntheticIssues += "Synthetic dataset should produce 2 local records." }

    $ExecuteCommand = @($SyntheticResult.dispatches_by_command | Where-Object { $_.name -eq "/execute" } | Select-Object -First 1)
    if ($ExecuteCommand.Count -eq 0 -or $ExecuteCommand[0].count -ne 2) { $SyntheticIssues += "Synthetic dataset should count /execute twice." }
    $LocalModel = @($SyntheticResult.dispatches_by_model | Where-Object { $_.name -eq "local-llama" } | Select-Object -First 1)
    if ($LocalModel.Count -eq 0 -or $LocalModel[0].count -ne 2) { $SyntheticIssues += "Synthetic dataset should count local-llama twice." }
    $ReviewWorker = @($SyntheticResult.dispatches_by_worker | Where-Object { $_.name -eq "review-worker" } | Select-Object -First 1)
    if ($ReviewWorker.Count -eq 0 -or $ReviewWorker[0].count -ne 2) { $SyntheticIssues += "Synthetic dataset should count review-worker twice." }
    $LocalReason = @($SyntheticResult.top_routing_reasons | Where-Object { $_.name -eq "Local only" } | Select-Object -First 1)
    if ($LocalReason.Count -eq 0 -or $LocalReason[0].count -ne 2) { $SyntheticIssues += "Synthetic dataset should count 'Local only' twice." }
    $Results += [pscustomobject]@{
        name = "synthetic log validation"
        passed = ($SyntheticIssues.Count -eq 0)
        issues = @($SyntheticIssues)
    }

    $RealIssues = @()
    if ([string]::IsNullOrWhiteSpace([string]$RealResult.status)) { $RealIssues += "Real log summary should return a status." }
    if ($RealResult.valid_records -lt 0) { $RealIssues += "Real log summary should not return a negative record count." }
    $Results += [pscustomobject]@{
        name = "real log directory"
        passed = ($RealIssues.Count -eq 0)
        issues = @($RealIssues)
    }

    $FailedCount = @($Results | Where-Object { -not $_.passed }).Count
    $Report = [pscustomobject]@{
        status = if ($FailedCount -eq 0) { "pass" } else { "fail" }
        summary_script = $SummaryScript
        result_count = $Results.Count
        failed_count = $FailedCount
        results = @($Results)
    }
}
finally {
    if (Test-Path -LiteralPath $TempRoot -PathType Container) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
    }
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA routing summary validation failed."
    }
    return
}

Write-Host "[*] PDA routing summary tests"
Write-Host ("Test cases : {0}" -f $Report.result_count)
Write-Host ("Failed     : {0}" -f $Report.failed_count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA routing summary validation failed."
}
