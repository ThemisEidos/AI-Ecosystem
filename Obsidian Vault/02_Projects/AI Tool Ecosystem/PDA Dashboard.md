# PDA Dashboard v2

Updated: 2026-06-05 23:07:00 -07:00
Overall health: pass

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
| Queue depth | 71 |
| Pending | 71 |
| Running | 0 |
| Completed | 41 |
| Failed | 244 |
| Results | 521 |
| Pending approvals | 27 |

### Latest Queue Files

| queue | task_id | command | status | updated_at |
| --- | --- | --- | --- | --- |
| pending | 7fed2f49-eb17-41f5-9443-be7cc525b9b2 | /review | queued | 06/06/2026 06:05:01 |
| completed | b4486b1b-8663-4068-b110-b4f215ea418f | /research | success | 06/06/2026 03:47:41 |
| failed | 881c700e-d685-42e6-b7fa-39ca8d904501 | /research | failed | 06/06/2026 03:44:44 |
| results | 8830e146-9624-4700-8a42-3cd5858b9eeb | - | completed | 06/06/2026 04:56:12 |

## Worker Status

| worker_name | command | status | routing_surface | cloud_capable | accepted_input_modes |
| --- | --- | --- | --- | --- | --- |
| reporter-worker | /reporter | active | local-only | no | staged-json, queue-json |
| planner-worker | /planner | active | local-only | no | queue-json, staged-json, message-only-test |
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
| test-worker | running | STALE | 4818.34 | no |

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
| 7fed2f49-eb17-41f5-9443-be7cc525b9b2 | /review | review-worker | category_1 | pending | queued | 06/06/2026 06:05:01 |
| d47d67b9-3071-4bfe-84d0-78d273b4ace2 | /review | review-worker | category_1 | pending | queued | 06/06/2026 06:04:28 |
| e050c7c2-30cd-42c6-9a50-e389455e7caf | /reporter | reporter-worker | category_1 | pending | queued | 06/06/2026 06:03:55 |
| 87d8b47f-3747-4256-87c2-f08649335b7f | /planner | planner-worker | category_1 | pending | queued | 06/06/2026 06:03:37 |
| 1f33ea4f-4981-4e8e-b8a9-1a29e915604b | /review | review-worker | category_1 | pending | queued | 06/06/2026 06:02:59 |
| 74333a35-507a-4601-9402-619449dfc22a | /review | review-worker | category_1 | pending | queued | 06/06/2026 06:02:29 |
| 0bd26de3-ea5b-404f-9e13-05834c1fec87 | /review | review-worker | category_1 | pending | queued | 06/06/2026 06:02:26 |
| 3e16aa88-7ea5-4730-bc2d-809ed51c26b8 | /review | review-worker | category_1 | pending | queued | 06/06/2026 06:01:54 |
| 17bde713-f10a-48d9-b061-e74e921ce082 | /reporter | reporter-worker | category_1 | pending | queued | 06/06/2026 06:01:51 |
| 9e4ea66a-7aef-4179-bdf3-cb28905f4ed2 | /planner | planner-worker | category_1 | pending | queued | 06/06/2026 06:01:31 |

## Recent Reports / Artifacts

| artifact_id | created_at | worker_name | category | artifact_type | summary |
| --- | --- | --- | --- | --- | --- |
| artifact-e411c055-55e8-418c-a219-08a96a346d91 | 06/05/2026 21:56:13 | review-worker | category_2 | worker_result_json | Review worker canonical result contract |
| artifact-7c8f9604-e9a2-4119-abc8-1907da2e35da | 06/05/2026 21:56:12 | review-worker | category_2 | worker_result_json | Review worker canonical result contract |
| artifact-3d5464ec-d37f-41a2-8bc1-20271f21fec1 | 06/05/2026 21:56:12 | review-worker | category_2 | review_markdown | Review worker markdown output |
| artifact-cd57c999-5e1a-4546-9a6d-d23997d5b61e | 06/05/2026 21:55:11 | draft-worker | category_1 | worker_result_json | Draft worker canonical result contract |
| artifact-618843e4-fa0b-4fda-993d-dcb7bf58aa1a | 06/05/2026 21:55:10 | draft-worker | category_1 | draft_markdown | Draft worker markdown output |
| artifact-2f9b138a-1af2-4a67-b279-aa42286c4016 | 06/05/2026 21:55:10 | draft-worker | category_1 | worker_result_json | Draft worker canonical result contract |
| artifact-3a4fc72e-a00a-44d1-9a1a-81e205da7fb4 | 06/05/2026 21:55:04 | draft-worker | category_1 | draft_markdown | Draft worker markdown output |
| artifact-701edbba-e641-44b7-bcea-bbec1ce76300 | 06/05/2026 21:55:04 | draft-worker | category_1 | worker_result_json | Draft worker canonical result contract |
| artifact-f7287e2c-d766-446c-ad78-5e6eaf457502 | 06/05/2026 21:54:58 | research-worker | category_3 | worker_result_json | Research worker canonical result contract |
| artifact-bd0d5b4e-c180-47d4-8411-92a3ffba941b | 06/05/2026 21:54:57 | research-worker | category_3 | worker_result_json | Research worker canonical result contract |

## Model Status

| metric | status | path | count | passed | failed | loaded | blank | missing |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Routing policy | pass | C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Scripts\PDA_ModelRouting.json | 1 | - | - | - | - | - |
| Provider validation | pass | - | 5 | 5 | 0 | - | - | - |
| Env validation | pass | - | 1 | - | - | 5 | 0 | 0 |

### Command Routes

| command | primary_model | fallback_chain | routing_surface | cloud_allowed |
| --- | --- | --- | --- | --- |
| /research | gemini | openrouter | cloud-capable | yes |
| /review | claude | openai | cloud-capable | yes |
| /draft | openai | claude | cloud-capable | yes |
| /execute | local-llama | - | local-only | no |

### Provider Availability

| name | configured | env_reference_ok | host_env_present | live_available | api_provider |
| --- | --- | --- | --- | --- | --- |
| openai | yes | yes | yes | yes | openai/gpt-4o-mini |
| claude | yes | yes | yes | yes | anthropic/claude-sonnet-4-5-20250929 |
| gemini | yes | yes | yes | yes | gemini/gemini-2.0-flash |
| openrouter | yes | yes | yes | yes | openrouter/openai/gpt-4o-mini |
| local-llama | yes | yes | yes | yes | ollama/llama3.2 |

## PDA Commander Integration

| component | status | passed | failed | details |
| --- | --- | --- | --- | --- |
| Command Interpreter | pass | 7 | 0 | mapped / ambiguous / unknown routing |
| Governed Handoff | pass | 5 | 0 | confirmation gate |
| Chat Bridge | pass | 6 | 0 | Open WebUI / n8n bridge |
| Webhook Bridge | pass | 4 | 0 | webhook transport wrapper |

### Conversation Snapshot

| metric | value |
| --- | --- |
| Conversation status | pass |
| Conversation ID | default |
| Active tasks | 18 |
| Pending approvals | 0 |
| Submitted tasks | 18 |
| Completed tasks | 0 |
| Latest task ID | - |
| Latest result path | - |

> Task e050c7c2-30cd-42c6-9a50-e389455e7caf for /reporter has been submitted and is waiting in the queue.

> Next: Wait for the queue worker to finish, then ask again for the latest status.

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
