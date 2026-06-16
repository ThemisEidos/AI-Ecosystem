[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Text,

    [Parameter(Mandatory = $false)]
    [switch]$ConfirmDispatch,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

    [Parameter(Mandatory = $false)]
    [string]$Project = "AI Ecosystem",

    [Parameter(Mandatory = $false)]
    [string]$ConversationId,

    [Parameter(Mandatory = $false)]
    [string]$SessionId,

    [Parameter(Mandatory = $false)]
    [string]$UserId,

    [Parameter(Mandatory = $false)]
    [string]$ConversationTitle
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$InterpreterScript = Join-Path $PSScriptRoot "PDA_CommandInterpreter.ps1"
$SubmitScript = Join-Path $PSScriptRoot "Submit-PDATask.ps1"
$FabricSubmitScript = Join-Path $PSScriptRoot "Submit-PDAFabricTask.ps1"
$NotebookLMCommandScript = Join-Path $PSScriptRoot "Invoke-PDANotebookLMCommand.ps1"
$CapabilityRouterScript = Join-Path $PSScriptRoot "PDA_CapabilityRouter.ps1"
. (Join-Path $PSScriptRoot "PDA_OutputParsing.ps1")
. (Join-Path $PSScriptRoot "PDA_Fabric.ps1")
. (Join-Path $PSScriptRoot "PDA_TaskOntology.ps1")
if (Test-Path -LiteralPath $CapabilityRouterScript -PathType Leaf) {
    . $CapabilityRouterScript
}
$DashboardStatusScript = Join-Path $PSScriptRoot "Get-PDADashboardStatus.ps1"
$WorkerStatusScript = Join-Path $PSScriptRoot "Get-PDAWorkerStatus.ps1"
$TaskResultScript = Join-Path $PSScriptRoot "Get-PDATaskResult.ps1"
$ArtifactIndexScript = Join-Path $PSScriptRoot "Get-PDAArtifactIndex.ps1"
$MemoryIndexScript = Join-Path $PSScriptRoot "Get-PDAMemoryIndex.ps1"
$MemoryCandidateSummaryScript = Join-Path $PSScriptRoot "Get-PDAMemoryCandidateSummary.ps1"

if (-not (Test-Path -Path $InterpreterScript -PathType Leaf)) {
    throw "Command interpreter missing: $InterpreterScript"
}

if (-not (Test-Path -Path $SubmitScript -PathType Leaf)) {
    throw "Governed submitter missing: $SubmitScript"
}

function Get-PDAHandoffClassification {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $TaskTypes = @(Find-PDATaskTypes -Root $Root -Command $Command)
    if ($TaskTypes.Count -eq 0) {
        return "category_1"
    }

    $Supported = @($TaskTypes[0].supported_categories)
    if ($Supported -contains "category_1") {
        return "category_1"
    }

    return [string]$Supported[0]
}

function Invoke-PDACommandScriptText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string[]]$Arguments = @()
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return "Unavailable: $Path"
    }

    try {
        $Raw = & pwsh -NoProfile -File $Path @Arguments 2>&1
        $TextOutput = [string]($Raw -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($TextOutput)) {
            return "No output returned."
        }

        return $TextOutput
    }
    catch {
        return "Command failed: $($_.Exception.Message)"
    }
}

function Invoke-PDACommandScriptJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string[]]$Arguments = @()
    )

    $TextOutput = Invoke-PDACommandScriptText -Path $Path -Arguments $Arguments
    if ([string]::IsNullOrWhiteSpace($TextOutput)) {
        throw "Command produced no JSON output: $Path"
    }

    try {
        return ConvertFrom-PDAMixedJson -Text $TextOutput -SourceName $Path
    }
    catch {
        throw "Failed to parse JSON output from ${Path}: $($_.Exception.Message)"
    }
}

