# PROGRESS.md — COOPER Build State

> Living document. Update every session. Full scope plan: `PRD.md`. Operating manual: `CLAUDE.md`.
> If `PROGRESS.md` is not current, the session is not done.

---

## Roadmap — 9 steps (PRD §5)

- [x] **Step 1 — Conversational runtime.** FastAPI service + one chat endpoint to Ollama. DoD: send COOPER a message and he answers conversationally, in-character, in the web UI. ✓ 2026-06-28
- [x] **Step 2 — Decision layer.** COOPER classifies each turn: answer / clarify / dispatch. DoD: COOPER asks a clarifying question on a vague request and answers directly on a simple one — observably, at runtime. ✓ 2026-06-28, re-verified 2026-06-29
- [x] **Step 3 — Registry reader + router (Quartermaster).** Load the real tool registry; select a capability by workshop + role. DoD: "what tools are available?" returns actual registry contents for the active workshop. ✓ 2026-07-01
- [x] **Step 4 — Approval gate (Safety Officer).** Enforce the permission ladder in code. DoD: a Level 2+ action visibly halts and waits for approval before proceeding; Level 0/1 auto-run. ✓ 2026-07-01
- [x] **Step 5 — Execution gateway (Workbench) + one real tool.** Wire one PowerShell/CLI tool end-to-end. DoD: COOPER executes a real tool after approval and shows the result + artifact path. ✓ 2026-07-01
- [x] **Step 6 — Workshop enforcement.** Open vs Private boundary enforced at the routing layer. DoD: Private Workshop refuses a cloud call at runtime; Open Workshop allows an approved one. ✓ 2026-07-01
- [x] **Step 7 — Sub-agent review loop.** Worker → reviewer → governor. DoD: a dispatched task is checked by a reviewer agent before results reach you. ✓ 2026-07-01
- [x] **Step 8 — Memory + skill loop.** ChromaDB + Obsidian brain read each turn; successful tasks abstracted into scored, versioned skills. DoD: COOPER recalls a prior decision and reuses a saved skill at runtime. ✓ 2026-07-01
- [x] **Step 9 — Dockerize + portability.** DoD: `docker compose up` brings COOPER fully online on a fresh checkout. ✓ 2026-07-02

**Current step: all 9 steps complete (2026-07-02)**

## Roadmap — Steps 10-13 (COOPER × Hermes merge, post-PRD, scoped 2026-07-08)

Native port of Hermes Agent's capability patterns into `cooper-core`, SKILL.md-format-compatible,
zero vendored code. Spec: `Docs/superpowers/specs/2026-07-08-cooper-hermes-merge-design.md`.
Plans: `Docs/superpowers/plans/2026-07-08-step-1{0,1,2,3}-*.md` (commit 50de439).

- [x] **Step 10 — Governed skills subsystem (hash-pinned manifest).** ✓ 2026-07-20. Built on
      `step-10-skills` via subagent-driven-development; whole-branch review found the skills
      subsystem was inert under `docker compose up` (Skills/ and the manifest never reached the
      container) — fixed and live-verified in real containers. Merged into `step-9-dockerize`.
- [x] **Step 11 — Self-improvement loop (draft → approve → promote).** ✓ 2026-07-21. See decision log.
- [x] **Step 12 — Signal gateway (signal-cli-rest-api, Open only).** Built in parallel worktree
      `step-12-gateway`; merged into `step-9-dockerize` 2026-07-08. Live Signal-phone verification
      not yet performed (needs a physical Signal-registered device).
- [x] **Step 13 — Session-bound approvals + install-cooper.sh.** ✓ 2026-07-08. See decision log.

---

## Roadmap — Steps 14–15 (Max-Metric Program, scoped 2026-08-04 + 2026-08-18)

Owner direction 2026-08-18: **max all nine harness metrics** (COOPER-Open to 45/45,
Private to its physical ceiling), **outperform other agentic harnesses — specifically
Hermes Agent** (29/45 on the same rubric) — and keep a running version operational
throughout: every slice ships alone and live. Specs:
`Docs/superpowers/specs/2026-08-04-step-14-autonomous-jobs-design.md` (approved) and
`Docs/superpowers/specs/2026-08-18-step-15-max-metrics-design.md` (approved direction;
governance gates G1–G5 open — see Blocked section).

Execution order: 15a → 14a(rev) → 15c → 14b → 15d → 15e → 14c(+15f-i) → 14d → 14e →
15f → 15g → 15h. 15b anytime; 14f pinned until the home-lab network exists (2026-08-23).

