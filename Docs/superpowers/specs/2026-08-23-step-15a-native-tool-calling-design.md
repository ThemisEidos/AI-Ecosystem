# Step 15a — Native Tool-Calling Dispatch — Design Spec

**Date:** 2026-08-23
**Status:** Approved by owner (ThemisEidos), design session 2026-08-23
**Parent spec:** `2026-08-18-step-15-max-metrics-design.md` (slice 15a row + gates)
**Branch context:** all work on `main`. Implement on a feature branch/worktree per repo habit.
**Intended executor:** a cheaper model implements from this spec (owner cost decision).
This spec is therefore deliberately concrete: files, signatures, schemas, and tests are
named. Where this spec and the running code disagree, read the code first, then honor
this spec's *intent* — and say so in the session log.

---

## 1. Decision record

### Problem

Dispatch today is three chained LLM guesses:

1. `decision.py::_classify` — a grammar-rule classifier ("verb + named noun") decides
   answer/clarify/dispatch **before tools are ever considered**.
2. `registry.py::select_tool_llm` — a second LLM call picks a `tool_id` from the catalog.
3. The raw message rides on the approval ticket; **at execution time** handlers re-parse
   it with regexes (`executor.py::_NOTE_WRITE_RE`, `_MODEL_HINT_RE`, colon-split
   conventions).

Both 2026-08-04 gotchas live here: `lite_llm_router` was unreachable by any phrasing
(step 1 misrouted), and the note writer demanded a literal `write note <name>.md: <content>`
syntax and only failed *after* an approval was spent (step 3 parsed too late).

### Decision: Option A — one call, tools always attached

The workshop's main persona model receives the registry rendered as OpenAI-format tool
schemas on **every** chat turn. Text reply = answer (including the model's own clarifying
questions). Emitted `tool_call` = dispatch. The classifier's routing role, the second
selection call, and all execution-time arg regexes are **deleted** — retired means
deleted, not dormant; no fallback path to the old flow.

Precedent (verified 2026-08-23): Hermes Agent, Claude Code CLI, and Claude Cowork all use
exactly this shape — tools attached to the main model, the model's tool_call *is* the
dispatch, safety lives in the gate between emission and execution. COOPER's approval gate
is that gate and survives unchanged.

### Explicitly rejected (recorded so they stay rejected)

- **Free-running tool-after-tool loop (Hermes-style).** One tool_call per turn, then the
  gate. Multi-step chaining arrives via 14d (bounded loop), 15e (planner–executor
  envelopes), 15h (session plans, G3 enacted 2026-08-23) — one approval covering a
  quota-capped envelope. Buying M2 by spending M4/M7 is Hermes's profile; declining that
  trade is this program's standing constraint.
