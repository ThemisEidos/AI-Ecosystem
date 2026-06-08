$ErrorActionPreference = "Stop"

function Get-PDAEnvironmentRootPath {
    param([Parameter(Mandatory = $false)][string]$Root = (Split-Path -Parent $PSScriptRoot))

    return [string]$Root
}

function ConvertTo-PDAEnvironmentString {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Value,

        [Parameter(Mandatory = $false)]
        [string]$Default = ""
    )

    if ($null -eq $Value) {
        return $Default
    }

    try {
        return [System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return $Default
    }
}

function ConvertTo-PDAArray {
    param([Parameter(Mandatory = $false)][object]$Value)

    if ($null -eq $Value) {
        return @()
    }

    return [object[]]$Value
}

function Resolve-PDAEnvironmentPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Value = [string]$Path.Trim()
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    if ($Value.StartsWith("~")) {
        $UserRoot = if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile) }
        $Value = Join-Path $UserRoot ($Value.Substring(1).TrimStart('\', '/'))
    }

    $Value = [Environment]::ExpandEnvironmentVariables($Value)
    try {
        return (Resolve-Path -LiteralPath $Value -ErrorAction Stop).Path
    }
    catch {
        return $Value
    }
}

function Get-PDAEnvironmentRootsFromText {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [string[]]$FallbackRoots = @()
    )

    $Roots = New-Object System.Collections.Generic.List[string]
    $SourceText = [string]$Text
    if (-not [string]::IsNullOrWhiteSpace($SourceText)) {
        $Pattern = '(?<!\w)(?:[A-Za-z]:\\[^"''\r\n,;]+|~[\\/][^"''\r\n,;]+)'
        foreach ($Match in [regex]::Matches($SourceText, $Pattern)) {
            $Candidate = [string]$Match.Value.Trim().TrimEnd('.', ',', ';', ':', ')', ']', '}')
            $Resolved = Resolve-PDAEnvironmentPath -Path $Candidate
            if (-not [string]::IsNullOrWhiteSpace($Resolved) -and -not $Roots.Contains($Resolved)) {
                $Roots.Add($Resolved)
            }
        }
    }

    foreach ($FallbackRoot in @($FallbackRoots)) {
        if ([string]::IsNullOrWhiteSpace([string]$FallbackRoot)) {
            continue
        }

        $ResolvedFallback = Resolve-PDAEnvironmentPath -Path ([string]$FallbackRoot)
        if (-not [string]::IsNullOrWhiteSpace($ResolvedFallback) -and -not $Roots.Contains($ResolvedFallback)) {
            $Roots.Add($ResolvedFallback)
        }
    }

    if ($Roots.Count -eq 0) {
        $DefaultRoot = Get-PDAEnvironmentRootPath
        if (-not [string]::IsNullOrWhiteSpace($DefaultRoot)) {
            $Roots.Add($DefaultRoot)
        }
    }

    return @($Roots.ToArray())
}

function Test-PDAPathArchiveCandidate {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [bool]([string]$Path -match '(?i)\b(archive|archives|backup|backups|old|obsolete|retired)\b')
}

function Test-PDAPathProjectCandidate {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [bool]([string]$Path -match '(?i)\b(project|projects|workspace|workspaces|repo|repositories|code|dev|development|src)\b')
}

function Test-PDAEnvironmentLocalPort {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutMs = 1000
    )

    try {
        $Client = [System.Net.Sockets.TcpClient]::new()
        $Async = $Client.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $Async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            $Client.Close()
            return $false
        }

        $Client.EndConnect($Async)
        $Client.Close()
        return $true
    }
    catch {
        return $false
    }
}

