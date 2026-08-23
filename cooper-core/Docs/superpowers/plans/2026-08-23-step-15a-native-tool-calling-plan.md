# Step 15a — Native Tool-Calling Dispatch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace COOPER's three-chained-LLM-guess dispatch (classifier → tool
selector → regex arg parsing) with one model call per turn that has the tool
registry attached as OpenAI-format `tools`; the model's own `tool_call` *is*
the dispatch, validated against a typed schema before the approval gate ever
sees it.

**Architecture:** `registry.py` renders each enabled tool as an OpenAI
function-calling schema and validates a proposed call's args against it.
`decision.py` attaches `tools=` to the single persona-model call on every
turn (blocking and streaming) and surfaces any `tool_call` the model emits
instead of running a separate classifier. `main.py`'s dispatch handler
(renamed `_handle_tool_call`) resolves the tool_call to a registry entry,
validates args pre-approval, and threads validated args through the
existing approval ticket → `executor.run` → review pipeline. `executor.py`'s
per-executor-type handlers stop parsing free text and consume `args` dicts
directly, deleting every regex that used to reverse-engineer intent from a
raw message.

**Tech Stack:** Python 3, FastAPI, httpx, PyYAML, pytest, Ollama `/api/chat`
native tool calling, OpenAI-compatible `tools`/`tool_calls` via LiteLLM.

**Spec:** `Docs/superpowers/specs/2026-08-23-step-15a-native-tool-calling-design.md`
— this plan implements that spec's Option A end-to-end. Where this plan
makes a call the spec left implicit, it's flagged inline as a **Deviation**
with rationale; per the spec's own header instruction, these are also worth
a line in the session log when the plan is executed.

## Global Constraints

- No new dependencies — `validate_args` implements the needed JSON-Schema
  subset by hand (stdlib-first is repo convention, spec §4 `registry.py`).
- Retired means deleted, not dormant — no fallback path to the old
  classifier/select_tool_llm/regex-parsing flow anywhere (spec §1 decision).
- Every behavior change lands with tests in the sibling `test_*.py`; full
  suite green before any "done" claim (CLAUDE.md, spec §6).
- Script/workflow allowlist authorization (`_authorize_script`,
  `allowed_workflows`) stays exactly as-is — args name the script/workflow,
  the allowlist still decides (spec §4 `executor.py`).
- `workshop.py`, `archivist.py`, `proposer.py`, `evidence.py`, semantic skill
  matching, `_post_dispatch`, session notices, auth, `/health`, `/tools`,
  `/skills` are untouched (spec §4 "Untouched").
- Out of scope: multi-step chaining, per-role model routing, Fabric
  executor, council, Cockpit, any registry permission-level/approval-rule
  change — governance is owner-only (spec §8).

## Design decisions this plan locks in (spec left these to "read the code")

1. **`_ollama_complete`/`_openai_complete` keep returning a bare `str` when
   called without `tools=`** (all six existing non-tool call sites —
   `archivist.py`, `proposer.py`, `review.py`, and `executor.py`'s
   `_run_local_llm`/`_run_llm_api` — are unaffected, matching the spec's own
   "Untouched" list for `archivist.py`/`proposer.py`). When called *with*
   `tools=`, they return a new `ModelReply(content, tool_calls)` dataclass
   instead. This is the minimal-blast-radius reading of spec §4's "extend...
   to surface tool_calls... return a small dataclass or tuple instead of a
   bare content string" — extending only the one new call path (the persona
   turn) rather than every caller of these two functions.
2. **Streaming forwards content in real time for plain answers, and buffers
   only once a tool_call fragment is seen** — implemented via a shared
   `_stream_events()` generator per backend that yields `{"content": ...}`
   or `{"tool_call_delta": ...}` items; `route_turn_stream` peeks the first
   event to decide the branch, matching spec §2's streaming-specifics
   requirement ("never interleaved") without buffering the common case.
3. **`filename` args that must stay a bare filename (no subdirectories)
   are declared with a custom `no_path_separators: true` flag** on the
   registry YAML's parameter schema, honored by `registry.validate_args`
   before approval — this is how spec §5's "note write targeting a
   subdirectory... refuses **before approval**" is actually implemented
   generically across `obsidian_note_writer` and `restricted_dmz_writer`.
4. **`route_turn`'s signature drops `base_url`/`api_key`/`model`/
   `classifier_model`/`backend`** (all now dead inside `route_turn` itself,
   since the one persona call is made inside the `generate_answer` closure
   main.py already owns) rather than keeping them as unused params for
   spec §4's "near-same signature" — `route_turn_stream` keeps them since it
   makes the backend call directly.

---

### Task 1: Registry — typed schema rendering + arg validation

**Files:**
- Modify: `cooper-core/registry.py`
- Test: `cooper-core/test_registry.py`

**Interfaces:**
- Produces: `registry.render_tool_schema(tool: dict) -> dict`,
  `registry.render_workshop_tools(workshop: str) -> List[dict]`,
  `registry.validate_args(tool: dict, args: dict) -> List[str]` (empty list
  = valid). These three are consumed by Task 8 (`main.py`) and Task 3
  (registry-walk test).
- Deletes: `registry.select_tool`, `registry.select_tool_llm`,
  `registry._SELECT_SYSTEM_TMPL`, `registry._STOPWORDS`, and the
  `from decision import _ollama_complete, _openai_complete` import (no
  longer used in this file).

- [ ] **Step 1: Delete the LLM-backed and keyword selectors**

In `cooper-core/registry.py`, delete lines 17-24's `from decision import
_ollama_complete, _openai_complete` (keep `import json`, `import re`,
`from pathlib import Path`, `from typing import Dict, List, Optional`,
`import yaml`). Delete the entire `_STOPWORDS` block (lines 117-120), the
entire `select_tool` function (lines 123-151), and the entire
`_SELECT_SYSTEM_TMPL` + `select_tool_llm` block (lines 154-227). Also
delete the docstring's line 7 (`2. "which tool fits this task?" ->
select_tool(workshop, message)`) and update the module docstring's opening
paragraph to describe the new job:

```python
"""
COOPER Quartermaster — tool registry reader, OpenAI-schema renderer, and arg
validator (Step 15a).

Loads the workshop-scoped tool registry YAML and answers:

  1. "what tools are available?"        -> list_tools(workshop) / format_tool_list(workshop)
  2. "what does the model see as tool schemas?" -> render_workshop_tools(workshop)
  3. "is this tool_call's args valid?"  -> validate_args(tool, args)

Registry files live at Config/general_tool_registry.yaml (open) and
Config/private_tool_registry.yaml (private), per CLAUDE.md's directory map.
Files are re-read whenever their mtime changes, so editing the YAML takes
effect immediately under `--reload` without a server restart.

This module only reads, renders, and validates. It does not execute
anything — the approval gate (approval.py) and execution gateway
(executor.py) are separate.
"""
```

- [ ] **Step 2: Add `render_tool_schema` and `render_workshop_tools`**

Append after `format_tool_list` (which stays):

```python
# ── OpenAI-format tool schema rendering (Step 15a) ──────────────────────────
def render_tool_schema(tool: dict) -> dict:
    """One tool entry -> an OpenAI function-calling `tools` array element."""
    parameters = tool.get("parameters") or {
        "type": "object", "properties": {}, "additionalProperties": False,
    }
    return {
        "type": "function",
        "function": {
            "name": tool.get("id"),
            "description": tool.get("description", ""),
            "parameters": parameters,
        },
    }


def render_workshop_tools(workshop: str) -> List[dict]:
    """Every enabled tool for a workshop, rendered as OpenAI tool schemas —
    attached to the persona model on every turn (spec §2, step 1)."""
    return [render_tool_schema(t) for t in list_tools(workshop)]
```

- [ ] **Step 3: Add `validate_args`**

Append below `render_workshop_tools`:

```python
# ── Arg validation (Step 15a) ───────────────────────────────────────────────
# Hand-rolled subset of JSON Schema (no jsonschema dependency — stdlib-first
# is the repo convention, spec §4). Covers what the registry's `parameters`
# blocks actually use: object/string/array-of-string/array-of-object,
# required keys, unknown-key rejection, and a custom `no_path_separators`
# flag (declared per-property in the YAML) so a bare-filename argument can
# be refused pre-approval rather than only sanitized at execution time.
def validate_args(tool: dict, args: dict) -> List[str]:
    """Validate a proposed tool_call's args against tool['parameters'].
    Returns a list of human-readable violation strings; empty = valid."""
    schema = tool.get("parameters") or {
        "type": "object", "properties": {}, "additionalProperties": False,
    }
    properties = schema.get("properties") or {}
    required = schema.get("required") or []
    violations: List[str] = []

    if not isinstance(args, dict):
        return [f"expected an object of arguments, got {type(args).__name__}"]

    for key in required:
        if key not in args:
            violations.append(f"missing required argument '{key}'")

    for key, value in args.items():
        if key not in properties:
            violations.append(f"unknown argument '{key}'")
            continue
        prop = properties[key]
        expected_type = prop.get("type")
        if expected_type == "string":
            if not isinstance(value, str):
                violations.append(f"argument '{key}' must be a string")
            elif prop.get("no_path_separators") and ("/" in value or "\\" in value):
                violations.append(
                    f"argument '{key}' must be a bare filename with no directory separators"
                )
        elif expected_type == "array":
            if not isinstance(value, list):
                violations.append(f"argument '{key}' must be an array")
            else:
                item_type = (prop.get("items") or {}).get("type")
                if item_type == "string" and not all(isinstance(v, str) for v in value):
                    violations.append(f"argument '{key}' must be an array of strings")
        elif expected_type == "object" and not isinstance(value, dict):
            violations.append(f"argument '{key}' must be an object")

    return violations
```

- [ ] **Step 4: Update `test_registry.py` for the deleted/added surface**

Replace the whole file's selector-testing section. Open
`cooper-core/test_registry.py` and:

1. Delete `test_keyword_select_finds_status_tool`,
   `test_keyword_select_returns_none_on_no_overlap`,
   `test_llm_select_returns_chosen_tool`,
   `test_llm_select_none_means_no_tool`,
   `test_llm_select_falls_back_to_keywords_on_error`,
   `test_llm_select_falls_back_on_unregistered_tool_id`, and the now-unused
   `_run` helper if nothing else in the file uses it (grep the file after
   deleting — `is_registry_query`'s test doesn't need it).
2. Keep `test_registry_yaml_files_have_no_duplicate_keys` and
   `test_is_registry_query` unchanged.
3. Add:

```python
_ECHO_TOOL = {
    "id": "echo_tool",
    "name": "Echo Tool",
    "description": "Echoes back the given text.",
    "parameters": {
        "type": "object",
        "properties": {
            "text": {"type": "string", "no_path_separators": True},
            "tags": {"type": "array", "items": {"type": "string"}},
            "context": {"type": "object"},
        },
        "required": ["text"],
        "additionalProperties": False,
    },
}


def test_render_tool_schema_shape():
    schema = registry.render_tool_schema(_ECHO_TOOL)
    assert schema == {
        "type": "function",
        "function": {
            "name": "echo_tool",
            "description": "Echoes back the given text.",
            "parameters": _ECHO_TOOL["parameters"],
        },
    }


def test_render_tool_schema_defaults_to_empty_object_parameters():
    schema = registry.render_tool_schema({"id": "no_args", "description": "d"})
    assert schema["function"]["parameters"] == {
        "type": "object", "properties": {}, "additionalProperties": False,
    }


def test_render_workshop_tools_covers_every_enabled_tool():
    rendered = registry.render_workshop_tools("private")
    ids = {r["function"]["name"] for r in rendered}
    assert ids == {t["id"] for t in registry.list_tools("private")}


def test_validate_args_accepts_valid_call():
    assert registry.validate_args(_ECHO_TOOL, {"text": "hi"}) == []


def test_validate_args_rejects_missing_required():
    violations = registry.validate_args(_ECHO_TOOL, {})
    assert any("missing required argument 'text'" in v for v in violations)


def test_validate_args_rejects_unknown_key():
    violations = registry.validate_args(_ECHO_TOOL, {"text": "hi", "bogus": 1})
    assert any("unknown argument 'bogus'" in v for v in violations)


def test_validate_args_rejects_wrong_type():
    violations = registry.validate_args(_ECHO_TOOL, {"text": 5})
    assert any("must be a string" in v for v in violations)


def test_validate_args_rejects_non_string_array_items():
    violations = registry.validate_args(_ECHO_TOOL, {"text": "hi", "tags": [1, 2]})
    assert any("must be an array of strings" in v for v in violations)


def test_validate_args_rejects_path_separators_when_flagged():
    violations = registry.validate_args(_ECHO_TOOL, {"text": "sub/dir.md"})
    assert any("no directory separators" in v for v in violations)


def test_validate_args_rejects_non_dict_args():
    assert registry.validate_args(_ECHO_TOOL, ["not", "a", "dict"]) != []
```

- [ ] **Step 5: Run the registry test file**

Run: `cd cooper-core && .venv/bin/python -m pytest test_registry.py -v`
Expected: all tests pass (registry-walk / M1 test lands in Task 3, after
Task 2 adds `parameters` to the YAMLs — the tests above don't depend on
that).

- [ ] **Step 6: Commit**

```bash
git add cooper-core/registry.py cooper-core/test_registry.py
git commit -m "feat(registry): render OpenAI tool schemas, validate args, drop LLM tool selection"
```

---

### Task 2: Registry YAML configs — add `parameters` per tool

**Files:**
- Modify: `Config/general_tool_registry.yaml`
- Modify: `Config/private_tool_registry.yaml`

**Interfaces:**
- Consumes: Task 1's `registry.render_tool_schema`/`validate_args` (which
  read `tool["parameters"]` and `no_path_separators`).
- Produces: every enabled tool entry in both files gains a `parameters:`
  key — required by Task 3's registry-walk test.

- [ ] **Step 1: `Config/general_tool_registry.yaml` — add `parameters` to every tool**

Add a `parameters:` block immediately after each tool's `enabled: true`
line (position doesn't matter to the YAML/loader, but keep it adjacent to
`inputs:`/`outputs:` for readability — leave `inputs:`/`outputs:` in place
as documentation per spec §3). Exact blocks, by tool id:

`status_summary`:
```yaml
    parameters:
      type: object
      properties: {}
      additionalProperties: false
```

`registry_inspector`: identical to `status_summary`'s block above.

`browser_research`:
```yaml
    parameters:
      type: object
      properties:
        urls:
          type: array
          items:
            type: string
          description: "One or more https:// URLs to research. At least one is required."
        search_terms:
          type: string
          description: "Optional search terms to focus the research summary."
      required:
        - urls
      additionalProperties: false
```

`lite_llm_router`:
```yaml
    parameters:
      type: object
      properties:
        prompt:
          type: string
          description: "The exact prompt to send to the routed model — no tool-invocation framing, just the task itself."
        model:
          type: string
          description: "Optional model name to route to. Defaults to the workshop's configured model if omitted."
      required:
        - prompt
      additionalProperties: false
```

`obsidian_note_writer`:
```yaml
    parameters:
      type: object
      properties:
        filename:
          type: string
          no_path_separators: true
          description: "Bare markdown filename like 'meeting-notes.md'. No directories — notes land in the vault inbox for human filing; subdirectory targets are refused, not silently flattened."
        content:
          type: string
          description: "The full markdown content of the note."
      required:
        - filename
        - content
      additionalProperties: false
