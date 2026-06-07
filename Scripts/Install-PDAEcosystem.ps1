[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow,

    [Parameter(Mandatory = $false)]
    [switch]$CreateLocalEnv,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ComposePath = Join-Path $Root "PDA-Runtime\docker-compose.yml"
$EnvExamplePath = Join-Path $Root "PDA-Runtime\.env.example"
$LocalEnvPath = Join-Path $Root "PDA-Runtime\.env"
$LiteLLMEnvPath = Join-Path $Root "litellm\.env.local"

$RequiredFolders = @(
    "PDA-Runtime",
    "PDA-Runtime\configs",
    "PDA-Runtime\data",
    "PDA-Runtime\logs",
    "PDA-Backups",
    "PDA-Backups\notebooklm",
    "PDA-Backups\build-runner",
    "PDA-Backups\build-runner\logs",
    "PDA-Backups\build-runner\reports",
    "Roadmap\work-packets",
    "Roadmap\codex-prompts"
)

function New-PDAInstallRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $false)][string]$Detail = "",
        [Parameter(Mandatory = $false)][string]$Value = ""
    )

    return [pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
        value = $Value
    }
}

function Get-PDACommandInfo {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Probe,
        [string]$FallbackPath = ""
    )

    $Record = [ordered]@{
        name = $Name
        status = "missing"
        path = ""
        version = ""
        detail = ""
    }

    try {
        $Value = & $Probe
        if (-not [string]::IsNullOrWhiteSpace([string]$Value)) {
            $Record.status = "ok"
            $Record.version = [string]$Value
        }
    }
    catch {
        $Record.detail = $_.Exception.Message
    }

    if ($Record.status -ne "ok" -and -not [string]::IsNullOrWhiteSpace($FallbackPath) -and (Test-Path -LiteralPath $FallbackPath -PathType Leaf)) {
        $Record.status = "found_by_path"
        $Record.path = $FallbackPath
        try {
            $Version = & $FallbackPath --version 2>$null
            if ($Version) {
                $Record.version = [string]($Version -join " ").Trim()
            }
        }
        catch {
            if ([string]::IsNullOrWhiteSpace($Record.detail)) {
                $Record.detail = $_.Exception.Message
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($Record.path)) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($Command) {
            $Record.path = [string]$Command.Source
        }
    }

    return [pscustomobject]$Record
}

function Test-PDAPathExists {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ((Test-Path -LiteralPath $Path -PathType Container) -or (Test-Path -LiteralPath $Path -PathType Leaf))
}

function Ensure-PDADirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-PDAPathExists -Path $Path) {
        return [pscustomobject]@{ path = $Path; status = "present"; action = "" }
    }

    if ($DryRun) {
        return [pscustomobject]@{ path = $Path; status = "planned"; action = "create_directory" }
    }

    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    return [pscustomobject]@{ path = $Path; status = "created"; action = "create_directory" }
}

function Copy-PDAEnvExampleIfRequested {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    if (-not $CreateLocalEnv) {
        return [pscustomobject]@{
            path = $DestinationPath
            status = if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) { "present" } else { "missing" }
            action = if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) { "" } else { "copy_source_example" }
            detail = "Use -CreateLocalEnv to copy the example locally if you want a starter file."
        }
    }

    if (Test-Path -LiteralPath $DestinationPath -PathType Leaf -and -not $Force) {
        return [pscustomobject]@{
            path = $DestinationPath
            status = "exists"
            action = ""
            detail = "Local env file already exists. Re-run with -Force to overwrite it."
        }
    }

    if ($DryRun) {
        return [pscustomobject]@{
            path = $DestinationPath
            status = "planned"
            action = "copy_source_example"
            detail = "Dry run only."
        }
    }

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        return [pscustomobject]@{
            path = $DestinationPath
            status = "missing"
            action = ""
            detail = "Source template not found: $SourcePath"
        }
    }

    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force:$Force
    return [pscustomobject]@{
        path = $DestinationPath
        status = "created"
        action = "copy_source_example"
        detail = "Copied from example template."
    }
}

$Tools = @()
$Tools += Get-PDACommandInfo -Name "pwsh" -Probe { (pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()').Trim() }
$Tools += Get-PDACommandInfo -Name "git" -Probe { (git --version).Trim() }
$Tools += Get-PDACommandInfo -Name "docker" -Probe { (docker --version).Trim() }
$Tools += Get-PDACommandInfo -Name "python" -Probe { (python --version 2>&1).Trim() }
$Tools += Get-PDACommandInfo -Name "fabric" -Probe {
    if (Get-Command fabric -ErrorAction SilentlyContinue) {
        (fabric --version).Trim()
    }
} -FallbackPath (Join-Path $env:USERPROFILE '.local\bin\fabric.exe')
$Tools += Get-PDACommandInfo -Name "ollama" -Probe {
    if (Get-Command ollama -ErrorAction SilentlyContinue) {
        (ollama --version).Trim()
    }
}
$Tools += Get-PDACommandInfo -Name "obsidian" -Probe {
    $Candidates = @(
        (Join-Path $env:LocalAppData 'Programs\Obsidian\Obsidian.exe'),
        (Join-Path $env:ProgramFiles 'Obsidian\Obsidian.exe')
    )
    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) { return $Candidate }
    }
}

