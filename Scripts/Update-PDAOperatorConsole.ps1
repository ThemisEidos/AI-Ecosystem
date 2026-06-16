$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$DashboardPath = Join-Path $Root "Obsidian Vault\02_Projects\AI Tool Ecosystem\PDA Operator Console.md"
$TelemetryPath = Join-Path $Root "PDA-Logs\telemetry\pda-queue-telemetry.json"
$RegistryPath = Join-Path $Root "Scripts\PDA_WorkerRegistry.json"
$ConversationRegistryPath = Join-Path $Root "PDA-Runtime\data\conversation-state.json"
$ConversationStateScript = Join-Path $PSScriptRoot "Get-PDAConversationState.ps1"
$OntologyPath = Join-Path $Root "Scripts\PDA_TaskOntology.json"
$LegacyRepairAllowlistPath = Join-Path $Root "Scripts\PDA_LegacyMemoryRepairAllowlist.json"
$LegacyRepairToolPath = "Scripts/Repair-PDALegacyMemoryRecord.ps1"
$LegacyRepairReportPath = Join-Path $Root "PDA-Obsidian-Vault\01_Dashboard\Memory Repair Report.md"
$ModelRoutingScript = Join-Path $PSScriptRoot "Test-PDAModelRouting.ps1"
$MemoryTaxonomyScript = Join-Path $PSScriptRoot "Test-PDAMemoryTaxonomy.ps1"
$MemoryWriterEnforcementScript = Join-Path $PSScriptRoot "Test-PDAMemoryWriterEnforcement.ps1"
$GovernanceScript = Join-Path $PSScriptRoot "Test-PDAOntologyGovernance.ps1"
$RepoGovernanceScript = Join-Path $PSScriptRoot "Test-PDARepoGovernance.ps1"
$RetrievalScript = Join-Path $PSScriptRoot "Test-PDARetrieval.ps1"
$TaskResultScript = Join-Path $PSScriptRoot "Get-PDATaskResult.ps1"
$LiteLLMProviderScript = Join-Path $PSScriptRoot "Test-PDALiteLLMProviders.ps1"
$LiteLLMEnvScript = Join-Path $PSScriptRoot "Test-PDALiteLLMEnv.ps1"
$ModelInvocationScript = Join-Path $PSScriptRoot "Test-PDAModelInvocation.ps1"
$ModelFallbackScript = Join-Path $PSScriptRoot "Test-PDAModelFallback.ps1"
$DraftWorkerScript = Join-Path $PSScriptRoot "Test-PDADraftWorker.ps1"
$ResearchWorkerScript = Join-Path $PSScriptRoot "Test-PDAResearchWorker.ps1"
$ReviewWorkerScript = Join-Path $PSScriptRoot "Test-PDAReviewWorker.ps1"
$ReporterWorkerScript = Join-Path $PSScriptRoot "Test-PDAReporterWorker.ps1"
$FabricPatternScript = Join-Path $PSScriptRoot "Test-PDAFabricPattern.ps1"
. (Join-Path $PSScriptRoot "PDA_Lifecycle.ps1")

. (Join-Path $PSScriptRoot "PDA_TaskOntology.ps1")

pwsh -NoProfile -File (Join-Path $PSScriptRoot "Get-PDAQueueTelemetry.ps1") | Out-Null

$Telemetry = Get-Content $TelemetryPath -Raw | ConvertFrom-Json

$RegistryText = ""
if (Test-Path $RegistryPath) {
    try {
        $Registry = Get-Content $RegistryPath -Raw | ConvertFrom-Json

        $Workers = if ($Registry.workers) { $Registry.workers } else { $Registry }

        $Rows = foreach ($w in $Workers) {
            $DefaultPattern = if ($w.default_pattern) { $w.default_pattern } else { "" }
            "| $($w.command) | $($w.worker_name) | $($w.status) | $($w.routing_surface) | $DefaultPattern | $($w.accepted_input_modes -join ', ') |"
        }

        $RegistryText = @"
## Worker Registry

| Command | Worker | Status | Routing Surface | Default Pattern | Input Modes |
|---|---|---|---|---|---|
$($Rows -join "`n")
"@
    }
    catch {
        $RegistryText = "## Worker Registry`n`nRegistry parse failed: $($_.Exception.Message)"
    }
}

$OntologyText = ""
if (Test-Path $OntologyPath) {
    try {
        $Ontology = Import-PDATaskOntology -Root $Root
        $OntologyText = @"
## Task Ontology Status

| Field | Value |
|---|---|
| Ontology | $($Ontology.ontology_name) |
| Version | $($Ontology.ontology_version) |
| Schema | Scripts/PDA_TaskOntology.schema.json |
| Intents | $(@($Ontology.task_intents).Count) |
| Categories | $(@($Ontology.task_categories).Count) |
| Category 2 routing | local-only only |
"@
    }
    catch {
        $OntologyText = "## Task Ontology Status`n`nOntology parse failed: $($_.Exception.Message)"
    }
}

$CommandInterpreterText = ""
$CommandInterpreterScript = Join-Path $PSScriptRoot "Test-PDACommandInterpreter.ps1"
if (Test-Path $CommandInterpreterScript) {
    try {
        $InterpreterJson = & pwsh -NoProfile -File $CommandInterpreterScript -NoThrow -AsJson
        $Interpreter = $InterpreterJson | ConvertFrom-Json
        $CommandInterpreterText = @"
## Command Interpreter Status

| Field | Value |
|---|---|
| Status | $($Interpreter.status) |
| Test cases | $($Interpreter.test_case_count) |
| Passed | $($Interpreter.passed_count) |
| Failed | $($Interpreter.failed_count) |
| Accuracy | $($Interpreter.accuracy_percent)% |
| Mapped | $($Interpreter.mapped_count) |
| Ambiguous | $($Interpreter.ambiguous_count) |
| Unknown | $($Interpreter.unknown_count) |
| Source of truth | Scripts/PDA_TaskOntology.json |
| Phase | Read-only, deterministic, no execution |
"@
    }
    catch {
        $CommandInterpreterText = "## Command Interpreter Status`n`nInterpreter scan failed: $($_.Exception.Message)"
    }
}

