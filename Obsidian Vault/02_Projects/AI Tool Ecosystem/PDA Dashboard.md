# PDA Dashboard

Last updated: 2026-06-04

## Active Workers

| Worker | Command | Status | Notes |
|---|---|---|---|
| `reporter-worker` | `/reporter` | active | Orchestrates timeline, findings, research, draft, review, and staged intake. |
| `planner-worker` | `/planner` | active | Produces implementation plans. |
| `research-worker` | `/research` | active | Produces operational research synthesis. |
| `review-worker` | `/review` | active | Supports file-based review and message-only test mode. |
| `execute-worker` | `/execute` | active | Dry-run/no-op unless explicitly approved. |

## Supported Commands

| Command | Route | Input Modes | Output |
|---|---|---|---|
| `/reporter` | reporter | staged JSON + queue JSON | Obsidian report chain + result JSON |
| `/planner` | planner | staged JSON + queue JSON + message-only test | Planner markdown + result JSON |
| `/research` | research | staged JSON + queue JSON + message-only test | Research markdown + result JSON |
| `/review` | review | file-based + message-only test | Review markdown + result JSON |
| `/execute` | execute | file-based + message-only test-dry-run | Execution manifest + result JSON |

## Task Ontology Status

- Ontology file: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\PDA_TaskOntology.json`
- Schema file: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\PDA_TaskOntology.schema.json`
- Validation helper: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Validate-PDATaskOntology.ps1`
- Query helper: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Get-PDATaskType.ps1`
- Worker resolver: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Resolve-PDATaskWorkers.ps1`
- Category 2 routing remains local-only and fails closed if a cloud-capable route appears.

## Conversational PDA

- Interpreter: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\PDA_CommandInterpreter.ps1`
- Handoff gate: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Invoke-PDACommandHandoff.ps1`
- Chat bridge: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Invoke-PDAChatBridge.ps1`
- Webhook bridge: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Invoke-PDAWebhookBridge.ps1`
- HTTP bridge generator: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\New-PDAHttpBridgeWorkflow.ps1`
- n8n clipboard generator: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\New-PDAN8nClipboardWorkflow.ps1`
- reachability probe: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDAWebhookServerReachability.ps1`
- HTTP server: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Start-PDAWebhookServer.ps1`
- Phase 1 status: read-only interpreter with ontology-backed recommendations
- Phase 2 status: UI-facing confirmation gate before governed dispatch
- Phase 3 status: JSON bridge contract for Open WebUI / n8n
- Phase 4 status: webhook wrapper for n8n transport and confirmation replay
- Phase 5 status: local HTTP bridge for n8n HTTP Request integration
- Safety: unknown or ambiguous requests do not dispatch and confirmation is explicit only

## Open WebUI Integration Status

- Chat Bridge: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Invoke-PDAChatBridge.ps1`
- Webhook Bridge: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Invoke-PDAWebhookBridge.ps1`
- HTTP Bridge: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Start-PDAWebhookServer.ps1`
- n8n Clipboard Workflow: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\n8n Workflow\PDA-ChatBridge-HTTP-Clipboard.json`
- Webhook Reachability: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDAWebhookServerReachability.ps1`
- n8n Workflow: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\n8n Workflow\PDA-ChatBridge.json`
- HTTP Workflow: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\n8n Workflow\PDA-ChatBridge-HTTP.json`
- Integration Test Status: deterministic, local-only, no queue bypass

## Model Routing Policy

- Policy file: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\PDA_ModelRouting.json`
- Lookup script: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Get-PDAModelRoute.ps1`
- Test script: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDAModelRouting.ps1`
- Gateway: LiteLLM where possible
- Review worker: Claude or GPT
- Draft worker: GPT or Claude
- Research worker: Gemini or OpenRouter
- Sensitive or local-only tasks: local-llama only
- Validation status: pass

## LiteLLM Provider Health

- Config file: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\litellm\litellm_config.yaml`
- Compose file: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Runtime\docker-compose.yml`
- Validation script: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDALiteLLMProviders.ps1`
- Endpoint: `http://localhost:4000/v1/models`
- Provider routes: `openai`, `claude`, `gemini`, `openrouter`, `local-llama`
- Key loading: environment variables only via `os.environ/...`
- Secret policy: no provider secrets are checked into the repo
- Live validation: confirms the provider aliases exposed by LiteLLM match the expected routes
- Validation status: pass

