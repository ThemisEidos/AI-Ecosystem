[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Get-ScriptDirectory {
    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return Split-Path -Parent $PSCommandPath
    }
    if (-not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
        return Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    return (Get-Location).Path
}

$Root = Get-ScriptDirectory
$WriterPath = Join-Path $Root "Write-COOPERWorkflowEvidence.ps1"
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("COOPER_WorkflowEvidenceWriter_{0}" -f ([guid]::NewGuid().ToString('N')))

$Issues = New-Object System.Collections.Generic.List[string]

function Add-Issue {
    param([Parameter(Mandatory = $true)][string]$Message)

    [void]$Issues.Add($Message)
}

function Invoke-Writer {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Arguments
    )

    try {
        return & $WriterPath @Arguments
    }
    catch {
        return [pscustomobject]@{
            failed = $true
            message = $_.Exception.Message
        }
    }
}

function Test-Iso8601Utc {
    param([Parameter(Mandatory = $true)][string]$Value)

    return $Value -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$'
}

function Read-JsonRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    try {
        $Raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        return [pscustomobject]@{
            raw = $Raw
            record = ($Raw | ConvertFrom-Json -ErrorAction Stop)
        }
    }
    catch {
        Add-Issue "Generated JSON could not be parsed: $Path"
        return $null
    }
}

function Assert-JsonUtcField {
    param(
        [Parameter(Mandatory = $true)][string]$RawText,
        [Parameter(Mandatory = $true)][string]$FieldName,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $Pattern = '(?ms)"' + [regex]::Escape($FieldName) + '"\s*:\s*"(?<value>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)"'
    if ($RawText -notmatch $Pattern) {
        Add-Issue "$FieldName is not ISO 8601 UTC in JSON text: $Path"
    }
}

function Assert-FileMatchesPattern {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ($FileName -notmatch $Pattern) {
        Add-Issue "Filename pattern mismatch: $Path"
    }
}

function Assert-RequiredFields {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][string[]]$Fields,
        [Parameter(Mandatory = $true)][string]$Path
    )

    foreach ($Field in $Fields) {
        if ($Record.PSObject.Properties.Name -notcontains $Field) {
            Add-Issue "Missing required field '$Field': $Path"
        }
    }
}