$CommandHandoffText = ""
$CommandHandoffScript = Join-Path $PSScriptRoot "Test-PDACommandHandoff.ps1"
if (Test-Path $CommandHandoffScript) {
    try {
        $HandoffJson = & pwsh -NoProfile -File $CommandHandoffScript -NoThrow -AsJson
        $Handoff = $HandoffJson | ConvertFrom-Json
        $CommandHandoffText = @"
## Command Handoff Status

| Field | Value |
|---|---|
| Status | $($Handoff.status) |
| Test cases | $($Handoff.test_case_count) |
| Passed | $($Handoff.passed_count) |
| Failed | $($Handoff.failed_count) |
| Dispatch confirmed | $($Handoff.dispatch_confirmed_count) |
| Dispatch blocked | $($Handoff.dispatch_blocked_count) |
| Source of truth | Scripts/PDA_CommandInterpreter.ps1 |
| Phase | UI-facing confirmation gate, no autonomous dispatch |
"@
    }
    catch {
        $CommandHandoffText = "## Command Handoff Status`n`nHandoff scan failed: $($_.Exception.Message)"
    }
}

$ChatBridgeText = ""
$ChatBridgeScript = Join-Path $PSScriptRoot "Test-PDAChatBridge.ps1"
if (Test-Path $ChatBridgeScript) {
    try {
        $ChatBridgeJson = & pwsh -NoProfile -File $ChatBridgeScript -NoThrow -AsJson
        $ChatBridge = $ChatBridgeJson | ConvertFrom-Json
        $ChatBridgeText = @"
## Chat Bridge Status

| Field | Value |
|---|---|
| Status | $($ChatBridge.status) |
| Test cases | $($ChatBridge.test_case_count) |
| Passed | $($ChatBridge.passed_count) |
| Failed | $($ChatBridge.failed_count) |
| Dispatch confirmed | $($ChatBridge.dispatch_confirmed_count) |
| Dispatch blocked | $($ChatBridge.dispatch_blocked_count) |
| Source of truth | Scripts/PDA_CommandInterpreter.ps1 |
| Phase | Open WebUI / n8n bridge contract |
"@
    }
    catch {
        $ChatBridgeText = "## Chat Bridge Status`n`nBridge scan failed: $($_.Exception.Message)"
    }
}

$WebhookBridgeText = ""
$WebhookBridgeScript = Join-Path $PSScriptRoot "Test-PDAWebhookBridge.ps1"
if (Test-Path $WebhookBridgeScript) {
    try {
        $WebhookBridgeJson = & pwsh -NoProfile -File $WebhookBridgeScript -NoThrow -AsJson
        $WebhookBridge = $WebhookBridgeJson | ConvertFrom-Json
        $WebhookBridgeText = @"
## Webhook Bridge Status

| Field | Value |
|---|---|
| Status | $($WebhookBridge.status) |
| Test cases | $($WebhookBridge.test_case_count) |
| Passed | $($WebhookBridge.passed_count) |
| Failed | $($WebhookBridge.failed_count) |
| Dispatch confirmed | $($WebhookBridge.dispatch_confirmed_count) |
| Dispatch blocked | $($WebhookBridge.dispatch_blocked_count) |
| Source of truth | Scripts/PDA_CommandInterpreter.ps1 |
| Phase | Open WebUI / n8n webhook wrapper |
"@
    }
    catch {
        $WebhookBridgeText = "## Webhook Bridge Status`n`nWebhook bridge scan failed: $($_.Exception.Message)"
    }
}

$HttpBridgeText = ""
$HttpBridgeScript = Join-Path $PSScriptRoot "Test-PDAHttpBridgeWorkflow.ps1"
if (Test-Path $HttpBridgeScript) {
    try {
        $HttpBridgeJson = & pwsh -NoProfile -File $HttpBridgeScript -NoThrow -AsJson
        $HttpBridge = $HttpBridgeJson | ConvertFrom-Json
        $HttpBridgeText = @"
## HTTP Bridge Status

| Field | Value |
|---|---|
| Status | $($HttpBridge.status) |
| Server script | $($HttpBridge.server_script) |
| Workflow | $($HttpBridge.workflow_path) |
| n8n target | $($HttpBridge.n8n_target_endpoint) |
| Uses HTTP request | $($HttpBridge.uses_http_request) |
| Uses executeCommand | $($HttpBridge.uses_execute_command) |
| Queue bypass detected | $($HttpBridge.queue_bypass_detected) |
"@
    }
    catch {
        $HttpBridgeText = "## HTTP Bridge Status`n`nHTTP bridge scan failed: $($_.Exception.Message)"
    }
}

