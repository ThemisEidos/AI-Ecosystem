[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow,

    [Parameter(Mandatory = $false)]
    [switch]$SkipOperatorConsole
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$InterpreterScript = Join-Path $PSScriptRoot "PDA_CommandInterpreter.ps1"
$OntologyPath = Join-Path $PSScriptRoot "PDA_TaskOntology.json"

if (-not (Test-Path -Path $OntologyPath -PathType Leaf)) {
    throw "Ontology file missing: $OntologyPath"
}

$Ontology = Get-Content -Path $OntologyPath -Raw | ConvertFrom-Json
$OntologyByCommand = @{}
$OntologyByIntent = @{}
foreach ($Intent in @($Ontology.task_intents)) {
    if ($Intent.PSObject.Properties.Name -contains "command" -and -not [string]::IsNullOrWhiteSpace([string]$Intent.command)) {
        $OntologyByCommand[[string]$Intent.command] = $Intent
    }

    if ($Intent.PSObject.Properties.Name -contains "intent" -and -not [string]::IsNullOrWhiteSpace([string]$Intent.intent)) {
        $OntologyByIntent[[string]$Intent.intent] = $Intent
    }
}

if (-not (Test-Path -Path $InterpreterScript -PathType Leaf)) {
    throw "Command interpreter missing: $InterpreterScript"
}

$TestCases = @(
    [pscustomobject]@{
        name             = "review findings"
        input            = "review my latest findings"
        expected_status  = "mapped"
        expected_intent  = "review"
        expected_task    = "review"
        expected_command = "/review"
        source_check     = $true
    }
    [pscustomobject]@{
        name             = "draft summary"
        input            = "draft an executive summary"
        expected_status  = "mapped"
        expected_intent  = "report_generation"
        expected_task    = "reporting"
        expected_command = "/reporter"
        source_check     = $true
    }
    [pscustomobject]@{
        name             = "project analysis"
        input            = "analyze this project"
        expected_status  = "mapped"
        expected_intent  = "planning"
        expected_task    = "planning"
        expected_command = "/planner"
        source_check     = $true
    }
    [pscustomobject]@{
        name             = "operator status"
        input            = "/status"
        expected_status  = "mapped"
        expected_intent  = "operator_status"
        expected_task    = "operator_status"
        expected_command = "/status"
        source_check     = $true
    }
    [pscustomobject]@{
        name             = "operator tasks"
        input            = "/tasks"
        expected_status  = "mapped"
        expected_intent  = "operator_tasks"
        expected_task    = "operator_tasks"
        expected_command = "/tasks"
        source_check     = $true
    }
    [pscustomobject]@{
        name             = "operator approvals"
        input            = "/approvals"
        expected_status  = "mapped"
        expected_intent  = "operator_approvals"
        expected_task    = "operator_approvals"
        expected_command = "/approvals"
        source_check     = $true
    }
    [pscustomobject]@{
        name             = "operator workers"
        input            = "/workers"
        expected_status  = "mapped"
        expected_intent  = "operator_workers"
        expected_task    = "operator_workers"
        expected_command = "/workers"
        source_check     = $true
    }
    [pscustomobject]@{
        name             = "operator reports"
        input            = "/reports"
        expected_status  = "mapped"
        expected_intent  = "operator_reports"
        expected_task    = "operator_reports"
        expected_command = "/reports"
        source_check     = $true
    }
    [pscustomobject]@{
        name             = "operator memory"
        input            = "/memory"
        expected_status  = "mapped"
        expected_intent  = "operator_memory"
        expected_task    = "operator_memory"
        expected_command = "/memory"
        source_check     = $true
    }
    [pscustomobject]@{
        name             = "operator help"
        input            = "/help"
        expected_status  = "mapped"
        expected_intent  = "operator_help"
        expected_task    = "operator_help"
        expected_command = "/help"
        source_check     = $true
    }
    [pscustomobject]@{
        name             = "research task"
        input            = "create a test research task"
        expected_status  = "mapped"
        expected_intent  = "research_synthesis"
        expected_task    = "research"
        expected_command = "/research"
        source_check     = $true
    }
    [pscustomobject]@{
        name             = "workflow run"
        input            = "run the workflow"
        expected_status  = "mapped"
        expected_intent  = "execution_manifest"
        expected_task    = "execution"
        expected_command = "/execute"
        source_check     = $true
    }
    [pscustomobject]@{
        name             = "ambiguous request"
        input            = "review and analyze this project"
        expected_status  = "ambiguous"
        expected_intent  = ""
        expected_task    = ""
        expected_command = ""
        source_check     = $false
    }
    [pscustomobject]@{
        name             = "unknown request"
        input            = "tell me something nice"
        expected_status  = "unknown"
        expected_intent  = ""
        expected_task    = ""
        expected_command = ""
        source_check     = $false
    }
)

if ($SkipOperatorConsole) {
    $TestCases = @($TestCases | Where-Object { [string]$_.name -notlike "operator *" })
}

$Results = @()
$Passed = 0
$Failed = 0
$MappedCount = 0
$AmbiguousCount = 0
$UnknownCount = 0

foreach ($Case in $TestCases) {
    $CasePassed = $true
    $CaseIssues = New-Object System.Collections.Generic.List[string]

    try {
        $Raw = & pwsh -NoProfile -File $InterpreterScript -Text $Case.input -AsJson
        $Result = $Raw | ConvertFrom-Json
        $ResultCommand = [string]$Result.command
        $ResultIntent = [string]$Result.intent
        $ResultTask = [string]$Result.task_type
        $ResultStatus = [string]$Result.status

        if ($ResultStatus -ne $Case.expected_status) {
            $CasePassed = $false
            $CaseIssues.Add("Expected status '$($Case.expected_status)' but got '$ResultStatus'.")
        }

        if ($Case.expected_intent -and $ResultIntent -ne $Case.expected_intent) {
            $CasePassed = $false
            $CaseIssues.Add("Expected intent '$($Case.expected_intent)' but got '$ResultIntent'.")
        }

        if ($Case.expected_task -and $ResultTask -ne $Case.expected_task) {
            $CasePassed = $false
            $CaseIssues.Add("Expected task type '$($Case.expected_task)' but got '$ResultTask'.")
        }

        if ($Case.expected_command -and $ResultCommand -ne $Case.expected_command) {
            $CasePassed = $false
            $CaseIssues.Add("Expected command '$($Case.expected_command)' but got '$ResultCommand'.")
        }

        if ($Case.source_check) {
            $OntologyMatch = $null
            if ($OntologyByCommand.ContainsKey($ResultCommand)) {
                $OntologyMatch = $OntologyByCommand[$ResultCommand]
            }

            if ($null -eq $OntologyMatch) {
                $CasePassed = $false
                $CaseIssues.Add("Returned command '$ResultCommand' was not found in PDA_TaskOntology.json.")
            }

            $Resolved = $null
            if ($OntologyByIntent.ContainsKey($ResultIntent)) {
                $Resolved = $OntologyByIntent[$ResultIntent]
            }

            if ($null -eq $Resolved) {
                $CasePassed = $false
                $CaseIssues.Add("Returned intent '$ResultIntent' was not found in PDA_TaskOntology.json.")
            }
            elseif ([string]$Resolved.command -ne $ResultCommand) {
                $CasePassed = $false
                $CaseIssues.Add("Ontology lookup returned '$($Resolved.command)' instead of '$ResultCommand'.")
            }
        }

        if ($Case.expected_status -eq "ambiguous") {
            $RecommendedCommands = @($Result.recommendations | ForEach-Object { [string]$_.command } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if (-not ($RecommendedCommands -contains "/review" -and $RecommendedCommands -contains "/planner")) {
                $CasePassed = $false
                $CaseIssues.Add("Ambiguous request did not recommend both /review and /planner.")
            }

            if (-not [string]::IsNullOrWhiteSpace($ResultCommand)) {
                $CasePassed = $false
                $CaseIssues.Add("Ambiguous request should not produce an executable command.")
            }
        }

        if ($Case.expected_status -eq "unknown") {
            if (-not [string]::IsNullOrWhiteSpace($ResultCommand)) {
                $CasePassed = $false
                $CaseIssues.Add("Unknown request should not produce an executable command.")
            }

            if (@($Result.recommendations).Count -eq 0) {
                $CasePassed = $false
                $CaseIssues.Add("Unknown request should return a recommendation to refine the request.")
            }
        }

        $Results += [pscustomobject]@{
            name      = $Case.name
            passed    = $CasePassed
            status    = $ResultStatus
            command   = $ResultCommand
            intent    = $ResultIntent
            task_type = $ResultTask
            reason    = [string]$Result.reason
            issues    = @($CaseIssues)
        }
    }
    catch {
        $CasePassed = $false
        $CaseIssues.Add($_.Exception.Message)
        $Results += [pscustomobject]@{
            name      = $Case.name
            passed    = $false
            status    = "error"
            command   = ""
            intent    = ""
            task_type = ""
            reason    = $_.Exception.Message
            issues    = @($CaseIssues)
        }
    }

    if ($CasePassed) {
        $Passed++
    }
    else {
        $Failed++
    }

    if ($ResultStatus -eq "mapped") {
        $MappedCount++
    }
    elseif ($ResultStatus -eq "ambiguous") {
        $AmbiguousCount++
    }
    elseif ($ResultStatus -eq "unknown") {
        $UnknownCount++
    }
}

$Total = $TestCases.Count
$Accuracy = if ($Total -gt 0) { [math]::Round((($Passed / $Total) * 100), 2) } else { 0 }
$Report = [pscustomobject]@{
    status           = if ($Failed -eq 0) { "pass" } else { "fail" }
    test_case_count  = $Total
    passed_count     = $Passed
    failed_count     = $Failed
    accuracy_percent = $Accuracy
    mapped_count     = $MappedCount
    ambiguous_count  = $AmbiguousCount
    unknown_count    = $UnknownCount
    source_of_truth  = "Scripts/PDA_TaskOntology.json"
    ontology_version = [string]$Ontology.ontology_version
    results          = @($Results)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA command interpreter validation failed."
    }
    return
}

Write-Host "[*] PDA command interpreter tests"
Write-Host ("Test cases       : {0}" -f $Report.test_case_count)
Write-Host ("Passed           : {0}" -f $Report.passed_count)
Write-Host ("Failed           : {0}" -f $Report.failed_count)
Write-Host ("Accuracy         : {0}%" -f $Report.accuracy_percent)
Write-Host ("Mapped           : {0}" -f $Report.mapped_count)
Write-Host ("Ambiguous        : {0}" -f $Report.ambiguous_count)
Write-Host ("Unknown          : {0}" -f $Report.unknown_count)
Write-Host ("Source of truth  : {0}" -f $Report.source_of_truth)
Write-Host ("Ontology version : {0}" -f $Report.ontology_version)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA command interpreter validation failed."
}