```

`powershell_open`:
```yaml
    parameters:
      type: object
      properties:
        script:
          type: string
          no_path_separators: true
          description: "Filename of an allowlisted PowerShell script under Scripts/, e.g. 'Test-PDAStack.ps1'."
      required:
        - script
      additionalProperties: false
```

`python_open`:
```yaml
    parameters:
      type: object
      properties:
        script:
          type: string
          no_path_separators: true
          description: "Filename of an allowlisted Python script under Scripts/Python/, e.g. 'Test-Exec.py'."
      required:
        - script
      additionalProperties: false
```

`n8n_general_workflows`:
```yaml
    parameters:
      type: object
      properties:
        workflow:
          type: string
          description: "Key into this tool's allowed_workflows mapping, e.g. 'pda_command_router'."
        payload:
          type: string
          description: "Optional text payload passed to the workflow."
      required:
        - workflow
      additionalProperties: false
```

`codex_task_launcher`:
```yaml
    parameters:
      type: object
      properties:
        request:
          type: string
          description: "Plain-language description of the task to turn into a governed Codex task file."
      required:
        - request
      additionalProperties: false
```

`import_skill`:
```yaml
    parameters:
      type: object
      properties:
        skill_name:
          type: string
          description: "Lowercase skill id, e.g. 'stack-health-check'. Must match [a-z0-9][a-z0-9-]*."
        tap_url:
          type: string
          description: "https:// URL of the tap repository containing skills/<skill_name>/SKILL.md."
      required:
        - skill_name
        - tap_url
      additionalProperties: false
```

`promote_skill` (Open entry):
```yaml
    parameters:
      type: object
      properties:
        skill_name:
          type: string
          description: "Lowercase id of the drafted or already-registered skill to promote."
      required:
        - skill_name
      additionalProperties: false
```

- [ ] **Step 2: `Config/private_tool_registry.yaml` — add `parameters` to every tool**

`status_summary_private` and `registry_inspector_private`: same empty-object
block as `status_summary` above.

`restricted_dmz_writer`:
```yaml
    parameters:
      type: object
      properties:
        filename:
          type: string
          no_path_separators: true
          description: "Bare filename for the DMZ workspace, e.g. 'analysis.txt'. No directories."
        content:
          type: string
          description: "The full text content to write."
      required:
        - filename
        - content
      additionalProperties: false
```

`qwen_local_assistant`:
```yaml
    parameters:
      type: object
      properties:
        prompt:
          type: string
          description: "The analysis or drafting prompt to send to the local model."
      required:
        - prompt
      additionalProperties: false
```

`powershell_private`: same block as `powershell_open` above (script,
no_path_separators, required).

`python_private`: same block as `python_open` above.

`restricted_workflow_runner`: same block as `n8n_general_workflows` above
(workflow/payload).

`promote_skill` (Private entry): same block as `promote_skill` in the Open
file above.

- [ ] **Step 3: Verify both YAMLs still parse and have no duplicate keys**

Run: `cd cooper-core && .venv/bin/python -m pytest test_registry.py::test_registry_yaml_files_have_no_duplicate_keys -v`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Config/general_tool_registry.yaml Config/private_tool_registry.yaml
git commit -m "feat(config): add parameters schema to every registry tool (spec §3)"
```

---

### Task 3: Registry-walk test (M1) + wired-executor-types constant

**Files:**
- Modify: `cooper-core/executor.py` (add a constant only — no behavior change)
- Modify: `cooper-core/test_registry.py`

**Interfaces:**
- Produces: `executor.WIRED_EXECUTOR_TYPES: frozenset[str]` — the set of
  `executor_type` values `executor.run` actually dispatches to (excludes the
  generic `_stub` fallback). Consumed only by this task's test.

- [ ] **Step 1: Add `WIRED_EXECUTOR_TYPES` to `executor.py`**

In `cooper-core/executor.py`, add near the top (after the `_TIMEOUT`/
`_MAX_OUTPUT` constants, before the docstring-adjacent regexes):

```python
# Every executor_type `run()` actually dispatches to (excludes the generic
# `_stub` fallback for unrecognized types) — read by the registry-walk test
# (M1) to assert every registry tool maps to a real handler, not a stub.
WIRED_EXECUTOR_TYPES = frozenset({
    "powershell", "python", "skill_import", "skill_promote", "informational",
    "local_read", "filesystem", "local_llm", "note_editor", "llm_api",
    "browser", "workflow_engine", "cli_launcher",
})
```

- [ ] **Step 2: Add the registry-walk test to `test_registry.py`**

Append:

```python
import executor as executor_mod


def _synthetic_args(params: dict) -> dict:
    """Minimal args dict that satisfies a parameters schema's required keys —
    just enough to drive validate_args() through a real accept path."""
    out = {}
    for key in params.get("required", []):
        prop = params["properties"][key]
        t = prop.get("type")
        if t == "string":
            out[key] = "example"
        elif t == "array":
            item_type = (prop.get("items") or {}).get("type")
            out[key] = ["https://example.com"] if item_type == "string" else []
        elif t == "object":
            out[key] = {}
    return out


def test_every_enabled_tool_has_a_valid_wired_parameters_block():
    """Registry-walk test — this IS metric M1, permanently (spec §6.1). For
    every enabled tool in both registries: a parameters block exists and is
    well-formed, render_tool_schema emits a valid OpenAI shape, a synthetic
    schema-conforming call passes validate_args, and the tool's
    executor_type maps to a real executor.py handler (no live LLM)."""
    for workshop_name in ("open", "private"):
        for tool in registry.list_tools(workshop_name):
            params = tool.get("parameters")
            assert params is not None, f"{tool['id']} is missing a parameters block"
            assert params.get("type") == "object", tool["id"]
            assert "properties" in params, tool["id"]

            schema = registry.render_tool_schema(tool)
            assert schema["type"] == "function"
            assert schema["function"]["name"] == tool["id"]
            assert schema["function"]["parameters"] == params

            synthetic = _synthetic_args(params)
            violations = registry.validate_args(tool, synthetic)
            assert violations == [], f"{tool['id']}: {violations}"

            executor_type = tool.get("executor_type")
            assert executor_type in executor_mod.WIRED_EXECUTOR_TYPES, (
                f"{tool['id']}'s executor_type {executor_type!r} is not wired"
            )
```

- [ ] **Step 3: Run it**

