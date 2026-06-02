param(
    [Parameter(Mandatory=$true)]
    [string]$Command,

    [Parameter(Mandatory=$true)]
    [string]$Target,

    [string]$Project = "AI Ecosystem",

    [string]$Category = "category_1",

    [bool]$Approved = $true
)

$PendingPath = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Tasks\pending"

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$SafeCommand = $Command.Replace("/", "").Replace("\", "").Replace(" ", "-")

$TaskFile = Join-Path $PendingPath "$Timestamp-$SafeCommand.json"

$Task = [ordered]@{
    command  = $Command
    project  = $Project
    target   = $Target
    category = $Category
    approved = $Approved
}

$Task | ConvertTo-Json -Depth 5 | Set-Content $TaskFile -Encoding UTF8

Write-Host ""
Write-Host "PDA task submitted:"
Write-Host $TaskFile
