[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Command = "",

    [Parameter(Mandatory = $false)]
    [string]$Intent = "",

    [Parameter(Mandatory = $false)]
    [string]$AllowedWorker = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("category_1", "category_2")]
    [string]$Classification = "",

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_Retrieval.ps1")

$QueryArgs = @{
    Root = $Root
}
if (-not [string]::IsNullOrWhiteSpace($Command)) { $QueryArgs.Command = $Command }
if (-not [string]::IsNullOrWhiteSpace($Intent)) { $QueryArgs.Intent = $Intent }
if (-not [string]::IsNullOrWhiteSpace($AllowedWorker)) { $QueryArgs.AllowedWorker = $AllowedWorker }
if (-not [string]::IsNullOrWhiteSpace($Classification)) { $QueryArgs.Classification = $Classification }

$Results = @(Get-PDATaskOntologyEntry @QueryArgs)
$Report = [pscustomobject]@{
    count = $Results.Count
    filters = [pscustomobject]@{
        command = $Command
        intent = $Intent
        allowed_worker = $AllowedWorker
        classification = $Classification
    }
    entries = $Results
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] Ontology retrieval results:"
Write-Host ("Count   : {0}" -f $Results.Count)
if ($Results.Count -eq 0) {
    Write-Host "No ontology entries matched the query."
    return
}

$Results |
    Select-Object task_type, intent, command, sensitivity_category, supported_categories, allowed_workers |
    Format-Table -AutoSize
