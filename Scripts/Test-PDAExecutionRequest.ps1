[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$NewRequestScript = Join-Path $PSScriptRoot "New-PDAExecutionRequest.ps1"
$GetRequestScript = Join-Path $PSScriptRoot "Get-PDAExecutionRequest.ps1"
$ApprovalWorkflowScript = Join-Path $PSScriptRoot "PDA_ApprovalWorkflow.ps1"
if (Test-Path -LiteralPath $ApprovalWorkflowScript -PathType Leaf) {
    . $ApprovalWorkflowScript
}

function ConvertFrom-PDAMixedJson {
    param([Parameter(Mandatory = $true)][string]$Text)

    $Trimmed = [string]$Text.Trim()
    if ([string]::IsNullOrWhiteSpace($Trimmed)) {
        return $null
    }

    try {
        return $Trimmed | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $Start = $Trimmed.LastIndexOf("{")
        $End = $Trimmed.LastIndexOf("}")
        if ($Start -ge 0 -and $End -gt $Start) {
            $Candidate = $Trimmed.Substring($Start, $End - $Start + 1)
            return $Candidate | ConvertFrom-Json -ErrorAction Stop
        }
        throw
    }
}

function Invoke-NewRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Capability,
        [Parameter(Mandatory = $true)][string]$Agent,
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][string]$Category
    )

    $Raw = & pwsh -NoProfile -File $NewRequestScript -Root $Root -Capability $Capability -Agent $Agent -Provider $Provider -Category $Category -AsJson 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "New-PDAExecutionRequest.ps1 returned empty output."
    }

    return ConvertFrom-PDAMixedJson -Text $Text
}

function Invoke-GetRequest {
    param([Parameter(Mandatory = $false)][string]$RequestId = "")

    $Args = @("-NoProfile", "-File", $GetRequestScript, "-Root", $Root, "-AsJson", "-NoThrow")
    if (-not [string]::IsNullOrWhiteSpace($RequestId)) {
        $Args += @("-RequestId", $RequestId)
    }

    $Raw = & pwsh @Args 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Get-PDAExecutionRequest.ps1 returned empty output."
    }

    return ConvertFrom-PDAMixedJson -Text $Text
}

$Issues = New-Object System.Collections.Generic.List[string]
$Results = @()
$Passed = 0
$Failed = 0

$DraftRequest = $null
$DraftRequestIssues = New-Object System.Collections.Generic.List[string]
try {
    $DraftRequest = Invoke-NewRequest -Capability "report_writing" -Agent "reporting_agent" -Provider "claude" -Category "category_1"
    if ([string]$DraftRequest.status -ne "pass") { $DraftRequestIssues.Add("Draft request did not resolve successfully.") }
    if ([string]$DraftRequest.request_status -ne "draft") { $DraftRequestIssues.Add("Report writing request should be draft because approval is not required.") }
    if ([string]$DraftRequest.approval_status -ne "not_required") { $DraftRequestIssues.Add("Report writing request should mark approval as not required.") }
    if (-not (Test-Path -LiteralPath $DraftRequest.request_path -PathType Leaf)) { $DraftRequestIssues.Add("Draft request file was not created.") }
} catch {
    $DraftRequestIssues.Add("Draft request creation failed: $($_.Exception.Message)")
}
$Results += [pscustomobject]@{
    name = "draft request"
    passed = ($DraftRequestIssues.Count -eq 0)
    request_id = if ($DraftRequest) { [string]$DraftRequest.request_id } else { "" }
    request_status = if ($DraftRequest) { [string]$DraftRequest.request_status } else { "" }
    approval_status = if ($DraftRequest) { [string]$DraftRequest.approval_status } else { "" }
    tool = if ($DraftRequest) { [string]$DraftRequest.tool } else { "" }
    issues = @($DraftRequestIssues)
}
if ($DraftRequestIssues.Count -eq 0) { $Passed++ } else { $Failed++ ; foreach ($Issue in $DraftRequestIssues) { $Issues.Add($Issue) } }

