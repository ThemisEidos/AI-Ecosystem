[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [string]$ReportRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "PDA-Backups\nightly-build\reports"),

    [Parameter(Mandatory = $false)]
    [int]$StaleThresholdHours = 12,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

function ConvertTo-PDAMarkdownTable {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Rows,

        [Parameter(Mandatory = $true)]
        [string[]]$Columns
    )

    if (-not $Rows -or $Rows.Count -eq 0) {
        return @("| (none) |", "| --- |")
    }

    $Header = "| " + ($Columns -join " | ") + " |"
    $Separator = "| " + (($Columns | ForEach-Object { "---" }) -join " | ") + " |"
    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add($Header)
    $Lines.Add($Separator)

    foreach ($Row in $Rows) {
        $Values = foreach ($Column in $Columns) {
            $Value = if ($Row.PSObject.Properties.Name -contains $Column) { [string]$Row.$Column } else { "" }
            $Value = $Value.Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
            if ([string]::IsNullOrWhiteSpace($Value)) { " " } else { $Value }
        }
        $Lines.Add("| " + ($Values -join " | ") + " |")
    }

    return $Lines.ToArray()
}

function Get-PDAJsonRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return @()
    }

    return @(Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json)
}

function Get-PDAQueueEntries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,

        [Parameter(Mandatory = $true)]
        [string]$QueueName
    )

    $Entries = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -Path $Directory -PathType Container)) {
        return @()
    }

    foreach ($File in Get-ChildItem -Path $Directory -Filter *.json -File -ErrorAction SilentlyContinue) {
        $Parsed = $null
        try {
            $Parsed = Get-Content -Path $File.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            $Parsed = $null
        }

        $TaskId = if ($Parsed -and ($Parsed.PSObject.Properties.Name -contains "task_id")) { [string]$Parsed.task_id } else { [System.IO.Path]::GetFileNameWithoutExtension($File.Name) }
        $Status = if ($Parsed -and ($Parsed.PSObject.Properties.Name -contains "status")) { [string]$Parsed.status } else { $QueueName }
        $Command = if ($Parsed -and ($Parsed.PSObject.Properties.Name -contains "command")) { [string]$Parsed.command } else { "" }
        $Worker = if ($Parsed -and ($Parsed.PSObject.Properties.Name -contains "assigned_worker")) { [string]$Parsed.assigned_worker } else { "" }
        $Updated = $File.LastWriteTimeUtc
        if ($Parsed) {
            foreach ($Field in @("updated_at","created","started","completed","approval_checked_at")) {
                if ($Parsed.PSObject.Properties.Name -contains $Field) {
                    $Candidate = [string]$Parsed.$Field
                    try {
                        $ParsedDate = [datetime]::Parse($Candidate)
                        if ($ParsedDate -gt [datetime]::MinValue) {
                            $Updated = $ParsedDate.ToUniversalTime()
                            break
                        }
                    }
                    catch {}
                }
            }
        }

        $Entries.Add([pscustomobject]@{
            queue         = $QueueName
            file_name     = $File.Name
            file_path     = $File.FullName
            task_id       = $TaskId
            command       = $Command
            worker        = $Worker
            status        = $Status
            age_hours     = [math]::Round(((Get-Date).ToUniversalTime() - $Updated).TotalHours, 2)
            last_write    = $File.LastWriteTimeUtc.ToString("o")
            parsed        = [bool]$Parsed
            raw           = $Parsed
        })
    }

    return $Entries.ToArray()
}