function Get-PDAFilesystemInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Roots = @(),

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $FallbackRoots = @()
    if (@($Roots).Count -gt 0) {
        $FallbackRoots = @($Roots)
    }
    else {
        $FallbackRoots = @($Root)
    }
    $ResolvedRoots = Get-PDAEnvironmentRootsFromText -FallbackRoots $FallbackRoots
    $RootSummaries = New-Object System.Collections.Generic.List[object]
    $ProjectLocations = New-Object System.Collections.Generic.List[object]
    $ArchiveLocations = New-Object System.Collections.Generic.List[object]
    $DuplicateIndicators = New-Object System.Collections.Generic.List[object]

    foreach ($ResolvedRoot in @($ResolvedRoots)) {
        if ([string]::IsNullOrWhiteSpace($ResolvedRoot)) {
            continue
        }

        if (-not (Test-Path -LiteralPath $ResolvedRoot -PathType Container)) {
            $RootSummaries.Add([pscustomobject]@{
                root = $ResolvedRoot
                status = "missing"
                file_count = 0
                folder_count = 0
                size_bytes = 0
                size_mb = 0
                top_level_categories = @()
                likely_projects = @()
                likely_archives = @()
                duplicate_indicators = @()
            })
            continue
        }

        $TopLevelFolders = @(Get-ChildItem -LiteralPath $ResolvedRoot -Directory -Force -ErrorAction SilentlyContinue)
        $TopLevelFiles = @(Get-ChildItem -LiteralPath $ResolvedRoot -File -Force -ErrorAction SilentlyContinue)
        $AllFiles = @(Get-ChildItem -LiteralPath $ResolvedRoot -File -Recurse -Force -ErrorAction SilentlyContinue)
        $AllFolders = @(Get-ChildItem -LiteralPath $ResolvedRoot -Directory -Recurse -Force -ErrorAction SilentlyContinue)
        $SizeBytes = [int64](@($AllFiles | Measure-Object -Property Length -Sum).Sum)

        $CategoryRows = New-Object System.Collections.Generic.List[object]
        $FileNameGroups = @()
        foreach ($Folder in @($TopLevelFolders)) {
            $FolderFiles = @(Get-ChildItem -LiteralPath $Folder.FullName -File -Recurse -Force -ErrorAction SilentlyContinue)
            $FolderFolders = @(Get-ChildItem -LiteralPath $Folder.FullName -Directory -Recurse -Force -ErrorAction SilentlyContinue)
            $FolderSize = [int64](@($FolderFiles | Measure-Object -Property Length -Sum).Sum)
            $FolderScore = 0
            if (Test-Path -LiteralPath (Join-Path $Folder.FullName ".git") -PathType Container) { $FolderScore += 4 }
            foreach ($Marker in @("package.json", "pyproject.toml", "requirements.txt", "go.mod", "Cargo.toml", "*.sln", "README.md", "README.txt")) {
                if (Get-ChildItem -LiteralPath $Folder.FullName -Filter $Marker -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
                    $FolderScore += 1
                    break
                }
            }
            if (Test-PDAPathProjectCandidate -Path $Folder.FullName) { $FolderScore += 1 }
            if (Test-PDAPathArchiveCandidate -Path $Folder.FullName) { $FolderScore -= 1 }

            $Classification = "general"
            if ($FolderScore -ge 4) {
                $Classification = "project"
            }
            elseif (Test-PDAPathArchiveCandidate -Path $Folder.FullName) {
                $Classification = "archive"
            }
            elseif ($Folder.Name -match '(?i)\b(downloads|documents|desktop|music|pictures|videos|notes|resources|inbox)\b') {
                $Classification = "storage"
            }

            $CategoryRows.Add([pscustomobject]@{
                name = $Folder.Name
                path = $Folder.FullName
                classification = $Classification
                file_count = @($FolderFiles).Count
                folder_count = @($FolderFolders).Count
                size_bytes = $FolderSize
                size_mb = [math]::Round(($FolderSize / 1MB), 2)
                score = $FolderScore
            })

            foreach ($File in @($FolderFiles)) {
                $FileNameGroups += [pscustomobject]@{
                    name = $File.Name
                    path = $File.FullName
                    length = [int64]$File.Length
                }
            }
        }

        foreach ($File in @($TopLevelFiles)) {
            $FileNameGroups += [pscustomobject]@{
                name = $File.Name
                path = $File.FullName
                length = [int64]$File.Length
            }
        }

        $LikelyProjects = @($CategoryRows | Where-Object { [string]$_.classification -eq "project" } | Sort-Object score -Descending | Select-Object -First 10)
        $LikelyArchives = @($CategoryRows | Where-Object { [string]$_.classification -eq "archive" } | Select-Object -First 10)
        $DuplicateIndicators = @(
            $FileNameGroups |
                Group-Object name |
                Where-Object { $_.Count -gt 1 } |
                Sort-Object Count -Descending |
                Select-Object -First 10 |
                ForEach-Object {
                    [pscustomobject]@{
                        file_name = [string]$_.Name
                        count = [int]$_.Count
                        sample_paths = @($_.Group | Select-Object -First 3 | ForEach-Object { [string]$_.path })
                    }
                }
        )

        $RootSummaries.Add([pscustomobject]@{
            root = $ResolvedRoot
            status = "pass"
            file_count = @($AllFiles).Count
            folder_count = @($AllFolders).Count
            size_bytes = $SizeBytes
            size_mb = [math]::Round(($SizeBytes / 1MB), 2)
            top_level_categories = ConvertTo-PDAArray $CategoryRows
            likely_projects = ConvertTo-PDAArray $LikelyProjects
            likely_archives = ConvertTo-PDAArray $LikelyArchives
            duplicate_indicators = ConvertTo-PDAArray $DuplicateIndicators
        })

        $ProjectLocations.AddRange(@($LikelyProjects))
        $ArchiveLocations.AddRange(@($LikelyArchives))
    }

    $InventoryStatus = "missing"
    if (@($RootSummaries | Where-Object { [string]$_.status -eq "pass" }).Count -gt 0) {
        $InventoryStatus = "pass"
    }
    elseif (@($RootSummaries).Count -gt 0) {
        $InventoryStatus = "warning"
    }

    return [pscustomobject]@{
        status = $InventoryStatus
        roots = ConvertTo-PDAArray $RootSummaries
        root_count = @($ResolvedRoots).Count
        project_candidates = ConvertTo-PDAArray ($ProjectLocations | Select-Object -Unique)
        archive_candidates = ConvertTo-PDAArray ($ArchiveLocations | Select-Object -Unique)
    }
}