$ApprovalRequest = $null
$ApprovalRequestIssues = New-Object System.Collections.Generic.List[string]
try {
    $ApprovalRequest = Invoke-NewRequest -Capability "code_implementation" -Agent "build_agent" -Provider "claude_code" -Category "category_1"
    if ([string]$ApprovalRequest.status -ne "pass") { $ApprovalRequestIssues.Add("Code implementation request did not resolve successfully.") }
    if ([string]$ApprovalRequest.request_status -ne "pending_approval") { $ApprovalRequestIssues.Add("Code implementation request should be pending approval.") }
    if ([string]$ApprovalRequest.approval_status -ne "pending") { $ApprovalRequestIssues.Add("Code implementation request should create a pending approval reference.") }
    if ([string]::IsNullOrWhiteSpace([string]$ApprovalRequest.approval_id)) { $ApprovalRequestIssues.Add("Approval ID was not linked to the execution request.") }
    if (-not (Test-Path -LiteralPath $ApprovalRequest.request_path -PathType Leaf)) { $ApprovalRequestIssues.Add("Pending request file was not created.") }
    $StoredApproval = if (-not [string]::IsNullOrWhiteSpace([string]$ApprovalRequest.approval_id)) { Get-PDAApprovalRequest -ApprovalId ([string]$ApprovalRequest.approval_id) -Root $Root } else { $null }
    if (-not $StoredApproval) { $ApprovalRequestIssues.Add("Linked approval record was not found.") }
} catch {
    $ApprovalRequestIssues.Add("Approval-linked request creation failed: $($_.Exception.Message)")
}
$Results += [pscustomobject]@{
    name = "approval request"
    passed = ($ApprovalRequestIssues.Count -eq 0)
    request_id = if ($ApprovalRequest) { [string]$ApprovalRequest.request_id } else { "" }
    request_status = if ($ApprovalRequest) { [string]$ApprovalRequest.request_status } else { "" }
    approval_status = if ($ApprovalRequest) { [string]$ApprovalRequest.approval_status } else { "" }
    tool = if ($ApprovalRequest) { [string]$ApprovalRequest.tool } else { "" }
    issues = @($ApprovalRequestIssues)
}
if ($ApprovalRequestIssues.Count -eq 0) { $Passed++ } else { $Failed++ ; foreach ($Issue in $ApprovalRequestIssues) { $Issues.Add($Issue) } }

$LocalRequest = $null
$LocalRequestIssues = New-Object System.Collections.Generic.List[string]
try {
    $LocalRequest = Invoke-NewRequest -Capability "local_restricted_analysis" -Agent "restricted_agent" -Provider "local-llama" -Category "category_2"
    if ([string]$LocalRequest.status -ne "pass") { $LocalRequestIssues.Add("Local restricted request did not resolve successfully.") }
    if ([string]$LocalRequest.request_status -ne "pending_approval") { $LocalRequestIssues.Add("Local restricted request should be pending approval.") }
    if (-not [bool]$LocalRequest.request.restricted_local_only) { $LocalRequestIssues.Add("Local restricted request should be marked local-only.") }
    if ([string]$LocalRequest.tool -ne "local_llm") { $LocalRequestIssues.Add("Local restricted request should resolve to local_llm.") }
} catch {
    $LocalRequestIssues.Add("Local restricted request creation failed: $($_.Exception.Message)")
}
$Results += [pscustomobject]@{
    name = "local restricted request"
    passed = ($LocalRequestIssues.Count -eq 0)
    request_id = if ($LocalRequest) { [string]$LocalRequest.request_id } else { "" }
    request_status = if ($LocalRequest) { [string]$LocalRequest.request_status } else { "" }
    approval_status = if ($LocalRequest) { [string]$LocalRequest.approval_status } else { "" }
    tool = if ($LocalRequest) { [string]$LocalRequest.tool } else { "" }
    issues = @($LocalRequestIssues)
}
if ($LocalRequestIssues.Count -eq 0) { $Passed++ } else { $Failed++ ; foreach ($Issue in $LocalRequestIssues) { $Issues.Add($Issue) } }

$Summary = Invoke-GetRequest
if ([string]$Summary.status -notin @("pass", "empty")) {
    $Issues.Add("Execution request summary did not report pass or empty.")
}
if ([int]$Summary.request_count -lt 3) {
    $Issues.Add("Execution request summary should include the created requests.")
}
if ([int]$Summary.pending_approval_count -lt 1) {
    $Issues.Add("Execution request summary should report at least one pending request.")
}

$MissingRaw = & pwsh -NoProfile -File $GetRequestScript -Root $Root -RequestId "missing-request-id" -AsJson -NoThrow 2>&1
$Missing = ConvertFrom-PDAMixedJson -Text ([string]($MissingRaw -join "`n"))
if ([string]$Missing.status -ne "missing") {
    $Issues.Add("Missing execution request should return missing status.")
}

$IssuesText = @($Issues + ($Results | ForEach-Object { $_.issues } | Where-Object { $_ })) | ForEach-Object { $_ } | Select-Object -Unique
$Status = if ($IssuesText.Count -eq 0) { "pass" } else { "fail" }

$Report = [pscustomobject]@{
    status = $Status
    request_count = if ($Summary) { [int]$Summary.request_count } else { 0 }
    pending_approval_count = if ($Summary) { [int]$Summary.pending_approval_count } else { 0 }
    approved_count = if ($Summary) { [int]$Summary.approved_count } else { 0 }
    draft_count = if ($Summary) { [int]$Summary.draft_count } else { 0 }
    failed_count = $Failed
    passed_count = $Passed
    issues = @($IssuesText)
    results = $Results
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 30
    if ($Status -ne "pass" -and -not $NoThrow) { throw "PDA execution request validation failed." }
    return
}

if ($Status -eq "pass") {
    Write-Host "[OK] PDA execution request validation passed."
}
else {
    Write-Host "[ERROR] PDA execution request validation failed."
    foreach ($Issue in $IssuesText) {
        Write-Host (" - {0}" -f $Issue)
    }
    if (-not $NoThrow) { throw "PDA execution request validation failed." }
}
