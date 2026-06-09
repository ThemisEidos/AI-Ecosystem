[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$Goal = "",

    [Parameter(Mandatory = $false)]
    [string]$RunId = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("pending", "approved", "rejected", "blocked")]
    [string]$ApprovalStatus = "",

    [Parameter(Mandatory = $false)]
    [string]$ResultText = "",

    [Parameter(Mandatory = $false)]
    [string]$ReviewText = "",

    [Parameter(Mandatory = $false)]
    [string]$StopReason = "",

    [Parameter(Mandatory = $false)]
    [int]$MaxIterations = 3,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$CreateScript = Join-Path $PSScriptRoot "New-PDAAgentRun.ps1"
$UpdateScript = Join-Path $PSScriptRoot "Update-PDAAgentRun.ps1"
$ParserPath = Join-Path $PSScriptRoot "PDA_OutputParsing.ps1"
if (Test-Path -LiteralPath $ParserPath -PathType Leaf) {
    . $ParserPath
}
if (-not (Test-Path -LiteralPath $CreateScript -PathType Leaf)) {
    throw "Agent run creation script missing: $CreateScript"
}
if (-not (Test-Path -LiteralPath $UpdateScript -PathType Leaf)) {
    throw "Agent run update script missing: $UpdateScript"
}

function Invoke-PDAJsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $Raw = & pwsh -NoProfile -File $Path @Arguments 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Script returned empty output: $Path"
    }

    return ConvertFrom-PDAMixedJson -Text $Text -SourceName $Path
}

$Operation = "inspect"
$Result = $null

if (-not [string]::IsNullOrWhiteSpace($Goal) -and [string]::IsNullOrWhiteSpace($RunId)) {
    $Operation = "create"
    $Result = Invoke-PDAJsonScript -Path $CreateScript -Arguments @("-Root", $Root, "-Goal", $Goal, "-MaxIterations", [string]$MaxIterations, "-AsJson")
    $RunId = [string]$Result.run_id
}

if (-not [string]::IsNullOrWhiteSpace($RunId) -and (
        -not [string]::IsNullOrWhiteSpace($ApprovalStatus) -or
        -not [string]::IsNullOrWhiteSpace($ResultText) -or
        -not [string]::IsNullOrWhiteSpace($ReviewText) -or
        -not [string]::IsNullOrWhiteSpace($StopReason)
    )) {
    $Operation = if ($Operation -eq "create") { "create_and_update" } else { "update" }
    $UpdateArgs = @("-Root", $Root, "-RunId", $RunId, "-MaxIterations", [string]$MaxIterations, "-AsJson")
    if (-not [string]::IsNullOrWhiteSpace($ApprovalStatus)) {
        $UpdateArgs += @("-ApprovalStatus", $ApprovalStatus)
    }
    if (-not [string]::IsNullOrWhiteSpace($ResultText)) {
        $UpdateArgs += @("-ResultText", $ResultText)
    }
    if (-not [string]::IsNullOrWhiteSpace($ReviewText)) {
        $UpdateArgs += @("-ReviewText", $ReviewText)
    }
    if (-not [string]::IsNullOrWhiteSpace($StopReason)) {
        $UpdateArgs += @("-StopReason", $StopReason)
    }
    $Result = Invoke-PDAJsonScript -Path $UpdateScript -Arguments $UpdateArgs
}

if (-not $Result) {
    $Result = [pscustomobject]@{
        status = "pass"
        operation = $Operation
        message = "No change requested."
    }
}
else {
    $Result | Add-Member -NotePropertyName operation -NotePropertyValue $Operation -Force
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 30
    return
}

Write-Host "[PDA AGENT LOOP]"
Write-Host ("Operation : {0}" -f $Result.operation)
if ($Result.PSObject.Properties.Name -contains "run_id") {
    Write-Host ("Run ID    : {0}" -f $Result.run_id)
}
if ($Result.PSObject.Properties.Name -contains "run" -and $Result.run) {
    Write-Host ("Status    : {0}" -f $Result.run.status)
    Write-Host ("Next      : {0}" -f $Result.run.next_action)
}