- [x] **15a — Native tool-calling dispatch** (M3→5; retires classifier dispatch; kills both 2026-08-04 gotchas as a class) — shipped 2026-08-24, live-verified both stacks (blocking + real SSE incl. preamble-then-dispatch), 3 post-review Importants closed in a fix-forward pass, itself reviewed clean (248/248). **Browser click-through per stack closed 2026-08-25** — see decision log; en route, found and fixed a real governance bypass on Private's Open WebUI (no cooper-core connection existed at all).
- [x] **14a — Fabric pattern executor** — shipped 2026-08-25, live-verified both stacks (blocking API + browser click-through, all 4 patterns reachable via native tool-calling). Revised plan (2026-08-04 original rewritten for 15a's args-based dispatch), 4 tasks + subagent-driven-development, whole-branch review found and fixed 1 Critical (`PDA-Fabric/` was gitignored and never committed — see decision log) + 1 Important (workshop routing failed open toward cloud). Separate, unfixed finding: an intermittent approval-ticket hijack via Open WebUI's own background calls — see Gotchas 2026-08-25, flagged for owner decision, not in scope for this slice.
- [ ] **15b — Zero-touch Open WebUI provisioning** (M9→5; independent, anytime)
- [x] **15c — Per-role model routing** (implements `Scripts/PDA_ModelRouting.json`; LiteLLM fallback pools; Private E4B/12B role split — E4B benchmark is the entry gate) ✓ 2026-08-30
- [x] **14b — Jobs harness + link-checker** (M2→3) ✓ mechanism shipped, live-verified,
  inert 2026-08-30 — `approved: false`, n8n scheduler workflow built but not imported
  (manual import still needed). Owner activation steps + the multi-day DoD clock: see
  decision log.
- [x] **15d — Council subsystem** (M6→5; planning-time panel + tiered final review, verdicts in evidence) ✓ 2026-08-31
- [ ] **15e — Planner–executor** (M2→4; big brain drafts envelopes, cheap model executes)
- [ ] **14c — SearXNG + web_search + PII job** (ships WITH 15f's injection canaries, not before)
- [ ] **14d — Bounded loop + opt-out documenter job**
- [ ] **14e — Repo steward, draft-and-notify**
- [ ] **15f — Robustness: retry policy implemented, chaos tests** (M8→5)
- [ ] **15g — Governed learning breadth** (M5→5; prompt-diff self-optimization, outcome-weighted skill scores)
- [ ] **15h — Session plans** (M2→5; gated on G3)
- [ ] **15i — COOPER Cockpit: custom UI** (chat with native approve/deny buttons, Obsidian-brain graph view, workflow monitor, metrics dashboard, settings; incremental — monitor page after 14b, dashboard after 15d; Open WebUI retires only after Cockpit chat parity is browser-verified)
- [ ] **14f — Network review design** (pinned 2026-08-23: placeholder until the home-lab network is built; integrate COOPER when that project starts)
- [ ] **MCP integration — backlogged 2026-08-25, not yet slotted to a letter.** Owner confirmed
  this needs addressing at some point, scope/timing undecided. Not a new idea: three
  candidates have sat at `Status: Evaluating` in `Docs/Ecosystem_Change_Backlog.md` since
  2026-06-24 — **CHG-005** (expanded MCP registry, ROI 9/10), **CHG-007** (Playwright MCP
  for browser automation, ROI 9/10), **CHG-008** (Perplexity MCP for research, ROI 8/10) —
  none picked up by any of the ~15 roadmap slices scoped since. Architecture docs
  (`COOPER-Agent-Routing-Architecture.md`, `COOPER-Agent-Profiles.md`) already list "MCP
  tools" as an approved-in-principle future tool class, bounded and auditable. Cheapest
  integration shape discussed: one generic `mcp_tool`-style executor acting as an MCP
  client (stdio/SSE), with COOPER's own registry YAML still owning
  `workshop`/`permission_level`/`approval_required` per mapped tool — the MCP server itself
  has no concept of COOPER's approval gate, so the boundary has to hold entirely on
  COOPER's side, before the call. When scheduled: read the full CHG-005/007/008 entries,
  pick a first candidate, and confirm the bridge-executor design before building.

---

## What actually runs today

*Updated 2026-07-01 after Step 5 (Workbench) implementation and verification.*

### Confirmed running end-to-end

- `docker compose -f PDA-Runtime/docker-compose.yml up -d` starts Open WebUI (3000), n8n (5678), LiteLLM (4000).
- `docker compose -f PDA-Runtime/docker-compose.private.yml up -d` starts private Ollama + private Open WebUI (127.0.0.1:3001).
- LiteLLM model aliasing works per `litellm/litellm_config.yaml`.
- **`cooper-core/main.py` FastAPI backend** runs at port 8000. Verified 2026-06-30:
  - `GET /health` → `{"status":"ok","workshop":"private","backend":"ollama","model":"gemma4:12b","classifier":"gemma4:12b"}` ✓
  - `POST /chat {"message":"hey how are you"}` → `{decision:"answer"}`, in-character reply ✓
  - `POST /chat {"message":"sort it out"}` → `{decision:"clarify"}`, single clarifying question ✓
  - `POST /chat {"message":"archive last weeks logs"}` → `{decision:"dispatch"}`, stub returned, nothing executes ✓
  - `POST /v1/chat/completions` (Open WebUI path) → same routing; "sort it out" returns clarifying question ✓
- **Decision layer (`cooper-core/decision.py`):** classifier uses `gemma4:12b` at temperature=0 with JSON-schema-constrained output, `think:false` to suppress extended reasoning (~53s per call without it). Turns classified as `answer`/`clarify`/`dispatch`. Dispatch path calls Quartermaster tool selector. Falls back to `answer` on any error.
- **Quartermaster registry (`cooper-core/registry.py`).** Verified 2026-07-01:
  - `GET /tools` → `{"workshop":"private","count":7,"tools":[...]}` — full private registry from YAML ✓
  - `POST /chat {"message":"what tools are available?"}` → formatted 7-tool listing, `decision:"answer"`, `reason:"registry query answered directly by Quartermaster"` — no LLM call ✓
- **Workbench execution gateway (`cooper-core/executor.py`).** Verified 2026-07-01:
  - `POST /chat {"message":"run Test-Exec.ps1"}` → `"Halt — PowerShell Private Runner [L4]..."`, `decision:"dispatch"` ✓
  - `POST /chat {"message":"yes, go ahead"}` → `"[Test-Exec.ps1 — OK]\nCOOPER Workbench execution check -- OK\nTimestamp : 2026-07-01 10:38:12\nHost : ID6"`, `decision:"answer"`, `reason:"approval gate resolved"` ✓
  - `POST /chat {"message":"run NotARealScript.ps1"}` → halt → approve → `"Workbench: no .ps1 script path found..."` (graceful, not a crash) ✓
- **Safety Officer approval gate (`cooper-core/approval.py`).** Verified 2026-07-01:
  - `POST /chat {"message":"write a note to the restricted dmz workspace"}` → `"Halt — Restricted DMZ Writer [Restricted DMZ Workspace, permission level 2] requires approval before it can proceed. Reply 'approve' or 'deny'."`, `decision:"dispatch"` ✓
  - `GET /pending` → `{"workshop":"private","pending":{"id":"a3a1ced4","tool":"Restricted DMZ Writer","permission_level":2,"requested_message":"...","age_seconds":5.7}}` ✓
  - `POST /chat {"message":"yes, go ahead"}` → `"Approved: Restricted DMZ Writer [permission level 2]. Execution gateway is not wired yet (step 5) — nothing has actually run."`, `decision:"answer"`, `reason:"approval gate resolved"` ✓
  - `GET /pending` after approval → `{"workshop":"private","pending":null}` ✓
  - Deny path: `POST /chat {"message":"no, cancel that"}` after L2 trigger → `"Cancelled. Restricted DMZ Writer will not run."`, ticket cleared ✓
  - `POST /chat {"message":"run a status summary"}` → `"Acknowledged. Auto-running Status Summary [permission level 0] — no approval required. Execution gateway is not wired yet (step 5) — nothing has actually run."`, `decision:"dispatch"` ✓
- **COOPER model in Ollama:** `COOPER:latest` built from `Models/cooper-personality/Modelfile` (gemma4:12b base).
- **Open WebUI wired to COOPER Core:** connection added manually via Admin Panel → Connections (`http://host.docker.internal:8000/v1`, key `cooper-local`).
- **`cooper-core/Start-CooperCore.ps1`:** accepts `-Workshop private|open` (default `private`). Uses `ProcessStartInfo` + cmd.exe wrapper to correctly inject the `WORKSHOP` env var into the child process. Run from WSL2 with: `powershell.exe -ExecutionPolicy Bypass -File "D:\D_Projects\01_AI_Ecosystem\cooper-core\Start-CooperCore.ps1" -Workshop private`.
- **Workshop enforcer (`cooper-core/workshop.py`).** Verified 2026-07-01:
  - `GET /workshop` → `{"workshop":"private","backend":"ollama","model":"gemma4:12b","boundary":"enforced","violation":null}` ✓
  - `POST /chat {"message":"run Test-Exec.ps1"}` → halt [L4], no workshop violation (correct — private tool in private workshop) ✓
  - Python unit checks: `private+ollama` passes, `private+openai` blocked, `open tool in private` blocked, `cloud executor (browser) in private` blocked ✓
- **Sub-agent Reviewer (`cooper-core/review.py`).** Worker (executor) → Reviewer (LLM verdict, `CLASSIFIER_MODEL`, JSON-schema pass/flag, think:false) → Governor (`govern()` — deterministic pass-through or flag banner). Wired into `_execute()` in `main.py`, between the Workbench run and the reply reaching the user. Fails open (pass) on reviewer error so a broken reviewer never blocks a legitimate result. Verified live 2026-07-01:
  - `POST /chat {"message":"run Test-Exec.ps1"}` → approve → `"[Test-Exec.ps1 — OK]\nCOOPER Workbench execution check -- OK\r\nTimestamp : 2026-07-01 20:06:28\r\nHost      : ID6"` — clean pass-through, no reviewer banner ✓
  - `POST /chat {"message":"run NotARealScript.ps1"}` → approve → `"[Reviewer flagged this result — script not found]\n\nWorkbench: no .ps1 script path found in request..."` — reviewer caught the failed dispatch before it reached the user ✓
- **Archivist memory + skill loop (`cooper-core/archivist.py`).** Verified live 2026-07-01:
  - Skill reuse: `POST /chat {"message":"run Test-Exec.ps1"}` → approve → `POST /chat {"message":"run Test-Exec.ps1"}` (second dispatch) → `"Halt — PowerShell Private Runner [Local Automation, permission level 4] requires approval before it can proceed (matches a proven skill — 1 successful run, 100% trust). Reply 'approve' or 'deny'."` — skill scored and reused at runtime on the very next dispatch ✓ (approved again afterward to leave the system clean)
  - Decision recall: `POST /chat {"message":"have we run Test-Exec.ps1 before, what happened?"}` → `{"reply":"Yes. We executed \`Test-Exec.ps1\` on host ID6.\n\n**Result:** Success. It confirmed the COOPER Workbench execution check is functional.\n\n**Contextual Note:** I recommend using this script over \`Test-PDAStack.ps1\`, as the latter will hang for 60 seconds and fail if Docker is not active. \`Test-Exec.ps1\` is self-contained and provides a faster exit.","decision":"answer","reason":"information request"}` — correctly recalls the prior successful run from the `decisions` table, not a generic non-answer ✓
  - No tuning of `_fts_query()` or `_EXTRACT_SYSTEM` was needed — both DoD scenarios passed on the first live attempt.

### Not working / only documented

- **Open WebUI browser confirmation** — needed as final visual sign-off for step 2 DoD.
- **Only `executor_type: powershell` is wired** — all other types (`python`, `browser`, `llm_api`, `note_editor`, `workflow_engine`, `cli_launcher`, `filesystem`, `local_llm`) return a stub. Add a handler in `executor.py` to extend coverage.
- **PowerShell tool selection requires explicit script filename** — "run the health check" won't match `Test-PDAStack.ps1`; user must say the `.ps1` filename. Keyword overlap only; no intent-to-filename mapping.
- **`Test-PDAStack.ps1` times out in 60s** — it requires Docker containers to be running. Use `Test-Exec.ps1` (added to Scripts/) for fast gateway verification.
- **"give me a status summary" classifies as `answer`** — the classifier treats it as an information request. Use "run a status summary" (explicit verb) to get a dispatch classification for L0 tools.
- **Approval gate is policy JSON only.** No code halts for human input.
- **No tool executes end-to-end through COOPER chat.**
- **Sub-agent review does not run.**
- **Memory is not read per-turn.** `State/COOPER_ProjectMemory.json` exists but nothing reads it per conversation.
- **ChromaDB is not deployed.**
- **Old PowerShell webhook server still in place** (untouched) — the raw TCP bridge at port 8788. Retire after FastAPI proves out in the browser UI.

---

## Decisions log

- **2026-06-28 · FastAPI runs on Windows, not WSL2** — Ollama binds to Windows loopback (`127.0.0.1:11434`). WSL2 cannot reach Windows loopback by default. Running FastAPI via Windows PowerShell (`.venv-win`) solves this without WSL2 restart. `C:\Users\earth\.wslconfig` written with `networkingMode=mirrored` for future sessions (takes effect after `wsl --shutdown`).
- **2026-06-28 · Model name is `COOPER` (created fresh), not `cooper-personality`** — An earlier run had created `cooper-personality:latest` from the same Modelfile. Created `COOPER:latest` using the same layers (fast — no re-download). The `main.py` default `COOPER_MODEL=COOPER` is now correct.
- **2026-06-28 · Open WebUI connected via `docker-compose.yml` env var, not a Pipe** — Added `OPENAI_API_BASE_URL=http://host.docker.internal:8000/v1` and `OPENAI_API_KEY=cooper-local` to the `open-webui` service. Cleaner than a Pipe: no Open WebUI code to maintain, standard OpenAI-compatible interface, COOPER model appears in the model dropdown automatically.
- **2026-06-28 · Old PowerShell bridge left in place** — `Scripts/Start-PDAWebhookServer.ps1` and all existing PS scripts untouched. Retire only after the FastAPI path is confirmed working in the browser UI.
- **2026-06-29 · Classifier model is `gemma4:12b`** — Health endpoint confirms `classifier: gemma4:12b` (not `gemma3:12b` as earlier docs stated). Model was updated at some point; PROGRESS.md now reflects reality.
- **2026-06-29 · WSL2 mirrored networking confirmed working** — `localhost:8000` reaches the Windows FastAPI server from WSL2 without any proxy. `~/.wslconfig` with `networkingMode=mirrored` is active.
- **2026-06-29 · Classifier prompt rewritten with few-shot examples** — `gemma4:12b` was ignoring the abstract rule "missing an exact path is NOT a reason to clarify" and returning `clarify` for "archive last week's logs". Replaced rule-list prompt with a compact few-shot prompt (10 labeled examples). Model now correctly dispatches named-noun imperatives regardless of path specificity.
- **2026-06-29 · Security hardening applied to `main.py` and `decision.py`** — Seven changes from a three-reviewer ECC code review: Bearer token auth (env-var `COOPER_API_KEY`, dev mode open if unset), message/history field validation (1–32k chars, 50-item history limit), 500-char history truncation before classifier input (prompt injection guard), role allowlist (`user`/`assistant` only), `/health` endpoint cleaned, 422 error responses on bad input.
- **2026-06-30 · Unicode crash on Windows startup fixed** — `main.py` lifespan used `⚠`/`✓` in print statements; Windows cp1252 can't encode them, crashing startup. Replaced with `[!!]`/`[ok]`.
- **2026-06-30 · `Start-CooperCore.ps1` overhauled for env var injection** — `Start-Process` doesn't reliably pass env vars to detached children on PS 5.1. Rewrote to use `ProcessStartInfo` via `[System.Diagnostics.Process]::Start()` with a cmd.exe wrapper (`set "WORKSHOP=..."`) to correctly set the env var without a trailing space (cmd.exe `set X=val && ...` includes the space in the value).
- **2026-07-01 · Step 8 full design written** — `Docs/superpowers/specs/2026-07-01-cooper-memory-skill-loop-design.md`. Archivist module (`cooper-core/archivist.py`, fifth pipeline role): deterministic FTS5 `recall()`, LLM-extraction `remember()` on reviewed dispatch success, trust-scored `skills` table, `decisions` audit trail, `brain_fts` read-only mirror of the Obsidian brain. No changes to `approval.py` security logic — purely additive.
- **2026-07-01 · Step 8 memory storage: SQLite FTS5 + Obsidian markdown, not ChromaDB** — PRD named ChromaDB, but research into the two comparable projects PRD itself cites (Hermes Agent, Agentic OS) showed neither uses a vector DB: Hermes's most advanced memory tier ("Holographic Memory") is SQLite + FTS5 + HRR algebra, fully local, no embedding model, no network call; Agentic OS pairs a markdown `brain/` folder (source of truth) with "Hermes SQLite FTS5" for the queryable layer. Broader 2026 guidance also favors "start with SQLite, add a vector DB only when scale demands it." Decision: `Obsidian Vault/brain/` markdown stays the durable, human-readable source of truth; a new SQLite DB in `cooper-core/` (FTS5-indexed) becomes the queryable decision/skill store — no ChromaDB, no new embedding model dependency. Schema will reserve a `hrr_vector BLOB NULL` column so Hermes-style holographic recall can be added later without a rewrite, deferred past Step 8's DoD since a tiny memory corpus doesn't yet benefit from fuzzy vector recall.
- **2026-06-30 · `WORKSHOP` env var now stripped in `main.py`** — cmd.exe `set WORKSHOP=private &&` adds a trailing space, so `"private " != "private"` and the server fell back to open/OpenAI. Added `.strip()` to `os.environ.get("WORKSHOP", "open").strip().lower()` as a defensive fix alongside the quoted `set "WORKSHOP=..."` in the launcher.
- **2026-06-30 · `think:false` added to all Ollama calls** — `gemma4:12b` runs extended reasoning by default, adding 40-53s per call (measured). With `think:false` in the payload, classifier calls drop to ~10s. Added to `_ollama_complete` and `_stream_ollama_chat` in `decision.py`.
- **2026-07-01 · `registry.py` added as Quartermaster (step 3)** — workshop-scoped YAML reader with mtime-based cache (edits to YAML take effect without server restart under `--reload`). `GET /tools` endpoint returns the live registry JSON. Registry-query detection (`is_registry_query()`) short-circuits LLM calls for "what tools are available?" style messages — answered instantly from the YAML. Tool selection is bag-of-words keyword-overlap only — known limitation to revisit if step 5 needs better intent matching.
- **2026-07-01 · `executor.py` added as Workbench gateway (step 5)** — PowerShell executor resolves `.ps1` filenames from user message against `Scripts/` on disk (no arbitrary paths, no path traversal via `relative_to()` guard). Uses `loop.run_in_executor()` + `subprocess.run` (thread pool) rather than `asyncio.create_subprocess_exec` — the asyncio subprocess protocol had empty-exception failures inside uvicorn's event loop on Windows. Tries `powershell.exe` first (always present), then `pwsh`. Hard timeout 60s, output capped 8 KB. `approval.py` refactored: `resolve()` replaced by `consume()` + `is_approved()` + `is_denied()` so `main.py` owns the execute-vs-cancel decision with the full ticket context. `_resolve_approval()` added to `main.py` as the approval-gate resolution path that calls `_execute()` rather than returning a stub. `Scripts/Test-Exec.ps1` added as a fast, self-contained execution verification script (no Docker required).
- **2026-07-01 · `approval.py` added as Safety Officer (step 4)** — L2+ (or any `approval_required: true` tool) halts with a single-use ticket and a 10-minute TTL. Approve/deny detected via regex short-circuit ahead of the classifier so "yes"/"no" replies aren't misclassified as new dispatch requests. Dispatch-reply construction moved out of `decision.py` into an async `dispatch_handler` callback owned by `main.py`, keeping `decision.py` registry/approval-agnostic. Approval state is in-memory and single-ticket-per-workshop — deliberate simplification for a single local user; will not survive a server restart and cannot handle concurrent pending actions.
- **2026-07-01 · `workshop.py` added as workshop enforcer (step 6)** — stateless enforcement layer with two functions: `check_backend(backend, workshop)` blocks Private Workshop + OpenAI backend combinations; `check_tool(tool, workshop)` blocks tools whose `workshop` field mismatches the active workshop, and blocks `_CLOUD_EXECUTORS = {browser, llm_api}` in Private Workshop regardless of registry settings. `check_backend` fires at startup (print-only, doesn't block server start) AND per-request in `_handle_dispatch` (returns conversational `WorkshopViolation` message, not HTTP 500). `GET /workshop` added for live boundary observability. Tool `workshop` field matched case-insensitively with " Workshop" suffix stripped — a tool with no `workshop` field passes the check (permissive default for PS-era tools not yet tagged).
- **2026-07-01 · Steps 1-5 code review — 4 findings fixed and verified live:**
  1. `decision.py route_turn()` — the `clarify` and `answer` branches (`_clarify()`, `generate_answer()`) had no error handling around the LLM call, unlike `_classify()` which already caught everything. A backend outage crashed `/chat` and `/v1/chat/completions` (non-streaming) with a raw 500; the streaming path (`_stream_sse`) was already resilient. Both branches now wrap the call in try/except and return `"[COOPER error: backend unavailable — {exc}]"` instead of raising. Verified by monkeypatching `_classify`/`_ollama_complete` to force each branch and confirmed a graceful reply instead of a traceback (`answer` branch and `clarify` branch both tested independently).
  2. `Obsidian Vault/brain/North Star.md` had drifted — still listed step 6 as CURRENT after step 6 shipped (commit `a592714`). Updated to step 7 CURRENT, matching this file and the git log.
  3. `GET /v1/models` was missing `dependencies=[Depends(_require_auth)]`, present on every other endpoint (`/chat`, `/tools`, `/pending`, `/workshop`, `/v1/chat/completions`). Added for consistency; no-op today since `COOPER_API_KEY` is unset (open/dev mode), and Open WebUI already sends its configured key on this connection once a key is set. Verified `/v1/models` still returns 200 after the change.
  4. `registry.py _load()` let `yaml.YAMLError` propagate uncaught on malformed registry YAML, bypassing the `RegistryError` wrapper every other registry failure path uses. Now caught and re-raised as `RegistryError`. Verified `/tools` still returns the 7-tool private registry unchanged after the fix.
- 2026-07-02 — Audit remediation (branch audit-remediation): auth required at startup
  (COOPER_API_KEY, default cooper-local via launcher); executor fail-closed
  allowed_scripts per registry tool; workshop enforcement fail-closed for untagged
  tools; approval approve/deny full-match only; archivist extract fail-safe +
  untrusted-marked recall context + thread-safe SQLite + 60s index debounce;
  LLM-backed tool selection with keyword fallback; CI workflow added; harness
  permissions moved to acceptEdits + deny list; ECC plugin trimmed to user-level
  keep-list. Live-verified: auth 401/200, allowlisted dispatch runs, unlisted
  script refused.
- 2026-07-02 — Step 9 (Dockerize) shipped and DoD-verified live: cooper-core +
  model-init containers added to docker-compose.private.yml; cooper-core reaches
  Ollama via container DNS. `pda-private-net` `internal: true` dropped (spec §4,
  confirmed post-audit — it blocked `ollama pull` AND silently disabled published
  ports). pwsh installed from GitHub release tarball (Microsoft apt repo signs
  SHA1, rejected by apt since 2026-02); COOPER_DB_PATH env override moves the
  memory DB to a named volume. GPU reservation added to private-ollama after CPU
  inference proved too slow (>5 min/turn; with RTX 3050 Ti partial offload:
  ~90 s/turn warm — functional, slower than Windows-host Ollama's ~30 s).
  In-container verification: health ok, 401 without key, chat classifies,
  /tools lists 7, /workshop enforced, dispatch→approve→Test-Exec.ps1 executes
  under Linux pwsh. Gotcha fixed en route: a dead uvicorn reloader left an
  orphaned Windows worker still serving :8000, so Docker's port publish silently
  didn't bind — early "container" checks were actually hitting the old Windows
  server (exposed by `Host : ID6` + skill history a fresh DB couldn't have).
- **2026-07-02 · First real front-door verification found `cooper-core` was never actually
  reachable through the UI** — every prior "live-verified" claim across all 9 steps was
  `curl` against a known endpoint with a Bearer token; nobody had opened Open WebUI and
  picked a model by name. When the user did, the "COOPER - Private" entry in the dropdown
  turned out to be a decoy: `litellm/litellm_config.yaml` had a `model_name: COOPER - Private`
  alias routing straight to raw `ollama/qwen2.5:7b` — no system prompt, no classifier,
  no approval gate, no registry, no memory, none of the 9-step pipeline. Open WebUI's
  SQLite-persisted Connections had a LiteLLM (port 4000) entry sitting alongside the
  correct `cooper-core` (port 8000) one, indistinguishable by name. Root cause fixed:
  removed the decoy alias from `litellm_config.yaml`. Discovered en route: `docker restart`
  served a stale cached copy of the edited config file (Docker Desktop's WSL2 bind-mount
  layer, same class of issue as the documented DrvFs `--reload` gotcha) — required
  `docker compose up -d --force-recreate` to actually pick up the change, verified via
  `docker exec ... cat /app/config.yaml`.
- **2026-07-02 · Renamed the Private Workshop model end-to-end: `gemma4:12b` → `COOPER-Private`**
  — user asked for the "gemma4:12b" showing in the Open WebUI dropdown to be identifiable
  as COOPER, not a raw base-model tag. Ollama tag renamed via `ollama cp gemma4:12b
  COOPER-Private` (old tag removed; blobs shared, no re-download). `cooper-core/main.py`:
  `COOPER_MODEL`/`CLASSIFIER_MODEL` private defaults now `COOPER-Private`; added a
  `DISPLAY_MODEL = f"COOPER-{WORKSHOP.capitalize()}"` constant used only in client-facing
  "model"/"id" fields (`/v1/models`, `/v1/chat/completions`, SSE chunks) — decoupled from
  `COOPER_MODEL` so Open Workshop's real backend model (`gpt-4o-mini`) never has to leak
  into the UI once that workshop is stood up. `/health` and `/workshop` still report the
  real backend tag on purpose (diagnostic, not branding). `docker-compose.private.yml`
  `model-init` now pulls `gemma4:12b` then `ollama cp`s it to `COOPER-Private` inside the
  container so the containerized stack matches (not yet live-tested in-container). Verified
  live in both `curl` and the Open WebUI browser after a stale-process restart (see gotcha
  below) — dropdown now shows `COOPER-Private` and answers in character.
- **2026-07-02 · `Start-CooperCore.ps1`'s "restart" didn't kill the old worker** — after the
  rename, `/health` kept reporting the old model even after re-running the launcher, and
  `/chat` 404'd against Ollama because the old tag no longer existed. The previous process
  (a zombie left over from an earlier session, `StartTime` ~90 min stale) was still holding
  port 8000 and never got killed by the script's port-clearing step. Fixed by manually
  `Get-Process python | Stop-Process -Force`, confirming the port was free via
  `Get-NetTCPConnection`, then relaunching. Same failure mode as the documented "dead
  uvicorn reloader" Docker gotcha, just on the bare-Windows dev path instead of in-container.
- **2026-07-07 · `COOPER-Private` rename verified in-container (was still open from 07-02)**
  — the running `pda-private-cooper-core` image was built 2026-07-02 18:39, *before* the
  rename commit (`9303387`, later that evening), so `/health` still reported
  `"model":"gemma4:12b"` despite the source and `model-init` container correctly using
  `COOPER-Private`. Rebuilt the image (`docker compose ... build cooper-core`) and
  `--force-recreate`d the container; `/health`, `/v1/models`, and `/chat` all then reported
  `COOPER-Private` correctly. Separately discovered the private stack's Open WebUI
  (`pda-private-open-webui`, port 3001) had an empty `user` table despite its volume dating
  to June 25 — nobody had ever completed the browser setup wizard for this instance; every
  prior "verification" of the private stack was `curl` directly against `cooper-core`,
  never through Open WebUI's own UI. Created the admin account and confirmed the model
  dropdown shows `COOPER-Private`. Confirmed by design: port 3001 (private) and port 3000
  (open) are fully separate Open WebUI containers/volumes/databases — LiteLLM and
  OpenRouter only exist in the Open Stack; the private stack showing only `COOPER-Private`
  is correct, not a misconfiguration.
- **2026-07-07 · Private-stack "not responding" traced to host memory pressure, not the model.**
  A `/chat` call was timing out (2-4+ min, ending in the classifier-error fallback), and
  `docker logs pda-private-ollama` showing only 7/49 GPU layers offloaded at 0.19 tok/s first
  looked like `gemma4:12b` not fitting the 4 GB GPU. User pushed back — cooper-private had
  worked fine earlier that same session — which prompted a proper recheck instead of accepting
  the first hypothesis. Actual cause: Windows had 1.2 GB free of 15.7 GB total, `vmmemWSL` alone
  used 6.5 GB, and two extra background Claude Code subagent processes plus a second full
  session were running concurrently in the same WSL2 VM, leaving no headroom for the 8.9 GB
  resident model — it was swapping to disk (196 GB block I/O), not compute-bound. See
  `Gotchas.md` 2026-07-07 entry. No code or config fix applied or needed; this was environmental
  contention, not a regression in the stack itself.
- **2026-07-07 · Open Workshop containerization complete and DoD-verified live.** Closes the gap
  Step 9 explicitly left open (Private Workshop only). `cooper-core` (WORKSHOP=open) now runs
  as a container in `docker-compose.yml` on host port 8001, routed through the existing
  `pda-litellm` gateway (`openai` alias) instead of talking to OpenAI directly, with a new
  `openai -> claude -> gemini` fallback chain. Six-task plan executed via subagent-driven
  development (`Docs/superpowers/plans/2026-07-07-open-workshop-containerization.md`); every
  task reviewed, one fix round on Task 1 (a subprocess-isolation test helper that broke under
  CI's actual repo-root pytest invocation). Live verification: `/health` and `/v1/models` both
  correct in-container; a real `/chat` call traversed cooper-core → LiteLLM → OpenAI end to
  end; the fallback chain was proven to actually engage (broke `OPENAI_API_KEY`, response came
  back from `claude-sonnet-4-5-20250929` instead, then restored and reconfirmed the primary
  path); Open WebUI's stale SQLite connection (pointed at a pre-existing
  `host.docker.internal:8000` from before `cooper-core` existed) was patched to `cooper-core:8000`
  and the dropdown/chat confirmed working live in the browser. Two real infrastructure bugs
  found and fixed along the way (not part of the original plan): LiteLLM's proxy needed
  `general_settings.allow_requests_on_db_unavailable: true` (no DB configured for this
  single-user deployment, otherwise intermittently rejected valid master-key auth), and
  `docker compose up -d --force-recreate` does not reliably re-read an external `env_file` —
  a full `stop`+`rm -f`+`up` is required. Both documented in `Gotchas.md`.
- **2026-07-07 · Final whole-branch review fix + one-click start buttons for both stacks.**
  Opus-reviewed the full Open Workshop containerization range and found one Important,
  cross-task-only gap: `docker-compose.yml`'s `OPENAI_API_KEY=${LITELLM_MASTER_KEY:-cooper-local}`
  for `cooper-core` resolves from Compose-level interpolation (shell env / `PDA-Runtime/.env`),
  **not** from `litellm/.env.local` — a latent fresh-clone auth failure that only worked here
  because both files happened to hold the same value. Documented in `docker-compose.yml` and
  `.env.example` (which already anticipated the requirement) rather than restructuring the
  mechanism. Separately, built desktop shortcuts for both stacks — `PDA-Runtime/Start COOPER
  Private.lnk` (amber icon) and `Start COOPER Open.lnk` (teal icon), both visible-console,
  `-NoExit`, ready to pin to Start/taskbar. Building the Open shortcut surfaced a real bug in
  `Scripts/Start-PDA.ps1`: it used `docker start <container>` against a hardcoded name list with
  no knowledge of the new `cooper-core` service (never started it) and still checked for a
  `pda-ollama` container that isn't part of the current `docker-compose.yml` at all. Replaced
  with `docker compose up -d` (matching `Start-PDAPrivateStack.ps1`'s approach) plus the same
  stderr/`$ErrorActionPreference` fix from Task 5. Also stopped auto-opening n8n's browser tab
  on Open stack startup (Open WebUI still opens). All work pushed to `origin/step-9-dockerize`.
- **2026-07-08 · Step 13 complete: session-bound approvals + install-cooper.sh.** Built on
  `step-13-sessions` (branched from `step-9-dockerize`) via subagent-driven-development, plan
  `Docs/superpowers/plans/2026-07-08-step-13-packaging-session-binding.md`. Four tasks: (1)
  `approval.py`'s `_pending` ticket store re-keyed `workshop` → `(workshop, session_id)`; (2)
  `main.py` multi-key auth (`COOPER_API_KEYS`, comma-separated, + legacy `COOPER_API_KEY`
  fallback), `_derive_session_id` (sha256(token)[:12], `"anon"` for none), threaded through
  every chat/dispatch/approval/`/pending` call site; (3) `install-cooper.sh` — one-command
  bootstrap (prereqs, idempotent `.env` seeding with a generated key, `docker compose up -d`,
  stack-aware health poll: 8001 open / 8000 private); (4) Signal gateway made per-sender
  session-aware (`session_id=f"signal:{sender}"`) — this task was originally deferred pending
  Step 12's merge, which happened *mid-branch*, requiring a rebase (see below).
  **Mid-flight complication:** Step 12 (Signal gateway) merged into `step-9-dockerize`'s tip
  after this branch had already forked from it, so `step-13-sessions` had to be rebased onto
  the new tip — conflicting with Task 2's session-threading (Step 12 had refactored
  `chat()`/`oai_chat()`/`_stream_sse()` into one shared `_chat_core()`) and with Task 3's
  compose-file edit (Step 12 added Signal env vars at the same insertion point `COOPER_API_KEYS`
  landed on). Both resolved cleanly (re-threaded `session_id` through the merged `_chat_core`;
  kept both sibling env lines in the compose file) — full suite green after (82/82, then 83/83
  after the final-review test addition).
  **Live-verified** (not just curl-tested-once): Docker Desktop cold-started, open stack brought
  up via `install-cooper.sh`, and in the process caught a stale pre-Task-2 cached `cooper-core`
  image that `docker compose up -d` had silently reused (rebuilt with `docker compose build`).
  Ran the plan's exact two-client scenario against an isolated instance
  (`COOPER_API_KEYS=key-a,key-b`): client A's dispatch halted for approval; client B's `approve`
  did NOT consume it (fell through as an ordinary reply — no cross-session leakage); client A's
  own `approve` consumed its ticket and attempted execution; `/pending` for A was empty after.
  **Whole-branch review (opus) caught a real security gap post-implementation:** the well-known
  default key `cooper-local` (used both by the legacy `COOPER_API_KEY` compose fallback and by
  Open WebUI's own hardcoded fresh-install connection credential) remained valid forever, so any
  two clients using the *documented* default landed on the identical derived session and could
  still cross-approve each other's tickets — defeating this step's entire purpose for anyone who
  hadn't rotated the default. Fixed by switching the compose files' `${VAR:-default}` to
  `${VAR-default}` (single-dash — treats an explicitly-empty value as intentional, not "unset")
  and having `install-cooper.sh` write `COOPER_API_KEY=` (empty) alongside the generated
  `COOPER_API_KEYS`; a fresh checkout with no `.env` is unaffected (unchanged zero-config
  solo-dev fallback). Also added an HTTP-level (`TestClient`) regression test for the isolation
  guarantee itself — prior coverage was pure-function/store-level only. Final state: 83/83
  tests passing, merged (fast-forward) into `step-9-dockerize`, `step-13-sessions` branch and
  worktree cleaned up. **Known, disclosed gaps, not done:** Open WebUI browser click-through (no
  browser-automation tool in this environment) and Task 4's live Signal-phone verification (no
  physical Signal-registered device available) — both explicitly flagged rather than claimed.

- **2026-07-20 · Step 10 closed: whole-branch review + Docker deployment fix.** Resumed a
  2026-07-08 pause (all 6 tasks done, final review pending). `step-10-skills` already had
  `step-9-dockerize`'s Steps 12/13 merged in. Ran the deferred whole-branch review
  (`superpowers:requesting-code-review`, opus) — independently verified: the earlier
  symlink-exfiltration fix actually blocks the attack, the Step 12/13 merge conflict resolution
  in `main.py` is correct, 120/120 tests pass. One Critical finding, fixed same session: the
  skills subsystem was inert under `docker compose up` — `Skills/` and `Config/skills_registry.yaml`
  were never copied into the `cooper-core` image or bind-mounted, so `GET /skills` was permanently
  empty and `import_skill` wrote into the container's ephemeral layer (lost on restart). This
  slipped through per-task review because Step 10's live verification used the bare-metal
  `.venv-win` path, not Docker. Fixed: Dockerfile now seeds `Skills/` + the manifest, both compose
  files bind-mount them read-write. Verified live in real containers: built and ran both open and
  private `cooper-core` images, confirmed `GET /skills` returns the seed skill through the open
  container. Also excluded `cooper-core/venv` (a stray local venv, unrelated to Skills) from the
  Docker build context — a broken symlink inside it was failing the build outright. Merged
  `step-10-skills` into `step-9-dockerize`.

- **2026-07-21 · Step 11 complete: self-improvement loop (draft → approve → promote).** Built on
  `step-11-proposer` (worktree, off `step-9-dockerize`) via subagent-driven-development, 4 tasks:
  (1) `proposer.py`'s `draft_skill()` drafts a candidate SKILL.md into `Skills/_drafts/<name>/`
  after a successful dispatch, inert by Step 10's `_RESERVED_DIRS` mechanism; (2) wired into
  `main.py`'s `_execute()` — on a passing review verdict, drafts a skill and appends a one-line
  promotion offer, wrapped in defense-in-depth try/except; (3) `promote_skill` tool —
  approval-gated (permission_level 2), previews the draft's SKILL.md before approval, then moves
  it to `Skills/learned/<name>` and registers it, mirroring Step 10's `import_skill` governance
  pattern; (4) `skillmd_stats` SQLite table counting activations at both of Step 10's injection
  call sites.
  **Bugs caught during task review, all fixed same session:** a plan-authored
  `asyncio.get_event_loop()` test bug that only broke under the full suite, not in isolation
  (switched to `asyncio.run()`); a test that didn't actually exercise the `_RESERVED_DIRS`
  inertness guarantee (strengthened to register a manifest entry pointing straight at a draft
  and confirm it's still refused); a duplicate `notes:` YAML key in
  `Config/private_tool_registry.yaml` that silently dropped an unrelated tool's governance note
  (fixed; added a duplicate-key-detecting regression test for the whole bug class, verified
  load-bearing).
  **Whole-branch review (opus) caught a real cross-task interaction** invisible to any single
  task's review: `draft_skill()` accepted a `tool` param but never used it, so approving a
  `promote_skill` or `skill_import` dispatch (itself a passing run) immediately drafted a
  self-referential meta-skill about promoting/importing and offered it for promotion — bounded
  and inert, but unintended operator-facing noise. Fixed with an early-return guard before any
  LLM call, verified load-bearing.
  **Live-verified against a real running server** (bare-metal, this branch's own code, port 8010
  to avoid disturbing the already-running dev stack on 8000): full round trip of
  dispatch → draft offer → promote → approve → register → `GET /skills` shows `ok` → conversational
  use → `skillmd_stats` activation count incremented, all genuine, all passed first attempt. Test
  artifacts from this run were reverted afterward (not intended permanent content). 139/139 tests
  passing. Merged into `step-9-dockerize`, worktree and branch cleaned up.
  **Known, disclosed, not done:** Open WebUI browser click-through (no browser-automation tool in
  this environment, and Open WebUI isn't wired to the verification server's port) — reviewer
  agreed this doesn't materially affect merge-readiness since the offer line is a plain string
  appended server-side to the same bytes the browser would render, already exercised by the API-level
  DoD check.

- **2026-07-21 · Open Workshop capability gap closed — steps 4/5/6/7/8/11 live-verified on Open,
  not just Private.** Prior audit found several capabilities were only ever proven against
  Private's local Ollama backend, never against Open's cloud path (`pda-open-cooper-core`, port
  8001, OpenAI/Claude/Gemini via LiteLLM) — presumed-fine by shared code, not proven-fine. Ran the
  same DoD checks live against the running Open container:
  - Approval gate + execution gateway (halt → approve → execute) confirmed on Open with
    `Test-Exec.ps1` (added to `general_tool_registry.yaml`'s `powershell_open.allowed_scripts`,
    mirroring the Private registry's existing entry — the only functional registry change).
  - Step 6's previously-unproven half ("Open Workshop allows an approved cloud call") confirmed by
    dispatching `lite_llm_router` (`executor_type: llm_api`, one of the two types Private's
    `workshop.py` blocks outright) — approved cleanly, no workshop violation. Executor stub output
    was correctly flagged by the sub-agent reviewer (`[Reviewer flagged this result — Executor type
    not wired in the gateway]`), proving Step 7's flag case on Open at the same time.
  - Step 8 (memory + skill loop) confirmed on Open: second `Test-Exec.ps1` dispatch showed
    skill-reuse messaging ("matches a proven skill"); a decision-recall question got a real answer
    from the `decisions` table, not a generic non-answer.
  - Step 11 (self-improvement loop) confirmed on Open end-to-end for the first time: a passing
    dispatch drafted `run-test-exec`, `promote skill run-test-exec` halted with the draft SKILL.md
    shown for review, approval registered it, `GET /skills` showed it `ok`, and a follow-up
    conversational question matching the skill's own wording triggered it and incremented
    `skillmd_stats`. **Decision: kept `run-test-exec` as a real registered skill** rather than
    reverting it as test residue — it was created through the legitimate promote workflow directly
    on the live production container (both stacks were already up; no isolated test instance was
    used this time, unlike Step 10/11's original port-8010 verification), and is genuinely useful.
  - `GET /skills` workshop-scoping cross-check: `hello-cooper` and the new `run-test-exec` (both
    `workshop: open`) show on 8001 and correctly return empty on 8000 (private).
  - Private Workshop regression check: full pytest suite via `.venv-win` — 137/139 passing
    (2 pre-existing, unrelated failures, see below); a live dispatch → approve → execute round trip
    on `pda-private-cooper-core` confirmed via direct DB read (`decisions` table shows the run,
    `outcome: success`, review verdict `pass`) after the CPU-only Ollama backend in this environment
    took several minutes to respond — slow, not broken (no GPU engaged this session; matches the
    documented GPU-reservation gotcha).

  **Real regression found and fixed, not a known limitation:** `approval.py`'s `_APPROVE_RE`/
  `_DENY_RE` were full-match-only against a single token, so the exact phrases PROGRESS.md itself
  records as live-verified — `"yes, go ahead"` and `"no, cancel that"` — silently stopped matching
  at some point (collateral damage from an earlier fix that correctly blocked `"yes, but first…"`
  from false-matching). A user typing the natural, documented approval phrase got reclassified as a
  new conversational turn with no error — just confused silence. Fixed by allowing chained
  approve/deny tokens (`yes, go ahead` = two tokens) while still rejecting hedges with non-approve
  content after the first token; two regression tests added to `test_approval.py`. Confirmed live
  on both workshops post-rebuild.

  **Two pre-existing test failures found, not caused by this session's edits (git diff confirms
  neither touched file was edited):** `test_main_open_routing.py`'s two subprocess-isolation tests
  fail with `OSError: [WinError 10106]` (Windows socket-provider error) when run via the Windows
  `.venv-win` — environmental, not code. `test_skills.py::test_fetch_tap_rejects_symlink_and_copies_nothing`
  fails consistently on the Windows venv (`DID NOT RAISE SkillError`) — likely a Windows
  symlink-privilege/semantics gap versus the Linux containers actually deployed; needs
  investigation on Linux, not fixed this session. Flagged for follow-up, not chased further.

  **Separately, changed COOPER's baseline humor setting from 35 to 55** (both workshops share one
  Modelfile) per explicit request — updated `Models/cooper-personality/Modelfile`,
  `personality.json`, `profiles.json`'s `operations` profile, the legacy
  `Scripts/COOPER_Personality.json` mirror, and `main.py`'s Modelfile-missing fallback string.
  Confirmed live on both workshops post-rebuild (`"Humor: 55."` / "55%" in conversational replies).

  **Both `cooper-core` images required a rebuild + `--force-recreate`** for every change above to
  take effect — `Models/cooper-personality/Modelfile` and `Config/general_tool_registry.yaml` are
  baked into the image at build time, not bind-mounted (only `Obsidian Vault/brain`, `Skills/`, and
  `Config/skills_registry.yaml` are). Worth remembering for any future Modelfile/registry edit.

  **Not attempted this session (explicitly out of scope):** fixing the known, already-disclosed
  limitations (non-PowerShell executor stubs, keyword-only tool/skill matching, memory not read
  outside dispatch) and Step 12's live Signal-phone verification (`SIGNAL_NUMBER` unset, no `.env`
  file yet, needs a real registered device) — both deferred as separate, later work.

- **2026-07-21/22 · "Arm COOPER with real tools + skills" — all 13 registry executor_types now
  wired for real, both workshops.** User redefined "done"/"fully functional" against Hermes Agent
  as the benchmark: every currently-listed registry tool executes for real, with real skills and
  full testing, closing the gap where COOPER's only working execution path was 2 of 307 legacy
  PowerShell scripts. Plan: `~/.claude/plans/snazzy-mapping-kite.md` (batches -1 through 8). Full
  detail below; every handler follows the proven `_run_powershell` pattern: resolve target →
  authorize against a registry allowlist (fail-closed) → execute off the event loop → bounded
  output → let the sub-agent reviewer catch problems.

  **Batch -1 — real, pre-existing vulnerability found and fixed, unrelated to the tools work.**
  A Fable 5 (`model: fable`) plan review flagged `n8n Workflow/PDA-ChatBridge.json` and
  `PDA-ChatBridge-Rebuilt.json`: both wired an `n8n-nodes-base.executeCommand` node whose
  `command` param was built by string-joining a `JSON.stringify()`-escaped user message into a
  shell command line — JSON escaping isn't shell escaping, so shell metacharacters in a chat
  message could break out of the intended argument. Verified via the owner's own n8n UI screenshot
  that neither "PDA Chat Bridge" nor "PDA Chat Bridge v1" was Published (only "PDA Command Router"
  and the safe HTTP-based "PDA Chat Bridge HTTP" were) — nothing was live-exploitable, but both
  files were gitignored, superseded by the safe HTTP variant, and one accidental toggle away from
  exposure. Both files deleted from the repo; owner deleted the corresponding n8n workflows.

  **Batch 0 — unblocked `import_skill`, proved the tap-import mechanism for real.** `git` was
  never installed in `cooper-core/Dockerfile` (only `wget ca-certificates`), so `fetch_tap`'s
  `git clone` would `FileNotFoundError` in the real container — added `git`. Rather than trust an
  unvetted public tap, proved the mechanism with a local fixture repo (same technique
  `test_skills.py` already uses: monkeypatched `_ALLOWED_SCHEMES` to include `file://` for the
  test only) run directly inside the live `pda-open-cooper-core` container: real `git clone` →
  frontmatter validation → symlink rejection → hash → manifest registration → confirmed via
  `GET /skills` showing `ok`. Test artifact reverted afterward.

  **Batch 1 — `informational` + `local_read`, both workshops.** Turn-local summary (no chat
  history reaches the executor layer, documented honestly rather than fabricated) and a
  registry-snapshot reuse of `registry.format_tool_list()`. Live-verified on Open.

  **Batch 2 — `python`, both workshops.** No existing Python script directory existed (unlike
  PowerShell's 307 scripts) — created `Scripts/Python/Test-Exec.py`, mirroring `Test-Exec.ps1`'s
  exact precedent, and added it to both registries' new `allowed_scripts` field (neither had one
  before). `_run_python` mirrors `_run_powershell` exactly. Live-verified on Open (dispatch →
  approve → real execution); on Private, tool-selection/dispatch was confirmed correct live but
  the full execute round-trip was blocked by host resource contention that session (see below) —
  confirmed instead via direct DB read after a delayed completion (`decisions` table shows
  `Test-Exec.ps1`... — actually the PowerShell entry; Python's own decisions-table confirmation is
  covered by the dispatch-level proof plus 23/23 passing unit tests exercising the real subprocess
  path).

  **Batch 3 — `filesystem` (Restricted DMZ Writer) + `local_llm` (Qwen Local Assistant), Private
  only.** Resolved decision #3 (qwen_local_assistant repoints at the already-deployed
  `COOPER-Private` Ollama model with a distinct analysis/drafting system prompt, since Qwen was
  already superseded by the Gemma-based rename, rather than pulling a second model). **Corrected a
  Fable finding against the actual governance doc**: Fable recommended an overwrite guard citing
  Level 5, but `01_AI Ecosystem Architecture.md` explicitly defines Level 2 as "Creates or updates
  local non-sensitive output... Example: create Obsidian note, draft markdown, write report draft"
  — both `restricted_dmz_writer` and `obsidian_note_writer`'s own registry descriptions say
  "create or update." Level 5's overwrite concern is protected/sensitive data or structurally
  altering the DMZ/Vault, not a Level-2 tool routinely updating its own output. Implemented
  create-or-update, not overwrite-refusal. Live-verified on Private: DMZ writer dispatch → approve
  → "Wrote 'batch3-test.txt'..." confirmed (content not inspected by me directly — Restricted DMZ
  Workspace is off-limits for me to read/write directly per CLAUDE.md, API-level confirmation is
  sufficient; owner asked to clean up the test file). Qwen Local Assistant's dispatch→approve path
  confirmed live; the actual Ollama call hit the same host-resource-contention timeout described
  below, correctly wrapped as a clean `ExecutionError` rather than crashing — the graceful-
  degradation path itself is proof the fail-safe design works under real duress, matching the
  Step 11 Docker-gap precedent. Success-path logic is thoroughly unit-tested with mocks.

  **Batch 4 — `note_editor`, `llm_api`, `browser`, Open only.** Note writer targets a new
  `Obsidian Vault/00_Inbox/` bind mount (matching `08_Obsidian Vault Structure.md`'s recommended
  layout — new content lands for a human to file properly, never the project-docs area).
  `browser_research` implements decision #2: stdlib-only `html.parser.HTMLParser` text extraction,
  no Playwright/Selenium. **Real bug found and fixed live**: `_run_llm_api` originally passed the
  *entire* dispatch message (including "use the LiteLLM Router tool to route this prompt...").
  This confused the downstream model into commenting on the tool-invocation framing itself instead
  of answering — caught by the sub-agent reviewer. Fixed to extract the text after the last colon
  as the actual prompt, matching the "instruction: payload" convention the DMZ/note writers
  already use. Re-verified clean after the fix. All three live-verified on Open with real output
  (a real fetch of example.com, a real LiteLLM-routed "Banana! 🍌", a real note file written and
  confirmed on the host filesystem, then cleaned up).

  **Batch 5 — `workflow_engine`, both workshops.** Private has no reachable n8n instance at all
  (confirmed: no n8n service in `docker-compose.private.yml`) — `restricted_workflow_runner`
  honestly reports this rather than silently pretending to succeed or guessing at a fake backend.
  Open's `n8n_general_workflows` got a manually-reviewed `allowed_workflows` mapping (direct
  consequence of Batch -1's finding: the allowlist gates *which* workflow, never *what it does
  internally* — every entry was inspected for unsafe node types first). **Real integration bug
  found and fixed live**: the handler's payload was sent only as `{"message": ...}`, but
  `PDA_Command_Router.json`'s own routing logic reads `body.command`, leaving every route
  classified `"unknown"`. Fixed to send both `command` and `message` keys (covering both
  currently-allowlisted workflows' different expectations). Live-verified: the fixed handler
  round-trips correctly through the real n8n webhook. **Separately, and unrelated to this
  handler's code, discovered `PDA_Command_Router.json`'s own reporter/multi-agent routes are
  currently broken** — they try to write to `/files/PDA-Tasks/staging/...` but `docker-compose.yml`
  mounts `..:/files:ro` (read-only); n8n's logs also show recurring `SQLITE_CONSTRAINT: FOREIGN KEY
  constraint failed` errors unrelated to this session's changes. Flagged as a pre-existing n8n
  workflow bug, not fixed this session — out of scope for the tools/skills work.

  **Batch 6 — `cli_launcher` (Codex Task Launcher), Open only.** Native Python port of
  `Scripts/Invoke-COOPERCodexTaskGenerator.ps1`'s title/slug/markdown-template logic only
  (decision #4) — does not chain into the legacy PowerShell approval/workbench/review scripts the
  original calls, since this dispatch is already governed by the new FastAPI approval gate.
  Title/slug regex ported faithfully (including a subtle backtracking edge case in the original
  that only surfaces on artificially truncated input, not real usage — preserved rather than
  "fixed," since decision #4 was a faithful port). Added a `Codex_Tasks/` bind mount (previously
  neither bind-mounted nor baked into the image). Live-verified on Open: real dispatch → approve →
  a real, correctly-formatted task file appeared in `Codex_Tasks/` on the host, then cleaned up.

  **All 13 registry-referenced `executor_type`s are now wired.** Full suite: 170 passing (up from
  137 at session start), same 3 pre-existing, unrelated, environment-specific failures (Windows
  `WinError 10106` socket-provider error in a subprocess-isolation test; a Windows-vs-Linux
  symlink-privilege gap in `test_fetch_tap_rejects_symlink_and_copies_nothing`) — neither touches
  any file changed this session, not chased further.

  **Environmental gotcha reconfirmed, twice, this session:** the same host-memory-pressure pattern
  documented 2026-07-07 (`vmmemWSL` alone consuming 6-6.6 GB of 16 GB total, leaving Private's
  CPU-only Ollama badly starved) recurred under this session's heavy rebuild/recreate/testing
  load, producing empty-message `ExecutionError`s (`asyncio` timeout-style exceptions stringify to
  `""`) and multi-hundred-second response times. Not a code regression — confirmed via `docker
  stats` and `Get-Process` both times.

  **Self-improvement loop kept pace automatically**: nearly every successful dispatch during this
  session's live testing auto-drafted a real candidate skill into `Skills/_drafts/` (e.g.
  `run-status-summary`, `run-registry-inspector`, `note-creation-process`, `lite-llm-routing`,
  `browser-research-example`, `run-pda-command-router`, `add-rate-limiting`) — inert until
  promoted, sitting ready for the owner's review. Batch 7 (curate/promote a real skill set) and
  the remainder of Batch 8 (workflow-level documentation beyond this entry) are still open.

  **Left for the owner:** a test file at `Restricted DMZ Workspace/batch3-test.txt` (proof-of-write
  artifact — I don't touch that directory directly per CLAUDE.md, so didn't delete it myself).

- **2026-07-30 · Migrated to Pop!_OS laptop + portable-deployment packaging.** Repo moved from
  the Windows 11/WSL2 machine to `/home/zb6/Documents/Projects/01_AI_Ecosystem` on a Pop!_OS
  laptop (i9-14900HX, 125 GB RAM, RTX 1000 Ada 6 GB) — the "Pop!_OS deployment test" horizon
  from North Star. Inventory: repo/branches/`cooper_memory.db`/`litellm/.env.local`/
  `n8n-api-key.txt` all migrated; `PDA-Runtime/.env` and Open WebUI volumes did not (installer
  reseeds / 2-minute rewire); the 2026-07-21/22 tools session arrived as an uncommitted working
  tree (real work — commit it). Machine was bare (no Docker/Ollama/pip/pwsh). Packaged the
  install path for any future machine (other laptops, home server): **`setup-linux.sh`** (new,
  repo root) provisions system applications on any Debian/Ubuntu-family host — git, curl,
  Docker Engine + Compose v2 + buildx, nvidia-container-toolkit (auto-skipped without a GPU),
  python3-venv/pip, sqlite3, host Ollama + `gemma4:12b`→`COOPER-Private`, pwsh tarball;
  `--minimal` flag for Docker-only hosts. `Documentation/PDA-Portable-Deployment.md` and
  `PDA-Migration-Checklist.md` rewritten for the v2 runtime (were PowerShell/Fabric-era):
  full application list, 3-layer install (provision → `install-cooper.sh` → identity/state),
  GPU-less private-stack override (`private-ollama`'s `deploy:` block), and the table of
  files/volumes that carry COOPER's identity. README + CLAUDE.md now point at the guide.
  Deleted the dead Windows `cooper-core/venv`. Not yet done on this machine: run
  `setup-linux.sh` (needs owner sudo), stand up the stacks, re-verify the suite on Linux,
  full CLAUDE.md Windows→Linux rewrite.

- **2026-07-31 · Pop!_OS deployment verified: both stacks live, 173/173 tests green on Linux.**
  Closes the "not yet done" list from the 07-30 migration entry (all but the CLAUDE.md rewrite).
  Owner ran `setup-linux.sh` — validated: Docker 29.1.3 + Compose 2.40.3 with the `nvidia`
  runtime, RTX 1000 Ada visible, Ollama 0.32.5 with `gemma4:12b`→`COOPER-Private`, pwsh 7.6.4,
  Python 3.12.3, sqlite3. Both stacks brought up via `install-cooper.sh` and live-verified:
  Private (8000) — health ok, 401 without key, `/tools` lists 8, GPU visible inside
  `pda-private-ollama`, real chat round trip in character (~78 s cold incl. model load);
  Open (8001) — health ok, 401 without key, real chat traversed cooper-core → LiteLLM → cloud.
  One fix en route: `docker-compose.yml` declares the `open-webui` volume `external: true`, and
  that volume didn't migrate — `docker volume create open-webui` before first `up` on a fresh
  machine (candidate for install-cooper.sh or the migration checklist). Test suite re-verified
  in a fresh Linux venv (`cooper-core/.venv`): **173 passed, 0 failed, 1.55 s** — all 3
  chronic Windows-environment failures (2× `WinError 10106` subprocess-isolation, 1× symlink
  semantics in `test_fetch_tap_rejects_symlink_and_copies_nothing`) pass on Linux, confirming
  they were environmental; the symlink *security* test now genuinely exercises on the deployed
  OS. GitHub auth for this machine set up (fresh ed25519 key, host keys fingerprint-verified);
  the migrated dirty tree committed as `6e8a8f5` (tools session) + `5ca0749` (deploy packaging)
  and pushed. Still open: CLAUDE.md Windows→Linux rewrite; Open WebUI fresh-volume setup on
  3000/3001 (admin account + manual connection with the key in `PDA-Runtime/.env` — owner task);
  Batch 7 skill curation; Step 12 live Signal-phone test.

- **2026-08-01 · CLAUDE.md Windows→Linux rewrite.** Closes the last CLAUDE.md item from the
  migration entries. Full rewrite for the Pop!_OS deployment: start/stop/status is now
  `install-cooper.sh` / `docker compose` (with port map and the `docker volume create
  open-webui` fresh-machine gotcha), auth section documents the `COOPER_API_KEYS` Bearer flow,
  bare-metal dev path is `cooper-core/.venv` + uvicorn with the `main.py` env vars, Open WebUI
  wiring updated to container-DNS URL + generated key. Removed entirely: D:\ paths,
  `.venv-win`, `Start-CooperCore.ps1` interop, WSL2 mirrored-networking section (git history
  has them). Directory map updated (Skills/, litellm `.env.local`, legacy markings on
  `Scripts/` and the PDA-Runtime `*.ps1` wrappers); "Current vs target architecture" replaced
  with the live v2 description (v1 socket path marked retired). Every documented command
  verified live this session: both healths, 173/173 suite (1.4 s), 8/8 pipe tests from repo
  root, key extraction + 401 without auth. Modelfile note clarified: `FROM gemma3:12b` is
  legacy — runtime extracts only the SYSTEM prompt; served weights are `gemma4:12b` aliased
  `COOPER-Private`. Remaining open items unchanged: Open WebUI fresh-volume wiring (owner),
  Batch 7 skill curation, Step 12 live Signal test.

- **2026-08-02 · Batch 7 skill curation done — 2 promoted, 5 rejected.** Reviewed all 7
  `Skills/_drafts/` candidates from the 07-21/22 tools session. Promoted
  `run-registry-inspector` and `run-status-summary` (accurate, general procedures for real
  registry tools) through the live governed workflow on the Open container — dispatch
  `promote skill <name>` → approval gate → `register_promotion` — both now in
  `Skills/learned/`, manifest entries appended (workshop: open), `GET /skills` on 8001
  reports 4 skills all status `ok`; Private (8000) unaffected at 0. Bind-mount writes
  preserved host ownership (`shutil.move` + in-place manifest rewrite — no root-owned-file
  cleanup needed on Linux, unlike the Windows drvfs episode). Rejected as test residue:
  `browser-research-example` (example.com browse), `lite-llm-routing` ("say banana" test),
  `note-creation-process` (batch4-test.md artifact), `run-pda-command-router` ("test payload
  from batch 5"), `add-rate-limiting` (generic Express.js advice, wrong stack). Suite
  173/173 after. Owner direction this session: Signal (Step 12) deferred to "far later";
  focus is a working product on this machine.

- **2026-08-02 · Desktop launcher buttons + open-webui volume fix.** New `launch-cooper.sh`
  (repo root): `--install-desktop` writes "COOPER Private" / "COOPER Open" `.desktop`
  entries into `~/.local/share/applications` (icons in `PDA-Runtime/launchers/`,
  absolute-path Exec — re-run after a repo move); `launch-cooper.sh <stack>` wraps
  `install-cooper.sh`, additionally polls the Open WebUI port, then `xdg-open`s :3001/:3000,
  with notify-send progress and failures logged to `tmp/launch-<stack>.log`. Verified live:
  `desktop-file-validate` clean on both entries, both stacks launched via the script
  (exit 0, browser opened), and a real click simulated with `gtk-launch cooper-private`
  (same code path as the dock) — full round trip through install-cooper.sh confirmed in the
  log. Also folded the fresh-machine `docker volume create open-webui` fix into
  `install-cooper.sh` (the volume is `external: true` in compose; create is idempotent) —
  closes the 07-31 gotcha, a fresh machine's first button click now works. Docs updated:
  CLAUDE.md start/stop section + `PDA-Portable-Deployment.md` launcher subsection.

- **2026-08-02 · Step 10 deferred follow-ups closed (TDD) + machine DNS gotcha found.** All
  three items from the 07-20 "known, disclosed, deferred" list, red-green with 5 new tests
  (`test_skills.py` ×3, `test_main_skills.py` ×2): (1) `fetch_tap` now bounds the WHOLE
  clone at 50MB (was: only the final `skills/<name>` subdir at 10MB — a huge file elsewhere
  in the tap repo sailed through); (2) staged-import cleanup — denying an `import_skill`
  approval discards `Skills/_incoming/<name>` (`skills.discard_staged`, non-fatal hook in
  `_resolve_approval`), `fetch_tap` sweeps `_incoming/` orphans older than 1h (expired
  tickets), and `Skills/_incoming/` is gitignored; (3) the blocking chat path
  (`_generate`) now injects recall-then-skill context, matching the streaming path (was
  inverted). Suite 178/178; both stack images rebuilt + recreated, health ok, new code
  confirmed inside both containers via `docker exec grep`. En route, the suite hung and
  systematic debugging traced it to a MACHINE bug, not the code: every `git clone` on the
  laptop hangs because the hostname isn't in `/etc/hosts` and the resolver path stalls
  (full chain + fixes in Gotchas.md 2026-08-02). Repo-side hardening landed as
  `cooper-core/conftest.py` (hermetic git ident for the suite); machine-side `/etc/hosts`
  fix needs owner sudo. Also this session: desktop launcher buttons (entry above) and
  Batch 7 curation (entry above).

- **2026-08-02 · Four hardening features (owner-picked), TDD, 206/206, deployed.** Machine
  DNS fixed by owner (`127.0.1.1 pop-os` in /etc/hosts — lookup now 2ms, clones work).
  (1) **Semantic skill matching** — `select_skill_semantic` embeds catalog+query via the
  workshop's own backend (`nomic-embed-text` on Ollama / `text-embedding-3-small` via
  LiteLLM, new `embeddings.py` with sqlite cache in cooper_memory.db), per-model thresholds
  calibrated live (nomic: match .52-.59 vs noise ≤.43 → 0.48; openai: .34-.40 vs ≤.17 →
  0.25 — one threshold would NOT fit both), keyword fallback on any failure. Live-proven on
  Open: "how are all systems doing right now?" (zero keyword overlap) activated
  run-status-summary, activation row written. Model pulls added to setup-linux.sh + private
  compose model-init; embedding model added to litellm_config. (2) **Background
  post-dispatch** — archivist.remember + proposer.draft_skill moved off the request path
  (`_post_dispatch` via create_task, strong-ref set); draft offers now arrive as next-turn
  session notices on both blocking and streaming paths. Live: dispatch replied in 3.3s with
  the memory write landing seconds after the reply. (3) **Draft gate** — heuristic
  test-residue regex before the LLM call + required `reusable` boolean in the draft schema
  (Batch 7's 5/7 residue ratio was the driver). (4) **Evidence validator** — new
  `evidence.py` (+CLI) encoding the Workflow_Evidence rule set: approval linkage,
  workflow/status consistency, Category 1/2 artifact boundaries, sensitive-marker hygiene;
  all 15 fixtures execute, each invalid failing for its named rule. **Real finding:** all
  12 records in `State/Workflow_Evidence/` are non-compliant (June v1-era, no approval_id —
  predate the linkage rule); left untouched as history. Not live-observed (unit-tested
  only): the next-turn draft-offer notice — needs a novel non-test dispatch to draft
  something new.
- **2026-08-04 · Browser path verified live; OpenRouter wired as a parallel connection.**
  Owner logged into Open WebUI on :3000 and the model dropdown was empty. Root cause: an
  OpenAI `sk-proj-…` key had been pasted where the `cooper-…` key belongs — Open WebUI shows
  NO error for this, only `401` in cooper-core's log (Gotchas 2026-08-04). After the fix:
  `GET /v1/models` and `POST /v1/chat/completions` all 200, and `run a status summary`
  matched the promoted `run-status-summary` skill ("1 successful run, 100% trust") on a real
  browser turn. **This closes the Open WebUI browser click-through, honestly flagged "not
  done, not claimed" since 2026-07-08 across Steps 11/12/13** — the full path Open WebUI →
  cooper-core → LiteLLM → cloud → browser is now proven end to end.
  **OpenRouter:** already keyed and working through LiteLLM (alias `openrouter`) but exposed
  nowhere; verified live from inside cooper-core (HTTP 200). Owner chose a second, direct
  Open WebUI connection to `https://openrouter.ai/api/v1` rather than routing it behind
  COOPER — deliberate ungoverned path for talking to models directly, governance tradeoff
  stated and accepted. Key validated (paid account, no cap). COOPER's own brain and
  classifier deliberately unchanged on gpt-4o-mini. Zero code changes, zero rebuild.
  **Dispatch pipeline re-verified live twice** (Obsidian Note Writer): dispatch → halt →
  approve → execute → reviewer pass → memory row → skill stats, with the note confirmed on
  the HOST filesystem. First attempt failed on the note-writer's undocumented literal syntax
  (Gotchas 2026-08-04) — the reviewer caught it and surfaced it rather than passing it.
  **Draft-offer notice: still not observed live, and now understood why.** `_post_dispatch`
  demonstrably ran (memory rows 6-7 written, skills table updated), so `draft_skill` returned
  `None` silently — the drafter judged both dispatches non-reusable, which is exactly what the
  2026-08-02 gate instructs (`proposer.py:22-24` names "verification probe" and "one-off").
  The first test message literally announced itself as a verification; the second was a
  one-off note write. Not a bug — but it means the notice path needs a dispatch whose
  *procedure* is repeatable, and the obvious candidate (`lite_llm_router`) turned out to be
  unreachable through natural language (Gotchas 2026-08-04). Still open.
- **2026-08-18 · New direction — Step 15 Max-Metric Program: max every metric, outperform Hermes Agent, stay operational.**
  Session defined a 9-metric agentic-harness rubric; scored COOPER 32/45 vs Hermes Agent 29/45 —
  mirror-image profiles (COOPER maxes governance/audit/verification exactly where Hermes bottoms
  out, and vice versa). Owner merged three threads into one program
  (`Docs/superpowers/specs/2026-08-18-step-15-max-metrics-design.md`): (1) close every metric
  gap — 8 new slices 15a–15h interleaved with Step 14's; (2) planner–executor split — a big-brain
  model drafts each job's plan+envelope once (plan == envelope, hash-pinned), a cheap executor
  runs the steps inside it; (3) council system at planning time and final review only — mid-run
  deviation prevention stays deterministic (envelope/quota/exception queue in code); councils
  judge quality, mechanisms enforce bounds. **15a (native tool-calling) goes first** and retires
  the classifier-dispatch architecture; key enabler verified: gemma4 has native Ollama tool
  support, so Private needs no model swap. **Local-model decision:** quantize-down rejected —
  gemma4:12b is already Q4_K_M and Q3/Q2 quality loss is disqualifying; role-split instead:
  `gemma4:e4b` (~5GB, fully GPU-resident on the 6GB card) for high-frequency roles, 12b
  on-demand for judgment; E4B side-by-side benchmark queued as 15c's entry gate. **OpenRouter
  recon** (live key query): account is NOT free-tier — $7.91 of $20 prepaid consumed; `:free`
  daily caps are account-wide so fan-out doesn't multiply quota; `qwen3-235b` undercuts
  gpt-4o-mini per-token. Five governance gates (G1–G5) recorded in spec §6 and the Blocked
  section — each blocks only its named slice. Docs updated same day: North Star, Gotchas, this
  file, the Step 15 spec.
- **2026-08-23 · G1 decided: NO — Private plans locally, no inbound Open-drafted plans.** Owner
  ruled that an Open-drafted, owner-approved plan file may NOT be handed inbound to Private for
  execution. This matches the spec's default: Private plans with gemma4 locally (weaker plans,
  purest workshop boundary). Consequence: 15e's Private variant is now unblocked and its design
  is fixed — the planner–executor split on Private runs entirely on local models; M2's Private
  ceiling stays at the "jobs + local planner" level. Recorded in spec §6 and the Blocked section.
- **2026-08-23 · G2, G3, G5 decided (same session as G1).** **G2: keep gpt-4o-mini** as
  COOPER-Open's brain (reaffirms 2026-08-04); the 15c planner alias also starts as gpt-4o-mini —
  revisit only if 15c benchmarking shows planning quality is the binding constraint. **G3: yes** —
  the session-plans governance amendment is enacted: per-job approval extends to interactive chat
  work; 15h is unblocked and M2's target ceiling is 5. **G5: yes** — an OpenRouter spend guard
  will be enacted: owner sets a key-level limit in the OpenRouter dashboard, and a burn-alert
  check joins the digest job when 14b lands; dollar threshold chosen at implementation. Still
  open: G4 (SearXNG scope, blocks 14c) and 14f (network-review data source).
- **2026-08-23 · G4 decided: SearXNG stays Open-only; 14f pinned pending home lab.** Private
  gets no web-search path — the boundary stays "nothing leaves the machine"; owner may revisit
  later if Private ever needs internet lookup. All five G-gates are now closed; 14c is fully
  unblocked. **14f is no longer a pending decision** — the home-lab network doesn't exist yet, so
  it converts to a placeholder: when the home-lab project begins, pick the data source (router
  syslog / Pi-hole / other) and integrate COOPER as the network reviewer then.
- **2026-08-23 · G5 enacted on the owner side: $15 lifetime key cap, auto top-up off.** Owner set
  the OpenRouter key's credit limit to $15 in the dashboard. Verified live via
  `GET /api/v1/auth/key`: `limit: 15`, `limit_reset: null` (never resets — cumulative lifetime
  cap), `usage: 7.91` already counted, so ~$7.09 of headroom remains under the cap ($12.09 credit
  remains on the account). At the cap the key returns 402s — no charge, no refill. Owner chose to
  keep $15 rather than match the $20 prepaid total (guard trips early by design). COOPER-side
  half still to build: burn alert in the 14b digest job, trigger = remaining < $5.
- **2026-08-24 · 15a shipped: native tool-calling dispatch live on both stacks, 3 post-review
  Importants closed in a fix-forward pass.** Implementation (`f6d320b`, 8 tasks via
  subagent-driven-development): `registry.py` renders OpenAI-format tool schemas and validates
  args pre-approval; `decision.py` attaches `tools=` on every persona-model call and surfaces
  `tool_call`s instead of running a separate classifier; `main.py`/`approval.py`/`executor.py`
  thread validated args through the existing approval gate unchanged. Classifier, `select_tool`/
  `select_tool_llm`, and all execution-time regex parsing deleted outright — no fallback path.
  A whole-branch review found 3 Important findings the task-scoped reviews couldn't see; a
  fix-forward pass (`60461fd`, 4 more tasks) closed all three: (1) streaming no longer silently
  drops a `tool_call` that arrives after preamble content — content streams live and the
  dispatch still runs, appended after a visible separator, so the blocking and streaming paths
  agree on every turn's governance outcome; (2) `validate_args` now refuses empty required
  args, an unknown `workflow_engine` value, and non-http(s) URLs *before* opening an approval
  ticket — the exact "approval spent, then refused" class 15a exists to kill; (3) the tool_call
  accumulator no longer shreds one call into ghost entries when a provider omits `index` on
  fragmented deltas, and (self-caught during the fix-forward's own final review) no longer
  silently overwrites one Ollama tool_call with another when both arrive index-less in the same
  message. **Live-verified post-merge, both stacks rebuilt:** `/health` on both ports OK;
  blocking dispatch confirmed on Private (`status_summary`, L0 auto-run) and Open
  (`lite_llm_router`, L3 halt → approve → execute, args preview rendered correctly); the
  identical round trip re-confirmed over the real SSE streaming endpoint
  (`/v1/chat/completions`, `stream:true`) on both stacks — the code path Open WebUI actually
  uses and the one the streaming fix targets. Gemma4 tool-call hit rate this session: 2/2 clean
  dispatches, no preamble observed (extends the 2026-08-24 baseline of 2/2 already recorded
  pre-fix-forward). **Not verified:** an actual browser click-through through Open WebUI — no
  `claude-in-chrome` extension connection available in this environment session-side. The API
  path is proven end-to-end including the exact streaming transport Open WebUI consumes; only
  the rendering-in-a-real-browser step is unconfirmed. See `Obsidian Vault/brain/Gotchas.md`
  for a new trap surfaced during the fix-forward review: a client disconnecting mid-preamble now
  skips the trailing dispatch (fail-closed, no lying reply, but worth knowing).
- **2026-08-24 · Fix-forward pass independently reviewed clean; 15a closes pending one owner
  browser turn.** A fresh-eyes whole-range review (2e7946a..645d91a) confirmed: 248/248 tests
  (run by the reviewer, not taken on faith); all three Importants closed with the plan's exact
  semantics; governance invariants verified independently (validation before ticket, ticket-arg
  fidelity, approval.py/workshop.py zero-diff, execution-time allowlists untouched); the
  mid-pass revision commit (60461fd) judged a correct self-catch of a bug in the fix-forward
  plan's own Task 3 wording, not a regression. Separately live-corroborated this session:
  in-container `decision.py` hashes byte-identical to repo HEAD, and the preamble-then-dispatch
  scenario round-tripped on the real SSE endpoint (67 preamble chunks → `---` → halt with
  validated args → approve → executor output). **Deferred minors recorded for a future sweep**
  (none urgent): key the tool_call accumulator on fragment `id` before the name heuristic;
  give synthetic indices a disjoint key space (negative counter); consider `asyncio.shield`
  around the dispatch block if mid-executor client-disconnect cancellation ever bites;
  harden `TurnDecision`'s deferred-mutation contract for future stream callers;
  `_render_args_preview` repr/str two-char count mismatch. **Also observed live:** the two
  `Skills/_drafts/` entries are genuine proposer output from this week's DoD dispatches —
  the 2026-08-02 "draft offer never observed live" item is now closed; drafts await Batch 8
  curation. Remaining 15a step: owner browser click-through per stack (steps in the 15a
  fix-forward plan Task 5.2); only Open WebUI's rendering of the mid-stream separator is
  unproven. Next slice: 14a.
- **2026-08-25 · 15a's browser click-through closed — found and fixed a real governance
  bypass on Private along the way.** `claude-in-chrome` became available this session
  (previously absent, per every 15a session log above). Before running the click-through,
  checked Private Open WebUI (`localhost:3001`)'s Admin → Connections and found **no
  `cooper-core` connection existed at all** — instead, two live connections: a direct
  `https://api.openai.com/v1` (Bearer key set, enabled) and a direct
  `http://private-ollama:11434` (enabled). Confirmed the effect before touching anything:
  sent a dispatch-shaped turn ("Could you please give me a status summary right now?"),
  which ran and dispatched a tool call to `search_calendar_events` — not a registry tool
  (`grep` across `Config/` came up empty) — with **no approval halt**, and
  `docker logs pda-private-cooper-core` showed **zero non-health requests** for the entire
  turn. The turn never touched cooper-core: it went straight to Ollama's native tool
  calling, client-side in Open WebUI, bypassing the approval gate, tool registry,
  classification, and audit logging entirely — on the one workshop whose entire premise is
  local-only, air-gapped, boundary-enforced. Root cause: Open WebUI's SQLite-stored
  connections (see the 2026-07-01 Gotchas entry) had drifted from the documented wiring at
  some point with zero server-side trace of it happening.
  Fixed with owner sign-off: deleted both bypass connections (via each connection's own
  "Delete" control, not a raw DB edit), added the documented `http://cooper-core:8000/v1`
  connection with the `COOPER_API_KEYS` value (owner supplied it in-terminal from
  `PDA-Runtime/.env` — that file is access-denied to Claude by permission settings, so the
  owner read and pasted it, not Claude). Re-ran the click-through: `Could you please run
  Test-Exec.ps1 for me?` → real halt (`Halt — PowerShell Private Runner [Local Automation,
  permission level 4]...`) → `yes, go ahead` → `[Test-Exec.ps1 — OK]` rendered live in the
  browser, `docker logs` confirmed the `POST /v1/chat/completions` landed on cooper-core.
  **Open stack (`localhost:3000`) checked too**: `cooper-core:8000/v1` connection present
  and correct, plus the intentional OpenRouter connection from the 2026-08-04 decision log
  — but also flagged (not fixed, owner hasn't decided): an undocumented
  `http://host.docker.internal:11434` direct-Ollama connection, enabled, that isn't
  recorded as intentional anywhere. Ran its click-through anyway since cooper-core was
  correctly selected: `Could you please use the litellm router to answer: what is 2+2?` →
  halt (`Halt — LiteLLM Router [AI Models, permission level 3]...`) → approve →
  `[LiteLLM Router — model: openai] 2 + 2 equals 4.` rendered live, `docker logs` confirmed
  `pda-open-cooper-core` served it. **15a is now fully DoD-closed on both stacks** — no
  open items remain. gemma4 tool-call hit rate this session: 1/1 clean (Private), extends
  the running baseline to 3/3. New Gotchas entry filed for the SQLite-connections-drift
  risk. **Open stack's stray `host.docker.internal:11434` Ollama connection also
  resolved**: owner suspected it might belong to the sibling `03_brain_bot` project;
  checked that repo directly — its own Ollama link uses the container DNS name
  `pda-private-ollama:11434` (not `host.docker.internal`) and it runs its own dedicated
  Open WebUI instances (`:3002`/`:3003`), with zero references anywhere to port
  `3000`/`8001` or `host.docker.internal`. Confirmed unrelated, owner approved removal,
  deleted via the connection's own "Delete" control. Open's Open WebUI now has exactly
  two connections: `http://cooper-core:8000/v1` (governed) and
  `https://openrouter.ai/api/v1` (the 2026-08-04 sanctioned ungoverned path). Next slice:
  14a.
- **2026-08-25 · 14a shipped: Fabric pattern executor live on both stacks, whole-branch
  review found and fixed 1 Critical + 1 Important.** The 2026-08-04 plan predated 15a's
  native tool-calling shift and was built entirely around regex-parsing a raw chat
  `message` (pattern name, content, `key=value` overrides all pulled from one free-text
  string). Post-15a, executors receive validated, structured `args: dict` instead — so
  the plan was rewritten in place
  (`Docs/superpowers/plans/2026-08-25-step-14a-fabric-executor-revised.md`) before any
  code: dropped the message-parsing helpers entirely, added a `parameters` JSON-Schema
  block to both registry entries matching what `registry.validate_args` actually
  understands, and had `_resolve_pattern` match a single `pattern_name` argument instead
  of scanning a whole message. Built via subagent-driven-development in a worktree, 4
  tasks (catalog+resolve, template fill, the executor handler, registry entries), each
  independently task-reviewed clean (248→263 tests). Live verification (controller-run,
  not delegated — needed Docker rebuilds of the real shared stacks and a browser) found
  a real deployment gap immediately: `PDA-Fabric/` was never copied into the
  `cooper-core` image (unlike `Config/`, `Scripts/`, `Skills/`) — fixed the Dockerfile,
  then found the fix alone was a silent no-op because `.dockerignore` is a deny-by-default
  allowlist that never allowlisted `PDA-Fabric` either — fixed that too. Both stacks then
  confirmed live: dispatch → halt → approve → filled artifact with no stray
  `{{placeholder}}` text, via both the blocking `/chat` API and a real browser round trip
  on Open (`lite_llm_router`-style native tool-calling, `report-summary`/`review-checklist`
  patterns) and Private (`review-checklist`/`research-synthesis`/`security-triage`
  patterns, one skill-matched at 100% trust after a single prior run). **Final
  whole-branch review (opus) found the actual root cause the two Docker fixes had only
  patched around: `PDA-Fabric/` itself was gitignored and had never been committed to
  git at all** — a stale v1-era "generated exports / local mirrors" classification.
  Confirmed by reproducing the failure: `docker build` fails outright
  (`"/PDA-Fabric": not found`) and 10 of the fabric tests fail on a genuinely fresh
  checkout, since this branch's own Docker fixes only ever ran on the one machine where
  the four untracked template files happened to already exist locally. Fixed by tracking
  the four hand-written `.md` templates (36K total, no generated output) and dropping the
  ignore line. Same review also flagged (Important) that `_run_fabric_pattern`'s
  workshop-routing branch failed *open* toward cloud egress on an unrecognized workshop
  value (`if workshop == "private": ollama else: openai`) rather than fail-*closed*
  toward local, inconsistent with this repo's stated doctrine even though no live leak
  existed (upstream `check_backend`/`check_tool` already enforce the boundary) — inverted
  the conditional. Scoped re-review confirmed both fixes clean, no new breakage. Merged
  to `main` via clean fast-forward, 263/263 green. **Separate finding, discovered during
  browser verification, explicitly NOT fixed and NOT in scope for this slice**: an
  intermittent approval-ticket hijack where Open WebUI's own background housekeeping
  calls (title/tag/follow-up-suggestion generation) can silently overwrite and then get
  approved in place of the human's actual pending ticket — see
  `Obsidian Vault/brain/Gotchas.md`'s 2026-08-25 entry for the full mechanism and
  evidence trail. This is a cross-cutting approval/session-architecture question, not a
  Fabric bug, and needs an owner decision on the right fix. Next slice: per the roadmap
  execution order, 15c (unless the owner prioritizes the approval-ticket finding first).
- **2026-08-25 · Owner decision: fix the approval-ticket overwrite, next session, before 15c.**
  Discussed the Gotchas 2026-08-25 finding (Open WebUI's background calls can silently
  hijack a pending approval ticket). Considered whether 15i's planned Cockpit UI (which
  retires Open WebUI) makes this moot — decided no: 15i is several slices away per the
  roadmap execution order, so the exposure is live in the interim, and the actual root
  cause isn't Open-WebUI-specific — it's `approval.request()` (`approval.py:63`)
  unconditionally overwriting a live ticket for `(workshop, session_id)` with no check,
  which would still matter under Cockpit too (concurrent requests, multiple tabs/devices)
  even without Open WebUI's specific trigger. Scoped the fix deliberately narrow: make
  `approval.request()` refuse to open a new ticket when one is already pending for that
  key, instead of silently replacing it — a small, UI-agnostic correctness fix, not a
  session-identity redesign. Explicitly ruled out: pattern-matching Open WebUI's specific
  background-prompt templates (throwaway work that dies with Open WebUI) and a full
  per-conversation session-id scheme (better solved properly in Cockpit's own design,
  not retrofitted onto Open WebUI's client). **Next session: implement this fix before
  starting 15c** — needs a test proving a second dispatch is rejected (not silently
  substituted) while a ticket is already pending, then live-reverify via curl that the
  original ticket survives an interleaving dispatch attempt.
- **2026-08-30 · Approval-ticket overwrite fixed, before 15c.** `approval.request()`
  (`approval.py`) now checks for a live ticket at `(workshop, session_id)` first and
  raises `ApprovalConflictError` instead of silently overwriting it; `main.py`'s
  `_handle_tool_call` catches it and replies naming the still-pending tool, telling the
  human to approve/deny it before anything new can be dispatched — no ticket is lost or
  substituted. 4 new tests (`test_approval.py`: refuses-to-overwrite, allows-after-expiry,
  allows-after-consume; `test_main_dispatch.py`: dispatch-level conflict reply), full
  suite 267/267 green. Live-reverified inside both running containers after
  `--build cooper-core` on each stack (rebuild is required — `up -d` alone serves stale
  code): opened a ticket, attempted a second `request()` for the same session, confirmed
  `ApprovalConflictError` raised and the original ticket's message/tool unchanged —
  verified on Private and Open. Scope matched the 2026-08-25 decision exactly: no
  Open-WebUI-specific pattern matching, no session-id redesign. Next: 15c.
- **2026-08-30 · 15c shipped — per-role model routing, E4B live on Private, LiteLLM
  fallback pool on Open.** 6 tasks via subagent-driven-development, each independently
  task-reviewed clean on `step-15c-model-routing`.
  - **E4B benchmark (entry gate, run earlier this session before this plan existed):**
    `gemma4:e4b-it-qat` — 100% GPU-resident (3.1GB loaded), 46.5 tok/s avg, 11/11 (100%)
    tool-call accuracy against the real private registry schemas. `gemma4:12b` — 44%/56%
    CPU/GPU split (not fully resident despite flash-attention + q8_0 KV cache), 8.7 tok/s
    avg, 10/11 (91%) accuracy (misrouted one case — a Qwen-assistant request to
    `status_summary_private`). Model-swap cost measured at ~5-13s per direction.
  - **Owner decision (via AskUserQuestion mid-session):** Private routes ALL four live
    roles (brain, reviewer, drafter, archivist) to `gemma4:e4b-it-qat` — not a 12b-for-
    reviewer split — specifically to avoid paying the VRAM swap cost every dispatch turn
    (execute → review → archivist/drafter would otherwise swap models twice, since e4b's
    3.1GB + 12b's 7.9GB exceed this host's 6GB VRAM together).
  - **Task 1** rewrote `Scripts/PDA_ModelRouting.json` into a 7-role
    (`classifier, brain, planner, executor, reviewer, drafter, archivist`) → alias map,
    deleting the old v1 schema (`command_routes`, `category_routes`,
    `worker_command_map`, etc.). `classifier`/`planner`/`executor` are intentionally
    map-only (no call site today — classifier folded into brain at 15a, planner/executor
    don't exist until 15e), flagged in the JSON's own `notes` fields so 15d/15e's
    authors don't have to re-derive why. Reviewed clean.
    **Correction (final-review fix wave, 2026-08-30):** the deleted v1 schema was NOT
    unused — it has real (now-broken) consumers: `Scripts/Get-PDAModelRoute.ps1` (hard-
    throws `"Model routing policy is missing command_routes."`),
    `Scripts/Get-PDADashboardStatus.ps1` and `Scripts/Update-PDADashboard.ps1` (silently
    show empty routing tables), and `Scripts/Test-PDAModelFallback.ps1` (its fallback-
    injection setup now no-ops). `Documentation/PDA-Model-Routing.md` still described the
    deleted schema as current — marked superseded. **Owner decision: accept this
    breakage** — it matches the repo's documented v1→v2 retirement story
    (`Scripts/` is legacy, maintained not extended, per CLAUDE.md; v2/cooper-core never
    consumed these enforcement rules for anything). Not fixing the v1 scripts, not
    restoring any deleted keys — this is intentional, accepted v1 breakage, not an
    oversight.
  - **Task 2** added `cooper-core/model_routing.py` (`model_for(role, workshop)`,
    `load_routing()`, `ModelRoutingError`) — a pure lookup over Task 1's JSON. 6 new
    tests. Reviewed clean.
  - **Task 3** wired `main.py`'s four live roles (brain/reviewer/drafter/archivist) to
    resolve independently via `model_routing.model_for(...)`, replacing the old single
    shared `UTILITY_MODEL` global (removed entirely — already flagged unused). `/health`
    now exposes a `"roles"` dict. Reviewed clean, full suite 274/274 at the time.
  - **Task 4** repointed the `COOPER-Private` Ollama alias from `gemma4:12b` to
    `gemma4:e4b-it-qat` (`docker-compose.private.yml`, `setup-linux.sh`, `CLAUDE.md`).
    Live-verified on the real running Private stack: `ollama list` showed
    `COOPER-Private`'s ID exactly matching `gemma4:e4b-it-qat`'s ID; `/health` showed all
    4 roles as `COOPER-Private`; a real end-to-end dispatch turn (`status_summary_private`)
    succeeded with no errors. Also found and fixed a real packaging gap live:
    `cooper-core/Dockerfile` and `.dockerignore` never shipped `Scripts/PDA_ModelRouting.json`
    into the image (Task 3's new hard runtime dependency), causing a crash-loop on the
    first real `--build` of this branch — fixed in a separate commit. Also hit and fixed a
    transient live-auth break (rebuilding from a git worktree, which lacks the gitignored
    `PDA-Runtime/.env`, briefly emptied `COOPER_API_KEYS` on the real running container) —
    caught immediately, restored, verified. Reviewed clean.
  - **Task 5** added a second LiteLLM deployment
    (`openrouter/openai/gpt-4o-mini`) under the existing `openai` model_name in
    `litellm/litellm_config.yaml`, giving the `openai` alias a same-model failover pool
    ahead of the existing cross-alias `fallbacks:` chain (`openai → [claude, gemini]`,
    left untouched). Live-verified the spec's literal DoD ("kill one provider key
    mid-conversation → turn still completes via fallback, logged") against the real
    running Open stack: broke the primary deployment's key with an explicit invalid
    literal, confirmed calls kept succeeding — served via OpenRouter (`gen-`-prefixed
    response ids) vs the normal direct-OpenAI `chatcmpl-`-prefixed ids — then fully
    reverted. Log evidence (`docker logs pda-litellm`):
    ```
    LiteLLM Router:INFO router.py:2934 - litellm.acompletion(model=openai/gpt-4o-mini) Exception litellm.AuthenticationError: AuthenticationError: OpenAIException - Incorrect API key provided: sk-delib*************************************
    LiteLLM Router:DEBUG cooldown_handlers.py:216 - percent fails for deployment = 23e5d935a5138e57f3f4538011b483525ad39429e70dbcd00d44c16a25bb3fc2, percent fails = 1.0, num successes = 0, num fails = 1
    LiteLLM Router:DEBUG cooldown_handlers.py:287 - Attempting to add 23e5d935a5138e57f3f4538011b483525ad39429e70dbcd00d44c16a25bb3fc2 to cooldown list
    LiteLLM Router:DEBUG router.py:10718 - cooldown deployments: ['23e5d935a5138e57f3f4538011b483525ad39429e70dbcd00d44c16a25bb3fc2']
    LiteLLM Router:INFO router.py:2905 - litellm.acompletion(model=openrouter/openai/gpt-4o-mini) 200 OK
    ```
    Same pattern (auth failure → cooldown → routed only to the surviving deployment → 200
    OK) repeated across all 5 test calls. A genuine methodology finding surfaced: pointing
    a LiteLLM deployment's `api_key` at a nonexistent `os.environ/<var>` name does NOT
    actually break it, because the underlying OpenAI SDK auto-discovers the real key still
    present in the container's process env, bypassing LiteLLM's own unresolved reference —
    had to use an explicit invalid literal key instead to genuinely simulate a dead/revoked
    key. See Gotchas.md's 2026-08-30 entry for the full mechanism. Reviewed clean.
  - **Task 6** ran the full-suite regression pass one more time from a clean checkout
    state — **274 passed** (`cd cooper-core && .venv/bin/python -m pytest -q`), matching
    Task 3's count exactly (no code changes in Tasks 4-6). First live-verify of both
    stacks' `/health` found a real gap: Open still showed the pre-15c `classifier`/
    `utility_model` schema, not the new `roles` dict — its `cooper-core` container had
    never been rebuilt by this plan (only Task 5's `litellm` container was recreated,
    then reverted). Ruled in-scope to close rather than leave documented-but-unfixed,
    since Task 3's `/health` change applies to both workshops and "15c shipped" would
    otherwise be inaccurate for half the system. Rebuilt Open's `cooper-core` for real,
    using Task 4's proven pattern (real secrets read from the main checkout's
    `PDA-Runtime/.env` via `grep`, exported inline into the same shell command as the
    `docker compose up -d --build cooper-core` invocation — never written to disk, never
    sourced from a worktree copy). Hit one new wrinkle Task 4 didn't: the compose file
    also declares `env_file: ../litellm/.env.local` for the `litellm` service, and that
    file — also gitignored, also DO-NOT-TOUCH — doesn't exist in this worktree either, so
    `docker compose` refused to parse the file at all, for *any* targeted service.
    Temporarily commented out just that `env_file` line (docker-compose.yml is not a
    secrets file — the two-line comment-out touched no credentials) to let compose parse;
    the rebuild then succeeded, but compose's reconciliation also recreated the running
    `litellm` container (its declared config had changed) — **stripping its real
    provider keys**, confirmed live: `docker exec pda-litellm printenv | grep -c API_KEY`
    → `0`. Caught immediately via that same check, not assumed fine. Fixed by running
    `docker compose -f PDA-Runtime/docker-compose.yml up -d litellm` from the **main
    checkout** (not the worktree), where the real `litellm/.env.local` physically exists
    on disk — recreated `litellm` again with its real keys restored (`printenv | grep -c
    API_KEY` → `4`, matching pre-incident count), confirmed via a clean debug-log
    startup (`Initialized Model List [...]`, no errors) and a real authenticated round
    trip: `POST /chat` on Open replied `"OK"` with `decision:"answer"` — proof the whole
    chain (cooper-core → LiteLLM → real provider) was intact. Reverted the
    docker-compose.yml comment-out via `git checkout --`, confirmed `git diff`/`git
    status` on it both clean. Re-ran the full suite (still 274/274) and the side-by-side
    `/health` check for real:
    ```
    Private (:8000): {"status":"ok","workshop":"private","backend":"ollama","model":"COOPER-Private","roles":{"brain":"COOPER-Private","reviewer":"COOPER-Private","drafter":"COOPER-Private","archivist":"COOPER-Private"}}
    Open (:8001):    {"status":"ok","workshop":"open","backend":"openai","model":"openai","roles":{"brain":"openai","reviewer":"openai","drafter":"openai","archivist":"openai"}}
    ```
    Both stacks now genuinely show the `roles` dict live — Private all `COOPER-Private`,
    Open all `openai`, exactly as the brief expected. `docker ps` confirms both
    `pda-open-cooper-core` (healthy) and `pda-litellm` up and stable afterward.
  - Both stacks' live containers are healthy and reflect all of Tasks 1-5's changes,
    fully rebuilt where 15c's code touched them. 15c's DoD is satisfied: role→alias map
    live on both workshops (Task 1-2-3, now live-confirmed on Open too), Private E4B/12B
    split decided and live with the benchmark as its entry gate (Task 4), LiteLLM
    fallback pools live-DoD-tested (Task 5), each role provably resolves to its own
    mapped alias (Task 3's four independent module-level constants + dispatch-level
    tests, now confirmed live on both stacks' `/health`). Next: per the roadmap execution
    order, 14b.
  - **Final-review fix wave (2026-08-30):** the whole-branch review raised 4 findings;
    all 4 fixed in one wave.
    - **Finding 1 (owner decision — make it true failover):** Task 5's same-`model_name`
      pool (`openai` deployed twice — direct OpenAI + OpenRouter) defaulted to LiteLLM's
      `simple-shuffle` 50/50 load-balancing, not failover — meaning ~half of all healthy
      Open Workshop traffic would silently go through OpenRouter. **Reverted the pool**:
      `litellm/litellm_config.yaml` now has a single `openai` deployment again, with
      `openrouter` (the pre-existing standalone alias) added to the front of the
      existing cross-alias `fallbacks:` chain (`openai: [openrouter, claude, gemini]`).
      Fallbacks only ever fire on the primary's own deployment(s) failing — true
      failover-only semantics, no healthy-state OpenRouter traffic. Live-verified against
      the real Open stack (two-checkout mitigation, main checkout restored after):
      10/10 calls to `openai` served by direct OpenAI in the healthy state (zero
      OpenRouter); killing the primary key (explicit invalid literal, not a nonexistent
      `os.environ/<var>` name — see Task 5's methodology finding above) produced
      `Falling back to model_group = openrouter` in the logs and 100% successful
      completions via OpenRouter, including one native tool-calling dispatch turn
      (`finish_reason: "tool_calls"`) through the fallback path — the gap the reviewer
      flagged as untested. Reverted the key and confirmed both deployments healthy
      again; main checkout restored to original committed state.
    - **Finding 2 (owner decision — accept v1 breakage, fix the docs):** PROGRESS.md's
      Task 1 entry above corrected to name the real v1 consumers affected. Added a
      superseded notice to the top of `Documentation/PDA-Model-Routing.md`.
    - **Finding 3:** `test_execute_passes_each_role_its_own_mapped_model`
      (`cooper-core/test_main_dispatch.py`) was tautological — every role maps to the
      same alias today, so its assertions reduced to string-equals-itself. Fixed by
      monkeypatching `REVIEWER_MODEL`/`DRAFTER_MODEL`/`ARCHIVIST_MODEL` to distinct
      sentinel values before dispatch. Proved detection power: temporarily swapping
      `ARCHIVIST_MODEL`/`DRAFTER_MODEL` at their `_post_dispatch` call sites made the
      test fail (`assert 'sentinel-drafter' == 'sentinel-archivist'`); reverted and
      confirmed passing again.
    - **Finding 4:** `Documentation/PDA-Portable-Deployment.md`'s install-guide table
      still named `gemma4:12b`/~7.6GB; corrected to `gemma4:e4b-it-qat`/~6.1GB
      (verified via `docker exec pda-private-ollama ollama list`), matching what Task 4
      actually made `setup-linux.sh` pull.
    - Full suite: 274/274 passing after all four fixes.

- **2026-08-30 · 14b shipped — jobs harness mechanism live and live-verified, ships**
  **inert (`approved: false`).** 8 tasks via subagent-driven-development on
  `step-14b-jobs-harness`, each task independently reviewed clean; whole-plan review
  283/283 → 315/315 as the harness grew (`cooper-core/jobs.py`: envelope hash-pinning,
  exception queue, `run_job` orchestration, digest note; `POST /jobs/run/{job_id}` in
  `main.py`; `Config/jobs_registry.yaml`'s `link-checker` entry; `State/LinkAudit/links.csv`
  seed). Full suite at Task 8: **315 passed** (`cd cooper-core && .venv/bin/python -m
  pytest -q`) — CLAUDE.md's stale "173 tests" claim corrected.
  - **Task 4's Critical finding (fixed in-plan, `942d7d5`):** the job-runner's
    `_run_file_edit` write-scope containment had a self-cancelling-`..` bypass — a
    `write_scope` entry like `"State/LinkAudit/../../PDA-Runtime/.env"` passed both the
    string-equality check (identical to `filename`) *and* the resolve-and-contain check
    (the two `..` segments cancel back to a path still nominally under the repo root),
    while actually landing on a completely different file than what `write_scope`
    visually named. Found via live reproduction against a stand-in `.env`, closed by
    rejecting any literal `..` path segment in `filename` or any `write_scope` entry
    outright before either check runs (`executor.py::_run_file_edit`, "Check 0"). No
    legitimate job `write_scope` ever needs a `..` segment.
  - **Task 7's parked Important finding (not fixed, by design):** a pre-flight refusal
    (`verify_job` says "not approved" or "hash mismatch") returns early from `run_job`
    with **no evidence record and no exception-queue row** — nothing persisted anywhere
    — so refused runs are invisible in the digest note even though `write_digest` runs
    right after. Ruled park-don't-fix: (1) doesn't block this plan's DoD — the
    successful-run mechanism (Task 6) and the exception-queue mechanism (Task 3, proven
    live below) are both already real; (2) a clean fix needs actual design judgment
    (generate a `run_id` before `verify_job` and write a `status: "refused"` evidence
    record, which would also make the digest's dormant "needs attention" section live)
    — not a mechanical patch; (3) low stakes right now — the job ships `approved: false`
    by the owner's own decision, so "refused runs are invisible" only matters in a state
    the owner configured and already knows about. Candidate for a small follow-up once
    the job is actually approved and running for real.
  - **Task 8 — live end-to-end verification against the real running Open stack.**
    First real Docker exercise of this plan's code (Tasks 1-7 only ran the pytest
    suite) surfaced a genuine infra gap none of the first 7 tasks' scope touched:
    `PDA-Runtime/docker-compose.yml`'s `cooper-core` service never bind-mounted
    `Config/jobs_registry.yaml` or `State/` at all — `jobs.py` resolves both from
    `_REPO_ROOT` (`/app` in-container), and neither path existed in the running
    container (`docker exec pda-open-cooper-core ls /app/State` → "No such file or
    directory"). Without the mount, `POST /jobs/run/link-checker` would 404 "unknown
    job id" (registry unreadable → fail-closed empty registry) instead of the intended
    "not approved" refusal, and a real run would have no CSV to read or write. Added two
    bind mounts to `docker-compose.yml` (`Config/jobs_registry.yaml` and `State/`,
    mirroring the existing `Config/skills_registry.yaml` pattern) — mechanical plumbing
    required for code that was already built and reviewed to actually run, not a
    governance change.
    - **Rebuild hit the same worktree/compose trap 15c's Task 6 documented**
      (Gotchas.md 2026-08-30): this worktree lacks `litellm/.env.local`, so
      `docker compose` refuses to parse `docker-compose.yml` at all — for any targeted
      service — until that `env_file:` line is temporarily commented out. Followed the
      proven procedure exactly: commented it out, rebuilt `cooper-core` with real
      secrets read from the main checkout's `PDA-Runtime/.env` and exported inline,
      confirmed compose's reconciliation also recreated `litellm` and stripped its real
      keys (`docker exec pda-litellm printenv | grep -c API_KEY` → `0`), restored by
      running `docker compose ... up -d litellm` from the **main checkout** (`4` keys
      back, clean startup log, a real authenticated `POST /chat` on Open replying `"OK"`
      end to end). Hit this same litellm-recreation step **twice more** across Steps 3
      and 5 (each subsequent `cooper-core` rebuild also touched `litellm`'s config
      hash) — restored the same way each time, confirmed 4/4 keys after each. Final
      state: `docker-compose.yml`'s `env_file:` line reverted (uncommented), `git diff`
      on it shows only the two new legitimate bind-mount lines.
    - **Step 2 (refused, `approved: false`):** `curl -X POST
      http://localhost:8001/jobs/run/link-checker` → `{"status":"refused","reason":"not
      approved"}`, live, before any flag was touched.
    - **Step 3 (real run, `approved: true` flipped locally, uncommitted):** rebuilt,
      confirmed the live container's mounted registry showed `approved: true`, ran the
      job for real: `{"status":"completed","run_id":"fc7743f09388","rows_checked":3,
      "rows_changed":0,"exceptions_raised":0,"fetches_used":3,"fetches_capped":false,
      "evidence_path":"/app/State/Workflow_Evidence/completion/
      workflow_completion_link-checker_20260831T041920479Z.json"}`. Confirmed live: the
      CSV's 3 placeholder rows got real `last_checked`/`status` values, a real evidence
      record was written and passed `evidence.validate_completion`'s job-linked schema,
      and a real digest note appeared at
      `Obsidian Vault/00_Inbox/COOPER-Digest-2026-08-31.md` describing the run in prose.
      All three (CSV mutation, evidence file, digest note) were then reverted/deleted —
      test artifacts from a temporarily-flipped flag, not real production output; kept
      only in this log as evidence the mechanism ran for real.
    - **Step 4 (exception-queue path, deterministic, live):** rather than hoping the
      placeholder URLs would trigger an out-of-scope write (they can't, by
      construction), ran a small script inside the live `cooper-core` container against
      the real `cooper_memory.db`, calling `jobs.csv_line_edit(...)` with a
      deliberately-wrong `write_scope` excluding the real CSV path. Confirmed
      `executor.ExecutionError` raised (`"'State/LinkAudit/links.csv' is not in the
      caller-supplied write_scope"`), confirmed the CSV's sha256 on disk was byte-for-byte
      unchanged before and after, called `jobs.enqueue_exception(...)`, and confirmed the
      row was visible via `jobs.list_exceptions(conn, status="pending")` against the
      live DB — the spec's literal DoD line ("an intentionally out-of-scope write lands
      in the exception queue instead of happening"), live-proven. Dismissed the
      synthetic test row afterward (`jobs.resolve_exception(..., "dismissed-test-artifact")`)
      so it doesn't sit in the real pending queue or show up in a future digest.
    - **Step 5 (revert):** `git checkout -- Config/jobs_registry.yaml` (back to
      `approved: false`), rebuilt (litellm recreated + restored a third time, see
      above), confirmed `{"status":"refused","reason":"not approved"}` live again.
      Final live state confirmed: `docker exec pda-open-cooper-core grep approved
      /app/Config/jobs_registry.yaml` → `approved: false`; `docker exec pda-litellm
      printenv | grep -c API_KEY` → `4`; `docker ps` shows all Open-stack containers
      healthy/up, none left in a broken state.
    - **SSL/CA-bundle finding (Task 5's flagged concern, resolved):** Task 5's
      implementer hit `SSL: CERTIFICATE_VERIFY_FAILED` testing `url_verify` against
      `https://example.com` from their local dev `.venv` (no system CA bundle in that
      sandbox). The deployed container does **not** have this problem: the real live
      run above (Step 3) fetched 3 `https://` URLs successfully with no SSL errors, and
      a direct check confirmed a working system CA bundle
      (`/etc/ssl/certs/ca-certificates.crt` present, `ssl.get_default_verify_paths()`
      resolves, a live `httpx.get('https://example.com')` inside the container returned
      `200`). Confirmed local-dev-venv-only, not a production concern, matching what
      Task 5 predicted but couldn't itself verify.
    - **n8n scheduler workflow — built, NOT imported.** Built
      `n8n Workflow/PDA-JobScheduler-LinkChecker.json` (Cron/Schedule Trigger, daily
      03:00, matching the registry's `schedule_hint`, → HTTP Request POST to
      `http://cooper-core:8000/jobs/run/link-checker` with `httpHeaderAuth`-credential
      bearer auth — no secret embedded in the committed JSON; the owner creates the
      credential in n8n's own UI post-import), top-level `"active": false`. Attempted
      both import paths per the brief: **scripted import via n8n's REST API** — reachable
      (`curl http://localhost:5678/api/v1/workflows` → `401` unauthenticated, confirming
      the API itself is live) but the repo's on-file `n8n-api-key.txt` is rejected
      (`401 {"message":"unauthorized"}` even after stripping a stray CRLF that was
      causing a raw `400`) — stale/rotated, not usable as-is; **browser-based import via
      `claude-in-chrome`** — the Chrome extension was not connected in this session
      (`tabs_context_mcp` reported "Browser extension is not connected"), so UI import
      could not be attempted, let alone verified. Reporting both honestly rather than
      claiming either succeeded: **the workflow file exists at the specified path,
      correctly built and deactivated, but is not yet imported into the running n8n
      instance — the owner (or a future session with a working browser tool, or a
      regenerated n8n API key) still needs to do the import.**
  - **Final live state, confirmed:** `Config/jobs_registry.yaml`'s `approved` is `false`
    (committed and live-matching); the n8n workflow JSON is committed, deactivated, and
    not imported; `docker-compose.yml`'s only committed diff from before this task is
    the two new `Config/jobs_registry.yaml` + `State/` bind mounts cooper-core actually
    needs to run this job at all.
  - **Owner activation steps, in order** (this plan cannot close the spec's "≥2
    consecutive days unattended" DoD line — that clock can only start after all of
    these, and necessarily outside any single execution session):
    1. Review `Config/jobs_registry.yaml`'s `link-checker` entry (schedule, quota,
       read/write scope, `permission_level`).
    2. Replace the 3 placeholder rows in `State/LinkAudit/links.csv` with real links.
    3. Flip `approved: true` in `Config/jobs_registry.yaml` and rebuild `cooper-core`
       (its envelope hash is already pinned to the current entry — editing the CSV
       doesn't touch the hash, but editing the registry entry itself would, so flip
       `approved` last, after any registry edits, or the hash will need recomputing).
    4. Import `n8n Workflow/PDA-JobScheduler-LinkChecker.json` into the running n8n
       instance (browser: workflow menu → Import from File; or fix the stale API key
       and script it) and create the `COOPER Open API Key` `httpHeaderAuth` credential
       it references, then activate the workflow.
    5. Only then does the daily-run, multi-day observation window actually start.

- **2026-08-31 · 15d shipped — council subsystem live and live-verified against the**
  **real running Open stack.** 6 tasks on `step-15d-council-subsystem`, each
  independently task-reviewed clean. `model_routing.council_roster(workshop)` (Task 1)
  reads a new `council_roster` block in `Scripts/PDA_ModelRouting.json`; `council.py`
  (Task 2) added `critique_envelope()` (planning-time panel) and a tiered `final_review()`
  — every member call runs concurrently via `asyncio.gather`, no member sees another's
  verdict, and a broken member fails open (`verdict="pass"`, error text in `reason`) so one
  silently-broken member can never suppress a real objection from another (`has_objection`
  fires on any single flag). `evidence.py` (Task 3) validates an optional per-member
  `verdicts` array on completion records. `jobs.py`'s `run_job` (Task 4) now calls
  `council.final_review` after a job's steps complete and writes its verdicts into the
  evidence record. `POST /jobs/critique/{job_id}` (Task 5) exposes the planning-time panel
  as a standalone endpoint. Full suite at Task 5: 315 → grew task by task; **343 passed**
  confirmed again at Task 6 (below), no regressions.
  - **Design decision carried from the plan's Global Constraints (not new this task):**
    Private has exactly one real model (`COOPER-Private` / `gemma4:e4b-it-qat`, Step 15c)
    and G1 (2026-08-23) already ruled out cloud-routed planning on Private, so there is no
    local model diversity to draw a panel from. `council_roster.private` in
    `Scripts/PDA_ModelRouting.json` repeats `COOPER-Private` three times at three different
    temperatures (`council.py`'s `_MEMBER_TEMPERATURES` — behavioral spread, not true model
    diversity) rather than fabricating a roster that doesn't exist. This is the honest
    ceiling North Star's own M6 traceability note already named: *"if 4b review quality
    fails, honest ceiling is 4 — same-model review."* Open's roster is three real,
    independent providers already wired in `litellm/litellm_config.yaml`:
    `["openai", "claude", "gemini"]`.
  - **Task 6 — live end-to-end verification against the real running Open stack**
    (`.superpowers/sdd/2026-08-31-step-15d-council-subsystem/task-6-report.md` has full
    command-by-command output). Rebuilt `pda-open-cooper-core` from this worktree's code
    (`docker compose -f PDA-Runtime/docker-compose.yml ... up -d --build cooper-core`),
    hitting the same worktree/compose trap 15c Task 6 and 14b Task 8 already documented
    (Gotchas.md 2026-08-30): this worktree lacks `litellm/.env.local`, so compose refuses
    to parse the file at all until that `env_file:` line is temporarily commented out.
    Fixed exactly as documented, and confirmed the collateral damage recurred as expected
    — compose's reconciliation also recreated the already-running `litellm` and stripped
    its 4 real provider keys (`docker exec pda-litellm printenv | grep -c API_KEY` → `0`),
    restored by re-running `up -d litellm` from the **main checkout** (`4` keys back,
    confirmed via a real authenticated `POST /chat` reply through cooper-core → LiteLLM →
    provider). **New wrinkle beyond the existing Gotcha, found and worked around live —
    now documented as its own entry, Gotchas.md 2026-08-31:** this worktree also lacks
    `PDA-Runtime/.env` itself (not just `litellm/.env.local`), and `cooper-core`'s own
    service block interpolates its secrets directly (`${COOPER_API_KEYS:-}`,
    `${LITELLM_MASTER_KEY:-cooper-local}`) rather than via `env_file:` — so compose
    doesn't hard-fail on the missing file, it silently substitutes the insecure
    `"cooper-local"` default with no build-time error, which would have broken both real
    client auth and cooper-core→LiteLLM calls on the live container. Fix: pass `--env-file
    <main-checkout>/PDA-Runtime/.env` (path only, never read) on every compose invocation
    against the worktree — verified via a `docker compose config` dry-run before `up`, and
    confirmed live via a real `POST /chat` reply and matching `API_KEY` counts throughout
    (open cooper-core `3`, litellm `4`, unchanged from baseline). Full mechanism, dry-run
    output, and takeaway: Gotchas.md's 2026-08-31 entry.
    - **Step 2 (planning-time critique on a seeded flaw):** added a throwaway
      `15d-test-flawed-envelope` job (`permission_level: 3`, `write_scope: ["/"]` —
      deliberately over-broad) to `Config/jobs_registry.yaml`, restarted cooper-core,
      called `POST /jobs/critique/15d-test-flawed-envelope`. Real result: `"objection":
      true`, all 3 Open roster members flagged it —
      openai: *"write_scope is broader than necessary"*; claude: *"write_scope grants root
      write access but permission_level 3 is too low for filesystem writes and steps only
      contain noop which needs no write access"*; gemini: *"write_scope is broader than job
      purpose needs for a noop step"*. The note landed at
      `Obsidian Vault/00_Inbox/COOPER-Job-Critique-15d-test-flawed-envelope.md` with the
      same 3/3-flagged verdict summary.
    - **Step 3 (passing L4+ job, named per-member verdicts in evidence):** replaced it
      with `15d-test-l4-job` (`permission_level: 4`, `approved: true`, empty scopes,
      `steps: [noop]`, real `envelope_hash` computed via `jobs.compute_envelope_hash`),
      restarted cooper-core, called `POST /jobs/run/15d-test-l4-job` → `"status":
      "completed"`. The written evidence record
      (`State/Workflow_Evidence/completion/workflow_completion_15d-test-l4-job_*.json`)
      carried a real `"verdicts"` array with exactly 3 entries — `openai`, `claude`,
      `gemini` — each with a non-empty `member`, `verdict` (all `"flag"` this run, since 0
      rows were processed — a legitimate reviewer finding, not a harness bug) and a
      `reason` (e.g. claude: *"zero rows checked indicates job did not execute or found no
      data to process"*). Proves the tiered `final_review` → evidence-write path end to
      end, with `steps: [noop]` and empty scopes meaning zero risk of the job's own
      `run_job` loop touching any real file.
    - **Step 4 (revert):** `git checkout -- Config/jobs_registry.yaml` and `git checkout --
      PDA-Runtime/docker-compose.yml` both confirmed clean via `git status --short`; the
      critique note and the synthetic evidence file both deleted; also deleted an
      unanticipated but expected byproduct — cooper-core's own daily digest note
      (`Obsidian Vault/00_Inbox/COOPER-Digest-2026-08-31.md`), auto-written by the run in
      Step 3 and referencing only the synthetic job, so it was cleaned up too even though
      the brief's Step 4 didn't name it explicitly. cooper-core restarted, `/health` still
      `ok`, `open-cooper-core`/`litellm` API-key counts still `3`/`4` (unchanged from
      baseline throughout).
    - **Step 5:** full suite re-run clean from the reverted state: **343 passed**
      (`cd cooper-core && .venv/bin/python -m pytest -q`) — CLAUDE.md's stale "315 tests"
      claim corrected to 343 as part of this task's Step 6.

---

## Blocked / needs owner input

Governance gates from the Step 15 spec §6 — each blocks only its named slice:

- ~~**G1**~~ **DECIDED 2026-08-23: No** — see decision log. Private plans locally with gemma4.
- ~~**G2**~~ **DECIDED 2026-08-23: keep gpt-4o-mini** (brain and initial 15c planner alias) — see decision log.
- ~~**G3**~~ **DECIDED 2026-08-23: Yes** — session-plans amendment enacted; 15h unblocked.
- ~~**G4**~~ **DECIDED 2026-08-23: Open only** — Private gets no web search; revisitable later by owner choice. 14c fully unblocked.
- ~~**G5**~~ **CLOSED 2026-08-23:** dashboard key limit set to $15 lifetime (never resets, verified live via `/api/v1/auth/key`: `limit_reset: null`, $7.91 already counted → ~$7.09 headroom); auto top-up off. Burn alert (trigger: remaining < $5) joins the digest job at 14b.
- **14f — PINNED (owner direction 2026-08-23):** the home-lab network is not built yet. Not a decision gate anymore — a placeholder: when the home-lab project starts, revisit the data-source choice (router syslog / Pi-hole / other) and integrate COOPER then.
- **15e scope — PAUSED 2026-08-31, awaiting owner decision, not a formal G-gate.** Research
  is done (spec fully read: `Docs/superpowers/specs/2026-08-18-step-15-max-metrics-design.md`
  §3's 15e row + target architecture diagram; no G1-G5 gate blocks it — G1/G2 already decide
  two of its sub-questions). No plan file or code written yet. The open question: 14b's
  `run_job` is hardcoded to one job shape (CSV read → URL check → write back) and does not
  generically dispatch a job's declared `steps` field. The spec's literal target architecture
  wants a genuinely generic executor: an LLM interprets each drafted step's natural-language
  instructions via the existing tool registry (`executor.py`) at runtime, bounded only by the
  envelope's read/write scope + quota + exception queue enforced in code, with **no per-step
  human approval** — real autonomous tool execution, a materially larger and more
  security-sensitive surface than 15a-15d. Options put to the owner: (a) **narrow** — the
  planner only drafts new jobs of the same shape `run_job` already knows how to execute
  (parameterized CSV-monitor jobs); no new autonomous tool-calling surface, satisfies a
  literal reading of the DoD without the security lift. (b) **full spec** — build the
  generic step-executor per the target architecture diagram; matches the DoD and the M2
  metric target (3→4) as written, but needs careful scoping of which tools/permission
  levels it may touch unattended before implementation starts. (c) discuss further. Next
  session resumes by asking the owner to choose, then (if (a) or (b)) writes and runs a full
  implementation plan the same way 15d was executed (subagent-driven-development, live
  verification against the real running Open stack, final whole-branch review).
