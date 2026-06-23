[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$RouterScript = Join-Path $PSScriptRoot "COOPER_ConversationalRouter.ps1"
$WorkflowScript = Join-Path $PSScriptRoot "Invoke-COOPERKnowledgeImportDraft.ps1"
$MemoryStatePath = Join-Path $Root "State\COOPER_ProjectMemory.json"
$SkillsStatePath = Join-Path $Root "State\COOPER_Skills.json"
$OriginalMemoryState = if (Test-Path -LiteralPath $MemoryStatePath -PathType Leaf) { Get-Content -LiteralPath $MemoryStatePath -Raw } else { $null }
$OriginalSkillsState = if (Test-Path -LiteralPath $SkillsStatePath -PathType Leaf) { Get-Content -LiteralPath $SkillsStatePath -Raw } else { $null }

. $RouterScript

foreach ($Path in @($MemoryStatePath, $SkillsStatePath)) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Remove-Item -LiteralPath $Path -Force
    }
}

try {
$Request = "Research official Pop!_OS documentation and prepare it for the Linux & Infrastructure knowledge collection."
$Route = Resolve-PDAConversationalRoute -Text $Request -Root $Root
$Result = Get-PDAConversationalNaturalResponse -Route $Route -ConversationId "wf006-conv" -SessionId "wf006-sess" -UserId "wf006-user" -ConversationTitle "WF-006 Test" -Text $Request -Root $Root

$Issues = New-Object System.Collections.Generic.List[string]

if ([string]$Route.route_type -ne "research_summary") {
    $Issues.Add("Combined request did not route to research_summary.")
}

if ($null -eq $Result) {
    $Issues.Add("Router did not return a result.")
}
else {
    if ([string]::IsNullOrWhiteSpace([string]$Result.research_summary_path)) {
        $Issues.Add("Router did not return the research summary path.")
    }
    elseif (-not (Test-Path -LiteralPath $Result.research_summary_path -PathType Leaf)) {
        $Issues.Add("Research summary file does not exist.")
    }

    if ([string]::IsNullOrWhiteSpace([string]$Result.collection_import_path)) {
        $Issues.Add("Router did not return the import draft path.")
    }
    elseif (-not (Test-Path -LiteralPath $Result.collection_import_path -PathType Leaf)) {
        $Issues.Add("Import draft file does not exist.")
    }

    if ($null -eq $Result.workflow_review -or [string]$Result.workflow_review.status -ne "pass") {
        $Issues.Add("WF-001 review did not pass inside the router chain.")
    }

    if ($null -eq $Result.collection_import_result) {
        $Issues.Add("WF-006 result was not returned by the router chain.")
    }
    else {
        if ([bool]$Result.collection_import_result.success -ne $true) {
            $Issues.Add("WF-006 did not succeed.")
        }
        if ($null -eq $Result.collection_import_result.workflow_review -or [string]$Result.collection_import_result.workflow_review.status -ne "pass") {
            $Issues.Add("WF-006 review did not pass.")
        }
        if ($Result.collection_import_result.PSObject.Properties.Name -contains "workspace_import_result") {
            $Issues.Add("WF-006 unexpectedly returned a workspace import payload.")
        }
    }

    if ([string]$Result.response_text -notmatch '(?i)research summary at .* import draft at') {
        $Issues.Add("Completion summary did not mention both artifacts.")
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Result.collection_import_path) -and (Test-Path -LiteralPath $Result.collection_import_path -PathType Leaf)) {
        $DraftContent = Get-Content -LiteralPath $Result.collection_import_path -Raw
        if ($DraftContent -notmatch '(?m)^#\s+Knowledge Collection Import Draft') {
            $Issues.Add("Import draft is missing the title.")
        }
        if ($DraftContent -notmatch '(?m)^##\s+Collection\s*$' -or $DraftContent -notmatch '(?i)Linux & Infrastructure') {
            $Issues.Add("Import draft is missing the collection name.")
        }
        if ($DraftContent -notmatch '(?m)^##\s+Source Research Artifact\s*$') {
            $Issues.Add("Import draft is missing the source research artifact section.")
        }
        if ($DraftContent -notmatch '(?m)^##\s+Import Status\s*$') {
            $Issues.Add("Import draft is missing the import status section.")
        }
        if ($DraftContent -notmatch '(?i)Draft only\. Not imported\.' -and $DraftContent -notmatch '(?i)not imported') {
            $Issues.Add("Import draft is missing the draft-only status.")
        }
        if ($DraftContent -notmatch '(?i)Source URL:') {
            $Issues.Add("Import draft is missing source URLs.")
        }
        if ($DraftContent -match '(?i)Open WebUI Workspace import|imported into workspace|automatic import occurred') {
            $Issues.Add("Import draft suggests a workspace import occurred.")
        }
    }
}