- **Keeping the classifier as a fallback.** Dead code is where the gotcha class hides.
  Model-side failure is already soft (no tool_call = plain answer, recoverable by
  rephrasing — same UX as today's misclassification, never a crash).
- **Two-step gate (classifier for answer/clarify + tool-call for dispatch only).** Keeps
  the "phrasing decides whether tools are considered" failure class alive at step 1.

---

## 2. Architecture — the new turn flow

Applies identically to `POST /chat` (blocking) and `POST /v1/chat/completions`
(blocking and streaming). Order of pre-model shortcuts is unchanged from today:
session notices → approval-response check (`approval.is_response` etc.) → registry-query
shortcut (`registry.is_registry_query`) → **then** the model call.

1. Build messages exactly as today (persona system prompt from the Modelfile SYSTEM
   block, memory recall context, skill context, history) and attach
   `tools=[render_tool_schema(t) for t in enabled workshop tools]`.
   - Open backend: OpenAI-format `tools` array via LiteLLM (`gpt-4o-mini`, G2 confirmed
     2026-08-23).
   - Private backend: same `tools` array on Ollama `/api/chat` (gemma4 native tool
     support; keep `think: false`).
2. **Text reply** → the answer. No `clarify` classification exists; a model that sees the
   tools asks its own "which logs?" naturally.
3. **`tool_calls` in the reply** → take the **first only**. If more than one was emitted,
   append a line to the eventual reply: `(Note: N additional tool calls were proposed and
   dropped — COOPER dispatches one action per turn.)`
4. Resolve the called function name to a registry entry (`registry.get_tool`). Unknown
   name → fail-closed refusal (§5). Then validate the call's JSON args against the tool's
   `parameters` schema (§3). Invalid → fail-closed refusal, nothing runs, no approval
   spent.
5. Hand off to the **existing** pipeline, unchanged in logic:
   `workshop.check_backend` → `workshop.check_tool` → skill trust note →
   `approval.needs_approval(tool)`:
   - L0/L1: execute immediately.
   - L2+: `approval.request(...)` opens a ticket **now also carrying the validated args**
     (§4); reply is the halt-for-approval message whose preview renders the validated
     args (e.g. `note: 'Gotchas-addendum.md', content: 214 chars`) instead of echoing raw
     text and hoping.
6. `decision` debug field on `/chat` is derived, not classified: `"dispatch"` if a
   tool_call was processed, else `"answer"`. `TurnDecision.reason` carries
   `tool_call: <tool_id>` or `no tool call emitted`. The `clarify` value disappears from
   live traffic; keep it in `VALID_DECISIONS` only if removing it breaks response-model
   validation for old clients — otherwise delete it.

### Streaming specifics

`stream=true`: stream the backend response. Content deltas pass through token-by-token as
today. If tool_call deltas appear (OpenAI: `choices[0].delta.tool_calls` fragments to
accumulate by `index`; Ollama: `message.tool_calls` arrives on a single chunk), buffer
silently until the tool_call is complete, run steps 3–5, then emit the dispatch result
(halt message or execution output) as content chunks. A turn is either streamed text OR a
buffered dispatch — never interleaved.

---

## 3. Registry: typed `parameters` per tool

Each tool entry in `Config/general_tool_registry.yaml` and
`Config/private_tool_registry.yaml` gains a `parameters` key holding a JSON-Schema object
(OpenAI function-calling subset: `type: object`, `properties`, `required`,
`additionalProperties: false`). The legacy `inputs:` name lists stay as documentation;
`parameters` is what renders and validates. No new config files.

`render_tool_schema(tool)` (new, in `registry.py`) produces:

```json
{"type": "function",
 "function": {"name": "<tool id>",
              "description": "<tool description field>",
              "parameters": {…the parameters block…}}}
```

A tool with no arguments gets `parameters: {type: object, properties: {}, additionalProperties: false}`.
**Every enabled tool MUST have a `parameters` block — the registry-walk test (§6) fails
otherwise.**

Parameter blocks to add (both registries; shared executor types share shapes):

| tool id(s) | executor_type | parameters |
|---|---|---|
| `status_summary`, `status_summary_private` | informational | none |
| `registry_inspector`, `registry_inspector_private` | local_read | none |
| `browser_research` | browser | `urls: array[string] (required)`, `search_terms: string` |
| `lite_llm_router` | llm_api | `prompt: string (required)`, `model: string` (optional; replaces `_MODEL_HINT_RE`) |
| `obsidian_note_writer` | note_editor | `filename: string (required)` — bare `.md` filename, no path separators; `content: string (required)` |
| `restricted_dmz_writer` | filesystem | `filename: string (required)`, `content: string (required)` |
| `qwen_local_assistant` | local_llm | `prompt: string (required)` |
| `powershell_open`, `powershell_private` | powershell | `script: string (required)` — script filename resolved against the existing allowlist |
| `python_open`, `python_private` | python | `script: string (required)` — same allowlist pattern |
| `n8n_general_workflows`, `restricted_workflow_runner` | workflow_engine | `workflow: string (required)` — key into `allowed_workflows`; `payload: string` |
| `codex_task_launcher` | cli_launcher | `request: string (required)` — the task description |
| `import_skill` | skill_import | `skill_name: string (required)`, `tap_url: string (required)` |
| `promote_skill` (both) | skill_promote | `skill_name: string (required)` |

Descriptions inside `properties` matter — they are what the model reads. Write them as
instructions (e.g. `filename`: "Bare markdown filename like 'meeting-notes.md'. No
directories — notes land in the vault inbox for human filing; subdirectory targets must
be refused, not silently flattened.").

---

## 4. Code changes by file (all in `cooper-core/` unless noted)

### `registry.py`
- Add `render_tool_schema(tool) -> dict` and `render_workshop_tools(workshop) -> list[dict]`.
- Add `validate_args(tool, args: dict) -> list[str]` returning human-readable violation
  strings (empty = valid). Implement the needed JSON-Schema subset by hand (type checks
  for string/array-of-string, required keys, reject unknown keys) — **do not add a
  jsonschema dependency**; stdlib-first is the repo convention.
- Delete `select_tool`, `select_tool_llm`, `_SELECT_SYSTEM_TMPL`, and their private
  helpers if now unused. Keep `list_tools`, `get_tool`, `format_tool_list`,
  `is_registry_query`.

### `decision.py`
- Replace `route_turn` / `route_turn_stream` internals: no `_classify` call; single
  backend call with `tools=` attached. Keep the module's public seam (`main.py` still
  calls two functions with the same names and near-same signatures; add a
  `tools: list[dict]` parameter and a `tool_call_handler` callback that `main.py`
  provides, replacing `dispatch_handler`).
- `tool_call_handler(tool_id: str, args: dict, raw_message: str) -> str` lives in
  `main.py` (evolution of `_handle_dispatch`).
- Delete `_CLASSIFIER_SYSTEM`, `_classify`, `_CLARIFY_SYSTEM`, `_clarify`,
  `_build_clarify_messages`.
- Extend `_ollama_complete` / `_openai_complete` / both stream functions to pass `tools`
  and to surface `tool_calls` from responses (blocking: return a small dataclass or tuple
  instead of bare content string; streaming: accumulate deltas as §2).

### `main.py`
- `_handle_dispatch` becomes the `tool_call_handler`: takes `(tool_id, args, raw_message,
  session_id)`; drops the `registry.select_tool_llm` call; validates args
  (`registry.validate_args`) before the workshop/approval steps; passes `args` through to
  `approval.request` and `_execute`.
- Approval halt message: append a rendered-args preview line. Render long string values
  as `<key>: <n> chars`; short ones verbatim.
- `_execute(tool, message, session_id, args)` threads args to `executor.run`.

### `approval.py`
- `ApprovalTicket` gains `args: dict` (default `{}`). `request(...)` accepts and stores
  it. On approve, `main.py` calls `_execute(ticket.tool, ticket.message, session_id,
  ticket.args)`. Everything else (session binding, expiry, approve/deny regexes) is
  untouched.

### `executor.py`
- `run(tool, message, workshop, args: dict | None = None)`.
- Handlers that parsed the message now consume args:
  `_run_note_editor(args)` (delete `_NOTE_WRITE_RE`; keep the byte cap, the
  `Path(...).name` + `relative_to` inbox containment, and refusal messages),
  `_run_llm_api(args)` (delete `_MODEL_HINT_RE` and the colon-split; `prompt` comes in
  clean — the 2026-07-21 "tool-framing text sent as prompt" bug class dies here),
  `_run_filesystem(args)`, `_run_local_llm(args)`, `_run_browser(args)`,
  `_run_powershell(tool, args)`,
  `_run_python(tool, args)`, `_run_workflow_engine(tool, args, workshop)`,
  `_run_cli_launcher(args)`, `_run_skill_import(args)`, `_run_skill_promote(args, workshop)`.
- Script/workflow **allowlist authorization stays exactly as-is** (`_authorize_script`,
  `allowed_workflows`) — args name the script, the allowlist still decides.
- `_run_informational` and `_run_local_read` unchanged (no args).
- `skills.preview_import` / `preview_promote` (called from the approval preview path in
  `main.py`) change their inputs from raw-message parsing to the validated args; update
  `skills.py` signatures accordingly.

### Config
- Both registry YAMLs: add `parameters` per §3's table.

### Untouched
`workshop.py`, `archivist.py`, `proposer.py`, `evidence.py`, semantic skill matching,
`_post_dispatch`, session notices, auth, `/health`, `/tools`, `/skills`.

---

## 5. Error handling (all fail-closed, none spend an approval)

| Case | Behavior |
|---|---|
| Model calls unknown function name | "COOPER proposed a call to unregistered tool '<name>'. Nothing ran." |
| Args fail schema validation | "COOPER proposed an invalid call to <tool>: <violations>. Nothing ran." |
| Note write targeting a subdirectory | schema description steers the model; if it still sends separators, `filename` validation refuses **before approval** (the DoD's "proper refusal, not post-approval parse error") |
| Tool disabled / wrong workshop | model never saw its schema; defense-in-depth `workshop.check_tool` + `get_tool` lookup remain |
| Backend error / timeout | existing `[COOPER error: backend unavailable — …]` path |
| Multiple tool_calls | first processed, rest dropped with a visible note (§2.3) |

---

## 6. Testing

Sibling `test_*.py` files, full suite green before any "done" claim.

1. **Registry-walk test (this IS metric M1, permanently):** for every enabled tool in
   BOTH registry YAMLs — `parameters` block present and well-formed; `render_tool_schema`
   emits valid OpenAI shape; a synthetic tool_call with schema-conforming args passes
   `validate_args` and maps to a wired executor handler (assert against `executor.py`'s
   dispatch table, no live LLM). A registry entry without `parameters` fails this test.
2. `validate_args` unit tests: accept/reject per type, missing required, unknown key.
3. Tool_call → ticket: args stored on ticket; approve executes with stored args; preview
   contains rendered args.
4. Multiple-tool_call truncation note.
5. Fail-closed cases from §5 (unknown tool, invalid args, note-write subdirectory refusal).
6. Streaming accumulation: OpenAI-style fragmented tool_call deltas and Ollama-style
   single-chunk tool_calls both produce one validated call (fixture-driven, no live LLM).
7. Executor handlers: re-target existing note_editor/llm_api/etc. tests to args input;
   delete classifier and select_tool tests along with their code.
8. Existing suite adaptations where tests monkeypatch `_classify` or `select_tool_llm`.

## 7. Live DoD (both stacks, from the parent spec — evidence before claims)

- The three previously-dead `lite_llm_router` phrasings (Gotchas 2026-08-04) all dispatch
  on Open, through the real container.
- A note write in ordinary phrasing (no magic syntax) round-trips on Open; a subdirectory
  note target is refused **pre-approval**.
- One full browser turn per stack (single visual confirmation; API for everything else,
  per CLAUDE.md).
- Full dispatch→approve→execute round trip on Private through Docker (rebuild first —
  `up -d` does not rebuild, Gotchas 2026-07-08).
- Record gemma4's observed tool-call hit rate during verification (informal count is
  fine) — it baselines M3 against the ~86% claim.

## 8. Out of scope for 15a

Multi-step chaining (14d/15e/15h), per-role model routing (15c), Fabric executor (14a),
council (15d), Cockpit (15i), any registry permission-level or approval-rule change
(governance is owner-only), Open WebUI provisioning (15b).
