[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Message,

    [Parameter(Mandatory = $false)]
    [switch]$ConfirmDispatch,

    [Parameter(Mandatory = $false)]
    [switch]$AsJson,

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
$HandoffScript = Join-Path $PSScriptRoot "Invoke-PDACommandHandoff.ps1"
$ConversationStateScript = Join-Path $PSScriptRoot "Get-PDAConversationState.ps1"
$TaskResultScript = Join-Path $PSScriptRoot "Get-PDATaskResult.ps1"
$UpdateConversationStateScript = Join-Path $PSScriptRoot "Update-PDAConversationState.ps1"
$ConversationalRouterScript = Join-Path $PSScriptRoot "PDA_ConversationalRouter.ps1"
$DecisionEngineScript = Join-Path $PSScriptRoot "PDA_DecisionEngine.ps1"
$EnvironmentHelperScript = Join-Path $PSScriptRoot "PDA_Environment.ps1"
$ApprovalWorkflowScript = Join-Path $PSScriptRoot "PDA_ApprovalWorkflow.ps1"
$COOPERIdentityScript = Join-Path $PSScriptRoot "Get-COOPERIdentity.ps1"
. (Join-Path $PSScriptRoot "PDA_OutputParsing.ps1")
if (Test-Path -Path $ConversationalRouterScript -PathType Leaf) {
    . $ConversationalRouterScript
}
if (Test-Path -Path $DecisionEngineScript -PathType Leaf) {
    . $DecisionEngineScript
}
if (Test-Path -Path $EnvironmentHelperScript -PathType Leaf) {
    . $EnvironmentHelperScript
}
if (Test-Path -Path $ApprovalWorkflowScript -PathType Leaf) {
    . $ApprovalWorkflowScript
}
if (Test-Path -Path $COOPERIdentityScript -PathType Leaf) {
    . $COOPERIdentityScript
}

if (-not (Test-Path -Path $HandoffScript -PathType Leaf)) {
    throw "Command handoff missing: $HandoffScript"
}

function Test-PDAStatusLookupMessage {
    param([Parameter(Mandatory = $true)][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    return [bool]($Text -match '(?i)\b(status|what happened|where is|how is|did it finish|latest result|result location|what happened to)\b')
}

function Test-PDAOperatorConsoleMessage {
    param([Parameter(Mandatory = $true)][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $Normalized = $Text.Trim().ToLowerInvariant()
    return [bool]($Normalized -match '^(\/status|\/tasks|\/approvals|\/workers|\/reports|\/memory|\/help)(\b|\s|$)')
}

function Test-PDAConfirmationMessage {
    param([Parameter(Mandatory = $true)][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $Normalized = $Text.Trim().ToLowerInvariant()
    return [bool]($Normalized -match '^(confirm|confirmed|yes|approve|approved|proceed|dispatch)\b')
}

function Test-PDAApprovalActionMessage {
    param([Parameter(Mandatory = $true)][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $Normalized = $Text.Trim().ToLowerInvariant()
    return [bool]($Normalized -match '^(approve|approved|reject|rejected|revise|revision|replan|escalate|cancel|cancelled|canceled|yes|confirm|confirmed|proceed|dispatch)\b')
}

function Get-PDAApprovalActionStatus {
    param([Parameter(Mandatory = $true)][string]$Text)

    $Normalized = $Text.Trim().ToLowerInvariant()
    switch -Regex ($Normalized) {
        '^(approve|approved|yes|confirm|confirmed|proceed|dispatch)\b' { return 'approved' }
        '^(reject|rejected|deny|decline|no)\b' { return 'rejected' }
        '^(revise|revision)\b' { return 'revision_requested' }
        '^(replan|re-plan)\b' { return 'replan_requested' }
        '^(escalate)\b' { return 'escalated' }
        '^(cancel|cancelled|canceled|abort|stop)\b' { return 'cancelled' }
        default { return '' }
    }
}

function Get-PDAConversationPendingActionFromSummary {
    param([Parameter(Mandatory = $false)]$ConversationState)

    if (-not $ConversationState) {
        return $null
    }

    if ($ConversationState.pending_action) {
        return $ConversationState.pending_action
    }

    if ($ConversationState.conversation -and $ConversationState.conversation.pending_recommended_command) {
        return [pscustomobject]@{
            recommended_command = [string]$ConversationState.conversation.pending_recommended_command
            dispatch_category    = [string]$ConversationState.conversation.pending_dispatch_category
            original_message     = [string]$ConversationState.conversation.pending_original_message
            timestamp            = [string]$ConversationState.conversation.pending_timestamp
            expires_at           = [string]$ConversationState.conversation.pending_expires_at
            status               = [string]$ConversationState.conversation.pending_status
            is_expired           = [bool]$ConversationState.conversation.pending_is_expired
        }
    }

    return $null
}

function Get-PDAPendingConfirmationTimeoutMinutes {
    $DefaultMinutes = 30
    $EnvValue = [string]$env:PDA_PENDING_CONFIRMATION_TIMEOUT_MINUTES
    if ([string]::IsNullOrWhiteSpace($EnvValue)) {
        return $DefaultMinutes
    }

    $Parsed = 0
    if ([int]::TryParse($EnvValue, [ref]$Parsed) -and $Parsed -gt 0) {
        return $Parsed
    }

    return $DefaultMinutes
}

function Get-PDACommanderRuntimeContext {
    param([Parameter(Mandatory = $true)][string]$Root)

    $Identity = $null
    if (Get-Command -Name Get-COOPERIdentity -ErrorAction SilentlyContinue) {
        try {
            $Identity = Get-COOPERIdentity -Root $Root
        }
        catch {
            $Identity = $null
        }
    }

    $RuntimeLayers = $null
    if ($Identity -and $Identity.PSObject.Properties.Name -contains "runtime_layers") {
        $RuntimeLayers = $Identity.runtime_layers
    }

    if (-not $RuntimeLayers) {
        $RuntimeLayers = [pscustomobject]@{
            cooper_layers_loaded = $false
            personality_loaded = (Test-Path -LiteralPath (Join-Path $Root "Scripts\COOPER_Personality.json") -PathType Leaf)
            memory_available = (Test-Path -LiteralPath (Join-Path $Root "Documentation\COOPER-Memory-Architecture.md") -PathType Leaf) -or (Test-Path -LiteralPath (Join-Path $Root "Documentation\PDA-Memory-Promotion-Workflow.md") -PathType Leaf)
            governance_available = (Test-Path -LiteralPath (Join-Path $Root "Scripts\PDA_ApprovalWorkflow.ps1") -PathType Leaf)
            capability_registry_available = (Test-Path -LiteralPath (Join-Path $Root "Scripts\PDA_CapabilityRegistry.json") -PathType Leaf)
            agent_registry_available = (Test-Path -LiteralPath (Join-Path $Root "Scripts\PDA_AgentProfileRegistry.json") -PathType Leaf)
            provider_routing_available = (Test-Path -LiteralPath (Join-Path $Root "Scripts\PDA_ProviderRoutingPolicy.json") -PathType Leaf)
            source_paths = [pscustomobject]@{
                personality = Join-Path $Root "Scripts\COOPER_Personality.json"
                memory = Join-Path $Root "Documentation\COOPER-Memory-Architecture.md"
                governance = Join-Path $Root "Scripts\PDA_ApprovalWorkflow.ps1"
                capability_registry = Join-Path $Root "Scripts\PDA_CapabilityRegistry.json"
                agent_registry = Join-Path $Root "Scripts\PDA_AgentProfileRegistry.json"
                provider_routing_policy = Join-Path $Root "Scripts\PDA_ProviderRoutingPolicy.json"
            }
        }
        $RuntimeLayers.cooper_layers_loaded = [bool]($RuntimeLayers.personality_loaded -and $RuntimeLayers.memory_available -and $RuntimeLayers.governance_available -and $RuntimeLayers.capability_registry_available -and $RuntimeLayers.agent_registry_available -and $RuntimeLayers.provider_routing_available)
    }

    $IdentitySummary = [pscustomobject]@{
        display_name = if ($Identity -and $Identity.PSObject.Properties.Name -contains "display_name") { [string]$Identity.display_name } else { "COOPER" }
        official_name = if ($Identity -and $Identity.PSObject.Properties.Name -contains "official_name") { [string]$Identity.official_name } else { "Command Operations Orchestrator for Planning, Execution, and Reporting" }
        tagline = if ($Identity -and $Identity.PSObject.Properties.Name -contains "tagline") { [string]$Identity.tagline } else { "Chief Officer of Preventing Everything from Randomly Exploding" }
        operational_modes = if ($Identity -and $Identity.PSObject.Properties.Name -contains "operational_modes") { @($Identity.operational_modes) } else { @("Analyst Mode", "Operator Mode", "TARS Mode", "Overlord Mode", "Emergency Mode") }
    }

    return [pscustomobject]@{
        cooper_layers_loaded = [bool]$RuntimeLayers.cooper_layers_loaded
        personality_loaded = [bool]$RuntimeLayers.personality_loaded
        memory_available = [bool]$RuntimeLayers.memory_available
        governance_available = [bool]$RuntimeLayers.governance_available
        capability_registry_available = [bool]$RuntimeLayers.capability_registry_available
        agent_registry_available = [bool]$RuntimeLayers.agent_registry_available
        provider_routing_available = [bool]$RuntimeLayers.provider_routing_available
        identity = $IdentitySummary
        runtime_layers = $RuntimeLayers
        cooper_interface = "COOPER"
        source_of_truth = "Scripts/Get-COOPERIdentity.ps1"
    }
}

function Add-PDACommanderRuntimeContextFields {
    param([Parameter(Mandatory = $true)]$Result)

    if ($null -eq $Result) {
        return $Result
    }

    $RuntimeContext = $script:PDACommanderRuntimeContext
    if (-not $RuntimeContext) {
        return $Result
    }

    $Fields = [ordered]@{
        cooper_layers_loaded = [bool]$RuntimeContext.cooper_layers_loaded
        personality_loaded = [bool]$RuntimeContext.personality_loaded
        memory_available = [bool]$RuntimeContext.memory_available
        governance_available = [bool]$RuntimeContext.governance_available
        capability_registry_available = [bool]$RuntimeContext.capability_registry_available
        agent_registry_available = [bool]$RuntimeContext.agent_registry_available
        cooper_context = $RuntimeContext
    }

    foreach ($Entry in $Fields.GetEnumerator()) {
        $Result | Add-Member -NotePropertyName ([string]$Entry.Key) -NotePropertyValue $Entry.Value -Force
    }

    return $Result
}

$script:PDACommanderRuntimeContext = Get-PDACommanderRuntimeContext -Root $Root

function Invoke-PDAConversationStateQuery {
    param(
        [string]$ConversationId,
        [string]$SessionId,
        [string]$Message
    )

    if (-not (Test-Path -Path $ConversationStateScript -PathType Leaf)) {
        return $null
    }

    $StateArgs = @("-AsJson")
    if (-not [string]::IsNullOrWhiteSpace($ConversationId)) {
        $StateArgs += @("-ConversationId", $ConversationId)
    }
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $StateArgs += @("-SessionId", $SessionId)
    }
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $StateArgs += @("-UserMessage", $Message)
    }

    try {
        $Raw = & pwsh -NoProfile -File $ConversationStateScript @StateArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $null
        }

        $JsonText = [string]($Raw -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($JsonText)) {
            return $null
        }

        $Parsed = ConvertFrom-PDAMixedJson -Text $JsonText -SourceName $ConversationStateScript
        if ($Parsed -and ($Parsed.conversation -or $Parsed.pending_action -or $Parsed.pending_approval_count -gt 0)) {
            return $Parsed
        }
    }
    catch {
        $Parsed = $null
    }

    try {
        $StatePath = Join-Path $Root "PDA-Runtime\data\conversation-state.json"
        if (-not (Test-Path -Path $StatePath -PathType Leaf)) {
            return $null
        }

        # Fallback directly to the persisted state file when the query helper
        # returns partial/empty output for confirmation-only conversations.
        $StateJson = Get-Content -Path $StatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $ConversationEntry = $null
        if ($StateJson.PSObject.Properties.Name -contains "conversations") {
            $ConversationEntry = @($StateJson.conversations.PSObject.Properties | Where-Object { [string]$_.Name -eq $ConversationId } | Select-Object -First 1).Value
        }

        if (-not $ConversationEntry) {
            return $null
        }

        $PendingApprovalCount = 0
        if ($ConversationEntry.pending_status -eq "awaiting_confirmation" -or -not [string]::IsNullOrWhiteSpace([string]$ConversationEntry.pending_recommended_command)) {
            $PendingApprovalCount = 1
        }

        return [pscustomobject]@{
            status = "pass"
            registry_path = $StatePath
            conversation_id = [string]$ConversationId
            session_id = [string]$SessionId
            task_id = ""
            conversation = $ConversationEntry
            pending_action = if (-not [string]::IsNullOrWhiteSpace([string]$ConversationEntry.pending_recommended_command)) {
                [pscustomobject]@{
                    recommended_command = [string]$ConversationEntry.pending_recommended_command
                    dispatch_category    = [string]$ConversationEntry.pending_dispatch_category
                    original_message     = [string]$ConversationEntry.pending_original_message
                    timestamp            = [string]$ConversationEntry.pending_timestamp
                    expires_at           = [string]$ConversationEntry.pending_expires_at
                    status               = [string]$ConversationEntry.pending_status
                    is_expired           = [bool]$ConversationEntry.pending_is_expired
                }
            }
            else {
                $null
            }
            response_text = if ($ConversationEntry.last_response_text) { [string]$ConversationEntry.last_response_text } else { "" }
            next_action = if ($ConversationEntry.last_next_action) { [string]$ConversationEntry.last_next_action } else { "" }
            pending_approval_count = $PendingApprovalCount
            active_task_count = if ($ConversationEntry.active_task_count) { [int]$ConversationEntry.active_task_count } else { 0 }
            submitted_task_count = if ($ConversationEntry.submitted_task_count) { [int]$ConversationEntry.submitted_task_count } else { 0 }
            completed_task_count = if ($ConversationEntry.completed_task_count) { [int]$ConversationEntry.completed_task_count } else { 0 }
        }
    }
    catch {
        return $null
    }
}

function Invoke-PDATaskResultQuery {
    param(
        [string]$ConversationId,
        [string]$SessionId,
        [string]$Message
    )

    if (-not (Test-Path -Path $TaskResultScript -PathType Leaf)) {
        return $null
    }

    $TaskArgs = @("-AsJson")
    if (-not [string]::IsNullOrWhiteSpace($ConversationId)) {
        $TaskArgs += @("-ConversationId", $ConversationId)
    }
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $TaskArgs += @("-SessionId", $SessionId)
    }
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $TaskArgs += @("-UserMessage", $Message)
    }

    try {
        $Raw = & pwsh -NoProfile -File $TaskResultScript @TaskArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $null
        }

        $JsonText = [string]($Raw -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($JsonText)) {
            return $null
        }

        return ConvertFrom-PDAMixedJson -Text $JsonText -SourceName $TaskResultScript
    }
    catch {
        return $null
    }
}

function Invoke-PDAConversationStateUpdate {
    param(
        [string]$ConversationId,
        [string]$SessionId,
        [string]$UserId,
        [string]$ConversationTitle,
        [string]$Message,
        [string]$TaskId,
        [string]$TaskStatus,
        [string]$TaskFilePath,
        [string]$ApprovalFilePath,
        [string]$ResultPath,
        [string]$ResultSummary,
        [string]$BridgeStatus,
        [string]$DispatchStatus,
        [string]$NextAction,
        [string]$ResponseText,
        [string]$RecommendedCommand,
        [string]$Intent,
        [double]$Confidence = 0,
        [bool]$RequiresConfirmation = $false,
        [string]$PendingRecommendedCommand,
        [string]$PendingDispatchCategory,
        [string]$PendingOriginalMessage,
        [string]$PendingTimestamp,
        [string]$PendingExpiresAt,
        [string]$PendingStatus,
        [string]$RouteType,
        [object]$Decision,
        [object]$COOPERContext,
        [bool]$COOPERLayersLoaded = $false,
        [bool]$PersonalityLoaded = $false,
        [bool]$MemoryAvailable = $false,
        [bool]$GovernanceAvailable = $false,
        [bool]$CapabilityRegistryAvailable = $false,
        [bool]$AgentRegistryAvailable = $false,
        [switch]$ClearPendingAction
    )

    if (-not (Test-Path -Path $UpdateConversationStateScript -PathType Leaf)) {
        return $null
    }

    $LogPath = Join-Path $Root "PDA-Logs\conversation-state-bridge.log"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
    Add-Content -Path $LogPath -Value ("{0} update-start conversation={1} session={2} task={3}" -f (Get-Date -Format o), $(if ($ConversationId) { $ConversationId } else { "default" }), $(if ($SessionId) { $SessionId } else { "" }), $(if ($TaskId) { $TaskId } else { "" }))

    $UpdateArgs = @(
        "-ConversationId", $(if ([string]::IsNullOrWhiteSpace($ConversationId)) { "default" } else { $ConversationId }),
        "-SessionId", $SessionId,
        "-UserId", $UserId,
        "-ConversationTitle", $ConversationTitle,
        "-UserMessage", $Message,
        "-RecommendedCommand", $RecommendedCommand,
        "-Intent", $Intent,
        "-Confidence", $Confidence,
        "-RequiresConfirmation", $RequiresConfirmation,
        "-DispatchStatus", $DispatchStatus,
        "-BridgeStatus", $BridgeStatus,
        "-NextAction", $NextAction,
        "-ResponseText", $ResponseText
    )

    if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        $UpdateArgs += @("-TaskId", $TaskId)
    }
    if (-not [string]::IsNullOrWhiteSpace($TaskStatus)) {
        $UpdateArgs += @("-TaskStatus", $TaskStatus)
    }
    if (-not [string]::IsNullOrWhiteSpace($TaskFilePath)) {
        $UpdateArgs += @("-TaskFilePath", $TaskFilePath)
    }
    if (-not [string]::IsNullOrWhiteSpace($ApprovalFilePath)) {
        $UpdateArgs += @("-ApprovalFilePath", $ApprovalFilePath)
    }
    if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
        $UpdateArgs += @("-ResultPath", $ResultPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($ResultSummary)) {
        $UpdateArgs += @("-ResultSummary", $ResultSummary)
    }
    if (-not [string]::IsNullOrWhiteSpace($PendingRecommendedCommand)) {
        $UpdateArgs += @("-PendingRecommendedCommand", $PendingRecommendedCommand)
    }
    if (-not [string]::IsNullOrWhiteSpace($PendingDispatchCategory)) {
        $UpdateArgs += @("-PendingDispatchCategory", $PendingDispatchCategory)
    }
    if (-not [string]::IsNullOrWhiteSpace($PendingOriginalMessage)) {
        $UpdateArgs += @("-PendingOriginalMessage", $PendingOriginalMessage)
    }
    if (-not [string]::IsNullOrWhiteSpace($PendingTimestamp)) {
        $UpdateArgs += @("-PendingTimestamp", $PendingTimestamp)
    }
    if (-not [string]::IsNullOrWhiteSpace($PendingExpiresAt)) {
        $UpdateArgs += @("-PendingExpiresAt", $PendingExpiresAt)
    }
    if (-not [string]::IsNullOrWhiteSpace($PendingStatus)) {
        $UpdateArgs += @("-PendingStatus", $PendingStatus)
    }
    if ($ClearPendingAction) {
        $UpdateArgs += "-ClearPendingAction"
    }
    if (-not [string]::IsNullOrWhiteSpace($RouteType)) {
        $UpdateArgs += @("-RouteType", $RouteType)
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$script:PDAConversationRouteType)) {
        $UpdateArgs += @("-RouteType", [string]$script:PDAConversationRouteType)
    }

    $DecisionValue = $Decision
    if ($null -eq $DecisionValue -and $script:PDACommanderDecision) {
        $DecisionValue = $script:PDACommanderDecision
    }
    if ($null -ne $DecisionValue) {
        $UpdateArgs += @("-Decision", ($DecisionValue | ConvertTo-Json -Depth 20 -Compress))
    }

    $RuntimeContext = $COOPERContext
    if ($null -eq $RuntimeContext -and $script:PDACommanderRuntimeContext) {
        $RuntimeContext = $script:PDACommanderRuntimeContext
    }
    if ($null -ne $RuntimeContext) {
        $UpdateArgs += @("-COOPERContext", ($RuntimeContext | ConvertTo-Json -Depth 20 -Compress))
        $UpdateArgs += @("-COOPERLayersLoaded", [bool]$RuntimeContext.cooper_layers_loaded)
        $UpdateArgs += @("-PersonalityLoaded", [bool]$RuntimeContext.personality_loaded)
        $UpdateArgs += @("-MemoryAvailable", [bool]$RuntimeContext.memory_available)
        $UpdateArgs += @("-GovernanceAvailable", [bool]$RuntimeContext.governance_available)
        $UpdateArgs += @("-CapabilityRegistryAvailable", [bool]$RuntimeContext.capability_registry_available)
        $UpdateArgs += @("-AgentRegistryAvailable", [bool]$RuntimeContext.agent_registry_available)
    }

    try {
        $Raw = & pwsh -NoProfile -File $UpdateConversationStateScript @UpdateArgs -AsJson 2>&1
        $Text = [string]($Raw -join "`n").Trim()
        if (-not [string]::IsNullOrWhiteSpace($Text)) {
            Add-Content -Path $LogPath -Value ("{0} update-output {1}" -f (Get-Date -Format o), $Text.Replace("`r", " ").Replace("`n", " "))
        }
        else {
            Add-Content -Path $LogPath -Value ("{0} update-output (empty)" -f (Get-Date -Format o))
        }
    }
    catch {
        try {
            Add-Content -Path $LogPath -Value ("{0} update-error {1}" -f (Get-Date -Format o), $_.Exception.Message.Replace("`r", " ").Replace("`n", " "))
        }
        catch {}
        return $null
    }
}

function Resolve-PDATaskFileFromDispatchPath {
    param([string]$DispatchPath)

    if ([string]::IsNullOrWhiteSpace($DispatchPath)) {
        return $null
    }

    if (Test-Path -Path $DispatchPath -PathType Leaf) {
        return Get-Item -Path $DispatchPath
    }

    $Leaf = Split-Path -Path $DispatchPath -Leaf
    foreach ($CandidateRoot in @(
        (Join-Path $Root "PDA-Tasks\pending"),
        (Join-Path $Root "PDA-Tasks\approvals\pending"),
        (Join-Path $Root "PDA-Tasks\approvals\approved"),
        (Join-Path $Root "PDA-Tasks\approvals\rejected"),
        (Join-Path $Root "PDA-Tasks\running"),
        (Join-Path $Root "PDA-Tasks\completed"),
        (Join-Path $Root "PDA-Tasks\failed")
    )) {
        $Candidate = Join-Path $CandidateRoot $Leaf
        if (Test-Path -Path $Candidate -PathType Leaf) {
            return Get-Item -Path $Candidate
        }
    }

    return $null
}

function Get-PDATaskIdFromFile {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$FileInfo)

    try {
        $Json = Get-Content -Path $FileInfo.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($Json.PSObject.Properties.Name -contains "task_id" -and -not [string]::IsNullOrWhiteSpace([string]$Json.task_id)) {
            return [string]$Json.task_id
        }
    }
    catch {
        return ""
    }

    return ""
}

