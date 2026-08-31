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

### 2026-08-04 · A wrong key in Open WebUI shows an EMPTY model dropdown, never an error

Open WebUI was wired to `http://cooper-core:8000/v1` with the wrong key (an OpenAI `sk-proj-…`
pasted where the 39-char `cooper-…` key belongs). The UI showed no error, no toast, no red
banner — just a model dropdown with nothing in it, which reads like "the server is down" rather
than "auth failed". The only evidence is server-side:
`docker logs pda-open-cooper-core | grep 401` → `"GET /v1/models HTTP/1.1" 401 Unauthorized`
from the open-webui container's IP.

**Debug order that works** (each layer independently, don't guess): (1) host →
`curl localhost:8001/v1/models -H "Authorization: Bearer $KEY"`; (2) container DNS →
`docker exec pda-open-webui sh -c 'curl -s http://cooper-core:8000/v1/models -H "Authorization: Bearer <key>"'`;
(3) what Open WebUI actually stored →
`docker exec pda-open-webui python3 -c "import sqlite3,json; c=sqlite3.connect('/app/backend/data/webui.db'); print(json.loads(c.execute('select data from config order by id desc limit 1').fetchone()[0])['openai'])"`.
Step 3 is the one that ends the argument — it shows the stored URL and key length per connection.

Related: the model appears as **COOPER-Open** / **COOPER-Private**, not `COOPER`
(`DISPLAY_MODEL`, main.py:82). CLAUDE.md said "pick COOPER" until this date.

### 2026-08-04 · Obsidian Note Writer demands a literal syntax the registry doesn't advertise

`general_tool_registry.yaml` lists `obsidian_note_writer` inputs as `note_path` and
`markdown_content`, and the classifier happily dispatches to it from ordinary phrasing. But
`_run_note_editor` (executor.py:357) regex-parses the RAW message and requires the literal form
`write note <name>.md: <content>` (`_NOTE_WRITE_RE`, executor.py:116). Anything else returns
"Workbench: could not parse a note write request" — and only AFTER you have spent an approval
on it, because the parse happens post-gate.

Two further constraints the registry doesn't mention: the filename charset is `[\w.\- ]`, so
**no subdirectories** (`Open Projects/foo.md` can never match), and the executor ignores any path
anyway — `Path(filename).name` into a fixed `Obsidian Vault/00_Inbox/`, refusing anything that
resolves outside it. That inbox IS bind-mounted rw on both stacks, so writes reach the host
(verified: file present on host, owned by root — container-written, as in the Step 11 history).

Working example: `write note openrouter-access.md: OpenRouter reaches the Open stack two ways…`

### 2026-08-04 · The classifier answers "run the litellm router using X: <payload>" instead of dispatching

Three phrasings — `use the litellm router using openrouter: <question>`,
`run the litellm router using openrouter: <question>`, and the same with an imperative
("summarize this in one sentence — …") — ALL classified as `answer` / "request for information".
COOPER answered the payload itself with its own model; the L3 `lite_llm_router` tool never ran
and no approval was ever requested. The tool was live-verified working on 2026-07-21, so this is
a classifier-routing problem, not a broken executor — the payload being answerable appears to
outweigh the explicit run-verb + named tool. Unresolved; not investigated further (out of scope
the day it was found). If you need the router, check `POST /chat`'s `decision` field —
`"decision":"answer"` means it never dispatched, regardless of how plausible the reply looks.

Note `_MODEL_HINT_RE` (executor.py:120) is `\busing\s+([\w.\-]+)` — no `/`, so raw OpenRouter
slugs like `anthropic/claude-sonnet-5` cannot be named directly; only LiteLLM aliases work.

### 2026-08-18 · OpenRouter "free" isn't, and `:free` fan-out doesn't multiply quota

Two facts that kill two plausible assumptions (verified live: `GET openrouter.ai/api/v1/key`
with the key from `litellm/.env.local`):

- The account is `is_free_tier: false` with **$7.91 of a $20 prepaid balance consumed**
  ($5.44 in Aug 2026 alone — presumably the direct Open WebUI → OpenRouter connection).
  "Never had to pay" = silent credit drawdown, not free usage. No spend limit set (gate G5).
- The `:free`-model daily request cap (1000/day at ≥$10 balance) is **account-wide across
  all `:free` models** — spreading a multi-agent workflow over five `:free` models draws one
  shared bucket. Quota-spreading only works across paid models / separate providers.

Also: COOPER-Open's brain (`openai` alias → gpt-4o-mini) bills the **OpenAI** key, not
OpenRouter — repointing it to an `openrouter/*` alias moves that spend onto the credits.

**Superseded by 15a (2026-08-24):** the classifier this entry and the one above describe no
longer exists — `decision.py::_classify`/`_CLASSIFIER_SYSTEM` were deleted outright, no
fallback. The persona model now sees the tool registry as `tools` on every turn; a `tool_call`
in its reply is the dispatch signal, checked against `registry.validate_args` before the
approval gate. Both entries stay for the historical record (the failure MODE — a plausible
answer standing in for a dispatch that never happened — is exactly what 15a was built to kill
as a class), but the specific phrasings/regexes named above no longer apply to the live system.

### 2026-08-24 · Streaming dispatch: a client that disconnects mid-preamble skips the dispatch

15a's streaming fix (`decision.py::_stream_and_maybe_dispatch`) forwards content live as it
arrives and only runs the accumulated tool_call's dispatch handler AFTER the stream ends —
this is necessary so a model's preamble text ("Sure, let me check…") doesn't cause the
following tool_call to be dropped (that was the bug the fix closed). Side effect: if the
HTTP client disconnects while the preamble is still streaming, Starlette closes the async
generator at its current `yield` and the dispatch handler is never reached — the tool_call the
model already committed to simply never runs, silently, no error, no approval ticket, no
executed action. This is a strictly milder failure than the bug that was fixed (no reply lies
to the user about what happened — there's just no reply at all), and no confirmed live
occurrence exists yet, but it's a new "a proposed dispatch can vanish" path worth knowing about
if a Private-workshop turn is ever observed to silently do nothing after visible preamble text.
Nothing to fix here today; documented so it isn't re-discovered as a mystery later.

### 2026-08-24 · Approval tickets expire at 600s; an expired "approve" falls through to plain chat

`approval.py::_TICKET_TTL_SECONDS = 600`. If a human takes more than 10 minutes to reply
"approve" after a halt message, the ticket has already expired (`approval._get_live` pops it
silently) and the literal word "approve" is handed to the persona model as an ordinary chat
message — it answers conversationally instead of executing anything, with no indication the
original action was ever abandoned. Pre-existing behavior, not introduced by 15a; surfaced
during 15a's fix-forward review as worth documenting. No fix planned — it's the correct
fail-closed behavior (a stale approval must not silently execute), just a UX wart: the human
has to notice the reply doesn't match what they expected and re-issue the original request.

### 2026-08-25 · Open WebUI's SQLite connections can drift to a governance bypass with zero server-side trace

Builds on the 2026-07-01 entry above ("Open WebUI stores connections in SQLite, env vars
ignored after first run") — that entry covers the *setup* gotcha; this one covers the
*drift* risk it creates. Found live on Private (`localhost:3001`): Admin → Connections had
**no `cooper-core` connection at all**, replaced by a direct `https://api.openai.com/v1`
(live Bearer key) and a direct `http://private-ollama:11434`. Neither is documented as
ever having been added deliberately — best guess is an artifact of earlier ad hoc testing
that was never reverted, but the mechanism doesn't matter as much as the blast radius: with
either of those enabled, a chat that *looks* identical to a normal COOPER conversation
(same model-picker label, same UI) skips cooper-core entirely — no classification, no
approval gate, no tool-registry validation, no audit log — and on Private specifically, the
OpenAI connection is a live crack in "local-only, air-gapped." **The failure is invisible
from the server side**: `docker logs`/`docker compose logs cooper-core` show nothing at all
for a bypassed turn (not an error — simply zero requests), because the request never
reached the container. The only way to catch it is from the client side: open Admin →
Connections and check the URL list against `http://cooper-core:<port>/v1` being the *only*
entry, or notice a dispatch-shaped prompt resolving to a tool name that doesn't exist in
`Config/*_tool_registry.yaml` (as happened here — `search_calendar_events`, no approval
halt, on a message clearly worded to trigger one). Fixed on Private 2026-08-25 (deleted
both stray connections, re-added the documented `cooper-core:8000/v1` one). **Not yet
checked as a standing practice**: verify Admin → Connections shows exactly the documented
entry (plus any owner-sanctioned ungoverned path, e.g. Open's OpenRouter connection from
2026-08-04) as part of any future session that does browser verification — this doesn't
self-heal and a stack rebuild does not reset Open WebUI's SQLite volume.

### 2026-08-25 · Open WebUI's own background calls can hijack a pending approval ticket

Found live during 14a's browser verification (Fabric Pattern Writer). Sequence: sent a
dispatch-shaped message on Open, got a correct halt (`Halt — Fabric Pattern Writer …
requires approval`), typed `yes, go ahead`, and the reply that came back was
`[LiteLLM Router — model: openai]` producing a thematic-tags list — not the fabric
artifact, and not anything the human asked for. The approval was consumed by a
completely different, unrequested tool call.

**Mechanism, traced through the code, not guessed:** `approval.py`'s ticket store is
keyed `(workshop, session_id)` with `session_id: str = "local"` as the default
(`approval.py:30,46`). Open WebUI's `/v1/chat/completions` connection is a bare
OpenAI-API client — the standard doesn't have a session-id concept, so Open WebUI never
sends one, and *every* request it makes (the visible chat AND its own background
housekeeping calls — title generation, tag generation, follow-up-suggestion generation,
all fired via the same connection) lands on the identical key `(workshop, "local")`.
`main.py:369` only treats an incoming message as an approval response if
`approval.has_pending(...) and approval.is_response(message)` are both true; if a
background call's prompt text doesn't match approve/deny, it falls through to a brand
new `route_turn(...)` call **with the tool schemas still attached** (line 377-378) —
and if the model decides that background prompt looks dispatch-shaped enough to invoke
a tool, `approval.request()` (`approval.py:63`) unconditionally overwrites
`_pending[(workshop, session_id)]` with the new ticket, no check for an existing one.
The human's next `approve`/`deny` reply then resolves whatever ticket is live at that
instant — which may no longer be the one they're looking at on screen.

**Confirmed, not merely reasoned through**: polled `GET /pending` every second while a
dispatch was in flight in the browser across several attempts. One run's ticket held
steady the whole time (Fabric Pattern Writer, unchanged); a separate run showed the
exact swap described above. **Reproduced once in roughly four browser attempts** — this
is probabilistic (depends on whether a given background prompt happens to read as
tool-call-shaped to the model), not deterministic, and does **not** reproduce via
`curl`/`/chat` at all, since nothing fires the background calls outside a real browser
client. That combination — rare, silent, no error surfaced, server logs show a normal
200 OK for both the hijacking dispatch and its approval — makes it easy to miss
entirely unless the actual returned content is checked against what was asked for.

**Severity: this is worse than a UX glitch.** The human's consent (`yes, go ahead`) can
be silently misapplied to an action they never saw and didn't intend to approve. It's
scoped to whatever the hijacking background call's own prompt asks for — in the
observed case, an already-approved-pattern (`lite_llm_router`) with harmless content —
but the mechanism doesn't guarantee that in general; it depends entirely on what Open
WebUI's own background prompt says and what the model decides to do with it.

**Fixed 2026-08-30** — the narrow candidate from the list above: `approval.request()`
now raises `ApprovalConflictError` instead of overwriting a live ticket for
`(workshop, session_id)`; `main.py`'s `_handle_tool_call` catches it and tells the human
what's already pending rather than silently dispatching over it. Verified at the
mechanism level: unit tests (`test_approval.py`, `test_main_dispatch.py`) plus a live
re-check inside both rebuilt containers — opened a ticket, attempted a second
`request()` on the same session, confirmed the conflict raised and the original ticket's
message/tool unchanged, on both Private and Open. **Caveat, stated honestly**: this
confirms the root-cause mechanism is closed, but the original probabilistic browser
repro above (~1-in-4, requires a real Open WebUI background call to fire and be judged
tool-call-shaped by the model) was not re-attempted live — that path doesn't reproduce
via `curl`/`/chat` at all (see above), so re-confirming it needs another live browser
session with `claude-in-chrome`, not yet done this session. Full decision/implementation
log: PROGRESS.md's 2026-08-30 entry.

### 2026-08-30 · A nonexistent `os.environ/<var>` in a LiteLLM deployment's `api_key` does NOT actually break auth

Found live during 15c Task 5, testing the DoD "kill one provider key mid-conversation →
turn still completes via fallback, logged" against a real second `openai/gpt-4o-mini`
LiteLLM deployment (the same-alias fallback pool added ahead of the existing cross-alias
`fallbacks:` chain). First attempt: pointed the primary deployment's `api_key` at
`os.environ/DOES_NOT_EXIST` — an env var name that genuinely does not exist in the
container. Expected an `AuthenticationError` and a failover. Got neither: every call kept
succeeding through the *primary* deployment (`chatcmpl-...` ids, not the fallback pool's
`gen-...` OpenRouter ids) — auth never actually broke.

**Root cause, confirmed by inspecting the container, not guessed:** LiteLLM's own
`os.environ/<name>` resolution failing (name not found) does not translate into "no key
passed." The underlying OpenAI SDK client that LiteLLM hands the call off to performs its
*own* independent env-var auto-discovery (`OPENAI_API_KEY` in the process environment) and
silently uses that instead — the real, still-valid key was present in `pda-litellm`'s
process env under its normal name the whole time, just not under the fake name LiteLLM was
told to look up. LiteLLM's own resolution failure never reaches the SDK as a hard error; it
degrades into "let the SDK's own fallback figure it out," which it does, successfully.

**Fix for testing "what if this key is dead/revoked":** don't point `api_key` at a
nonexistent or unset env var name — point it at an explicit **invalid literal key value**
(e.g. `"sk-deliberately-invalid-..."`). That forces LiteLLM to pass a real (but wrong)
key string explicitly, which the SDK cannot auto-discover around, producing a genuine
`AuthenticationError` from the provider. Confirmed this version worked: `docker logs
pda-litellm` showed the real failure → router cooldown → successful failover sequence
(`litellm.AuthenticationError: ... Incorrect API key provided: sk-delib***` →
`Attempting to add <deployment-hash> to cooldown list` → subsequent calls routed only to
the surviving deployment, 200 OK), and 5/5 live calls during the break all came back via
the fallback pool. Full DoD test detail: PROGRESS.md's 2026-08-30 (15c) entry,
`.superpowers/sdd/2026-08-30-step-15c-per-role-model-routing/task-5-report.md`.

**Why this matters beyond this one test:** any config or infra check reasoning "this
env var doesn't exist, so the credential must be absent" is unsound wherever the consuming
SDK does its own env-var fallback discovery — the absence has to be verified at the layer
that actually makes the call, not just at the layer that's supposed to supply it. Flagged
as worthwhile by both the Task 5 implementer and Task 5's reviewer but out of scope for
either to write down; recorded here at 15c's Task 6 (docs) instead.

### 2026-08-30 · `docker compose up --build <one-service>` can silently recreate a DIFFERENT, already-running service and strip its secrets

Found live during 15c Task 6's fix-round, rebuilding Open's `cooper-core` from this
worktree (which lacks the gitignored `PDA-Runtime/.env` and `litellm/.env.local`).
`docker-compose.yml`'s `litellm` service declares `env_file: ../litellm/.env.local`; that
file doesn't exist in the worktree, and `docker compose` refuses to parse the **entire**
file over one missing `env_file` reference, regardless of which service is actually
targeted (`up -d --build cooper-core` still fails on `litellm`'s directive). Worked around
it by temporarily commenting out just that one `env_file` line so compose could parse, ran
`up -d --build cooper-core` — and compose recreated **both** `cooper-core` (the intended
target) **and** the already-running `litellm` container, even though only `cooper-core` was
named on the command line. Because the `env_file` line was commented out, the recreated
`litellm` came up with **zero** of its real provider keys.

**Mechanism:** `docker compose up -d --build <service>` only *builds* the named service,
but its reconciliation pass still compares every service's *declared* config (the whole
file, as just parsed) against each container's *currently applied* config, and recreates
any container whose effective config no longer matches — not just the one named on the
command line. Editing one line for one service's env-file list changed `litellm`'s
declared config hash, so compose treated `litellm` as needing recreation too, silently,
with no confirmation prompt and no service name on the command line to warn otherwise.

**Confirmed, not assumed:** `docker exec pda-litellm printenv | grep -c API_KEY` → `0`
immediately after the incident (should be `4`). Caught within seconds by checking this
directly rather than trusting `docker ps`'s "healthy"/"Up" status, which showed nothing
wrong — LiteLLM starts and serves normally even fully unauthenticated to its upstream
providers; the break only surfaces on the first real inference call.

**Fix, live-verified:** recreate the damaged service from a checkout where its real
env file genuinely exists — here, `docker compose -f PDA-Runtime/docker-compose.yml up -d
litellm` run from the **main checkout**, not the worktree. Confirmed restored via the same
`printenv | grep -c API_KEY` check (`4`, matching pre-incident) and a real end-to-end
authenticated `POST /chat` on Open replying correctly. The compose-file edit itself was
then reverted (`git checkout --`) and confirmed clean.

**Takeaway for any future worktree-based rebuild that touches a multi-service compose
file:** a `docker compose up -d --build <target>` from a worktree missing one or more
services' secret files is not safely scoped to that target — it can implicitly recreate
and break *any* other service in the same file whose declared config you had to touch
(even temporarily) to get compose to parse at all. Verify every *other* running service's
critical env/state immediately after such a rebuild, not just the one you meant to touch.
