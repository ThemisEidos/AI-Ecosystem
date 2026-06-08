[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = 'Stop'

$RegistryScript = Join-Path $PSScriptRoot 'PDA_ExecutorRegistry.ps1'
if (Test-Path -LiteralPath $RegistryScript -PathType Leaf) {
    . $RegistryScript
}

function Get-PDADispatchFileSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$QueueName
    )

    $Items = @()
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $Items
    }

    foreach ($File in Get-ChildItem -LiteralPath $Path -Filter *.json -File -ErrorAction SilentlyContinue) {
        $Items += [pscustomobject]@{
            file_name   = $File.Name
            file_path   = $File.FullName
            queue       = $QueueName
            updated_at  = $File.LastWriteTimeUtc.ToString('o')
            task_id     = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
        }
    }

    return @($Items)
}

try {
    $Registry = Get-PDAExecutorRegistry -Root $Root
}
catch {
    $Registry = [pscustomobject]@{
        status = 'error'
        registry_path = Get-PDAExecutorRegistryPath -Root $Root
        executor_count = 0
        local_only_count = 0
        category2_capable_count = 0
        cloud_capable_count = 0
        requires_approval_count = 0
        executors = @()
        error = $_.Exception.Message
    }
}

$PendingApprovalPath = Join-Path $Root 'PDA-Tasks\approvals\pending'
$ApprovedPath = Join-Path $Root 'PDA-Tasks\approvals\approved'
$PreparedPath = Join-Path $Root 'PDA-Tasks\staging\dispatch'
$RunningPath = Join-Path $Root 'PDA-Tasks\running'
$CompletedPath = Join-Path $Root 'PDA-Tasks\completed'
$FailedPath = Join-Path $Root 'PDA-Tasks\failed'

$PendingApproval = Get-PDADispatchFileSummary -Path $PendingApprovalPath -QueueName 'approvals/pending'
$Approved = Get-PDADispatchFileSummary -Path $ApprovedPath -QueueName 'approvals/approved'
$Prepared = Get-PDADispatchFileSummary -Path $PreparedPath -QueueName 'staging/dispatch'
$Running = Get-PDADispatchFileSummary -Path $RunningPath -QueueName 'running'
$Completed = Get-PDADispatchFileSummary -Path $CompletedPath -QueueName 'completed'
$Failed = Get-PDADispatchFileSummary -Path $FailedPath -QueueName 'failed'

$Status = if ($Registry.status -eq 'error') { 'warning' } else { 'pass' }
$Report = [pscustomobject]@{
    status = $Status
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    root_path = $Root
    registry = $Registry
    counts = [pscustomobject]@{
        pending_approval = @($PendingApproval).Count
        approved = @($Approved).Count
        prepared = @($Prepared).Count
        running = @($Running).Count
        completed = @($Completed).Count
        failed = @($Failed).Count
    }
    pending_approval = @($PendingApproval | Select-Object -First 20)
    approved = @($Approved | Select-Object -First 20)
    prepared = @($Prepared | Select-Object -First 20)
    running = @($Running | Select-Object -First 20)
    completed = @($Completed | Select-Object -First 20)
    failed = @($Failed | Select-Object -First 20)
    recent_items = @((@($Prepared + $Running + $Completed + $Failed) | Sort-Object updated_at -Descending | Select-Object -First 20))
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 10
    if (-not $NoThrow -and $Report.status -ne 'pass') {
        throw 'PDA dispatch status validation failed.'
    }
    return
}

Write-Host '[PDA DISPATCH STATUS]'
Write-Host ("Executors        : {0}" -f $Report.registry.executor_count)
Write-Host ("Pending approval : {0}" -f $Report.counts.pending_approval)
Write-Host ("Approved         : {0}" -f $Report.counts.approved)
Write-Host ("Prepared         : {0}" -f $Report.counts.prepared)
Write-Host ("Running          : {0}" -f $Report.counts.running)
Write-Host ("Completed        : {0}" -f $Report.counts.completed)
Write-Host ("Failed           : {0}" -f $Report.counts.failed)

if (-not $NoThrow -and $Report.status -ne 'pass') {
    throw 'PDA dispatch status validation failed.'
}