function Get-PDABridgeCommanderDecision {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [object]$ConversationRoute,

        [Parameter(Mandatory = $false)]
        [object]$Handoff,

        [Parameter(Mandatory = $false)]
        [string]$Root
    )

    $Category = "category_1"
    $RequiresLocalOnly = $false

    if ($Handoff -and $Handoff.PSObject.Properties.Name -contains "dispatch_category" -and -not [string]::IsNullOrWhiteSpace([string]$Handoff.dispatch_category)) {
        $Category = [string]$Handoff.dispatch_category
    }
    elseif ($ConversationRoute -and $ConversationRoute.PSObject.Properties.Name -contains "route_type") {
        switch ([string]$ConversationRoute.route_type) {
            "environment_awareness" { $Category = "category_1" }
            "goal_planning" { $Category = "category_1" }
            default { $Category = "category_1" }
        }
    }

    if ($Category -in @("category_2", "restricted_local")) {
        $RequiresLocalOnly = $true
    }

    if (Get-Command -Name New-PDACommanderDecision -ErrorAction SilentlyContinue) {
        return New-PDACommanderDecision -Text $Text -Category $Category -RequiresLocalOnly:([bool]$RequiresLocalOnly) -Root $Root
    }

    return $null
}

function Set-PDABridgeDecisionMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Result,

        [Parameter(Mandatory = $false)]
        [string]$RouteType,

        [Parameter(Mandatory = $false)]
        [object]$Decision
    )

    if ($null -eq $Result) {
        return $Result
    }

    if (-not [string]::IsNullOrWhiteSpace($RouteType)) {
        if ($Result.PSObject.Properties.Name -contains "route_type") {
            $Result.route_type = [string]$RouteType
        }
        else {
            $Result | Add-Member -NotePropertyName route_type -NotePropertyValue ([string]$RouteType) -Force
        }
    }

    if ($null -ne $Decision) {
        if ($Result.PSObject.Properties.Name -contains "decision") {
            $Result.decision = $Decision
        }
        else {
            $Result | Add-Member -NotePropertyName decision -NotePropertyValue $Decision -Force
        }
    }

    return $Result
}

$IsConfirmationMessage = Test-PDAConfirmationMessage -Text $Message
$IsStatusLookup = Test-PDAStatusLookupMessage -Text $Message
$IsOperatorConsoleCommand = Test-PDAOperatorConsoleMessage -Text $Message
$NormalizedMessage = [string]$Message.Trim()
$IsSlashCommandMessage = $NormalizedMessage.StartsWith("/")
$UseLegacyStatusLookup = $true
$HandoffInputMessage = $Message

$ConversationState = $null
if ($IsConfirmationMessage -or $ConfirmDispatch -or (Test-PDAApprovalActionMessage -Text $Message)) {
    $ConversationState = Invoke-PDAConversationStateQuery -ConversationId $ConversationId -SessionId $SessionId -Message $Message
}

