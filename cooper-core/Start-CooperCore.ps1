[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$Port = 8000,

    [Parameter(Mandatory = $false)]
    [ValidateSet("open", "private")]
    [string]$Workshop = "private"
)

# Start-CooperCore.ps1
# Launches the COOPER Core FastAPI server as a DETACHED background process with
# --reload. Frees the port first (idempotent restart). Sets WORKSHOP env var so
# the correct backend is selected. Output to cooper-core.out.log / .err.log.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# Free the port if something is already bound.
Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }

$uvicorn = Join-Path $PSScriptRoot ".venv-win\Scripts\uvicorn.exe"
if (-not (Test-Path $uvicorn)) {
    throw "uvicorn not found at $uvicorn - run: python -m venv .venv-win && .venv-win\Scripts\pip install -r requirements.txt"
}

# Set WORKSHOP in this process so the child inherits it.
$logOut = Join-Path $PSScriptRoot "cooper-core.out.log"
$logErr = Join-Path $PSScriptRoot "cooper-core.err.log"

# Use quoted set syntax to avoid trailing-space in the env var value.
$cmdLine = "/c set `"WORKSHOP=$Workshop`" && `"$uvicorn`" main:app --host 0.0.0.0 --port $Port --reload >`"$logOut`" 2>`"$logErr`""

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName        = "cmd.exe"
$psi.Arguments       = $cmdLine
$psi.WorkingDirectory = $PSScriptRoot
$psi.UseShellExecute  = $false
$psi.CreateNoWindow   = $true
[System.Diagnostics.Process]::Start($psi) | Out-Null

Start-Sleep -Seconds 3
Write-Output "COOPER Core started (workshop=$Workshop) on port $Port. Logs: cooper-core.out.log / cooper-core.err.log"
