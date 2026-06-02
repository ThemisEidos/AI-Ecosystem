# Agent Capability Matrix

This note mirrors the canonical worker registry in `Scripts/PDA_WorkerRegistry.json`.

## Active Workers

| Worker | Command | Purpose | Input Modes | Required Fields | Output Locations | Safety | Status |
|---|---|---|---|---|---|---|---|
| `reporter-worker` | `/reporter` | Deterministic orchestration across timeline → findings → draft → review. | `staged-json`, `queue-json` | `task_id`, `command`, `message`, `project`, `classification`, `source_path`, `approved` | `PDA-Tasks/results`, `Obsidian Vault/02_Projects/AI Tool Ecosystem/Agent Findings/Reports` | No loops, no legacy `Tasks/`, no side effects in the controller. | active |
| `planner-worker` | `/planner` | Produce implementation-focused execution plans. | `queue-json`, `staged-json`, `message-only-test` | `task_id`, `command`, `project`, `classification` | `PDA-Tasks/results`, `.../Agent Findings/Planner` | Planning only; no execution side effects. | active |
| `research-worker` | `/research` | Produce concise operational research synthesis. | `queue-json`, `staged-json`, `message-only-test` | `task_id`, `command`, `project`, `classification` | `PDA-Tasks/results`, `.../Agent Findings/Research` | No invented facts; separate findings from open questions. | active |
| `review-worker` | `/review` | Review drafts for unsupported claims and clarity. | `file-based`, `message-only-test` | `task_id`, `command`, `project`, `classification` | `PDA-Tasks/results`, `.../Agent Findings/Reviews` | File-based tasks must resolve; test mode is stub-safe. | active |
| `execute-worker` | `/execute` | Produce deterministic execution manifests. | `file-based`, `message-only-test-dry-run` | `task_id`, `command`, `project`, `classification` | `PDA-Tasks/results`, `.../Agent Findings/Execution` | Dry-run/no-op unless explicitly approved. | active |

## Notes

- The registry is the operational source of truth for supported commands and task shape.
- `review-worker` and `execute-worker` support message-only test mode through intake synthesis, not by weakening file validation.
- `execute-worker` remains non-destructive by default.
- `reporter-worker` remains unchanged and uses the existing staged intake path.
- Category 2 tasks use the restricted-local profile and fail closed when no local route exists.
- Category 1 tasks may use local or cloud-capable routing if those routes are added later.