## LiteLLM Env Loading

- Local env file: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\litellm\.env.local`
- Example template: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\litellm\.env.local.example`
- Compose env_file: `../litellm/.env.local`
- Validation script: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDALiteLLMEnv.ps1`
- Git ignore protection: `.gitignore` excludes `litellm/.env.local`
- Example safety: template contains placeholders only, no secrets
- Validation status: pass

## LiteLLM Invocation Adapter

- Adapter file: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Invoke-PDAModel.ps1`
- Validation script: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDAModelInvocation.ps1`
- Inputs: `worker_name`, `task_type`, `sensitivity`, `prompt`
- Flow: model route lookup, LiteLLM `/v1/chat/completions`, normalized JSON response
- Restricted local rule: `restricted_local` routes only to `local-llama`
- Secret policy: no provider secrets are checked into the repo
- Validation status: pass, with one skipped upstream provider case during live validation

## LiteLLM Fallback Status

- Validation script: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDAModelFallback.ps1`
- Fallback policy: approved draft/research routes may retry within their model candidate list
- Restricted local rule: no cloud fallback is allowed
- Draft fallback: enabled within approved policy
- Research fallback: enabled within approved policy
- Validation status: pass

## Review Worker Adapter

- Worker file: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Invoke-PDAReviewWorker.ps1`
- Validation script: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDAReviewWorker.ps1`
- Flow: `Get-PDAModelRoute.ps1` -> `Invoke-PDAModel.ps1` -> LiteLLM -> canonical result JSON
- Local route: review tasks are forced through `restricted_local` and stay on `local-llama`
- Result artifact: written to `PDA-Tasks/results/<task_id>-result.json`
- Failure handling: writes a safe failed result artifact without queue bypass
- Validation status: pass

## Draft Worker Adapter

- Worker file: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Invoke-PDADraftWorker.ps1`
- Validation script: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDADraftWorker.ps1`
- Flow: `Get-PDAModelRoute.ps1` -> `Invoke-PDAModel.ps1` -> LiteLLM -> canonical result JSON
- Default sensitivity: `standard`
- Route preference: `gpt` or `claude`
- Result artifact: written to `PDA-Tasks/results/<task_id>-result.json`
- Failure handling: writes a safe failed result artifact without queue bypass
- Validation status: pass

## Research Worker Adapter

- Worker file: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Invoke-PDAResearchWorker.ps1`
- Validation script: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDAResearchWorker.ps1`
- Flow: `Get-PDAModelRoute.ps1` -> `Invoke-PDAModel.ps1` -> LiteLLM -> canonical result JSON
- Default route: `gemini` or `openrouter`
- Result artifact: written to `PDA-Tasks/results/<task_id>-result.json`
- Failure handling: writes a safe failed result artifact without queue bypass
- Validation status: pass

## Reporter Pipeline Status

- Worker file: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Invoke-PDAReporterWorker.ps1`
- Validation script: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDAReporterWorker.ps1`
- Flow: `Invoke-PDATimelineWorker.ps1` -> `Invoke-PDAFindingsWorker.ps1` -> `Invoke-PDAResearchWorker.ps1` -> `Invoke-PDADraftWorker.ps1` -> `Invoke-PDAReviewWorker.ps1`
- Result artifact: written to `PDA-Tasks/results/<task_id>-result.json`
- Conversation lookup: passes through `latest_task_id` and `latest_result_path`
- Failure handling: writes a safe failed result artifact without queue bypass
- Validation status: pass

## Conversation State Registry

