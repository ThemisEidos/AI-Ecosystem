param(
    [string]$StagingRoot = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Tasks\staging\n8n-reporter"
)

$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"
$Dispatcher = Join-Path $Root "Scripts\dispatch-pda-command.ps1"
$ProcessedRoot = Join-Path $Root "PDA-Tasks\staging\processed"
$FailedRoot = Join-Path $Root "PDA-Tasks\staging\failed"
$LogRoot = Join-Path $Root "PDA-Logs"

# Deprecated legacy queue paths are intentionally not used.
# This intake script only stages reporter tasks into the canonical PDA-Tasks flow.

New-Item -ItemType Directory -Force -Path $StagingRoot, $ProcessedRoot, $FailedRoot, $LogRoot | Out-Null

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogFile = Join-Path $LogRoot "$Timestamp-reporter-staged-intake.log"

function Write-Log {
    param([string]$Message)
    $Line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $Line | Add-Content -Path $LogFile -Encoding UTF8
    Write-Host $Line
}

Write-Log "Reporter staged-task intake started."
Write-Log "Staging root: $StagingRoot"

$StagedFiles = Get-ChildItem -Path $StagingRoot -Filter *.json -ErrorAction SilentlyContinue |
    Sort-Object CreationTime

foreach ($StagedFile in $StagedFiles) {
    $ProcessedPath = Join-Path $ProcessedRoot $StagedFile.Name
    $FailedPath = Join-Path $FailedRoot $StagedFile.Name

    try {
        $Task = Get-Content $StagedFile.FullName -Raw | ConvertFrom-Json

        if ($Task.command -ne "/reporter") {
            throw "Unsupported staged command: $($Task.command)"
        }

        if (-not $Task.PSObject.Properties['task_id'] -or [string]::IsNullOrWhiteSpace([string]$Task.task_id)) {
            $Task | Add-Member -NotePropertyName task_id -NotePropertyValue ([guid]::NewGuid().ToString()) -Force
            Write-Log "Generated missing task_id for staged file: $($StagedFile.Name) -> $($Task.task_id)"
            $Task | ConvertTo-Json -Depth 20 | Set-Content -Path $StagedFile.FullName -Encoding UTF8
        }

        if (-not $Task.PSObject.Properties['source_path'] -or [string]::IsNullOrWhiteSpace([string]$Task.source_path)) {
            throw "Missing required source_path for reporter task; staged file will not be dispatched."
        }

        Write-Log "Dispatching staged file: $($StagedFile.Name)"
        & pwsh -File $Dispatcher -TaskFile $StagedFile.FullName

        if ($LASTEXITCODE -ne 0) {
            throw "Dispatcher failed with exit code $LASTEXITCODE"
        }

        Move-Item -Path $StagedFile.FullName -Destination $ProcessedPath -Force
        Write-Log "Processed staged file moved to: $ProcessedPath"
    }
    catch {
        Write-Log "Failed staged file: $($StagedFile.Name)"
        Write-Log $_.Exception.Message

        if (Test-Path $StagedFile.FullName) {
            Move-Item -Path $StagedFile.FullName -Destination $FailedPath -Force
            Write-Log "Failed staged file moved to: $FailedPath"
        }
    }
}

Write-Log "Reporter staged-task intake complete."