function Get-PDAOperatorConsoleResponse {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $false)]
        [string]$ConversationId,

        [Parameter(Mandatory = $false)]
        [string]$SessionId,

        [Parameter(Mandatory = $false)]
        [string]$UserMessage
    )

    switch ($Command.ToLowerInvariant()) {
        "/status" {
            $StatusReport = Invoke-PDACommandScriptJson -Path $DashboardStatusScript -Arguments @("-NoThrow", "-SkipCoreIntegration", "-AsJson") 
            $Body = Invoke-PDACommandScriptText -Path $DashboardStatusScript -Arguments @("-NoThrow", "-SkipCoreIntegration")
            $SummaryLines = @()
            if ($StatusReport -and $StatusReport.PSObject.Properties.Name -contains "cooper_status" -and $StatusReport.cooper_status -and $StatusReport.cooper_status.PSObject.Properties.Name -contains "summary_lines") {
                $SummaryLines = @($StatusReport.cooper_status.summary_lines)
            }
            if ($SummaryLines.Count -eq 0) {
                $SummaryLines = @(
                    "COOPER Status"
                    "Chief Officer of Preventing Everything from Randomly Exploding"
                )
            }
            $ResponseLines = New-Object System.Collections.Generic.List[string]
            [void]$ResponseLines.Add("COOPER Operator Console: Status")
            [void]$ResponseLines.Add("")
            foreach ($Line in $SummaryLines) {
                [void]$ResponseLines.Add([string]$Line)
            }
            [void]$ResponseLines.Add("")
            [void]$ResponseLines.Add($Body)
            return [pscustomobject]@{
                response_text = ($ResponseLines -join "`n")
                next_action = "Use /tasks, /approvals, /workers, /reports, /memory, or /help for a narrower operator view."
            }
        }
        "/tasks" {
            $Body = Invoke-PDACommandScriptText -Path $TaskResultScript -Arguments @(
                "-NoThrow",
                "-ConversationId", $ConversationId,
                "-SessionId", $SessionId,
                "-UserMessage", $(if ($UserMessage) { $UserMessage } else { "show latest task" })
            )
            return [pscustomobject]@{
                response_text = @(
                    "COOPER Operator Console: Tasks"
                    $Body
                ) -join "`n"
                next_action = "Use /status for the queue overview or /help for the available console commands."
            }
        }
        "/approvals" {
            $Body = Invoke-PDACommandScriptText -Path $DashboardStatusScript -Arguments @("-NoThrow", "-SkipCoreIntegration")
            return [pscustomobject]@{
                response_text = @(
                    "COOPER Operator Console: Approvals"
                    $Body
                ) -join "`n"
                next_action = "Use /help to see the command list or confirm a task request if you intend to dispatch work."
            }
        }
        "/workers" {
            $Body = Invoke-PDACommandScriptText -Path $WorkerStatusScript
            return [pscustomobject]@{
                response_text = @(
                    "COOPER Operator Console: Workers"
                    $Body
                ) -join "`n"
                next_action = "Use /status for a cross-system summary or /help for the available console commands."
            }
        }
        "/reports" {
            $Body = Invoke-PDACommandScriptText -Path $ArtifactIndexScript
            return [pscustomobject]@{
                response_text = @(
                    "COOPER Operator Console: Reports"
                    $Body
                ) -join "`n"
                next_action = "Use /memory for memory records or /help for the available console commands."
            }
        }
        "/memory" {
            $Body = Invoke-PDACommandScriptText -Path $MemoryIndexScript
            $CandidateBody = Invoke-PDACommandScriptText -Path $MemoryCandidateSummaryScript -Arguments @()
            return [pscustomobject]@{
                response_text = @(
                    "COOPER Operator Console: Memory"
                    $Body
                    ""
                    $CandidateBody
                ) -join "`n"
                next_action = "Use /reports for artifact history or /help for the available console commands."
            }
        }
        "/dispatch" {
            $DispatchScript = Join-Path $PSScriptRoot "Get-PDADispatchStatus.ps1"
            $DispatchBody = Invoke-PDACommandScriptText -Path $DispatchScript -Arguments @("-Root", $Root, "-NoThrow")
            return [pscustomobject]@{
                response_text = @(
                    "COOPER Operator Console: Dispatch"
                    "Use /dispatch to review the governed executor recommendation and preparation path."
                    $DispatchBody
                ) -join "`n"
                next_action = "Use /help for the available console commands or ask 'what should handle this task?' for a natural-language dispatch recommendation."
            }
        }
        "/help" {
            return [pscustomobject]@{
                response_text = @(
                    "COOPER Operator Console Commands"
                    "/status - system health, queue depth, worker and model status"
                    "/tasks - latest tracked task summary"
                    "/approvals - pending approval summary"
                    "/workers - worker registry and runtime status"
                    "/reports - recent artifacts and reports"
                    "/memory - memory index and recent records"
                    "/dispatch - governed executor recommendation and dispatch preparation status"
                    "/fabric research|report|review|security - local Fabric CLI runs from sanitized inputs only"
                    "/notebooklm - sanitized NotebookLM package creation from Category 1 notes only"
                    "/help - show this command list"
                    "Read-only console commands do not require approval."
                ) -join "`n"
                next_action = "Use one of the operator commands above, or submit a governed task command when you need work dispatched."
            }
        }
        default {
            return [pscustomobject]@{
                response_text = "Unknown operator console command."
                next_action = "Use /help to see the available operator commands."
            }
        }
    }
}