if (-not (Test-Path -LiteralPath $MemoryStatePath -PathType Leaf)) {
    $Issues.Add("Project memory state file was not written.")
}
else {
    $MemoryState = Get-Content -LiteralPath $MemoryStatePath -Raw | ConvertFrom-Json
    $OperationalWorkflows = @($MemoryState.operational_workflows | ForEach-Object { [string]$_ })
    if ($OperationalWorkflows -notcontains "WF-006") {
        $Issues.Add("Project memory did not mark WF-006 as operational.")
    }
}

if (-not (Test-Path -LiteralPath $SkillsStatePath -PathType Leaf)) {
    $Issues.Add("Skills state file was not written.")
}
else {
    $SkillsState = Get-Content -LiteralPath $SkillsStatePath -Raw | ConvertFrom-Json
    $WF006Skill = @($SkillsState.skills | Where-Object { [string]$_.workflow_id -eq "WF-006" } | Select-Object -First 1)
    if ($WF006Skill.Count -eq 0) {
        $Issues.Add("WF-006 skill entry was not recorded.")
    }
    elseif ([string]$WF006Skill[0].status -ne "operational") {
        $Issues.Add("WF-006 skill was not promoted to operational.")
    }
}

$ResearchFailResult = [pscustomobject]@{
    status = "fail"
    review_passed = $false
    issues = @("WF-001 review failed.")
}
$FailedImport = & $WorkflowScript -RequestText $Request -ResearchResult ([pscustomobject]@{ saved_path = "C:\temp\wf-001.md"; output = [pscustomobject]@{ sources = @() } }) -ResearchReview $ResearchFailResult -Approved -Root $Root

if ([bool]$FailedImport.success -ne $false) {
    $Issues.Add("WF-006 should not run when WF-001 review fails.")
}
if (-not [string]::IsNullOrWhiteSpace([string]$FailedImport.import_draft_path)) {
    $Issues.Add("WF-006 should not create an import draft when WF-001 fails.")
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    route_type = [string]$Route.route_type
    response = $Result
    failed_import = $FailedImport
    issues = @($Issues)
}
}
finally {
    if ($null -ne $OriginalMemoryState) {
        Set-Content -LiteralPath $MemoryStatePath -Value $OriginalMemoryState -Encoding UTF8
    }
    elseif (Test-Path -LiteralPath $MemoryStatePath -PathType Leaf) {
        Remove-Item -LiteralPath $MemoryStatePath -Force
    }

    if ($null -ne $OriginalSkillsState) {
        Set-Content -LiteralPath $SkillsStatePath -Value $OriginalSkillsState -Encoding UTF8
    }
    elseif (Test-Path -LiteralPath $SkillsStatePath -PathType Leaf) {
        Remove-Item -LiteralPath $SkillsStatePath -Force
    }
}

Write-Host "[*] COOPER knowledge collection import workflow test"
Write-Host ("Status   : {0}" -f $Report.status)
Write-Host ("Route    : {0}" -f $Report.route_type)

if ($Report.status -ne "pass") {
    foreach ($Issue in @($Report.issues)) {
        Write-Host ("[FAIL] {0}" -f $Issue)
    }
    exit 1
}

Write-Host "[PASS] WF-006 knowledge collection import workflow validated."
exit 0
