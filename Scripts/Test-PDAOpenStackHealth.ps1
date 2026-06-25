[CmdletBinding()]
param(
    [switch]$AsJson,
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$StackScript = Join-Path $PSScriptRoot "Test-PDAStack.ps1"
$WebhookHealthUrl = "http://localhost:8788/pda-chat-bridge/healthz"

if (-not (Test-Path -LiteralPath $StackScript -PathType Leaf)) {
    throw "Open stack health script not found: $StackScript"
}

$OpenStackReport = & $StackScript -AsJson -NoThrow | ConvertFrom-Json

$WebhookStatusCode = $null
$WebhookHealthy = $false
$WebhookIssue = $null
try {
    $Params = @{
        Uri             = $WebhookHealthUrl
        Method          = "GET"
        UseBasicParsing = $true
        TimeoutSec      = 5
        ErrorAction     = "Stop"
    }
    $Command = Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue
    if ($Command -and $Command.Parameters.ContainsKey("NoProxy")) {
        $Params.NoProxy = $true
    }
    $Response = Invoke-WebRequest @Params
    $WebhookStatusCode = [int]$Response.StatusCode
    $WebhookHealthy = ($WebhookStatusCode -eq 200)
}
catch {
    if ($_.Exception -and ($_.Exception.PSObject.Properties.Name -contains "Response") -and $_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $WebhookStatusCode = [int]$_.Exception.Response.StatusCode.value__
    }
    $WebhookIssue = $_.Exception.Message
}

$Results = @(
    [pscustomobject]@{
        name = "Open stack"
        type = "aggregate"
        passed = ([string]$OpenStackReport.status -eq "pass")
        issues = @($OpenStackReport.results | Where-Object { -not $_.passed } | ForEach-Object {
            if ($_.issues) { @($_.issues) } else { "Failed: $($_.name)" }
        })
    }
    [pscustomobject]@{
        name = "PDA Webhook Server"
        type = "service"
        passed = $WebhookHealthy
        status_code = $WebhookStatusCode
        url = $WebhookHealthUrl
        issues = if ($WebhookHealthy) { @() } else { @("Webhook server health check failed.", $WebhookIssue | Where-Object { $_ }) }
    }
)

$Failed = @($Results | Where-Object { -not $_.passed }).Count
$Report = [pscustomobject]@{
    status = if ($Failed -eq 0) { "pass" } else { "fail" }
    results = @($Results)
    open_stack_report = $OpenStackReport
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "Open stack health validation failed."
    }
    return
}

Write-Host "=== OPEN STACK HEALTH CHECK ==="
foreach ($Result in $Results) {
    if ($Result.passed) {
        Write-Host ("[OK] {0}" -f $Result.name) -ForegroundColor Green
    }
    else {
        Write-Host ("[FAIL] {0}" -f $Result.name) -ForegroundColor Red
        foreach ($Issue in @($Result.issues)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$Issue)) {
                Write-Host ("       {0}" -f $Issue)
            }
        }
    }
}

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "Open stack health validation failed."
}