function Get-PDARepositoryInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Roots = @(),

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [int]$MaxRepositories = 25
    )

    $FallbackRoots = @()
    if (@($Roots).Count -gt 0) {
        $FallbackRoots = @($Roots)
    }
    else {
        $FallbackRoots = @($Root)
    }
    $ResolvedRoots = Get-PDAEnvironmentRootsFromText -FallbackRoots $FallbackRoots
    $GitCommand = Get-Command -Name git -ErrorAction SilentlyContinue
    $Repositories = New-Object System.Collections.Generic.List[object]

    if (-not $GitCommand) {
        return [pscustomobject]@{
            status = "missing"
            roots = @($ResolvedRoots)
            repo_count = 0
            repositories = @()
            active_projects = @()
            archived_projects = @()
            error = "git command not available."
        }
    }

    $CandidateRoots = New-Object System.Collections.Generic.List[string]
    foreach ($ResolvedRoot in @($ResolvedRoots)) {
        if ([string]::IsNullOrWhiteSpace($ResolvedRoot)) {
            continue
        }

        if (Test-Path -LiteralPath (Join-Path $ResolvedRoot ".git") -PathType Container) {
            if (-not $CandidateRoots.Contains($ResolvedRoot)) { $CandidateRoots.Add($ResolvedRoot) }
        }

        if (Test-Path -LiteralPath $ResolvedRoot -PathType Container) {
            foreach ($GitDir in @(Get-ChildItem -LiteralPath $ResolvedRoot -Directory -Force -Recurse -ErrorAction SilentlyContinue | Where-Object { [string]$_.Name -eq ".git" })) {
                $Parent = Split-Path -Parent $GitDir.FullName
                if (-not [string]::IsNullOrWhiteSpace($Parent) -and -not $CandidateRoots.Contains($Parent)) {
                    $CandidateRoots.Add($Parent)
                }
            }
        }
    }

    foreach ($RepoRoot in @($CandidateRoots | Select-Object -First $MaxRepositories)) {
        try {
            $StatusOutput = & git -C $RepoRoot status --porcelain=v1 --branch 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "git status failed."
            }

            $StatusLines = @($StatusOutput)
            $BranchLine = [string]($StatusLines | Select-Object -First 1)
            $BranchName = ""
            if ($BranchLine -match '^##\s+(?<branch>[^.]+)') {
                $BranchName = $Matches.branch.Trim()
            }
            elseif ($BranchLine -match '^##\s+(?<branch>.+)$') {
                $BranchName = $Matches.branch.Trim()
            }

            $DirtyLines = @($StatusLines | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and -not [string]$_ -like "## *" })
            $Dirty = $DirtyLines.Count -gt 0
            $CommitCount = ""
            try {
                $CommitCount = [string](& git -C $RepoRoot rev-list --count HEAD 2>$null)
            }
            catch {
                $CommitCount = ""
            }

            $ProjectMetadata = [pscustomobject]@{
                has_solution = [bool](Get-ChildItem -LiteralPath $RepoRoot -Filter *.sln -File -ErrorAction SilentlyContinue | Select-Object -First 1)
                has_package_json = [bool](Get-ChildItem -LiteralPath $RepoRoot -Filter package.json -File -ErrorAction SilentlyContinue | Select-Object -First 1)
                has_pyproject = [bool](Get-ChildItem -LiteralPath $RepoRoot -Filter pyproject.toml -File -ErrorAction SilentlyContinue | Select-Object -First 1)
                has_readme = [bool](Get-ChildItem -LiteralPath $RepoRoot -Filter README* -File -ErrorAction SilentlyContinue | Select-Object -First 1)
                has_docker_compose = [bool](Get-ChildItem -LiteralPath $RepoRoot -Filter "docker-compose*.yml" -File -ErrorAction SilentlyContinue | Select-Object -First 1)
            }
            $ProjectState = "active"
            if (Test-PDAPathArchiveCandidate -Path $RepoRoot) {
                $ProjectState = "archived"
            }

            $Repositories.Add([pscustomobject]@{
                path = $RepoRoot
                name = Split-Path -Leaf $RepoRoot
                branch = $BranchName
                clean = -not $Dirty
                dirty = [bool]$Dirty
                branch_summary = $BranchLine
                commit_count = $CommitCount
                remote = [string](& git -C $RepoRoot remote get-url origin 2>$null)
                status_lines = @($DirtyLines)
                project_metadata = $ProjectMetadata
                project_state = $ProjectState
            })
        }
        catch {
            $Repositories.Add([pscustomobject]@{
                path = $RepoRoot
                name = Split-Path -Leaf $RepoRoot
                branch = ""
                clean = $false
                dirty = $false
                branch_summary = ""
                commit_count = ""
                remote = ""
                status_lines = @()
                project_metadata = [pscustomobject]@{}
                project_state = "error"
                error = $_.Exception.Message
            })
        }
    }

    $ActiveProjects = @($Repositories | Where-Object { [string]$_.project_state -eq "active" })
    $ArchivedProjects = @($Repositories | Where-Object { [string]$_.project_state -eq "archived" })

    $ErrorRows = @($Repositories | Where-Object { $_.PSObject.Properties.Name -contains "error" })
    $InventoryStatus = "pass"
    if ($ErrorRows.Count -gt 0) {
        $InventoryStatus = "warning"
    }
    $ResolvedRootValues = [string[]]$ResolvedRoots
    $RepositoryRows = [object[]]$Repositories
    $ActiveProjectRows = [object[]]$ActiveProjects
    $ArchivedProjectRows = [object[]]$ArchivedProjects
    $RepoCount = [int]$Repositories.Count

    return [pscustomobject]@{
        status = $InventoryStatus
        roots = $ResolvedRootValues
        repo_count = $RepoCount
        repositories = $RepositoryRows
        active_projects = $ActiveProjectRows
        archived_projects = $ArchivedProjectRows
    }
}