$PendingAction = Get-PDAConversationPendingActionFromSummary -ConversationState $ConversationState
$HasPendingAction = $PendingAction -and -not [bool]$PendingAction.is_expired

$ApprovalRecord = $null
if (Get-Command -Name Get-PDAApprovalRequest -ErrorAction SilentlyContinue) {
    try {
        if ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.PSObject.Properties.Name -contains "approval_id" -and -not [string]::IsNullOrWhiteSpace([string]$ConversationState.conversation.approval_id)) {
            $ApprovalRecord = Get-PDAApprovalRequest -ApprovalId ([string]$ConversationState.conversation.approval_id) -Root $Root
        }
        if (-not $ApprovalRecord -and -not [string]::IsNullOrWhiteSpace($ConversationId)) {
            $ApprovalRecord = Get-PDAApprovalRequest -ConversationId $ConversationId -SessionId $SessionId -Root $Root
        }
    }
    catch {
        $ApprovalRecord = $null
    }
}

if (-not $PendingAction -and $ApprovalRecord -and [string]$ApprovalRecord.status -eq "pending_approval") {
    $PendingAction = [pscustomobject]@{
        recommended_command = if ($ApprovalRecord.PSObject.Properties.Name -contains "recommended_command") { [string]$ApprovalRecord.recommended_command } else { "" }
        dispatch_category    = if ($ApprovalRecord.PSObject.Properties.Name -contains "dispatch_category") { [string]$ApprovalRecord.dispatch_category } else { "" }
        original_message     = if ($ApprovalRecord.PSObject.Properties.Name -contains "user_message") { [string]$ApprovalRecord.user_message } else { "" }
        timestamp            = if ($ApprovalRecord.PSObject.Properties.Name -contains "request_timestamp") { [string]$ApprovalRecord.request_timestamp } else { "" }
        expires_at           = if ($ApprovalRecord.PSObject.Properties.Name -contains "expires_at") { [string]$ApprovalRecord.expires_at } else { "" }
        status               = [string]$ApprovalRecord.status
        is_expired           = $false
        approval_id          = if ($ApprovalRecord.PSObject.Properties.Name -contains "approval_id") { [string]$ApprovalRecord.approval_id } else { "" }
        approval_path        = if ($ApprovalRecord.PSObject.Properties.Name -contains "approval_path") { [string]$ApprovalRecord.approval_path } else { "" }
    }
    $HasPendingAction = $true
}

if (-not $ApprovalRecord -and $HasPendingAction -and (Get-Command -Name New-PDAApprovalRequest -ErrorAction SilentlyContinue)) {
    try {
        $ApprovalRecord = New-PDAApprovalRequest -RunId "" -ConversationId $(if ($ConversationId) { $ConversationId } else { "" }) -SessionId $(if ($SessionId) { $SessionId } else { "" }) -Goal $(if ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.goal) { [string]$ConversationState.conversation.goal } else { [string]$Message }) -RequestedAction ([string]$PendingAction.recommended_command) -Category $(if ($PendingAction.dispatch_category) { [string]$PendingAction.dispatch_category } else { "category_1" }) -RouteType "conversation_approval" -RecommendedCommand ([string]$PendingAction.recommended_command) -RecommendedExecutor "human approval" -DispatchCategory ([string]$PendingAction.dispatch_category) -UserMessage ([string]$PendingAction.original_message) -ApprovalKind "conversation" -ApprovalRationale "Created from pending conversation action." -Root $Root
        if ($ApprovalRecord -and $ApprovalRecord.PSObject.Properties.Name -contains "approval") {
            $ConversationState = if ($ConversationState) { $ConversationState } else { [pscustomobject]@{} }
            if (-not ($ConversationState.PSObject.Properties.Name -contains "conversation")) {
                $ConversationState | Add-Member -NotePropertyName conversation -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $ConversationState.conversation | Add-Member -NotePropertyName approval_id -NotePropertyValue ([string]$ApprovalRecord.approval_id) -Force
            $ConversationState.conversation | Add-Member -NotePropertyName approval_status -NotePropertyValue "pending_approval" -Force
            $ConversationState.conversation | Add-Member -NotePropertyName approval_path -NotePropertyValue ([string]$ApprovalRecord.approval_path) -Force
            $ConversationState.conversation | Add-Member -NotePropertyName approval_requested_action -NotePropertyValue ([string]$PendingAction.recommended_command) -Force
            $ConversationState.conversation | Add-Member -NotePropertyName approval_request_timestamp -NotePropertyValue ([string]$ApprovalRecord.approval.request_timestamp) -Force
        }
    }
    catch {}
}

$ApprovalActionStatus = if (Test-PDAApprovalActionMessage -Text $Message) { Get-PDAApprovalActionStatus -Text $Message } else { "" }
if (-not [string]::IsNullOrWhiteSpace($ApprovalActionStatus) -and ($HasPendingAction -or $ApprovalRecord)) {
    if ($ApprovalActionStatus -eq "approved") {
        $IsConfirmationMessage = $true
        $ConfirmDispatch = $true
    }
    else {
        $ApprovalTarget = $ApprovalRecord
        if (-not $ApprovalTarget -and (Get-Command -Name New-PDAApprovalRequest -ErrorAction SilentlyContinue) -and $HasPendingAction) {
            try {
                $ApprovalTarget = New-PDAApprovalRequest -RunId "" -ConversationId $(if ($ConversationId) { $ConversationId } else { "" }) -SessionId $(if ($SessionId) { $SessionId } else { "" }) -Goal $(if ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.goal) { [string]$ConversationState.conversation.goal } else { [string]$Message }) -RequestedAction ([string]$PendingAction.recommended_command) -Category $(if ($PendingAction.dispatch_category) { [string]$PendingAction.dispatch_category } else { "category_1" }) -RouteType "conversation_approval" -RecommendedCommand ([string]$PendingAction.recommended_command) -RecommendedExecutor "human approval" -DispatchCategory ([string]$PendingAction.dispatch_category) -UserMessage ([string]$PendingAction.original_message) -ApprovalKind "conversation" -ApprovalRationale "Created for approval action replay." -Root $Root
            }
            catch {
                $ApprovalTarget = $null
            }
        }

        $ApprovalIdForAction = if ($ApprovalTarget -and $ApprovalTarget.PSObject.Properties.Name -contains "approval_id") { [string]$ApprovalTarget.approval_id } elseif ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.PSObject.Properties.Name -contains "approval_id") { [string]$ConversationState.conversation.approval_id } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($ApprovalIdForAction) -and (Get-Command -Name Update-PDAApprovalRequest -ErrorAction SilentlyContinue)) {
            try {
                [void](Update-PDAApprovalRequest -ApprovalId $ApprovalIdForAction -Status $ApprovalActionStatus -Approver $(if ($UserId) { $UserId } else { "human" }) -Rationale ([string]$Message) -Root $Root -NoThrow)
            }
            catch {}
        }

        $ApprovalResponseText = switch ($ApprovalActionStatus) {
            "rejected" { "Approval rejected. The governed request will not dispatch." }
            "revision_requested" { "Revision requested. The governed request stays queued for revision." }
            "replan_requested" { "Replan requested. COOPER will revise the goal plan before dispatch." }
            "escalated" { "Approval escalated for human review." }
            "cancelled" { "Approval cancelled. The governed request has been closed." }
            default { "Approval state updated." }
        }

        $ShouldClearPending = $ApprovalActionStatus -in @("rejected", "cancelled")
        if ($ShouldClearPending) {
            $PendingAction = $null
        }

        if ($ConversationId -or $SessionId -or $ApprovalIdForAction) {
            Invoke-PDAConversationStateUpdate -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Message $Message -TaskId "" -TaskStatus $(if ($ShouldClearPending) { "" } else { "pending_approval" }) -TaskFilePath "" -ApprovalFilePath $(if (-not [string]::IsNullOrWhiteSpace($ApprovalIdForAction) -and $ApprovalTarget -and $ApprovalTarget.PSObject.Properties.Name -contains "approval_path") { [string]$ApprovalTarget.approval_path } elseif ($ApprovalRecord -and $ApprovalRecord.PSObject.Properties.Name -contains "approval_path") { [string]$ApprovalRecord.approval_path } else { "" }) -ResultPath "" -ResultSummary "" -BridgeStatus "ready" -DispatchStatus "not_dispatched" -NextAction $(if ($ShouldClearPending) { "Use /planner or ask for a revised goal plan." } else { "The approval remains pending human follow-up." }) -ResponseText $ApprovalResponseText -RecommendedCommand $(if ($PendingAction) { [string]$PendingAction.recommended_command } else { "" }) -Intent "approval_action" -Confidence 1 -RequiresConfirmation:$false -ApprovalId $ApprovalIdForAction -ApprovalStatus $ApprovalActionStatus -ApprovalPath $(if (-not [string]::IsNullOrWhiteSpace($ApprovalIdForAction) -and $ApprovalTarget -and $ApprovalTarget.PSObject.Properties.Name -contains "approval_path") { [string]$ApprovalTarget.approval_path } elseif ($ApprovalRecord -and $ApprovalRecord.PSObject.Properties.Name -contains "approval_path") { [string]$ApprovalRecord.approval_path } else { "" }) -ApprovalRequestedAction $(if ($ApprovalTarget -and $ApprovalTarget.PSObject.Properties.Name -contains "requested_action") { [string]$ApprovalTarget.requested_action } elseif ($ApprovalRecord -and $ApprovalRecord.PSObject.Properties.Name -contains "requested_action") { [string]$ApprovalRecord.requested_action } else { "" }) -ApprovalRationale ([string]$Message) -ApprovalRequestTimestamp $(if ($ApprovalTarget -and $ApprovalTarget.PSObject.Properties.Name -contains "request_timestamp") { [string]$ApprovalTarget.request_timestamp } elseif ($ApprovalRecord -and $ApprovalRecord.PSObject.Properties.Name -contains "request_timestamp") { [string]$ApprovalRecord.request_timestamp } else { "" }) -ApprovalResponseTimestamp $(if ($ApprovalTarget -and $ApprovalTarget.PSObject.Properties.Name -contains "response_timestamp") { [string]$ApprovalTarget.response_timestamp } elseif ($ApprovalRecord -and $ApprovalRecord.PSObject.Properties.Name -contains "response_timestamp") { [string]$ApprovalRecord.response_timestamp } else { "" }) -ApprovalHistory $(if ($ApprovalTarget -and $ApprovalTarget.PSObject.Properties.Name -contains "history") { $ApprovalTarget.history } elseif ($ApprovalRecord -and $ApprovalRecord.PSObject.Properties.Name -contains "history") { $ApprovalRecord.history } else { @() }) -PendingRecommendedCommand $(if ($ShouldClearPending) { "" } else { [string]$PendingAction.recommended_command }) -PendingDispatchCategory $(if ($ShouldClearPending) { "" } else { [string]$PendingAction.dispatch_category }) -PendingOriginalMessage $(if ($ShouldClearPending) { "" } else { [string]$PendingAction.original_message }) -PendingTimestamp $(if ($ShouldClearPending) { "" } else { [string]$PendingAction.timestamp }) -PendingExpiresAt $(if ($ShouldClearPending) { "" } else { [string]$PendingAction.expires_at }) -PendingStatus $(if ($ShouldClearPending) { "" } else { $ApprovalActionStatus }) $(if ($ShouldClearPending) { "-ClearPendingAction" } else { "" }) | Out-Null
        }

        $Result = [pscustomobject]@{
            original_message         = $Message
            response_text            = $ApprovalResponseText
            recommended_command      = $(if ($PendingAction) { [string]$PendingAction.recommended_command } else { "" })
            intent                   = "approval_action"
            route_type               = "approval_action"
            confidence               = 1
            requires_confirmation    = $false
            dispatch_ready           = $false
            dispatch_status          = "not_dispatched"
            next_action              = $(if ($ShouldClearPending) { "Use /planner or ask for a revised goal plan." } else { "The approval remains active." })
            bridge_status            = "ready"
            handoff_status           = $ApprovalActionStatus
            source_of_truth          = "Scripts/PDA_ApprovalWorkflow.ps1"
            confirmation_mode        = [bool]$ConfirmDispatch
            dispatch_path            = ""
            dispatch_category        = $(if ($PendingAction) { [string]$PendingAction.dispatch_category } else { "" })
            conversation_id          = $(if ($ConversationId) { $ConversationId } elseif ($ConversationState -and $ConversationState.conversation_id) { [string]$ConversationState.conversation_id } else { "" })
            session_id               = $SessionId
            conversation_state_status = if ($ConversationState) { [string]$ConversationState.status } else { "empty" }
            latest_task_id           = if ($ConversationState -and $ConversationState.latest_task) { [string]$ConversationState.latest_task.task_id } else { "" }
            latest_task_status       = if ($ConversationState -and $ConversationState.latest_task) { [string]$ConversationState.latest_task.task_status } else { "" }
            latest_result_path       = if ($ConversationState -and $ConversationState.latest_result) { [string]$ConversationState.latest_result.result_path } else { "" }
            latest_result_response_text = if ($ConversationState) { [string]$ConversationState.response_text } else { "" }
            result_artifact_path     = if ($ConversationState -and $ConversationState.latest_result) { [string]$ConversationState.latest_result.result_path } else { "" }
            result_artifact          = if ($ConversationState) { $ConversationState.latest_result } else { $null }
            decision                 = $script:PDACommanderDecision
            bridge_mode              = "approval_action"
            pending_action           = if ($PendingAction) { $PendingAction } else { $null }
            approval_id              = $ApprovalIdForAction
            approval_status          = $ApprovalActionStatus
            approval_path            = $(if (-not [string]::IsNullOrWhiteSpace($ApprovalIdForAction) -and $ApprovalTarget -and $ApprovalTarget.PSObject.Properties.Name -contains "approval_path") { [string]$ApprovalTarget.approval_path } elseif ($ApprovalRecord -and $ApprovalRecord.PSObject.Properties.Name -contains "approval_path") { [string]$ApprovalRecord.approval_path } else { "" })
        }
        $Result = Add-PDACommanderRuntimeContextFields -Result $Result

        if ($AsJson) {
            $Result | ConvertTo-Json -Depth 20
            return
        }

        Write-Host "[OK] PDA chat bridge result:"
        Write-Host ("Response text        : {0}" -f $Result.response_text)
        Write-Host ("Recommended command  : {0}" -f $(if ($Result.recommended_command) { $Result.recommended_command } else { "(none)" }))
        Write-Host ("Intent               : {0}" -f $(if ($Result.intent) { $Result.intent } else { "(none)" }))
        Write-Host ("Confidence           : {0}" -f $Result.confidence)
        Write-Host ("Dispatch ready       : {0}" -f $Result.dispatch_ready)
        Write-Host ("Dispatch status      : {0}" -f $Result.dispatch_status)
        Write-Host ("Next action          : {0}" -f $Result.next_action)
        return
    }
}

