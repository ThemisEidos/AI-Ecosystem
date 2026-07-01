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
- [ ] **Step 7 — Sub-agent review loop.** Worker → reviewer → governor. DoD: a dispatched task is checked by a reviewer agent before results reach you.
- [ ] **Step 8 — Memory + skill loop.** ChromaDB + Obsidian brain read each turn; successful tasks abstracted into scored, versioned skills. DoD: COOPER recalls a prior decision and reuses a saved skill at runtime.
- [ ] **Step 9 — Dockerize + portability.** DoD: `docker compose up` brings COOPER fully online on a fresh checkout.

**Current step: 7 — Sub-agent review loop**

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
- **2026-06-30 · `WORKSHOP` env var now stripped in `main.py`** — cmd.exe `set WORKSHOP=private &&` adds a trailing space, so `"private " != "private"` and the server fell back to open/OpenAI. Added `.strip()` to `os.environ.get("WORKSHOP", "open").strip().lower()` as a defensive fix alongside the quoted `set "WORKSHOP=..."` in the launcher.
- **2026-06-30 · `think:false` added to all Ollama calls** — `gemma4:12b` runs extended reasoning by default, adding 40-53s per call (measured). With `think:false` in the payload, classifier calls drop to ~10s. Added to `_ollama_complete` and `_stream_ollama_chat` in `decision.py`.
- **2026-07-01 · `registry.py` added as Quartermaster (step 3)** — workshop-scoped YAML reader with mtime-based cache (edits to YAML take effect without server restart under `--reload`). `GET /tools` endpoint returns the live registry JSON. Registry-query detection (`is_registry_query()`) short-circuits LLM calls for "what tools are available?" style messages — answered instantly from the YAML. Tool selection is bag-of-words keyword-overlap only — known limitation to revisit if step 5 needs better intent matching.
- **2026-07-01 · `executor.py` added as Workbench gateway (step 5)** — PowerShell executor resolves `.ps1` filenames from user message against `Scripts/` on disk (no arbitrary paths, no path traversal via `relative_to()` guard). Uses `loop.run_in_executor()` + `subprocess.run` (thread pool) rather than `asyncio.create_subprocess_exec` — the asyncio subprocess protocol had empty-exception failures inside uvicorn's event loop on Windows. Tries `powershell.exe` first (always present), then `pwsh`. Hard timeout 60s, output capped 8 KB. `approval.py` refactored: `resolve()` replaced by `consume()` + `is_approved()` + `is_denied()` so `main.py` owns the execute-vs-cancel decision with the full ticket context. `_resolve_approval()` added to `main.py` as the approval-gate resolution path that calls `_execute()` rather than returning a stub. `Scripts/Test-Exec.ps1` added as a fast, self-contained execution verification script (no Docker required).
- **2026-07-01 · `approval.py` added as Safety Officer (step 4)** — L2+ (or any `approval_required: true` tool) halts with a single-use ticket and a 10-minute TTL. Approve/deny detected via regex short-circuit ahead of the classifier so "yes"/"no" replies aren't misclassified as new dispatch requests. Dispatch-reply construction moved out of `decision.py` into an async `dispatch_handler` callback owned by `main.py`, keeping `decision.py` registry/approval-agnostic. Approval state is in-memory and single-ticket-per-workshop — deliberate simplification for a single local user; will not survive a server restart and cannot handle concurrent pending actions.
- **2026-07-01 · `workshop.py` added as workshop enforcer (step 6)** — stateless enforcement layer with two functions: `check_backend(backend, workshop)` blocks Private Workshop + OpenAI backend combinations; `check_tool(tool, workshop)` blocks tools whose `workshop` field mismatches the active workshop, and blocks `_CLOUD_EXECUTORS = {browser, llm_api}` in Private Workshop regardless of registry settings. `check_backend` fires at startup (print-only, doesn't block server start) AND per-request in `_handle_dispatch` (returns conversational `WorkshopViolation` message, not HTTP 500). `GET /workshop` added for live boundary observability. Tool `workshop` field matched case-insensitively with " Workshop" suffix stripped — a tool with no `workshop` field passes the check (permissive default for PS-era tools not yet tagged).

---

## Blocked / needs owner input

*(none)*
