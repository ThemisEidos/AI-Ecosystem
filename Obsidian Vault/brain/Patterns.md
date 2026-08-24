# Patterns — Confirmed Implementation Approaches

> Updated 2026-07-01. Append new entries with `### YYYY-MM-DD · <title>`.

---

### 2026-08-23 · Step 15a native tool-calling dispatch — implemented, test-green, NOT live-verified

Implemented via `superpowers:subagent-driven-development` on branch
`worktree-step-15a-native-tool-calling` (worktree at
`.claude/worktrees/step-15a-native-tool-calling`), plan at
`Docs/superpowers/plans/2026-08-23-step-15a-native-tool-calling-plan.md`,
spec at `Docs/superpowers/specs/2026-08-23-step-15a-native-tool-calling-design.md`.
All 8 code tasks complete and independently task-reviewed (7 clean, 1 with a
verified-correct test deviation — see the plan's ledger at
`.superpowers/sdd/2026-08-23-step-15a-native-tool-calling-plan/progress.md`
inside that worktree for every ruling and deferred-minor finding). Full
`cooper-core` suite: 226/226 passing, independently re-run by the Task 8
reviewer, not just claimed.

Four design decisions this plan locked in beyond the spec's literal text
(full rationale in the plan's "Design decisions this plan locks in"
section):
1. `decision._ollama_complete`/`_openai_complete` return a bare `str` when
   called without `tools=` — the six existing non-tool callers
   (`archivist.py`, `proposer.py`, `review.py`, `executor.py`'s
   `_run_local_llm`/`_run_llm_api`) stay untouched. A new
   `ModelReply(content, tool_calls)` dataclass is returned only when
   `tools=` is passed — i.e. only the persona-turn call path.
2. Streaming forwards content in real time for plain answers and only
   buffers once a tool_call fragment is detected, via a shared
   `_stream_events()` generator per backend that `route_turn_stream` peeks
   on its first event to pick the branch — avoids buffering the common
   case while still satisfying "never interleaved."
3. A custom `no_path_separators: true` flag on registry YAML parameter
   schemas (`obsidian_note_writer`, `restricted_dmz_writer`,
   `powershell_*`/`python_*`'s `script` args) drives
   `registry.validate_args` to refuse subdirectory-targeting filenames
   **pre-approval** — this is the actual generic mechanism behind spec
   §5's "note write targeting a subdirectory... refuses before approval."
4. `decision.route_turn` dropped `base_url`/`api_key`/`model`/`backend`/
   `classifier_model` from its signature (dead inside `route_turn` itself,
   since the one persona call lives in the `generate_answer` closure
   main.py owns). `route_turn_stream` keeps them since it makes the
   backend HTTP call directly.

**Live DoD verification (spec §7) was NOT run this session.** Both the
Private and Open Docker stacks were found already running live (5 hours
up, real ports 8000/8001) when Task 10 started. The plan's verification
steps call for rebuilding those containers from this unmerged branch and
writing a real test file into `Restricted DMZ Workspace/` — which
`CLAUDE.md`'s DO NOT TOUCH list marks human-only. Owner chose to skip live
verification rather than disrupt the running deployment or touch that
directory. **The branch is implementation-complete and test-green but not
live-verified** — run the plan's Task 10 (Docker rebuild + curl round
trips on both stacks, including the three previously-dead
`lite_llm_router` phrasings from Gotchas 2026-08-04) before merging or
calling this shipped.

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
