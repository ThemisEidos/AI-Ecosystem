$ErrorActionPreference = "Stop"

Write-Host "[*] PDA Git Safety Check"

$BlockedPatterns = @(
    "PDA-Tasks/",
    "PDA-Logs/",
    "Tasks/",
    "Agent Findings/",
    "n8n Workflow/Watch Folder/",
    ".env",
    "n8n-api-key.txt",
    "insert_api_key.sql",
    ".sqlite",
    ".sqlite-wal",
    ".sqlite-shm",
    "secret",
    "credential",
    "token",
    "apikey",
    "api-key",
    "Class-2",
    "Restricted",
    "Sensitive",
    "VeraCrypt"
)

$Status = git status --short
$Unsafe = @()

foreach ($line in $Status) {
    foreach ($pattern in $BlockedPatterns) {
        if ($line -like "*$pattern*") {
            $Unsafe += $line
        }
    }
}

if ($Unsafe.Count -gt 0) {
    Write-Host "[WARN] Potential unsafe files detected:" -ForegroundColor Yellow
    $Unsafe | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    throw "Git safety check failed. Review staged/untracked files before committing."
}

Write-Host "[OK] No obvious unsafe Git-tracked files detected."
git status --short