function Get-PDADockerInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $DockerCommand = Get-Command -Name docker -ErrorAction SilentlyContinue
    if (-not $DockerCommand) {
        return [pscustomobject]@{
            status = "missing"
            containers = @()
            running_count = 0
            total_count = 0
            compose_projects = @()
            error = "docker command not available."
        }
    }

    $ContainerRows = New-Object System.Collections.Generic.List[object]
    try {
        $RawRows = & docker ps -a --format "{{json .}}" 2>$null
        foreach ($RawRow in @($RawRows)) {
            if ([string]::IsNullOrWhiteSpace([string]$RawRow)) {
                continue
            }

            $Row = $RawRow | ConvertFrom-Json -ErrorAction Stop
            $InspectRaw = & docker inspect $Row.ID 2>$null
            $Inspect = $null
            if ($LASTEXITCODE -eq 0 -and $InspectRaw) {
                try {
                    $Inspect = @($InspectRaw | ConvertFrom-Json -ErrorAction Stop)[0]
                }
                catch {
                    $Inspect = $null
                }
            }

            $Labels = $null
            if ($Inspect -and $Inspect.PSObject.Properties.Name -contains "Config") {
                $Labels = $Inspect.Config.Labels
            }

            $ComposeProject = ""
            if ($Labels -and $Labels.PSObject.Properties.Name -contains "com.docker.compose.project") {
                $ComposeProject = [string]$Labels."com.docker.compose.project"
            }

            $ComposeFiles = ""
            if ($Labels -and $Labels.PSObject.Properties.Name -contains "com.docker.compose.project.config_files") {
                $ComposeFiles = [string]$Labels."com.docker.compose.project.config_files"
            }

            $State = ""
            if ($Inspect -and $Inspect.PSObject.Properties.Name -contains "State") {
                $State = [string]$Inspect.State.Status
            }
            $ContainerRows.Add([pscustomobject]@{
                id = [string]$Row.ID
                name = [string]$Row.Names
                image = [string]$Row.Image
                status = [string]$Row.Status
                running = [bool]([string]$Row.Status -match '^Up')
                ports = [string]$Row.Ports
                compose_project = $ComposeProject
                compose_files = $ComposeFiles
                state = $State
            })
        }
    }
    catch {
        return [pscustomobject]@{
            status = "warning"
            containers = @()
            running_count = 0
            total_count = 0
            compose_projects = @()
            error = $_.Exception.Message
        }
    }

    $ComposeProjects = @(
        $ContainerRows |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.compose_project) } |
            Group-Object compose_project |
            ForEach-Object {
                [pscustomobject]@{
                    name = [string]$_.Name
                    count = [int]$_.Count
                }
            }
    )

    $ContainerRowsArray = [object[]]$ContainerRows
    $RunningContainerRows = [object[]](@($ContainerRowsArray | Where-Object { [bool]$_.running }))
    $ComposeProjectRows = [object[]]$ComposeProjects

    return [pscustomobject]@{
        status = "pass"
        containers = $ContainerRowsArray
        running_count = [int]$RunningContainerRows.Count
        total_count = [int]$ContainerRowsArray.Count
        compose_projects = $ComposeProjectRows
    }
}

