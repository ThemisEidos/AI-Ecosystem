# PDA Dashboard v2

Updated: 2026-06-06 19:08:06 -07:00
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
| Queue depth | 468 |
| Pending | 468 |
| Running | 0 |
| Completed | 41 |
| Failed | 244 |
| Results | 533 |
| Pending approvals | 27 |

### Latest Queue Files

| queue | task_id | command | status | updated_at |
| --- | --- | --- | --- | --- |
| pending | 8ac1559b-e654-4c58-9822-a9a74567918a | /review | queued | 06/07/2026 02:05:35 |
| completed | b4486b1b-8663-4068-b110-b4f215ea418f | /research | success | 06/06/2026 03:47:41 |
| failed | 881c700e-d685-42e6-b7fa-39ca8d904501 | /research | failed | 06/06/2026 03:44:44 |
| results | 1394ef67-5e9f-4086-a32e-ec8112ea66b2 | /fabric | completed | 06/07/2026 01:56:00 |

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
| test-worker | running | STALE | 6018.94 | no |

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
| 8ac1559b-e654-4c58-9822-a9a74567918a | /review | review-worker | category_1 | pending | queued | 06/07/2026 02:05:35 |
| 0cc3d311-ec60-4e66-b49d-b4ed0f277b6c | /review | review-worker | category_1 | pending | queued | 06/07/2026 02:05:08 |
| ee1c040a-a000-4aa0-9152-3b8a60c8f4b0 | /review | review-worker | category_1 | pending | queued | 06/07/2026 02:04:52 |
| 2da0a1c0-0e67-4619-9f0c-14e41565ddd7 | /reporter | reporter-worker | category_1 | pending | queued | 06/07/2026 02:04:25 |
| a707bdfa-51fe-4ff7-807a-4a3e0cff446e | /reporter | reporter-worker | category_1 | pending | queued | 06/07/2026 02:04:09 |
| f67a0fe1-68a5-4e43-b1f2-f0056c28fbe8 | /fabric research | fabric-worker | category_1 | pending | pending | 06/07/2026 02:04:04 |
| 6ad0a462-538f-44a6-8bd2-8b961acfcc60 | /planner | planner-worker | category_1 | pending | queued | 06/07/2026 02:03:58 |
| ac9bc96c-c68b-4f9f-b365-a96aff0eb839 | /fabric research | fabric-worker | category_1 | pending | pending | 06/07/2026 02:03:48 |
| 1b8d8880-4350-4690-a41d-9dbffeae99df | /planner | planner-worker | category_1 | pending | queued | 06/07/2026 02:03:43 |
| 93fdc64e-9648-4106-a4ea-e7d6e7922d91 | /review | review-worker | category_1 | pending | queued | 06/07/2026 02:03:20 |

## Recent Reports / Artifacts

| artifact_id | created_at | worker_name | category | artifact_type | summary |
| --- | --- | --- | --- | --- | --- |
| artifact-40920de6-eb56-4f4f-aab5-e8e518fb5403 | 06/06/2026 18:56:00 | fabric-worker | category_2 | fabric_markdown | Fabric worker artifact output |
| artifact-61ffa5fc-54b9-427a-b122-c130eb86b976 | 06/06/2026 18:55:49 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |
| artifact-726495de-de46-4f78-bc27-bf920f608aa7 | 06/06/2026 18:54:54 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |
| artifact-74af87ea-d980-4d77-b21e-2bc57c77276e | 06/06/2026 18:53:58 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |
| artifact-87492c49-463e-422a-9d7b-89039a9748c2 | 06/06/2026 18:53:21 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |
| artifact-615e693f-e0bb-4c30-87ed-3d1245cd6996 | 06/06/2026 18:52:00 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |
| artifact-cb1f54b6-9f2b-4fea-8f68-bef676c9338c | 06/06/2026 18:50:39 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |
| artifact-105a695f-646e-47d2-ac24-942e7fe5e319 | 06/06/2026 18:50:39 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |
| artifact-10f12fc9-9ee3-4fa4-a951-7d401e859e00 | 06/06/2026 18:49:13 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |
| artifact-50a071c9-4b23-4cf4-b181-1e508f30a775 | 06/06/2026 18:49:12 | fabric-worker | category_1 | fabric_markdown | Fabric worker artifact output |

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
| Command Interpreter | pass | 11 | 0 | mapped / ambiguous / unknown routing |
| Governed Handoff | pass | 6 | 0 | confirmation gate |
| Chat Bridge | pass | 6 | 0 | Open WebUI / n8n bridge |
| Webhook Bridge | pass | 4 | 0 | webhook transport wrapper |

### Conversation Snapshot

| metric | value |
| --- | --- |
| Conversation status | pass |
| Conversation ID | default |
| Active tasks | 7 |
| Pending approvals | 0 |
| Submitted tasks | 7 |
| Completed tasks | 0 |
| Latest task ID | - |
| Latest result path | - |

> No tracked PDA task found for this conversation.

> Next: Ask the PDA to start a new task or confirm a queued request.

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
