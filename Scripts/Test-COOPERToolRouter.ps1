[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$RouterScript = Join-Path $PSScriptRoot "Invoke-COOPERTool.ps1"
$TempPrivateRegistryLevel3 = Join-Path ([System.IO.Path]::GetTempPath()) "cooper-private-tool-registry-level3-test.yaml"
$TempPrivateRegistryExternal = Join-Path ([System.IO.Path]::GetTempPath()) "cooper-private-tool-registry-external-test.yaml"
$TempIgnoredGeneralRegistry = Join-Path ([System.IO.Path]::GetTempPath()) "cooper-router-ignored-general-registry-test.yaml"
$TempIgnoredPrivateRegistry = Join-Path ([System.IO.Path]::GetTempPath()) "cooper-router-ignored-private-registry-test.yaml"

$ExpectedGeneralRegistryPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\Config\general_tool_registry.yaml"))
$ExpectedPrivateRegistryPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\Config\private_tool_registry.yaml"))

function Invoke-RouterCase {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )

    & $RouterScript @Parameters
}

function New-PrivateRegistryFixture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ToolId,

        [Parameter(Mandatory = $true)]
        [int]$PermissionLevel,

        [Parameter(Mandatory = $true)]
        [string]$ExecutorType
    )

    $Content = @"
registry_name: Test Private Workshop Registry
workshop: Private Workshop
version: 1
purpose: Test fixture for router validation.
generated_at: "2026-06-14"
tools:
  - id: $ToolId
    name: Test Private Tool
    drawer: Local Automation
    workshop: Private Workshop
    description: Synthetic private tool used to verify router blocking rules.
    permission_level: $PermissionLevel
    approval_required: true
    executor_type: $ExecutorType
    enabled: true
    inputs:
      - prompt
    outputs:
      - result
    notes: Test helper only.
"@

    Set-Content -LiteralPath $Path -Value $Content -NoNewline
}

New-PrivateRegistryFixture -Path $TempPrivateRegistryLevel3 -ToolId "test_private_level3_tool" -PermissionLevel 3 -ExecutorType "filesystem"
New-PrivateRegistryFixture -Path $TempPrivateRegistryExternal -ToolId "test_private_external_tool" -PermissionLevel 2 -ExecutorType "llm_api"

$Cases = @(
    [pscustomobject]@{
        name = "valid open workshop lookup"
        params = @{
            ToolId = "browser_research"
            Workshop = "Open Workshop"
            WorkshopMode = "Open Workshop"
            DryRun = $true
            PrivateRegistryPath = $TempIgnoredPrivateRegistry
        }
        expect_status = "pass"
        expect_tool = "browser_research"
        expect_workshop = "Open Workshop"
        expect_workshop_mode = "Open Workshop"
        expect_allowed = $true
        expect_registry_path = $ExpectedGeneralRegistryPath
        expect_report_like = "Dry run only"
    }
    [pscustomobject]@{
        name = "valid private workshop lookup"
        params = @{
            ToolId = "restricted_dmz_writer"
            Workshop = "Private Workshop"
            WorkshopMode = "Private Workshop"
            DryRun = $true
            GeneralRegistryPath = $TempIgnoredGeneralRegistry
        }
        expect_status = "pass"
        expect_tool = "restricted_dmz_writer"
        expect_workshop = "Private Workshop"
        expect_workshop_mode = "Private Workshop"
        expect_allowed = $true
        expect_registry_path = $ExpectedPrivateRegistryPath
        expect_report_like = "Dry run only"
    }
    [pscustomobject]@{
        name = "invalid workshop mismatch"
        params = @{ ToolId = "browser_research"; Workshop = "Open Workshop"; WorkshopMode = "Private Workshop"; DryRun = $true }
        expect_status = "fail"
        expect_blocked_like = "does not match selected workshop mode"
    }
    [pscustomobject]@{
        name = "private level 3 blocked"
        params = @{
            ToolId = "test_private_level3_tool"
            Workshop = "Private Workshop"
            WorkshopMode = "Private Workshop"
            DryRun = $true
            PrivateRegistryPath = $TempPrivateRegistryLevel3
        }
        expect_status = "fail"
        expect_blocked_like = "permission_level 3"
    }
    [pscustomobject]@{
        name = "private external executor blocked"
        params = @{
            ToolId = "test_private_external_tool"
            Workshop = "Private Workshop"
            WorkshopMode = "Private Workshop"
            DryRun = $true
            PrivateRegistryPath = $TempPrivateRegistryExternal
        }
        expect_status = "fail"
        expect_blocked_like = "external executor_type"
    }
    [pscustomobject]@{
        name = "unknown tool id"
        params = @{ ToolId = "not-a-real-tool"; Workshop = "Open Workshop"; WorkshopMode = "Open Workshop"; DryRun = $true }
        expect_status = "fail"
        expect_blocked_like = "No tool matched tool id"
    }
)

