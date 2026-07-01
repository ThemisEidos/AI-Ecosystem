# Key Decisions — Binding Architectural Choices

> Updated 2026-07-01. Append new entries with `### YYYY-MM-DD · <title>`.
> Full decision log with rationale: PROGRESS.md "Decisions log" section.

---

### 2026-06-28 · FastAPI runs on Windows, not WSL2

Ollama binds to Windows loopback (`127.0.0.1:11434`). WSL2 with NAT networking cannot reach Windows loopback by default. FastAPI must run via Windows PowerShell (`.venv-win`) to reach Ollama directly. WSL2 mirrored networking (`networkingMode=mirrored`) provides the reverse path (WSL2 curl → Windows `localhost:8000`).

### 2026-06-28 · Model name is COOPER, not cooper-personality

Canonical model is `COOPER:latest` (built from `Models/cooper-personality/Modelfile`, base: gemma4:12b). `main.py` default `COOPER_MODEL=COOPER` is correct.

### 2026-06-28 · Old PowerShell bridge left in place until FastAPI proves in browser

`Scripts/Start-PDAWebhookServer.ps1` and all existing PS scripts are untouched. Retire only after FastAPI is confirmed working in Open WebUI browser. Do not modify them.

### 2026-06-29 · Classifier model is gemma4:12b (not gemma3:12b)

Model was updated at some point prior to the FastAPI rebuild. Health endpoint confirms `classifier: gemma4:12b`. All code and docs reflect this.

### 2026-06-29 · Classifier prompt: few-shot 10 examples, not rules

Rule-list prompts failed for named-noun imperatives without exact paths. 10 labeled examples calibrate the model reliably. See `decision.py` `_CLASSIFIER_SYSTEM`.

### 2026-06-29 · Security hardening applied

Bearer token auth (`COOPER_API_KEY` env var, dev mode open if unset), message/history field validation, 500-char history truncation before classifier (prompt injection guard), role allowlist, 422 errors on bad input. Applied to `main.py` and `decision.py`.

### 2026-06-30 · think:false in all Ollama calls

gemma4:12b runs extended reasoning by default (40-53s/call). `"think": False` drops classifier calls to ~10s. In `decision.py` `_ollama_complete` and `_stream_ollama_chat`.

### 2026-06-30 · Start-CooperCore.ps1: ProcessStartInfo with cmd.exe wrapper

`Start-Process` does not reliably pass env vars to detached children on PS 5.1. Uses `[System.Diagnostics.Process]::Start()` with cmd.exe wrapper, quoted `set "WORKSHOP=private"` syntax. Accepts `-Workshop private|open` (default `private`).

### 2026-07-01 · Approval state: in-memory, single-ticket-per-workshop, 600s TTL

Deliberate simplification for a single local user. Does not survive server restart. Will scale at Step 7.

### 2026-07-01 · workshop.py: stateless enforcement layer (step 6)

`workshop.py` added as a pure enforcement module — no side effects, no state, raises `WorkshopViolation` or returns `None`. Three enforcement points: (1) tool compatibility — tool's `workshop` field must match active workshop; (2) executor safety — `{browser, llm_api}` always blocked in Private Workshop; (3) backend integrity — `private + openai` hard-blocked per-request, not just at startup. `check_backend` fires in lifespan (informational print) AND in `_handle_dispatch` (conversational reply, not 500). Tool `workshop` field matched case-insensitively, " Workshop" suffix stripped — tools with no field set pass (permissive default, tighten at step 9). `GET /workshop` added for live observability.

### 2026-07-01 · executor.py: thread pool subprocess, path traversal guard

asyncio subprocess broken on Windows uvicorn. Hard timeout 60s, output cap 8KB. Path traversal prevented via `candidate.relative_to(_SCRIPTS_DIR.resolve())`. Requires explicit `.ps1` filename in user message.