function Get-PDAApprovalEntries {
    param([Parameter(Mandatory = $true)][string]$Directory)

    if (-not (Test-Path -Path $Directory -PathType Container)) {
        return @()
    }

    $Entries = New-Object System.Collections.Generic.List[object]
    foreach ($File in Get-ChildItem -Path $Directory -Filter *.json -File -ErrorAction SilentlyContinue) {
        $Parsed = $null
        try {
            $Parsed = Get-Content -Path $File.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            $Parsed = $null
        }

        $TaskId = if ($Parsed -and ($Parsed.PSObject.Properties.Name -contains "task_id")) { [string]$Parsed.task_id } else { [System.IO.Path]::GetFileNameWithoutExtension($File.Name) }
        $Status = if ($Parsed -and ($Parsed.PSObject.Properties.Name -contains "approval_status")) { [string]$Parsed.approval_status } elseif ($Parsed -and ($Parsed.PSObject.Properties.Name -contains "status")) { [string]$Parsed.status } else { "pending" }
        $Command = if ($Parsed -and ($Parsed.PSObject.Properties.Name -contains "command")) { [string]$Parsed.command } else { "" }
        $Worker = if ($Parsed -and ($Parsed.PSObject.Properties.Name -contains "worker")) { [string]$Parsed.worker } else { "" }
        $Updated = $File.LastWriteTimeUtc
        if ($Parsed) {
            foreach ($Field in @("updated_at","approval_checked_at","created")) {
                if ($Parsed.PSObject.Properties.Name -contains $Field) {
                    try {
                        $ParsedDate = [datetime]::Parse([string]$Parsed.$Field)
                        $Updated = $ParsedDate.ToUniversalTime()
                        break
                    }
                    catch {}
                }
            }
        }

        $Entries.Add([pscustomobject]@{
            queue         = Split-Path -Leaf $Directory
            file_name     = $File.Name
            file_path     = $File.FullName
            task_id       = $TaskId
            command       = $Command
            worker        = $Worker
            approval_status = $Status
            age_hours     = [math]::Round(((Get-Date).ToUniversalTime() - $Updated).TotalHours, 2)
            last_write    = $File.LastWriteTimeUtc.ToString("o")
            parsed        = [bool]$Parsed
            raw           = $Parsed
        })
    }

    return $Entries.ToArray()
}

$QueueRoot = Join-Path $Root "PDA-Tasks"
$QueueDirs = @{
    pending   = Join-Path $QueueRoot "pending"
    running   = Join-Path $QueueRoot "running"
    completed = Join-Path $QueueRoot "completed"
    failed    = Join-Path $QueueRoot "failed"
    results   = Join-Path $QueueRoot "results"
}
$ApprovalDirs = @{
    pending   = Join-Path $QueueRoot "approvals\pending"
    approved  = Join-Path $QueueRoot "approvals\approved"
    rejected  = Join-Path $QueueRoot "approvals\rejected"
}

$QueueEntries = New-Object System.Collections.Generic.List[object]
foreach ($Item in $QueueDirs.GetEnumerator()) {
    foreach ($Entry in @(Get-PDAQueueEntries -Directory $Item.Value -QueueName $Item.Key)) {
        [void]$QueueEntries.Add($Entry)
    }
}

$ApprovalEntries = New-Object System.Collections.Generic.List[object]
foreach ($Item in $ApprovalDirs.GetEnumerator()) {
    foreach ($Entry in @(Get-PDAApprovalEntries -Directory $Item.Value)) {
        [void]$ApprovalEntries.Add($Entry)
    }
}

$TaskIndex = @{}
foreach ($Entry in $QueueEntries) {
    if (-not [string]::IsNullOrWhiteSpace($Entry.task_id)) {
        $TaskIndex[[string]$Entry.task_id] = $Entry
    }
}

$ResultTaskIds = @()
foreach ($Entry in $QueueEntries) {
    if ($Entry.queue -eq "results" -and -not [string]::IsNullOrWhiteSpace($Entry.task_id)) {
        $ResultTaskIds += [string]$Entry.task_id
    }
}

$StaleTasks = @(
    $QueueEntries | Where-Object {
        ($_.queue -in @("pending","running")) -and $_.age_hours -ge $StaleThresholdHours
    } | Sort-Object age_hours -Descending
)

$FailedTasks = @(
    $QueueEntries | Where-Object { $_.queue -eq "failed" -or $_.status -eq "failed" } | Sort-Object age_hours -Descending
)

$OrphanedApprovals = @(
    $ApprovalEntries | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$_.task_id) -or
        (-not $TaskIndex.ContainsKey([string]$_.task_id) -and ($ResultTaskIds -notcontains [string]$_.task_id))
    } | Sort-Object age_hours -Descending
)

