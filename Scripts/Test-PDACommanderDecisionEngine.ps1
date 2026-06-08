[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$EngineScript = Join-Path $PSScriptRoot "PDA_DecisionEngine.ps1"
if (-not (Test-Path -LiteralPath $EngineScript -PathType Leaf)) {
    throw "Decision engine missing: $EngineScript"
}
. $EngineScript

function Assert-PDACondition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][System.Collections.Generic.List[string]]$Issues
    )

    if (-not $Condition -and $Issues) {
        $Issues.Add($Message)
    }

    return $Condition
}

$Issues = New-Object System.Collections.Generic.List[string]
$Cases = @(
    [pscustomobject]@{
        name = "direct answer"
        text = "How is PDA doing?"
        category = "category_1"
        expected_decision_type = "direct_answer"
        expected_route_type = "direct_status"
        expected_requires_local_only = $false
        expected_dispatch_ready = $false
    },
    [pscustomobject]@{
        name = "clarify"
        text = "Can you review and run this?"
        category = "category_1"
        expected_decision_type = "clarify"
        expected_route_type = "ambiguous"
        expected_requires_local_only = $false
        expected_dispatch_ready = $false
    },
    [pscustomobject]@{
        name = "plan"
        text = "Scan my filesystem and recommend a better project structure."
        category = "category_1"
        expected_decision_type = "plan"
        expected_route_type = "goal_planning"
        expected_requires_local_only = $false
        expected_dispatch_ready = $false
    },
    [pscustomobject]@{
        name = "recommend workflow"
        text = "Show my repositories and running services."
        category = "category_1"
        expected_decision_type = "recommend_workflow"
        expected_route_type = "environment_awareness"
        expected_requires_local_only = $false
        expected_dispatch_ready = $false
    },
    [pscustomobject]@{
        name = "dispatch worker"
        text = "/research Evaluate the latest findings."
        category = "category_1"
        expected_decision_type = "dispatch_worker"
        expected_route_type = "governed_request"
        expected_requires_local_only = $false
        expected_dispatch_ready = $true
    },
    [pscustomobject]@{
        name = "dispatch n8n"
        text = "Automate a recurring sync workflow."
        category = "category_1"
        expected_decision_type = "dispatch_n8n"
        expected_route_type = "governed_request"
        expected_requires_local_only = $false
        expected_dispatch_ready = $true
    },
    [pscustomobject]@{
        name = "restricted local"
        text = "Automate a recurring sync workflow."
        category = "category_2"
        expected_decision_type = "restricted_local"
        expected_route_type = "governed_request"
        expected_requires_local_only = $true
        expected_dispatch_ready = $true
    }
)

$Results = New-Object System.Collections.Generic.List[object]
foreach ($Case in $Cases) {
    $Decision = New-PDACommanderDecision -Text $Case.text -Category $Case.category -Root $PSScriptRoot
    $Results.Add($Decision) | Out-Null

    Assert-PDACondition -Condition ($Decision.PSObject.Properties.Name -contains "decision_type") -Message "Decision object missing decision_type for $($Case.name)." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ($Decision.PSObject.Properties.Name -contains "route_type") -Message "Decision object missing route_type for $($Case.name)." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ($Decision.PSObject.Properties.Name -contains "intent") -Message "Decision object missing intent for $($Case.name)." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ($Decision.PSObject.Properties.Name -contains "recommended_command") -Message "Decision object missing recommended_command for $($Case.name)." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ($Decision.PSObject.Properties.Name -contains "recommended_executor") -Message "Decision object missing recommended_executor for $($Case.name)." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ($Decision.PSObject.Properties.Name -contains "requires_confirmation") -Message "Decision object missing requires_confirmation for $($Case.name)." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ($Decision.PSObject.Properties.Name -contains "dispatch_ready") -Message "Decision object missing dispatch_ready for $($Case.name)." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ($Decision.PSObject.Properties.Name -contains "dispatch_status") -Message "Decision object missing dispatch_status for $($Case.name)." -Issues $Issues | Out-Null

    Assert-PDACondition -Condition ([string]$Decision.decision_type -eq [string]$Case.expected_decision_type) -Message "Unexpected decision_type for $($Case.name)." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ([string]$Decision.route_type -eq [string]$Case.expected_route_type) -Message "Unexpected route_type for $($Case.name)." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ([bool]$Decision.governance.requires_local_only -eq [bool]$Case.expected_requires_local_only) -Message "Unexpected requires_local_only for $($Case.name)." -Issues $Issues | Out-Null
    Assert-PDACondition -Condition ([bool]$Decision.dispatch_ready -eq [bool]$Case.expected_dispatch_ready) -Message "Unexpected dispatch_ready for $($Case.name)." -Issues $Issues | Out-Null

    if ($Case.expected_decision_type -eq "restricted_local") {
        Assert-PDACondition -Condition ($Decision.recommended_executor -notin @("n8n", "gemini-cli")) -Message "Restricted-local decision should not recommend cloud/n8n execution." -Issues $Issues | Out-Null
    }
}

$ResultStatus = "fail"
if ($Issues.Count -eq 0) {
    $ResultStatus = "pass"
}
$CaseResults = @($Results.ToArray())
$IssueList = @($Issues.ToArray())
$Report = [pscustomobject]@{
    status = $ResultStatus
    cases = $CaseResults
    issues = $IssueList
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 30
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA commander decision engine validation failed."
    }
    return
}

Write-Host "[*] PDA commander decision engine tests"
Write-Host ("Status     : {0}" -f $Report.status)
Write-Host ("Issues     : {0}" -f @($Report.issues).Count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA commander decision engine validation failed."
}