- Registry file: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Runtime\data\conversation-state.json`
- Lookup script: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Get-PDAConversationState.ps1`
- Update script: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Update-PDAConversationState.ps1`
- Bridge integration: conversation/session IDs now pass from Open WebUI Pipe through n8n to the bridge
- Tracked surfaces: active conversations, pending approvals, submitted tasks, completed tasks, latest results
- Status lookup: later prompts such as "What happened to my report?" resolve from the tracked conversation state
- Current live snapshot: `conv-live-dispatch-001` is the latest submitted conversation, `conv-live-pass-004` is the latest status lookup conversation
- Current tracked conversations: `conv-live-dispatch-001`, `conv-live-pass-004`, `conv-state-test-001`, `conv-state-test-004`, `default`

## Task Result Retrieval

- Lookup script: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Get-PDATaskResult.ps1`
- Test script: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDATaskResult.ps1`
- Live lookup mode: prefers `latest_task_id` from conversation state, then resolves the matching task record and result artifact
- Completed artifact example: `ea5d19d8-4cc0-427f-9be0-8659b10ffe8a-result.json`
- Live queued example: `conv-live-dispatch-001` resolves to task `e6deb443-580d-4d61-bf36-84f10125de9a` and reports queue wait status
- Result exposure: the bridge returns both task status text and latest result artifact metadata when a result exists
- Validation status: pass

## Ontology Enforcement

- Approved entrypoints snapshot: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\PDA_ApprovedEntrypoints.json`
- Static drift scan: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDAOntologyGovernance.ps1`
- Drift challenge test: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDAOntologyGovernanceDrift.ps1`
- Enforced rules: ontology validation, command to task-type resolution, eligible worker resolution, Category 2 local-only routing, and fail-closed handling for unknown commands.

## Repo Governance

- Preflight check: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDARepoGovernance.ps1`
- Scope: `Scripts\*.ps1` files that write to protected PDA task surfaces.
- Status: compared against the approved-entrypoint manifest before runtime dispatch.

## Retrieval Layer

- Shared retrieval module: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\PDA_Retrieval.ps1`
- Retrieval integrity check: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDARetrieval.ps1`
- Query wrappers: `Get-PDAArtifacts.ps1`, `Get-PDAMemory.ps1`, `Get-PDATaskOntologyEntry.ps1`, `Get-PDAWorkerCapability.ps1`
- Deterministic scope: artifact index, memory index, task ontology, worker registry, and lineage/foreign-reference validation only.

## Memory Taxonomy

- Taxonomy file: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\PDA_MemoryTaxonomy.json`
- Schema file: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\PDA_MemoryTaxonomy.schema.json`
- Validation helper: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Validate-PDAMemoryTaxonomy.ps1`
- Normalization checker: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\Test-PDAMemoryTaxonomy.ps1`
- Current status: pass
- Total memory records: 2
- Valid records: 2
- Invalid records: 0
- Missing fields: 0
- Invalid values: 0
- Invalid tags: 0
- Source reference issues: 0
- Orphaned lineage: 0

## Queue / Watchers

- Queue counts:
  - pending: 161
  - running: 0
  - completed: 40
  - failed: 0
  - results: 23
- Watchers:
  - queue worker: running
  - reporter intake watcher: running
  - multi-agent intake watcher: running

## Latest Artifacts

- Reporter manifest: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Reports\reporter-manifest-20260602-123105.json`
- Planner output: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Planner\planner-output-20260602-125723.md`
- Research output: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Research\research-output-20260602-130045.md`
- Review output: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Reviews\review-output-20260602-130620.md`
- Execute output: `C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Obsidian Vault\02_Projects\AI Tool Ecosystem\Agent Findings\Execution\execution-output-20260602-130629.md`

## Known Limitations

- `execute-worker` is intentionally dry-run/no-op unless explicitly approved.
- Message-only tests for `/review` and `/execute` create synthetic local inputs so real file-based validation remains strict.
- n8n is a staging transport only; canonical control lives in PowerShell queue workers.
- Codex remains for development and maintenance, not routine operation.

## Category Enforcement

| Category | Policy |
|---|---|
| `category_1` | Local or cloud-capable routing allowed. |
| `category_2` | Restricted-local only; no cloud-capable or external-api routing. |

- Restricted-local profile: no cloud credentials exposed in logs.
- If a local route is unavailable, routing fails closed and does not dispatch.
