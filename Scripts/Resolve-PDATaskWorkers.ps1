[CmdletBinding(DefaultParameterSetName = "ByValues")]
param(
    [Parameter(Mandatory = $false, ParameterSetName = "ByPath")]
    [string]$TaskPath = "",

    [Parameter(Mandatory = $false, ParameterSetName = "ByValues")]
    [string]$Command = "",

    [Parameter(Mandatory = $false, ParameterSetName = "ByValues")]
    [ValidateSet("category_1", "category_2")]
    [string]$Classification = "",

    [Parameter(Mandatory = $false, ParameterSetName = "ByValues")]
    [bool]$Approved = $false,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "PDA_TaskOntology.ps1")

$Task = $null
if ($PSCmdlet.ParameterSetName -eq "ByPath") {
    if (-not (Test-Path -Path $TaskPath -PathType Leaf)) {
        throw "Task path not found: $TaskPath"
    }

    $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
}

$ResolveArgs = @{
    Root     = $Root
    Approved = $Approved
}
if ($null -ne $Task) { $ResolveArgs.Task = $Task }
if (-not [string]::IsNullOrWhiteSpace($Command)) { $ResolveArgs.Command = $Command }
if (-not [string]::IsNullOrWhiteSpace($Classification)) { $ResolveArgs.Classification = $Classification }

$Result = Get-PDATaskWorkerEligibility @ResolveArgs

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] Task routing result:"
Write-Host ("Status            : {0}" -f $Result.status)
Write-Host ("Command           : {0}" -f $Result.command)
Write-Host ("Classification    : {0}" -f $Result.classification)
Write-Host ("Requires approval  : {0}" -f $Result.requires_approval)
Write-Host ("Eligible workers   : {0}" -f (@($Result.eligible_workers).Count))
Write-Host ("Blocked workers    : {0}" -f (@($Result.blocked_workers).Count))

if (@($Result.eligible_workers).Count -gt 0) {
    Write-Host ""
    Write-Host "Eligible worker details:"
    $Result.eligible_workers |
        Select-Object worker_name, command, routing_surface, status |
        Format-Table -AutoSize
}
