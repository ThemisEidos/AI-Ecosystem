[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$StatusScript = Join-Path $PSScriptRoot "Get-PDADashboardStatus.ps1"
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
if (Test-Path -LiteralPath $ParserPath -PathType Leaf) {
    . $ParserPath
}

function Invoke-PDADashboardStatusCase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkshopMode
    )

    $PreviousMode = [string]$env:COOPER_WORKSHOP_MODE
    try {
        $env:COOPER_WORKSHOP_MODE = $WorkshopMode
        $Raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $StatusScript -RootPath $Root -AsJson -NoThrow 2>&1
        $Text = [string]($Raw -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($Text)) {
            throw "Dashboard status returned empty output."
        }

        return ConvertFrom-PDAMixedJson -Text $Text -SourceName $StatusScript
    }
    finally {
        if ([string]::IsNullOrWhiteSpace($PreviousMode)) {
            Remove-Item Env:\COOPER_WORKSHOP_MODE -ErrorAction SilentlyContinue
        }
        else {
            $env:COOPER_WORKSHOP_MODE = $PreviousMode
        }
    }
}

$Cases = @(
    [pscustomobject]@{
        name = "open workshop"
        workshop_mode = "Open Workshop"
        expected_registry = "Config/general_tool_registry.yaml"
        expected_default_model = "Claude Sonnet"
        expected_cloud_allowed = $true
        expected_workshop_name = "COOPER"
    }
    [pscustomobject]@{
        name = "private workshop"
        workshop_mode = "Private Workshop"
        expected_registry = "Config/private_tool_registry.yaml"
        expected_default_model = "local Qwen via Ollama"
        expected_cloud_allowed = $false
        expected_workshop_name = "COOPER Private"
    }
)

$Results = @()
$Passed = 0
$Failed = 0

foreach ($Case in $Cases) {
    $Issues = New-Object System.Collections.Generic.List[string]
    try {
        $Report = Invoke-PDADashboardStatusCase -WorkshopMode $Case.workshop_mode

        if ($Report.status -ne "pass") {
            $Issues.Add("Dashboard status report did not pass.")
        }

        if (-not ($Report.PSObject.Properties.Name -contains "cooper_status")) {
            $Issues.Add("Dashboard status report did not include cooper_status.")
        }
        else {
            $Status = $Report.cooper_status
            if ($Status.status_source -match 'Get-COOPERRuntimeStatus\.ps1') {
                $Issues.Add("Dashboard status source must not use the legacy runtime helper as authoritative output.")
            }
            if ($Status.workshop_mode -ne $Case.workshop_mode) {
                $Issues.Add("Expected workshop_mode '$($Case.workshop_mode)' but got '$($Status.workshop_mode)'.")
            }
            if ($Status.workshop_name -ne $Case.expected_workshop_name) {
                $Issues.Add("Expected workshop_name '$($Case.expected_workshop_name)' but got '$($Status.workshop_name)'.")
            }
            if ($Status.default_model -ne $Case.expected_default_model) {
                $Issues.Add("Expected default_model '$($Case.expected_default_model)' but got '$($Status.default_model)'.")
            }
            if ([bool]$Status.cloud_allowed -ne [bool]$Case.expected_cloud_allowed) {
                $Issues.Add("Expected cloud_allowed '$($Case.expected_cloud_allowed)' but got '$($Status.cloud_allowed)'.")
            }
            if ($Status.active_registry -ne $Case.expected_registry) {
                $Issues.Add("Expected active_registry '$($Case.expected_registry)' but got '$($Status.active_registry)'.")
            }

            $Security = $Status.security_sources
            foreach ($Field in @("firewall_status", "ids_status", "backup_status")) {
                if (-not ($Security -and $Security.PSObject.Properties.Name -contains $Field)) {
                    $Issues.Add("Dashboard security_sources must include '$Field'.")
                    continue
                }
                if ([string]$Security.$Field -notin @("Not Configured", "Legacy Non-Authoritative", "Not Available", "Unknown")) {
                    $Issues.Add("Dashboard security source '$Field' used an unsupported value '$([string]$Security.$Field)'.")
                }
            }

            if ($Status.summary_lines -match '(?i)\bFirewall Status:\s*(Green|Yellow|Red|Healthy)|IDS Status:\s*(Green|Yellow|Red|Healthy)|Backup Status:\s*(Green|Yellow|Red|Healthy)') {
                $Issues.Add("Dashboard summary lines surfaced fictional security health values.")
            }
        }
    }
    catch {
        $Issues.Add($_.Exception.Message)
    }

    $CasePassed = ($Issues.Count -eq 0)
    $Results += [pscustomobject]@{
        name = $Case.name
        passed = $CasePassed
        workshop_mode = $Case.workshop_mode
        issues = @($Issues)
    }

    if ($CasePassed) {
        $Passed++
    }
    else {
        $Failed++
    }
}

$Report = [pscustomobject]@{
    status = if ($Failed -eq 0) { "pass" } else { "fail" }
    test_case_count = @($Results).Count
    passed_count = $Passed
    failed_count = $Failed
    results = @($Results)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA dashboard status validation failed."
    }
    return
}

Write-Host "[*] PDA dashboard status tests"
Write-Host ("Test cases : {0}" -f $Report.test_case_count)
Write-Host ("Passed     : {0}" -f $Report.passed_count)
Write-Host ("Failed     : {0}" -f $Report.failed_count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA dashboard status validation failed."
}
