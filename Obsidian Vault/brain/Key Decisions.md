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

### 2026-07-01 · Steps 1-5 review found the blocking chat path had no LLM-failure handling

`decision.py`'s `_classify()` already caught every exception and fell back to `answer`, but the `clarify` and `answer` branches of `route_turn()` (used by non-streaming `/chat` and `/v1/chat/completions`) called `_clarify()`/`generate_answer()` with no try/except at all — a backend hiccup (Ollama restart, timeout, bad response) crashed the request with a raw 500. The streaming path (`_stream_sse`) already handled this correctly, which is what exposed the asymmetry. Fixed by wrapping both branches the same way, returning `"[COOPER error: backend unavailable — {exc}]"` instead of raising. Same review pass added auth to `/v1/models` (was the only endpoint missing `_require_auth`) and wrapped `registry.py`'s YAML parsing in try/except (was the only registry failure path not raising `RegistryError`).

### 2026-07-01 · Step 8 memory storage: SQLite FTS5 + Obsidian markdown, not ChromaDB

PRD names ChromaDB, but neither comparable project the PRD itself cites actually uses a vector DB. Hermes Agent's most advanced tier ("Holographic Memory") is SQLite + FTS5 + HRR (Holographic Reduced Representations) algebra — fully local, no embedding model, no network call. Agentic OS pairs a markdown `brain/` folder (source of truth, same pattern as this repo's `obsidian-mind` install) with "Hermes SQLite FTS5" for the queryable layer. Decision: `Obsidian Vault/brain/` stays the durable source of truth; a new SQLite DB in `cooper-core/` (FTS5-indexed) becomes the queryable decision/skill store. No ChromaDB, no embedding model dependency — only `sqlite3` (stdlib). Schema reserves a `hrr_vector BLOB NULL` column so Hermes-style holographic recall can be bolted on later without a rewrite; deferred past Step 8's DoD since a small memory corpus doesn't yet benefit from fuzzy vector recall.

### 2026-07-01 · Step 8 (Archivist) verified live

Both DoD scenarios confirmed against the running server, no code changes needed. Skill reuse: dispatching `run Test-Exec.ps1` twice (approve, then dispatch again) produced a second halt reply with `"(matches a proven skill — 1 successful run, 100% trust)"` appended — the skill was scored after the first approved run and surfaced on the very next dispatch. Decision recall: `"have we run Test-Exec.ps1 before, what happened?"` returned `decision:"answer"` with a reply that named the host, confirmed success, and added a contextual note about preferring `Test-Exec.ps1` over `Test-PDAStack.ps1` — pulled from the `decisions` table via `archivist.recall()`, not a generic non-answer. `_fts_query()` and `_EXTRACT_SYSTEM` needed no tuning; both scenarios passed on the first live attempt.
