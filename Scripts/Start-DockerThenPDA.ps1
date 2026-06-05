$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$RuntimeScript = Join-Path $RepoRoot "PDA-Runtime\launch-pda.ps1"

& $RuntimeScript
exit $LASTEXITCODE