$N8nClipboardText = ""
$N8nClipboardScript = Join-Path $PSScriptRoot "Test-PDAN8nClipboardWorkflow.ps1"
if (Test-Path $N8nClipboardScript) {
    try {
        $N8nClipboardJson = & pwsh -NoProfile -File $N8nClipboardScript -NoThrow -AsJson
        $N8nClipboard = $N8nClipboardJson | ConvertFrom-Json
        $N8nClipboardText = @"
## n8n Clipboard Workflow Status

| Field | Value |
|---|---|
| Status | $($N8nClipboard.status) |
| Node count | $($N8nClipboard.node_count) |
| Has connections | $($N8nClipboard.has_connections) |
| HTTP request | $($N8nClipboard.contains_http_request) |
| ExecuteCommand | $($N8nClipboard.contains_execute_command) |
| Clipboard file | $($N8nClipboard.clipboard_path) |
"@
    }
    catch {
        $N8nClipboardText = "## n8n Clipboard Workflow Status`n`nClipboard workflow scan failed: $($_.Exception.Message)"
    }
}

$ReachabilityText = ""
$ReachabilityScript = Join-Path $PSScriptRoot "Test-PDAWebhookServerReachability.ps1"
if (Test-Path $ReachabilityScript) {
    try {
        $ReachabilityJson = & pwsh -NoProfile -File $ReachabilityScript -NoThrow -AsJson
        $Reachability = $ReachabilityJson | ConvertFrom-Json
        $WorkingTargetText = if ($Reachability.working_target) {
            "{0}:{1}" -f $Reachability.working_target.host, $Reachability.working_target.http_status
        } elseif ($Reachability.working_lan_target) {
            "{0}:{1}" -f $Reachability.working_lan_target.host, $Reachability.working_lan_target.http_status
        } else {
            "none"
        }
        $ReachabilityText = @"
## Webhook Reachability Status

| Field | Value |
|---|---|
| Status | $($Reachability.status) |
| Container | $($Reachability.container) |
| Endpoint | $($Reachability.endpoint) |
| host.docker.internal | $($Reachability.host_docker_internal.http_status) |
| gateway.docker.internal | $($Reachability.gateway_docker_internal.http_status) |
| 172.17.0.1 | $($Reachability.bridge_ip.http_status) |
| Working target | $WorkingTargetText |
"@
    }
    catch {
        $ReachabilityText = "## Webhook Reachability Status`n`nReachability scan failed: $($_.Exception.Message)"
    }
}

$OpenWebUIIntegrationText = ""
if ($ChatBridge -or $WebhookBridge -or $HttpBridge -or $N8nClipboard -or $Reachability) {
    $ChatBridgeStatus = if ($ChatBridge) { $ChatBridge.status } else { "unknown" }
    $WebhookBridgeStatus = if ($WebhookBridge) { $WebhookBridge.status } else { "unknown" }
    $HttpBridgeStatus = if ($HttpBridge) { $HttpBridge.status } else { "unknown" }
    $ClipboardStatus = if ($N8nClipboard) { $N8nClipboard.status } else { "unknown" }
    $ReachabilityStatus = if ($Reachability) { $Reachability.status } else { "unknown" }
    $IntegrationTestStatus = if ($ChatBridgeStatus -eq "pass" -and $WebhookBridgeStatus -eq "pass" -and $HttpBridgeStatus -eq "pass" -and $ClipboardStatus -eq "pass" -and $ReachabilityStatus -eq "pass") { "pass" } else { "check" }
    $OpenWebUIIntegrationText = @"
## Open WebUI Integration Status

| Component | Status | Details |
|---|---|---|
| Chat Bridge | $ChatBridgeStatus | Scripts/Invoke-PDAChatBridge.ps1 |
| Webhook Bridge | $WebhookBridgeStatus | Scripts/Invoke-PDAWebhookBridge.ps1 |
| HTTP Bridge | $HttpBridgeStatus | Scripts/Start-PDAWebhookServer.ps1 + n8n Workflow/PDA-ChatBridge-HTTP.json |
| n8n Workflow | present | n8n Workflow/PDA-ChatBridge.json |
| n8n Clipboard Workflow | $ClipboardStatus | n8n Workflow/PDA-ChatBridge-HTTP-Clipboard.json |
| Webhook Reachability | $ReachabilityStatus | Scripts/Test-PDAWebhookServerReachability.ps1 |
| Integration Test Status | $IntegrationTestStatus | Bridge tests remain local-only and deterministic |
"@
}

$ModelRoutingText = ""
if (Test-Path $ModelRoutingScript) {
    try {
        $ModelRoutingJson = & pwsh -NoProfile -File $ModelRoutingScript -NoThrow -AsJson
        $ModelRouting = $ModelRoutingJson | ConvertFrom-Json
        $ModelRoutingText = @"
## Model Routing Policy Status

| Field | Value |
|---|---|
| Status | $($ModelRouting.status) |
| Policy | $($ModelRouting.policy_path) |
| Route script | $($ModelRouting.route_script) |
| Test cases | $($ModelRouting.test_case_count) |
| Passed | $($ModelRouting.passed_count) |
| Failed | $($ModelRouting.failed_count) |
| Default model | local-llama |
| Review worker | claude, gpt |
| Draft worker | gpt, claude |
| Research worker | gemini, openrouter |
| Sensitive/local | local-llama only |
| LiteLLM gateway | yes |
"@
    }
    catch {
        $ModelRoutingText = "## Model Routing Policy Status`n`nModel routing scan failed: $($_.Exception.Message)"
    }
}

