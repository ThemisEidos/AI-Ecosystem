[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Command = "",

    [Parameter(Mandatory = $false)]
    [string]$Intent = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("category_1", "category_2")]
    [string]$Classification = "",

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_TaskOntology.ps1")

$QueryArgs = @{
    Root = $Root
}
if (-not [string]::IsNullOrWhiteSpace($Command)) { $QueryArgs.Command = $Command }
if (-not [string]::IsNullOrWhiteSpace($Intent)) { $QueryArgs.Intent = $Intent }
if (-not [string]::IsNullOrWhiteSpace($Classification)) { $QueryArgs.Classification = $Classification }

$Results = @(Find-PDATaskTypes @QueryArgs)

if ($AsJson) {
    $Results | ConvertTo-Json -Depth 20
    return
}

if ($Results.Count -eq 0) {
    Write-Host "No task types matched the query."
    return
}

Write-Host "[OK] Matched task types:"
$Results |
    Select-Object task_type, intent, command, sensitivity_category, supported_categories |
    Format-Table -AutoSize
