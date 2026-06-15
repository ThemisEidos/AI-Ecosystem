[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$StatusScript = Join-Path $PSScriptRoot "Invoke-COOPERStatusCommand.ps1"
$ExpectedGeneralRegistryPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\Config\general_tool_registry.yaml"))
$ExpectedPrivateRegistryPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\Config\private_tool_registry.yaml"))

function Invoke-StatusCase {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters,

        [Parameter(Mandatory = $false)]
        [string]$WorkshopModeOverride = ""
    )

    $PreviousMode = [string]$env:COOPER_WORKSHOP_MODE
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkshopModeOverride)) {
            $env:COOPER_WORKSHOP_MODE = $WorkshopModeOverride
        }
        elseif ($env:COOPER_WORKSHOP_MODE) {
            Remove-Item Env:COOPER_WORKSHOP_MODE -ErrorAction SilentlyContinue
        }

        & $StatusScript @Parameters
    }
    finally {
        if ([string]::IsNullOrWhiteSpace($PreviousMode)) {
            Remove-Item Env:COOPER_WORKSHOP_MODE -ErrorAction SilentlyContinue
        }
        else {
            $env:COOPER_WORKSHOP_MODE = $PreviousMode
        }
    }
}

$Cases = @(
    [pscustomobject]@{
        name = "default open workshop status succeeds"
        params = @{}
        expect_success = $true
        expect_workshop_mode = "Open Workshop"
        expect_workshop_name = "COOPER"
        expect_default_model = "Claude Sonnet"
        expect_active_registry = "Config/general_tool_registry.yaml"
        expect_registry = $ExpectedGeneralRegistryPath
        expect_tool_id = "status_summary"
    }
    [pscustomobject]@{
        name = "open workshop status succeeds"
        params = @{ WorkshopMode = "Open Workshop" }
        expect_success = $true
        expect_workshop_mode = "Open Workshop"
        expect_workshop_name = "COOPER"
        expect_default_model = "Claude Sonnet"
        expect_active_registry = "Config/general_tool_registry.yaml"
        expect_registry = $ExpectedGeneralRegistryPath
        expect_tool_id = "status_summary"
    }
    [pscustomobject]@{
        name = "private workshop status succeeds"
        params = @{ WorkshopMode = "Private Workshop" }
        expect_success = $true
        expect_workshop_mode = "Private Workshop"
        expect_workshop_name = "COOPER Private"
        expect_default_model = "local Qwen via Ollama"
        expect_active_registry = "Config/private_tool_registry.yaml"
        expect_registry = $ExpectedPrivateRegistryPath
        expect_tool_id = "status_summary_private"
    }
    [pscustomobject]@{
        name = "env workshop mode respects private workshop"
        params = @{ WorkshopMode = "" }
        env_mode = "Private Workshop"
        expect_success = $true
        expect_workshop_mode = "Private Workshop"
        expect_workshop_name = "COOPER Private"
        expect_default_model = "local Qwen via Ollama"
        expect_active_registry = "Config/private_tool_registry.yaml"
        expect_registry = $ExpectedPrivateRegistryPath
        expect_tool_id = "status_summary_private"
    }
    [pscustomobject]@{
        name = "unsupported workshop fails cleanly"
        params = @{ WorkshopMode = "Unsupported Workshop" }
        expect_success = $false
        expect_reason_like = "Unsupported workshop mode"
    }
)

$Results = @()
$Passed = 0
$Failed = 0