$Folders = @()
foreach ($Folder in $RequiredFolders) {
    $Folders += Ensure-PDADirectory -Path (Join-Path $Root $Folder)
}

$EnvCopy = Copy-PDAEnvExampleIfRequested -SourcePath $EnvExamplePath -DestinationPath $LocalEnvPath

$MissingTools = @($Tools | Where-Object { $_.status -eq "missing" })
$DockerAvailable = $false
try {
    $DockerVersion = (docker version --format '{{.Server.Version}}' 2>$null | Select-Object -First 1)
    $DockerAvailable = -not [string]::IsNullOrWhiteSpace([string]$DockerVersion)
}
catch {
    $DockerAvailable = $false
}

$Issues = New-Object System.Collections.Generic.List[string]
if (-not $DockerAvailable) { $Issues.Add("Docker is not available or the daemon is not running.") }
if (-not (Test-Path -LiteralPath $ComposePath -PathType Leaf)) { $Issues.Add("docker-compose.yml is missing.") }
if (-not (Test-Path -LiteralPath $EnvExamplePath -PathType Leaf)) { $Issues.Add("PDA-Runtime/.env.example is missing.") }
if ($Tools | Where-Object { $_.name -eq "fabric" -and $_.status -eq "missing" }) { $Issues.Add("Fabric CLI is not on PATH and no fallback executable was found.") }
if ($EnvCopy.status -eq "missing" -and $CreateLocalEnv) { $Issues.Add($EnvCopy.detail) }
if ($EnvCopy.status -eq "exists" -and $CreateLocalEnv -and -not $Force) { $Issues.Add($EnvCopy.detail) }

$ActionItems = @()
foreach ($Folder in $Folders) {
    if ($Folder.action) {
        $ActionItems += $Folder
    }
}
if ($EnvCopy.action) {
    $ActionItems += $EnvCopy
}

$Status = if ($Issues.Count -eq 0) { "pass" } elseif ($DockerAvailable -and (Test-Path -LiteralPath $ComposePath -PathType Leaf) -and (Test-Path -LiteralPath $EnvExamplePath -PathType Leaf)) { "warn" } else { "fail" }

$Result = [pscustomobject]@{
    status = $Status
    dry_run = [bool]$DryRun
    root = $Root
    compose_path = $ComposePath
    env_example_path = $EnvExamplePath
    local_env_path = $LocalEnvPath
    tools = @($Tools)
    missing_tool_count = $MissingTools.Count
    docker_available = $DockerAvailable
    folders = @($Folders)
    env_copy = $EnvCopy
    actions = @($ActionItems)
    issues = @($Issues)
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 12
    if (-not $NoThrow -and $Result.status -eq "fail") {
        throw "PDA ecosystem installation preflight failed."
    }
    return
}

Write-Host "=== PDA ECOSYSTEM INSTALLER ==="
Write-Host ("Mode   : {0}" -f ($(if ($DryRun) { "dry-run" } else { "apply" })))
Write-Host ("Status : {0}" -f $Result.status)
Write-Host ("Root   : {0}" -f $Result.root)
Write-Host ""
Write-Host "Tools"
foreach ($Tool in $Result.tools) {
    Write-Host ("- {0}: {1} {2}" -f $Tool.name, $Tool.status, $Tool.version)
}
Write-Host ""
Write-Host "Folders"
foreach ($Folder in $Result.folders) {
    Write-Host ("- {0}: {1}" -f $Folder.path, $Folder.status)
}
Write-Host ""
Write-Host ("Env example : {0}" -f $Result.env_example_path)
Write-Host ("Local env   : {0} ({1})" -f $Result.local_env_path, $Result.env_copy.status)

if ($Result.actions.Count -gt 0) {
    Write-Host ""
    Write-Host "Planned actions"
    foreach ($Action in $Result.actions) {
        Write-Host ("- {0}: {1}" -f $Action.action, $Action.path)
    }
}

if ($Result.issues.Count -gt 0) {
    Write-Host ""
    Write-Host "Issues"
    foreach ($Issue in $Result.issues) {
        Write-Host ("- {0}" -f $Issue)
    }
}

if (-not $NoThrow -and $Result.status -eq "fail") {
    throw "PDA ecosystem installation preflight failed."
}
