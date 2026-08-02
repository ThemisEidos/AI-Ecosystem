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

### 2026-07-07 · `docker compose up -d --force-recreate <service>` doesn't reliably re-read an external `env_file`

Editing `litellm/.env.local` (referenced via `env_file:` in `docker-compose.yml`, not a bind
mount) and then running `docker compose up -d --force-recreate litellm` did not pick up the
change — `docker exec pda-litellm printenv OPENAI_API_KEY` still showed the pre-edit value.
Compose appears to decide whether to recreate a service based on its own config hash, which
doesn't change when only an externally-referenced env file changes, so `--force-recreate`
recreated the container but reused a cached environment resolution. Fix: a full teardown —
`docker compose stop <service>` then `docker compose rm -f <service>` then `docker compose up -d
<service>` — forces a fresh `env_file` read every time. `--force-recreate` is not equivalent to
this for env-file-only changes, even though it destroys and recreates the container. Same class
of staleness as the documented Docker Desktop/WSL2 bind-mount caching gotcha (2026-07-02), but a
different mechanism (compose-level recreate logic, not the container filesystem layer) — don't
assume `--force-recreate` alone is sufficient after any external-file edit; verify the loaded
value directly (`docker exec <container> printenv <VAR>`) before trusting a restart worked.

### 2026-07-07 · LiteLLM `main-latest` proxy needs `allow_requests_on_db_unavailable: true` with no DB configured

Without a database configured, this project's LiteLLM proxy image intermittently rejected valid
master-key Bearer auth with `{"type":"no_db_connection","message":"No connected db."}` — not
consistently reproducible on every request, which made it look like a race condition before the
actual mechanism (DB-backed virtual-key lookup with no DB present) was identified. Fixed by
adding to `litellm_config.yaml`:
```yaml
general_settings:
  allow_requests_on_db_unavailable: true
```
After adding this, 3/3 consecutive requests succeeded where before it failed unpredictably.
Master-key-only auth (the only auth mode this single-user local deployment uses) is unaffected.

### 2026-07-08 · `docker compose up -d` silently reuses a stale built image after source changes

Rebuilding cooper-core's session-binding code and running `docker compose up -d cooper-core`
against an already-built image does NOT rebuild it — Compose only rebuilds on an explicit
`docker compose build` (or `up --build`), never automatically just because the build context's
source files changed. A running container kept serving pre-Task-2 code (old single-key auth,
old error message) for several minutes after the code changed, with `up -d` reporting success
each time. Caught only because a live two-client test produced the OLD `_check_auth_config`
error text instead of the new one. Always `docker compose build <service>` (or `up -d --build`)
after editing anything under a service's build context before trusting a live test against it —
`up -d` alone is not evidence the running container reflects current source.

### 2026-07-08 · `git diff`'s mode-conflict display under DrvFs is noise, not a real conflict

Mid-rebase, `git diff` on an unmerged path showed `mode 100644,100644..100755` for a file
neither side actually changed the mode of. `git ls-files -s <path>` confirmed all three merge
stages were genuinely `100644` — the `755` was `git diff` reflecting the *working tree* file's
apparent executable bit, and every file on this repo's `/mnt/d` DrvFs mount reports `777` to
Linux regardless of real Windows permissions (`stat -c "%a"` on totally ordinary files showed
`777`). `core.fileMode=false` is already set in this repo specifically to make git ignore this
noise for diffing/staging — so a real `git add` on such a conflict does NOT pick up a mode
change, only the display did. Don't chase a "mode conflict" on this repo without first checking
`git ls-files -s` for the actual staged modes; if `core.fileMode` is `false`, filesystem-reported
permissions are cosmetic only.

### 2026-07-08 · Parallel worktree's base branch can move while you're mid-task — check before assuming your rebase is a no-op

A plan built for a parallel-worktree task (Step 13, branched from `step-9-dockerize`) explicitly
deferred one of its own tasks "until Step 12 merges" — but nothing re-checked whether that had
actually happened by the time execution reached that point. It had: Step 12 (built in a sibling
worktree) merged into `step-9-dockerize`'s tip mid-session, refactoring shared code
(`main.py`'s `chat()`/`oai_chat()`/`_stream_sse()` into one `_chat_core()`) that the in-flight
branch's own already-committed, already-reviewed work then conflicted with on rebase. Lesson:
when a plan says "do X after branch/step Y merges" and Y is being built concurrently in a
sibling worktree, re-check `git log --oneline <base>..<sibling-branch>` (or just `git branch -a`
+ `git log <base> -1`) immediately before executing that deferred task — don't assume the base
you originally branched from is still the tip of the integration branch. The conflict itself was
mechanical to resolve once found, but discovering it required noticing the mismatch, not just
trusting the plan's own "not yet merged" framing written before either branch existed.

### 2026-07-08 · A "well-known default key" left valid after a real key is generated defeats per-client isolation

`install-cooper.sh` generated a real per-install `COOPER_API_KEYS` value, but both compose files
still defaulted the legacy singular `COOPER_API_KEY` to the literal `cooper-local` via
`${COOPER_API_KEY:-cooper-local}` — and `${VAR:-default}` treats an *explicitly empty* value the
same as *unset*, so simply having the bootstrap script write `COOPER_API_KEY=` (empty) would NOT
have suppressed the fallback. Fixed by switching to the single-dash `${VAR-default}` form (only
defaults when the var is truly absent, not when present-but-empty) in both compose files' `
COOPER_API_KEY` line AND in `open-webui`'s own hardcoded `OPENAI_API_KEY=cooper-local` fallback
(which needed to become `${COOPER_API_KEY-cooper-local}` too — otherwise Open WebUI's own
fresh-install connection stays wired to the now-dead literal). A whole-branch review is what
caught this, not the per-task reviews — each task's diff looked correct in isolation; the gap
only existed at the intersection of "script generates a key" + "compose still defaults to the
old one" + "a second service hardcodes that same old default independently." Worth checking for
this pattern (a new credential mechanism added alongside an old one that was never actually
retired) whenever a bootstrap/install script's whole point is to replace a shared default.

### 2026-08-02 · git clone hangs machine-wide when hostname lookup stalls

Every `git clone` on the laptop (local file paths AND network) hung indefinitely mid-session — including the full pytest suite (tap-import tests clone) and even Claude's plugin updater. Root cause chain: `git clone` without explicit committer ident DNS-canonicalizes the machine hostname; `pop-os` is NOT in `/etc/hosts` (Pop!_OS normally seeds `127.0.1.1 pop-os`); nsswitch routes the query to systemd-resolved (`resolve [!UNAVAIL=return]` sits BEFORE `myhostname`, which would answer instantly); resolved's Global upstream is `127.0.0.1:53`, which listens but never answers, and the DHCP search domain gets appended — result: infinite stall, not fast NXDOMAIN. Started mid-session (~08:30) after a network/DHCP change; `git commit`/`status` unaffected (repo has user config), Docker containers unaffected (Docker writes the container hostname into the container's /etc/hosts).

**Repo-side fix (done):** `cooper-core/conftest.py` pins `GIT_AUTHOR_*`/`GIT_COMMITTER_*` env for the suite — clone-based tests are now hermetic against machine name resolution.

**Machine-side fix (needs owner sudo):** add the hostname to /etc/hosts:
`echo "127.0.1.1 pop-os" | sudo tee -a /etc/hosts` — and separately investigate what listens on 127.0.0.1:53 and why resolved's Global DNS points at it.

Diagnostic trail: `getent hosts pop-os` hangs while `getent hosts github.com` works; `GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t git clone …` succeeds instantly.
