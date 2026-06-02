# PDA Multi-Agent Orchestration Phase 2 Checkpoint

## Status
- Phase 2 introduces first-pass deterministic routing for `/planner`, `/research`, `/review`, and `/execute`.
- `/reporter` remains unchanged and continues to use the existing staged intake and reporter orchestration chain.
- The architecture keeps human-in-the-loop control and avoids autonomous agent loops.

## Routing Architecture
- n8n receives `POST /webhook/pda-command-router`.
- The webhook parser normalizes the incoming command into a deterministic `route` value.
- `/reporter` uses the existing reporter staging branch only.
- `/planner`, `/research`, `/review`, and `/execute` are staged into `PDA-Tasks/staging/n8n-router`.
- PowerShell intake converts staged route JSON into canonical queue tasks under `PDA-Tasks/pending`.
- `Start-PDAQueueWorker.ps1` advances queued tasks through the worker lifecycle.
- `Invoke-PDAWorker.ps1` dispatches to the route-specific worker scripts.

## Worker Contract
- Canonical task request schema: `Scripts/PDA_TaskRequest.schema.json`.
- Required fields:
  - `task_id`
  - `created`
  - `command`
  - `route`
  - `project`
  - `classification`
  - `status`
  - `requested_output`
  - `target`
  - `source`
  - `assigned_worker`
  - `next_worker`
  - `retry_count`
- Optional fields preserve compatibility with staged inputs and future local-only workflows:
  - `message`
  - `source_path`
  - `category`
  - `approved`
  - `origin`
  - `staged_path`

## Folder Structure
- Canonical queue root: `PDA-Tasks/`
- Staging:
  - `PDA-Tasks/staging/n8n-reporter`
  - `PDA-Tasks/staging/n8n-router`
  - `PDA-Tasks/staging/processed`
  - `PDA-Tasks/staging/failed`
- Queue states:
  - `PDA-Tasks/pending`
  - `PDA-Tasks/running`
  - `PDA-Tasks/completed`
  - `PDA-Tasks/failed`
  - `PDA-Tasks/results`
- Reporter-specific worker artifacts remain isolated under:
  - `PDA-Tasks/running/reporter-stages`
  - `PDA-Tasks/results/reporter-stages`
  - `PDA-Tasks/failed/reporter-stages`

## Command Normalization
- Supported commands are normalized by prefix:
  - `/planner`
  - `/reporter`
  - `/research`
  - `/review`
  - `/execute`
- The normalized route is stored as a lowercase deterministic token.
- Unsupported commands return the router result without queue dispatch.
- Staged tasks preserve the original message and command text for traceability.

## Queue Routing Logic
- Route → worker mapping:
  - `planner` → `planner-worker`
  - `research` → `research-worker`
  - `review` → `review-worker`
  - `execute` → `execute-worker`
- `reporter` remains routed through the dedicated reporter controller and is not folded into the generic router intake.
- `review` and `execute` require a valid `source_path` before dispatch.
- Queue tasks include `next_worker` for deterministic handoff metadata, but the queue worker remains the execution authority.

## Worker Lifecycle
- n8n stages JSON under `PDA-Tasks/staging/...`.
- PowerShell staged intake validates and normalizes the staged record.
- Intake writes canonical task JSON into `PDA-Tasks/pending`.
- Queue worker moves the task into `running`.
- Route-specific worker script generates deterministic output artifacts.
- Queue worker persists the result JSON into `PDA-Tasks/results`.
- Task then moves into `completed` or `failed`.

## Failure Handling
- Missing `route` or unsupported route fails at staged intake.
- Missing `source_path` for `review` and `execute` fails before queue dispatch.
- Staged files move to `PDA-Tasks/staging/failed` on validation failure.
- Execution failures are captured in worker result JSON and surface in `PDA-Tasks/results`.
- Retry behavior stays bounded and deterministic; no autonomous retry loops are introduced.

## Compatibility Notes
- `/reporter` remains unchanged and operational.
- Legacy `Tasks/` remains untouched for backward compatibility.
- The architecture is compatible with future local-only Category 2 workflows because task normalization occurs before worker execution.
- Compartmentalization stays intact: route staging, queue processing, and artifact generation are separate phases.

## Minimal Implementation Roadmap
- Keep the n8n workflow modular and reversible.
- Activate the updated webhook workflow in the live n8n instance.
- Validate `/planner`, `/research`, `/review`, and `/execute` one route at a time.
- Confirm staged intake creates canonical tasks in `PDA-Tasks/pending`.
- Confirm each worker emits its expected Obsidian artifact path.
- Add targeted worker coverage only where a route proves stable and genuinely useful.

## References
- `Scripts\PDA_TaskRequest.schema.json`
- `Scripts\Process-PDACommandStagedTasks.ps1`
- `Scripts\Invoke-PDAResearchWorker.ps1`
- `Scripts\Invoke-PDAExecuteWorker.ps1`
- `Scripts\Invoke-PDAWorker.ps1`
- `Scripts\Test-PDACommandRouter.ps1`
- `n8n Workflow\PDA_Command_Router.json`
- `workers.json`
