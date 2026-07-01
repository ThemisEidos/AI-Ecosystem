# Patterns — Confirmed Implementation Approaches

> Updated 2026-07-01. Append new entries with `### YYYY-MM-DD · <title>`.

---

### 2026-07-01 · Windows subprocess from FastAPI: thread pool, not asyncio

Use `loop.run_in_executor(None, _sync_run)` with `subprocess.run` inside a thread pool instead of `asyncio.create_subprocess_exec`. The asyncio subprocess protocol is unreliable in uvicorn's ProactorEventLoop on Windows. Try `powershell.exe` first (always present), then `pwsh` as fallback. See `cooper-core/executor.py`.

### 2026-07-01 · Script path security: relative_to() guard

Validate resolved script paths against the Scripts/ base directory with `candidate.relative_to(_SCRIPTS_DIR.resolve())`. This raises `ValueError` if a crafted path escapes Scripts/. Use `.name` only (not the full token) when constructing the candidate path to strip any directory components from user input.

### 2026-07-01 · Approve/deny messages: regex short-circuit before classifier

Check `approval.has_pending(WORKSHOP) and approval.is_response(message)` at the top of every chat endpoint BEFORE calling `route_turn`. If "yes"/"no"-style replies go through the classifier they will be misclassified as new dispatch requests. Order: registry query check → approval response check → classifier.

### 2026-07-01 · dispatch_handler async callback keeps decision.py agnostic

Pass dispatch logic as `dispatch_handler: Optional[Callable[[str], Awaitable[str]]]` to `route_turn` and `route_turn_stream`. This keeps `decision.py` unaware of registry, approval, and executor — all three live in `main.py`.

### 2026-07-01 · Registry mtime cache: edits take effect without server restart

Cache the YAML registry with a `(mtime, data)` tuple. On each `list_tools()` call, stat the file — if mtime matches, return cached data; otherwise reload. Live YAML edits visible without restart under `--reload` (subject to DrvFs watcher caveat — see Gotchas.md).

### 2026-07-01 · Bag-of-words tool selection

`registry.select_tool()` tokenizes the user message and each tool's name/description/drawer on whitespace, computes intersection, and returns the tool with highest overlap. Simple and predictable — user must use words from the tool's name/description. Does not handle synonyms.

### 2026-06-29 · Few-shot classifier prompt beats rule-list prompt

The classifier uses 10 labeled examples rather than a list of rules. Rule-list prompts caused gemma4:12b to ignore "dispatch even when exact path is unspecified" and return `clarify` for named-noun imperatives. Examples calibrate the model reliably.

### 2026-06-30 · WORKSHOP env var: always .strip().lower() at read time

`os.environ.get("WORKSHOP", "open").strip().lower()` — `.strip()` defends against cmd.exe trailing-space injection; `.lower()` normalizes capitalization. Belt-and-suspenders alongside the quoted `set "WORKSHOP=..."` in Start-CooperCore.ps1.

### 2026-06-28 · Open WebUI wiring: manual connection, not env var

After first run, Open WebUI reads connections from SQLite, not env vars. Add once via Admin Panel → Settings → Connections → + (URL: `http://host.docker.internal:8000/v1`, Key: `cooper-local`). Env vars in docker-compose.yml remain as fallback for fresh installs only.