$InterpreterRaw = & pwsh -NoProfile -File $InterpreterScript -Text $Text -AsJson
$Interpreter = ConvertFrom-PDAMixedJson -Text ([string]($InterpreterRaw -join "`n")) -SourceName $InterpreterScript

$RecommendedCommand = [string]$Interpreter.command
$DispatchCategory = ""
$DispatchReady = $false
$RequiresConfirmation = $false
$AmbiguityReason = [string]$Interpreter.reason
$DispatchPath = ""
$DispatchStatus = "not_dispatched"
$DispatchOutput = @()
$DispatchResponseText = ""
$DispatchNextAction = ""
$DispatchTaskId = ""
$CapabilityRoute = $null
$CapabilityMatrixSummary = [pscustomobject]@{
    status              = "skipped"
    matrix_path         = ""
    route_count         = 0
    local_only_count    = 0
    cloud_allowed_count = 0
}
$Eligibility = $null
$OperatorConsoleResponse = $null
$OperatorCommands = @("/status", "/tasks", "/approvals", "/workers", "/reports", "/memory", "/dispatch", "/help")
$IsOperatorConsoleCommand = $OperatorCommands -contains [string]$RecommendedCommand

if ($Interpreter.status -eq "mapped" -and -not [string]::IsNullOrWhiteSpace($RecommendedCommand) -and -not $IsOperatorConsoleCommand) {
    $DispatchCategory = Get-PDAHandoffClassification -Command $RecommendedCommand -Root $Root
    $Eligibility = Get-PDATaskWorkerEligibility -Root $Root -Command $RecommendedCommand -Classification $DispatchCategory -Approved $true
    $DispatchReady = @($Eligibility.eligible_workers).Count -gt 0
    $RequiresConfirmation = -not [bool]$ConfirmDispatch
    $AmbiguityReason = [string]$Interpreter.reason
}
elseif ($Interpreter.status -eq "mapped" -and $IsOperatorConsoleCommand) {
    $OperatorConsoleResponse = Get-PDAOperatorConsoleResponse -Command $RecommendedCommand -ConversationId $ConversationId -SessionId $SessionId -UserMessage $Text
    $DispatchReady = $false
    $RequiresConfirmation = $false
    $DispatchStatus = "not_applicable"
    $AmbiguityReason = [string]$Interpreter.reason
}
elseif ($Interpreter.status -eq "ambiguous") {
    $AmbiguityReason = [string]$Interpreter.reason
}
else {
    $AmbiguityReason = [string]$Interpreter.reason
}

if (Get-Command -Name Get-PDACapabilityMatrix -ErrorAction SilentlyContinue) {
    try {
        $CapabilityMatrix = Get-PDACapabilityMatrix -Root $Root
        $CapabilityMatrixSummary = [pscustomobject]@{
            status              = [string]$CapabilityMatrix.status
            matrix_path         = [string]$CapabilityMatrix.matrix_path
            route_count         = [int]$CapabilityMatrix.route_count
            local_only_count    = [int]$CapabilityMatrix.local_only_count
            cloud_allowed_count = [int]$CapabilityMatrix.cloud_allowed_count
        }
    }
    catch {
        $CapabilityMatrixSummary = [pscustomobject]@{
            status              = "error"
            matrix_path         = [string]$CapabilityRouterScript
            route_count         = 0
            local_only_count    = 0
            cloud_allowed_count = 0
            error               = $_.Exception.Message
        }
    }
}

if ($Interpreter.status -eq "mapped" -and -not [string]::IsNullOrWhiteSpace($RecommendedCommand) -and -not $IsOperatorConsoleCommand -and (Get-Command -Name Get-PDAToolForTask -ErrorAction SilentlyContinue)) {
    try {
        $TaskDefinition = @(
            Find-PDATaskTypes -Root $Root -Command $RecommendedCommand -Classification $DispatchCategory | Select-Object -First 1
        )[0]
        $PreferredOutput = if ($TaskDefinition -and $TaskDefinition.PSObject.Properties.Name -contains "output_types" -and @($TaskDefinition.output_types).Count -gt 0) {
            [string]@($TaskDefinition.output_types)[0]
        }
        else {
            ""
        }

        $CapabilityRoute = Get-PDAToolForTask -TaskType $Interpreter.task_type -Category $DispatchCategory -PreferredOutput $PreferredOutput -RequiresLocalOnly:($DispatchCategory -in @("category_2", "restricted_local")) -Root $Root
        if ($CapabilityRoute -and -not [bool]$CapabilityRoute.allowed) {
            $DispatchReady = $false
            $RequiresConfirmation = $false
            $DispatchStatus = "blocked"
            $AmbiguityReason = if ([string]::IsNullOrWhiteSpace([string]$CapabilityRoute.blocked_reason)) { [string]$CapabilityRoute.routing_reason } else { [string]$CapabilityRoute.blocked_reason }
        }
    }
    catch {
        $CapabilityRoute = [pscustomobject]@{
            selected_tool       = ""
            backup_tool         = ""
            routing_reason      = "Capability router failed: $($_.Exception.Message)"
            allowed             = $false
            blocked_reason      = $_.Exception.Message
            output_location     = @()
            task_type           = [string]$Interpreter.task_type
            category            = $DispatchCategory
            preferred_output    = ""
            requires_local_only = ($DispatchCategory -in @("category_2", "restricted_local"))
            cloud_allowed       = $false
            matrix_status       = "error"
            matrix_path         = [string]$CapabilityRouterScript
            route_count         = 0
            matrix_loaded       = $false
        }
    }
}