function Get-PDAQueueCount {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IEnumerable]$Entries,

        [Parameter(Mandatory = $true)]
        [string]$QueueName
    )

    $Count = 0
    foreach ($Entry in $Entries) {
        if ([string]$Entry.queue -eq $QueueName) {
            $Count++
        }
    }

    return $Count
}

function Get-PDAApprovalCount {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IEnumerable]$Entries,

        [Parameter(Mandatory = $true)]
        [string]$QueueName
    )

    $Count = 0
    foreach ($Entry in $Entries) {
        if ([string]$Entry.queue -eq $QueueName) {
            $Count++
        }
    }

    return $Count
}

$QueueCounts = [pscustomobject]@{
    pending   = Get-PDAQueueCount -Entries $QueueEntries -QueueName "pending"
    running   = Get-PDAQueueCount -Entries $QueueEntries -QueueName "running"
    completed = Get-PDAQueueCount -Entries $QueueEntries -QueueName "completed"
    failed    = Get-PDAQueueCount -Entries $QueueEntries -QueueName "failed"
    results   = Get-PDAQueueCount -Entries $QueueEntries -QueueName "results"
}

$ApprovalCounts = [pscustomobject]@{
    pending  = Get-PDAApprovalCount -Entries $ApprovalEntries -QueueName "pending"
    approved = Get-PDAApprovalCount -Entries $ApprovalEntries -QueueName "approved"
    rejected = Get-PDAApprovalCount -Entries $ApprovalEntries -QueueName "rejected"
    total    = $ApprovalEntries.Count
}

$ImpactStatus = "healthy"
$ImpactNotes = New-Object System.Collections.Generic.List[string]
if ($QueueCounts.failed -gt 0) {
    $ImpactStatus = "degraded"
    $ImpactNotes.Add("Failed queue entries keep the dashboard out of green.")
}
if ($ApprovalCounts.pending -gt 0) {
    $ImpactStatus = "degraded"
    $ImpactNotes.Add("Pending approvals keep the approval backlog elevated.")
}
if ($StaleTasks.Count -gt 0) {
    $ImpactStatus = "degraded"
    $ImpactNotes.Add("Stale pending or running tasks suggest queue items are not flowing cleanly.")
}
if ($OrphanedApprovals.Count -gt 0) {
    $ImpactStatus = "degraded"
    $ImpactNotes.Add("Orphaned approvals indicate approval records without matching queue tasks or results.")
}

