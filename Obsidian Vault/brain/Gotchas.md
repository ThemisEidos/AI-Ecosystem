# Gotchas — Known Traps and Environment Quirks

> Updated 2026-07-01. Append new entries with `### YYYY-MM-DD · <title>`.

---

### 2026-07-01 · asyncio subprocess is broken on Windows uvicorn

`asyncio.create_subprocess_exec` produces empty-string exceptions inside uvicorn's ProactorEventLoop on Windows. No error message — the exception `str()` is `""`. Fix: use `loop.run_in_executor(None, _sync_run)` + `subprocess.run` in a thread pool. See `cooper-core/executor.py`.

### 2026-07-01 · cmd.exe set X=val && adds trailing space to env var

`set WORKSHOP=private &&` sets the value to `"private "` (note the space), not `"private"`. This caused workshop detection to fall back to "open" (OpenAI). Two-part fix: (1) use quoted syntax `set "WORKSHOP=private"` in `Start-CooperCore.ps1`; (2) add `.strip()` on the `os.environ.get("WORKSHOP", "open")` read in `main.py`.

### 2026-07-01 · uvicorn --reload unreliable across DrvFs boundary

Files edited from WSL2 on a Windows-mounted path (`/mnt/d/...`) don't trigger uvicorn's StatReload file watcher reliably. The watcher detects the change but fails to respawn the worker. Fix: use `Start-CooperCore.ps1` to force a clean restart (kills by port first, then relaunches).

### 2026-07-01 · Unicode characters crash Windows cp1252 at FastAPI startup

Print statements with Unicode symbols in the FastAPI lifespan handler crash startup on Windows (cp1252 encoding cannot encode non-ASCII). Fix: use ASCII equivalents `[!!]` and `[ok]`. See `main.py` lifespan handler.

### 2026-07-01 · Test-PDAStack.ps1 times out when Docker is not running

`Scripts/Test-PDAStack.ps1` requires live Docker containers. Hangs for 60s then fails if Docker isn't active. Use `Scripts/Test-Exec.ps1` instead — self-contained fast-exit, no Docker dependency.

### 2026-07-01 · "give me a status summary" classifies as answer not dispatch

The classifier sees this as an information request. Use "run a status summary" (explicit "run" verb + named noun) to trigger dispatch classification reliably.

### 2026-07-01 · Open WebUI stores connections in SQLite (env vars ignored after first run)

Open WebUI v0.9.6 writes the API connection to SQLite on first run. After that, docker-compose.yml env vars for API URL/key are ignored. Manual setup: Settings → Connections → + → URL `http://host.docker.internal:8000/v1`, Key `cooper-local`.

### 2026-07-01 · gemma4:12b runs extended reasoning by default (40-53s per call)

Without `"think": false` in the Ollama API payload, gemma4:12b activates extended reasoning. Always include `"think": False` in all Ollama payloads. See `decision.py` `_ollama_complete` and `_stream_ollama_chat`.

### 2026-06-30 · WSL2 mirrored networking requires wsl --shutdown to activate

`~/.wslconfig` with `networkingMode=mirrored` is inert until WSL restarts. Run `wsl --shutdown` from Windows, wait ~8s, reopen. Confirm with `wslinfo --networking-mode` (must print `mirrored`).

### 2026-07-01 · workshop.check_tool() is permissive for tools with no workshop field

If a tool in the registry has no `workshop` field (or an empty string), `check_tool()` passes it through without raising. This is intentional — PS-era tools in the registry predate workshop tagging. Do not rely on `check_tool()` to enforce boundaries for untagged tools. Tighten by adding `workshop` fields to the registry in step 9.

### 2026-07-01 · BACKEND is a module-level constant — restart required for WORKSHOP changes

`BACKEND` is set once at startup from the `WORKSHOP` env var. `check_backend` fires per-request but compares against the startup-time value. A live env var change (without server restart) won't update `BACKEND`. If `WORKSHOP` is changed, kill python processes and run `Start-CooperCore.ps1` again.

### 2026-06-29 · ECC GateGuard blocks first Write/Edit to each new file this session

GateGuard requires facts (callers, no duplicate, data schemas, verbatim instruction) before the first creation of each new file per session. Present facts inline in the message text, then retry the identical tool call.