$ConversationRoute = $null
if (Get-Command -Name Resolve-PDAConversationalRoute -ErrorAction SilentlyContinue) {
    $ConversationRoute = Resolve-PDAConversationalRoute -Text $Message -Root $Root
    $script:PDAConversationRouteType = if ($ConversationRoute -and $ConversationRoute.PSObject.Properties.Name -contains "route_type") { [string]$ConversationRoute.route_type } else { "" }
    $script:PDACommanderDecision = Get-PDABridgeCommanderDecision -Text $Message -ConversationRoute $ConversationRoute -Root $Root
    if ($ConversationRoute -and -not ($IsConfirmationMessage -and $HasPendingAction)) {
        switch ([string]$ConversationRoute.route_type) {
            "direct_status" {
                $DirectResult = Get-PDAConversationalNaturalResponse -Route $ConversationRoute -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Text $Message -Root $Root
                $DirectResult = Set-PDABridgeDecisionMetadata -Result $DirectResult -RouteType ([string]$ConversationRoute.route_type) -Decision $script:PDACommanderDecision
                Invoke-PDAConversationStateUpdate -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Message $Message -TaskId ([string]$DirectResult.latest_task_id) -TaskStatus ([string]$DirectResult.latest_task_status) -TaskFilePath "" -ApprovalFilePath "" -ResultPath ([string]$DirectResult.latest_result_path) -ResultSummary "" -BridgeStatus ([string]$DirectResult.bridge_status) -DispatchStatus ([string]$DirectResult.dispatch_status) -NextAction ([string]$DirectResult.next_action) -ResponseText ([string]$DirectResult.response_text) -RecommendedCommand ([string]$DirectResult.recommended_command) -Intent ([string]$DirectResult.intent) -Confidence ([double]$DirectResult.confidence) -RequiresConfirmation:$false | Out-Null

                $DirectResult = Add-PDACommanderRuntimeContextFields -Result $DirectResult

                if ($AsJson) {
                    $DirectResult | ConvertTo-Json -Depth 20
                    return
                }

                Write-Host "[OK] PDA chat bridge result:"
                Write-Host ("Response text        : {0}" -f $DirectResult.response_text)
                Write-Host ("Recommended command  : {0}" -f $(if ($DirectResult.recommended_command) { $DirectResult.recommended_command } else { "(none)" }))
                Write-Host ("Intent               : {0}" -f $(if ($DirectResult.intent) { $DirectResult.intent } else { "(none)" }))
                Write-Host ("Confidence           : {0}" -f $DirectResult.confidence)
                Write-Host ("Dispatch ready       : {0}" -f $DirectResult.dispatch_ready)
                Write-Host ("Dispatch status      : {0}" -f $DirectResult.dispatch_status)
                Write-Host ("Next action          : {0}" -f $DirectResult.next_action)
                return
            }
            "direct_help" {
                $DirectResult = Get-PDAConversationalNaturalResponse -Route $ConversationRoute -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Text $Message -Root $Root
                $DirectResult = Set-PDABridgeDecisionMetadata -Result $DirectResult -RouteType ([string]$ConversationRoute.route_type) -Decision $script:PDACommanderDecision
                Invoke-PDAConversationStateUpdate -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Message $Message -TaskId ([string]$DirectResult.latest_task_id) -TaskStatus ([string]$DirectResult.latest_task_status) -TaskFilePath "" -ApprovalFilePath "" -ResultPath ([string]$DirectResult.latest_result_path) -ResultSummary "" -BridgeStatus ([string]$DirectResult.bridge_status) -DispatchStatus ([string]$DirectResult.dispatch_status) -NextAction ([string]$DirectResult.next_action) -ResponseText ([string]$DirectResult.response_text) -RecommendedCommand ([string]$DirectResult.recommended_command) -Intent ([string]$DirectResult.intent) -Confidence ([double]$DirectResult.confidence) -RequiresConfirmation:$false | Out-Null

                $DirectResult = Add-PDACommanderRuntimeContextFields -Result $DirectResult

                if ($AsJson) {
                    $DirectResult | ConvertTo-Json -Depth 20
                    return
                }

                Write-Host "[OK] PDA chat bridge result:"
                Write-Host ("Response text        : {0}" -f $DirectResult.response_text)
                Write-Host ("Recommended command  : {0}" -f $(if ($DirectResult.recommended_command) { $DirectResult.recommended_command } else { "(none)" }))
                Write-Host ("Intent               : {0}" -f $(if ($DirectResult.intent) { $DirectResult.intent } else { "(none)" }))
                Write-Host ("Confidence           : {0}" -f $DirectResult.confidence)
                Write-Host ("Dispatch ready       : {0}" -f $DirectResult.dispatch_ready)
                Write-Host ("Dispatch status      : {0}" -f $DirectResult.dispatch_status)
                Write-Host ("Next action          : {0}" -f $DirectResult.next_action)
                return
            }
            "task_lookup" {
                $DirectResult = Get-PDAConversationalNaturalResponse -Route $ConversationRoute -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Text $Message -Root $Root
                $DirectResult = Set-PDABridgeDecisionMetadata -Result $DirectResult -RouteType ([string]$ConversationRoute.route_type) -Decision $script:PDACommanderDecision
                Invoke-PDAConversationStateUpdate -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Message $Message -TaskId ([string]$DirectResult.latest_task_id) -TaskStatus ([string]$DirectResult.latest_task_status) -TaskFilePath "" -ApprovalFilePath "" -ResultPath ([string]$DirectResult.latest_result_path) -ResultSummary "" -BridgeStatus ([string]$DirectResult.bridge_status) -DispatchStatus ([string]$DirectResult.dispatch_status) -NextAction ([string]$DirectResult.next_action) -ResponseText ([string]$DirectResult.response_text) -RecommendedCommand ([string]$DirectResult.recommended_command) -Intent ([string]$DirectResult.intent) -Confidence ([double]$DirectResult.confidence) -RequiresConfirmation:$false | Out-Null

                if ($AsJson) {
                    $DirectResult | ConvertTo-Json -Depth 20
                    return
                }

                Write-Host "[OK] PDA chat bridge result:"
                Write-Host ("Response text        : {0}" -f $DirectResult.response_text)
                Write-Host ("Recommended command  : {0}" -f $(if ($DirectResult.recommended_command) { $DirectResult.recommended_command } else { "(none)" }))
                Write-Host ("Intent               : {0}" -f $(if ($DirectResult.intent) { $DirectResult.intent } else { "(none)" }))
                Write-Host ("Confidence           : {0}" -f $DirectResult.confidence)
                Write-Host ("Dispatch ready       : {0}" -f $DirectResult.dispatch_ready)
                Write-Host ("Dispatch status      : {0}" -f $DirectResult.dispatch_status)
                Write-Host ("Next action          : {0}" -f $DirectResult.next_action)
                return
            }
            "memory_candidates" {
                $DirectResult = Get-PDAConversationalNaturalResponse -Route $ConversationRoute -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Text $Message -Root $Root
                $DirectResult = Set-PDABridgeDecisionMetadata -Result $DirectResult -RouteType ([string]$ConversationRoute.route_type) -Decision $script:PDACommanderDecision
                Invoke-PDAConversationStateUpdate -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Message $Message -TaskId ([string]$DirectResult.latest_task_id) -TaskStatus ([string]$DirectResult.latest_task_status) -TaskFilePath "" -ApprovalFilePath "" -ResultPath ([string]$DirectResult.latest_result_path) -ResultSummary "" -BridgeStatus ([string]$DirectResult.bridge_status) -DispatchStatus ([string]$DirectResult.dispatch_status) -NextAction ([string]$DirectResult.next_action) -ResponseText ([string]$DirectResult.response_text) -RecommendedCommand ([string]$DirectResult.recommended_command) -Intent ([string]$DirectResult.intent) -Confidence ([double]$DirectResult.confidence) -RequiresConfirmation:$false | Out-Null

                if ($AsJson) {
                    $DirectResult | ConvertTo-Json -Depth 20
                    return
                }

                Write-Host "[OK] PDA chat bridge result:"
                Write-Host ("Response text        : {0}" -f $DirectResult.response_text)
                Write-Host ("Recommended command  : {0}" -f $(if ($DirectResult.recommended_command) { $DirectResult.recommended_command } else { "(none)" }))
                Write-Host ("Intent               : {0}" -f $(if ($DirectResult.intent) { $DirectResult.intent } else { "(none)" }))
                Write-Host ("Confidence           : {0}" -f $DirectResult.confidence)
                Write-Host ("Dispatch ready       : {0}" -f $DirectResult.dispatch_ready)
                Write-Host ("Dispatch status      : {0}" -f $DirectResult.dispatch_status)
                Write-Host ("Next action          : {0}" -f $DirectResult.next_action)
                return
            }
            "commander_briefing" {
                $DirectResult = Get-PDAConversationalNaturalResponse -Route $ConversationRoute -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Text $Message -Root $Root
                $DirectResult = Set-PDABridgeDecisionMetadata -Result $DirectResult -RouteType ([string]$ConversationRoute.route_type) -Decision $script:PDACommanderDecision
                Invoke-PDAConversationStateUpdate -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Message $Message -TaskId ([string]$DirectResult.latest_task_id) -TaskStatus ([string]$DirectResult.latest_task_status) -TaskFilePath "" -ApprovalFilePath "" -ResultPath ([string]$DirectResult.latest_result_path) -ResultSummary "" -BridgeStatus ([string]$DirectResult.bridge_status) -DispatchStatus ([string]$DirectResult.dispatch_status) -NextAction ([string]$DirectResult.next_action) -ResponseText ([string]$DirectResult.response_text) -RecommendedCommand ([string]$DirectResult.recommended_command) -Intent ([string]$DirectResult.intent) -Confidence ([double]$DirectResult.confidence) -RequiresConfirmation:$false | Out-Null

                if ($AsJson) {
                    $DirectResult | ConvertTo-Json -Depth 20
                    return
                }

                Write-Host "[OK] PDA chat bridge result:"
                Write-Host ("Response text        : {0}" -f $DirectResult.response_text)
                Write-Host ("Recommended command  : {0}" -f $(if ($DirectResult.recommended_command) { $DirectResult.recommended_command } else { "(none)" }))
                Write-Host ("Intent               : {0}" -f $(if ($DirectResult.intent) { $DirectResult.intent } else { "(none)" }))
                Write-Host ("Confidence           : {0}" -f $DirectResult.confidence)
                Write-Host ("Dispatch ready       : {0}" -f $DirectResult.dispatch_ready)
                Write-Host ("Dispatch status      : {0}" -f $DirectResult.dispatch_status)
                Write-Host ("Next action          : {0}" -f $DirectResult.next_action)
                return
            }
            "dispatch_guidance" {
                $DirectResult = Get-PDAConversationalNaturalResponse -Route $ConversationRoute -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Text $Message -Root $Root
                $DirectResult = Set-PDABridgeDecisionMetadata -Result $DirectResult -RouteType ([string]$ConversationRoute.route_type) -Decision $script:PDACommanderDecision
                Invoke-PDAConversationStateUpdate -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Message $Message -TaskId "" -TaskStatus "" -TaskFilePath "" -ApprovalFilePath "" -ResultPath "" -ResultSummary "" -BridgeStatus ([string]$DirectResult.bridge_status) -DispatchStatus ([string]$DirectResult.dispatch_status) -NextAction ([string]$DirectResult.next_action) -ResponseText ([string]$DirectResult.response_text) -RecommendedCommand ([string]$DirectResult.recommended_command) -Intent ([string]$DirectResult.intent) -Confidence ([double]$DirectResult.confidence) -RequiresConfirmation:$false | Out-Null

                if ($AsJson) {
                    $DirectResult | ConvertTo-Json -Depth 20
                    return
                }

                Write-Host "[OK] PDA chat bridge result:"
                Write-Host ("Response text        : {0}" -f $DirectResult.response_text)
                Write-Host ("Recommended command  : {0}" -f $(if ($DirectResult.recommended_command) { $DirectResult.recommended_command } else { "(none)" }))
                Write-Host ("Intent               : {0}" -f $(if ($DirectResult.intent) { $DirectResult.intent } else { "(none)" }))
                Write-Host ("Confidence           : {0}" -f $DirectResult.confidence)
                Write-Host ("Dispatch ready       : {0}" -f $DirectResult.dispatch_ready)
                Write-Host ("Dispatch status      : {0}" -f $DirectResult.dispatch_status)
                Write-Host ("Next action          : {0}" -f $DirectResult.next_action)
                return
            }
            "environment_awareness" {
                $DirectResult = Get-PDAConversationalNaturalResponse -Route $ConversationRoute -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Text $Message -Root $Root
                $DirectResult = Set-PDABridgeDecisionMetadata -Result $DirectResult -RouteType ([string]$ConversationRoute.route_type) -Decision $script:PDACommanderDecision
                Invoke-PDAConversationStateUpdate -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Message $Message -TaskId "" -TaskStatus "" -TaskFilePath "" -ApprovalFilePath "" -ResultPath "" -ResultSummary "" -BridgeStatus ([string]$DirectResult.bridge_status) -DispatchStatus ([string]$DirectResult.dispatch_status) -NextAction ([string]$DirectResult.next_action) -ResponseText ([string]$DirectResult.response_text) -RecommendedCommand ([string]$DirectResult.recommended_command) -Intent ([string]$DirectResult.intent) -Confidence ([double]$DirectResult.confidence) -RequiresConfirmation:$false | Out-Null

                if ($AsJson) {
                    $DirectResult | ConvertTo-Json -Depth 20
                    return
                }

                Write-Host "[OK] PDA chat bridge result:"
                Write-Host ("Response text        : {0}" -f $DirectResult.response_text)
                Write-Host ("Recommended command  : {0}" -f $(if ($DirectResult.recommended_command) { $DirectResult.recommended_command } else { "(none)" }))
                Write-Host ("Intent               : {0}" -f $(if ($DirectResult.intent) { $DirectResult.intent } else { "(none)" }))
                Write-Host ("Confidence           : {0}" -f $DirectResult.confidence)
                Write-Host ("Dispatch ready       : {0}" -f $DirectResult.dispatch_ready)
                Write-Host ("Dispatch status      : {0}" -f $DirectResult.dispatch_status)
                Write-Host ("Next action          : {0}" -f $DirectResult.next_action)
                return
            }
            "goal_planning" {
                $DirectResult = Get-PDAConversationalNaturalResponse -Route $ConversationRoute -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Text $Message -Root $Root
                $DirectResult = Set-PDABridgeDecisionMetadata -Result $DirectResult -RouteType ([string]$ConversationRoute.route_type) -Decision $script:PDACommanderDecision
                $GoalPlan = if ($DirectResult.PSObject.Properties.Name -contains "goal_plan") { $DirectResult.goal_plan } else { $null }
                $ExecutionPlan = if ($DirectResult.PSObject.Properties.Name -contains "execution_plan") { $DirectResult.execution_plan } else { $null }
                $GoalPlanRequiresConfirmation = [bool](
                    ($GoalPlan -and $GoalPlan.PSObject.Properties.Name -contains "approval_required" -and [bool]$GoalPlan.approval_required) -or
                    ($ExecutionPlan -and $ExecutionPlan.PSObject.Properties.Name -contains "approval_required" -and [bool]$ExecutionPlan.approval_required)
                )
                $PendingCommand = ""
                if ($script:PDACommanderDecision -and $script:PDACommanderDecision.PSObject.Properties.Name -contains "recommended_command" -and -not [string]::IsNullOrWhiteSpace([string]$script:PDACommanderDecision.recommended_command)) {
                    $PendingCommand = [string]$script:PDACommanderDecision.recommended_command
                }
                elseif ($DirectResult.PSObject.Properties.Name -contains "recommended_command" -and -not [string]::IsNullOrWhiteSpace([string]$DirectResult.recommended_command)) {
                    $PendingCommand = [string]$DirectResult.recommended_command
                }
                elseif ($GoalPlanRequiresConfirmation) {
                    $PendingCommand = "/planner"
                }

                $PendingCategory = "category_1"
                if ($script:PDACommanderDecision -and $script:PDACommanderDecision.PSObject.Properties.Name -contains "classification" -and $script:PDACommanderDecision.classification -and $script:PDACommanderDecision.classification.PSObject.Properties.Name -contains "category" -and -not [string]::IsNullOrWhiteSpace([string]$script:PDACommanderDecision.classification.category)) {
                    $PendingCategory = [string]$script:PDACommanderDecision.classification.category
                }

                $PendingTaskId = ""
                if ($ExecutionPlan -and $ExecutionPlan.PSObject.Properties.Name -contains "plan_id" -and -not [string]::IsNullOrWhiteSpace([string]$ExecutionPlan.plan_id)) {
                    $PendingTaskId = [string]$ExecutionPlan.plan_id
                }
                elseif ($GoalPlan -and $GoalPlan.PSObject.Properties.Name -contains "plan_id" -and -not [string]::IsNullOrWhiteSpace([string]$GoalPlan.plan_id)) {
                    $PendingTaskId = [string]$GoalPlan.plan_id
                }

                $GoalPlanDecision = [pscustomobject]@{
                    decision_id = if ($script:PDACommanderDecision -and $script:PDACommanderDecision.PSObject.Properties.Name -contains "decision_id" -and -not [string]::IsNullOrWhiteSpace([string]$script:PDACommanderDecision.decision_id)) { [string]$script:PDACommanderDecision.decision_id } else { [guid]::NewGuid().ToString() }
                    created_at = if ($script:PDACommanderDecision -and $script:PDACommanderDecision.PSObject.Properties.Name -contains "created_at" -and -not [string]::IsNullOrWhiteSpace([string]$script:PDACommanderDecision.created_at)) { [string]$script:PDACommanderDecision.created_at } else { (Get-Date).ToUniversalTime().ToString("o") }
                    source = [pscustomobject]@{
                        surface = "decision_engine"
                        script = "Scripts/PDA_DecisionEngine.ps1"
                    }
                    request = [pscustomobject]@{
                        text = [string]$Message
                        conversation_id = [string]$ConversationId
                        session_id = [string]$SessionId
                        user_id = [string]$UserId
                        root_path = [string]$Root
                    }
                    decision_type = "plan"
                    classification = [pscustomobject]@{
                        decision_type = "plan"
                        intent = "goal_planning"
                        task_type = if ($GoalPlan -and $GoalPlan.PSObject.Properties.Name -contains "goal_type" -and -not [string]::IsNullOrWhiteSpace([string]$GoalPlan.goal_type)) { [string]$GoalPlan.goal_type } else { "goal_planning" }
                        goal_type = if ($ExecutionPlan -and $ExecutionPlan.PSObject.Properties.Name -contains "goal_type") { [string]$ExecutionPlan.goal_type } elseif ($GoalPlan -and $GoalPlan.PSObject.Properties.Name -contains "goal_type") { [string]$GoalPlan.goal_type } else { "" }
                        category = $PendingCategory
                        confidence = if ($DirectResult.PSObject.Properties.Name -contains "confidence") { [double]$DirectResult.confidence } else { 0.9 }
                        ambiguous = $false
                    }
                    governance = [pscustomobject]@{
                        allowed = $true
                        requires_confirmation = $GoalPlanRequiresConfirmation
                        approval_required = $GoalPlanRequiresConfirmation
                        requires_local_only = ($PendingCategory -in @("category_2", "restricted_local"))
                        blocked_reason = ""
                    }
                    routing = [pscustomobject]@{
                        recommended_command = $PendingCommand
                        recommended_executor = if ($GoalPlan -and $GoalPlan.PSObject.Properties.Name -contains "goal_type" -and [string]$GoalPlan.goal_type -eq "data_validation_report") { "execute-worker" } else { "planner-worker" }
                        recommended_workflow = "goal_planning"
                        dispatch_target = "planner"
                        next_action = [string]$DirectResult.next_action
                        response_mode = "direct_answer"
                    }
                    plan = [pscustomobject]@{
                        goal_plan = $GoalPlan
                        execution_plan = $ExecutionPlan
                        subtasks = if ($ExecutionPlan -and $ExecutionPlan.PSObject.Properties.Name -contains "subtasks") { @($ExecutionPlan.subtasks) } else { @() }
                        deliverables = if ($ExecutionPlan -and $ExecutionPlan.PSObject.Properties.Name -contains "deliverables") { @($ExecutionPlan.deliverables) } else { @() }
                    }
                    diagnostics = [pscustomobject]@{
                        reason = if ($GoalPlan -and $GoalPlan.PSObject.Properties.Name -contains "next_action" -and -not [string]::IsNullOrWhiteSpace([string]$GoalPlan.next_action)) { [string]$GoalPlan.next_action } else { "Goal plan requires approval." }
                        fallback_reason = ""
                        matched_rules = @("goal_planning")
                        capability_route = $null
                        executor_recommendation = $null
                    }
                    route_type = "goal_planning"
                    intent = "goal_planning"
                    task_type = if ($GoalPlan -and $GoalPlan.PSObject.Properties.Name -contains "goal_type" -and -not [string]::IsNullOrWhiteSpace([string]$GoalPlan.goal_type)) { [string]$GoalPlan.goal_type } else { "goal_planning" }
                    recommended_command = $PendingCommand
                    recommended_executor = if ($GoalPlan -and $GoalPlan.PSObject.Properties.Name -contains "goal_type" -and [string]$GoalPlan.goal_type -eq "data_validation_report") { "execute-worker" } else { "planner-worker" }
                    requires_confirmation = $GoalPlanRequiresConfirmation
                    dispatch_ready = $false
                    dispatch_status = "not_dispatched"
                    response_mode = "direct_answer"
                    allowed = $true
                    blocked_reason = ""
                    source_of_truth = "Scripts/Invoke-PDAChatBridge.ps1"
                }

                $PendingTimestamp = (Get-Date).ToUniversalTime().ToString("o")
                $PendingExpiresAt = (Get-Date).ToUniversalTime().AddMinutes((Get-PDAPendingConfirmationTimeoutMinutes)).ToString("o")
                $GoalPlanApproval = $null
                if ($GoalPlanRequiresConfirmation -and (Get-Command -Name New-PDAApprovalRequest -ErrorAction SilentlyContinue)) {
                    try {
                        $GoalPlanApproval = New-PDAApprovalRequest -RunId ([string]$PendingTaskId) -ConversationId $(if ($ConversationId) { $ConversationId } else { "" }) -SessionId $(if ($SessionId) { $SessionId } else { "" }) -Goal ([string]$GoalPlan.goal) -RequestedAction ([string]$PendingCommand) -Category ([string]$PendingCategory) -RouteType ([string]$ConversationRoute.route_type) -RecommendedCommand ([string]$PendingCommand) -RecommendedExecutor ([string]$GoalPlanDecision.recommended_executor) -DispatchCategory ([string]$PendingCategory) -UserMessage $Message -ApprovalKind "goal_plan" -ApprovalRationale "Goal plan requires human approval before dispatch." -Root $Root
                    }
                    catch {
                        $GoalPlanApproval = $null
                    }
                }

                if ($GoalPlanRequiresConfirmation) {
                    $DirectResult | Add-Member -NotePropertyName requires_confirmation -NotePropertyValue $true -Force
                    $DirectResult | Add-Member -NotePropertyName dispatch_ready -NotePropertyValue $false -Force
                    $DirectResult | Add-Member -NotePropertyName dispatch_status -NotePropertyValue "not_dispatched" -Force
                    $DirectResult | Add-Member -NotePropertyName pending_action -NotePropertyValue ([pscustomobject]@{
                        recommended_command = $PendingCommand
                        dispatch_category    = $PendingCategory
                        original_message     = $Message
                        timestamp            = $PendingTimestamp
                        expires_at           = $PendingExpiresAt
                        status               = "awaiting_confirmation"
                        is_expired           = $false
                    }) -Force
                    $DirectResult | Add-Member -NotePropertyName pending_confirmation -NotePropertyValue $true -Force
                    $DirectResult | Add-Member -NotePropertyName pending_recommended_command -NotePropertyValue $PendingCommand -Force
                    $DirectResult | Add-Member -NotePropertyName pending_dispatch_category -NotePropertyValue $PendingCategory -Force
                    if ($GoalPlanApproval) {
                        $DirectResult | Add-Member -NotePropertyName approval_id -NotePropertyValue ([string]$GoalPlanApproval.approval_id) -Force
                        $DirectResult | Add-Member -NotePropertyName approval_path -NotePropertyValue ([string]$GoalPlanApproval.approval_path) -Force
                    }
                }

                Invoke-PDAConversationStateUpdate -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Message $Message -TaskId $PendingTaskId -TaskStatus $(if ($GoalPlanRequiresConfirmation) { "pending_confirmation" } else { "" }) -TaskFilePath "" -ApprovalFilePath $(if ($GoalPlanApproval) { [string]$GoalPlanApproval.approval_path } else { "" }) -ResultPath "" -ResultSummary "" -BridgeStatus ([string]$DirectResult.bridge_status) -DispatchStatus ([string]$DirectResult.dispatch_status) -NextAction ([string]$DirectResult.next_action) -ResponseText ([string]$DirectResult.response_text) -RecommendedCommand $PendingCommand -Intent ([string]$DirectResult.intent) -Confidence ([double]$DirectResult.confidence) -RequiresConfirmation:([bool]$GoalPlanRequiresConfirmation) -ApprovalId $(if ($GoalPlanApproval) { [string]$GoalPlanApproval.approval_id } else { "" }) -ApprovalStatus $(if ($GoalPlanRequiresConfirmation) { "pending_approval" } else { "" }) -ApprovalPath $(if ($GoalPlanApproval) { [string]$GoalPlanApproval.approval_path } else { "" }) -ApprovalRequestedAction $PendingCommand -ApprovalRationale "Goal plan requires human approval before dispatch." -ApprovalRequestTimestamp $(if ($GoalPlanApproval -and $GoalPlanApproval.approval -and $GoalPlanApproval.approval.PSObject.Properties.Name -contains "request_timestamp") { [string]$GoalPlanApproval.approval.request_timestamp } else { $PendingTimestamp }) -ApprovalHistory $(if ($GoalPlanApproval -and $GoalPlanApproval.approval -and $GoalPlanApproval.approval.PSObject.Properties.Name -contains "history") { $GoalPlanApproval.approval.history } else { @() }) -ApprovalKind "goal_plan" -PendingRecommendedCommand $PendingCommand -PendingDispatchCategory $PendingCategory -PendingOriginalMessage $Message -PendingTimestamp $PendingTimestamp -PendingExpiresAt $PendingExpiresAt -PendingStatus $(if ($GoalPlanRequiresConfirmation) { "awaiting_confirmation" } else { "" }) -Decision $GoalPlanDecision -RouteType ([string]$ConversationRoute.route_type) | Out-Null
                $DirectResult = Set-PDABridgeDecisionMetadata -Result $DirectResult -RouteType ([string]$ConversationRoute.route_type) -Decision $GoalPlanDecision
                $DirectResult = Add-PDACommanderRuntimeContextFields -Result $DirectResult

                if ($AsJson) {
                    $DirectResult | ConvertTo-Json -Depth 20
                    return
                }

                Write-Host "[OK] PDA chat bridge result:"
                Write-Host ("Response text        : {0}" -f $DirectResult.response_text)
                Write-Host ("Recommended command  : {0}" -f $(if ($DirectResult.recommended_command) { $DirectResult.recommended_command } else { "(none)" }))
                Write-Host ("Intent               : {0}" -f $(if ($DirectResult.intent) { $DirectResult.intent } else { "(none)" }))
                Write-Host ("Confidence           : {0}" -f $DirectResult.confidence)
                Write-Host ("Dispatch ready       : {0}" -f $DirectResult.dispatch_ready)
                Write-Host ("Dispatch status      : {0}" -f $DirectResult.dispatch_status)
                Write-Host ("Next action          : {0}" -f $DirectResult.next_action)
                return
            }
            "ambiguous" {
                $DirectResult = Get-PDAConversationalNaturalResponse -Route $ConversationRoute -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Text $Message -Root $Root
                $DirectResult = Set-PDABridgeDecisionMetadata -Result $DirectResult -RouteType ([string]$ConversationRoute.route_type) -Decision $script:PDACommanderDecision
                Invoke-PDAConversationStateUpdate -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Message $Message -TaskId "" -TaskStatus "" -TaskFilePath "" -ApprovalFilePath "" -ResultPath "" -ResultSummary "" -BridgeStatus ([string]$DirectResult.bridge_status) -DispatchStatus ([string]$DirectResult.dispatch_status) -NextAction ([string]$DirectResult.next_action) -ResponseText ([string]$DirectResult.response_text) -RecommendedCommand ([string]$DirectResult.recommended_command) -Intent ([string]$DirectResult.intent) -Confidence ([double]$DirectResult.confidence) -RequiresConfirmation:$false | Out-Null
                $DirectResult = Add-PDACommanderRuntimeContextFields -Result $DirectResult

                if ($AsJson) {
                    $DirectResult | ConvertTo-Json -Depth 20
                    return
                }

                Write-Host "[OK] PDA chat bridge result:"
                Write-Host ("Response text        : {0}" -f $DirectResult.response_text)
                Write-Host ("Recommended command  : {0}" -f $(if ($DirectResult.recommended_command) { $DirectResult.recommended_command } else { "(none)" }))
                Write-Host ("Intent               : {0}" -f $(if ($DirectResult.intent) { $DirectResult.intent } else { "(none)" }))
                Write-Host ("Confidence           : {0}" -f $DirectResult.confidence)
                Write-Host ("Dispatch ready       : {0}" -f $DirectResult.dispatch_ready)
                Write-Host ("Dispatch status      : {0}" -f $DirectResult.dispatch_status)
                Write-Host ("Next action          : {0}" -f $DirectResult.next_action)
                return
            }
            "fallback" {
                $DirectResult = Get-PDAConversationalNaturalResponse -Route $ConversationRoute -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Text $Message -Root $Root
                $DirectResult = Set-PDABridgeDecisionMetadata -Result $DirectResult -RouteType ([string]$ConversationRoute.route_type) -Decision $script:PDACommanderDecision
                Invoke-PDAConversationStateUpdate -TaskId "" -TaskStatus "" -TaskFilePath "" -ApprovalFilePath "" -ResultPath "" -ResultSummary "" -BridgeStatus ([string]$DirectResult.bridge_status) -DispatchStatus ([string]$DirectResult.dispatch_status) -NextAction ([string]$DirectResult.next_action) -ResponseText ([string]$DirectResult.response_text) -RecommendedCommand ([string]$DirectResult.recommended_command) -Intent ([string]$DirectResult.intent) -Confidence ([double]$DirectResult.confidence) -RequiresConfirmation:$false | Out-Null
                $DirectResult = Add-PDACommanderRuntimeContextFields -Result $DirectResult

                if ($AsJson) {
                    $DirectResult | ConvertTo-Json -Depth 20
                    return
                }

                Write-Host "[OK] PDA chat bridge result:"
                Write-Host ("Response text        : {0}" -f $DirectResult.response_text)
                Write-Host ("Recommended command  : {0}" -f $(if ($DirectResult.recommended_command) { $DirectResult.recommended_command } else { "(none)" }))
                Write-Host ("Intent               : {0}" -f $(if ($DirectResult.intent) { $DirectResult.intent } else { "(none)" }))
                Write-Host ("Confidence           : {0}" -f $DirectResult.confidence)
                Write-Host ("Dispatch ready       : {0}" -f $DirectResult.dispatch_ready)
                Write-Host ("Dispatch status      : {0}" -f $DirectResult.dispatch_status)
                Write-Host ("Next action          : {0}" -f $DirectResult.next_action)
                return
            }
            "slash_command" {
                $HandoffInputMessage = $Message
                $UseLegacyStatusLookup = $false
            }
            "governed_request" {
                $HandoffInputMessage = if (-not [string]::IsNullOrWhiteSpace([string]$ConversationRoute.synthetic_text)) { [string]$ConversationRoute.synthetic_text } else { $Message }
                $UseLegacyStatusLookup = $false
            }
            default {
                $UseLegacyStatusLookup = $false
            }
        }
    }
}

