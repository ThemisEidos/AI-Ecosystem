$ProjectRoot = Split-Path $PSScriptRoot -Parent
$OutputRoot = Join-Path $ProjectRoot "PDA-Outputs"

$IndexPath = Join-Path $ProjectRoot "PDA-Obsidian-Vault\07_Automations\PDA Command System\Artifact Index.md"

$Artifacts = Get-ChildItem $OutputRoot -Recurse -Filter *.md | Sort-Object LastWriteTime -Descending

$Lines = @()
$Lines += "# PDA Artifact Index"
$Lines += ""
$Lines += "Last Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$Lines += ""
$Lines += "| Timestamp | Agent | File | Path |"
$Lines += "|---|---|---|---|"

foreach ($Artifact in $Artifacts) {
    $Agent = Split-Path $Artifact.DirectoryName -Leaf
    if ($Agent -eq "PDA-Outputs") { $Agent = "general" }

    $Lines += "| $($Artifact.LastWriteTime) | $Agent | $($Artifact.Name) | $($Artifact.FullName) |"
}

$Lines | Set-Content $IndexPath -Encoding UTF8

Write-Host "Artifact index updated:"
Write-Host $IndexPath
