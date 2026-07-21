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
**DONE 2026-07-20** — whole-branch review passed with fixes (see below). Step 11 starting now.)

### 2026-07-20 · Step 10 fully closed — whole-branch review + Docker wiring fix

Resumed the 2026-07-08 pause: `step-10-skills` already had `step-9-dockerize`'s Steps 12/13
merged in (`a4a5ca0`). Ran the deferred final whole-branch review
(`superpowers:requesting-code-review`, range `a0b0ad5..a4a5ca0`) — verified independently
(not taken on faith): the earlier symlink-exfiltration fix actually blocks the attack,
the Step 12/13 merge conflict resolution in `main.py` is correct (`session_id` traced by
hand through every path), and 120/120 tests pass.

**One Critical finding, fixed same session:** the skills subsystem was inert under
`docker compose up` — `Skills/` and `Config/skills_registry.yaml` were never copied into
the `cooper-core` image or bind-mounted, so `GET /skills` was permanently empty and
`import_skill` wrote into the ephemeral container layer (lost on restart). This slipped
through per-task review because Step 10's live verification used the bare-metal
`.venv-win` path, not Docker. Fixed (commit `f18b6c1`): Dockerfile now seeds `Skills/` +
the manifest, both compose files bind-mount them read-write (same pattern as the existing
`Obsidian Vault/brain` mount). **Verified live in real containers**, not just compose
config parsing: built both open and private `cooper-core` images, confirmed
`GET /skills` returns the seed skill through the open container and correctly returns
empty for private (skill is scoped `workshop: open`). Also had to exclude
`cooper-core/venv` (a stray local venv, not `.venv`/`.venv-win`) from the Docker build
context — a broken symlink inside it was failing the build outright, unrelated to Skills
but blocking verification.

**Known, disclosed, deferred as follow-ups** (not blocking, real but lower-urgency):
`fetch_tap`'s 10MB cap only bounds the final `skills/<name>` subdir, not the full clone;
no cleanup of orphaned `Skills/_incoming/<name>` staging dirs on denial/expiry (and that
path isn't gitignored); minor prompt-ordering inconsistency between the blocking and
streaming chat paths' skill/recall context order.

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
| 10 | Governed skills subsystem (hash-pinned manifest) | BLOCKER — first | **DONE 2026-07-20** on `step-10-skills` (a0b0ad5..f18b6c1). Whole-branch review passed; Docker deployment gap found and fixed. |
| 11 | Self-improvement loop (draft → approve → promote) | after 10 | in progress — starting 2026-07-20 |
| 12 | Signal gateway (signal-cli-rest-api, Open only) | parallel worktree | done, merged 2026-07-08 (live phone test pending) |
| 13 | Session-bound approvals + install-cooper.sh | parallel worktree | done, merged 2026-07-08 |

### 2026-07-08 · Step 10 paused mid-session (all 6 tasks done, final review pending)

Session A (this thread) executed Step 10's plan via subagent-driven-development, Sonnet
throughout. All 6 tasks complete and individually reviewed (several needed one fix round
each — see `.superpowers/sdd/progress.md` for full detail). **Paused here at the user's
request before the Step 10 final whole-branch review and before starting Step 11.**

**To resume:**
1. `git checkout step-10-skills` (or re-enter its worktree if one was set up).
2. **Rebase/merge first** — `step-9-dockerize` moved forward while this session ran
   (Steps 12 + 13 both merged into it same-day). `step-10-skills` still branches from
   the OLD `step-9-dockerize` tip (`a0b0ad5`). Merge/rebase `step-9-dockerize`'s current
   tip into `step-10-skills` before the final review or before merging Step 10 back —
   otherwise Steps 12/13's work silently vanishes from Step 10's perspective on merge.
3. **Known git hygiene wrinkle**: commit `a4f672c` ("docs: record Step 13 completion")
   sits on `step-10-skills`' lineage but is NOT an ancestor of `step-9-dockerize`'s own
   Step 13 commits — a concurrent-session artifact (another session's doc-commit landed
   here because this repo checkout was shared, not worktree-isolated, at that moment).
   It's real, correct content (PROGRESS.md/Gotchas/Patterns Step 13 writeup) that just
   needs to end up on `step-9-dockerize` too — check whether the rebase naturally carries
   it over correctly or whether it needs a manual cherry-pick.
4. Dispatch the Step 10 final whole-branch review (`superpowers:requesting-code-review`'s
   template, most capable model, range after rebase) before touching Step 11.
5. Then start Step 11 per `Docs/superpowers/plans/2026-07-08-step-11-self-improvement-loop.md`.

**Carry forward, not yet actioned:** a real throwaway public GitHub repo
(`https://github.com/ThemisEidos/cooper-skill-tap-test`, created during Task 6's live
verification of the tap importer) needs manual deletion by the user — the `gh` token used
lacks `delete_repo` scope. Inert (README + one SKILL.md, self-labeled "safe to delete"),
no secrets.

**Notable findings from Step 10's review cycle** (full detail in the ledger): a Critical
security bug in the tap importer — `shutil.copytree`'s default symlink-dereferencing let
a malicious tap exfiltrate arbitrary local file content (`.env`, SSH keys) past the
human-visible approval preview — was caught and fixed (symlink rejection, name validation,
10MB size cap all added to `fetch_tap`). This was a bug in the plan's own given code, not
an implementer deviation — worth remembering when trusting "plan gives the code verbatim"
tasks: the plan author (a prior session) can introduce real bugs too, review catches them
the same as any other code.

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
