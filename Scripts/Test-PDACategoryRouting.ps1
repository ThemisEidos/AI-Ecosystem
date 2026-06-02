param(
    [switch]$SkipLiveSubmit
)

$Root = "C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem"
$QueueStagingRoot = Join-Path $Root "PDA-Tasks\staging\n8n-router"
$Processor = Join-Path $Root "Scripts\Process-PDACommandStagedTasks.ps1"

. (Join-Path $Root "Scripts\PDA_CategoryRouting.ps1")

$Registry = Get-PDAWorkerRegistry -Root $Root
$RequiredCommands = @("/reporter", "/planner", "/research", "/review", "/execute")
$MissingCommands = $RequiredCommands | Where-Object { $_ -notin @($Registry.workers.command) }
if ($MissingCommands) {
    throw "Missing commands in registry: $($MissingCommands -join ', ')"
}

$PlannerWorker = Get-PDAWorkerRegistryEntry -Registry $Registry -Command "/planner"
$ReviewWorker = Get-PDAWorkerRegistryEntry -Registry $Registry -Command "/review"

$Category1Decision = Resolve-PDACategoryRouting -Task ([pscustomobject]@{ classification = "category_1" }) -Worker $PlannerWorker
$Category2Decision = Resolve-PDACategoryRouting -Task ([pscustomobject]@{ classification = "category_2" }) -Worker $ReviewWorker
$SimulatedCloudWorker = [pscustomobject]@{
    worker_name      = "cloud-review-worker"
    command          = "/review"
    routing_surface  = "cloud-capable"
    cloud_capable    = $true
    category_support = @("category_1", "category_2")
}
$Category2BlockedDecision = Resolve-PDACategoryRouting -Task ([pscustomobject]@{ classification = "category_2" }) -Worker $SimulatedCloudWorker

Write-Host "=== PDA CATEGORY ROUTING TEST ==="
Write-Host ("Category 1 planner allowed : {0}" -f $Category1Decision.allowed)
Write-Host ("Category 2 review allowed  : {0}" -f $Category2Decision.allowed)
Write-Host ("Category 2 cloud blocked   : {0}" -f (-not $Category2BlockedDecision.allowed))

if ($SkipLiveSubmit) {
    return
}

New-Item -ItemType Directory -Force -Path $QueueStagingRoot | Out-Null

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$LiveTasks = @(
    [ordered]@{
        command           = "/planner"
        route             = "planner"
        message           = "Category 1 routing validation"
        target            = "Category 1 routing validation"
        project           = "AI Ecosystem"
        classification    = "category_1"
        requested_output  = "markdown"
        source            = "validation"
        approved          = $true
        received_at       = (Get-Date).ToUniversalTime().ToString("o")
    },
    [ordered]@{
        command           = "/review"
        route             = "review"
        message           = "Category 2 routing validation"
        target            = "Category 2 routing validation"
        project           = "AI Ecosystem"
        classification    = "category_2"
        requested_output  = "markdown"
        source            = "validation"
        approved          = $true
        received_at       = (Get-Date).ToUniversalTime().ToString("o")
    },
    [ordered]@{
        command           = "/execute"
        route             = "execute"
        message           = "Category 2 dry-run validation"
        target            = "Category 2 dry-run validation"
        project           = "AI Ecosystem"
        classification    = "category_2"
        requested_output  = "markdown"
        source            = "validation"
        approved          = $true
        received_at       = (Get-Date).ToUniversalTime().ToString("o")
    }
)

foreach ($Task in $LiveTasks) {
    $Task.task_id = [guid]::NewGuid().ToString()
    $FileName = "{0}-{1}.json" -f $Timestamp, $Task.route
    $TaskPath = Join-Path $QueueStagingRoot $FileName
    $Task | ConvertTo-Json -Depth 20 | Out-File -FilePath $TaskPath -Encoding utf8
    Write-Host "Staged: $TaskPath"
}

& pwsh -File $Processor

Write-Host "Validation staging submitted. Check PDA-Tasks\results and Obsidian outputs for completion."
