[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$InvokeScript = Join-Path $PSScriptRoot "Invoke-PDAModel.ps1"
$PolicyPath = Join-Path $PSScriptRoot "PDA_ModelRouting.json"
$TempRoot = Join-Path $Root "tmp\model-fallback-validation"

if (-not (Test-Path -Path $InvokeScript -PathType Leaf)) {
    throw "Model invocation adapter missing: $InvokeScript"
}
if (-not (Test-Path -Path $PolicyPath -PathType Leaf)) {
    throw "Model routing policy missing: $PolicyPath"
}

function ConvertTo-PDAHashtable {
    param([Parameter(Mandatory = $true)]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [hashtable] -or $Value -is [System.Collections.IDictionary]) {
        $Copy = @{}
        foreach ($Key in $Value.Keys) {
            if ($null -eq $Value[$Key]) {
                $Copy[$Key] = $null
            }
            else {
                $Copy[$Key] = ConvertTo-PDAHashtable -Value $Value[$Key]
            }
        }
        return $Copy
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $List = @()
        foreach ($Item in $Value) {
            if ($null -eq $Item) {
                $List += $null
            }
            else {
                $List += ,(ConvertTo-PDAHashtable -Value $Item)
            }
        }
        return $List
    }

    if ($Value -is [psobject] -and $Value.PSObject.Properties.Name.Count -gt 0) {
        $Copy = @{}
        foreach ($Prop in $Value.PSObject.Properties) {
            if ($null -eq $Prop.Value) {
                $Copy[$Prop.Name] = $null
            }
            else {
                $Copy[$Prop.Name] = ConvertTo-PDAHashtable -Value $Prop.Value
            }
        }
        return $Copy
    }

    return $Value
}

function Invoke-Adapter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkerName,

        [Parameter(Mandatory = $false)]
        [string]$TaskType,

        [Parameter(Mandatory = $true)]
        [string]$Sensitivity,

        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter(Mandatory = $false)]
        [string]$PolicyPathOverride,

        [Parameter(Mandatory = $false)]
        [string]$Endpoint
    )

    $Args = @(
        "-WorkerName", $WorkerName,
        "-Sensitivity", $Sensitivity,
        "-Prompt", $Prompt,
        "-NoThrow",
        "-AsJson"
    )
    if (-not [string]::IsNullOrWhiteSpace($TaskType)) {
        $Args += @("-TaskType", $TaskType)
    }
    if (-not [string]::IsNullOrWhiteSpace($PolicyPathOverride)) {
        $Args += @("-PolicyPath", $PolicyPathOverride)
    }
    if (-not [string]::IsNullOrWhiteSpace($Endpoint)) {
        $Args += @("-Endpoint", $Endpoint)
    }

    $Raw = & pwsh -NoProfile -File $InvokeScript @Args 2>&1
    $Text = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Adapter returned empty output."
    }

    $Match = [regex]::Match($Text, '(?m)^\{')
    if (-not $Match.Success) {
        throw "Adapter output did not contain JSON."
    }

    $JsonText = $Text.Substring($Match.Index).Trim()
    return $JsonText | ConvertFrom-Json -ErrorAction Stop
}

New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$Issues = New-Object System.Collections.Generic.List[string]

function New-PolicyPath {
    param([Parameter(Mandatory = $true)][object]$PolicyObject)

    $PolicyCopyPath = Join-Path $TempRoot ("policy-{0}.json" -f ([guid]::NewGuid().ToString()))
    $PolicyObject | ConvertTo-Json -Depth 20 | Set-Content -Path $PolicyCopyPath -Encoding UTF8
    return $PolicyCopyPath
}

$BasePolicy = Get-Content -Path $PolicyPath -Raw | ConvertFrom-Json

$DraftPolicy = ConvertTo-PDAHashtable -Value $BasePolicy
if ($DraftPolicy.command_routes."/draft") {
    $DraftPolicy.command_routes."/draft".primary_model = "no-such-model"
    $DraftPolicy.command_routes."/draft".fallback_chain = @("openai")
}
$DraftPolicyPath = New-PolicyPath -PolicyObject $DraftPolicy

$DraftResult = $null
try {
    $DraftResult = Invoke-Adapter -WorkerName "draft-worker" -TaskType "draft" -Sensitivity "standard" -Prompt "Return exactly: draft-fallback-ok" -PolicyPathOverride $DraftPolicyPath
}
catch {
    $Issues.Add("Draft fallback test threw unexpectedly: $($_.Exception.Message)")
}