$ConversationStateText = ""
if (Test-Path $ConversationStateScript) {
    try {
        function Get-PDAConversationDate {
            param([object]$Value)

            try {
                return [datetime]::Parse([string]$Value)
            }
            catch {
                return [datetime]::MinValue
            }
        }

        $ConversationIdForConsole = "default"
        if (Test-Path $ConversationRegistryPath) {
            try {
                $ConversationRegistry = Get-Content $ConversationRegistryPath -Raw | ConvertFrom-Json
                $ConversationItems = @()
                if ($ConversationRegistry.conversations) {
                    $ConversationItems = @($ConversationRegistry.conversations.PSObject.Properties | ForEach-Object { $_.Value })
                }

                $PreferredConversation = $ConversationItems |
                    Where-Object { $_.conversation_id -and $_.conversation_id -ne "default" } |
                    Sort-Object @{ Expression = { Get-PDAConversationDate $_.updated_at } } -Descending |
                    Select-Object -First 1

                if ($PreferredConversation -and $PreferredConversation.conversation_id) {
                    $ConversationIdForConsole = [string]$PreferredConversation.conversation_id
                }
            }
            catch {
                # Fall back to the default summary path below.
            }
        }

        $ConversationStateJson = & pwsh -NoProfile -File $ConversationStateScript -ConversationId $ConversationIdForConsole -NoThrow -AsJson
        $ConversationState = $ConversationStateJson | ConvertFrom-Json
        $ConversationSummary = if ($ConversationState.conversation) { $ConversationState.conversation } else { $ConversationState }
        $ConversationSessionId = if ($ConversationState.session_id) { [string]$ConversationState.session_id } elseif ($ConversationSummary.session_id) { [string]$ConversationSummary.session_id } else { "" }
        $ConversationLatestResult = ""
        if ($ConversationState.latest_result -and $ConversationState.latest_result.result_path) {
            $ConversationLatestResult = [string]$ConversationState.latest_result.result_path
        }
        elseif ($ConversationSummary.latest_result_path) {
            $ConversationLatestResult = [string]$ConversationSummary.latest_result_path
        }
        $ConversationResponseText = if ($ConversationState.response_text) { [string]$ConversationState.response_text } elseif ($ConversationSummary.response_text) { [string]$ConversationSummary.response_text } else { "" }
        $ConversationStateText = @"
## Conversation State Registry

| Field | Value |
|---|---|
| Status | $($ConversationState.status) |
| Registry path | $($ConversationState.registry_path) |
| Conversation ID | $($ConversationState.conversation_id) |
| Session ID | $ConversationSessionId |
| Active tasks | $($ConversationState.active_task_count) |
| Pending approvals | $($ConversationState.pending_approval_count) |
| Completed tasks | $($ConversationState.completed_task_count) |
| Latest result | $ConversationLatestResult |
| Response text | $ConversationResponseText |
"@
    }
    catch {
        $ConversationStateText = "## Conversation State Registry`n`nConversation state scan failed: $($_.Exception.Message)"
    }
}

$TaskResultText = ""
if (Test-Path $TaskResultScript) {
    try {
        $TaskResultJson = & pwsh -NoProfile -File $TaskResultScript -ConversationId $ConversationIdForConsole -SessionId $ConversationSessionId -UserMessage $(if ($ConversationState.last_message) { $ConversationState.last_message } elseif ($ConversationResponseText) { $ConversationResponseText } else { "" }) -NoThrow -AsJson
        $TaskResult = $TaskResultJson | ConvertFrom-Json
        $ResultArtifactPath = if ($TaskResult.result_artifact_path) { [string]$TaskResult.result_artifact_path } elseif ($TaskResult.latest_result -and $TaskResult.latest_result.result_path) { [string]$TaskResult.latest_result.result_path } else { "" }
        $TaskResultText = @"
## Task Result Retrieval Status

| Field | Value |
|---|---|
| Status | $($TaskResult.status) |
| Lookup script | $TaskResultScript |
| Conversation ID | $($TaskResult.conversation_id) |
| Session ID | $($TaskResult.session_id) |
| Task ID | $($TaskResult.task_id) |
| Latest task status | $(if ($TaskResult.latest_task) { $TaskResult.latest_task.task_status } else { "" }) |
| Latest result path | $(if ($TaskResult.latest_result) { $TaskResult.latest_result.result_path } else { "" }) |
| Result artifact path | $ResultArtifactPath |
| Response text | $($TaskResult.response_text) |
| Latest result text | $($TaskResult.latest_result_response_text) |
| Next action | $($TaskResult.next_action) |
"@
    }
    catch {
        $TaskResultText = "## Task Result Retrieval Status`n`nResult lookup scan failed: $($_.Exception.Message)"
    }
}

$LiteLLMProviderText = ""
if (Test-Path $LiteLLMProviderScript) {
    try {
        $LiteLLMProviderJson = & pwsh -NoProfile -File $LiteLLMProviderScript -NoThrow -AsJson
        $LiteLLMProvider = $LiteLLMProviderJson | ConvertFrom-Json

        $ProviderRows = foreach ($Provider in @($LiteLLMProvider.providers)) {
            $EnvName = if ($Provider.env_name) { [string]$Provider.env_name } else { "-" }
            $EnvStatus = if ($Provider.requires_api_key) {
                if ($Provider.host_env_present) { "set" } else { "missing" }
            }
            else {
                "n/a"
            }
            "| $($Provider.name) | $($Provider.model_name) | $EnvName | $EnvStatus | $($Provider.configured) | $($Provider.live_available) | $($Provider.env_reference_ok) |"
        }

        $LiteLLMProviderText = @"
## LiteLLM Provider Health

| Field | Value |
|---|---|
| Status | $($LiteLLMProvider.status) |
| Endpoint | $($LiteLLMProvider.endpoint) |
| Config | $($LiteLLMProvider.config_path) |
| Compose | $($LiteLLMProvider.compose_path) |
| Live model count | $(@($LiteLLMProvider.live_model_ids).Count) |
| Secret scan | $($LiteLLMProvider.secret_scan.status) |
| Secret hits | $($LiteLLMProvider.secret_scan.hit_count) |
| Test script | $LiteLLMProviderScript |

| Provider | Route | Env Var | Host Env | Configured | Live | Env Ref |
|---|---|---|---|---|---|---|
$($ProviderRows -join "`n")
"@
    }
    catch {
        $LiteLLMProviderText = "## LiteLLM Provider Health`n`nProvider validation scan failed: $($_.Exception.Message)"
    }
}