if ($IsConfirmationMessage -and -not $HasPendingAction) {
    if ($PendingAction -and [bool]$PendingAction.is_expired) {
        Invoke-PDAConversationStateUpdate -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Message $Message -TaskId "" -TaskStatus "" -ResultPath "" -BridgeStatus "ready" -DispatchStatus "not_dispatched" -NextAction "Start a new request or ask for a status refresh." -ResponseText "Pending confirmation expired for this conversation." -RecommendedCommand "" -Intent "confirmation" -Confidence 1 -RequiresConfirmation:$false -ClearPendingAction | Out-Null
    }

    $Result = [pscustomobject]@{
        original_message         = $Message
        response_text            = "No pending governed action found for this conversation."
        recommended_command      = ""
        intent                   = "confirmation"
        route_type               = "confirmation"
        confidence               = 1
        requires_confirmation    = $false
        dispatch_ready           = $false
        dispatch_status          = "not_dispatched"
        next_action              = "Start a new request or request a status lookup."
        bridge_status            = "ready"
        handoff_status           = "no_pending_confirmation"
        source_of_truth          = "Scripts/Get-PDAConversationState.ps1"
        confirmation_mode        = [bool]$ConfirmDispatch
        dispatch_path            = ""
        dispatch_category        = ""
        conversation_id          = $(if ($ConversationId) { $ConversationId } elseif ($ConversationState -and $ConversationState.conversation_id) { [string]$ConversationState.conversation_id } else { "" })
        session_id               = $SessionId
        conversation_state_status = if ($ConversationState) { [string]$ConversationState.status } else { "empty" }
        latest_task_id           = if ($ConversationState -and $ConversationState.latest_task) { [string]$ConversationState.latest_task.task_id } else { "" }
        latest_task_status       = if ($ConversationState -and $ConversationState.latest_task) { [string]$ConversationState.latest_task.task_status } else { "" }
        latest_result_path       = if ($ConversationState -and $ConversationState.latest_result) { [string]$ConversationState.latest_result.result_path } else { "" }
        latest_result_response_text = if ($ConversationState) { [string]$ConversationState.response_text } else { "" }
        result_artifact_path     = if ($ConversationState -and $ConversationState.latest_result) { [string]$ConversationState.latest_result.result_path } else { "" }
        result_artifact          = if ($ConversationState) { $ConversationState.latest_result } else { $null }
        decision                 = $script:PDACommanderDecision
        bridge_mode              = "confirmation_replay"
        pending_action           = if ($PendingAction) { $PendingAction } else { $null }
    }

    $Result = Add-PDACommanderRuntimeContextFields -Result $Result

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        return
    }

    Write-Host "[OK] PDA chat bridge result:"
    Write-Host ("Response text        : {0}" -f $Result.response_text)
    Write-Host ("Recommended command  : {0}" -f $(if ($Result.recommended_command) { $Result.recommended_command } else { "(none)" }))
    Write-Host ("Intent               : {0}" -f $(if ($Result.intent) { $Result.intent } else { "(none)" }))
    Write-Host ("Confidence           : {0}" -f $Result.confidence)
    Write-Host ("Dispatch ready       : {0}" -f $Result.dispatch_ready)
    Write-Host ("Dispatch status      : {0}" -f $Result.dispatch_status)
    Write-Host ("Next action          : {0}" -f $Result.next_action)
    return
}

