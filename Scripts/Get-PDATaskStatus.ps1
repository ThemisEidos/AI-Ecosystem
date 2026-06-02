$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"

$Folders = @("pending","running","completed","failed","results")

# Deprecated legacy queue path:
# Tasks\queued remains visible only for migration checks.
$LegacyFolders = @("queued","running","completed","failed")

foreach ($Folder in $Folders) {
    $Path = Join-Path $Root "PDA-Tasks\$Folder"
    $Count = @(Get-ChildItem -Path $Path -Filter *.json -ErrorAction SilentlyContinue).Count
    "{0} : {1}" -f $Folder, $Count
}

Write-Host ""
Write-Host "Legacy queue paths:"
foreach ($Folder in $LegacyFolders) {
    $Path = Join-Path $Root "Tasks\$Folder"
    if (Test-Path $Path) {
        $Count = @(Get-ChildItem -Path $Path -Filter *.json -ErrorAction SilentlyContinue).Count
        "{0} : {1}" -f $Folder, $Count
    }
}