function Get-PDAServiceInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $DockerInventory = Get-PDADockerInventory -Root $Root
    $DockerContainers = @($DockerInventory.containers)
    $WorkerStateDir = Join-Path $Root "PDA-Logs\workers"
    $WorkerStates = New-Object System.Collections.Generic.List[object]
    if (Test-Path -LiteralPath $WorkerStateDir -PathType Container) {
        foreach ($File in @(Get-ChildItem -LiteralPath $WorkerStateDir -File -Filter "*-state.json" -ErrorAction SilentlyContinue)) {
            try {
                $State = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $WorkerStates.Add([pscustomobject]@{
                    worker_name = if ($State.PSObject.Properties.Name -contains "worker_name") { [string]$State.worker_name } else { ($File.BaseName -replace '-state$', '') }
                    status = if ($State.PSObject.Properties.Name -contains "status") { [string]$State.status } else { "unknown" }
                    pid = if ($State.PSObject.Properties.Name -contains "pid") { [int]$State.pid } else { $null }
                    process_live = if ($State.PSObject.Properties.Name -contains "pid" -and $State.pid) { $null -ne (Get-Process -Id $State.pid -ErrorAction SilentlyContinue) } else { $false }
                    script = if ($State.PSObject.Properties.Name -contains "script") { [string]$State.script } else { "" }
                    log_file = if ($State.PSObject.Properties.Name -contains "log_file") { [string]$State.log_file } else { "" }
                })
            }
            catch {
                $WorkerStates.Add([pscustomobject]@{
                    worker_name = ($File.BaseName -replace '-state$', '')
                    status = "parse-error"
                    pid = $null
                    process_live = $false
                    script = ""
                    log_file = ""
                    error = $_.Exception.Message
                })
            }
        }
    }

    $Definitions = @(
        [pscustomobject]@{ name = "Open WebUI"; patterns = @("open-webui", "openwebui", "open webui"); ports = @(3000, 8080); endpoint = "http://localhost:3000" }
        [pscustomobject]@{ name = "LiteLLM"; patterns = @("litellm", "lite llm"); ports = @(4000, 4001); endpoint = "http://localhost:4000" }
        [pscustomobject]@{ name = "n8n"; patterns = @("n8n"); ports = @(5678); endpoint = "http://localhost:5678" }
        [pscustomobject]@{ name = "Ollama"; patterns = @("ollama"); ports = @(11434); endpoint = "http://localhost:11434" }
    )

    $ServiceRows = New-Object System.Collections.Generic.List[object]
    foreach ($Definition in $Definitions) {
        $MatchedContainer = $null
        foreach ($Container in @($DockerContainers)) {
            $SearchText = ([string]$Container.name + " " + [string]$Container.image + " " + [string]$Container.compose_project).ToLowerInvariant()
            $MatchedPattern = $false
            foreach ($Pattern in @($Definition.patterns)) {
                if ($SearchText -match [regex]::Escape(([string]$Pattern).ToLowerInvariant())) {
                    $MatchedPattern = $true
                    break
                }
            }

            if ($MatchedPattern) {
                $MatchedContainer = $Container
                break
            }
        }

        $ListeningPort = $null
        foreach ($Port in @($Definition.ports)) {
            if (Test-PDAEnvironmentLocalPort -Port ([int]$Port)) {
                $ListeningPort = [int]$Port
                break
            }
        }

        $ServiceStatus = "offline"
        $ServiceSource = "port"
        if ($MatchedContainer -and [bool]$MatchedContainer.running) {
            $ServiceStatus = "online"
            $ServiceSource = "docker"
        }
        elseif ($ListeningPort) {
            $ServiceStatus = "online"
            $ServiceSource = "port"
        }
        $ContainerName = if ($MatchedContainer) { [string]$MatchedContainer.name } else { "" }

        $ServiceRows.Add([pscustomobject]@{
            name = [string]$Definition.name
            status = $ServiceStatus
            source = $ServiceSource
            endpoint = [string]$Definition.endpoint
            container = $ContainerName
            ports = @($Definition.ports)
            listening_port = $ListeningPort
        })
    }

    $PDAWorkerRows = @(
        $WorkerStates | ForEach-Object {
            [pscustomobject]@{
                name = [string]$_.worker_name
                status = [string]$_.status
                process_live = [bool]$_.process_live
                pid = $_.pid
                script = [string]$_.script
                log_file = [string]$_.log_file
                source = "worker_state"
            }
        }
    )

    $ServiceRows.AddRange(@($PDAWorkerRows))

    $InventoryStatus = if (@($ServiceRows | Where-Object { [string]$_.status -eq "online" }).Count -gt 0) { "pass" } else { "warning" }

    return [pscustomobject]@{
        status = $InventoryStatus
        services = ConvertTo-PDAArray $ServiceRows
        worker_states = ConvertTo-PDAArray $WorkerStates
        online_count = [int]@($ServiceRows | Where-Object { [string]$_.status -eq "online" }).Count
        offline_count = [int]@($ServiceRows | Where-Object { [string]$_.status -eq "offline" }).Count
    }
}

