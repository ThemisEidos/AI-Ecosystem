[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ChatBridgeScript = Join-Path $PSScriptRoot "Invoke-PDAChatBridge.ps1"
$TaskResultScript = Join-Path $PSScriptRoot "Get-PDATaskResult.ps1"
. (Join-Path $PSScriptRoot "PDA_OutputParsing.ps1")

function Get-PDASlug {
    param([Parameter(Mandatory = $true)][string]$Text)

    $Slug = [string]$Text.Trim().ToLowerInvariant()
    $Slug = $Slug -replace '[^a-z0-9]+', '-'
    $Slug = $Slug -replace '-+', '-'
    $Slug = $Slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($Slug)) {
        return "package"
    }

    return $Slug
}

function Assert-PathExists {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][object]$Issues
    )

    if ($Issues -isnot [System.Collections.Generic.List[string]]) {
        throw "Issues collector must be a generic string list."
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            $Issues.Add("$Label missing: $Path")
        }
    }
}

function Get-PDANormalizedPath {
    param([Parameter(Mandatory = $false)]$Value)

    return ([string]$Value).Trim()
}

$Issues = New-Object System.Collections.Generic.List[string]
$CleanupPaths = New-Object System.Collections.Generic.List[string]
$ConversationId = "notebooklm-test-{0}" -f ([guid]::NewGuid().ToString())
$SessionId = "notebooklm-session-{0}" -f ([guid]::NewGuid().ToString())
$ConversationTitle = "NotebookLM Command Test"

$Source1 = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\NotebookLM\NotebookLM-Integration-Guide.md"
$Source2 = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\NotebookLM\NotebookLM-Sanitization-Checklist.md"

$Message = @"
/notebooklm
LearningArea: Research
Topic: NotebookLM Command Integration Test
SourcePaths:
- $Source1
- $Source2
Summary:
Sanitized NotebookLM package generated for command workflow validation.
Questions:
- What are the primary steps?
- Which files are safe to upload?
- What should be captured in Obsidian?
"@

