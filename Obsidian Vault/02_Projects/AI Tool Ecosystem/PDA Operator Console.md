# PDA Operator Console

Updated: 2026-06-05 13:35:14

## Dashboard Index

- [[System Status]]
- [[Routing Summary]]
- [[Task Summary]]

## Snapshot

- Service health source: `aiec-status`
- Routing records: 14
- Dispatch success rate: 85.71%
- Queue depth: 227
- Memory records: 2
- Artifact records: 317

## Key Metrics

| metric | value |
| --- | --- |
| Cloud usage | 8 |
| Local usage | 6 |
| Fallback used | 0 |
| Pending tasks | 227 |
| Running tasks | 0 |
| Recent artifacts | 10 |

## Recent Tasks

| task_id | command | worker | category | queue | status | updated_at |
| --- | --- | --- | --- | --- | --- | --- |
| 6a3c7914-6fc7-4321-bc68-411ac0c5628c | /research |  | category_1 | pending | queued | 2026-06-05T12:49:16 |
| 9cb0189f-5f01-4f72-84e7-6a5265673d76 |  | execute-worker |  | results | success | 2026-06-05T12:44:27 |
| c04e4394-3127-46c6-84fa-e3b8a511c0c8 |  | execute-worker |  | results | failed | 2026-06-05T12:43:01 |
| ba4139bd-9335-4a66-9ef4-56a0917b3b55 | /research |  | category_1 | pending | queued | 2026-06-04T15:48:53 |
| e5d0e279-f990-45f2-a00c-c907e1e84566 | /review |  | category_1 | pending | queued | 2026-06-04T15:44:31 |
| 1a2f2e62-3bdd-4877-9e3b-0aa70b36c5c1 | /review |  | category_1 | pending | queued | 2026-06-04T15:43:54 |
| 06c01981-a5b1-43db-800d-9e6e4055ac7c | /review |  | category_1 | pending | queued | 2026-06-04T15:43:37 |
| 24684ca0-9fea-4689-acd6-65fc81eae136 | /reporter |  | category_1 | pending | queued | 2026-06-04T15:43:27 |
| 59176dfc-e50a-4a7d-a8bb-4bb197c0f67d | /review |  | category_1 | pending | queued | 2026-06-04T15:43:01 |
| 14e048bc-4545-484c-8a58-b38541d8c1d4 | /reporter |  | category_1 | pending | queued | 2026-06-04T15:42:36 |

## Recent Artifacts

| artifact_id | created_at | worker_name | category | artifact_type |
| --- | --- | --- | --- | --- |
| artifact-d3b49040-6c40-4620-9846-eb733dae70c0 | 06/05/2026 12:44:27 | execute-worker | category_1 | worker_result_json |
| artifact-b8af77a3-f37e-4aa4-a591-b64a54f1fa8c | 06/05/2026 12:44:27 | execute-worker | category_1 | execution_markdown |
| artifact-6c218a0d-6cbd-44e7-b2db-10157f8047d9 | 06/05/2026 12:43:01 | execute-worker | category_1 | worker_result_json |
| artifact-33f4f713-6384-46f6-bb7e-97d689f3d18b | 06/04/2026 15:17:18 | reporter-worker | category_1 | worker_result_json |
| artifact-f92150c9-711d-4c99-a64a-dbcd404f133c | 06/04/2026 15:17:18 | reporter-worker | category_1 | report_pipeline_markdown |
| artifact-99111ca3-3acf-4a8a-b27c-1417ac104bd6 | 06/04/2026 15:17:14 | review-worker | category_1 | review_markdown |
| artifact-e44b759a-7451-490c-be14-23d6dc976a4b | 06/04/2026 15:17:14 | reporter-worker | category_1 | worker_result_json |
| artifact-cfebcf3e-68e4-462e-9b3f-53147c6d1006 | 06/04/2026 15:17:14 | reporter-worker | category_1 | report_pipeline_markdown |
| artifact-86dfbd9f-dc56-477e-b700-f2adb87f2cd2 | 06/04/2026 15:17:14 | review-worker | category_1 | worker_result_json |
| artifact-04bb43fd-d116-422a-aa14-70fe5b5356dd | 06/04/2026 15:17:08 | draft-worker | category_1 | worker_result_json |