foreach ($Case in $Cases) {
    $Result = Invoke-StatusCase -Parameters $Case.params -WorkshopModeOverride $(if ($Case.PSObject.Properties.Name -contains "env_mode") { [string]$Case.env_mode } else { "" })
    $Issues = New-Object System.Collections.Generic.List[string]

    if ($Case.PSObject.Properties.Name -contains "expect_success" -and [bool]$Result.success -ne [bool]$Case.expect_success) {
        $Issues.Add("Expected success '$($Case.expect_success)' but got '$($Result.success)'.")
    }

    if ($Case.PSObject.Properties.Name -contains "expect_tool_id" -and [string]$Result.tool_id -ne [string]$Case.expect_tool_id) {
        $Issues.Add("Expected tool_id '$($Case.expect_tool_id)' but got '$([string]$Result.tool_id)'.")
    }

    if ($Case.PSObject.Properties.Name -contains "expect_workshop_mode" -and [string]$Result.workshop_mode -ne [string]$Case.expect_workshop_mode) {
        $Issues.Add("Expected workshop_mode '$($Case.expect_workshop_mode)' but got '$([string]$Result.workshop_mode)'.")
    }

    if ($Case.PSObject.Properties.Name -contains "expect_reason_like" -and [string]$Result.reason -notmatch [regex]::Escape([string]$Case.expect_reason_like)) {
        $Issues.Add("Expected reason to contain '$($Case.expect_reason_like)' but got '$([string]$Result.reason)'.")
    }

    if ($Case.PSObject.Properties.Name -contains "expect_success" -and [bool]$Case.expect_success -eq $true) {
        if ($Result.PSObject.Properties.Name -notcontains "workshop_identity") {
            $Issues.Add("Status command must include workshop_identity.")
        }
        if ($Result.PSObject.Properties.Name -notcontains "routed_tool") {
            $Issues.Add("Status command must include routed_tool.")
        }
        if ($Result.PSObject.Properties.Name -notcontains "approval_decision") {
            $Issues.Add("Status command must include approval_decision.")
        }
        if ($Result.PSObject.Properties.Name -notcontains "workbench_result") {
            $Issues.Add("Status command must include workbench_result.")
        }

        if ($Result.workshop_identity -and [string]$Result.workshop_identity.default_model -ne [string]$Case.expect_default_model) {
            $Issues.Add("Expected default model '$($Case.expect_default_model)' but got '$([string]$Result.workshop_identity.default_model)'.")
        }

        if ($Result.workshop_identity -and [string]$Result.workshop_identity.registry_path -notmatch [regex]::Escape([string]$Case.expect_registry)) {
            $Issues.Add("Expected registry path to end with '$($Case.expect_registry)' but got '$([string]$Result.workshop_identity.registry_path)'.")
        }

        if ($Result.routed_tool -and [string]$Result.routed_tool.registry_path -notmatch [regex]::Escape([string]$Case.expect_registry)) {
            $Issues.Add("Routed tool should use the expected registry path.")
        }

        if ($Result.approval_decision -and [bool]$Result.approval_decision.execution_authorized -ne $true) {
            $Issues.Add("Approval decision must authorize status execution.")
        }

        if ($Result.workbench_result -and [bool]$Result.workbench_result.success -ne $true) {
            $Issues.Add("Workbench result must succeed.")
        }

        if ($Result.workbench_result -and $Result.workbench_result.output) {
            foreach ($Field in @("workshop_mode", "workshop_name", "default_model", "cloud_allowed", "active_registry", "status_workflow")) {
                if ($Result.workbench_result.output.PSObject.Properties.Name -notcontains $Field) {
                    $Issues.Add("Status output must include '$Field'.")
                }
            }

            if ([string]$Result.workbench_result.output.workshop_mode -ne [string]$Case.expect_workshop_mode) {
                $Issues.Add("Status output workshop_mode mismatch.")
            }

            if ([string]$Result.workbench_result.output.workshop_name -ne [string]$Case.expect_workshop_name) {
                $Issues.Add("Status output workshop_name mismatch.")
            }

            if ([string]$Result.workbench_result.output.default_model -ne [string]$Case.expect_default_model) {
                $Issues.Add("Status output default_model mismatch.")
            }

            if ([string]$Result.workbench_result.output.active_registry -ne [string]$Case.expect_active_registry) {
                $Issues.Add("Status output active_registry mismatch.")
            }

            $Security = $Result.workbench_result.output.security_sources
            foreach ($Field in @("firewall_status", "ids_status", "backup_status")) {
                if ($Security.PSObject.Properties.Name -notcontains $Field) {
                    $Issues.Add("Status output security_sources must include '$Field'.")
                }
                elseif ([string]$Security.$Field -notmatch '^(Not Configured|Not Available|Unknown)$') {
                    $Issues.Add("Status output '$Field' must be Not Configured, Not Available, or Unknown.")
                }
            }

            if ([string]$Result.response_text -notmatch 'Active Workshop:') {
                $Issues.Add("Response text must mention Active Workshop.")
            }
            if ([string]$Result.response_text -match '(?i)\b(Green|Yellow|Healthy)\b') {
                $Issues.Add("Response text must not invent fictional security status values.")
            }

            if ($Result.workbench_result -and $Result.workbench_result.output -and $Result.workbench_result.output.PSObject.Properties.Name -contains "status_source") {
                if ([string]$Result.workbench_result.output.status_source -match 'Get-COOPERRuntimeStatus\.ps1') {
                    $Issues.Add("Governed status path must not use the legacy runtime status helper as its source of truth.")
                }
            }
        }
    }

    $CasePassed = ($Issues.Count -eq 0)
    if ($CasePassed) {
        $Passed++
    }
    else {
        $Failed++
    }

    $Results += [pscustomobject]@{
        name = $Case.name
        passed = $CasePassed
        success = [bool]$Result.success
        workshop_mode = [string]$Result.workshop_mode
        tool_id = [string]$Result.tool_id
        reason = [string]$Result.reason
        issues = @($Issues)
    }
}

$Report = [pscustomobject]@{
    status = if ($Failed -eq 0) { "pass" } else { "fail" }
    test_case_count = @($Cases).Count
    passed_count = $Passed
    failed_count = $Failed
    results = @($Results)
}

Write-Host "[*] COOPER status command tests"
Write-Host ("Status     : {0}" -f $Report.status)
Write-Host ("Test cases : {0}" -f $Report.test_case_count)
Write-Host ("Passed     : {0}" -f $Report.passed_count)
Write-Host ("Failed     : {0}" -f $Report.failed_count)

foreach ($Result in $Results) {
    if (-not $Result.passed) {
        Write-Host ("[FAIL] {0}" -f $Result.name)
        foreach ($Issue in @($Result.issues)) {
            Write-Host ("[FAIL] {0}" -f $Issue)
        }
    }
}

if ($Report.status -ne "pass") {
    exit 1
}

exit 0
