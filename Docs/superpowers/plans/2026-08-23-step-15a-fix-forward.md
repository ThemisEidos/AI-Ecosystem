# Step 15a — Fix-Forward Tasks (post-review)

**Date:** 2026-08-23
**Context:** 15a merged to main (`f148d8e..f6d320b`), whole-branch review + live DoD run
2026-08-23/24. Verdict: no Criticals; 228/228 green; live DoD passed on both stacks
(evidence in PROGRESS.md when this lands). Three Important findings to fix forward, then
the deferred browser verification closes the slice.
**Spec authority:** `Docs/superpowers/specs/2026-08-23-step-15a-native-tool-calling-design.md`
**Rules:** TDD (failing test first), full suite green before any "done" claim
(`cd cooper-core && .venv/bin/python -m pytest`), rebuild both Docker stacks before any
live claim (`up -d` does NOT rebuild). Work on a feature branch/worktree, merge when green.

---

## Task 1 — Streaming must not silently swallow a dispatch (Important #1)

**Problem:** Blocking and streaming paths disagree on mixed content+tool_call replies.
`decision.py::route_turn`: tool_calls present → dispatch (accompanying content discarded).
`decision.py::_forward_remaining` (streaming): if any content delta arrives *before* the
tool_call delta, the tool_call is **silently dropped** and the turn becomes an answer —
currently pinned by `test_ollama_stream_content_before_tool_call_drops_the_tool_call`.
Gemma-class models often emit preamble prose ("Sure, let me check…") before a tool call,
and Open WebUI uses the streaming path — so real browser dispatches vanish with no trace,
while the identical reply on `POST /chat` dispatches. Same model output must not produce
a different governance outcome.

**Fix (chosen semantic — make streaming match blocking):** buffer the stream; if a
complete tool_call arrives at any point, the turn is a dispatch — stream/emit the
dispatch pipeline's result and drop the preamble content (same as blocking). If no
tool_call arrives, content passes through as today. Practical shape: forward content
deltas only after the stream ends without tool_calls is NOT acceptable (kills streaming
UX for every answer turn). Instead: forward content deltas as they arrive, and if a
tool_call subsequently completes, append the dispatch result as additional chunks after
a separator line (`\n\n---\n`), so the preamble is visible but the dispatch still
happens. The tool_call is never dropped.

**Tests:** replace `test_ollama_stream_content_before_tool_call_drops_the_tool_call`
with tests asserting: (a) content-then-tool_call streams the content AND runs the
dispatch handler, result appended; (b) tool_call-only unchanged; (c) content-only
unchanged. Cover both Ollama single-chunk and OpenAI fragmented delta fixtures.

## Task 2 — Invalid-value calls must not spend an approval (Important #2)

**Problem:** `registry.py::validate_args` checks type/required/unknown-key/path-separator
only. Empty required strings (`filename: ""`, `content: ""`, `prompt: ""`, `script: ""`),
empty `urls: []`, and unknown `workflow` keys pass pre-approval validation and are
refused by the executor only AFTER a human approves — the exact "approval spent, then
refusal" class 15a exists to kill. (Spec gap acknowledged: §4's validator subset omitted
these; this task amends the implementation and the registry blocks, not governance.)

**Fix:**
1. `validate_args`: a **required** string arg must be non-empty after `.strip()`; a
   **required** array arg must be non-empty. Optional args may be empty/absent.
2. `workflow_engine` tools: validate the supplied `workflow` value against the tool's
   `allowed_workflows` mapping keys **pre-approval** in `main.py::_handle_tool_call`
   (or a small hook in `validate_args` given the tool dict is available). The execution-
   time allowlist check in `executor.py` stays exactly as-is (authoritative, spec §4).
3. While present in `browser_research`: require `urls` entries to start with `http://`
   or `https://` at validation time (mirrors the executor's existing refusal).

**Tests:** accept/reject cases per rule; a workflow_engine call with an unknown key is
refused with no ticket opened (assert `approval.has_pending` false); existing executor
refusals stay as defense in depth.

## Task 3 — Tool_call accumulator: index-less fragments (Important #3)

**Problem:** `decision.py::_ToolCallAccumulator.add` uses
`fragment.get("index", len(self._order))`, so a provider that omits `index` (possible
behind LiteLLM) opens a NEW slot per fragment — shredding one call into a name-only
primary (spurious "missing required argument" refusal) plus nameless ghost "dropped"
calls.

**Fix:** a fragment without `index` continues the most recently opened entry; only a
fragment bearing a new explicit `index` (or the first fragment) opens a slot.

**Tests:** fixture stream of index-less fragments yields exactly one assembled call with
concatenated arguments; existing indexed fixtures unchanged.

## Task 4 — Minor sweep (single commit, no behavior risk)

- `decision.py::_dropped_calls_note`: was/were agreement for n=1.
- `main.py`: rename `CLASSIFIER_MODEL` → `UTILITY_MODEL` (it now serves
  review/archivist/proposer only); update startup print and `/health` key
  (`"classifier"` → keep emitting BOTH keys for one release if any client reads it —
  check `install-cooper.sh`/launchers for consumers first; CLAUDE.md health examples
  show the field, update CLAUDE.md if changed).
- `executor.py`: convert `run()`'s if-chain to a dict dispatch table and derive
  `WIRED_EXECUTOR_TYPES` from it, so the M1 registry-walk assertion cannot drift.
- `main.py::_render_args_preview`: measure and render the same string (repr vs str
  mismatch at the 60-char threshold).
- `registry.py::validate_args`: comment that `additionalProperties` is treated as
  always-false regardless of the block's value.
- `general_tool_registry.yaml::browser_research`: description currently overpromises —
  executor fetches only `urls[0]` and ignores `search_terms`. Narrow the description
  (do NOT extend the executor in this pass).

## Task 5 — Close the DoD: browser verification + docs

1. Rebuild BOTH stacks (`docker compose -f … up -d --build cooper-core`).
2. Browser click-through, one turn per stack (Open :3000, Private :3001): send a
   dispatch-shaped message with a preamble-inducing phrasing (e.g. "Could you please use
   the litellm router to answer: what is 2+2?") — this exercises the Task 1 fix on the
   real streaming path — approve in the browser, confirm executor output renders.
3. Record observed gemma4 tool-call hit rate (informal running count including the
   2026-08-24 baseline: 2/2).
4. Docs: PROGRESS.md 15a checklist tick + decision-log entry; North Star current
   position; Gotchas entry if any new trap surfaced. Note in the log: approval tickets
   expire at 600 s (`approval.py::_TICKET_TTL_SECONDS`) and an expired "approve" falls
   through to the model as ordinary chat — known UX wart, pre-existing, not 15a's.

## Out of scope

Everything else: 14a is next AFTER this closes. No governance, permission-level, or
approval-rule changes. No new executors. No model swaps.
