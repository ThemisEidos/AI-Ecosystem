param(
    [switch]$NoOpen
)

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$CommandScript = Join-Path $RepoRoot "Scripts\AIEcosystem.Commands.ps1"

. $CommandScript

$ExitCode = Invoke-AIECDashboard -RepoRoot $RepoRoot -NoOpen:$NoOpen
exit $ExitCode