function Get-PDAToolInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Definitions = @(
        [pscustomobject]@{ name = "Codex"; commands = @("codex"); notes = "Codex CLI / task runner." }
        [pscustomobject]@{ name = "Gemini CLI"; commands = @("gemini"); notes = "Gemini command-line client." }
        [pscustomobject]@{ name = "Git"; commands = @("git"); notes = "Repository and governance tooling." }
        [pscustomobject]@{ name = "Docker"; commands = @("docker"); notes = "Container runtime and compose tooling." }
        [pscustomobject]@{ name = "Obsidian"; commands = @("obsidian"); notes = "Vault and knowledge workspace." }
        [pscustomobject]@{ name = "PowerShell"; commands = @("pwsh", "powershell"); notes = "Local scripting runtime." }
        [pscustomobject]@{ name = "Python"; commands = @("python", "python3"); notes = "General-purpose scripting runtime." }
        [pscustomobject]@{ name = "Fabric"; commands = @("fabric"); notes = "Fabric CLI / pattern execution." }
        [pscustomobject]@{ name = "NotebookLM"; commands = @("Invoke-PDANotebookLMCommand.ps1"); notes = "Sanitized local package workflow for NotebookLM." }
    )

    $Rows = New-Object System.Collections.Generic.List[object]
    foreach ($Definition in $Definitions) {
        $FoundCommand = $null
        $CommandPath = ""
        foreach ($Command in @($Definition.commands)) {
            if ($Command -like "*.ps1") {
                $ScriptPath = Join-Path $Root "Scripts\$Command"
                if (Test-Path -LiteralPath $ScriptPath -PathType Leaf) {
                    $FoundCommand = $Command
                    $CommandPath = $ScriptPath
                    break
                }
            }
            else {
                $Resolved = Get-Command -Name $Command -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($Resolved) {
                    $FoundCommand = $Command
                    $CommandPath = [string]$Resolved.Source
                    break
                }

                if ($Command -eq "obsidian" -and (Get-Command -Name Get-StartApps -ErrorAction SilentlyContinue)) {
                    $App = @(Get-StartApps | Where-Object { [string]$_.Name -match '(?i)obsidian' } | Select-Object -First 1)
                    if ($App.Count -gt 0) {
                        $FoundCommand = "obsidian"
                        $CommandPath = [string]$App[0].AppID
                        break
                    }
                }
            }
        }
        $SourceKind = if ($FoundCommand) {
            if ($CommandPath -like "*.ps1") { "local_script" } else { "command" }
        }
        else {
            "missing"
        }

        $Rows.Add([pscustomobject]@{
            tool_name = [string]$Definition.name
            available = [bool]$FoundCommand
            command = [string]$FoundCommand
            path = [string]$CommandPath
            source = $SourceKind
            notes = [string]$Definition.notes
        })
    }

    $InventoryStatus = if (@($Rows | Where-Object { [bool]$_.available }).Count -gt 0) { "pass" } else { "warning" }

    return [pscustomobject]@{
        status = $InventoryStatus
        tools = ConvertTo-PDAArray $Rows
        available_count = [int]@($Rows | Where-Object { [bool]$_.available }).Count
    }
}