if ($HasPendingAction -and ($IsConfirmationMessage -or $ConfirmDispatch)) {
    if ([string]::IsNullOrWhiteSpace([string]$PendingAction.recommended_command) -eq $false -and [string]$PendingAction.recommended_command -eq "/planner") {
        $GoalPlanPendingResponseText = if ($ConversationState -and $ConversationState.response_text) {
            [string]$ConversationState.response_text
        }
        elseif ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.latest_response_text) {
            [string]$ConversationState.conversation.latest_response_text
        }
        elseif ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.last_response_text) {
            [string]$ConversationState.conversation.last_response_text
        }
        else {
            "Goal plan remains pending approval."
        }

        $GoalPlanPendingNextAction = if ($ConversationState -and $ConversationState.next_action) {
            [string]$ConversationState.next_action
        }
        elseif ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.latest_next_action) {
            [string]$ConversationState.conversation.latest_next_action
        }
        else {
            "Review the goal plan and approve it when ready."
        }

        $Result = [pscustomobject]@{
            original_message         = $Message
            response_text            = $GoalPlanPendingResponseText
            recommended_command      = [string]$PendingAction.recommended_command
            intent                   = "goal_planning"
            route_type               = "goal_planning"
            confidence               = if ($ConversationState -and $ConversationState.pending_action -and $ConversationState.pending_action.PSObject.Properties.Name -contains "confidence" -and -not [string]::IsNullOrWhiteSpace([string]$ConversationState.pending_action.confidence)) { [double]$ConversationState.pending_action.confidence } elseif ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.pending_action -and $ConversationState.conversation.pending_action.PSObject.Properties.Name -contains "confidence") { [double]$ConversationState.conversation.pending_action.confidence } else { 0.9 }
            requires_confirmation    = $true
            dispatch_ready           = $false
            dispatch_status          = "not_dispatched"
            next_action              = $GoalPlanPendingNextAction
            bridge_status            = "ready"
            handoff_status           = "goal_plan_pending_confirmation"
            source_of_truth          = "Scripts/Get-PDAConversationState.ps1"
            confirmation_mode        = [bool]$ConfirmDispatch
            dispatch_path            = ""
            dispatch_category        = [string]$PendingAction.dispatch_category
            conversation_id          = $(if ($ConversationId) { $ConversationId } elseif ($ConversationState -and $ConversationState.conversation_id) { [string]$ConversationState.conversation_id } else { "" })
            session_id               = $SessionId
            conversation_state_status = if ($ConversationState) { [string]$ConversationState.status } else { "empty" }
            latest_task_id           = if ($ConversationState -and $ConversationState.latest_task) { [string]$ConversationState.latest_task.task_id } elseif ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.latest_task_id) { [string]$ConversationState.conversation.latest_task_id } else { "" }
            latest_task_status       = if ($ConversationState -and $ConversationState.latest_task) { [string]$ConversationState.latest_task.task_status } elseif ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.latest_task_status) { [string]$ConversationState.conversation.latest_task_status } else { "" }
            latest_result_path       = if ($ConversationState -and $ConversationState.latest_result) { [string]$ConversationState.latest_result.result_path } elseif ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.latest_result_path) { [string]$ConversationState.conversation.latest_result_path } else { "" }
            latest_result_response_text = if ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.latest_response_text) { [string]$ConversationState.conversation.latest_response_text } else { "" }
            result_artifact_path     = if ($ConversationState -and $ConversationState.latest_result) { [string]$ConversationState.latest_result.result_path } else { "" }
            result_artifact          = if ($ConversationState) { $ConversationState.latest_result } else { $null }
            decision                 = if ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.last_decision) { $ConversationState.conversation.last_decision } else { $script:PDACommanderDecision }
            bridge_mode              = "confirmation_replay"
            pending_action           = if ($PendingAction) { $PendingAction } else { $null }
            goal_plan                = if ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.goal_plan) { $ConversationState.conversation.goal_plan } else { $null }
            execution_plan           = if ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.execution_plan) { $ConversationState.conversation.execution_plan } else { $null }
        }

        if ($AsJson) {
            $Result | ConvertTo-Json -Depth 20
            return
        }

        Write-Host "[OK] PDA chat bridge result:"
        Write-Host ("Response text        : {0}" -f $Result.response_text)
        Write-Host ("Recommended command  : {0}" -f $(if ($Result.recommended_command) { $Result.recommended_command } else { "(none)" }))
        Write-Host ("Intent               : {0}" -f $(if ($Result.intent) { $Result.intent } else { "(none)" }))
        Write-Host ("Confidence           : {0}" -f $Result.confidence)
        Write-Host ("Dispatch ready       : {0}" -f $Result.dispatch_ready)
        Write-Host ("Dispatch status      : {0}" -f $Result.dispatch_status)
        Write-Host ("Next action          : {0}" -f $Result.next_action)
        return
    }

    $DispatchMessage = if ($PendingAction.original_message) { [string]$PendingAction.original_message } else { $Message }
    $ConfirmationArgs = @(
        "-Text", $DispatchMessage,
        "-AsJson",
        "-ConfirmDispatch",
        "-ConversationId", $(if ($ConversationId) { $ConversationId } else { "" }),
        "-SessionId", $(if ($SessionId) { $SessionId } else { "" }),
        "-UserId", $(if ($UserId) { $UserId } else { "" }),
        "-ConversationTitle", $(if ($ConversationTitle) { $ConversationTitle } else { "" })
    )

    $Raw = & pwsh -NoProfile -File $HandoffScript @ConfirmationArgs
    $Handoff = ConvertFrom-PDAMixedJson -Text ([string]($Raw -join "`n")) -SourceName $HandoffScript

    $ResponseText = ""
    $NextAction = ""

    if ($Handoff.dispatch_status -eq "not_applicable") {
        $ResponseText = [string]$Handoff.response_text
        $NextAction = [string]$Handoff.next_action
    }
    elseif ($Handoff.dispatch_status -eq "completed") {
        $ResponseText = [string]$Handoff.response_text
        $NextAction = [string]$Handoff.next_action
    }
    elseif ($Handoff.dispatch_status -eq "submitted") {
        $ResponseText = "Dispatched via governed PDA handoff using $($Handoff.recommended_command)."
        $NextAction = "Dispatch submitted through the governed submitter."
    }
    elseif ($Handoff.requires_confirmation) {
        $ResponseText = "Recommended command: $($Handoff.recommended_command). Confirm to dispatch."
        $NextAction = "Reply with confirmation to submit through the governed handoff."
    }
    else {
        $ResponseText = "Recommended command: $($Handoff.recommended_command)."
        $NextAction = "Review the recommendation before dispatch."
    }

    $DispatchPath = [string]$Handoff.dispatch_path
    $TaskFile = Resolve-PDATaskFileFromDispatchPath -DispatchPath $DispatchPath
    $TaskId = ""
    $TaskStatus = ""
    $ApprovalPath = ""
    $ResultPath = ""

    if ($TaskFile) {
        $TaskId = Get-PDATaskIdFromFile -FileInfo $TaskFile
        if ($TaskFile.FullName -match '\\approvals\\pending\\') {
            $ApprovalPath = $TaskFile.FullName
            $TaskStatus = "pending_approval"
        }
        elseif ($TaskFile.FullName -match '\\results\\') {
            $TaskStatus = "completed"
        }
        elseif ($TaskFile.FullName -match '\\running\\') {
            $TaskStatus = "running"
        }
        elseif ($TaskFile.FullName -match '\\completed\\') {
            $TaskStatus = "completed"
        }
        elseif ($TaskFile.FullName -match '\\failed\\') {
            $TaskStatus = "failed"
        }
        elseif ($TaskFile.FullName -match '\\pending\\') {
            $TaskStatus = "queued"
        }

        if (-not [string]::IsNullOrWhiteSpace($TaskId) -and $TaskStatus -eq "completed") {
            try {
                $TaskJson = Get-Content -Path $TaskFile.FullName -Raw | ConvertFrom-Json
                if ($TaskJson.PSObject.Properties.Name -contains "result_path" -and -not [string]::IsNullOrWhiteSpace([string]$TaskJson.result_path)) {
                    $ResultPath = [string]$TaskJson.result_path
                }
            }
            catch {}
        }
    }

    $ApprovalId = ""
    if ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.PSObject.Properties.Name -contains "approval_id") {
        $ApprovalId = [string]$ConversationState.conversation.approval_id
    }
    elseif ($PendingAction -and $PendingAction.PSObject.Properties.Name -contains "approval_id") {
        $ApprovalId = [string]$PendingAction.approval_id
    }

    if (-not [string]::IsNullOrWhiteSpace($ApprovalId) -and (Get-Command -Name Update-PDAApprovalRequest -ErrorAction SilentlyContinue)) {
        try {
            [void](Update-PDAApprovalRequest -ApprovalId $ApprovalId -Status "approved" -Approver $(if ($UserId) { $UserId } else { "human" }) -Rationale ([string]$Message) -Root $Root -NoThrow)
        }
        catch {}
    }

    if ($Handoff.dispatch_status -in @("submitted", "completed")) {
        Invoke-PDAConversationStateUpdate -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Message $Message -TaskId $TaskId -TaskStatus $TaskStatus -TaskFilePath $(if ($TaskFile) { $TaskFile.FullName } else { "" }) -ApprovalFilePath $ApprovalPath -ResultPath $ResultPath -BridgeStatus $(if ($Handoff.bridge_status) { [string]$Handoff.bridge_status } else { "submitted" }) -DispatchStatus $Handoff.dispatch_status -NextAction $NextAction -ResponseText $ResponseText -RecommendedCommand $Handoff.recommended_command -Intent $Handoff.intent -Confidence $Handoff.confidence -RequiresConfirmation:([bool]$Handoff.requires_confirmation) -ApprovalId $ApprovalId -ApprovalStatus "approved" -ApprovalPath $(if (-not [string]::IsNullOrWhiteSpace($ApprovalPath)) { $ApprovalPath } elseif ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.PSObject.Properties.Name -contains "approval_path") { [string]$ConversationState.conversation.approval_path } else { "" }) -ApprovalRequestedAction $(if ($PendingAction) { [string]$PendingAction.recommended_command } else { "" }) -ApprovalRationale ([string]$Message) -ApprovalRequestTimestamp $(if ($ConversationState -and $ConversationState.conversation -and $ConversationState.conversation.PSObject.Properties.Name -contains "approval_request_timestamp") { [string]$ConversationState.conversation.approval_request_timestamp } else { "" }) -ApprovalResponseTimestamp (Get-Date).ToUniversalTime().ToString("o") -PendingRecommendedCommand ([string]$PendingAction.recommended_command) -PendingDispatchCategory ([string]$PendingAction.dispatch_category) -PendingOriginalMessage ([string]$PendingAction.original_message) -PendingTimestamp ([string]$PendingAction.timestamp) -PendingExpiresAt ([string]$PendingAction.expires_at) -PendingStatus "dispatched" -ClearPendingAction | Out-Null
    }

    $Result = [pscustomobject]@{
        original_message         = $Message
        response_text            = $ResponseText
        recommended_command      = [string]$Handoff.recommended_command
        intent                   = [string]$Handoff.intent
        route_type               = if ($ConversationRoute -and $ConversationRoute.PSObject.Properties.Name -contains "route_type") { [string]$ConversationRoute.route_type } else { [string]$Handoff.interpreter_status }
        confidence               = [double]$Handoff.confidence
        requires_confirmation    = [bool]$Handoff.requires_confirmation
        dispatch_ready           = [bool]$Handoff.dispatch_ready
        dispatch_status          = [string]$Handoff.dispatch_status
        next_action              = $NextAction
        bridge_status            = if ($Handoff.bridge_status) { [string]$Handoff.bridge_status } elseif ($Handoff.dispatch_status -eq "submitted") { "submitted" } elseif ($Handoff.interpreter_status -eq "mapped") { "ready" } else { "needs_clarification" }
        handoff_status           = [string]$Handoff.interpreter_status
        source_of_truth          = "Scripts/PDA_CommandInterpreter.ps1"
        confirmation_mode        = [bool]$ConfirmDispatch
        dispatch_path            = $DispatchPath
        dispatch_category        = [string]$Handoff.dispatch_category
        conversation_id          = $(if ($ConversationId) { $ConversationId } else { $(if ($ConversationState -and $ConversationState.conversation_id) { [string]$ConversationState.conversation_id } else { "" }) })
        session_id               = $SessionId
        conversation_state_status = if ($ConversationState) { [string]$ConversationState.status } else { "empty" }
        latest_task_id           = $TaskId
        latest_task_status       = $TaskStatus
        latest_result_path       = $ResultPath
        decision                 = $script:PDACommanderDecision
        bridge_mode              = "confirmation_replay"
        pending_action           = if ($PendingAction) { $PendingAction } else { $null }
    }

    $Result = Add-PDACommanderRuntimeContextFields -Result $Result

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        return
    }

    Write-Host "[OK] PDA chat bridge result:"
    Write-Host ("Response text        : {0}" -f $Result.response_text)
    Write-Host ("Recommended command  : {0}" -f $(if ($Result.recommended_command) { $Result.recommended_command } else { "(none)" }))
    Write-Host ("Intent               : {0}" -f $(if ($Result.intent) { $Result.intent } else { "(none)" }))
    Write-Host ("Confidence           : {0}" -f $Result.confidence)
    Write-Host ("Dispatch ready       : {0}" -f $Result.dispatch_ready)
    Write-Host ("Dispatch status      : {0}" -f $Result.dispatch_status)
    Write-Host ("Next action          : {0}" -f $Result.next_action)
    return
}