function Assert-PathPrefix {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Prefix,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $PathText = ([System.IO.Path]::GetFullPath($Path)).Replace('/', '\')
    $PrefixText = ([System.IO.Path]::GetFullPath($Prefix)).TrimEnd('\').Replace('/', '\') + '\'
    if (-not $PathText.StartsWith($PrefixText, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Issue "$Label path escaped its expected boundary: $Path"
    }
}

function Expect-Failure {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$ExpectedFragment
    )

    $Result = Invoke-Writer -Arguments $Arguments
    if (-not $Result.failed) {
        Add-Issue "$Label should have failed."
        return
    }
    if ($Result.message -notmatch [regex]::Escape($ExpectedFragment)) {
        Add-Issue "$Label did not report the expected error fragment: $ExpectedFragment"
    }
}

if (-not (Test-Path -LiteralPath $WriterPath -PathType Leaf)) {
    throw "Workflow evidence writer is missing: $WriterPath"
}

New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

try {
    $OpenCompletionResult = Invoke-Writer -Arguments @{
        Root = $TempRoot
        RecordType = 'completion'
        WorkshopId = 'open'
        WorkflowId = 'WF-002'
        WorkflowName = 'Codex Task Generator'
        ExecutionId = '20260622T010000Z-writer-open'
        Status = 'pass'
        CompletionTime = '2026-06-22T01:00:00Z'
        ApprovalId = ''
        ArtifactPaths = @('Codex_Tasks/TASK-001/Output/task.md')
        ReviewStatus = 'pass'
        UserAccepted = $true
        Notes = 'Open workshop completion record written by the writer test.'
    }

    $OpenCompletionBundle = Read-JsonRecord -Path $OpenCompletionResult.path
    if ($null -ne $OpenCompletionBundle) {
        $OpenCompletion = $OpenCompletionBundle.record
        Assert-RequiredFields -Record $OpenCompletion -Fields @(
            'workflow_id',
            'workflow_name',
            'execution_id',
            'status',
            'completion_time',
            'workshop_id',
            'workshop_name',
            'approval_id',
            'artifact_paths',
            'review_status',
            'user_accepted',
            'notes'
        ) -Path $OpenCompletionResult.path
        Assert-FileMatchesPattern -FileName (Split-Path -Leaf $OpenCompletionResult.path) -Pattern '^workflow_completion_WF-\d+_[A-Za-z0-9._-]+\.json$' -Path $OpenCompletionResult.path
        Assert-PathPrefix -Path $OpenCompletionResult.path -Prefix (Join-Path $TempRoot 'State\Workflow_Evidence\completion') -Label 'Open completion'
        if ($OpenCompletion.status -ne 'pass' -or $OpenCompletion.review_status -ne 'pass') {
            Add-Issue "Open completion record did not preserve the expected status values."
        }
        if ($OpenCompletion.workshop_id -ne 'open' -or $OpenCompletion.workshop_name -ne 'Open Workshop') {
            Add-Issue "Open completion record did not preserve workshop metadata."
        }
        Assert-JsonUtcField -RawText $OpenCompletionBundle.raw -FieldName 'completion_time' -Path $OpenCompletionResult.path
    }

    $PrivateApprovalResult = Invoke-Writer -Arguments @{
        Root = $TempRoot
        RecordType = 'approval'
        WorkshopId = 'private'
        ApprovalId = 'AP-20260622-010001'
        WorkflowId = 'WF-007'
        Status = 'approved'
        RequestedTime = '2026-06-22T01:05:00Z'
        ApprovedTime = '2026-06-22T01:06:00Z'
        CompletedTime = '2026-06-22T01:07:00Z'
        BlockedTime = $null
        StaleTime = $null
        ExpirationTime = '2026-07-22T01:05:00Z'
        Reason = 'Private analysis approval lifecycle record.'
        Notes = 'Private workshop approval record written by the writer test.'
        RelatedExecutionId = '20260622T010001Z-private'
        ArtifactPaths = @('Restricted DMZ Workspace/State/Workflow_Evidence/completion/workflow_completion_WF-007_20260622T010001Z-private.json')
    }

    $PrivateApprovalBundle = Read-JsonRecord -Path $PrivateApprovalResult.path
    if ($null -ne $PrivateApprovalBundle) {
        $PrivateApproval = $PrivateApprovalBundle.record
        Assert-RequiredFields -Record $PrivateApproval -Fields @(
            'approval_id',
            'workflow_id',
            'status',
            'requested_time',
            'approved_time',
            'completed_time',
            'blocked_time',
            'stale_time',
            'expiration_time',
            'reason',
            'notes'
        ) -Path $PrivateApprovalResult.path
        Assert-FileMatchesPattern -FileName (Split-Path -Leaf $PrivateApprovalResult.path) -Pattern '^approval_lifecycle_[A-Za-z0-9._-]+\.json$' -Path $PrivateApprovalResult.path
        Assert-PathPrefix -Path $PrivateApprovalResult.path -Prefix (Join-Path $TempRoot 'Restricted DMZ Workspace\State\Workflow_Evidence\approval') -Label 'Private approval'
        if ($PrivateApproval.status -ne 'approved') {
            Add-Issue "Private approval record did not preserve the approval status."
        }
        if ($PrivateApproval.workshop_id -ne 'private' -or $PrivateApproval.workshop_name -ne 'Private Workshop') {
            Add-Issue "Private approval record did not preserve workshop metadata."
        }
        foreach ($Field in @('requested_time', 'approved_time', 'completed_time', 'expiration_time')) {
            Assert-JsonUtcField -RawText $PrivateApprovalBundle.raw -FieldName $Field -Path $PrivateApprovalResult.path
        }
    }

    Expect-Failure -Label 'invalid completion status' -ExpectedFragment 'Invalid completion status' -Arguments @{
        Root = $TempRoot
        RecordType = 'completion'
        WorkshopId = 'open'
        WorkflowId = 'WF-002'
        WorkflowName = 'Codex Task Generator'
        ExecutionId = '20260622T010100Z-invalid-status'
        Status = 'pending'
        CompletionTime = '2026-06-22T01:10:00Z'
        ApprovalId = 'AP-20260622-010100'
        ReviewStatus = 'pass'
        UserAccepted = $true
        Notes = 'This record should fail because completion status pending is invalid.'
    }

    Expect-Failure -Label 'invalid workshop' -ExpectedFragment 'Invalid workshop_id' -Arguments @{
        Root = $TempRoot
        RecordType = 'approval'
        WorkshopId = 'shared'
        ApprovalId = 'AP-20260622-010101'
        WorkflowId = 'WF-002'
        Status = 'pending'
        RequestedTime = '2026-06-22T01:11:00Z'
        ApprovedTime = $null
        CompletedTime = $null
        BlockedTime = $null
        StaleTime = $null
        ExpirationTime = '2026-07-22T01:11:00Z'
        Reason = 'Invalid workshop should be rejected.'
        Notes = 'This record should fail because the workshop is invalid.'
    }

    Expect-Failure -Label 'open restricted artifact path' -ExpectedFragment 'compartment boundary' -Arguments @{
        Root = $TempRoot
        RecordType = 'completion'
        WorkshopId = 'open'
        WorkflowId = 'WF-002'
        WorkflowName = 'Codex Task Generator'
        ExecutionId = '20260622T010200Z-open-boundary'
        Status = 'pass'
        CompletionTime = '2026-06-22T01:20:00Z'
        ApprovalId = 'AP-20260622-010200'
        ArtifactPaths = @('Restricted DMZ Workspace/State/Workflow_Evidence/completion/workflow_completion_WF-007_20260622T010200Z-private.json')
        ReviewStatus = 'pass'
        UserAccepted = $true
        Notes = 'This record should fail because the open workshop artifact path points into restricted storage.'
    }

    Expect-Failure -Label 'private external artifact path' -ExpectedFragment 'Private Workshop artifact path must remain inside Restricted DMZ Workspace' -Arguments @{
        Root = $TempRoot
        RecordType = 'completion'
        WorkshopId = 'private'
        WorkflowId = 'WF-007'
        WorkflowName = 'Private Local Analysis'
        ExecutionId = '20260622T010300Z-private-boundary'
        Status = 'pass'
        CompletionTime = '2026-06-22T01:30:00Z'
        ApprovalId = 'AP-20260622-010300'
        ArtifactPaths = @('Outputs/private-summary.md')
        ReviewStatus = 'pass'
        UserAccepted = $true
        Notes = 'This record should fail because the private workshop artifact path escapes the restricted workspace.'
    }

    Expect-Failure -Label 'secret marker rejection' -ExpectedFragment 'Secret marker rejected' -Arguments @{
        Root = $TempRoot
        RecordType = 'completion'
        WorkshopId = 'open'
        WorkflowId = 'WF-002'
        WorkflowName = 'Codex Task Generator'
        ExecutionId = '20260622T010400Z-secret-marker'
        Status = 'pass'
        CompletionTime = '2026-06-22T01:40:00Z'
        ApprovalId = 'AP-20260622-010400'
        ReviewStatus = 'pass'
        UserAccepted = $true
        Notes = 'This record contains api_key and must be rejected.'
    }

    Expect-Failure -Label 'missing required field' -ExpectedFragment 'Missing required field' -Arguments @{
        Root = $TempRoot
        RecordType = 'completion'
        WorkshopId = 'open'
        WorkflowId = 'WF-002'
        WorkflowName = 'Codex Task Generator'
        ExecutionId = '20260622T010500Z-missing-field'
        Status = 'pass'
        CompletionTime = '2026-06-22T01:50:00Z'
        ApprovalId = 'AP-20260622-010500'
        ReviewStatus = 'pass'
        UserAccepted = $true
    }
}
finally {
    if (Test-Path -LiteralPath $TempRoot -PathType Container) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
    }
}

if ($Issues.Count -gt 0) {
    Write-Host "[*] COOPER workflow evidence writer validation"
    Write-Host "Status   : fail"
    foreach ($Issue in @($Issues)) {
        Write-Host ("[FAIL] {0}" -f $Issue)
    }
    exit 1
}

Write-Host "[*] COOPER workflow evidence writer validation"
Write-Host "Status   : pass"
Write-Host "[PASS] Workflow evidence writer validated."
exit 0
