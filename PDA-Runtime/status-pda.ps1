$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$CommandScript = Join-Path $RepoRoot "Scripts\AIEcosystem.Commands.ps1"

. $CommandScript

Invoke-AIECStatus -RepoRoot $RepoRoot