Run: `cd cooper-core && .venv/bin/python -m pytest test_registry.py -v`
Expected: all tests pass, including the new registry-walk test (this
depends on Task 2's YAML edits already being in place).

- [ ] **Step 4: Commit**

```bash
git add cooper-core/executor.py cooper-core/test_registry.py
git commit -m "test(registry): add M1 registry-walk test over parameters + wired executors"
```

---

### Task 4: Approval ticket carries validated args

**Files:**
- Modify: `cooper-core/approval.py`
- Test: `cooper-core/test_approval.py`

**Interfaces:**
- Produces: `ApprovalTicket.args: dict` (default `{}`);
  `approval.request(workshop, tool, message, session_id="local", args=None)`
  — `args` is a new optional keyword param, backward compatible with every
  existing positional call site.
- Consumes: nothing new.

- [ ] **Step 1: Add the field and param**

In `cooper-core/approval.py`, change the import line:

```python
from dataclasses import dataclass, field
```

Change the dataclass:

```python
@dataclass
class ApprovalTicket:
    id: str
    workshop: str
    tool: dict
    message: str
    created_at: float
    session_id: str = "local"
    args: dict = field(default_factory=dict)
```

Change `request`:

```python
def request(
    workshop: str,
    tool: dict,
    message: str,
    session_id: str = "local",
    args: Optional[dict] = None,
) -> ApprovalTicket:
    """Open a pending ticket for this (workshop, session), replacing any prior one.
    Session binding (Step 13): only the session that opened a ticket can see or
    consume it — client A can never approve client B's action. `args` carries
    the tool_call's validated arguments through to execution on approve
    (Step 15a) — `main.py` reads `ticket.args` in `_execute`."""
    ticket = ApprovalTicket(
        id=uuid.uuid4().hex[:8],
        workshop=workshop,
        tool=tool,
        message=message,
        created_at=time.time(),
        session_id=session_id,
        args=args or {},
    )
    _pending[(workshop, session_id)] = ticket
    return ticket
```

- [ ] **Step 2: Add a test**

In `cooper-core/test_approval.py`, append:

```python
def test_ticket_stores_and_returns_args():
    ticket = approval.request(
        "open", _tool(), "write note x.md: hi", session_id="c",
        args={"filename": "x.md", "content": "hi"},
    )
    assert ticket.args == {"filename": "x.md", "content": "hi"}
    consumed = approval.consume("open", "c")
    assert consumed.args == {"filename": "x.md", "content": "hi"}


def test_ticket_args_defaults_to_empty_dict():
    ticket = approval.request("open", _tool(), "do it", session_id="c2")
    assert ticket.args == {}
```

- [ ] **Step 3: Run the approval test file**

Run: `cd cooper-core && .venv/bin/python -m pytest test_approval.py -v`
Expected: all tests pass (including the pre-existing ones, unaffected by
the new optional param).

- [ ] **Step 4: Commit**

```bash
git add cooper-core/approval.py cooper-core/test_approval.py
git commit -m "feat(approval): carry validated tool_call args on the ticket"
```

---

### Task 5: Skills — structured args instead of raw-message parsing

**Files:**
- Modify: `cooper-core/skills.py`
- Test: `cooper-core/test_skills.py`

**Interfaces:**
- Produces (new signatures, replacing the message-parsing versions):
  - `skills.preview_import(skill_name: str, tap_url: str, *, repo_root=None) -> str`
  - `skills.register_import(skill_name: str, tap_url: str, *, repo_root=None, manifest_path=None) -> dict`
  - `skills.discard_staged(skill_name: str, *, repo_root=None) -> bool`
  - `skills.preview_promote(skill_name: str, *, repo_root=None, manifest_path=None) -> str`
  - `skills.register_promotion(skill_name: str, *, workshop="open", repo_root=None, manifest_path=None) -> dict`
- Deletes: `skills.parse_import_request`, `skills.parse_promote_request`,
  `skills._IMPORT_RE`, `skills._PROMOTE_RE`.
- Consumes: `skills.fetch_tap(url, skill_name, ...)` and `skills._draft_dir(name, ...)`
  are unchanged (already take structured params, not raw messages).
- Consumed by: Task 6 (`executor.py`'s `_run_skill_import`/`_run_skill_promote`)
  and Task 8 (`main.py`'s preview calls and `_resolve_approval`'s
  `discard_staged` call).

- [ ] **Step 1: Rewrite the import functions**

In `cooper-core/skills.py`, delete `_IMPORT_RE` (the regex) and
`parse_import_request`. Replace `discard_staged`, `preview_import`, and
`register_import`:

```python
def discard_staged(skill_name: str, *, repo_root: Optional[Path] = None) -> bool:
    """Denied import: drop the staged _incoming/<name> dir. False if nothing
    is staged for this skill_name."""
    staged = (repo_root or _REPO_ROOT) / "Skills" / "_incoming" / skill_name
    if not staged.is_dir():
        return False
    shutil.rmtree(staged, ignore_errors=True)
    return True
```

```python
def preview_import(
    skill_name: str, tap_url: str, *, repo_root: Optional[Path] = None
) -> str:
    """Fetch + stage the skill, return its SKILL.md text for the approval question."""
    staged = fetch_tap(tap_url, skill_name, repo_root=repo_root)
    text = (staged / "SKILL.md").read_text(encoding="utf-8")
    if len(text) > _PREVIEW_MAX:
        text = text[:_PREVIEW_MAX] + "\n[... preview truncated]"
    return text


def register_import(
    skill_name: str,
    tap_url: str,
    *,
    repo_root: Optional[Path] = None,
    manifest_path: Optional[Path] = None,
) -> dict:
    """Post-approval: promote _incoming/<name> to Skills/imported/<name>, hash it,
    append the manifest entry (workshop: open — Private promotion is a separate
    approval, spec §3). Re-fetches if staging is missing (e.g. ticket expired)."""
    root = repo_root or _REPO_ROOT
    staged = root / "Skills" / "_incoming" / skill_name
    if not (staged / "SKILL.md").exists():
        print(f"  [!!] skill '{skill_name}' staged copy missing at registration — re-fetching from {tap_url}")
        staged = fetch_tap(tap_url, skill_name, repo_root=repo_root)
    final = root / "Skills" / "imported" / skill_name
    final.parent.mkdir(parents=True, exist_ok=True)
    if final.exists():
        shutil.rmtree(final)
    shutil.move(str(staged), str(final))
    entry = {
        "id": skill_name,
        "path": str(final.relative_to(root)).replace("\\", "/"),
        "workshop": "open",
        "permission_level": 1,
        "approval_required": False,
        "content_hash": compute_content_hash(final),
    }
    _append_manifest_entry(entry, manifest_path)
    return entry
```

- [ ] **Step 2: Rewrite the promotion functions**

Delete `_PROMOTE_RE` and `parse_promote_request`. Replace `preview_promote`
and `register_promotion` (keep `_draft_dir` unchanged):

```python
def preview_promote(
    skill_name: str,
    *,
    repo_root: Optional[Path] = None,
    manifest_path: Optional[Path] = None,
) -> str:
    """SKILL.md text for the approval question — from the draft, or (fallback,
    matching register_promotion) from an already-registered skill being
    promoted into another workshop."""
    root = repo_root or _REPO_ROOT
    try:
        d = _draft_dir(skill_name, repo_root)
    except SkillError:
        existing = next(
            (e for e in load_manifest(manifest_path) if str(e.get("id")) == skill_name), None
        )
        if existing is None:
            raise
        d = (root / str(existing["path"])).resolve()
        if not (d / "SKILL.md").exists():
            raise SkillError(f"registered skill '{skill_name}' has no SKILL.md on disk")
    text = (d / "SKILL.md").read_text(encoding="utf-8")
    return text[:_PREVIEW_MAX] + ("\n[... preview truncated]" if len(text) > _PREVIEW_MAX else "")


def register_promotion(
    skill_name: str,
    *,
    workshop: str = "open",
    repo_root: Optional[Path] = None,
    manifest_path: Optional[Path] = None,
) -> dict:
    """Post-approval: move the draft to Skills/learned/<name>, hash, register.
    Fallback (spec §3 'promoting a skill to Private is a second explicit
    approval'): when no draft exists but the skill is already registered for
    another workshop, add an entry for the ACTIVE workshop instead — this is
    how an imported Open skill gets promoted into Private."""
    root = repo_root or _REPO_ROOT
    try:
        src = _draft_dir(skill_name, repo_root)
    except SkillError:
        existing = next(
            (e for e in load_manifest(manifest_path) if str(e.get("id")) == skill_name), None
        )
        if existing is None:
            raise
        skill_dir = (root / str(existing["path"])).resolve()
        entry = {
            "id": skill_name,
            "path": existing["path"],
            "workshop": workshop,
            "permission_level": int(existing.get("permission_level", 1)),
            "approval_required": bool(existing.get("approval_required", False)),
            "content_hash": compute_content_hash(skill_dir),
        }
        _append_manifest_entry(entry, manifest_path)
        return entry
    final = root / "Skills" / "learned" / skill_name
    final.parent.mkdir(parents=True, exist_ok=True)
    if final.exists():
        shutil.rmtree(final)
    shutil.move(str(src), str(final))
    entry = {
        "id": skill_name,
        "path": str(final.relative_to(root)).replace("\\", "/"),
        "workshop": workshop,
        "permission_level": 1,
        "approval_required": False,
        "content_hash": compute_content_hash(final),
    }
    _append_manifest_entry(entry, manifest_path)
    return entry
```

- [ ] **Step 3: Update `test_skills.py`'s import/promote tests**

Open `cooper-core/test_skills.py`. Delete `test_parse_import_request` and
`test_parse_promote_request` entirely (the functions they test no longer
exist). For every remaining test that currently builds a natural-language
message and passes it to one of the five changed functions, replace the
message-building with direct `skill_name`/`tap_url` args. Concretely:

`test_fetch_tap_rejects_non_https` / `_rejects_symlink...` /
`_rejects_unsafe_skill_name` / `_rejects_oversized_tap` /
`_rejects_oversized_clone` call `skills.fetch_tap(url, name, ...)` directly
already — **unchanged**, `fetch_tap` isn't touched by this task.

`test_register_import_logs_refetch_when_staging_missing` — full replacement:

```python
def test_register_import_logs_refetch_when_staging_missing(tmp_path, monkeypatch, capsys):
    """Fix 4: registration re-fetching due to missing staged copy must be logged."""
    url = make_tap_repo(tmp_path)
    monkeypatch.setattr(skills, "_ALLOWED_SCHEMES", ("https://", "file://"))
    manifest = write_manifest(tmp_path, [])

    # Skip preview_import (which would stage it) and register directly —
    # staged dir is missing, forcing the re-fetch path.
    entry = skills.register_import("tap-skill", url, repo_root=tmp_path, manifest_path=manifest)
    assert entry["id"] == "tap-skill"
    output = capsys.readouterr().out
    assert "[!!]" in output and "re-fetching" in output
```

`test_import_flow_end_to_end` — full replacement:

```python
def test_import_flow_end_to_end(tmp_path, monkeypatch):
    url = make_tap_repo(tmp_path)
    monkeypatch.setattr(skills, "_ALLOWED_SCHEMES", ("https://", "file://"))
    manifest = write_manifest(tmp_path, [])

    preview = skills.preview_import("tap-skill", url, repo_root=tmp_path)
    assert "Imported test skill" in preview
    # staged in _incoming — still inert
    assert skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path) == []

    entry = skills.register_import("tap-skill", url, repo_root=tmp_path, manifest_path=manifest)
    assert entry["id"] == "tap-skill"
    assert entry["workshop"] == "open"
    assert (tmp_path / "Skills" / "imported" / "tap-skill" / "SKILL.md").exists()
    loaded = skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path)
    assert [s.name for s in loaded] == ["tap-skill"]
```

Delete `test_parse_import_request` and `test_parse_promote_request`
entirely (already noted above — listing again here since they sit right
next to the functions above/below in the file).

`test_promotion_flow` — full replacement:

```python
def test_promotion_flow(tmp_path):
    make_draft(tmp_path)
    manifest = write_manifest(tmp_path, [])
    preview = skills.preview_promote("stack-health-check", repo_root=tmp_path)
    assert "Drafted procedure" in preview
    entry = skills.register_promotion(
        "stack-health-check",
        workshop="open", repo_root=tmp_path, manifest_path=manifest,
    )
    assert entry["id"] == "stack-health-check"
    assert (tmp_path / "Skills" / "learned" / "stack-health-check" / "SKILL.md").exists()
    assert not (tmp_path / "Skills" / "_drafts" / "stack-health-check").exists()
    loaded = skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path)
    assert [s.name for s in loaded] == ["stack-health-check"]
```

`test_promote_missing_draft_raises` — full replacement:

```python
def test_promote_missing_draft_raises(tmp_path):
    with pytest.raises(skills.SkillError):
        skills.preview_promote("ghost", repo_root=tmp_path)
```

`test_promote_registered_open_skill_into_private` — full replacement:

```python
def test_promote_registered_open_skill_into_private(tmp_path):
    # no draft — the skill is already live in Open; promotion adds a Private entry
    d = make_skill_dir(tmp_path, name="hello-cooper")
    manifest = write_manifest(tmp_path, [approved_entry(tmp_path, d)])
    entry = skills.register_promotion(
        "hello-cooper",
        workshop="private", repo_root=tmp_path, manifest_path=manifest,
    )
    assert entry["workshop"] == "private"
    # both workshops now load it — the Open entry survived the append
    assert len(skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path)) == 1
    assert len(skills.list_skills("private", manifest_path=manifest, repo_root=tmp_path)) == 1
```

`test_discard_staged_removes_staging_dir` — full replacement:

```python
def test_discard_staged_removes_staging_dir(tmp_path, monkeypatch):
    """Denied imports must be able to clean their Skills/_incoming/<name> staging
    dir; discarding again (or a name with nothing staged) is a silent no-op."""
    url = make_tap_repo(tmp_path)
    monkeypatch.setattr(skills, "_ALLOWED_SCHEMES", ("https://", "file://"))
    skills.preview_import("tap-skill", url, repo_root=tmp_path)
    staged = tmp_path / "Skills" / "_incoming" / "tap-skill"
    assert staged.exists()

    assert skills.discard_staged("tap-skill", repo_root=tmp_path) is True
    assert not staged.exists()
    assert skills.discard_staged("tap-skill", repo_root=tmp_path) is False
    assert skills.discard_staged("no-such-skill", repo_root=tmp_path) is False
```

- [ ] **Step 4: Run the skills test file**

Run: `cd cooper-core && .venv/bin/python -m pytest test_skills.py -v`
Expected: all tests pass. If a test fails because it still references
`msg`/`parse_import_request`/`parse_promote_request`, fix that specific
test's setup to build the literal strings directly instead of parsing them
out of a sentence — read the failing test's context to find the exact
values it was using.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/skills.py cooper-core/test_skills.py
git commit -m "feat(skills): take structured skill_name/tap_url args instead of parsing raw messages"
```

---

### Task 6: Executor — args-driven handlers, delete parsing regexes

**Files:**
- Modify: `cooper-core/executor.py`
- Test: `cooper-core/test_executor.py`

**Interfaces:**
- Produces: `executor.run(tool: dict, message: str, workshop: str, args: Optional[dict] = None) -> str`
  — `args` is new; `message` stays (still used by `_run_informational` and
  passed through to `review.review`/`_post_dispatch` by `main.py`, unchanged
  there).
- Consumes: Task 5's new `skills.register_import(skill_name, tap_url, ...)`
  / `skills.register_promotion(skill_name, *, workshop, ...)` signatures.
- Deletes: `_DMZ_WRITE_RE`, `_NOTE_WRITE_RE`, `_MODEL_HINT_RE`, `_URL_RE`,
  `_resolve_script_in_dir`, `_resolve_script`, `_resolve_python_script`
  (replaced by one `_resolve_named_script(name, scripts_dir)`).

- [ ] **Step 1: Replace the message-parsing regexes and script resolvers**

In `cooper-core/executor.py`, delete these four regex constants:
`_DMZ_WRITE_RE`, `_NOTE_WRITE_RE`, `_MODEL_HINT_RE`, `_URL_RE` (keep
`_CODEX_*` regexes — those parse `request` text for title/slug generation,
which is still free text by design, not touched by this spec).

Delete `_resolve_script_in_dir`, `_resolve_script`, and
`_resolve_python_script`. Replace with:

```python
def _resolve_named_script(name: str, scripts_dir: Path) -> Optional[Path]:
    """Resolve a script filename named directly in validated args against
    scripts_dir. Any path traversal is neutralized before the existence
    check (Path(...).name strips directories; relative_to confirms
    containment)."""
    clean = Path(name).name
    if not clean:
        return None
    candidate = (scripts_dir / clean).resolve()
    try:
        candidate.relative_to(scripts_dir.resolve())
    except ValueError:
        return None
    return candidate if candidate.exists() else None
```

- [ ] **Step 2: Rewrite `_run_filesystem` and `_run_note_editor` to take `args`**

```python
async def _run_filesystem(args: dict) -> str:
    """Restricted DMZ Writer (Private only). New files only — governance
    classifies overwrites as Level 5 (blocked by default), so an existing
    path is refused rather than silently replaced."""
    filename = Path(str(args.get("filename", ""))).name
    content = str(args.get("content", "")).strip()
    if not filename or not content:
        return "Workbench: DMZ write request has no content to write."
    content_bytes = content.encode("utf-8")
    if len(content_bytes) > _MAX_DMZ_CONTENT_BYTES:
        return (
            f"Workbench: content is {len(content_bytes)} bytes, over the "
            f"{_MAX_DMZ_CONTENT_BYTES}-byte cap for a DMZ write."
        )

    loop = asyncio.get_running_loop()

    def _sync_write() -> str:
        dest = (_DMZ_DIR / filename).resolve()
        try:
            dest.relative_to(_DMZ_DIR.resolve())
        except ValueError:
            return f"Workbench: '{filename}' resolves outside the DMZ Workspace — refused."
        existed = dest.exists()
        _DMZ_DIR.mkdir(parents=True, exist_ok=True)
        dest.write_text(content, encoding="utf-8")
        verb = "Updated" if existed else "Wrote"
        return f"{verb} '{filename}' in the Restricted DMZ Workspace ({len(content_bytes)} bytes)."

    try:
        return await loop.run_in_executor(None, _sync_write)
    except Exception as exc:
        return f"Workbench: DMZ write failed unexpectedly — {exc}"


async def _run_note_editor(args: dict) -> str:
    """Obsidian Note Writer (Open only). Create-or-update, same Level 2
    reasoning as _run_filesystem. Writes into 00_Inbox/ per 08_Obsidian
    Vault Structure.md's recommended layout."""
    filename = Path(str(args.get("filename", "")).strip()).name
    content = str(args.get("content", "")).strip()
    if not filename or not content:
        return "Workbench: note write request has no content to write."
    content_bytes = content.encode("utf-8")
    if len(content_bytes) > _MAX_NOTE_CONTENT_BYTES:
        return (
            f"Workbench: content is {len(content_bytes)} bytes, over the "
            f"{_MAX_NOTE_CONTENT_BYTES}-byte cap for a note write."
        )

    loop = asyncio.get_running_loop()

    def _sync_write() -> str:
        dest = (_OBSIDIAN_INBOX_DIR / filename).resolve()
        try:
            dest.relative_to(_OBSIDIAN_INBOX_DIR.resolve())
        except ValueError:
            return f"Workbench: '{filename}' resolves outside the Knowledge Shelf inbox — refused."
        existed = dest.exists()
        _OBSIDIAN_INBOX_DIR.mkdir(parents=True, exist_ok=True)
        dest.write_text(content, encoding="utf-8")
        verb = "Updated" if existed else "Created"
        return f"{verb} note '{filename}' in the Obsidian Knowledge Shelf inbox ({len(content_bytes)} bytes)."

    try:
        return await loop.run_in_executor(None, _sync_write)
    except Exception as exc:
        return f"Workbench: note write failed unexpectedly — {exc}"
```

- [ ] **Step 3: Rewrite `_run_llm_api` and `_run_local_llm`**

```python
async def _run_llm_api(args: dict) -> str:
    """LiteLLM Router (Open only) — routes an approved prompt to LiteLLM's
    chat-completions endpoint. args.prompt is the clean instruction text
    with no tool-invocation framing (the 2026-07-21 'framing text sent as
    prompt' bug class dies with the regex it required)."""
    model = args.get("model") or _LITELLM_DEFAULT_MODEL
    prompt = str(args.get("prompt", "")).strip()
    if not prompt:
        return "Workbench: LiteLLM Router request has no prompt to route."
    try:
        response = await _openai_complete(
            _LITELLM_BASE_URL, _LITELLM_API_KEY, model,
            [{"role": "user", "content": prompt}],
        )
    except Exception as exc:
        raise ExecutionError(f"LiteLLM routing failed — {exc}")
    return f"[LiteLLM Router — model: {model}]\n{response.strip()}"


async def _run_local_llm(args: dict) -> str:
    """Qwen Local Assistant (Private only) — specialist analysis/drafting route."""
    prompt = str(args.get("prompt", "")).strip()
    if not prompt:
        return "Workbench: no prompt supplied for local analysis."
    try:
        draft = await _ollama_complete(
            _OLLAMA_HOST, _QWEN_MODEL,
            [
                {"role": "system", "content": _QWEN_ANALYSIS_SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
        )
    except Exception as exc:
        raise ExecutionError(f"local analysis backend unavailable — {exc}")
    return f"[Qwen Local Assistant — draft]\n{draft.strip()}"
```

- [ ] **Step 4: Rewrite `_run_browser`**

```python
async def _run_browser(args: dict) -> str:
    """Browser Research (Open only). HTTP fetch + stdlib HTML→text extraction
    per decision #2 — no Playwright/Selenium. Won't render JS-only pages."""
    urls = args.get("urls") or []
    url = str(urls[0]).strip().rstrip(".,)") if urls else ""
    if not url.startswith(("http://", "https://")):
        return "Workbench: no http(s):// URL found in request."

    loop = asyncio.get_running_loop()

    async def _fetch() -> str:
        async with httpx.AsyncClient(
            timeout=_FETCH_TIMEOUT, follow_redirects=True
        ) as client:
            resp = await client.get(url)
            resp.raise_for_status()
            raw = resp.content[:_MAX_FETCH_BYTES]
            return raw.decode(resp.encoding or "utf-8", errors="replace")

    try:
        html = await _fetch()
    except Exception as exc:
        raise ExecutionError(f"fetch failed for '{url}' — {exc}")

    def _extract() -> str:
        parser = _HTMLTextExtractor()
        parser.feed(html)
        return parser.text()

    text = await loop.run_in_executor(None, _extract)
    text = text[:_MAX_OUTPUT].strip()
    return f"[Browser Research — {url}]\n{text}"
```

- [ ] **Step 5: Rewrite `_run_workflow_engine` and `_run_cli_launcher`**

```python
async def _run_workflow_engine(tool: dict, args: dict, workshop: str) -> str:
    """n8n workflow trigger (Open only — no reachable instance from
    Private). allowed_workflows maps a workflow id to a webhook path; per
    the Batch -1 finding, this mapping is a manually-reviewed-safe
    allowlist, not just an existence check."""
    if workshop != "open":
        return (
            "Workbench: no n8n (or equivalent) workflow engine is deployed for "
            "the Private Workshop — this tool has nothing to call yet."
        )

    allowed = tool.get("allowed_workflows") or {}
    if not allowed:
        return (
            f"Workbench: tool '{tool.get('name', tool.get('id', 'unknown'))}' has no "
            "allowed_workflows mapping in its registry entry. Execution is fail-closed."
        )

    workflow_id = str(args.get("workflow", ""))
    if workflow_id not in allowed:
        return (
            f"Workbench: no known workflow_id found in request. "
            f"Known workflows: {', '.join(sorted(allowed))}."
        )
    webhook_path = allowed[workflow_id]
    payload_text = str(args.get("payload") or "")

    try:
        async with httpx.AsyncClient(timeout=_FETCH_TIMEOUT) as client:
            resp = await client.post(
                f"{_N8N_BASE_URL}/webhook/{webhook_path}",
                json={"command": payload_text, "message": payload_text},
            )
            resp.raise_for_status()
            result_text = resp.text[:_MAX_OUTPUT]
    except Exception as exc:
        raise ExecutionError(f"n8n workflow '{workflow_id}' call failed — {exc}")
    return f"[n8n workflow: {workflow_id}]\n{result_text.strip()}"


async def _run_cli_launcher(args: dict) -> str:
    """Codex Task Launcher (Open only) — Level 2 template-writing half of
    WF-002 only. Each dispatch gets a fresh timestamped filename."""
    request_text = str(args.get("request", ""))
    title = _codex_task_title(request_text)
    slug = _codex_task_slug(request_text)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    filename = f"TASK-{timestamp}-{slug}.md"
    content = _codex_task_markdown(title, request_text)

    loop = asyncio.get_running_loop()

    def _sync_write() -> str:
        _CODEX_TASKS_DIR.mkdir(parents=True, exist_ok=True)
        dest = _CODEX_TASKS_DIR / filename
        dest.write_text(content, encoding="utf-8")
        return f"Created Codex task '{filename}' (title: \"{title}\")."

    try:
        return await loop.run_in_executor(None, _sync_write)
    except Exception as exc:
        return f"Workbench: Codex task creation failed unexpectedly — {exc}"
```

- [ ] **Step 6: Rewrite `_run_powershell` and `_run_python`**

```python
async def _run_powershell(tool: dict, args: dict) -> str:
    script_name = str(args.get("script", ""))
    script = _resolve_named_script(script_name, _SCRIPTS_DIR)

    if script is None:
        return (
            f"Workbench: script '{script_name}' does not exist in Scripts/. "
            "Rephrase with the script filename (e.g. 'Test-PDAStack.ps1')."
        )

    denial = _authorize_script(script, tool)
    if denial is not None:
        return denial

    loop = asyncio.get_running_loop()

    def _sync_run() -> str:
        for shell in ("powershell.exe", "pwsh"):
            try:
                result = subprocess.run(
                    [shell, "-NonInteractive", "-NoProfile", "-File", str(script)],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    cwd=str(_REPO_ROOT),
                    timeout=_TIMEOUT,
                )
                raw = result.stdout
                output = raw[:_MAX_OUTPUT].decode("utf-8", errors="replace").strip()
                truncated = len(raw) > _MAX_OUTPUT
                exit_label = "OK" if result.returncode == 0 else f"exit {result.returncode}"
                res = f"[{script.name} — {exit_label}]\n{output}"
                if truncated:
                    res += f"\n[... output truncated at {_MAX_OUTPUT} bytes]"
                return res
            except FileNotFoundError:
                continue
            except subprocess.TimeoutExpired:
                raise ExecutionError(f"{script.name} timed out after {_TIMEOUT}s")
        raise ExecutionError(
            "Neither powershell.exe nor pwsh found — ensure PowerShell is on PATH"
        )

    try:
        return await loop.run_in_executor(None, _sync_run)
    except ExecutionError:
        raise
    except Exception as exc:
        raise ExecutionError(f"executor error ({type(exc).__name__}): {exc}")


async def _run_python(tool: dict, args: dict) -> str:
    """Mirrors _run_powershell exactly, for .py scripts under Scripts/Python/."""
    script_name = str(args.get("script", ""))
    script = _resolve_named_script(script_name, _SCRIPTS_PY_DIR)

    if script is None:
        return (
            f"Workbench: script '{script_name}' does not exist in Scripts/Python/. "
            "Rephrase with the script filename (e.g. 'Test-Exec.py')."
        )

    denial = _authorize_script(script, tool)
    if denial is not None:
        return denial

    loop = asyncio.get_running_loop()

    def _sync_run() -> str:
        try:
            result = subprocess.run(
                [sys.executable, str(script)],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                cwd=str(_REPO_ROOT),
                timeout=_TIMEOUT,
            )
        except subprocess.TimeoutExpired:
            raise ExecutionError(f"{script.name} timed out after {_TIMEOUT}s")
        raw = result.stdout
        output = raw[:_MAX_OUTPUT].decode("utf-8", errors="replace").strip()
        truncated = len(raw) > _MAX_OUTPUT
        exit_label = "OK" if result.returncode == 0 else f"exit {result.returncode}"
        res = f"[{script.name} — {exit_label}]\n{output}"
        if truncated:
            res += f"\n[... output truncated at {_MAX_OUTPUT} bytes]"
        return res

    try:
        return await loop.run_in_executor(None, _sync_run)
    except ExecutionError:
        raise
    except Exception as exc:
        raise ExecutionError(f"executor error ({type(exc).__name__}): {exc}")
```

- [ ] **Step 7: Rewrite `_run_skill_import` and `_run_skill_promote`**

```python
async def _run_skill_import(args: dict) -> str:
    """Post-approval skill registration. Network + filesystem work off-loop."""
    loop = asyncio.get_running_loop()
    skill_name = str(args.get("skill_name", ""))
    tap_url = str(args.get("tap_url", ""))

    def _sync() -> str:
        entry = skills.register_import(skill_name, tap_url)
        content_hash = entry.get("content_hash", "?")
        return (
            f"Skill '{entry.get('id', '?')}' imported and registered for the "
            f"{entry.get('workshop', '?')} workshop "
            f"(hash {content_hash[:12] if content_hash != '?' else '?'}…). "
            f"It is now live. Promote to Private only via a separate approval."
        )

    try:
        return await loop.run_in_executor(None, _sync)
    except skills.SkillError as exc:
        return f"Workbench: skill import failed — {exc}"
    except Exception as exc:
        return f"Workbench: skill import failed unexpectedly — {exc}"


async def _run_skill_promote(args: dict, workshop: str) -> str:
    """Post-approval draft activation. Filesystem work off-loop, same
    degrade-gracefully contract as _run_skill_import."""
    loop = asyncio.get_running_loop()
    skill_name = str(args.get("skill_name", ""))

    def _sync() -> str:
        entry = skills.register_promotion(skill_name, workshop=workshop)
        content_hash = entry.get("content_hash", "?")
        return (
            f"Skill '{entry.get('id', '?')}' promoted from draft and registered for the "
            f"{entry.get('workshop', '?')} workshop "
            f"(hash {content_hash[:12] if content_hash != '?' else '?'}…)."
        )

    try:
        return await loop.run_in_executor(None, _sync)
    except skills.SkillError as exc:
        return f"Workbench: skill promotion failed — {exc}"
    except Exception as exc:
        return f"Workbench: skill promotion failed unexpectedly — {exc}"
```

- [ ] **Step 8: Update `run()`'s dispatcher**

```python
async def run(tool: dict, message: str, workshop: str, args: Optional[dict] = None) -> str:
    """
    Execute an approved tool and return the result string.

    Raises ExecutionError on hard failures (script not found, timeout, etc.).
    Non-fatal output (non-zero exit code with stderr) is returned as text,
    not raised, so COOPER can relay it conversationally.
    """
    executor_type = tool.get("executor_type", "")
    tool_name     = tool.get("name", tool.get("id", "unknown"))
    args = args or {}

    if executor_type == "powershell":
        return await _run_powershell(tool, args)

    if executor_type == "python":
        return await _run_python(tool, args)

    if executor_type == "skill_import":
        return await _run_skill_import(args)

    if executor_type == "skill_promote":
        return await _run_skill_promote(args, workshop)

    if executor_type == "informational":
        return _run_informational(tool, message, workshop)

    if executor_type == "local_read":
        return _run_local_read(tool, workshop)

    if executor_type == "filesystem":
        return await _run_filesystem(args)

    if executor_type == "local_llm":
        return await _run_local_llm(args)

    if executor_type == "note_editor":
        return await _run_note_editor(args)

    if executor_type == "llm_api":
        return await _run_llm_api(args)

    if executor_type == "browser":
        return await _run_browser(args)

    if executor_type == "workflow_engine":
        return await _run_workflow_engine(tool, args, workshop)

    if executor_type == "cli_launcher":
        return await _run_cli_launcher(args)

    return _stub(executor_type, tool_name)
```

`_run_informational(tool, message, workshop)` and `_run_local_read(tool,
workshop)` stay exactly as they are today — no args.

- [ ] **Step 9: Rewrite `test_executor.py`**

Every test that builds a natural-language `message` and calls
`executor.run(tool, message, workshop)` must instead pass a structured
`args` dict as the 4th positional/keyword argument, and any test that calls
a now-args-based `_run_*` helper directly must update that call too. Work
through the file top to bottom:

Script-resolution tests — replace the two free-text resolver tests with
direct resolver tests:

```python
def test_resolve_named_script_finds_existing_script():
    script = executor._resolve_named_script("Test-Exec.ps1", executor._SCRIPTS_DIR)
    assert script is not None
    assert script.name == "Test-Exec.ps1"


def test_resolve_named_script_returns_none_for_unknown_script():
    assert executor._resolve_named_script("Definitely-Not-Real-XYZ.ps1", executor._SCRIPTS_DIR) is None


def test_resolve_named_script_neutralizes_traversal():
    script = executor._resolve_named_script("../../Test-Exec.ps1", executor._SCRIPTS_DIR)
    assert script is None or script.parent == executor._SCRIPTS_DIR.resolve()
```

(`_authorize_script` tests are unchanged — that function's signature never
took a message.)

```python
def test_run_refuses_unlisted_script_without_spawning():
    result = asyncio.run(
        executor.run(ALLOWED_TOOL, "run it", "private", {"script": "Test-PDAStack.ps1"})
    )
    assert "allowed_scripts" in result


def test_run_returns_stub_for_unwired_executor():
    result = asyncio.run(
        executor.run({"executor_type": "totally_unknown_type", "name": "X"}, "x", "open", {})
    )
    assert "not yet wired" in result
```

Skill import/promote tests — `register_import`/`register_promotion` fakes
now take `(skill_name, tap_url)` / `(skill_name, *, workshop)` instead of
`(message, **kw)`; keep the fakes accepting `*args, **kw` so the assertions
stay focused on the executor's own behavior, and drive `executor.run` with
`args=` instead of a sentence:

```python
def test_skill_import_executor(monkeypatch):
    monkeypatch.setattr(
        skills_mod, "register_import",
        lambda *a, **kw: {"id": "tap-skill", "workshop": "open",
                          "content_hash": "ab" * 32},
    )
    tool = {"id": "import_skill", "name": "Import Skill", "executor_type": "skill_import"}
    out = asyncio.run(executor.run(
        tool, "import", "open", {"skill_name": "tap-skill", "tap_url": "https://x/y"}
    ))
    assert "tap-skill" in out and "imported" in out.lower()


def test_skill_import_executor_reports_failure(monkeypatch):
    def boom(*a, **kw):
        raise skills_mod.SkillError("bad tap")
    monkeypatch.setattr(skills_mod, "register_import", boom)
    tool = {"id": "import_skill", "name": "Import Skill", "executor_type": "skill_import"}
    out = asyncio.run(executor.run(
        tool, "import", "open", {"skill_name": "x", "tap_url": "https://x/y"}
    ))
    assert "failed" in out.lower() and "bad tap" in out


def test_skill_import_executor_degrades_on_unexpected_exception(monkeypatch):
    def boom(*a, **kw):
        raise RuntimeError("connection reset by peer")
    monkeypatch.setattr(skills_mod, "register_import", boom)
    tool = {"id": "import_skill", "name": "Import Skill", "executor_type": "skill_import"}
    out = asyncio.run(executor.run(
        tool, "import", "open", {"skill_name": "x", "tap_url": "https://x/y"}
    ))
    assert isinstance(out, str)
    assert "unexpectedly" in out.lower()
    assert "connection reset by peer" in out


def test_skill_import_executor_defends_malformed_entry_shape(monkeypatch):
    monkeypatch.setattr(skills_mod, "register_import", lambda *a, **kw: {})
    tool = {"id": "import_skill", "name": "Import Skill", "executor_type": "skill_import"}
    out = asyncio.run(executor.run(
        tool, "import", "open", {"skill_name": "x", "tap_url": "https://x/y"}
    ))
    assert isinstance(out, str)
    assert "?" in out


def test_skill_promote_executor(monkeypatch):
    monkeypatch.setattr(
        skills_mod, "register_promotion",
        lambda name, **kw: {"id": "stack-health-check", "workshop": kw.get("workshop", "open"),
                            "content_hash": "cd" * 32},
    )
    tool = {"id": "promote_skill", "name": "Promote Skill", "executor_type": "skill_promote"}
    out = asyncio.run(executor.run(
        tool, "promote", "open", {"skill_name": "stack-health-check"}
    ))
    assert "stack-health-check" in out and "promoted" in out.lower()


def test_skill_promote_executor_reports_failure(monkeypatch):
    def boom(name, **kw):
        raise skills_mod.SkillError("no draft named 'x'")
    monkeypatch.setattr(skills_mod, "register_promotion", boom)
    tool = {"id": "promote_skill", "name": "Promote Skill", "executor_type": "skill_promote"}
    out = asyncio.run(executor.run(tool, "promote", "open", {"skill_name": "x"}))
    assert "failed" in out.lower() and "no draft named" in out


def test_skill_promote_executor_degrades_on_unexpected_exception(monkeypatch):
    def boom(name, **kw):
        raise RuntimeError("disk full")
    monkeypatch.setattr(skills_mod, "register_promotion", boom)
    tool = {"id": "promote_skill", "name": "Promote Skill", "executor_type": "skill_promote"}
    out = asyncio.run(executor.run(tool, "promote", "open", {"skill_name": "x"}))
    assert isinstance(out, str)
    assert "unexpectedly" in out.lower()
    assert "disk full" in out


def test_skill_promote_executor_defends_malformed_entry_shape(monkeypatch):
    monkeypatch.setattr(skills_mod, "register_promotion", lambda name, **kw: {})
    tool = {"id": "promote_skill", "name": "Promote Skill", "executor_type": "skill_promote"}
    out = asyncio.run(executor.run(tool, "promote", "open", {"skill_name": "x"}))
    assert isinstance(out, str)
    assert "?" in out


def test_skill_promote_executor_passes_active_workshop(monkeypatch):
    seen = {}
    def spy(name, **kw):
        seen["workshop"] = kw.get("workshop")
        return {"id": "x", "workshop": kw.get("workshop"), "content_hash": "ef" * 32}
    monkeypatch.setattr(skills_mod, "register_promotion", spy)
    tool = {"id": "promote_skill", "name": "Promote Skill", "executor_type": "skill_promote"}
    asyncio.run(executor.run(tool, "promote", "private", {"skill_name": "x"}))
    assert seen["workshop"] == "private"
```

Python-script tests — mirror the powershell ones:

```python
def test_python_executor_runs_allowed_script():
    result = asyncio.run(
        executor.run(PYTHON_ALLOWED_TOOL, "run it", "private", {"script": "Test-Exec.py"})
    )
    assert "Test-Exec.py" in result
    assert "OK" in result


def test_python_executor_refuses_unlisted_script_without_spawning():
    tool = {"id": "python_private", "name": "Python Private Runner", "executor_type": "python"}
    result = asyncio.run(executor.run(tool, "run it", "private", {"script": "Test-Exec.py"}))
    assert "fail-closed" in result
```

Filesystem tests — replace natural-language messages with `args`, and drop
the "unparseable message" test (structured args can't be "unparseable" —
validation now happens pre-approval via `registry.validate_args`, tested in
Task 1/3); add an "empty content" defense-in-depth test instead:

```python
def test_filesystem_executor_writes_new_file(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_DMZ_DIR", tmp_path)
    out = asyncio.run(executor.run(
        {"executor_type": "filesystem"}, "write", "private",
        {"filename": "notes.txt", "content": "hello world"},
    ))
    assert "Wrote 'notes.txt'" in out
    assert (tmp_path / "notes.txt").read_text() == "hello world"


def test_filesystem_executor_updates_existing_file(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_DMZ_DIR", tmp_path)
    (tmp_path / "existing.txt").write_text("original")
    out = asyncio.run(executor.run(
        {"executor_type": "filesystem"}, "write", "private",
        {"filename": "existing.txt", "content": "replacement"},
    ))
    assert "Updated 'existing.txt'" in out
    assert (tmp_path / "existing.txt").read_text() == "replacement"


def test_filesystem_executor_neutralizes_traversal(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_DMZ_DIR", tmp_path)
    out = asyncio.run(executor.run(
        {"executor_type": "filesystem"}, "write", "private",
        {"filename": "../../etc/passwd", "content": "pwned"},
    ))
    assert not (tmp_path.parent / "etc").exists()


def test_filesystem_executor_rejects_empty_content():
    out = asyncio.run(executor.run(
        {"executor_type": "filesystem"}, "write", "private",
        {"filename": "x.txt", "content": ""},
    ))
    assert "no content" in out.lower()
```

Local LLM tests — unchanged assertions, args-based call:

```python
def test_local_llm_executor_calls_ollama(monkeypatch):
    async def fake_complete(base_url, model, messages, **kw):
        assert messages[0]["role"] == "system"
        assert messages[1]["content"] == "analyze this"
        return "  drafted analysis text  "
    monkeypatch.setattr(executor, "_ollama_complete", fake_complete)
    out = asyncio.run(executor.run(
        {"executor_type": "local_llm"}, "run", "private", {"prompt": "analyze this"}
    ))
    assert "Qwen Local Assistant" in out
    assert "drafted analysis text" in out


def test_local_llm_executor_raises_execution_error_on_backend_failure(monkeypatch):
    async def boom(base_url, model, messages, **kw):
        raise RuntimeError("connection refused")
    monkeypatch.setattr(executor, "_ollama_complete", boom)
    try:
        asyncio.run(executor.run(
            {"executor_type": "local_llm"}, "run", "private", {"prompt": "analyze this"}
        ))
        assert False, "expected ExecutionError"
    except executor.ExecutionError as exc:
        assert "connection refused" in str(exc)
```

Note editor tests — args-based, drop the "unparseable" test, add an
empty-content one:

```python
def test_note_editor_creates_new_note(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_OBSIDIAN_INBOX_DIR", tmp_path)
    out = asyncio.run(executor.run(
        {"executor_type": "note_editor"}, "write", "open",
        {"filename": "idea.md", "content": "some idea content"},
    ))
    assert "Created note 'idea.md'" in out
    assert (tmp_path / "idea.md").read_text() == "some idea content"


def test_note_editor_updates_existing_note(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_OBSIDIAN_INBOX_DIR", tmp_path)
    (tmp_path / "idea.md").write_text("old")
    out = asyncio.run(executor.run(
        {"executor_type": "note_editor"}, "write", "open",
        {"filename": "idea.md", "content": "new content"},
    ))
    assert "Updated note 'idea.md'" in out
    assert (tmp_path / "idea.md").read_text() == "new content"


def test_note_editor_rejects_empty_content():
    out = asyncio.run(executor.run(
        {"executor_type": "note_editor"}, "write", "open",
        {"filename": "idea.md", "content": ""},
    ))
    assert "no content" in out.lower()
```

LLM API tests — the "extracts prompt after colon" test no longer applies
(there's no colon-splitting left); replace it with a test proving the
prompt passes through clean regardless of framing text elsewhere in the
turn (there is none anymore — args.prompt IS the prompt):

```python
def test_llm_api_executor_routes_through_litellm(monkeypatch):
    async def fake_complete(base_url, api_key, model, messages, **kw):
        assert model == "claude-sonnet"
        return "  routed response  "
    monkeypatch.setattr(executor, "_openai_complete", fake_complete)
    out = asyncio.run(executor.run(
        {"executor_type": "llm_api"}, "run", "open",
        {"prompt": "summarize this", "model": "claude-sonnet"},
    ))
    assert "routed response" in out
    assert "claude-sonnet" in out


def test_llm_api_executor_defaults_model_when_unspecified(monkeypatch):
    seen = {}
    async def fake_complete(base_url, api_key, model, messages, **kw):
        seen["model"] = model
        return "ok"
    monkeypatch.setattr(executor, "_openai_complete", fake_complete)
    asyncio.run(executor.run(
        {"executor_type": "llm_api"}, "run", "open", {"prompt": "summarize this"}
    ))
    assert seen["model"] == executor._LITELLM_DEFAULT_MODEL


def test_llm_api_executor_passes_prompt_through_clean(monkeypatch):
    seen = {}
    async def fake_complete(base_url, api_key, model, messages, **kw):
        seen["prompt"] = messages[0]["content"]
        return "ok"
    monkeypatch.setattr(executor, "_openai_complete", fake_complete)
    asyncio.run(executor.run(
        {"executor_type": "llm_api"}, "run", "open", {"prompt": "say the word banana"}
    ))
    assert seen["prompt"] == "say the word banana"


def test_llm_api_executor_raises_execution_error_on_failure(monkeypatch):
    async def boom(base_url, api_key, model, messages, **kw):
        raise RuntimeError("502 bad gateway")
    monkeypatch.setattr(executor, "_openai_complete", boom)
    try:
        asyncio.run(executor.run(
            {"executor_type": "llm_api"}, "run", "open", {"prompt": "hi"}
        ))
        assert False, "expected ExecutionError"
    except executor.ExecutionError as exc:
        assert "502 bad gateway" in str(exc)
```

Browser tests — args-based `urls`:

```python
def test_browser_executor_extracts_text_from_fetched_html(monkeypatch):
    class FakeResponse:
        content = b"<html><body><script>ignoreMe()</script><p>Hello world</p></body></html>"
        encoding = "utf-8"
        def raise_for_status(self): pass

    class FakeClient:
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        async def get(self, url): return FakeResponse()

    monkeypatch.setattr(executor.httpx, "AsyncClient", lambda **kw: FakeClient())
    out = asyncio.run(executor.run(
        {"executor_type": "browser"}, "research", "open",
        {"urls": ["https://example.com/page"]},
    ))
    assert "Hello world" in out
    assert "ignoreMe" not in out
    assert "https://example.com/page" in out


def test_browser_executor_rejects_no_urls():
    out = asyncio.run(executor.run(
        {"executor_type": "browser"}, "look something up", "open", {"urls": []}
    ))
    assert "no http" in out.lower()


def test_browser_executor_raises_execution_error_on_fetch_failure(monkeypatch):
    class FakeClient:
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        async def get(self, url): raise RuntimeError("connection reset")

    monkeypatch.setattr(executor.httpx, "AsyncClient", lambda **kw: FakeClient())
    try:
        asyncio.run(executor.run(
            {"executor_type": "browser"}, "research", "open",
            {"urls": ["https://example.com"]},
        ))
        assert False, "expected ExecutionError"
    except executor.ExecutionError as exc:
        assert "connection reset" in str(exc)
```

Workflow engine tests — args-based `workflow`/`payload`, exact-match id
instead of fuzzy match:

```python
WORKFLOW_TOOL = {
    "id": "n8n_general_workflows",
    "name": "n8n General Workflows",
    "executor_type": "workflow_engine",
    "allowed_workflows": {"pda_command_router": "pda-command-router"},
}


def test_workflow_engine_refuses_on_private_workshop():
    out = asyncio.run(executor.run(
        WORKFLOW_TOOL, "run", "private", {"workflow": "pda_command_router", "payload": "hi"}
    ))
    assert "no n8n" in out.lower()


def test_workflow_engine_fails_closed_without_allowlist():
    tool = {"id": "n8n_general_workflows", "name": "n8n", "executor_type": "workflow_engine"}
    out = asyncio.run(executor.run(
        tool, "run", "open", {"workflow": "pda_command_router", "payload": "hi"}
    ))
    assert "fail-closed" in out


def test_workflow_engine_rejects_unknown_workflow_id():
    out = asyncio.run(executor.run(
        WORKFLOW_TOOL, "run", "open", {"workflow": "some_other_flow", "payload": "hi"}
    ))
    assert "no known workflow_id" in out.lower()


def test_workflow_engine_calls_n8n_webhook(monkeypatch):
    class FakeResponse:
        text = '{"status":"ok"}'
        def raise_for_status(self): pass

    seen = {}
    class FakeClient:
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        async def post(self, url, json):
            seen["url"] = url
            seen["json"] = json
            return FakeResponse()

    monkeypatch.setattr(executor.httpx, "AsyncClient", lambda **kw: FakeClient())
    out = asyncio.run(executor.run(
        WORKFLOW_TOOL, "run", "open",
        {"workflow": "pda_command_router", "payload": "do the thing"},
    ))
    assert "pda_command_router" in out
    assert "ok" in out
    assert seen["url"].endswith("/webhook/pda-command-router")
    assert seen["json"] == {"command": "do the thing", "message": "do the thing"}


def test_workflow_engine_raises_execution_error_on_call_failure(monkeypatch):
    class FakeClient:
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        async def post(self, url, json): raise RuntimeError("connection refused")

    monkeypatch.setattr(executor.httpx, "AsyncClient", lambda **kw: FakeClient())
    try:
        asyncio.run(executor.run(
            WORKFLOW_TOOL, "run", "open",
            {"workflow": "pda_command_router", "payload": "hi"},
        ))
        assert False, "expected ExecutionError"
    except executor.ExecutionError as exc:
        assert "connection refused" in str(exc)
```

Codex launcher — `_codex_task_title`/`_codex_task_slug`/`_codex_task_markdown`
unit tests are unchanged (those helpers still take plain text). Update only
the `run()`-level test:

```python
def test_cli_launcher_writes_task_file(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_CODEX_TASKS_DIR", tmp_path)
    out = asyncio.run(executor.run(
        {"executor_type": "cli_launcher"}, "create", "open",
        {"request": "fix the login bug"},
    ))
    assert "Created Codex task" in out
    files = list(tmp_path.glob("TASK-*.md"))
    assert len(files) == 1
    assert "Fix The Login Bug" in files[0].read_text()
    assert "fix-login-bug" in files[0].name
```

Informational/local_read — `message` still drives these, unchanged except
the trailing `args` positional now needs to be supplied (defaults to `{}`
via `run()`'s own `args = args or {}`, so passing nothing is fine):

```python
def test_informational_executor_summarizes_current_turn():
    tool = {"id": "status_summary", "name": "Status Summary", "executor_type": "informational"}
    out = asyncio.run(executor.run(tool, "give me a status summary", "open"))
    assert "Status Summary" in out
    assert "give me a status summary" in out
    assert "open" in out


def test_local_read_executor_reuses_registry_snapshot(monkeypatch):
    monkeypatch.setattr(registry, "format_tool_list", lambda ws: f"snapshot-for-{ws}")
    tool = {"id": "registry_inspector", "name": "Registry Inspector", "executor_type": "local_read"}
    out = asyncio.run(executor.run(tool, "what's in the registry?", "private"))
    assert "Registry Inspector" in out
    assert "snapshot-for-private" in out
```

- [ ] **Step 10: Run the executor test file**

Run: `cd cooper-core && .venv/bin/python -m pytest test_executor.py -v`
Expected: all tests pass. If a test still references a deleted regex
(`_DMZ_WRITE_RE`, `_NOTE_WRITE_RE`, `_MODEL_HINT_RE`, `_URL_RE`,
`_resolve_script`, `_resolve_python_script`, `_resolve_script_in_dir`),
that's a leftover from Step 9 — finish translating it per the patterns
above.

- [ ] **Step 11: Commit**

```bash
git add cooper-core/executor.py cooper-core/test_executor.py
git commit -m "feat(executor): consume validated args instead of parsing raw messages"
```

---

### Task 7: Decision — one tool-attached model call, no classifier

**Files:**
- Modify: `cooper-core/decision.py`
- Test: `cooper-core/test_decision.py` (new file)

**Interfaces:**
- Produces: `decision.ModelReply` (`content: str`, `tool_calls: List[ToolCall]`),
  `decision.ToolCall` (`id: str`, `name: str`, `arguments: dict`).
  `decision._openai_complete(...)` / `decision._ollama_complete(...)` gain
  an optional `tools: Optional[list] = None` kwarg — return `str` (as
  today) when omitted, `ModelReply` when supplied.
  `decision.route_turn(message, history, *, generate_answer, tools=None, tool_call_handler=None) -> Tuple[str, TurnDecision]`.
  `decision.route_turn_stream(message, history, *, system_prompt, base_url, api_key, model, backend="ollama", tools=None, tool_call_handler=None) -> Tuple[TurnDecision, AsyncIterator[str]]`.
- Deletes: `_CLASSIFIER_SYSTEM`, `_classify`, `_CLARIFY_SYSTEM`, `_clarify`,
  `_build_clarify_messages`, `_stream_chat`, `_stream_ollama_chat`,
  `_stream_openai_chat`, `VALID_DECISIONS`, `BACKENDS`, `_truncate`,
  `_MAX_HISTORY_CONTENT`.
- Consumed by: Task 8 (`main.py`'s `_generate`, `_chat_core_inner`,
  `_stream_sse`).

- [ ] **Step 1: Replace the module docstring and delete the classifier/clarify machinery**

Replace `cooper-core/decision.py`'s top docstring (lines 1-22):

```python
"""
COOPER decision layer — one tool-attached model call per turn (Step 15a).

The persona model receives the workshop's tool registry as OpenAI-format
`tools` on every turn. A text reply is the answer (including the model's
own clarifying questions — there is no separate clarify step). A `tool_call`
in the reply is the dispatch signal; the caller resolves and validates it
before anything runs.

Public API
----------
route_turn(message, history, *, generate_answer, tools=None, tool_call_handler=None)
  Blocking. Used by POST /chat and POST /v1/chat/completions stream=False.

route_turn_stream(message, history, *, system_prompt, base_url, api_key, model,
                   backend, tools=None, tool_call_handler=None)
  -> (TurnDecision, AsyncIterator[str])
  Streams the backend response; buffers silently if tool_call deltas appear,
  then emits the dispatch result as content chunks (spec §2 streaming specifics).

Decisions
---------
  answer   — the model replied with text (including its own clarifying questions)
  dispatch — the model emitted a tool_call; tool_call_handler ran it
"""
import json
from dataclasses import dataclass
from typing import AsyncIterator, Awaitable, Callable, Dict, List, Optional, Tuple

import httpx
```

Delete `_CLASSIFIER_SYSTEM` (old lines 30-52), `_CLARIFY_SYSTEM` (old lines
55-59), and keep `_DISPATCH_FALLBACK` (still used when `tool_call_handler`
is `None`). Delete `VALID_DECISIONS`, `BACKENDS`, `_ALLOWED_ROLES` — **wait,
keep `_ALLOWED_ROLES`** (still used by `_build_answer_messages`, which
stays). Delete `_MAX_HISTORY_CONTENT` and `_truncate` (only `_classify`
used them).

The constants block becomes:

```python
_DISPATCH_FALLBACK = "Acknowledged. No dispatch handler is wired for this request."

_ALLOWED_ROLES = frozenset({"user", "assistant"})
```

- [ ] **Step 2: Add `ToolCall` and `ModelReply` dataclasses**

After `TurnDecision`:

```python
@dataclass
class TurnDecision:
    decision: str  # "answer" | "dispatch"
    reason: str


@dataclass
class ToolCall:
    id: str
    name: str
    arguments: dict


@dataclass
class ModelReply:
    content: str
    tool_calls: List[ToolCall]
```

- [ ] **Step 3: Rewrite `route_turn`**

```python
def _dropped_calls_note(tool_calls: List[ToolCall]) -> str:
    if len(tool_calls) <= 1:
        return ""
    n = len(tool_calls) - 1
    return (
        f"\n\n(Note: {n} additional tool call{'s' if n != 1 else ''} were proposed "
        "and dropped — COOPER dispatches one action per turn.)"
    )


# ── route_turn — one tool-attached call, tool_call = dispatch ────────────────
async def route_turn(
    message: str,
    history: List[dict],
    *,
    generate_answer: Callable[..., Awaitable[ModelReply]],
    tools: Optional[List[dict]] = None,
    tool_call_handler: Optional[Callable[[str, dict, str], Awaitable[str]]] = None,
) -> Tuple[str, TurnDecision]:
    try:
        reply_obj = await generate_answer(message, history, tools=tools)
    except Exception as exc:
        return (
            f"[COOPER error: backend unavailable — {exc}]",
            TurnDecision(decision="answer", reason=f"backend error: {exc}"),
        )

    if reply_obj.tool_calls:
        primary = reply_obj.tool_calls[0]
        extra_note = _dropped_calls_note(reply_obj.tool_calls)
        td = TurnDecision(decision="dispatch", reason=f"tool_call: {primary.name}")
        if tool_call_handler is None:
            return _DISPATCH_FALLBACK + extra_note, td
        reply = await tool_call_handler(primary.name, primary.arguments, message)
        return reply + extra_note, td

    return reply_obj.content, TurnDecision(decision="answer", reason="no tool call emitted")
```

- [ ] **Step 4: Add the per-backend streaming event generators**

Delete `_stream_chat`, `_stream_ollama_chat`, `_stream_openai_chat` (old
lines 239-296) entirely. Replace with:

```python
# ── Streaming event generators — yield {"content": str} or
#    {"tool_call_delta": dict} items in arrival order ──────────────────────
async def _stream_ollama_events(
    base_url: str, model: str, messages: List[dict], tools: Optional[List[dict]]
) -> AsyncIterator[dict]:
    payload: dict = {"model": model, "messages": messages, "stream": True, "think": False}
    if tools:
        payload["tools"] = tools
    async with httpx.AsyncClient(timeout=120.0) as client:
        async with client.stream("POST", f"{base_url}/api/chat", json=payload) as resp:
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                if not line.strip():
                    continue
                try:
                    data = json.loads(line)
                except json.JSONDecodeError:
                    continue
                msg = data.get("message", {})
                for tc in msg.get("tool_calls") or []:
                    yield {"tool_call_delta": tc}
                content = msg.get("content", "")
                if content:
                    yield {"content": content}
                if data.get("done", False):
                    return


async def _stream_openai_events(
    base_url: str, api_key: str, model: str, messages: List[dict], tools: Optional[List[dict]]
) -> AsyncIterator[dict]:
    payload: dict = {"model": model, "messages": messages, "stream": True}
    if tools:
        payload["tools"] = tools
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    async with httpx.AsyncClient(timeout=120.0) as client:
        async with client.stream(
            "POST", f"{base_url}/chat/completions", json=payload, headers=headers
        ) as resp:
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                if not line.strip() or line == "data: [DONE]":
                    continue
                if not line.startswith("data: "):
                    continue
                try:
                    data = json.loads(line[6:])
                    delta = data["choices"][0]["delta"]
                except (json.JSONDecodeError, KeyError, IndexError):
                    continue
                for tc in delta.get("tool_calls") or []:
                    yield {"tool_call_delta": tc}
                content = delta.get("content")
                if content:
                    yield {"content": content}


def _stream_events(
    base_url: str, api_key: str, model: str, messages: List[dict],
    *, backend: str, tools: Optional[List[dict]],
) -> AsyncIterator[dict]:
    if backend == "openai":
        return _stream_openai_events(base_url, api_key, model, messages, tools)
    return _stream_ollama_events(base_url, model, messages, tools)
```

- [ ] **Step 5: Add the tool-call fragment accumulator**

```python
class _ToolCallAccumulator:
    """Accumulates OpenAI-style fragmented tool_call deltas (by `index`,
    arguments arrive as a partial JSON string across chunks) or Ollama-style
    single-chunk tool_calls (arguments arrive as a whole dict already)."""

    def __init__(self) -> None:
        self._by_index: Dict[int, dict] = {}
        self._order: List[int] = []

    def add(self, fragment: dict) -> None:
        index = fragment.get("index", len(self._order))
        if index not in self._by_index:
            self._by_index[index] = {"id": "", "name": "", "arguments": ""}
            self._order.append(index)
        entry = self._by_index[index]
        if fragment.get("id"):
            entry["id"] = fragment["id"]
        fn = fragment.get("function") or {}
        if fn.get("name"):
            entry["name"] = fn["name"]
        raw_args = fn.get("arguments")
        if isinstance(raw_args, str):
            entry["arguments"] += raw_args
        elif isinstance(raw_args, dict):
            entry["arguments"] = raw_args

    def finish(self) -> List[ToolCall]:
        calls = []
        for i, index in enumerate(self._order):
            entry = self._by_index[index]
            args = entry["arguments"]
            if isinstance(args, str):
                try:
                    args = json.loads(args) if args else {}
                except json.JSONDecodeError:
                    args = {}
            calls.append(ToolCall(id=entry["id"] or str(i), name=entry["name"], arguments=args))
        return calls
```

- [ ] **Step 6: Rewrite `route_turn_stream`**

Delete the old `route_turn_stream` (lines 122-149) and replace it (place it
after `route_turn`, before the deleted `_classify`'s old position):

```python
# ── route_turn_stream — real-time content streaming; silent buffer + single
#    dispatch chunk if a tool_call appears (spec §2 streaming specifics) ─────
async def route_turn_stream(
    message: str,
    history: List[dict],
    *,
    system_prompt: str,
    base_url: str,
    api_key: str,
    model: str,
    backend: str = "ollama",
    tools: Optional[List[dict]] = None,
    tool_call_handler: Optional[Callable[[str, dict, str], Awaitable[str]]] = None,
) -> Tuple[TurnDecision, AsyncIterator[str]]:
    msgs = _build_answer_messages(message, history, system_prompt)
    events = _stream_events(base_url, api_key, model, msgs, backend=backend, tools=tools)

    accumulator = _ToolCallAccumulator()
    first_content: Optional[str] = None

    async for ev in events:
        if "tool_call_delta" in ev:
            accumulator.add(ev["tool_call_delta"])
            # A tool_call turn: drain the rest of the stream silently — any
            # stray content after this point is buffered, never forwarded
            # (a turn is either streamed text OR a buffered dispatch, never
            # interleaved).
            async for ev2 in events:
                if "tool_call_delta" in ev2:
                    accumulator.add(ev2["tool_call_delta"])
            tool_calls = accumulator.finish()
            primary = tool_calls[0]
            extra_note = _dropped_calls_note(tool_calls)
            td = TurnDecision(decision="dispatch", reason=f"tool_call: {primary.name}")
            if tool_call_handler is None:
                return td, _single_chunk(_DISPATCH_FALLBACK + extra_note)
            reply = await tool_call_handler(primary.name, primary.arguments, message)
            return td, _single_chunk(reply + extra_note)
        first_content = ev["content"]
        break

    td = TurnDecision(decision="answer", reason="no tool call emitted")
    if first_content is None:
        return td, _single_chunk("")
    return td, _forward_remaining(first_content, events)


async def _forward_remaining(first_content: str, events: AsyncIterator[dict]) -> AsyncIterator[str]:
    yield first_content
    async for ev in events:
        if "content" in ev and ev["content"]:
            yield ev["content"]
        # a stray tool_call_delta arriving after content has already started
        # streaming is ignored — see the "never interleaved" note above.
```

- [ ] **Step 7: Extend `_ollama_complete` / `_openai_complete` to accept `tools`**

Replace both blocking completion functions (old lines 300-341):

```python
# ── Blocking completions ───────────────────────────────────────────────────
# Return a bare `str` when called without `tools` (the pre-existing contract
# every other caller — archivist.py, proposer.py, review.py, executor.py's
# _run_local_llm/_run_llm_api — still relies on). Return a `ModelReply` when
# `tools` is supplied (only the persona-turn call path does this).
async def _ollama_complete(
    base_url: str,
    model: str,
    messages: List[dict],
    *,
    options: Optional[dict] = None,
    fmt: Optional[dict] = None,
    tools: Optional[List[dict]] = None,
):
    payload: dict = {"model": model, "messages": messages, "stream": False, "think": False}
    if options:
        payload["options"] = options
    if fmt:
        payload["format"] = fmt
    if tools:
        payload["tools"] = tools
    async with httpx.AsyncClient(timeout=120.0) as client:
        resp = await client.post(f"{base_url}/api/chat", json=payload)
        resp.raise_for_status()
        data = resp.json()
    message_obj = data["message"]
    if tools:
        return ModelReply(
            content=message_obj.get("content") or "",
            tool_calls=_parse_ollama_tool_calls(message_obj.get("tool_calls") or []),
        )
    return message_obj["content"]


async def _openai_complete(
    base_url: str,
    api_key: str,
    model: str,
    messages: List[dict],
    *,
    temperature: Optional[float] = None,
    response_format: Optional[dict] = None,
    tools: Optional[List[dict]] = None,
):
    payload: dict = {"model": model, "messages": messages}
    if temperature is not None:
        payload["temperature"] = temperature
    if response_format:
        payload["response_format"] = response_format
    if tools:
        payload["tools"] = tools
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(
            f"{base_url}/chat/completions", json=payload, headers=headers
        )
        resp.raise_for_status()
        data = resp.json()
    message_obj = data["choices"][0]["message"]
    if tools:
        return ModelReply(
            content=message_obj.get("content") or "",
            tool_calls=_parse_openai_tool_calls(message_obj.get("tool_calls") or []),
        )
    return message_obj["content"]


def _parse_ollama_tool_calls(raw: List[dict]) -> List[ToolCall]:
    calls = []
    for i, tc in enumerate(raw):
        fn = tc.get("function", {})
        arguments = fn.get("arguments") or {}
        if isinstance(arguments, str):
            try:
                arguments = json.loads(arguments)
            except json.JSONDecodeError:
                arguments = {}
        calls.append(ToolCall(id=str(i), name=fn.get("name", ""), arguments=arguments))
    return calls


def _parse_openai_tool_calls(raw: List[dict]) -> List[ToolCall]:
    calls = []
    for tc in raw:
        fn = tc.get("function", {})
        try:
            arguments = json.loads(fn.get("arguments") or "{}")
        except json.JSONDecodeError:
            arguments = {}
        calls.append(ToolCall(id=tc.get("id", ""), name=fn.get("name", ""), arguments=arguments))
    return calls
```

- [ ] **Step 8: Delete `_clarify` and `_build_clarify_messages`; keep the rest of the message builders + `_single_chunk`**

Delete the `_clarify` function (old lines 222-235) and
`_build_clarify_messages` (old lines 345-351). `_build_answer_messages` and
`_single_chunk` stay exactly as they are today (unchanged).

- [ ] **Step 9: Sanity-check the file for leftover references**

Run: `cd cooper-core && grep -n "_classify\|_clarify\|_CLASSIFIER_SYSTEM\|_CLARIFY_SYSTEM\|_stream_chat\b\|_stream_ollama_chat\|_stream_openai_chat\|VALID_DECISIONS\|BACKENDS\b" decision.py`
Expected: no output (everything referencing those names is gone).

- [ ] **Step 10: Write `cooper-core/test_decision.py` (new file)**

```python
import asyncio
import json

import decision


def _run(coro):
    return asyncio.run(coro)


async def _collect(aiter):
    out = []
    async for chunk in aiter:
        out.append(chunk)
    return out


# ── route_turn (blocking) ────────────────────────────────────────────────────
def test_route_turn_dispatches_on_tool_call():
    async def gen(message, history, tools=None):
        return decision.ModelReply(
            content="", tool_calls=[decision.ToolCall(id="1", name="status_summary", arguments={})]
        )

    async def handler(tool_id, args, raw):
        return f"ran {tool_id}"

    reply, td = _run(decision.route_turn(
        "status", [], generate_answer=gen, tools=[], tool_call_handler=handler,
    ))
    assert reply == "ran status_summary"
    assert td.decision == "dispatch"
    assert td.reason == "tool_call: status_summary"


def test_route_turn_answers_when_no_tool_call():
    async def gen(message, history, tools=None):
        return decision.ModelReply(content="hi there", tool_calls=[])

    reply, td = _run(decision.route_turn("hello", [], generate_answer=gen))
    assert reply == "hi there"
    assert td.decision == "answer"


def test_route_turn_falls_back_without_a_handler():
    async def gen(message, history, tools=None):
        return decision.ModelReply(
            content="", tool_calls=[decision.ToolCall(id="1", name="a", arguments={})]
        )

    reply, td = _run(decision.route_turn("do stuff", [], generate_answer=gen))
    assert reply == decision._DISPATCH_FALLBACK
    assert td.decision == "dispatch"


def test_route_turn_multiple_tool_calls_drops_extra_with_note():
    async def gen(message, history, tools=None):
        return decision.ModelReply(content="", tool_calls=[
            decision.ToolCall(id="1", name="a", arguments={}),
            decision.ToolCall(id="2", name="b", arguments={}),
        ])

    async def handler(tool_id, args, raw):
        return "ran a"

    reply, td = _run(decision.route_turn(
        "do stuff", [], generate_answer=gen, tool_call_handler=handler,
    ))
    assert reply.startswith("ran a")
    assert "1 additional tool call" in reply
    assert "dropped" in reply


def test_route_turn_backend_error_is_caught():
    async def gen(message, history, tools=None):
        raise RuntimeError("boom")

    reply, td = _run(decision.route_turn("hi", [], generate_answer=gen))
    assert "backend unavailable" in reply
    assert td.decision == "answer"


# ── _openai_complete / _ollama_complete ──────────────────────────────────────
class _FakeHTTPResp:
    def __init__(self, data):
        self._data = data
    def raise_for_status(self):
        pass
    def json(self):
        return self._data


class _FakeHTTPClient:
    def __init__(self, data):
        self._data = data
    async def __aenter__(self):
        return self
    async def __aexit__(self, *a):
        return False
    async def post(self, url, **kw):
        return _FakeHTTPResp(self._data)


def test_openai_complete_returns_plain_string_without_tools(monkeypatch):
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeHTTPClient(
        {"choices": [{"message": {"content": "plain answer"}}]}
    ))
    result = _run(decision._openai_complete("http://x", "k", "m", [{"role": "user", "content": "hi"}]))
    assert result == "plain answer"


def test_openai_complete_returns_model_reply_with_tools(monkeypatch):
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeHTTPClient(
        {"choices": [{"message": {
            "content": "",
            "tool_calls": [{"id": "1", "function": {"name": "status_summary", "arguments": "{}"}}],
        }}]}
    ))
    result = _run(decision._openai_complete(
        "http://x", "k", "m", [{"role": "user", "content": "hi"}],
        tools=[{"type": "function", "function": {"name": "status_summary"}}],
    ))
    assert isinstance(result, decision.ModelReply)
    assert result.tool_calls[0].name == "status_summary"
    assert result.tool_calls[0].arguments == {}


def test_ollama_complete_returns_plain_string_without_tools(monkeypatch):
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeHTTPClient(
        {"message": {"content": "plain"}}
    ))
    result = _run(decision._ollama_complete("http://x", "m", [{"role": "user", "content": "hi"}]))
    assert result == "plain"


def test_ollama_complete_returns_model_reply_with_tools(monkeypatch):
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeHTTPClient(
        {"message": {"content": "", "tool_calls": [
            {"function": {"name": "status_summary", "arguments": {}}}
        ]}}
    ))
    result = _run(decision._ollama_complete(
        "http://x", "m", [{"role": "user", "content": "hi"}],
        tools=[{"type": "function", "function": {"name": "status_summary"}}],
    ))
    assert isinstance(result, decision.ModelReply)
    assert result.tool_calls[0].name == "status_summary"


# ── route_turn_stream — fixture-driven, no live LLM (spec §6.6) ─────────────
class _FakeStreamResp:
    def __init__(self, lines):
        self._lines = lines
    def raise_for_status(self):
        pass
    async def aiter_lines(self):
        for line in self._lines:
            yield line


class _FakeStreamCtx:
    def __init__(self, resp):
        self._resp = resp
    async def __aenter__(self):
        return self._resp
    async def __aexit__(self, *a):
        return False


class _FakeStreamClient:
    def __init__(self, lines):
        self._lines = lines
    async def __aenter__(self):
        return self
    async def __aexit__(self, *a):
        return False
    def stream(self, method, url, **kw):
        return _FakeStreamCtx(_FakeStreamResp(self._lines))


def test_ollama_stream_single_chunk_tool_call_dispatches(monkeypatch):
    lines = [json.dumps({
        "message": {
            "role": "assistant", "content": "",
            "tool_calls": [{"function": {"name": "status_summary", "arguments": {}}}],
        },
        "done": True,
    })]
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeStreamClient(lines))

    captured = {}
    async def handler(tool_id, args, raw):
        captured["tool_id"] = tool_id
        captured["args"] = args
        return "EXECUTED"

    td, content_iter = _run(decision.route_turn_stream(
        "give me a status summary", [], system_prompt="sys",
        base_url="http://x", api_key="", model="m", backend="ollama",
        tools=[{"type": "function", "function": {"name": "status_summary", "parameters": {}}}],
        tool_call_handler=handler,
    ))
    chunks = _run(_collect(content_iter))
    assert td.decision == "dispatch"
    assert td.reason == "tool_call: status_summary"
    assert captured["tool_id"] == "status_summary"
    assert chunks == ["EXECUTED"]


def test_openai_stream_fragmented_tool_call_accumulates(monkeypatch):
    deltas = [
        {"choices": [{"delta": {"tool_calls": [
            {"index": 0, "id": "call_1", "function": {"name": "status_summary", "arguments": ""}}
        ]}}]},
        {"choices": [{"delta": {"tool_calls": [
            {"index": 0, "function": {"arguments": '{"a"'}}
        ]}}]},
        {"choices": [{"delta": {"tool_calls": [
            {"index": 0, "function": {"arguments": ': 1}'}}
        ]}}]},
    ]
    lines = [f"data: {json.dumps(d)}" for d in deltas] + ["data: [DONE]"]
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeStreamClient(lines))

    captured = {}
    async def handler(tool_id, args, raw):
        captured["tool_id"] = tool_id
        captured["args"] = args
        return "EXECUTED"

    td, content_iter = _run(decision.route_turn_stream(
        "status please", [], system_prompt="sys",
        base_url="http://x", api_key="k", model="m", backend="openai",
        tools=[{"type": "function", "function": {"name": "status_summary", "parameters": {}}}],
        tool_call_handler=handler,
    ))
    chunks = _run(_collect(content_iter))
    assert td.decision == "dispatch"
    assert captured["tool_id"] == "status_summary"
    assert captured["args"] == {"a": 1}
    assert chunks == ["EXECUTED"]


def test_ollama_stream_plain_content_forwards_incrementally(monkeypatch):
    lines = [
        json.dumps({"message": {"content": "Hel"}, "done": False}),
        json.dumps({"message": {"content": "lo"}, "done": False}),
        json.dumps({"message": {"content": ""}, "done": True}),
    ]
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeStreamClient(lines))

    td, content_iter = _run(decision.route_turn_stream(
        "hi", [], system_prompt="sys",
        base_url="http://x", api_key="", model="m", backend="ollama",
        tools=[], tool_call_handler=None,
    ))
    chunks = _run(_collect(content_iter))
    assert td.decision == "answer"
    assert chunks == ["Hel", "lo"]


def test_stream_dispatch_falls_back_without_a_handler(monkeypatch):
    lines = [json.dumps({
        "message": {"content": "", "tool_calls": [{"function": {"name": "x", "arguments": {}}}]},
        "done": True,
    })]
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeStreamClient(lines))

    td, content_iter = _run(decision.route_turn_stream(
        "do it", [], system_prompt="sys",
        base_url="http://x", api_key="", model="m", backend="ollama",
        tools=[], tool_call_handler=None,
    ))
    chunks = _run(_collect(content_iter))
    assert td.decision == "dispatch"
    assert chunks == [decision._DISPATCH_FALLBACK]
```

- [ ] **Step 11: Run the new and existing decision-related tests**

Run: `cd cooper-core && .venv/bin/python -m pytest test_decision.py -v`
Expected: all tests pass.

- [ ] **Step 12: Commit**

```bash
git add cooper-core/decision.py cooper-core/test_decision.py
git commit -m "feat(decision): one tool-attached model call per turn, delete classifier/clarify"
```

---

### Task 8: main.py — wire tools, rename dispatch handler, thread args

**Files:**
- Modify: `cooper-core/main.py`
- Test: `cooper-core/test_main_dispatch.py`, `cooper-core/test_main_skills.py`

**Interfaces:**
- Produces: `main._handle_tool_call(tool_id, args, raw_message, session_id="local") -> str`
  (renamed/evolved from `_handle_dispatch`); `main._execute(tool, message, session_id="local", args=None) -> str`
  (gains `args`); `main._generate(message, history, tools=None)` (gains `tools`,
  now returns whatever `decision._openai_complete`/`_ollama_complete` return
  — `ModelReply` in production since `tools` is always non-empty there).
- Consumes: Task 1's `registry.render_workshop_tools`/`registry.validate_args`,
  Task 4's `approval.request(..., args=...)`/`ApprovalTicket.args`, Task 5's
  `skills.preview_import(skill_name, tap_url)`/`skills.preview_promote(skill_name)`/
  `skills.discard_staged(skill_name)`, Task 6's `executor.run(tool, message, workshop, args)`,
  Task 7's `decision.route_turn(..., tools=, tool_call_handler=)` /
  `decision.route_turn_stream(..., tools=, tool_call_handler=)`.

- [ ] **Step 1: Rewrite `_handle_dispatch` as `_handle_tool_call`**

In `cooper-core/main.py`, replace the entire `_handle_dispatch` function
(lines 165-233):

```python
_ARGS_PREVIEW_CHAR_THRESHOLD = 60


def _render_args_preview(args: dict) -> str:
    """Approval-halt preview line: short values verbatim, long ones as a
    char count (spec §4 main.py — 'note: ...md, content: 214 chars')."""
    if not args:
        return ""
    parts = []
    for key, value in args.items():
        text = str(value)
        if len(text) > _ARGS_PREVIEW_CHAR_THRESHOLD:
            parts.append(f"{key}: {len(text)} chars")
        else:
            parts.append(f"{key}: {value!r}")
    return "\n\nArgs — " + ", ".join(parts)


async def _handle_tool_call(
    tool_id: str, args: dict, raw_message: str, session_id: str = "local"
) -> str:
    """
    The model's tool_call IS the dispatch (spec §2 step 4-5). Resolve
    tool_id to a registry entry, validate args, gate via approval, execute
    if the gate passes. L0/L1 auto-run immediately. L2+ halts for approval.
    Every failure here is fail-closed and spends no approval (spec §5).
    """
    try:
        workshop.check_backend(BACKEND, WORKSHOP)
    except workshop.WorkshopViolation as exc:
        return f"Workshop violation: {exc}"

    tool = registry.get_tool(WORKSHOP, tool_id)
    if tool is None:
        return f"COOPER proposed a call to unregistered tool '{tool_id}'. Nothing ran."

    try:
        workshop.check_tool(tool, WORKSHOP)
    except workshop.WorkshopViolation as exc:
        return f"Workshop violation: {exc}"

    violations = registry.validate_args(tool, args)
    if violations:
        return (
            f"COOPER proposed an invalid call to {tool.get('name', tool_id)}: "
            f"{'; '.join(violations)}. Nothing ran."
        )

    skill_note = ""
    skill = await asyncio.to_thread(
        archivist.get_skill, _ARCHIVIST_CONN, tool.get("name", tool.get("id", "unknown"))
    )
    if skill is not None and skill.trust_score > 0.5:
        skill_note = (
            f" (matches a proven skill — {skill.successful_run_count} successful "
            f"run{'s' if skill.successful_run_count != 1 else ''}, "
            f"{skill.trust_score:.0%} trust)"
        )

    if approval.needs_approval(tool):
        preview = ""
        if tool.get("executor_type") == "skill_import":
            try:
                text = await asyncio.to_thread(
                    skills.preview_import, args.get("skill_name", ""), args.get("tap_url", "")
                )
                preview = f"\n\nSKILL.md under review:\n---\n{text}\n---"
            except skills.SkillError as exc:
                return f"Skill import rejected before approval: {exc}"
            except Exception as exc:
                return f"Skill import rejected before approval (unexpected error): {exc}"
        elif tool.get("executor_type") == "skill_promote":
            try:
                text = await asyncio.to_thread(skills.preview_promote, args.get("skill_name", ""))
                preview = f"\n\nDraft SKILL.md under review:\n---\n{text}\n---"
            except skills.SkillError as exc:
                return f"Skill promotion rejected before approval: {exc}"
            except Exception as exc:
                return f"Skill promotion rejected before approval (unexpected error): {exc}"
        approval.request(WORKSHOP, tool, raw_message, session_id, args=args)
        return (
            f"Halt — {tool.get('name', tool.get('id'))} "
            f"[{tool.get('drawer', 'Uncategorized')}, permission level {tool.get('permission_level', '?')}] "
            f"requires approval before it can proceed{skill_note}. Reply 'approve' or 'deny'."
            f"{_render_args_preview(args)}"
            f"{preview}"
        )

    # L0/L1: execute immediately
    if skill_note:
        print(f"  [archivist] {tool.get('name')}{skill_note}")
    return await _execute(tool, raw_message, session_id, args)
```

- [ ] **Step 2: Thread `args` through `_execute` and `_resolve_approval`**

Replace `_execute` (old lines 277-301):

```python
async def _execute(
    tool: dict, message: str, session_id: str = "local", args: Optional[dict] = None
) -> str:
    """
    Run an approved/auto-run tool through the Workbench (Worker), then have
    the Reviewer check the result (Step 7) before it reaches the user.
    Memory + skill drafting happen in the background (_post_dispatch).
    """
    args = args or {}
    try:
        raw_output = await executor.run(tool, message, WORKSHOP, args)
    except executor.ExecutionError as exc:
        return f"Workbench error: {exc}"

    verdict = await review.review(
        tool, message, raw_output,
        base_url=BACKEND_URL,
        api_key=BACKEND_KEY,
        model=CLASSIFIER_MODEL,
        backend=BACKEND,
    )

    task = asyncio.create_task(
        _post_dispatch(tool, message, raw_output, verdict, session_id))
    _BG_TASKS.add(task)
    task.add_done_callback(_BG_TASKS.discard)

    return review.govern(raw_output, verdict)
```

Replace `_resolve_approval` (old lines 304-325):

```python
async def _resolve_approval(message: str, session_id: str = "local") -> str:
    """
    Consume the pending ticket and execute on approve, or cancel on deny.
    Called only when approval.has_pending() and approval.is_response() are both true.
    """
    if approval.is_denied(message):
        ticket = approval.consume(WORKSHOP, session_id)
        if ticket is None:
            return "No pending action to cancel."
        if ticket.tool.get("executor_type") == "skill_import":
            try:
                skills.discard_staged(ticket.args.get("skill_name", ""))
            except Exception as exc:
                print(f"  [!!] discard_staged failed (non-fatal): {exc}")
        name = ticket.tool.get("name", ticket.tool.get("id"))
        return f"Cancelled. {name} will not run."

    ticket = approval.consume(WORKSHOP, session_id)
    if ticket is None:
        return "No pending action to approve. Nothing queued."

    return await _execute(ticket.tool, ticket.message, session_id, ticket.args)
```

- [ ] **Step 3: Wire `tools=` and `tool_call_handler=` into `_chat_core_inner`**

Replace the `route_turn(...)` call at the end of `_chat_core_inner` (old
lines 346-352):

```python
async def _chat_core_inner(message: str, history: List[dict], session_id: str = "local") -> tuple:
    if registry.is_registry_query(message):
        return registry.format_tool_list(WORKSHOP), TurnDecision(
            decision="answer", reason="registry query answered directly by Quartermaster")
    if skills.is_skill_query(message):
        return skills.format_skill_list(WORKSHOP), TurnDecision(
            decision="answer", reason="skill catalog answered directly")
    if approval.has_pending(WORKSHOP, session_id) and approval.is_response(message):
        return await _resolve_approval(message, session_id), TurnDecision(
            decision="answer", reason="approval gate resolved")
    return await route_turn(
        message, history,
        generate_answer=_generate,
        tools=registry.render_workshop_tools(WORKSHOP),
        tool_call_handler=lambda tid, a, raw: _handle_tool_call(tid, a, raw, session_id),
    )
```

- [ ] **Step 4: Wire `tools=` and `tool_call_handler=` into `_stream_sse`**

In `_stream_sse`, replace the `route_turn_stream(...)` call (old lines
624-634):

```python
            td, content_iter = await route_turn_stream(
                message,
                history,
                system_prompt=system_prompt,
                base_url=BACKEND_URL,
                api_key=BACKEND_KEY,
                model=COOPER_MODEL,
                backend=BACKEND,
                tools=registry.render_workshop_tools(WORKSHOP),
                tool_call_handler=lambda tid, a, raw: _handle_tool_call(tid, a, raw, session_id),
            )
```

(`classifier_model=CLASSIFIER_MODEL` is dropped from this call — the
streaming decision layer no longer classifies.)

- [ ] **Step 5: Add `tools` to `_generate`**

Replace `_generate` (old lines 676-704):

```python
async def _generate(message: str, history: List[dict], tools: Optional[List[dict]] = None):
    try:
        await asyncio.to_thread(archivist.index_brain, _ARCHIVIST_CONN)
        recall_context = archivist.format_recall_context(
            await asyncio.to_thread(archivist.recall, _ARCHIVIST_CONN, message)
        )
    except Exception as exc:
        print(f"  [!!] archivist.recall failed (non-fatal): {exc}")
        recall_context = ""
    skill_ctx = ""
    try:
        matched = await _select_skill(message)
        if matched is not None:
            skill_ctx = skills.format_skill_context(matched)
            await asyncio.to_thread(skills.record_activation, _ARCHIVIST_CONN, matched.id)
    except Exception as exc:
        print(f"  [!!] skill context injection failed (non-fatal): {exc}")
        skill_ctx = ""
    msgs = _build_messages(history, message)
    # Same injection order as the streaming path: SYSTEM, recall, skill.
    if skill_ctx:
        msgs.insert(1, {"role": "system", "content": skill_ctx})
    if recall_context:
        msgs.insert(1, {"role": "system", "content": recall_context})
    if BACKEND == "openai":
        from decision import _openai_complete
        return await _openai_complete(BACKEND_URL, BACKEND_KEY, COOPER_MODEL, msgs, tools=tools)
    from decision import _ollama_complete
    return await _ollama_complete(BACKEND_URL, COOPER_MODEL, msgs, tools=tools)
```

- [ ] **Step 6: Update `test_main_dispatch.py`**

`main._execute` now takes an optional 4th `args` positional; the existing
call in `test_execute_returns_before_memory_and_draft_run` passes 3
positional args (`_TOOL, "run test exec", "sess-bg"`) which still works
unchanged since `args` defaults to `None`/`{}`. But `main.executor.run`'s
fake in that test has signature `async def fake_run(tool, message,
workshop)` — `_execute` now calls `executor.run(tool, message, WORKSHOP,
args)` with 4 positional args, so the fake needs a 4th parameter. Update:

```python
        async def fake_run(tool, message, workshop, args=None):
            return "RAW-OUTPUT"
```

That's the only change needed for the existing test. Also add
`import approval` to this file's imports, and four new tests covering spec
§6 items 3 and 5 at the main.py level (ticket args round trip + fail-closed
refusals) — append:

```python
import approval  # noqa: E402


def test_handle_tool_call_refuses_unknown_tool_id():
    reply = asyncio.run(main._handle_tool_call("nonexistent_tool", {}, "do it", "s1"))
    assert "unregistered tool" in reply.lower()


def test_handle_tool_call_refuses_invalid_args(monkeypatch):
    monkeypatch.setattr(main.registry, "get_tool", lambda ws, tid: {
        "id": "status_summary", "name": "Status Summary", "permission_level": 0,
        "workshop": "Open Workshop", "executor_type": "informational",
    })
    monkeypatch.setattr(main.registry, "validate_args", lambda tool, args: ["missing required argument 'x'"])
    reply = asyncio.run(main._handle_tool_call("status_summary", {}, "do it", "s1"))
    assert "invalid call" in reply.lower()
    assert "missing required argument" in reply


def test_handle_tool_call_opens_ticket_with_rendered_args_preview(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main.registry, "get_tool", lambda ws, tid: {
        "id": "obsidian_note_writer", "name": "Obsidian Note Writer",
        "workshop": "Open Workshop", "permission_level": 2,
        "approval_required": True, "executor_type": "note_editor",
        "drawer": "Knowledge Shelf",
    })
    monkeypatch.setattr(main.registry, "validate_args", lambda tool, args: [])
    approval._pending.clear()
    reply = asyncio.run(main._handle_tool_call(
        "obsidian_note_writer",
        {"filename": "x.md", "content": "y" * 100},
        "write it", "s2",
    ))
    assert "Halt —" in reply
    assert "filename: 'x.md'" in reply
    assert "content: 100 chars" in reply
    ticket = approval.peek(main.WORKSHOP, "s2")
    assert ticket.args == {"filename": "x.md", "content": "y" * 100}


def test_approve_executes_with_ticket_stored_args(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", set())
    tool = {"id": "obsidian_note_writer", "name": "Obsidian Note Writer",
            "workshop": "Open Workshop", "executor_type": "note_editor"}
    approval._pending.clear()
    approval.request(main.WORKSHOP, tool, "write it", "s3",
                      args={"filename": "x.md", "content": "hi"})

    seen = {}

    async def fake_run(t, message, workshop, args=None):
        seen["args"] = args
        return "wrote it"

    monkeypatch.setattr(main.executor, "run", fake_run)

    verdict = main.review.ReviewVerdict(verdict="pass", reason="ok")

    async def fake_review(*a, **k):
        return verdict

    monkeypatch.setattr(main.review, "review", fake_review)

    async def fake_remember(*a, **k):
        return None

    monkeypatch.setattr(main.archivist, "remember", fake_remember)

    async def fake_draft(*a, **k):
        return None

    monkeypatch.setattr(main.proposer, "draft_skill", fake_draft)

    reply = asyncio.run(main._resolve_approval("approve", "s3"))
    assert seen["args"] == {"filename": "x.md", "content": "hi"}
    assert "wrote it" in reply
```

- [ ] **Step 7: Update `test_main_skills.py`**

`test_rejected_preview_never_opens_an_approval_ticket` currently drives
`main._handle_dispatch("import skill tap-skill from https://x/y")` and
monkeypatches `main.registry.select_tool_llm` — both are gone. Rewrite to
drive `main._handle_tool_call` directly with structured args, and drop the
`select_tool_llm` monkeypatch (resolution is now `registry.get_tool`, real
and unmocked — the test tool needs to actually exist in the loaded
registry, or `get_tool` monkeypatched instead):

```python
def test_rejected_preview_never_opens_an_approval_ticket(monkeypatch):
    # Core security property: if skills.preview_import() raises before
    # approval.request() is ever called, _handle_tool_call() must return the
    # rejection immediately and MUST NOT leave a dangling approval ticket behind.
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main, "_ALLOW_ANON", True)

    monkeypatch.setattr(main.registry, "get_tool", lambda ws, tid: dict(_IMPORT_SKILL_TOOL))
    monkeypatch.setattr(main.registry, "validate_args", lambda tool, args: [])

    def _boom(skill_name, tap_url):
        raise skills.SkillError("bad tap")

    monkeypatch.setattr(main.skills, "preview_import", _boom)

    approval_calls = []
    monkeypatch.setattr(
        main.approval, "request",
        lambda *args, **kwargs: approval_calls.append((args, kwargs)),
    )

    reply = asyncio.run(
        main._handle_tool_call(
            "import_skill",
            {"skill_name": "tap-skill", "tap_url": "https://x/y"},
            "import skill tap-skill from https://x/y",
        )
    )

    assert "rejected" in reply.lower()
    assert "bad tap" in reply
    assert approval_calls == []
```

`test_execute_reply_unchanged_when_proposer_raises` calls
`main.executor.run` via a fake `async def _run(*args, **kwargs): return
"..."` — already `*args, **kwargs`, unaffected by the new 4th `args`
parameter. No change needed there.

`test_deny_import_skill_cleans_staging` seeds a ticket via
`approval.request("open", _IMPORT_SKILL_TOOL, msg, "anon")` — no `args=`
kwarg, so `ticket.args` defaults to `{}`. Since `_resolve_approval` now
calls `skills.discard_staged(ticket.args.get("skill_name", ""))`, this test
must seed the ticket with real args so `discard_staged` receives the real
skill name:

```python
def test_deny_import_skill_cleans_staging(tmp_path, monkeypatch):
    """Denying a pending import_skill approval must remove the staged
    Skills/_incoming/<name> dir, not orphan it."""
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main, "_ALLOW_ANON", True)
    staged = tmp_path / "Skills" / "_incoming" / "tap-skill"
    staged.mkdir(parents=True)
    (staged / "SKILL.md").write_text(
        "---\nname: tap-skill\ndescription: d.\n---\n\nB.\n", encoding="utf-8"
    )
    monkeypatch.setattr(skills, "_REPO_ROOT", tmp_path)

    import approval
    approval.request(
        "open", _IMPORT_SKILL_TOOL, "import skill tap-skill from https://example.com/tap",
        "anon", args={"skill_name": "tap-skill", "tap_url": "https://example.com/tap"},
    )
    with TestClient(main.app) as client:
        resp = client.post("/chat", json={"message": "deny"})
    assert resp.status_code == 200
    assert "Cancelled" in resp.json()["reply"]
    assert not staged.exists()
```

`test_generate_context_order_matches_streaming` calls `main._generate("hello",
[])` and monkeypatches `decision._openai_complete` with a fake taking
`(base_url, api_key, model, messages, **kw)` — already `**kw`-tolerant, so
the new `tools=` kwarg passed through by `_generate` doesn't break it. No
change needed.

The other tests in this file (`test_chat_answers_skill_query_without_llm`,
`test_get_skills_endpoint`,
`test_get_skills_endpoint_isolates_per_entry_status_failure`) don't touch
dispatch — unaffected.

- [ ] **Step 8: Run the full main.py-related test files**

Run:
```bash
cd cooper-core
.venv/bin/python -m pytest test_main_dispatch.py test_main_skills.py test_main_auth.py test_main_open_routing.py -v
```
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add cooper-core/main.py cooper-core/test_main_dispatch.py cooper-core/test_main_skills.py
git commit -m "feat(main): wire tools onto every turn, dispatch via tool_call not classifier"
```

---

### Task 9: Full suite green + stray-reference sweep

**Files:** none new — verification only, with point-fixes wherever the
sweep finds something.

- [ ] **Step 1: Run the full cooper-core suite**

Run: `cd cooper-core && .venv/bin/python -m pytest -v`
Expected: 0 failures. If any test fails, read its failure — it's almost
certainly a leftover from Tasks 1-8 that referenced deleted symbols
(`select_tool`, `select_tool_llm`, `_classify`, `_clarify`,
`parse_import_request`, `parse_promote_request`, an old free-text executor
call) or an unrelated pre-existing flake. Fix the leftover in the same file
the plan already touched; do not reintroduce any deleted code path.

- [ ] **Step 2: Grep for anything the plan's deletions might have missed**

Run:
```bash
cd cooper-core
grep -rn "select_tool_llm\|_classify(\|_clarify(\|parse_import_request\|parse_promote_request\|_NOTE_WRITE_RE\|_DMZ_WRITE_RE\|_MODEL_HINT_RE\b\|dispatch_handler=" --include="*.py" .
```
Expected: no output outside of this plan file / the spec (those are docs,
not code). If anything shows up in a `.py` file, that's a straggler — fix
it and re-run Step 1.

- [ ] **Step 3: Run the v1 Pipe unit tests (unaffected, but confirm)**

Run: `cd /home/zb6/Documents/Projects/01_AI_Ecosystem && cooper-core/.venv/bin/python -m pytest "Open WebUI/Test_PDA_ChatBridge_Pipe.py" -v`
Expected: unchanged pass/fail state from before this plan (this legacy
bridge test suite has no dependency on anything Step 15a touches).

- [ ] **Step 4: Commit any stray fixes**

Only if Step 1/2 required point-fixes beyond what Tasks 1-8 already
committed:
```bash
git add -A
git commit -m "fix: clean up stray references left by the Step 15a dispatch rewrite"
```

---

### Task 10: Live DoD verification (spec §7)

**Files:** none — this is a verification task against the running Docker
stacks. Report honestly per CLAUDE.md's operating mindset: not-done is
flagged as not-done, never claimed; if a sub-check can't be run in this
environment (no browser tool session, no live OpenAI-format cloud key
reachable, etc.), say so explicitly rather than skipping silently.

- [ ] **Step 1: Rebuild and bring up the Private stack**

```bash
cd /home/zb6/Documents/Projects/01_AI_Ecosystem
docker compose -f PDA-Runtime/docker-compose.private.yml up -d --build cooper-core
```
Wait for health: `curl -s --max-time 3 http://localhost:8000/health` until
it returns `{"status":"ok","workshop":"private",...}` (Gotchas 2026-07-08:
`up -d` alone does not rebuild).

- [ ] **Step 2: Full dispatch → approve → execute round trip on Private**

```bash
KEY=$(grep '^COOPER_API_KEYS=' PDA-Runtime/.env | cut -d= -f2)
curl -s -X POST http://localhost:8000/chat \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"message":"give me a status summary"}'
```
Expected: `"decision":"dispatch"` (status_summary is L0, auto-runs — this
alone proves the tool_call path fires without hitting a classifier). Then
try an L2+ Private tool, e.g. a DMZ write:
```bash
curl -s -X POST http://localhost:8000/chat \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"message":"write a file called verify-15a.txt to the DMZ with the content: native tool calling works"}'
```
Expected: `"decision":"dispatch"`, reply starts with `Halt —` and includes
an args preview line (`filename: 'verify-15a.txt'` or similar). Then:
```bash
curl -s -X POST http://localhost:8000/chat \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"message":"approve"}'
```
Expected: reply confirms the file was written. Verify on disk:
`cat "Restricted DMZ Workspace/verify-15a.txt"`.

Record gemma4's observed tool-call hit rate informally across these
manual turns (spec §7's M3 baseline) — note in the session log how many of
the attempted turns actually emitted a `tool_call` vs. fell back to a plain
answer.

- [ ] **Step 3: Open stack — the three previously-dead `lite_llm_router` phrasings**

Requires the Open stack up (`docker compose -f PDA-Runtime/docker-compose.yml
up -d --build cooper-core`) with a working `OPENAI_API_KEY`/LiteLLM
connection. If LiteLLM/OpenRouter credentials aren't available in this
environment, **state that explicitly and skip this step rather than
fabricating a result** — this is exactly the kind of claim CLAUDE.md's
"report honestly" rule exists for. If credentials are available, retrieve
the three specific phrasings that were dead per Gotchas 2026-08-04 (check
`Obsidian Vault/brain/Gotchas.md` 2026-08-04 entry for the exact wording)
and confirm each now returns `"decision":"dispatch"` with a `tool_call:
lite_llm_router` reason.

- [ ] **Step 4: Note write in ordinary phrasing + subdirectory refusal (Open)**

```bash
KEY=$(grep '^COOPER_API_KEYS=' PDA-Runtime/.env | cut -d= -f2)
curl -s -X POST http://localhost:8001/chat \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"message":"jot down a quick note called verify-15a.md that says native tool calling round-tripped"}'
```
Expected: `"decision":"dispatch"`, halts for approval with no "could not
parse" error (this is the core §5 DoD — ordinary phrasing works with no
magic `write note X.md: Y` syntax required). Then a subdirectory attempt:
```bash
curl -s -X POST http://localhost:8001/chat \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"message":"write a note at subdir/escape.md that says test"}'
```
Expected: refused **before** any approval ticket opens (`"COOPER proposed
an invalid call..."` or similar — no `Halt —` prefix). Confirm with
`GET /pending` that nothing is queued.

- [ ] **Step 5: One full browser turn per stack**

Per CLAUDE.md: "Use the browser only for a single final visual confirmation
per step, not per iteration." If a `claude-in-chrome` browser session is
available in this environment, open Open WebUI (`http://localhost:3000` or
`:3001`), send one dispatching message through the actual chat UI on each
stack, and visually confirm the reply renders correctly. If no browser tool
is available in this session, **state that explicitly** rather than
claiming it — CLAUDE.md's honesty rule again.

- [ ] **Step 6: Write the session-log entry**

Per the spec's own header instruction ("Where this spec and the running
code disagree... say so in the session log") and CLAUDE.md's "write
findings down the day they happen": append an entry to
`Obsidian Vault/brain/Patterns.md` (or the appropriate brain file per the
`/om-capture` convention) recording:
- The four design decisions this plan locked in (listed at the top of this
  plan) and why.
- Which DoD items in Step 1-5 above were actually verified live vs. skipped
  (and why, if skipped).
- The informal gemma4 tool-call hit-rate observation from Step 2.

Use `/om-capture` or `/om-update Patterns.md <content>` to do this via the
brain skill rather than hand-editing, per the repo's own session-startup
convention.
