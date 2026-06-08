# PDA Dashboard v2

Updated: 2026-06-08 09:02:18 -07:00
Overall health: degraded

## System Health

| check | status | passed | failed | details |
| --- | --- | --- | --- | --- |
| PDA stack | pass | 5 | 0 | Open WebUI / n8n / LiteLLM / Ollama |
| Deep validation | pass | - | - | Open WebUI chat completion |

| name | passed | type | status_code |
| --- | --- | --- | --- |
| Open WebUI | yes | service | 200 |
| n8n | yes | service | 200 |
| LiteLLM | yes | service | 401 |
| Ollama | yes | service | 200 |
| Open WebUI Chat Completion | yes | deep_validation | 200 |

## Queue Status

| metric | value |
| --- | --- |
| Queue depth | 672 |
| Pending | 672 |
| Running | 0 |
| Completed | 41 |
| Failed | 244 |
| Results | 541 |
| Pending approvals | 27 |

### Latest Queue Files

| queue | task_id | command | status | updated_at |
| --- | --- | --- | --- | --- |
| pending | 3062ec8a-cfc1-487d-ac40-13a206058937 | /review | queued | 06/08/2026 15:53:59 |
| completed | b4486b1b-8663-4068-b110-b4f215ea418f | /research | success | 06/06/2026 03:47:41 |
| failed | 881c700e-d685-42e6-b7fa-39ca8d904501 | /research | failed | 06/06/2026 03:44:44 |
| results | cf20b3bf-0b72-46e7-a0fe-4bb92c0c065c | /fabric security | completed | 06/07/2026 03:40:10 |

## Worker Status

| worker_name | command | status | routing_surface | cloud_capable | accepted_input_modes |
| --- | --- | --- | --- | --- | --- |
| reporter-worker | /reporter | active | local-only | no | staged-json, queue-json |
| planner-worker | /planner | active | local-only | no | queue-json, staged-json, message-only-test |
| operator-console-worker | /status | active | local-only | no | message-only-test |
| notebooklm-worker | /notebooklm | active | local-only | no | message-only-test, file-based |
| research-worker | /research | active | local-only | no | queue-json, staged-json, message-only-test |
| draft-worker | /draft | active | local-or-cloud | yes | file-based, message-only-test |
| review-worker | /review | active | local-only | no | file-based, message-only-test |
| execute-worker | /execute | active | local-only | no | file-based, message-only-test-dry-run |
| fabric-worker | /fabric | experimental | local-or-litellm | yes | message-only-test, file |

### Runtime States

| component | status | pid | started_at |
| --- | --- | --- | --- |
| pda-worker-state | running | 19676 | 06/03/2026 04:23:53 |
| pda-reporter-intake-state | running | 26484 | 06/03/2026 04:24:02 |
| pda-multiagent-intake-state | running | 25164 | 06/03/2026 04:24:10 |

### Heartbeats

| worker_name | status | state | age_minutes | process_live |
| --- | --- | --- | --- | --- |
| test-worker | running | STALE | 8294.47 | no |

## Pending Approvals

| task_id | command | worker | category | approval_status | updated_at | file_name |
| --- | --- | --- | --- | --- | --- | --- |
| 3013f01d-bb38-4d22-addd-6cbe716f2ff6 | /execute | execute-worker | category_1 | pending | 06/06/2026 03:34:37 | 2026-06-05_20-34-37-execute.json |
| 6e640052-e868-4eb2-b5e1-908861b49d22 | /execute | execute-worker | category_1 | pending | 06/06/2026 03:32:16 | 2026-06-05_20-32-16-execute.json |
| f92850bd-a0f0-4fc8-a61c-dada79be843f | /review | review-worker | category_2 | pending | 06/03/2026 23:02:04 | approval-category2.json |
| 0af1ad7e-a52f-46e2-9710-d697bf18571a | /execute | execute-worker | category_1 | pending | 06/03/2026 23:02:03 | approval-execute.json |
| 5cd5435c-91c3-4b7c-974d-7db09c198706 | /review | review-worker | category_2 | pending | 06/03/2026 22:06:10 | 5cd5435c-91c3-4b7c-974d-7db09c198706.json |
| f499fe03-4beb-4a1f-aa19-9a6ec0b59858 | /review | review-worker | category_2 | pending | 06/03/2026 21:31:03 | f499fe03-4beb-4a1f-aa19-9a6ec0b59858.json |
| 91619039-fd2c-41e2-874f-c56fa8c360ad | /review | review-worker | category_2 | pending | 06/03/2026 21:21:50 | 91619039-fd2c-41e2-874f-c56fa8c360ad.json |
| 93a0ef92-3437-4e32-aa58-ff0e6af72370 | /review | review-worker | category_2 | pending | 06/03/2026 21:16:01 | 93a0ef92-3437-4e32-aa58-ff0e6af72370.json |
| ec022471-2812-4968-88d8-e51c31e5fd0c | /review | review-worker | category_2 | pending | 06/03/2026 21:08:55 | ec022471-2812-4968-88d8-e51c31e5fd0c.json |
| b7b97849-807c-45a9-97ca-b274681bb09a | /review | review-worker | category_2 | pending | 06/03/2026 20:42:25 | b7b97849-807c-45a9-97ca-b274681bb09a.json |