$LiteLLMEnvText = ""
if (Test-Path $LiteLLMEnvScript) {
    try {
        $LiteLLMEnvJson = & pwsh -NoProfile -File $LiteLLMEnvScript -NoThrow -AsJson
        $LiteLLMEnv = $LiteLLMEnvJson | ConvertFrom-Json
        $LiteLLMEnvText = @"
## LiteLLM Env Loading

| Field | Value |
|---|---|
| Status | $($LiteLLMEnv.status) |
| Env file | $($LiteLLMEnv.env_path) |
| Example file | $($LiteLLMEnv.example_path) |
| Compose env_file | $($LiteLLMEnv.compose_has_env_file) |
| Loaded keys | $($LiteLLMEnv.loaded_key_count) |
| Blank keys | $($LiteLLMEnv.blank_key_count) |
| Missing keys | $($LiteLLMEnv.missing_key_count) |
| Example placeholders | $($LiteLLMEnv.example_has_placeholders) |
"@
    }
    catch {
        $LiteLLMEnvText = "## LiteLLM Env Loading`n`nEnv validation scan failed: $($_.Exception.Message)"
    }
}

$ModelInvocationText = ""
if (Test-Path $ModelInvocationScript) {
    try {
        $ModelInvocationJson = & pwsh -NoProfile -File $ModelInvocationScript -NoThrow -AsJson
        $ModelInvocation = $ModelInvocationJson | ConvertFrom-Json

        $InvocationRows = foreach ($Case in @($ModelInvocation.results)) {
            "| $($Case.name) | $($Case.expected_model) | $($Case.selected_model) | $($Case.status) | $($Case.passed) | $($Case.skipped) |"
        }

        $ModelInvocationText = @"
## LiteLLM Invocation Adapter

| Field | Value |
|---|---|
| Status | $($ModelInvocation.status) |
| Adapter | $($ModelInvocation.adapter_path) |
| Test cases | $($ModelInvocation.test_case_count) |
| Passed | $($ModelInvocation.passed_count) |
| Failed | $($ModelInvocation.failed_count) |
| Skipped | $($ModelInvocation.skipped_count) |

| Case | Expected Model | Selected Model | Status | Passed | Skipped |
|---|---|---|---|---|---|
$($InvocationRows -join "`n")
"@
    }
    catch {
        $ModelInvocationText = "## LiteLLM Invocation Adapter`n`nInvocation scan failed: $($_.Exception.Message)"
    }
}

$ModelFallbackText = ""
if (Test-Path $ModelFallbackScript) {
    try {
        $ModelFallbackJson = & pwsh -NoProfile -File $ModelFallbackScript -NoThrow -AsJson
        $ModelFallback = $ModelFallbackJson | ConvertFrom-Json

        $ModelFallbackText = @"
## LiteLLM Fallback Status

| Field | Value |
|---|---|
| Status | $($ModelFallback.status) |
| Test cases | $($ModelFallback.test_case_count) |
| Passed | $($ModelFallback.passed_count) |
| Failed | $($ModelFallback.failed_count) |
| Draft fallback used | $($ModelFallback.draft_result.fallback.used) |
| Research fallback used | $($ModelFallback.research_result.fallback.used) |
| Restricted local fallback allowed | $($ModelFallback.restricted_result.fallback.allowed) |
| Restricted local fallback used | $($ModelFallback.restricted_result.fallback.used) |
"@
    }
    catch {
        $ModelFallbackText = "## LiteLLM Fallback Status`n`nFallback scan failed: $($_.Exception.Message)"
    }
}

$FabricPatternText = ""
if (Test-Path $FabricPatternScript) {
    try {
        $FabricPatternJson = & pwsh -NoProfile -File $FabricPatternScript -NoThrow -AsJson
        $FabricPattern = $FabricPatternJson | ConvertFrom-Json
        $FabricPatternText = @"
## Fabric Pattern Status

| Field | Value |
|---|---|
| Status | $($FabricPattern.status) |
| Pattern root | $($FabricPattern.pattern_root) |
| Script | $($FabricPattern.fabric_script) |
| Test cases | $($FabricPattern.test_case_count) |
| Passed | $($FabricPattern.passed_count) |
| Failed | $($FabricPattern.failed_count) |
| No model calls | $($FabricPattern.bypass_scan.model_call) |
| No queue bypass | $($FabricPattern.bypass_scan.queue_bypass) |
"@
    }
    catch {
        $FabricPatternText = "## Fabric Pattern Status`n`nFabric pattern scan failed: $($_.Exception.Message)"
    }
}

$DraftWorkerText = ""
if (Test-Path $DraftWorkerScript) {
    try {
        $DraftWorkerJson = & pwsh -NoProfile -File $DraftWorkerScript -NoThrow -AsJson
        $DraftWorker = $DraftWorkerJson | ConvertFrom-Json

        $DraftWorkerText = @"
## Draft Worker Adapter

| Field | Value |
|---|---|
| Status | $($DraftWorker.status) |
| Worker script | $($DraftWorker.worker_script) |
| Results root | $($DraftWorker.results_root) |
| Test cases | $($DraftWorker.test_case_count) |
| Passed | $($DraftWorker.passed_count) |
| Failed | $($DraftWorker.failed_count) |
| Adapter call | $($DraftWorker.bypass_scan.adapter_call) |
| Legacy queue refs | $($DraftWorker.bypass_scan.legacy_queue_reference) |
| Direct LiteLLM request | $($DraftWorker.bypass_scan.direct_litellm_request) |
"@
    }
    catch {
        $DraftWorkerText = "## Draft Worker Adapter`n`nDraft worker scan failed: $($_.Exception.Message)"
    }
}