if (-not $DraftResult) {
    $Issues.Add("Draft fallback test did not return a result.")
}
else {
    if ($DraftResult.status -ne "pass") {
        $Issues.Add("Draft fallback test should pass.")
    }
    if ([string]$DraftResult.response_text -notmatch 'draft-fallback-ok') {
        $Issues.Add("Draft fallback response text did not contain the expected token.")
    }
    if (-not $DraftResult.fallback.allowed) {
        $Issues.Add("Draft fallback should be allowed.")
    }
    if (-not $DraftResult.fallback.used) {
        $Issues.Add("Draft fallback should be used when the first transport fails.")
    }
    if ([int]$DraftResult.fallback.attempt_count -lt 2) {
        $Issues.Add("Draft fallback should record multiple attempts.")
    }
    if ([string]$DraftResult.routing.requested_model -ne "no-such-model") {
        $Issues.Add("Draft fallback should preserve the original requested model.")
    }
    if ([string]$DraftResult.routing.selected_model -ne "openai") {
        $Issues.Add("Draft fallback should settle on the approved fallback model.")
    }
    if ([string]$DraftResult.routing.transport_model -ne "openai") {
        $Issues.Add("Draft fallback transport should resolve to openai.")
    }
}

$ResearchPolicy = ConvertTo-PDAHashtable -Value $BasePolicy
if ($ResearchPolicy.command_routes."/research") {
    $ResearchPolicy.command_routes."/research".primary_model = "no-such-model"
    $ResearchPolicy.command_routes."/research".fallback_chain = @("gemini")
}
$ResearchPolicyPath = New-PolicyPath -PolicyObject $ResearchPolicy

$ResearchResult = $null
try {
    $ResearchResult = Invoke-Adapter -WorkerName "research-worker" -TaskType "research" -Sensitivity "standard" -Prompt "Return exactly: research-fallback-ok" -PolicyPathOverride $ResearchPolicyPath
}
catch {
    $Issues.Add("Research fallback test threw unexpectedly: $($_.Exception.Message)")
}

if (-not $ResearchResult) {
    $Issues.Add("Research fallback test did not return a result.")
}
else {
    if ($ResearchResult.status -ne "pass") {
        $Issues.Add("Research fallback test should pass.")
    }
    if ([string]$ResearchResult.response_text -notmatch 'research-fallback-ok') {
        $Issues.Add("Research fallback response text did not contain the expected token.")
    }
    if (-not $ResearchResult.fallback.allowed) {
        $Issues.Add("Research fallback should be allowed.")
    }
    if (-not $ResearchResult.fallback.used) {
        $Issues.Add("Research fallback should be used when the first transport fails.")
    }
    if ([int]$ResearchResult.fallback.attempt_count -lt 2) {
        $Issues.Add("Research fallback should record multiple attempts.")
    }
    if ([string]$ResearchResult.routing.requested_model -ne "no-such-model") {
        $Issues.Add("Research fallback should preserve the original requested model.")
    }
    if ([string]$ResearchResult.routing.selected_model -ne "gemini") {
        $Issues.Add("Research fallback should settle on the approved fallback model.")
    }
    if ([string]$ResearchResult.routing.transport_model -ne "gemini") {
        $Issues.Add("Research fallback transport should resolve to gemini.")
    }
}

$RestrictedResult = $null
try {
    $RestrictedResult = Invoke-Adapter -WorkerName "review-worker" -TaskType "review" -Sensitivity "restricted_local" -Prompt "Return exactly: local-only-ok" -Endpoint "http://localhost:59999/v1/chat/completions"
}
catch {
    $Issues.Add("Restricted-local fallback test threw unexpectedly: $($_.Exception.Message)")
}

if (-not $RestrictedResult) {
    $Issues.Add("Restricted-local fallback test did not return a result.")
}
else {
    if ($RestrictedResult.status -ne "fail") {
        $Issues.Add("Restricted-local fallback should fail when the local transport is unavailable.")
    }
    if ($RestrictedResult.fallback.allowed -ne $false) {
        $Issues.Add("Restricted-local fallback should not be allowed.")
    }
    if ($RestrictedResult.fallback.used -ne $false) {
        $Issues.Add("Restricted-local fallback should not fall back to cloud.")
    }
    if ([int]$RestrictedResult.fallback.attempt_count -ne 1) {
        $Issues.Add("Restricted-local fallback should only attempt the local route once.")
    }
    if ([string]$RestrictedResult.routing.selected_model -ne "local-llama") {
        $Issues.Add("Restricted-local routing should remain on local-llama.")
    }
}

$Report = [pscustomobject]@{
    status = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
    invoke_script = $InvokeScript
    policy_path = $PolicyPath
    test_case_count = 3
    passed_count = if ($Issues.Count -eq 0) { 3 } else { 0 }
    failed_count = if ($Issues.Count -eq 0) { 0 } else { 1 }
    draft_result = if ($DraftResult) { $DraftResult } else { $null }
    research_result = if ($ResearchResult) { $ResearchResult } else { $null }
    restricted_result = if ($RestrictedResult) { $RestrictedResult } else { $null }
    issues = @($Issues)
}

if ($AsJson) {
    $Report | ConvertTo-Json -Depth 20
    if (-not $NoThrow -and $Report.status -ne "pass") {
        throw "PDA model fallback validation failed."
    }
    return
}

Write-Host "[*] PDA model fallback tests"
Write-Host ("Test cases : {0}" -f $Report.test_case_count)
Write-Host ("Passed     : {0}" -f $Report.passed_count)
Write-Host ("Failed     : {0}" -f $Report.failed_count)

if (-not $NoThrow -and $Report.status -ne "pass") {
    throw "PDA model fallback validation failed."
}
