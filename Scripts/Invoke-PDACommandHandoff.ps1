[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Text,

    [Parameter(Mandatory = $false)]
    [switch]$ConfirmDispatch,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [string]$Project = "AI Ecosystem"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$InterpreterScript = Join-Path $PSScriptRoot "PDA_CommandInterpreter.ps1"
$SubmitScript = Join-Path $PSScriptRoot "Submit-PDATask.ps1"
. (Join-Path $PSScriptRoot "PDA_TaskOntology.ps1")

if (-not (Test-Path -Path $InterpreterScript -PathType Leaf)) {
    throw "Command interpreter missing: $InterpreterScript"
}

if (-not (Test-Path -Path $SubmitScript -PathType Leaf)) {
    throw "Governed submitter missing: $SubmitScript"
}

function Get-PDAHandoffClassification {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $TaskTypes = @(Find-PDATaskTypes -Root $Root -Command $Command)
    if ($TaskTypes.Count -eq 0) {
        return "category_1"
    }

    $Supported = @($TaskTypes[0].supported_categories)
    if ($Supported -contains "category_1") {
        return "category_1"
    }

    return [string]$Supported[0]
}

$InterpreterRaw = & pwsh -NoProfile -File $InterpreterScript -Text $Text -AsJson
$Interpreter = $InterpreterRaw | ConvertFrom-Json

$RecommendedCommand = [string]$Interpreter.command
$DispatchCategory = ""
$DispatchReady = $false
$RequiresConfirmation = $false
$AmbiguityReason = [string]$Interpreter.reason
$DispatchPath = ""
$DispatchStatus = "not_dispatched"
$DispatchOutput = @()
$Eligibility = $null

if ($Interpreter.status -eq "mapped" -and -not [string]::IsNullOrWhiteSpace($RecommendedCommand)) {
    $DispatchCategory = Get-PDAHandoffClassification -Command $RecommendedCommand -Root $Root
    $Eligibility = Get-PDATaskWorkerEligibility -Root $Root -Command $RecommendedCommand -Classification $DispatchCategory -Approved $true
    $DispatchReady = @($Eligibility.eligible_workers).Count -gt 0
    $RequiresConfirmation = -not [bool]$ConfirmDispatch
    $AmbiguityReason = [string]$Interpreter.reason
}
elseif ($Interpreter.status -eq "ambiguous") {
    $AmbiguityReason = [string]$Interpreter.reason
}
else {
    $AmbiguityReason = [string]$Interpreter.reason
}

if ($ConfirmDispatch -and $Interpreter.status -eq "mapped" -and $DispatchReady) {
    $DispatchStatus = "submitted"
    $SubmitOutput = & pwsh -NoProfile -File $SubmitScript -Command $RecommendedCommand -Target $Text -Project $Project -Category $DispatchCategory -Approved:$true 2>&1
    $DispatchOutput = @($SubmitOutput | ForEach-Object { [string]$_ })

    if ($LASTEXITCODE -ne 0) {
        throw "Governed dispatch failed with exit code $LASTEXITCODE"
    }

    $SubmitLines = @($DispatchOutput | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $DispatchPath = [string]($SubmitLines | Select-Object -Last 1)
}
elseif ($ConfirmDispatch -and $Interpreter.status -ne "mapped") {
    $DispatchStatus = "blocked"
}

$Result = [pscustomobject]@{
    original_input      = $Text
    interpreter_status  = [string]$Interpreter.status
    recommended_command = $RecommendedCommand
    intent              = [string]$Interpreter.intent
    confidence          = [double]$Interpreter.confidence
    ambiguity_reason    = $AmbiguityReason
    requires_confirmation = $RequiresConfirmation
    dispatch_ready      = $DispatchReady
    dispatch_status     = $DispatchStatus
    dispatch_path       = $DispatchPath
    dispatch_category   = $DispatchCategory
    source_of_truth     = [string]$Interpreter.source_of_truth
    ontology_version    = [string]$Interpreter.ontology_version
    approved_via_gate   = ($DispatchStatus -eq "submitted")
    dispatch_output     = @($DispatchOutput)
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] PDA command handoff result:"
Write-Host ("Interpreter status   : {0}" -f $Result.interpreter_status)
Write-Host ("Recommended command  : {0}" -f $(if ($Result.recommended_command) { $Result.recommended_command } else { "(none)" }))
Write-Host ("Intent               : {0}" -f $(if ($Result.intent) { $Result.intent } else { "(none)" }))
Write-Host ("Confidence           : {0}" -f $Result.confidence)
Write-Host ("Requires confirmation : {0}" -f $Result.requires_confirmation)
Write-Host ("Dispatch ready       : {0}" -f $Result.dispatch_ready)
Write-Host ("Dispatch status      : {0}" -f $Result.dispatch_status)
if ($Result.dispatch_path) {
    Write-Host ("Dispatch path        : {0}" -f $Result.dispatch_path)
}
Write-Host ("Ambiguity reason     : {0}" -f $Result.ambiguity_reason)
