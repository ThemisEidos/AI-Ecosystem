# North Star — COOPER Project Direction

> Updated 2026-07-01. Source of truth: PROGRESS.md + PRD.md.

## Current Position

**All 9 steps COMPLETE (2026-07-02).** Step 9 shipped and DoD-verified live: the private
compose stack (`PDA-Runtime/docker-compose.private.yml`) brings cooper-core + Ollama +
Open WebUI fully online — health, auth, classify, dispatch→approve→execute all verified
in-container. Spec §4 (drop `internal: true`) was re-reviewed and confirmed post-audit;
spec §8 lists the post-audit amendments that were applied. GPU reservation on
private-ollama is required for usable inference (~90 s/turn warm vs >5 min on CPU).
The `.venv-win` dev-mode path (`Start-CooperCore.ps1`) remains the faster daily driver
(~30 s/turn via Windows-host Ollama).

Next horizon (not yet scoped): Pop!_OS deployment test, merge `step-9-dockerize` → `main`.
(Open Workshop containerization done 2026-07-07; Steps 12 and 13 now done — see below. Step 10
in progress on `step-10-skills`, Step 11 not started.)

### 2026-07-08 · Step 13 complete (session-bound approvals + install-cooper.sh)

Built on `step-13-sessions` (from `step-9-dockerize`) via subagent-driven-development; merged
(fast-forward) back into `step-9-dockerize`, branch/worktree cleaned up. Full detail in
`PROGRESS.md`'s decision log. Highlights for next session:
- Approval tickets now key on `(workshop, session_id)`, not just `workshop` — client A can
  never see/consume client B's pending ticket.
- `COOPER_API_KEYS` (comma-separated multi-key auth) + `install-cooper.sh` one-command bootstrap
  now exist. `cooper-local` (the old universal default key) is retired the moment
  `install-cooper.sh` seeds a real `.env` — see `Gotchas.md` for the mechanism if touching auth
  config again.
- Step 12 (Signal gateway) merged into `step-9-dockerize` **mid-branch**, forcing a rebase —
  see `Gotchas.md`'s "parallel worktree base moved" entry before starting Step 11 in a worktree
  branched from a still-moving integration branch.
- **Not done, flagged not claimed:** Open WebUI browser click-through (no browser tool in that
  session) and live Signal-phone approval test (no physical device). Do these before treating
  Steps 12/13 as fully DoD-closed if a phone/browser becomes available.

### 2026-07-08 · Steps 10–13 scoped: COOPER × Hermes merge

Decision: native port of Hermes Agent's capability patterns into cooper-core,
SKILL.md-format-compatible, **zero vendored code** — COOPER keeps its governance, gains
Hermes's ecosystem (skills are portable data, so the 90K-skill hub stays reachable).
Spec: `Docs/superpowers/specs/2026-07-08-cooper-hermes-merge-design.md`. Plans (commit
50de439, `Docs/superpowers/plans/2026-07-08-step-1*.md`):

| # | Name | Order | Status |
|---|------|-------|--------|
| 10 | Governed skills subsystem (hash-pinned manifest) | BLOCKER — first | in progress (`step-10-skills`) |
| 11 | Self-improvement loop (draft → approve → promote) | after 10 | not started |
| 12 | Signal gateway (signal-cli-rest-api, Open only) | parallel worktree | done, merged 2026-07-08 (live phone test pending) |
| 13 | Session-bound approvals + install-cooper.sh | parallel worktree | done, merged 2026-07-08 |

Execute on **Sonnet** (user cost decision); plans carry complete code + tests, follow
superpowers:subagent-driven-development. Human prereq: Signal account registration/linking
before Step 12 Task 4. Note: `~/.claude/agents/planner.md` pins opus — avoid or override
during Sonnet execution.

**⚠️ BRANCH CHECK FIRST:** the branch this project's code lived on (`codex/nightly-task-002-20260606-165602`) was discarded 2026-07-01/02. All work (Steps 1-9) now lives on **`step-9-dockerize`**, recovered from the same tip commit. `main` does not have this code. Run `git branch --show-current` before doing anything — do not assume.

## 9-Step Roadmap

| # | Name | Status |
|---|------|--------|
| 1 | Conversational runtime (FastAPI + Ollama) | done 2026-06-28 |
| 2 | Decision layer (classifier) | done 2026-06-28, re-verified 2026-06-29/30 |
| 3 | Registry reader + router (Quartermaster) | done 2026-07-01 |
| 4 | Approval gate (Safety Officer) | done 2026-07-01 |
| 5 | Execution gateway + one real tool (Workbench) | done 2026-07-01 |
| 6 | Workshop enforcement (Open vs Private boundary) | done 2026-07-01 |
| 7 | Sub-agent review loop (worker → reviewer → governor) | done 2026-07-01 |
| 8 | Memory + skill loop (SQLite FTS5 + Obsidian brain) | done 2026-07-01 |
| 9 | Dockerize + portability | done 2026-07-02 |

## Target Architecture (PRD §4, §9)

Python FastAPI backend + Ollama conversational core + LiteLLM routing + ChromaDB memory + SQLite state.
Open WebUI and n8n retained as client/orchestrator. PowerShell scripts wrapped as callable registry tools.

## Discipline Rule (PRD §10)

Every artifact must RUN, not describe. New standards, policy, or doctrine documents do not count as done. Before declaring any phase done, apply the anti-drift checklist in PRD.md §10.

## What NOT To Do

- Do not retire the PS webhook server (port 8788) until FastAPI is confirmed live in browser UI
- Do not modify PDA-Backups/, Legacy_Docs/, .env, or any file in the CLAUDE.md DO NOT TOUCH list
- Do not run /om-vault-upgrade against this repo
- Do not add features or abstractions beyond the current step's DoD
