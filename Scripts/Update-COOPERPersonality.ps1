[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$ProfilePath,

    [Parameter(Mandatory = $true)]
    [string]$Setting,

    [Parameter(Mandatory = $true)]
    [object]$Value,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [Alias("AsJson")]
    [switch]$OutputJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"
$SetScript = Join-Path $PSScriptRoot "Set-COOPERPersonality.ps1"

if (-not (Test-Path -LiteralPath $SetScript -PathType Leaf)) {
    throw "Set-COOPERPersonality.ps1 is missing: $SetScript"
}

$SetArgs = @("-Root", $Root)
if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) {
    $SetArgs += @("-ProfilePath", $ProfilePath)
}

switch ([string]$Setting.ToLowerInvariant()) {
    "humor" { $SetArgs += @("-Humor", $Value) }
    "sarcasm" { $SetArgs += @("-Sarcasm", $Value) }
    "professionalism" { $SetArgs += @("-Professionalism", $Value) }
    "brevity" { $SetArgs += @("-Brevity", $Value) }
    "initiative" { $SetArgs += @("-Initiative", $Value) }
    "risk" { $SetArgs += @("-RiskAwareness", $Value) }
    "risk_awareness" { $SetArgs += @("-RiskAwareness", $Value) }
    "profile" { $SetArgs += @("-Profile", [string]$Value) }
    default { throw "Unsupported COOPER setting '$Setting'. Use humor, sarcasm, professionalism, brevity, initiative, risk, or profile." }
}

if ($DryRun) {
    $SetArgs += "-DryRun"
}
if ($OutputJson) {
    $SetArgs += "-AsJson"
}
if ($NoThrow) {
    $SetArgs += "-NoThrow"
}

& pwsh -NoProfile -File $SetScript @SetArgs