## Recent Tasks

| task_id | command | worker | category | queue | status | updated_at |
| --- | --- | --- | --- | --- | --- | --- |
| 3062ec8a-cfc1-487d-ac40-13a206058937 | /review | review-worker | category_1 | pending | queued | 06/08/2026 15:53:59 |
| a0647fdd-20aa-4bac-9d7e-827e6b7cc73c | /reporter | reporter-worker | category_1 | pending | queued | 06/08/2026 15:53:36 |
| ebb25cd8-14a1-4254-9b9e-f8cb23be38e8 | /review | review-worker | category_1 | pending | queued | 06/08/2026 15:50:08 |
| c2cfa010-cfe7-4fa6-a20b-885f9f96b497 | /reporter | reporter-worker | category_1 | pending | queued | 06/08/2026 15:49:45 |
| 5406f909-4d1c-46fe-85b6-e8e50d53ec77 | /fabric research | fabric-worker | category_1 | pending | pending | 06/08/2026 15:48:24 |
| 6b53a1fb-9242-44d3-841d-e3c685ae253e | /review | review-worker | category_1 | pending | queued | 06/08/2026 15:47:58 |
| 5d93121b-5c63-46d9-86e6-b20d6a17ee1e | /reporter | reporter-worker | category_1 | pending | queued | 06/08/2026 15:47:35 |
| c8ce1075-54f0-49b9-b480-e68e96d04db3 | /planner | planner-worker | category_1 | pending | queued | 06/08/2026 15:47:31 |
| f7ae6bf8-0f3a-4f35-b9db-31cc18ba9dad | /fabric research | fabric-worker | category_1 | pending | pending | 06/08/2026 15:42:22 |
| 8a9029bb-bcee-4678-b67e-0c27e2ce6af4 | /review | review-worker | category_1 | pending | queued | 06/08/2026 15:41:55 |

## Recent Reports / Artifacts

| artifact_id | created_at | worker_name | category | artifact_type | summary |
| --- | --- | --- | --- | --- | --- |
| artifact-a542509e-adaf-41fb-b97e-4e8b669639db | 06/06/2026 20:40:10 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |
| artifact-36b337b2-c1f4-45a3-b995-b44909a3b2d0 | 06/06/2026 20:39:31 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |
| artifact-a1c45cbd-2daf-426c-886b-a66443131268 | 06/06/2026 20:38:22 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |
| artifact-ed7a28e4-f060-4da8-9129-0f32c91c37d7 | 06/06/2026 20:37:18 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |
| artifact-47b7e178-374d-413b-8b51-066ca08477f6 | 06/06/2026 20:36:16 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |
| artifact-b78f9dc3-f0b1-4502-aff3-7ea9a0a281f4 | 06/06/2026 20:35:42 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |
| artifact-6656fab3-413f-43c5-a2ee-b8ed6042c862 | 06/06/2026 20:35:08 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |
| artifact-71dfdab7-50d8-42f4-ba97-c9e2b0461cfa | 06/06/2026 20:34:29 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |
| artifact-40920de6-eb56-4f4f-aab5-e8e518fb5403 | 06/06/2026 18:56:00 | fabric-worker | category_2 | fabric_markdown | Fabric worker artifact output |
| artifact-61ffa5fc-54b9-427a-b122-c130eb86b976 | 06/06/2026 18:55:49 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |

## Model Status

| metric | status | path | count | passed | failed | loaded | blank | missing |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Routing policy | pass | C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\PDA_ModelRouting.json | 1 | - | - | - | - | - |
| Provider validation | fail | - | 0 | 0 | 0 | - | - | - |
| Env validation | pass | - | 1 | - | - | 5 | 0 | 0 |

### Command Routes

| command | primary_model | fallback_chain | routing_surface | cloud_allowed |
| --- | --- | --- | --- | --- |
| /research | gemini | openrouter | cloud-capable | yes |
| /review | claude | openai | cloud-capable | yes |
| /draft | openai | claude | cloud-capable | yes |
| /execute | local-llama | - | local-only | no |

### Provider Availability

- No provider rows found.

## Capability Router

| metric | value |
| --- | --- |
| Status | pass |
| Matrix path | C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\PDA_CapabilityMatrix.json |
| Route count | 19 |
| Local-only routes | 12 |
| Cloud-allowed routes | 7 |

### Fabric CLI Status

| metric | value |
| --- | --- |
| Status | pass |
| Message | Fabric CLI is installed and PDA patterns are synced. |
| Executable path | C:\Users\earth\.local\bin\fabric.exe |
| Version | 1.4.454 |
| Pattern count | 258 |
| Pattern listing | pass |

## PDA Commander Integration

| component | status | passed | failed | details |
| --- | --- | --- | --- | --- |
| Command Interpreter | pass | 12 | 0 | mapped / ambiguous / unknown routing |
| Governed Handoff | pass | 4 | 0 | confirmation gate |
| Chat Bridge | pass | 4 | 0 | Open WebUI / n8n bridge |
| Webhook Bridge | fail | 1 | 2 | webhook transport wrapper |

### Conversation Snapshot

| metric | value |
| --- | --- |
| Conversation status | pass |
| Conversation ID | default |
| Active tasks | 3 |
| Pending approvals | 1 |
| Submitted tasks | 3 |
| Completed tasks | 0 |
| Latest task ID | - |
| Latest result path | - |

> No tracked PDA task found for this conversation.

> Next: Ask the PDA to start a new task or confirm a queued request.

## PDA Commander Briefing

| metric | value |
| --- | --- |
| Briefing status | degraded |
| Focus | default |
| Dashboard health | degraded |
| Queue depth | 0 |
| Pending approvals | 0 |
| Failed tasks | 0 |
| Memory candidates | 0 |
| Memory approvals | 0 |
| Recommended action | Review the dashboard and continue normal operations |
| Recommended executor | Human operator |

### Commander Actions

| action | executor | reason |
| --- | --- | --- |
| Review the dashboard and continue normal operations | Human operator | No immediate blockers were found. |

## Dispatch Queue

| metric | value |
| --- | --- |
| Status | pass |
| Executor count | 10 |
| Pending approvals | 27 |
| Approved | 11 |
| Prepared | 0 |
| Running | 0 |
| Completed | 41 |
| Failed | 244 |

### Executor Registry

| executor_name | display_name | executor_type | risk_level | requires_approval | supports_category2 | supports_local_only | dispatch_method |
| --- | --- | --- | --- | --- | --- | --- | --- |
| codex | Codex | local_cli | medium | yes | yes | yes | local_prompt_package |
| gemini-cli | Gemini CLI | cloud_cli | medium | yes | no | no | cloud_prompt_package |
| n8n | n8n | workflow_orchestrator | medium | yes | yes | yes | workflow_request |
| reporter-worker | Reporter Worker | pda_worker | low | yes | yes | yes | task_queue |
| planner-worker | Planner Worker | pda_worker | low | yes | yes | yes | task_queue |
| review-worker | Review Worker | pda_worker | low | yes | yes | yes | task_queue |
| execute-worker | Execute Worker | pda_worker | medium | yes | yes | yes | task_queue |
| research-worker | Research Worker | pda_worker | low | yes | yes | yes | task_queue |
| notebooklm | NotebookLM | cloud_learning_service | medium | yes | no | no | sanitized_package |
| operator-console-worker | Operator Console Worker | pda_worker | low | no | yes | yes | operator_console |