$Results = @()
$Passed = 0
$Failed = 0

foreach ($Case in $Cases) {
    $Result = Invoke-RouterCase -Parameters $Case.params
    $Issues = New-Object System.Collections.Generic.List[string]

    if ([string]$Result.status -ne [string]$Case.expect_status) {
        $Issues.Add("Expected status '$($Case.expect_status)' but got '$($Result.status)'.")
    }

    if ($Case.PSObject.Properties.Name -contains "expect_tool" -and [string]$Result.selected_tool -ne [string]$Case.expect_tool) {
        $Issues.Add("Expected tool '$($Case.expect_tool)' but got '$($Result.selected_tool)'.")
    }

    if ($Case.PSObject.Properties.Name -contains "expect_workshop" -and [string]$Result.workshop -ne [string]$Case.expect_workshop) {
        $Issues.Add("Expected workshop '$($Case.expect_workshop)' but got '$([string]$Result.workshop)'.")
    }

    if ($Case.PSObject.Properties.Name -contains "expect_allowed" -and [bool]$Result.execution_allowed -ne [bool]$Case.expect_allowed) {
        $Issues.Add("Expected execution_allowed '$($Case.expect_allowed)' but got '$($Result.execution_allowed)'.")
    }

    if ($Case.PSObject.Properties.Name -contains "expect_workshop_mode" -and [string]$Result.workshop_mode -ne [string]$Case.expect_workshop_mode) {
        $Issues.Add("Expected workshop_mode '$($Case.expect_workshop_mode)' but got '$([string]$Result.workshop_mode)'.")
    }

    if ($Case.PSObject.Properties.Name -contains "expect_blocked_like" -and [string]$Result.blocked_reason -notmatch [regex]::Escape([string]$Case.expect_blocked_like)) {
        $Issues.Add("Expected blocked_reason to contain '$($Case.expect_blocked_like)' but got '$([string]$Result.blocked_reason)'.")
    }

    if ($Case.PSObject.Properties.Name -contains "expect_report_like" -and [string]$Result.report -notmatch [regex]::Escape([string]$Case.expect_report_like)) {
        $Issues.Add("Expected report to contain '$($Case.expect_report_like)' but got '$([string]$Result.report)'.")
    }

    if ($Case.PSObject.Properties.Name -contains "expect_registry_path" -and [string]$Result.registry_path -ne [string]$Case.expect_registry_path) {
        $Issues.Add("Expected registry_path '$($Case.expect_registry_path)' but got '$([string]$Result.registry_path)'.")
    }

    if ($Case.name -match "dry run" -and [bool]$Result.dry_run -ne $true) {
        $Issues.Add("Dry-run flag should be preserved.")
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
        status = [string]$Result.status
        selected_tool = [string]$Result.selected_tool
        workshop = [string]$Result.workshop
        workshop_mode = [string]$Result.workshop_mode
        registry_path = [string]$Result.registry_path
        execution_allowed = [bool]$Result.execution_allowed
        blocked_reason = [string]$Result.blocked_reason
        report = [string]$Result.report
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

Write-Host "[*] COOPER tool router tests"
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

Remove-Item -LiteralPath $TempPrivateRegistryLevel3 -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $TempPrivateRegistryExternal -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $TempIgnoredGeneralRegistry -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $TempIgnoredPrivateRegistry -Force -ErrorAction SilentlyContinue

if ($Report.status -ne "pass") {
    exit 1
}

exit 0