function Get-PDAEnvironmentSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Roots = @(),

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $Filesystem = Get-PDAFilesystemInventory -Roots $Roots -Root $Root
    $Repositories = Get-PDARepositoryInventory -Roots $Roots -Root $Root
    $Docker = Get-PDADockerInventory -Root $Root
    $Services = Get-PDAServiceInventory -Root $Root
    $Tools = Get-PDAToolInventory -Root $Root

    $WorkspaceRows = @(
        $Filesystem.roots | ForEach-Object {
            [pscustomobject]@{
                root = [string]$_.root
                project_candidates = @($_.likely_projects).Count
                archive_candidates = @($_.likely_archives).Count
                file_count = [int]$_.file_count
                folder_count = [int]$_.folder_count
                size_mb = [double]$_.size_mb
            }
        }
    )

    $StorageRows = New-Object System.Collections.Generic.List[object]
    foreach ($RootRow in @($Filesystem.roots)) {
        foreach ($Category in @($RootRow.top_level_categories)) {
            $StorageRows.Add([pscustomobject]@{
                root = [string]$RootRow.root
                name = [string]$Category.name
                classification = [string]$Category.classification
                file_count = [int]$Category.file_count
                folder_count = [int]$Category.folder_count
                size_mb = [double]$Category.size_mb
            })
        }
    }

    $Status = "pass"
    foreach ($ComponentStatus in @($Filesystem.status, $Repositories.status, $Docker.status, $Services.status, $Tools.status)) {
        if ([string]$ComponentStatus -in @("warning", "missing", "error")) {
            $Status = "warning"
        }
    }
    $WorkspaceRowsArray = [object[]]$WorkspaceRows
    $StorageRowsArray = [object[]]$StorageRows
    $FilesystemRootValues = [string[]](@($Filesystem.roots | ForEach-Object { [string]$_.root }))
    $FilesystemProjectCandidates = @($Filesystem.project_candidates)
    $FilesystemArchiveCandidates = @($Filesystem.archive_candidates)
    $RepositoryProjectRows = @($Repositories.repositories | Where-Object { [string]$_.project_state -eq "active" })
    $RepositoryArchiveRows = @($Repositories.archived_projects)
    $ProjectCountValue = [int]($FilesystemProjectCandidates.Count + $RepositoryProjectRows.Count)
    $ArchiveCountValue = [int]($FilesystemArchiveCandidates.Count + $RepositoryArchiveRows.Count)
    $TopLevelCategoryCount = [int]$StorageRowsArray.Count
    $RepositoryCountValue = [int]$Repositories.repo_count
    $ContainerCountValue = [int]$Docker.total_count
    $RunningContainerCountValue = [int]$Docker.running_count
    $ServicesOnlineCountValue = [int]$Services.online_count
    $ToolsAvailableCountValue = [int]$Tools.available_count

    return [pscustomobject]@{
        status = $Status
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        roots = $FilesystemRootValues
        filesystem = $Filesystem
        repositories = $Repositories
        containers = $Docker
        services = $Services
        tools = $Tools
        workspace_summary = [pscustomobject]@{
            roots = $WorkspaceRowsArray
            project_count = $ProjectCountValue
            archive_count = $ArchiveCountValue
        }
        storage_summary = [pscustomobject]@{
            roots = $StorageRowsArray
            top_level_category_count = $TopLevelCategoryCount
        }
        counts = [pscustomobject]@{
            repositories = $RepositoryCountValue
            containers = $ContainerCountValue
            running_containers = $RunningContainerCountValue
            services_online = $ServicesOnlineCountValue
            tools_available = $ToolsAvailableCountValue
        }
    }
}