$ResearchWorkerText = ""
if (Test-Path $ResearchWorkerScript) {
    try {
        $ResearchWorkerJson = & pwsh -NoProfile -File $ResearchWorkerScript -NoThrow -AsJson
        $ResearchWorker = $ResearchWorkerJson | ConvertFrom-Json

        $ResearchWorkerText = @"
## Research Worker Adapter

| Field | Value |
|---|---|
| Status | $($ResearchWorker.status) |
| Worker script | $($ResearchWorker.worker_script) |
| Results root | $($ResearchWorker.results_root) |
| Test cases | $($ResearchWorker.test_case_count) |
| Passed | $($ResearchWorker.passed_count) |
| Failed | $($ResearchWorker.failed_count) |
| Adapter call | $($ResearchWorker.bypass_scan.adapter_call) |
| Legacy queue refs | $($ResearchWorker.bypass_scan.legacy_queue_reference) |
| Direct LiteLLM request | $($ResearchWorker.bypass_scan.direct_litellm_request) |
"@
    }
    catch {
        $ResearchWorkerText = "## Research Worker Adapter`n`nResearch worker scan failed: $($_.Exception.Message)"
    }
}

$ReviewWorkerText = ""
if (Test-Path $ReviewWorkerScript) {
    try {
        $ReviewWorkerJson = & pwsh -NoProfile -File $ReviewWorkerScript -NoThrow -AsJson
        $ReviewWorker = $ReviewWorkerJson | ConvertFrom-Json

        $ReviewWorkerText = @"
## Review Worker Adapter

| Field | Value |
|---|---|
| Status | $($ReviewWorker.status) |
| Worker script | $($ReviewWorker.worker_script) |
| Results root | $($ReviewWorker.results_root) |
| Test cases | $($ReviewWorker.test_case_count) |
| Passed | $($ReviewWorker.passed_count) |
| Failed | $($ReviewWorker.failed_count) |
| Adapter call | $($ReviewWorker.bypass_scan.adapter_call) |
| Legacy queue refs | $($ReviewWorker.bypass_scan.legacy_queue_reference) |
| Direct LiteLLM request | $($ReviewWorker.bypass_scan.direct_litellm_request) |
"@
    }
    catch {
        $ReviewWorkerText = "## Review Worker Adapter`n`nReview worker scan failed: $($_.Exception.Message)"
    }
}

$ReporterPipelineText = ""
if (Test-Path $ReporterWorkerScript) {
    try {
        $ReporterWorkerJson = & pwsh -NoProfile -File $ReporterWorkerScript -NoThrow -AsJson
        $ReporterWorker = $ReporterWorkerJson | ConvertFrom-Json

        $ReporterPipelineText = @"
## Reporter Pipeline Status

| Field | Value |
|---|---|
| Status | $($ReporterWorker.status) |
| Worker script | $($ReporterWorker.worker_script) |
| Lookup script | $($ReporterWorker.lookup_script) |
| Results root | $($ReporterWorker.results_root) |
| Test cases | $($ReporterWorker.test_case_count) |
| Passed | $($ReporterWorker.passed_count) |
| Failed | $($ReporterWorker.failed_count) |
| Stage worker calls | $($ReporterWorker.bypass_scan.stage_worker_calls) |
| Legacy queue refs | $($ReporterWorker.bypass_scan.legacy_queue_reference) |
| Direct LiteLLM request | $($ReporterWorker.bypass_scan.direct_litellm_request) |
| Direct adapter call | $($ReporterWorker.bypass_scan.direct_adapter_call) |
| Lookup status | $($ReporterWorker.lookup_result.status) |
| Lookup latest task | $($ReporterWorker.lookup_result.latest_task_id) |
| Lookup result path | $($ReporterWorker.lookup_result.latest_result_path) |
"@
    }
    catch {
        $ReporterPipelineText = "## Reporter Pipeline Status`n`nReporter pipeline scan failed: $($_.Exception.Message)"
    }
}

$GovernanceText = ""
if (Test-Path $GovernanceScript) {
    try {
        $GovernanceJson = & pwsh -NoProfile -File $GovernanceScript -NoThrow -AsJson
        $Governance = $GovernanceJson | ConvertFrom-Json
        $GovernanceText = @"
## Ontology Enforcement Status

| Field | Value |
|---|---| 
| Status | $($Governance.status) |
| Approved entrypoints | $($Governance.approved_entrypoint_count) |
| Observed writers | $($Governance.observed_writer_count) |
| Drift violations | $($Governance.violation_count) |
| Manifest | Scripts/PDA_ApprovedEntrypoints.json |
"@
    }
    catch {
        $GovernanceText = "## Ontology Enforcement Status`n`nGovernance scan failed: $($_.Exception.Message)"
    }
}

$RepoGovernanceText = ""
if (Test-Path $RepoGovernanceScript) {
    try {
        $RepoGovernanceJson = & pwsh -NoProfile -File $RepoGovernanceScript -NoThrow -AsJson
        $RepoGovernance = $RepoGovernanceJson | ConvertFrom-Json
        $RepoGovernanceText = @"
## Repo Governance Preflight

| Field | Value |
|---|---|
| Status | $($RepoGovernance.status) |
| Approved entries | $($RepoGovernance.approved_count) |
| Observed writers | $($RepoGovernance.observed_writer_count) |
| Missing scripts | $(@($RepoGovernance.missing_approved_scripts).Count) |
| Unknown writers | $(@($RepoGovernance.unknown_writers).Count) |
| Noncompliant writers | $(@($RepoGovernance.noncompliant_approved_writers).Count) |
| Manifest | Scripts/PDA_ApprovedEntrypoints.json |
"@
    }
    catch {
        $RepoGovernanceText = "## Repo Governance Preflight`n`nGovernance scan failed: $($_.Exception.Message)"
    }
}

