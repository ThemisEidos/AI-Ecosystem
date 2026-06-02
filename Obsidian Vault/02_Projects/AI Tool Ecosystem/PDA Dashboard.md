# PDA Dashboard

Last updated: 2026-06-02

## Active Workers

| Worker | Command | Status | Notes |
|---|---|---|---|
| `reporter-worker` | `/reporter` | active | Preserves reporter chain and staged intake. |
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

## Queue / Watchers

- Queue counts:
  - pending: 0
  - running: 0
  - completed: 34
  - failed: 0
  - results: 15
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