### Recent Dispatches

| task_id | command | executor_name | dispatch_state | approval_status | updated_at | file_name |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-06-05_20-47-32-research | - | - | - | - | 06/06/2026 03:47:41 | 2026-06-05_20-47-32-research.json |
| 2026-06-05_20-44-42-research | - | - | - | - | 06/06/2026 03:44:44 | 2026-06-05_20-44-42-research.json |
| 2026-06-05_20-41-37-research | - | - | - | - | 06/06/2026 03:42:18 | 2026-06-05_20-41-37-research.json |
| 2026-06-05_20-40-27-review | - | - | - | - | 06/06/2026 03:42:18 | 2026-06-05_20-40-27-review.json |
| 2026-06-05_20-39-58-reporter | - | - | - | - | 06/06/2026 03:42:17 | 2026-06-05_20-39-58-reporter.json |
| 2026-06-05_20-39-50-planner | - | - | - | - | 06/06/2026 03:42:17 | 2026-06-05_20-39-50-planner.json |
| 2026-06-05_19-48-06-review | - | - | - | - | 06/06/2026 03:42:17 | 2026-06-05_19-48-06-review.json |
| 2026-06-05_19-47-45-review | - | - | - | - | 06/06/2026 03:42:17 | 2026-06-05_19-47-45-review.json |
| 2026-06-05_19-47-34-reporter | - | - | - | - | 06/06/2026 03:42:17 | 2026-06-05_19-47-34-reporter.json |
| 2026-06-05_19-45-56-review | - | - | - | - | 06/06/2026 03:42:17 | 2026-06-05_19-45-56-review.json |
| 2026-06-05_19-45-36-review | - | - | - | - | 06/06/2026 03:42:17 | 2026-06-05_19-45-36-review.json |
| 2026-06-05_19-45-26-reporter | - | - | - | - | 06/06/2026 03:42:17 | 2026-06-05_19-45-26-reporter.json |
| 2026-06-05_19-45-17-planner | - | - | - | - | 06/06/2026 03:42:17 | 2026-06-05_19-45-17-planner.json |
| 2026-06-05_13-57-12-review | - | - | - | - | 06/06/2026 03:42:17 | 2026-06-05_13-57-12-review.json |
| 2026-06-05_13-56-40-reporter | - | - | - | - | 06/06/2026 03:42:17 | 2026-06-05_13-56-40-reporter.json |
| 2026-06-05_13-54-20-review | - | - | - | - | 06/06/2026 03:42:17 | 2026-06-05_13-54-20-review.json |
| 2026-06-05_13-53-52-reporter | - | - | - | - | 06/06/2026 03:42:16 | 2026-06-05_13-53-52-reporter.json |
| 2026-06-05_13-42-15-reporter | - | - | - | - | 06/06/2026 03:42:16 | 2026-06-05_13-42-15-reporter.json |
| 2026-06-05_12-49-16-research | - | - | - | - | 06/06/2026 03:42:16 | 2026-06-05_12-49-16-research.json |
| 2026-06-04_15-48-53-research | - | - | - | - | 06/06/2026 03:42:16 | 2026-06-04_15-48-53-research.json |

## Memory Summary

| metric | value |
| --- | --- |
| Memory count | 2 |
| Updated at | 06/03/2026 13:26:24 |
| By type | promoted-artifact: 1, test-note: 1 |
| By category | category_1: 1, test: 1 |

### Memory Types

| name | count |
| --- | --- |
| promoted-artifact | 1 |
| test-note | 1 |

### Memory Categories

| name | count |
| --- | --- |
| category_1 | 1 |
| test | 1 |

### Recent Memories

| memory_id | created_at | memory_type | category | title | summary |
| --- | --- | --- | --- | --- | --- |
| memory-17eaed7d-80ae-46e0-9541-7d48762b8229 | 06/02/2026 21:32:05 | promoted-artifact | category_1 | Planner artifact promoted to memory | Promoted the planner output for durable retention. |
| memory-7d41a212-3f98-4a48-8e1a-45fd67203375 | 06/02/2026 21:27:30 | test-note | test | Memory validation sample | Harmless test memory for validating the registry. |