$RetrievalText = ""
if (Test-Path $RetrievalScript) {
    try {
        $RetrievalJson = & pwsh -NoProfile -File $RetrievalScript -NoThrow -AsJson
        $Retrieval = $RetrievalJson | ConvertFrom-Json
        $RetrievalText = @"
## Retrieval Layer Status

| Field | Value |
|---|---|
| Status | $($Retrieval.integrity.status) |
| Artifact count | $($Retrieval.integrity.artifact_count) |
| Memory count | $($Retrieval.integrity.memory_count) |
| Ontology count | $($Retrieval.integrity.ontology_count) |
| Worker count | $($Retrieval.integrity.worker_count) |
| Missing references | $($Retrieval.integrity.missing_reference_count) |
| Orphan count | $($Retrieval.integrity.orphan_count) |
| Invalid ontology refs | $($Retrieval.integrity.invalid_ontology_reference_count) |
| Invalid worker maps | $($Retrieval.integrity.invalid_worker_mapping_count) |
| Lineage health | $($Retrieval.integrity.lineage_health) |
"@
    }
    catch {
        $RetrievalText = "## Retrieval Layer Status`n`nRetrieval scan failed: $($_.Exception.Message)"
    }
}

$MemoryTaxonomyText = ""
if (Test-Path $MemoryTaxonomyScript) {
    try {
        $MemoryTaxonomyJson = & pwsh -NoProfile -File $MemoryTaxonomyScript -NoThrow -AsJson
        $MemoryTaxonomy = $MemoryTaxonomyJson | ConvertFrom-Json
        $MemoryTaxonomyText = @"
## Memory Taxonomy Status

| Field | Value |
|---|---|
| Status | $($MemoryTaxonomy.status) |
| Taxonomy | $($MemoryTaxonomy.taxonomy.name) |
| Version | $($MemoryTaxonomy.taxonomy.version) |
| Total records | $($MemoryTaxonomy.total_record_count) |
| Valid records | $($MemoryTaxonomy.valid_record_count) |
| Invalid records | $($MemoryTaxonomy.invalid_record_count) |
| Missing fields | $($MemoryTaxonomy.missing_field_count) |
| Invalid values | $($MemoryTaxonomy.invalid_value_count) |
| Invalid tags | $($MemoryTaxonomy.invalid_tag_count) |
| Source refs | $($MemoryTaxonomy.source_reference_issue_count) |
| Orphans | $($MemoryTaxonomy.orphan_count) |
| Duplicate IDs | $($MemoryTaxonomy.duplicate_memory_id_count) |
| Contract | Scripts/PDA_MemoryTaxonomy.json |
"@
    }
    catch {
        $MemoryTaxonomyText = "## Memory Taxonomy Status`n`nMemory taxonomy scan failed: $($_.Exception.Message)"
    }
}

$MemoryWriterText = ""
if (Test-Path $MemoryWriterEnforcementScript) {
    try {
        $MemoryWriterJson = & pwsh -NoProfile -File $MemoryWriterEnforcementScript -NoThrow -AsJson
        $MemoryWriter = $MemoryWriterJson | ConvertFrom-Json
        $MemoryWriterText = @"
## Memory Writer Enforcement

| Field | Value |
|---|---|
| Status | $($MemoryWriter.status) |
| Writer count | $($MemoryWriter.writer_count) |
| Taxonomy-compliant writers | $($MemoryWriter.taxonomy_compliant_writer_count) |
| Live valid records | $($MemoryWriter.live_valid_record_count) |
| Live invalid records | $($MemoryWriter.live_invalid_record_count) |
| Repair needed | $($MemoryWriter.repair_needed_count) |
"@
    }
    catch {
        $MemoryWriterText = "## Memory Writer Enforcement`n`nWriter enforcement scan failed: $($_.Exception.Message)"
    }
}

$ArtifactLifecycleText = ""
try {
    $ArtifactLifecycle = Get-PDALifecycleCounts -Root $Root -RecordType "artifact"
    $ArtifactLifecycleText = @"
## Artifact Lifecycle Status

| Field | Value |
|---|---|
| Active | $($ArtifactLifecycle.active) |
| Archived | $($ArtifactLifecycle.archived) |
| Deprecated | $($ArtifactLifecycle.deprecated) |
| Retired | $($ArtifactLifecycle.retired) |
| Total | $($ArtifactLifecycle.total) |
"@
}
catch {
    $ArtifactLifecycleText = "## Artifact Lifecycle Status`n`nLifecycle scan failed: $($_.Exception.Message)"
}

$MemoryLifecycleText = ""
try {
    $MemoryLifecycle = Get-PDALifecycleCounts -Root $Root -RecordType "memory"
    $MemoryLifecycleText = @"
## Memory Lifecycle Status

| Field | Value |
|---|---|
| Active | $($MemoryLifecycle.active) |
| Archived | $($MemoryLifecycle.archived) |
| Deprecated | $($MemoryLifecycle.deprecated) |
| Retired | $($MemoryLifecycle.retired) |
| Total | $($MemoryLifecycle.total) |
"@
}
catch {
    $MemoryLifecycleText = "## Memory Lifecycle Status`n`nLifecycle scan failed: $($_.Exception.Message)"
}