function Get-PDAFileOrganizationRecommendation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Roots = @(),

        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot),

        [Parameter(Mandatory = $false)]
        [object]$FilesystemInventory = $null
    )

    if (-not $FilesystemInventory) {
        $FilesystemInventory = Get-PDAFilesystemInventory -Roots $Roots -Root $Root
    }

    if ($FilesystemInventory.PSObject.Properties.Name -contains "filesystem" -and $FilesystemInventory.filesystem) {
        $FilesystemInventory = $FilesystemInventory.filesystem
    }

    $RootsSummary = @($FilesystemInventory.roots)
    $ProjectCount = @($FilesystemInventory.project_candidates).Count
    $ArchiveCount = @($FilesystemInventory.archive_candidates).Count
    $HasLargeRoot = @($RootsSummary | Where-Object { [double]$_.size_mb -gt 512 }).Count -gt 0
    $Model = "Project/Area/Archive (PARA-aligned)"
    if ($ProjectCount -gt 5 -and $ArchiveCount -gt 2) {
        $Model = "Project/Area/Archive (PARA-aligned)"
    }
    elseif ($HasLargeRoot -and $ProjectCount -gt 2) {
        $Model = "Johnny Decimal"
    }
    elseif (@($RootsSummary | Where-Object { @($_.top_level_categories | Where-Object { [string]$_.classification -eq "project" }).Count -gt 0 }).Count -gt 0) {
        $Model = "Project/Area/Archive"
    }

    $ProposedStructure = @(
        [pscustomobject]@{ path = "Projects"; purpose = "Active workspaces and time-bound deliverables."; priority = 1 }
        [pscustomobject]@{ path = "Areas"; purpose = "Ongoing responsibilities and stable operating domains."; priority = 2 }
        [pscustomobject]@{ path = "Archive"; purpose = "Completed or inactive material with low change frequency."; priority = 3 }
        [pscustomobject]@{ path = "Resources"; purpose = "Reference material, reusable assets, and documentation."; priority = 4 }
        [pscustomobject]@{ path = "Inbox"; purpose = "New, untriaged material awaiting classification."; priority = 5 }
    )

    $MigrationStrategy = @(
        [pscustomobject]@{ phase = 1; name = "Inventory"; action = "Map current folders to project, area, archive, resource, or inbox categories."; risk = "Low"; approval_required = $true }
        [pscustomobject]@{ phase = 2; name = "Label"; action = "Tag folders and repos before any moves so owners can verify the intended destination."; risk = "Low"; approval_required = $true }
        [pscustomobject]@{ phase = 3; name = "Pilot"; action = "Move a small, low-risk subset first and validate links, shortcuts, and automation."; risk = "Medium"; approval_required = $true }
        [pscustomobject]@{ phase = 4; name = "Rollout"; action = "Expand the migration in batches after the pilot path is accepted."; risk = "Medium"; approval_required = $true }
    )

    $RiskAssessment = @(
        [pscustomobject]@{ risk = "Broken references"; impact = "Files may be linked from notes or scripts." ; mitigation = "Use a staged pilot, preserve redirects, and avoid automatic moves." }
        [pscustomobject]@{ risk = "Repository disruption"; impact = "Git working trees can be dirtied or detached by aggressive moves."; mitigation = "Treat repositories as first-class projects and do not move them automatically." }
        [pscustomobject]@{ risk = "Over-normalization"; impact = "A rigid taxonomy can fight real workflows."; mitigation = "Keep the structure shallow and leave an inbox for exceptions." }
    )

    $ApprovalPath = @(
        "Review the current-state inventory.",
        "Approve the recommended structure model.",
        "Approve the staged migration plan before any manual file moves.",
        "Do not move or rename files automatically."
    )

    return [pscustomobject]@{
        status = "pass"
        roots = @($FilesystemInventory.roots | ForEach-Object { [string]$_.root })
        recommended_model = $Model
        current_state = [pscustomobject]@{
            root_count = @($FilesystemInventory.roots).Count
            project_candidates = @($FilesystemInventory.project_candidates).Count
            archive_candidates = @($FilesystemInventory.archive_candidates).Count
            repository_count = if ($FilesystemInventory.PSObject.Properties.Name -contains "repositories") { [int]$FilesystemInventory.repositories.repo_count } else { 0 }
        }
        proposed_structure = @($ProposedStructure)
        migration_strategy = @($MigrationStrategy)
        risk_assessment = @($RiskAssessment)
        approval_path = @($ApprovalPath)
        no_auto_moves = $true
        summary = "Recommended model: $Model. Review the inventory first, then approve a staged migration."
        source_of_truth = "Scripts/PDA_Environment.ps1"
    }
}