$Remediation = @()
if ($FailedTasks.Count -gt 0) {
    $Remediation += "Review failed tasks first and identify recurring command or worker failures."
}
if ($StaleTasks.Count -gt 0) {
    $Remediation += "Manually triage stale queue items and either requeue or retire them through the governed path."
}
if ($OrphanedApprovals.Count -gt 0) {
    $Remediation += "Reconcile orphaned approval records with their source tasks; do not auto-delete or auto-approve them."
}
if ($ApprovalCounts.pending -gt 0) {
    $Remediation += "Reduce the approval backlog by processing pending approvals in the approved governance flow."
}
if ($Remediation.Count -eq 0) {
    $Remediation += "No immediate remediation required from the backlog audit."
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null
$ReportPath = Join-Path $ReportRoot "task-001-audit-$Timestamp.md"

$Lines = New-Object System.Collections.Generic.List[string]
$Lines.Add("# PDA Queue and Approval Backlog Audit")
$Lines.Add("")
$Lines.Add(("Generated at: {0}" -f (Get-Date).ToString("o")))
$Lines.Add(("Root path: {0}" -f $Root))
$Lines.Add(("Stale threshold: {0} hours" -f $StaleThresholdHours))
$Lines.Add("")
$Lines.Add("## Queue Counts")
$Lines.Add("")
$Lines.Add("| queue | count |")
$Lines.Add("| --- | ---: |")
$Lines.Add(("| pending | {0} |" -f $QueueCounts.pending))
$Lines.Add(("| running | {0} |" -f $QueueCounts.running))
$Lines.Add(("| completed | {0} |" -f $QueueCounts.completed))
$Lines.Add(("| failed | {0} |" -f $QueueCounts.failed))
$Lines.Add(("| results | {0} |" -f $QueueCounts.results))
$Lines.Add("")
$Lines.Add("## Approval Counts")
$Lines.Add("")
$Lines.Add("| approval queue | count |")
$Lines.Add("| --- | ---: |")
$Lines.Add(("| pending | {0} |" -f $ApprovalCounts.pending))
$Lines.Add(("| approved | {0} |" -f $ApprovalCounts.approved))
$Lines.Add(("| rejected | {0} |" -f $ApprovalCounts.rejected))
$Lines.Add(("| total | {0} |" -f $ApprovalCounts.total))
$Lines.Add("")
$Lines.Add("## Stale Tasks")
$Lines.Add("")
if ($StaleTasks.Count -gt 0) {
    foreach ($Line in @(ConvertTo-PDAMarkdownTable -Rows @($StaleTasks | Select-Object -First 25) -Columns @("queue","task_id","command","worker","status","age_hours","file_name"))) {
        $Lines.Add($Line)
    }
}
else {
    $Lines.Add("No stale tasks were detected.")
}
$Lines.Add("")
$Lines.Add("## Orphaned Approvals")
$Lines.Add("")
if ($OrphanedApprovals.Count -gt 0) {
    foreach ($Line in @(ConvertTo-PDAMarkdownTable -Rows @($OrphanedApprovals | Select-Object -First 25) -Columns @("queue","task_id","command","worker","approval_status","age_hours","file_name"))) {
        $Lines.Add($Line)
    }
}
else {
    $Lines.Add("No orphaned approvals were detected.")
}
$Lines.Add("")
$Lines.Add("## Failed Tasks")
$Lines.Add("")
if ($FailedTasks.Count -gt 0) {
    foreach ($Line in @(ConvertTo-PDAMarkdownTable -Rows @($FailedTasks | Select-Object -First 25) -Columns @("queue","task_id","command","worker","status","age_hours","file_name"))) {
        $Lines.Add($Line)
    }
}
else {
    $Lines.Add("No failed tasks were detected.")
}
$Lines.Add("")
$Lines.Add("## Dashboard Health Impact")
$Lines.Add("")
$Lines.Add(("Status: {0}" -f $ImpactStatus))
foreach ($Note in $ImpactNotes) {
    $Lines.Add(("- {0}" -f $Note))
}
$Lines.Add("")
$Lines.Add("## Recommended Remediation")
$Lines.Add("")
foreach ($Step in $Remediation) {
    $Lines.Add(("- {0}" -f $Step))
}
$Lines.Add("")
$Lines.Add("## Read-Only Guarantee")
$Lines.Add("")
$Lines.Add("- This audit only reads queue and approval files.")
$Lines.Add("- It does not approve, reject, requeue, or delete anything.")

$Lines | Set-Content -Path $ReportPath -Encoding UTF8

$Result = [pscustomobject]@{
    status              = "pass"
    generated_at        = (Get-Date).ToUniversalTime().ToString("o")
    root_path           = $Root
    report_root         = $ReportRoot
    report_path         = $ReportPath
    stale_threshold_hours = $StaleThresholdHours
    queue_counts        = $QueueCounts
    approval_counts     = $ApprovalCounts
    stale_task_count    = $StaleTasks.Count
    orphaned_approval_count = $OrphanedApprovals.Count
    failed_task_count   = $FailedTasks.Count
    dashboard_health_impact = [pscustomobject]@{
        status = $ImpactStatus
        notes  = @($ImpactNotes)
    }
    recommended_remediation = @($Remediation)
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] PDA queue backlog audit complete."
Write-Host ("Report path : {0}" -f $ReportPath)
Write-Host ("Queue items  : pending={0} running={1} completed={2} failed={3} results={4}" -f $QueueCounts.pending, $QueueCounts.running, $QueueCounts.completed, $QueueCounts.failed, $QueueCounts.results)
Write-Host ("Approvals    : pending={0} approved={1} rejected={2}" -f $ApprovalCounts.pending, $ApprovalCounts.approved, $ApprovalCounts.rejected)