$LegacyRepairText = ""
$LegacyRepairAllowlistCountText = "unknown"
if (Test-Path $LegacyRepairAllowlistPath) {
    try {
        $LegacyRepairAllowlist = Get-Content -Path $LegacyRepairAllowlistPath -Raw | ConvertFrom-Json
        $LegacyRepairAllowlistCountText = if ($LegacyRepairAllowlist.memory_ids) { [string](@($LegacyRepairAllowlist.memory_ids).Count) } else { "0" }
    }
    catch {
        $LegacyRepairAllowlistCountText = "unknown"
    }
}

$LegacyRepairText = @"
## Legacy Memory Repair

| Field | Value |
|---|---|
| Tool | $LegacyRepairToolPath |
| Allowlist count | $LegacyRepairAllowlistCountText |
| Repair report | $LegacyRepairReportPath |
| Dry-run mode | Supported via -WhatIf |
"@

$LatestCompleted = if ($Telemetry.latest.completed) { $Telemetry.latest.completed.name } else { "None" }
$LatestFailed = if ($Telemetry.latest.failed) { $Telemetry.latest.failed.name } else { "None" }
$LatestResult = if ($Telemetry.latest.result) { $Telemetry.latest.result.name } else { "None" }

$Content = @"
# PDA Operator Console

Generated: $($Telemetry.generated_at)

## Queue Status

| Queue | Count |
|---|---:|
| Pending | $($Telemetry.counts.pending) |
| Running | $($Telemetry.counts.running) |
| Completed | $($Telemetry.counts.completed) |
| Failed | $($Telemetry.counts.failed) |
| Results | $($Telemetry.counts.results) |

## Latest Activity

| Type | Latest |
|---|---|
| Completed Task | $LatestCompleted |
| Failed Task | $LatestFailed |
| Result | $LatestResult |

$RegistryText

$OntologyText

$CommandInterpreterText

$CommandHandoffText

$ChatBridgeText

$WebhookBridgeText

$HttpBridgeText

$N8nClipboardText

$ReachabilityText

$OpenWebUIIntegrationText

$ModelRoutingText

$ConversationStateText

$TaskResultText

$LiteLLMProviderText

$LiteLLMEnvText

$ModelInvocationText

$ModelFallbackText

$FabricPatternText

$DraftWorkerText

$ResearchWorkerText

$ReviewWorkerText

$ReporterPipelineText

$GovernanceText

$RepoGovernanceText

$RetrievalText

$MemoryTaxonomyText

$MemoryWriterText

$ArtifactLifecycleText

$MemoryLifecycleText

$LegacyRepairText

## Operator Commands

~~~powershell
pwsh -File Scripts\Get-PDAStatus.ps1
pwsh -File Scripts\Get-PDAWorkerStatus.ps1
pwsh -File Scripts\Get-PDAQueueTelemetry.ps1
pwsh -File Scripts\PDA_CommandInterpreter.ps1 -Text "review my latest findings"
pwsh -File Scripts\Test-PDACommandInterpreter.ps1
pwsh -File Scripts\Invoke-PDACommandHandoff.ps1 -Text "review my latest findings" -ConfirmDispatch
pwsh -File Scripts\Test-PDACommandHandoff.ps1
pwsh -File Scripts\Invoke-PDAChatBridge.ps1 -Message "review my latest findings" -AsJson
pwsh -File Scripts\Test-PDAChatBridge.ps1
pwsh -File Scripts\Test-PDAChatBridgeIntegration.ps1
pwsh -File Scripts\Invoke-PDAWebhookBridge.ps1 -Message "review my latest findings" -AsJson
pwsh -File Scripts\Test-PDAWebhookBridge.ps1
pwsh -File Scripts\Get-PDAConversationState.ps1
pwsh -File Scripts\Update-PDAConversationState.ps1
pwsh -File Scripts\Test-PDALiteLLMEnv.ps1
pwsh -File Scripts\Test-PDALiteLLMProviders.ps1
pwsh -File Scripts\Test-PDAModelInvocation.ps1
pwsh -File Scripts\Test-PDAModelFallback.ps1
pwsh -File Scripts\Test-PDAFabricPattern.ps1
pwsh -File Scripts\Test-PDADraftWorker.ps1
pwsh -File Scripts\Test-PDAResearchWorker.ps1
pwsh -File Scripts\Test-PDAReviewWorker.ps1
pwsh -File Scripts\Test-PDAReporterWorker.ps1
pwsh -File Scripts\New-PDAHttpBridgeWorkflow.ps1
pwsh -File Scripts\Start-PDAWebhookServer.ps1
pwsh -File Scripts\Test-PDAHttpBridgeWorkflow.ps1
pwsh -File Scripts\New-PDAN8nClipboardWorkflow.ps1
pwsh -File Scripts\Test-PDAN8nClipboardWorkflow.ps1
pwsh -File Scripts\Test-PDAWebhookServerReachability.ps1
pwsh -File Scripts\Update-PDAOperatorConsole.ps1
pwsh -File Scripts\Start-PDAWorker.ps1
pwsh -File Scripts\Stop-PDAWorker.ps1
~~~

## Safety Notes

- Category 2 tasks must remain local-only.
- Approved ontology-backed writers are statically checked for drift.
- Do not commit runtime data, logs, secrets, or restricted files.
- `/execute` remains dry-run/no-op unless explicitly approved.
- Fabric Category 2 tasks must use local-only model routing.

## Next Improvements

- Retry policy
- Dead-letter queue
- Worker heartbeat details
- Artifact index
- Web dashboard later
"@

$Content | Set-Content $DashboardPath -Encoding UTF8

Write-Host "[OK] PDA Operator Console updated:"
Write-Host $DashboardPath
