[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Deep,

    [Parameter(Mandatory = $false)]
    [switch]$ValidateOpenWebUIChat,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$OpenWebUIValidationRequested = ($Deep -or $ValidateOpenWebUIChat)
$OpenWebUIValidatorPath = Join-Path $PSScriptRoot "Test-OpenWebUIChatCompletion.ps1"

$Checks = @(
    [pscustomobject]@{
        Name = "Open WebUI"
        Url = "http://localhost:3000"
        AcceptStatusCodes = @(200)
    }
    [pscustomobject]@{
        Name = "n8n"
        Url = "http://localhost:5678"
        AcceptStatusCodes = @(200)
    }
    [pscustomobject]@{
        Name = "LiteLLM"
        Url = "http://localhost:4000/v1/models"
        AcceptStatusCodes = @(200, 401)
    }
    [pscustomobject]@{
        Name = "Ollama"
        Url = "http://localhost:11434/api/tags"
        AcceptStatusCodes = @(200)
    }
)

function Get-HttpStatusCode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [int]$TimeoutSeconds = 5
    )

    try {
        $Response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSeconds
        return [int]$Response.StatusCode
    }
    catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            return [int]$_.Exception.Response.StatusCode.value__
        }

        return $null
    }
}

$Results = @()
$Passed = 0
$Failed = 0

foreach ($Check in $Checks) {
    $Healthy = $false
    $StatusCode = $null

    for ($Attempt = 1; $Attempt -le 10; $Attempt++) {
        $StatusCode = Get-HttpStatusCode -Url $Check.Url -TimeoutSeconds 5
        if ($null -ne $StatusCode -and @($Check.AcceptStatusCodes) -contains $StatusCode) {
            $Healthy = $true
            break
        }

        if ($Attempt -lt 10) {
            Start-Sleep -Seconds 2
        }
    }

    $Issues = @()
    if (-not $Healthy) {
        $Issues += if ($null -ne $StatusCode) {
            "Expected HTTP status in [$(@($Check.AcceptStatusCodes) -join ', ')] but received $StatusCode."
        }
        else {
            "No HTTP response received."
        }
        $Failed++
    }
    else {
        $Passed++
    }

    $Results += [pscustomobject]@{
        name = $Check.Name
        type = "service"
        passed = $Healthy
        url = $Check.Url
        status_code = $StatusCode
        issues = @($Issues)
    }
}

if ($OpenWebUIValidationRequested) {
    $DeepIssues = @()
    $DeepResult = $null

    if (-not (Test-Path -LiteralPath $OpenWebUIValidatorPath -PathType Leaf)) {
        $DeepIssues += "Open WebUI validator script missing: $OpenWebUIValidatorPath"
    }
    else {
        try {
            $Raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $OpenWebUIValidatorPath -AsJson -NoThrow 2>&1
            $JsonText = [string]($Raw -join "`n").Trim()
            if ([string]::IsNullOrWhiteSpace($JsonText)) {
                $DeepIssues += "Open WebUI validator returned no output."
            }
            else {
                $DeepResult = $JsonText | ConvertFrom-Json
            }
        }
        catch {
            $DeepIssues += "Open WebUI validator execution failed: $($_.Exception.Message)"
        }
    }

    $DeepPassed = ($DeepIssues.Count -eq 0 -and $DeepResult -and $DeepResult.status -eq "pass")
    if ($DeepPassed) {
        $Passed++
    }
    else {
        $Failed++
        if ($DeepResult -and $DeepResult.issues) {
            foreach ($Issue in @($DeepResult.issues)) {
                $DeepIssues += [string]$Issue
            }
        }
    }

    $Results += [pscustomobject]@{
        name = "Open WebUI Chat Completion"
        type = "deep_validation"
        passed = $DeepPassed
        url = "http://localhost:3000/api/chat/completions"
        status_code = if ($DeepResult) { $DeepResult.probe.completion_check.status_code } else { $null }
        issues = @($DeepIssues | Select-Object -Unique)
        details = if ($DeepResult) { $DeepResult } else { $null }
    }
}

$Report = [pscustomobject]@{
    status = if ($Failed -eq 0) { "pass" } else { "fail" }
    deep_validation_requested = $OpenWebUIValidationRequested
    validator_path = $OpenWebUIValidatorPath
    service_check_count = $Checks.Count
    total_check_count = $Results.Count
    passed_count = $Passed
    failed_count = $Failed
    results = @($Results)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA stack validation failed."
    }
    return
}

Write-Host "=== PDA STACK HEALTH CHECK ==="

foreach ($Result in $Results | Where-Object { $_.type -eq "service" }) {
    if ($Result.passed) {
        if ($Result.status_code -eq 200) {
            Write-Host ("[OK] {0}" -f $Result.name)
        }
        else {
            Write-Host ("[OK] {0} (HTTP {1})" -f $Result.name, $Result.status_code)
        }
    }
    else {
        Write-Host ("[FAIL] {0}" -f $Result.name)
    }
}

if ($OpenWebUIValidationRequested) {
    Write-Host ""
    Write-Host "=== DEEP VALIDATION ==="
    $DeepValidation = $Results | Where-Object { $_.type -eq "deep_validation" } | Select-Object -First 1
    if ($DeepValidation) {
        if ($DeepValidation.passed) {
            Write-Host ("[OK] {0}" -f $DeepValidation.name)
        }
        else {
            Write-Host ("[FAIL] {0}" -f $DeepValidation.name)
            foreach ($Issue in @($DeepValidation.issues)) {
                Write-Host ("      {0}" -f $Issue)
            }
        }
    }
}

Write-Host ""
Write-Host "=== CONTAINERS ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA stack validation failed."
}