if ($UseLegacyStatusLookup -and $IsStatusLookup -and -not $IsOperatorConsoleCommand -and -not $IsSlashCommandMessage) {
    $TaskResult = Invoke-PDATaskResultQuery -ConversationId $ConversationId -SessionId $SessionId -Message $Message
    if (-not $TaskResult) {
        $TaskResult = Invoke-PDAConversationStateQuery -ConversationId $ConversationId -SessionId $SessionId -Message $Message
    }

    $LatestTask = $null
    $ResponseText = "No tracked PDA task found for this conversation."
    $NextAction = "Start a governed PDA task or confirm a request so the bridge can track it."
    $RecommendedCommand = ""
    $Intent = "status_lookup"
    $Confidence = 1
    $LatestTaskStatus = ""
    $LatestTaskId = ""
    $LatestResultPath = ""

    if ($TaskResult -and $TaskResult.conversation_id) {
        $LatestTask = $TaskResult.latest_task
        if ($LatestTask) {
            $LatestTaskId = [string]$LatestTask.task_id
            $LatestTaskStatus = [string]$LatestTask.task_status
            $RecommendedCommand = if ($LatestTask.command) { [string]$LatestTask.command } else { "" }
            $Intent = if ($LatestTask.intent) { [string]$LatestTask.intent } else { "status_lookup" }
            $LatestResultPath = if ($TaskResult.latest_result -and $TaskResult.latest_result.result_path) {
                [string]$TaskResult.latest_result.result_path
            } elseif ($TaskResult.result_artifact -and $TaskResult.result_artifact.saved_path) {
                [string]$TaskResult.result_artifact.saved_path
            } else {
                ""
            }
        }

        $ResponseText = [string]$TaskResult.response_text
        $NextAction = [string]$TaskResult.next_action
    }

    $Result = [pscustomobject]@{
        original_message         = $Message
        response_text            = $ResponseText
        recommended_command      = $RecommendedCommand
        intent                   = $Intent
        route_type               = if ($ConversationRoute -and $ConversationRoute.PSObject.Properties.Name -contains "route_type") { [string]$ConversationRoute.route_type } else { "direct_status" }
        confidence               = [double]$Confidence
        requires_confirmation    = $false
        dispatch_ready           = $false
        dispatch_status          = "not_dispatched"
        next_action              = $NextAction
        bridge_status            = "ready"
        handoff_status           = "status_lookup"
        source_of_truth          = "Scripts/Get-PDATaskResult.ps1"
        confirmation_mode        = [bool]$ConfirmDispatch
        dispatch_path            = ""
        dispatch_category        = ""
        conversation_id          = $(if ($ConversationId) { $ConversationId } elseif ($TaskResult -and $TaskResult.conversation_id) { [string]$TaskResult.conversation_id } else { "" })
        session_id               = $SessionId
        conversation_state_status = $(if ($TaskResult) { [string]$TaskResult.status } else { "empty" })
        latest_task_id           = $LatestTaskId
        latest_task_status       = $LatestTaskStatus
        latest_result_path       = $LatestResultPath
        latest_result_response_text = $(if ($TaskResult) { [string]$TaskResult.latest_result_response_text } else { "" })
        result_artifact_path     = $(if ($TaskResult -and $TaskResult.latest_result) { [string]$TaskResult.latest_result.result_path } else { "" })
        result_artifact          = $(if ($TaskResult) { $TaskResult.result_artifact } else { $null })
        decision                 = $script:PDACommanderDecision
        bridge_mode              = "status_lookup"
    }

    Invoke-PDAConversationStateUpdate -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Message $Message -TaskId $LatestTaskId -TaskStatus $LatestTaskStatus -ResultPath $LatestResultPath -BridgeStatus "ready" -DispatchStatus "not_dispatched" -NextAction $NextAction -ResponseText $ResponseText -RecommendedCommand $RecommendedCommand -Intent $Intent -Confidence $Confidence -RequiresConfirmation:$false | Out-Null

    $Result = Add-PDACommanderRuntimeContextFields -Result $Result

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 20
        return
    }

    Write-Host "[OK] PDA chat bridge result:"
    Write-Host ("Response text        : {0}" -f $Result.response_text)
    Write-Host ("Recommended command  : {0}" -f $(if ($Result.recommended_command) { $Result.recommended_command } else { "(none)" }))
    Write-Host ("Intent               : {0}" -f $(if ($Result.intent) { $Result.intent } else { "(none)" }))
    Write-Host ("Confidence           : {0}" -f $Result.confidence)
    Write-Host ("Dispatch ready       : {0}" -f $Result.dispatch_ready)
    Write-Host ("Dispatch status      : {0}" -f $Result.dispatch_status)
    Write-Host ("Next action          : {0}" -f $Result.next_action)
    return
}

