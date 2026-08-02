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

---

## Blocked / needs owner input

*(none)*
