# North Star — COOPER Project Direction

> Updated 2026-08-24. Source of truth: PROGRESS.md + PRD.md.

## Current Position

**15a (native tool-calling dispatch) fully DoD-closed 2026-08-25 — browser click-through
verified on both stacks, a real governance bypass on Private found and fixed along the
way.** Shipped 2026-08-24 (see that entry below for the dispatch-shape detail). On
2026-08-25, with `claude-in-chrome` available for the first time across every 15a
session, checked Private Open WebUI's connections before testing and found **no
cooper-core connection existed at all** — instead a direct `https://api.openai.com/v1`
(live key) and a direct `http://private-ollama:11434`, both bypassing the approval gate,
registry, and audit log entirely on the one workshop meant to be local-only and
air-gapped. Confirmed live before touching anything (a dispatch-shaped turn ran with zero
requests reaching cooper-core's logs), then fixed with owner sign-off: deleted both
connections, wired the documented `http://cooper-core:8000/v1` with the real
`COOPER_API_KEYS` value (owner supplied it directly — `.env` is access-denied to Claude).
Re-ran click-through on both stacks, both fully governed round trips confirmed live in
browser: Private (`Test-Exec.ps1`, L4 halt → approve → executor output rendered) and Open
(`lite_llm_router`, L3 halt → approve → `2 + 2 equals 4.` rendered), each cross-checked
against `docker logs` to prove the request actually hit cooper-core. Open stack's own
stray `host.docker.internal:11434` Ollama connection was also resolved same-session —
checked the sibling `03_brain_bot` repo (owner's hypothesis it might belong there) and
found no reference to that host or to Open's ports anywhere in it; confirmed unrelated
and removed. Open's Open WebUI now carries exactly two connections: governed
`cooper-core:8000/v1` and the 2026-08-04 sanctioned OpenRouter path. Full detail:
PROGRESS.md's 2026-08-25 decision-log entry. No open items remain on 15a.
**Next up: slice 14a (Fabric pattern executor)**, a light revision on top of 15a's new
dispatch shape. **All five owner gates decided 2026-08-23** (G1: no inbound Open-drafted plans to Private; G2: brain stays
gpt-4o-mini; G3: session-plans amendment enacted, 15h unblocked; G4: SearXNG Open-only,
Private gets no web search; G5: spend guard enacted, $15 lifetime OpenRouter key cap live).
14f is pinned as a placeholder until the home-lab network exists. No governance blockers
remain on any slice.

**All 9 steps COMPLETE (2026-07-02).** Step 9 shipped and DoD-verified live: the private
compose stack (`PDA-Runtime/docker-compose.private.yml`) brings cooper-core + Ollama +
Open WebUI fully online — health, auth, classify, dispatch→approve→execute all verified
in-container. Spec §4 (drop `internal: true`) was re-reviewed and confirmed post-audit;
spec §8 lists the post-audit amendments that were applied. GPU reservation on
private-ollama is required for usable inference (~90 s/turn warm vs >5 min on CPU).
The `.venv-win` dev-mode path (`Start-CooperCore.ps1`) remains the faster daily driver
(~30 s/turn via Windows-host Ollama).

**`step-9-dockerize` merged into `main` 2026-07-21** (clean fast-forward — `main` was a direct
ancestor, no conflicts). Stale branches (`step-10-skills`, two `codex/nightly-task-002-*`,
`audit-remediation`) cleaned up, local and remote.

**"Arm COOPER with real tools + skills," 2026-07-21/22 — all 13 registry executor_types now wired,
both workshops.** User redefined "done" against Hermes Agent as the benchmark. Full detail in
PROGRESS.md; highlights: found and fixed a real pre-existing command-injection vulnerability in
two now-deleted n8n workflow exports (Fable 5 plan review caught it, verified nothing was
live-exploitable via the owner's own n8n UI); found and fixed two real integration bugs live
(llm_api passing tool-framing text as the actual prompt; workflow_engine sending the wrong JSON
key for n8n's own routing logic); corrected an over-broad Fable finding against the actual
governance doc (Level 2 explicitly permits "create or update," not just create — Level 5's
overwrite concern is protected data, not routine tool output). Skills/_drafts/ now holds several
real candidate skills from the session's own dispatches, ready for the owner's review/promotion —
curation (Batch 7) is the next open item.

**Open Workshop capability-gap audit + closure, 2026-07-21** — see dated entry below. Found
Open had never been live-verified for several of its documented capabilities (only ever proven
against Private's Ollama backend); closed that gap, found and fixed a real regression along the
way (approval phrase matching), and changed COOPER's baseline humor to 55.

Next horizon: Batch 8 skill curation when drafts accumulate (now gated for quality);
decide grandfather-vs-archive for the 12 non-compliant v1 evidence records in
`State/Workflow_Evidence/`; investigate the dead DNS listener on 127.0.0.1:53 (owner).
Signal gateway (Step 12) deferred to "far later" by owner direction 2026-08-02 —
needs a real registered phone.

**Open WebUI browser click-through is DONE as of 2026-08-04** — no longer owner-pending.
See the dated entry below.

### 2026-08-18 · Step 15 scoped: max every metric, planner–executor, council

Full detail: PROGRESS.md's 2026-08-18 decision-log entry + the Step 15 spec. Highlights:

- **9-metric harness rubric defined; COOPER 32/45 vs Hermes Agent 29/45** — mirror-image
  profiles. Standing constraint carried into every slice: never spend M4 (governance) or
  M7 (audit) to buy another metric — that trade is Hermes's profile, declining it is ours.
- **Architecture:** big brain drafts plan+envelope → council critiques (dissents attached)
  → owner approves → hash-pinned → cheap executor runs inside it. Councils at planning +
  final review only; mid-run deviation prevention stays deterministic (envelope/quota/
  exception queue in code). Rejected and recorded so they stay rejected: mid-run council
  checkpoints, runtime LLM-picks-the-LLM routing, `:free`-model fan-out for quota.
- **15a first:** native tool-calling dispatch. gemma4 has native Ollama tool support
  (~86% claimed), so Private needs no model swap; both 2026-08-04 gotchas (unreachable
  `lite_llm_router`, note-writer literal syntax) die as a class. The written 14a plan gets
  a light revision on top.
- **Private model strategy:** quantize-down rejected (12b already Q4_K_M; Q3/Q2 unusable).
  Role split instead — `gemma4:e4b` (~5GB, fully GPU-resident) for high-frequency roles,
  12b on-demand for judgment. E4B benchmark (tool-call accuracy, t/s, 100% GPU) is 15c's
  entry gate and caps Private's M6 score.
- **COOPER Cockpit (15i), owner-added same day:** custom UI to replace Open WebUI —
  chat with native approve/deny buttons (retires the approval-phrase-regex fragility
  class), a graph view of the Obsidian brain, workflow monitor + exception-queue drain,
  M1–M9 metrics dashboard, settings. Strictly a client of the same gated API — never a
  bypass. Incremental delivery; Open WebUI retires only after chat parity is
  browser-verified (same rule that governed the v1 PS-webhook retirement).
- **Owner gates: all five decided 2026-08-23** — G1 no inbound plans to Private; G2 keep
  gpt-4o-mini; G3 session-plans yes; G4 SearXNG Open-only (revisitable); G5 spend guard
  yes. 14f pinned until the home-lab network exists.

### 2026-08-04 · Browser path proven; OpenRouter added as a parallel ungoverned path

Owner-driven session, no roadmap step. Full detail in PROGRESS.md's 2026-08-04 entry.

- **The browser path is verified end to end** — Open WebUI → cooper-core → LiteLLM → cloud →
  browser, on a real turn, with the promoted `run-status-summary` skill matching live. This
  had been honestly flagged "not done, not claimed" since 2026-07-08 (Steps 11/12/13 all
  lacked a browser). It should stop appearing as an open item.
- **The bug that hid it:** an OpenAI key pasted where the COOPER key belongs. Open WebUI
  renders an empty dropdown and no error whatsoever; the 401 exists only in cooper-core's
  log. Worth internalizing — "empty dropdown" reads as "server down" and is not.
- **OpenRouter** was already keyed and working through LiteLLM but exposed nowhere. Owner
  chose a direct second Open WebUI connection (ungoverned, deliberate — governance tradeoff
  stated and accepted) over routing it behind COOPER. COOPER's brain stays gpt-4o-mini by
  explicit owner decision. No code changed.
- **Two real paper-cuts logged, neither fixed** (out of scope, see Gotchas 2026-08-04): the
  note writer demands a literal syntax the registry doesn't advertise and only fails AFTER
  an approval is spent; and `lite_llm_router` could not be dispatched at all — three
  phrasings all classified as `answer`, COOPER answering the payload itself. The latter is
  the more serious of the two: a registered L3 tool that natural language cannot reach.
- **Draft-offer notice still unobserved, but no longer mysterious** — `_post_dispatch` ran
  (memory + skill stats prove it); the drafter correctly judged both dispatches non-reusable
  per its own 2026-08-02 gate. Needs a dispatch with a genuinely repeatable procedure.

### 2026-08-02 · Working-product session: Batch 7, launchers, Step 10 follow-ups, 4 hardening features

Owner direction: Signal is far-later; focus is a working product on this machine. Everything
below is committed, deployed to both stacks, and live-verified (suite 173→206, all green;
full detail in PROGRESS.md's three dated 2026-08-02 entries):
- **Batch 7 curation done** — promoted `run-registry-inspector` + `run-status-summary` via
  the live governed workflow; rejected 5 test-residue drafts.
- **Desktop launcher buttons** — `launch-cooper.sh --install-desktop` gives dock-pinnable
  "COOPER Private"/"COOPER Open" entries (up → health-wait → browser); the open-webui
  external-volume gotcha is now fixed inside install-cooper.sh.
- **Step 10 deferred follow-ups closed** — whole-clone 50MB cap in fetch_tap, staged-import
  cleanup on deny + 1h orphan sweep (+`Skills/_incoming/` gitignored), blocking/streaming
  prompt-order aligned (recall before skill).
- **Semantic skill matching** — embeddings per workshop backend (nomic-embed-text local /
  text-embedding-3-small via LiteLLM), per-model calibrated thresholds, sqlite cache,
  keyword fallback. Live-proven with a zero-keyword-overlap activation.
- **Post-dispatch is background** — memory write + skill draft no longer block the reply
  (3.3s live dispatch); draft offers arrive as next-turn notices (notice path unit-tested,
  not yet observed live — needs a novel non-test dispatch).
- **Draft gate** — test-style dispatches never reach the drafting LLM; drafts must
  self-declare `reusable`.
- **Evidence validator** — `evidence.py` + all 15 fixtures running; found all 12 real
  `State/Workflow_Evidence/` records non-compliant (v1-era, pre-linkage) — left as history.
- **Machine gotcha fixed** — git clone hung machine-wide (hostname missing from /etc/hosts
  + dead 127.0.0.1:53 resolver upstream); owner added `127.0.1.1 pop-os`, suite made
  hermetic via `cooper-core/conftest.py` git-ident pins. See Gotchas.md 2026-08-02.

### 2026-07-21 · Open Workshop capability gap closed; approval-regex regression found + fixed

The prior session's audit found Open Workshop (`pda-open-cooper-core`, port 8001, cloud backend)
had never been live-verified for approval+execution, sub-agent review, memory/skill recall, or
the self-improvement loop — all previously proven only against Private's local Ollama. User had
real tasks queued for Open and wanted confirmation it actually works first. Full detail in
`PROGRESS.md`'s decision log; highlights:

- All of steps 4/5/6/7/8/11 replayed live against the running Open container and confirmed
  working, including Step 6's previously-unproven "Open allows an approved cloud call" half
  (proved via `lite_llm_router`, one of the two `_CLOUD_EXECUTORS` types Private blocks outright).
- **Real regression found, not a known limitation:** `approval.py`'s approve/deny regexes were
  full-match-only against a single token — `"yes, go ahead"` and `"no, cancel that"`, the *exact*
  phrases this file's own history records as live-verified, silently stopped matching (collateral
  damage from an earlier "yes, but first…" hedge-rejection fix). No error surfaced — the message
  just got reclassified as a new turn. Fixed to allow chained approve/deny tokens; two regression
  tests added. This is exactly the kind of gap a "presumed fine, never re-verified" capability can
  hide — worth remembering when trusting old verification evidence at face value.
- Promoted a real skill (`run-test-exec`) through the legitimate draft→promote workflow directly
  on the live production container (both stacks were already running — no isolated test instance
  this time, unlike Step 10/11's original port-8010 approach) — **kept it**, not reverted, since
  it's genuinely useful, not test residue.
- Private regression check: pytest 137/139 (2 pre-existing failures, environmental — Windows
  socket-provider error in a subprocess-isolation test, and a likely Windows-vs-Linux symlink
  semantics gap in the security test — neither touches files edited this session); live
  dispatch→approve→execute round trip confirmed via direct DB read after Ollama (CPU-only, no GPU
  engaged this session) took several minutes — slow, not broken.
- Changed COOPER's baseline humor 35→55 (shared Modelfile, both workshops) per explicit request.
- **Gotcha confirmed:** the Modelfile and `general_tool_registry.yaml` are baked into the
  `cooper-core` image at build time, not bind-mounted (only `Obsidian Vault/brain`, `Skills/`, and
  `skills_registry.yaml` are) — any edit needs an image rebuild + `--force-recreate`, not just a
  container restart.
- Not attempted (explicitly out of scope): fixing known limitations (executor stubs beyond
  PowerShell, keyword-only tool/skill matching) and Step 12's live Signal-phone verification.

### 2026-07-21 · Step 11 complete — self-improvement loop (draft → approve → promote)

Built on `step-11-proposer` (git worktree at `.worktrees/step-11-proposer`, off
`step-9-dockerize`) via subagent-driven-development, 4 tasks — full detail in
`PROGRESS.md`'s decision log and `.superpowers/sdd/progress.md` (worktree removed after
merge; ledger history survives in git). Highlights for next session:
- `proposer.py`'s `draft_skill()` drafts a candidate SKILL.md into `Skills/_drafts/<name>/`
  after any successful dispatch; `promote_skill` (approval-gated, permission_level 2)
  activates one. `skillmd_stats` counts activations.
- **Whole-branch review caught a cross-task bug invisible to any single task's review:**
  `draft_skill()` took a `tool` param but never used it, so approving a `promote_skill` or
  `skill_import` dispatch (itself a passing run) immediately drafted a self-referential
  meta-skill about promoting/importing. Fixed with an early-return guard
  (`_UNDRAFTABLE_EXECUTOR_TYPES`) before any LLM call — worth remembering: task-level
  reviews catch what's wrong within a task, but only a whole-branch pass catches what
  happens when independently-correct tasks compose.
- **Live-verified against a real running server**, not just curl-tested-once: bare-metal
  on port 8010 (deliberately not 8000, to avoid disturbing the already-running dev stack),
  this branch's own code, real Windows-host Ollama. Full round trip — dispatch → draft
  offer → promote → approve → register → `GET /skills` shows `ok` → conversational use →
  activation count incremented — all passed first attempt. Test artifacts (the promoted
  skill + manifest entry) were reverted afterward; they were proof-of-pipeline, not
  intended permanent content.
- **Known, disclosed, not done:** Open WebUI browser click-through (no browser-automation
  tool in this environment). Reviewer judged this doesn't block merge-readiness since the
  offer line is a plain string appended server-side to the same bytes the browser renders,
  already covered by the API-level check — but flag it if a browser becomes available.
- **Docker-deployment gap check: done, confirmed working, with a useful real-world fail-safe
  demonstration along the way.** Rebuilt and recreated `pda-private-cooper-core` with Step 11's
  code, then re-ran the full DoD sequence through the real container. The natural-language
  dispatch call ("run Test-Exec.ps1" → approve) took over 20 minutes and the draft never
  appeared — `docker logs` showed `[!!] proposer.draft_skill failed (non-fatal): ` (empty
  message). Root cause: `decision.py`'s httpx clients use a 120s timeout, and this one request
  now chains THREE sequential LLM calls (review → archivist.remember → proposer.draft_skill,
  Task 2's flagged latency concern made concrete) on a CPU-only Dockerized Ollama already under
  sustained 200-270% CPU load from the first two calls — the third timed out. **This is exactly
  the fail-safe design working as intended under real duress**: the user still got their correct
  script output with no error surfaced, only the (optional) draft silently didn't happen.
  Confirmed the actual open question — does the `Skills/_drafts`/`Skills/learned` write path
  work through Docker's bind mount — directly and fast via `docker exec ... python -c` calling
  `proposer.draft_skill()` with a fake `extract_fn` (bypassing the slow real LLM call): draft
  written inside the container, confirmed visible on the HOST filesystem (proves the bind mount
  is genuinely bidirectional, not just container-writable); then `skills.register_promotion()`
  via the same exec path moved it to `Skills/learned/` and appended the manifest entry; then the
  real running API's `GET /skills` confirmed status `"ok"`. No Docker-deployment gap exists for
  Step 11 — Step 10's existing `Skills/` + manifest bind mount already covers it fully. Test
  artifacts reverted afterward (the `Skills/learned/` entry was container-created as root and
  needed removal from the Windows side, not WSL, due to a drvfs permission quirk — worth
  remembering if cleaning up container-written files under `/mnt/d` again).

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
| 10 | Governed skills subsystem (hash-pinned manifest) | BLOCKER — first | **DONE 2026-07-20** on `step-10-skills` (a0b0ad5..f18b6c1), merged into `step-9-dockerize`. Whole-branch review passed; Docker deployment gap found and fixed. |
| 11 | Self-improvement loop (draft → approve → promote) | after 10 | **DONE 2026-07-21** on `step-11-proposer` (worktree, 051df4c..dca241f), merged into `step-9-dockerize`. Whole-branch review caught and fixed a cross-task self-referential-draft bug; live-verified end-to-end. |
| 12 | Signal gateway (signal-cli-rest-api, Open only) | parallel worktree | done, merged 2026-07-08 (live phone test pending) |
| 13 | Session-bound approvals + install-cooper.sh | parallel worktree | done, merged 2026-07-08 |

**Carry forward, not yet actioned:** a real throwaway public GitHub repo
(`https://github.com/ThemisEidos/cooper-skill-tap-test`, created during Task 6's live
verification of the tap importer) needs manual deletion by the user — the `gh` token used
lacks `delete_repo` scope. Inert (README + one SKILL.md, self-labeled "safe to delete"),
no secrets. User has acknowledged, will delete when they have time.

**Notable findings from Step 10's review cycle** (full detail in the ledger): a Critical
security bug in the tap importer — `shutil.copytree`'s default symlink-dereferencing let
a malicious tap exfiltrate arbitrary local file content (`.env`, SSH keys) past the
human-visible approval preview — was caught and fixed (symlink rejection, name validation,
10MB size cap all added to `fetch_tap`). This was a bug in the plan's own given code, not
an implementer deviation — worth remembering when trusting "plan gives the code verbatim"
tasks: the plan author (a prior session) can introduce real bugs too, review catches them
the same as any other code. A second, similar lesson from the same day: the plan's own
Docker deployment wiring was also incomplete (see the 2026-07-20 entry above) — treat a
plan's infrastructure/deployment sections with the same scrutiny as its logic.

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
