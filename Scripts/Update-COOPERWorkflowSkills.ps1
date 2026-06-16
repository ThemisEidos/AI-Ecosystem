[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkflowId,

    [Parameter(Mandatory = $false)]
    [object]$ReviewResult = $null,

    [Parameter(Mandatory = $false)]
    [string]$ExampleRequest = "",

    [Parameter(Mandatory = $false)]
    [string]$ExampleOutput = "",

    [Parameter(Mandatory = $false)]
    [string]$SkillName = "",

    [Parameter(Mandatory = $false)]
    [string]$StatePath = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = Join-Path $Root "State\COOPER_Skills.json"
}

function New-COOPERSkillsState {
    return [ordered]@{
        skills = @()
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
        source_of_truth = "State/COOPER_Skills.json"
    }
}

function Read-COOPERSkillsState {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return New-COOPERSkillsState
    }

    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        return New-COOPERSkillsState
    }
}

function ConvertTo-COOPERSkillsList {
    param([Parameter(Mandatory = $false)]$Value)
    if ($null -eq $Value) {
        return @()
    }
    return @(
        @($Value) |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { [string]$_ }
    )
}

$SkillsState = Read-COOPERSkillsState -Path $StatePath
$Now = (Get-Date).ToUniversalTime().ToString("o")
$ReviewStatus = ""
$ReviewPassed = $false

if ($ReviewResult) {
    if ($ReviewResult.PSObject.Properties.Name -contains "status") {
        $ReviewStatus = [string]$ReviewResult.status
    }
    if ($ReviewResult.PSObject.Properties.Name -contains "review_passed") {
        $ReviewPassed = [bool]$ReviewResult.review_passed
    }
    elseif ($ReviewStatus -eq "pass") {
        $ReviewPassed = $true
    }
}

if (-not $ReviewPassed) {
    $SkillsState.updated_at = $Now
    $Parent = Split-Path -Parent $StatePath
    if (-not (Test-Path -LiteralPath $Parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Parent | Out-Null
    }
    $SkillsState | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $StatePath -Encoding UTF8
    return [pscustomobject]@{
        status = if ($ReviewStatus) { $ReviewStatus } else { "fail" }
        workflow_id = $WorkflowId
        state_path = $StatePath
        promoted = $false
        source_of_truth = "Scripts/Update-COOPERWorkflowSkills.ps1"
    }
}

$Skills = @($SkillsState.skills)
$Existing = @($Skills | Where-Object { [string]$_.workflow_id -eq $WorkflowId } | Select-Object -First 1)
if ($Existing.Count -gt 0) {
    $Entry = $Existing[0]
}
else {
    $Entry = [pscustomobject]@{
        workflow_id = $WorkflowId
        skill_name = if ([string]::IsNullOrWhiteSpace($SkillName)) { $WorkflowId } else { $SkillName }
        status = "operational"
        successful_run_count = 0
        last_success = ""
        example_request = ""
        example_output = ""
    }
    $Skills += $Entry
}

$Entry.status = "operational"
$Entry.successful_run_count = [int]$Entry.successful_run_count + 1
$Entry.last_success = $Now
if (-not [string]::IsNullOrWhiteSpace($SkillName)) {
    $Entry.skill_name = $SkillName
}
if (-not [string]::IsNullOrWhiteSpace($ExampleRequest)) {
    $Entry.example_request = $ExampleRequest
}
if (-not [string]::IsNullOrWhiteSpace($ExampleOutput)) {
    $Entry.example_output = $ExampleOutput
}

$SkillsState.skills = @($Skills | ForEach-Object { $_ })
$SkillsState.updated_at = $Now

$Parent = Split-Path -Parent $StatePath
if (-not (Test-Path -LiteralPath $Parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null
}

$SkillsState | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $StatePath -Encoding UTF8

return [pscustomobject]@{
    status = "pass"
    workflow_id = $WorkflowId
    state_path = $StatePath
    promoted = $true
    skill = $Entry
    source_of_truth = "Scripts/Update-COOPERWorkflowSkills.ps1"
}
