# Patterns — Confirmed Implementation Approaches

> Updated 2026-07-01. Append new entries with `### YYYY-MM-DD · <title>`.

---

### 2026-07-08 · Session identity = derived from the credential, never client-supplied

`_derive_session_id(token)` in `cooper-core/main.py` is `sha256(token)[:12]`, `"anon"` for
none — never accepted as client input, always computed server-side from the already-authenticated
bearer token. This is what makes session-scoped approval tickets (`approval.py`'s `_pending`
keyed on `(workshop, session_id)`) actually safe: a client can't spoof another session's id
without possessing that session's actual credential. Same identity function reused for the
Signal gateway (`signal:<sender>`) — one function, one derivation rule, no matter which
transport carried the request in.

### 2026-07-08 · `${VAR-default}` vs `${VAR:-default}` in Docker Compose / bash — the distinction matters for "kill a default credential"

`${VAR:-default}` substitutes `default` when VAR is unset **or empty**. `${VAR-default}`
(no colon) substitutes `default` **only when VAR is completely absent** — an explicitly-empty
value is honored as real. Use the single-dash form whenever a bootstrap/install script needs to
write an empty value to `.env` specifically to suppress a compose-level default (e.g. retiring
a shared default API key once a real one is generated) — the colon form would silently keep
falling back to the old default forever, defeating the point of writing the empty override.

### 2026-07-08 · Deferred-task plan items need a freshness check before executing, not just before writing

When a plan defers a task with "do X after Y merges" (Step 13's Task 4, gated on Step 12), treat
that as a live precondition to re-check at execution time, not a fact fixed when the plan was
written — especially in a parallel-worktree setup where Y is being built concurrently by another
in-flight session. `git log --oneline <base>..<sibling-branch>` immediately before starting the
deferred task tells you whether the gate has actually opened, cheaply, before you commit to
either skipping the task or (worse) executing it against a base that's already moved out from
under you. See `Gotchas.md`'s matching entry for what happens when this check is skipped.

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
