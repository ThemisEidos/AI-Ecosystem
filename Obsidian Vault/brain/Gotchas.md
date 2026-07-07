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

### 2026-07-02 · check_tool() is now FAIL-CLOSED for untagged tools

Supersedes the 2026-07-01 entry "workshop.check_tool() is permissive for tools with no workshop field". As of the audit-remediation branch, a tool without a `workshop:` field raises WorkshopViolation. Every tool in both registry YAMLs must carry a workshop tag or it will not run.

### 2026-07-02 · Dead uvicorn reloader leaves an orphaned worker serving :8000 — Docker publish silently loses

Killing the uvicorn --reload parent (or it dying) does NOT stop the worker child, which
inherited the socket and keeps serving. Get-NetTCPConnection then shows the LISTEN owned by a
nonexistent PID. Worse: if a container publishing 8000 starts while this zombie holds the port,
Docker Desktop's proxy fails to bind WITHOUT any compose error — your "container" requests hit
the old Windows server. Detection: response contained Windows-only state (Host: ID6, skill
history a fresh container DB couldn't have). Fix: `Get-Process python | Stop-Process -Force`,
then `docker restart pda-private-cooper-core` to rebind. Always verify which backend answered
via `docker logs` before trusting container test results.

### 2026-07-02 · Microsoft apt repo unusable on Debian 12+ images — SHA1 signature rejected since 2026-02

apt now hard-rejects SHA1 release signatures ("SHA1 is not considered secure since
2026-02-01"), and packages.microsoft.com/debian still signs with SHA1. Installing pwsh via the
packages-microsoft-prod.deb route fails with exit 100 regardless of gnupg. Use the official
GitHub release tarball + `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` (skips libicu). See
cooper-core/Dockerfile.

### 2026-07-02 · gemma4:12b in containerized Ollama needs the GPU reservation block

Without `deploy.resources.reservations.devices` on private-ollama, inference runs CPU-only:
>5 min per /chat turn (classifier times out → "classifier error (safe fallback)"). With the
nvidia block + RTX 3050 Ti (4 GB, partial offload of the 7.6 GB model): ~3 min cold load,
~90 s warm. First request after container start will likely still hit the classifier timeout —
treat the first turn as a warmup.

### 2026-07-07 · Private-stack timeouts traced to host-wide memory pressure, not model/GPU sizing

A live `/chat` test appeared to hang/error (2-4+ min, ending in `"classifier error (safe
fallback)"`), and `docker logs pda-private-ollama` showed only 7/49 model layers offloaded to
the GPU at 0.19 tokens/sec — this initially looked like `gemma4:12b` (7.6 GB) simply not fitting
the RTX 3050 Ti's 4 GB VRAM. **That diagnosis was wrong, corrected after user pushback** ("I was
talking to cooper-private fine earlier, my hardware is fine — what changed?"). The actual cause:
Windows had only 1.2 GB free out of 15.7 GB total at the time, `vmmemWSL` (Docker Desktop's
WSL2 VM) alone was using 6.5 GB, and WSL2's own internal memory was full (7.6 GB total, swap
100% used) — root-caused to two extra background `claude` CLI subagent processes plus a second
full Claude Code CLI session running concurrently in the same WSL2 VM. The 8.9 GB-resident model
was swapping to disk for lack of headroom (196 GB of block I/O on the container), not failing to
fit on the GPU. The ~90s warm figure above may still be accurate under normal memory
conditions — it was never actually invalidated, the test environment was just abnormally
memory-starved. Lesson: before concluding a performance regression is architectural (model size,
GPU capacity), check host-wide resource pressure first, especially when other heavy sessions
(other Claude Code instances, other Docker stacks) may be running concurrently.