$HandoffArgs = New-Object System.Collections.Generic.List[string]
$HandoffArgs.Add("-Text") | Out-Null
$HandoffArgs.Add($HandoffInputMessage) | Out-Null
$HandoffArgs.Add("-AsJson") | Out-Null
if (-not [string]::IsNullOrWhiteSpace([string]$ConversationId)) {
    $HandoffArgs.Add("-ConversationId") | Out-Null
    $HandoffArgs.Add([string]$ConversationId) | Out-Null
}
if (-not [string]::IsNullOrWhiteSpace([string]$SessionId)) {
    $HandoffArgs.Add("-SessionId") | Out-Null
    $HandoffArgs.Add([string]$SessionId) | Out-Null
}
if (-not [string]::IsNullOrWhiteSpace([string]$UserId)) {
    $HandoffArgs.Add("-UserId") | Out-Null
    $HandoffArgs.Add([string]$UserId) | Out-Null
}
if (-not [string]::IsNullOrWhiteSpace([string]$ConversationTitle)) {
    $HandoffArgs.Add("-ConversationTitle") | Out-Null
    $HandoffArgs.Add([string]$ConversationTitle) | Out-Null
}
if ($ConfirmDispatch) {
    $HandoffArgs.Add("-ConfirmDispatch") | Out-Null
}

$Raw = & pwsh -NoProfile -File $HandoffScript @($HandoffArgs)
$Handoff = ConvertFrom-PDAMixedJson -Text ([string]($Raw -join "`n")) -SourceName $HandoffScript
$script:PDAConversationRouteType = if ($ConversationRoute -and $ConversationRoute.PSObject.Properties.Name -contains "route_type") { [string]$ConversationRoute.route_type } else { "" }
$script:PDACommanderDecision = Get-PDABridgeCommanderDecision -Text $Message -ConversationRoute $ConversationRoute -Handoff $Handoff -Root $Root

$ResponseText = ""
$NextAction = ""

    if ($Handoff.dispatch_status -eq "not_applicable") {
        $ResponseText = [string]$Handoff.response_text
        $NextAction = [string]$Handoff.next_action
    }
    else {
switch ($Handoff.interpreter_status) {
    "mapped" {
        if ($Handoff.dispatch_status -eq "completed") {
            $ResponseText = [string]$Handoff.response_text
            $NextAction = [string]$Handoff.next_action
        }
        elseif ($Handoff.dispatch_status -eq "submitted") {
            $ResponseText = "Dispatched via governed PDA handoff using $($Handoff.recommended_command)."
            $NextAction = "Dispatch submitted through the governed submitter."
        }
        elseif ($Handoff.requires_confirmation) {
            $ResponseText = "Recommended command: $($Handoff.recommended_command). Confirm to dispatch."
            $NextAction = "Reply with confirmation to submit through the governed handoff."
        }
        else {
            $ResponseText = "Recommended command: $($Handoff.recommended_command)."
            $NextAction = "Review the recommendation before dispatch."
        }
    }
    "ambiguous" {
        $ResponseText = "Clarification required. $($Handoff.ambiguity_reason)"
        $NextAction = "Refine the request so the interpreter returns one governed command."
    }
    default {
        $ResponseText = "No governed command matched. $($Handoff.ambiguity_reason)"
        $NextAction = "Rephrase using review, report, analyze, run, or research language."
    }
}
}

$PendingTimestamp = ""
$PendingExpiresAt = ""
if ($Handoff.interpreter_status -eq "mapped" -and $Handoff.requires_confirmation) {
    $PendingTimestamp = (Get-Date).ToUniversalTime().ToString("o")
    $PendingExpiresAt = (Get-Date).ToUniversalTime().AddMinutes((Get-PDAPendingConfirmationTimeoutMinutes)).ToString("o")
    Invoke-PDAConversationStateUpdate -ConversationId $ConversationId -SessionId $SessionId -UserId $UserId -ConversationTitle $ConversationTitle -Message $Message -TaskId "" -TaskStatus "pending_confirmation" -TaskFilePath "" -ApprovalFilePath "" -ResultPath "" -ResultSummary "" -BridgeStatus "ready" -DispatchStatus "not_dispatched" -NextAction $NextAction -ResponseText $ResponseText -RecommendedCommand $Handoff.recommended_command -Intent $Handoff.intent -Confidence $Handoff.confidence -RequiresConfirmation:([bool]$Handoff.requires_confirmation) -PendingRecommendedCommand ([string]$Handoff.recommended_command) -PendingDispatchCategory ([string]$Handoff.dispatch_category) -PendingOriginalMessage $Message -PendingTimestamp $PendingTimestamp -PendingExpiresAt $PendingExpiresAt -PendingStatus "awaiting_confirmation" -COOPERContext $script:PDACommanderRuntimeContext -COOPERLayersLoaded ([bool]$script:PDACommanderRuntimeContext.cooper_layers_loaded) -PersonalityLoaded ([bool]$script:PDACommanderRuntimeContext.personality_loaded) -MemoryAvailable ([bool]$script:PDACommanderRuntimeContext.memory_available) -GovernanceAvailable ([bool]$script:PDACommanderRuntimeContext.governance_available) -CapabilityRegistryAvailable ([bool]$script:PDACommanderRuntimeContext.capability_registry_available) -AgentRegistryAvailable ([bool]$script:PDACommanderRuntimeContext.agent_registry_available) | Out-Null
}

$DispatchPath = [string]$Handoff.dispatch_path
$TaskFile = Resolve-PDATaskFileFromDispatchPath -DispatchPath $DispatchPath
$TaskId = ""
$TaskStatus = ""
$ApprovalPath = ""
$ResultPath = ""

if ($TaskFile) {
    $TaskId = Get-PDATaskIdFromFile -FileInfo $TaskFile
    if ($TaskFile.FullName -match '\\approvals\\pending\\') {
        $ApprovalPath = $TaskFile.FullName
        $TaskStatus = "pending_approval"
    }
    elseif ($TaskFile.FullName -match '\\results\\') {
        $TaskStatus = "completed"
    }
    elseif ($TaskFile.FullName -match '\\running\\') {
        $TaskStatus = "running"
    }
    elseif ($TaskFile.FullName -match '\\completed\\') {
        $TaskStatus = "completed"
    }
    elseif ($TaskFile.FullName -match '\\failed\\') {
        $TaskStatus = "failed"
    }
    elseif ($TaskFile.FullName -match '\\pending\\') {
        $TaskStatus = "queued"
    }

    if (-not [string]::IsNullOrWhiteSpace($TaskId) -and $TaskStatus -eq "completed") {
        try {
            $TaskJson = Get-Content -Path $TaskFile.FullName -Raw | ConvertFrom-Json
            if ($TaskJson.PSObject.Properties.Name -contains "result_path" -and -not [string]::IsNullOrWhiteSpace([string]$TaskJson.result_path)) {
                $ResultPath = [string]$TaskJson.result_path
            }
        }
        catch {}
    }
}

$Result = [pscustomobject]@{
    original_message         = $Message
    response_text            = $ResponseText
    recommended_command      = [string]$Handoff.recommended_command
    intent                   = [string]$Handoff.intent
    route_type               = if ($ConversationRoute -and $ConversationRoute.PSObject.Properties.Name -contains "route_type") { [string]$ConversationRoute.route_type } else { [string]$Handoff.interpreter_status }
    confidence               = [double]$Handoff.confidence
    requires_confirmation    = [bool]$Handoff.requires_confirmation
    dispatch_ready           = [bool]$Handoff.dispatch_ready
    dispatch_status          = [string]$Handoff.dispatch_status
    next_action              = $NextAction
    bridge_status            = if ($Handoff.bridge_status) { [string]$Handoff.bridge_status } elseif ($Handoff.dispatch_status -eq "submitted") { "submitted" } elseif ($Handoff.interpreter_status -eq "mapped") { "ready" } else { "needs_clarification" }
    handoff_status           = [string]$Handoff.interpreter_status
    source_of_truth          = "Scripts/PDA_CommandInterpreter.ps1"
    confirmation_mode        = [bool]$ConfirmDispatch
    dispatch_path            = $DispatchPath
    dispatch_category        = [string]$Handoff.dispatch_category
    conversation_id          = $(if ($ConversationId) { $ConversationId } else { "" })
    session_id               = $SessionId
    conversation_state_status = "unknown"
    latest_task_id           = $TaskId
    latest_task_status       = $TaskStatus
    latest_result_path       = $ResultPath
    decision                 = $script:PDACommanderDecision
    bridge_mode              = "command_handoff"
}

$Result = Add-PDACommanderRuntimeContextFields -Result $Result

Invoke-PDAConversationStateUpdate -TaskId $TaskId -TaskStatus $TaskStatus -TaskFilePath $(if ($TaskFile) { $TaskFile.FullName } else { "" }) -ApprovalFilePath $ApprovalPath -ResultPath $ResultPath -BridgeStatus $Result.bridge_status -DispatchStatus $Result.dispatch_status -NextAction $Result.next_action -ResponseText $Result.response_text -RecommendedCommand $Result.recommended_command -Intent $Result.intent -Confidence $Result.confidence -RequiresConfirmation:([bool]$Result.requires_confirmation) -COOPERContext $script:PDACommanderRuntimeContext -COOPERLayersLoaded ([bool]$script:PDACommanderRuntimeContext.cooper_layers_loaded) -PersonalityLoaded ([bool]$script:PDACommanderRuntimeContext.personality_loaded) -MemoryAvailable ([bool]$script:PDACommanderRuntimeContext.memory_available) -GovernanceAvailable ([bool]$script:PDACommanderRuntimeContext.governance_available) -CapabilityRegistryAvailable ([bool]$script:PDACommanderRuntimeContext.capability_registry_available) -AgentRegistryAvailable ([bool]$script:PDACommanderRuntimeContext.agent_registry_available) | Out-Null

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    return
}

Write-Host "[OK] PDA chat bridge result:"
Write-Host ("Response text        : {0}" -f $Result.response_text)
Write-Host ("Recommended command  : {0}" -f $(if ($Result.recommended_command) { $Result.recommended_command } else { "(none)" }))
Write-Host ("Intent               : {0}" -f $(if ($Result.intent) { $Result.intent } else { "(none)" }))
Write-Host ("Confidence           : {0}" -f $Result.confidence)
Write-Host ("Dispatch ready       : {0}" -f $Result.dispatch_ready)
Write-Host ("Dispatch status      : {0}" -f $Result.dispatch_status)
Write-Host ("Next action          : {0}" -f $Result.next_action)