if ($ConfirmDispatch -and $Interpreter.status -eq "mapped" -and $DispatchReady) {
    if ($RecommendedCommand -eq "/notebooklm") {
        if (-not (Test-Path -Path $NotebookLMCommandScript -PathType Leaf)) {
            throw "NotebookLM command helper missing: $NotebookLMCommandScript"
        }

        $NotebookLMArgs = @(
            "-Text", $Text,
            "-Project", $Project,
            "-ConversationId", $(if ($ConversationId) { $ConversationId } else { "" }),
            "-SessionId", $(if ($SessionId) { $SessionId } else { "" }),
            "-UserId", $(if ($UserId) { $UserId } else { "" }),
            "-ConversationTitle", $(if ($ConversationTitle) { $ConversationTitle } else { "" }),
            "-AsJson"
        )

        $NotebookLMResult = Invoke-PDACommandScriptJson -Path $NotebookLMCommandScript -Arguments $NotebookLMArgs
        $DispatchStatus = [string]$NotebookLMResult.dispatch_status
        $DispatchOutput = @($NotebookLMResult | ConvertTo-Json -Depth 40)
        $DispatchPath = [string]$NotebookLMResult.result_path
        $DispatchResponseText = [string]$NotebookLMResult.response_text
        $DispatchNextAction = [string]$NotebookLMResult.next_action
        $DispatchTaskId = [string]$NotebookLMResult.task_id
    }
    elseif ($RecommendedCommand -eq "/codex-task") {
        $CodexTaskScript = Join-Path $PSScriptRoot "Invoke-COOPERCodexTaskGenerator.ps1"
        if (-not (Test-Path -Path $CodexTaskScript -PathType Leaf)) {
            throw "Codex task generator missing: $CodexTaskScript"
        }

        $CodexTaskResult = & $CodexTaskScript -Text $Text -Approved -Root $Root
        $DispatchStatus = "completed"
        $DispatchOutput = @($CodexTaskResult | ConvertTo-Json -Depth 40)
        $DispatchPath = [string]$CodexTaskResult.task_path
        $DispatchResponseText = [string]$CodexTaskResult.response_text
        if ([string]::IsNullOrWhiteSpace($DispatchResponseText)) {
            $DispatchResponseText = "Created Codex task."
        }
        $DispatchNextAction = "Review the generated task artifact or confirm another governed request."
        $DispatchTaskId = if (-not [string]::IsNullOrWhiteSpace($DispatchPath)) { [System.IO.Path]::GetFileNameWithoutExtension($DispatchPath) } else { "" }
    }
    elseif ($RecommendedCommand -like "/fabric*") {
        if (-not (Test-Path -Path $FabricSubmitScript -PathType Leaf)) {
            throw "Fabric submitter missing: $FabricSubmitScript"
        }

        $FabricAlias = Resolve-PDAFabricPatternAlias -Text $Text -Command $RecommendedCommand
        $FabricPattern = Resolve-PDAFabricPatternName -Alias $FabricAlias
        $SubmitOutput = & pwsh -NoProfile -File $FabricSubmitScript -Command $RecommendedCommand -Pattern $FabricPattern -PatternAlias $FabricAlias -Message $Text -Category $DispatchCategory -Approved:$true 2>&1
        $DispatchOutput = @($SubmitOutput | ForEach-Object { [string]$_ })

        if ($LASTEXITCODE -ne 0) {
            throw "Fabric dispatch failed with exit code $LASTEXITCODE"
        }

        $SubmitLines = @($DispatchOutput | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $DispatchPath = [string]($SubmitLines | Select-Object -Last 1)
        $DispatchStatus = "submitted"
        if (-not [string]::IsNullOrWhiteSpace($FabricAlias)) {
            $DispatchResponseText = "Dispatched Fabric pattern '$FabricAlias' via governed PDA handoff."
        }
        else {
            $DispatchResponseText = "Dispatched Fabric pattern via governed PDA handoff."
        }
        $DispatchNextAction = "Await queue processing for the Fabric worker result."
    }
    else {
        $DispatchStatus = "submitted"
        $SubmitOutput = & pwsh -NoProfile -File $SubmitScript -Command $RecommendedCommand -Target $Text -Project $Project -Category $DispatchCategory -Approved:$true 2>&1
        $DispatchOutput = @($SubmitOutput | ForEach-Object { [string]$_ })

        if ($LASTEXITCODE -ne 0) {
            throw "Governed dispatch failed with exit code $LASTEXITCODE"
        }

        $SubmitLines = @($DispatchOutput | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $DispatchPath = [string]($SubmitLines | Select-Object -Last 1)
    }
}
elseif ($ConfirmDispatch -and $Interpreter.status -ne "mapped") {
    $DispatchStatus = "blocked"
}

if ([string]::IsNullOrWhiteSpace($DispatchTaskId) -and $DispatchOutput.Count -gt 0) {
    $TaskIdLine = @($DispatchOutput | Where-Object { [string]$_ -match 'Task ID:\s*(.+)$' } | Select-Object -Last 1)
    if ($TaskIdLine.Count -gt 0) {
        $DispatchTaskId = ([string]$TaskIdLine[-1] -replace '^.*Task ID:\s*', '').Trim()
    }
}

$Result = [pscustomobject]@{
    original_input      = $Text
    interpreter_status  = [string]$Interpreter.status
    recommended_command = $RecommendedCommand
    intent              = [string]$Interpreter.intent
    confidence          = [double]$Interpreter.confidence
    ambiguity_reason    = $AmbiguityReason
    requires_confirmation = $RequiresConfirmation
    dispatch_ready      = $DispatchReady
    dispatch_status     = $DispatchStatus
    dispatch_path       = $DispatchPath
    dispatch_category   = $DispatchCategory
    task_id             = $DispatchTaskId
    capability_matrix   = $CapabilityMatrixSummary
    capability_route    = $CapabilityRoute
    selected_tool       = if ($CapabilityRoute) { [string]$CapabilityRoute.selected_tool } else { "" }
    backup_tool         = if ($CapabilityRoute) { [string]$CapabilityRoute.backup_tool } else { "" }
    routing_reason      = if ($CapabilityRoute) { [string]$CapabilityRoute.routing_reason } else { "" }
    blocked_reason      = if ($CapabilityRoute) { [string]$CapabilityRoute.blocked_reason } else { "" }
    output_location     = if ($CapabilityRoute) { @($CapabilityRoute.output_location) } else { @() }
    response_text       = if ($DispatchResponseText) { [string]$DispatchResponseText } elseif ($OperatorConsoleResponse) { [string]$OperatorConsoleResponse.response_text } else { "" }
    next_action         = if ($DispatchNextAction) { [string]$DispatchNextAction } elseif ($OperatorConsoleResponse) { [string]$OperatorConsoleResponse.next_action } else { "" }
    source_of_truth     = [string]$Interpreter.source_of_truth
    ontology_version    = [string]$Interpreter.ontology_version
    bridge_status       = if ($DispatchStatus -eq "completed") { "completed" } elseif ($DispatchStatus -eq "submitted") { "submitted" } else { "ready" }
    approved_via_gate   = ($DispatchStatus -in @("submitted", "completed"))
    dispatch_output     = @($DispatchOutput)
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] PDA command handoff result:"
Write-Host ("Interpreter status   : {0}" -f $Result.interpreter_status)
Write-Host ("Recommended command  : {0}" -f $(if ($Result.recommended_command) { $Result.recommended_command } else { "(none)" }))
Write-Host ("Intent               : {0}" -f $(if ($Result.intent) { $Result.intent } else { "(none)" }))
Write-Host ("Confidence           : {0}" -f $Result.confidence)
Write-Host ("Requires confirmation : {0}" -f $Result.requires_confirmation)
Write-Host ("Dispatch ready       : {0}" -f $Result.dispatch_ready)
Write-Host ("Dispatch status      : {0}" -f $Result.dispatch_status)
if ($Result.dispatch_path) {
    Write-Host ("Dispatch path        : {0}" -f $Result.dispatch_path)
}
Write-Host ("Ambiguity reason     : {0}" -f $Result.ambiguity_reason)