try {
    if (-not (Test-Path -Path $ChatBridgeScript -PathType Leaf)) {
        throw "Chat bridge script missing: $ChatBridgeScript"
    }
    if (-not (Test-Path -Path $TaskResultScript -PathType Leaf)) {
        throw "Task result script missing: $TaskResultScript"
    }

    $Raw = & pwsh -NoProfile -File $ChatBridgeScript -Message $Message -ConfirmDispatch -ConversationId $ConversationId -SessionId $SessionId -UserId "notebooklm-test" -ConversationTitle $ConversationTitle -AsJson 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "NotebookLM chat bridge invocation failed with exit code $LASTEXITCODE"
    }

    $JsonText = [string]($Raw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        throw "NotebookLM chat bridge returned no JSON."
    }

    $Bridge = ConvertFrom-PDAMixedJson -Text $JsonText -SourceName "NotebookLM chat bridge"
    if ([string]$Bridge.recommended_command -ne "/notebooklm") {
        $Issues.Add("Expected /notebooklm but received '$($Bridge.recommended_command)'.")
    }
    if ([string]$Bridge.dispatch_status -ne "completed") {
        $Issues.Add("Expected completed dispatch but received '$($Bridge.dispatch_status)'.")
    }
    if ([string]$Bridge.bridge_status -ne "completed") {
        $Issues.Add("Expected completed bridge status but received '$($Bridge.bridge_status)'.")
    }

    $TaskResultRaw = & pwsh -NoProfile -File $TaskResultScript -ConversationId $ConversationId -SessionId $SessionId -AsJson 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Task result lookup failed with exit code $LASTEXITCODE"
    }

    $TaskResultText = [string]($TaskResultRaw -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($TaskResultText)) {
        throw "Task result lookup returned no JSON."
    }

    $TaskResult = ConvertFrom-PDAMixedJson -Text $TaskResultText -SourceName "NotebookLM task result"
    if ([string]$TaskResult.latest_task.command -ne "/notebooklm") {
        $Issues.Add("Task result lookup did not report /notebooklm.")
    }
    if ([string]$TaskResult.latest_task_status -ne "completed") {
        $Issues.Add("Task result lookup did not report completed status.")
    }
    if ([string]::IsNullOrWhiteSpace([string]$TaskResult.latest_result_path)) {
        $Issues.Add("Task result lookup did not report a result path.")
    }

    $ResultArtifactPath = ""
    foreach ($Path in @([string]$TaskResult.latest_result_path, [string]$Bridge.latest_result_path, [string]$Bridge.result_artifact_path)) {
        $NormalizedPath = Get-PDANormalizedPath -Value $Path
        if (-not [string]::IsNullOrWhiteSpace($NormalizedPath) -and (Test-Path -LiteralPath $NormalizedPath -PathType Leaf)) {
            $ResultArtifactPath = $NormalizedPath
            $CleanupPaths.Add($NormalizedPath) | Out-Null
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($ResultArtifactPath)) {
        $Issues.Add("NotebookLM result artifact was not found.")
    }
    else {
        try {
            $DispatchResult = ConvertFrom-PDAMixedJson -Text (Get-Content -LiteralPath $ResultArtifactPath -Raw) -SourceName $ResultArtifactPath
            if ([string]::IsNullOrWhiteSpace([string]$DispatchResult.package_path)) {
                $Issues.Add("Package path was missing from the NotebookLM result artifact.")
            }
            else {
                $CleanupPaths.Add([string]$DispatchResult.package_path) | Out-Null
            }

            foreach ($Path in @(
                [string]$DispatchResult.package_path,
                [string]$DispatchResult.manifest_path,
                [string]$DispatchResult.package_summary_path,
                [string]$DispatchResult.questions_path,
                [string]$DispatchResult.result_path,
                [string]$DispatchResult.result_report_path
            )) {
                if (-not [string]::IsNullOrWhiteSpace($Path)) {
                    $CleanupPaths.Add($Path) | Out-Null
                }
            }

            $DispatchResultResultPath = Get-PDANormalizedPath -Value $DispatchResult.result_path
            $DispatchResultPackagePath = Get-PDANormalizedPath -Value $DispatchResult.package_path
            $DispatchResultManifestPath = Get-PDANormalizedPath -Value $DispatchResult.manifest_path
            $DispatchResultSummaryPath = Get-PDANormalizedPath -Value $DispatchResult.package_summary_path
            $DispatchResultQuestionsPath = Get-PDANormalizedPath -Value $DispatchResult.questions_path
            $DispatchResultReportPath = Get-PDANormalizedPath -Value $DispatchResult.result_report_path

            if ([string]::IsNullOrWhiteSpace($DispatchResultResultPath)) {
                $Issues.Add("Result path was missing from the NotebookLM result artifact.")
            }
            elseif (-not (Test-Path -LiteralPath $DispatchResultResultPath -PathType Leaf)) {
                $Issues.Add("Result file does not exist: $DispatchResultResultPath")
            }

            Assert-PathExists -Path $DispatchResultPackagePath -Label "Package folder" -Issues $Issues
            Assert-PathExists -Path $DispatchResultManifestPath -Label "Manifest" -Issues $Issues
            Assert-PathExists -Path $DispatchResultSummaryPath -Label "Summary" -Issues $Issues
            Assert-PathExists -Path $DispatchResultQuestionsPath -Label "Questions" -Issues $Issues

            foreach ($Child in @("manifest.json", "summary.md", "questions.md")) {
                $ChildPath = Join-Path $DispatchResultPackagePath $Child
                if (-not (Test-Path -LiteralPath $ChildPath -PathType Leaf)) {
                    $Issues.Add("Expected package file missing: $ChildPath")
                }
            }

            $SourceFolder = Join-Path $DispatchResultPackagePath "sources"
            if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
                $Issues.Add("Sources folder missing: $SourceFolder")
            }
        }
        catch {
            $Issues.Add("Failed to parse NotebookLM result artifact JSON: $($_.Exception.Message)")
        }
    }

    $Result = [pscustomobject]@{
        status            = if ($Issues.Count -eq 0) { "pass" } else { "fail" }
        issues            = @($Issues)
        command           = "/notebooklm"
        recommended_command = [string]$Bridge.recommended_command
        dispatch_status   = [string]$Bridge.dispatch_status
        bridge_status     = [string]$Bridge.bridge_status
        latest_task_id    = [string]$TaskResult.latest_task_id
        latest_task_status = [string]$TaskResult.latest_task_status
        latest_result_path = [string]$TaskResult.latest_result_path
        package_path      = if ($DispatchResult) { [string]$DispatchResult.package_path } else { "" }
        conversation_id   = $ConversationId
        session_id        = $SessionId
    }

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
    }
    else {
        Write-Host "[OK] NotebookLM command test"
        Write-Host ("Status           : {0}" -f $Result.status)
        Write-Host ("Dispatch status  : {0}" -f $Result.dispatch_status)
        Write-Host ("Bridge status    : {0}" -f $Result.bridge_status)
        Write-Host ("Result path      : {0}" -f $Result.latest_result_path)
        Write-Host ("Package path     : {0}" -f $Result.package_path)
        if ($Issues.Count -gt 0) {
            Write-Host "Issues:"
            foreach ($Issue in $Issues) {
                Write-Host ("- {0}" -f $Issue)
            }
        }
    }

    if ($Issues.Count -gt 0 -and -not $NoThrow) {
        throw ("NotebookLM command validation failed: " + ($Issues -join "; "))
    }
}
catch {
    $Failure = [pscustomobject]@{
        status   = "fail"
        issues   = @($_.Exception.Message)
        command  = "/notebooklm"
    }
    if ($AsJson) {
        $Failure | ConvertTo-Json -Depth 10
    }
    else {
        Write-Host "[FAIL] NotebookLM command test"
        Write-Host $_.Exception.Message
    }
    if (-not $NoThrow) {
        throw
    }
}
finally {
    foreach ($Path in @($CleanupPaths | Select-Object -Unique)) {
        try {
            if ([string]::IsNullOrWhiteSpace([string]$Path)) {
                continue
            }
            if (Test-Path -LiteralPath $Path) {
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        catch {}
    }
}
