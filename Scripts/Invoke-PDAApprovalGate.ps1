param(
    [Parameter(Mandatory=$true)]
    [string]$TaskPath
)

$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$PolicyPath = Join-Path $PSScriptRoot "PDA_ApprovalPolicy.json"
$ApprovalRoot = Join-Path $Root "PDA-Tasks\approvals"
$PendingApprovalDir = Join-Path $ApprovalRoot "pending"
$ApprovedDir = Join-Path $ApprovalRoot "approved"
$RejectedDir = Join-Path $ApprovalRoot "rejected"
$LogDir = Join-Path $Root "PDA-Logs\approvals"

New-Item -ItemType Directory -Force -Path $PendingApprovalDir | Out-Null
New-Item -ItemType Directory -Force -Path $ApprovedDir | Out-Null
New-Item -ItemType Directory -Force -Path $RejectedDir | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

if (-not (Test-Path $TaskPath)) {
    throw "TaskPath not found: $TaskPath"
}

$Task = Get-Content $TaskPath -Raw | ConvertFrom-Json
$Policy = Get-Content $PolicyPath -Raw | ConvertFrom-Json

if (-not $Task.task_id) {
    $Task | Add-Member -NotePropertyName task_id -NotePropertyValue ([guid]::NewGuid().ToString()) -Force
}

$TaskId = $Task.task_id
$Command = [string]$Task.command
$Category = if ($Task.category) { [string]$Task.category } else { "category_1" }
$RoutingSurface = if ($Task.routing_surface) { [string]$Task.routing_surface } else { "" }
$Message = if ($Task.message) { [string]$Task.message } else { "" }
$SourcePath = if ($Task.source_path) { [string]$Task.source_path } else { "" }

$Decision = "allow"
$Reason = "Default allow."
$RequiresApproval = $false
$HardBlock = $false

$SecretPattern = '(?i)(api[_-]?key|secret|token|password|passwd|private[_-]?key|BEGIN RSA PRIVATE KEY|BEGIN OPENSSH PRIVATE KEY)'

if ($Message -match $SecretPattern -or $SourcePath -match $SecretPattern) {
    $Decision = "blocked"
    $Reason = "Potential secret/API key detected."
    $HardBlock = $true
}

if (-not $HardBlock -and $Category -eq "category_2" -and $RoutingSurface -match "cloud|external") {
    $Decision = "blocked"
    $Reason = "Category 2 cloud/external route is blocked."
    $HardBlock = $true
}

if (-not $HardBlock) {
    foreach ($rule in $Policy.auto_allow) {
        if ($rule.command -eq $Command -and $rule.categories -contains $Category) {
            $Decision = "allow"
            $Reason = $rule.reason
            $RequiresApproval = $false
            break
        }
    }
}

if (-not $HardBlock) {
    if ($Command -eq "/execute") {
        $Decision = "approval_required"
        $Reason = "Execute tasks require human approval."
        $RequiresApproval = $true
    }
    elseif ($Category -eq "category_2") {
        $Decision = "approval_required"
        $Reason = "Category 2 task requires human approval."
        $RequiresApproval = $true
    }
    elseif ($RoutingSurface -match "cloud") {
        $Decision = "approval_required"
        $Reason = "Cloud-capable routing requires operator review."
        $RequiresApproval = $true
    }
}

$Task | Add-Member -NotePropertyName approval_decision -NotePropertyValue $Decision -Force
$Task | Add-Member -NotePropertyName approval_reason -NotePropertyValue $Reason -Force
$Task | Add-Member -NotePropertyName approval_checked_at -NotePropertyValue (Get-Date).ToString("s") -Force

$Log = [pscustomobject]@{
    task_id = $TaskId
    command = $Command
    category = $Category
    routing_surface = $RoutingSurface
    decision = $Decision
    reason = $Reason
    checked_at = (Get-Date).ToString("s")
    task_path = $TaskPath
}

$LogPath = Join-Path $LogDir "$TaskId-approval.json"
$Log | ConvertTo-Json -Depth 8 | Set-Content $LogPath -Encoding UTF8

if ($Decision -eq "blocked") {
    $Dest = Join-Path $RejectedDir (Split-Path $TaskPath -Leaf)
    $Task | ConvertTo-Json -Depth 12 | Set-Content $Dest -Encoding UTF8
    Write-Host "[BLOCKED] $Reason"
    Write-Host $Dest
    exit 2
}

if ($Decision -eq "approval_required") {
    $Dest = Join-Path $PendingApprovalDir (Split-Path $TaskPath -Leaf)
    $Task | ConvertTo-Json -Depth 12 | Set-Content $Dest -Encoding UTF8
    Write-Host "[APPROVAL REQUIRED] $Reason"
    Write-Host $Dest
    exit 3
}

Write-Host "[ALLOWED] $Reason"
Write-Host "[OK] Approval log: $LogPath"
exit 0
