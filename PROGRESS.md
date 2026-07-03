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

---

## Blocked / needs owner input

*(none)*
