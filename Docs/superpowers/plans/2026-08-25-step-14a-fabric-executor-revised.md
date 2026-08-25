# Step 14a — Fabric Pattern Executor Implementation Plan (revised for 15a)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Supersedes:** `Docs/superpowers/plans/2026-08-04-step-14a-fabric-executor.md`. That plan
predates 15a (native tool-calling dispatch, shipped 2026-08-24) and was built around
classifier-era natural-language parsing of the raw chat `message` — the classifier no
longer exists, and `executor.py` handlers today receive validated, structured `args: dict`
(a `tool_call`'s JSON arguments, checked against the tool's own `parameters` JSON-Schema by
`registry.validate_args` *before* the approval gate). The original Tasks 1-2 built
`_split_fabric_request()`/`_parse_overrides()` to regex-parse a raw message for pattern name,
content, and `key=value` overrides — none of that exists in a world where the model supplies
`pattern_name`, `content_input`, and any overrides as separate structured arguments. This
revision keeps the original's pattern-catalog design (patterns live on disk under
`PDA-Fabric/<Category>/<name>.md`, `{{placeholder}}` substitution, lenient name-matching so a
typo'd pattern name never returns a magic-syntax error) and drops everything that assumed a
single free-text message.

**Goal:** Wire the four existing `PDA-Fabric/` prompt patterns into cooper-core as a governed
`fabric_pattern` executor, so raw text (pasted or described in chat) can be turned into a
filled template through a native tool-call, on both workshops.

**Architecture:** One new executor handler in `cooper-core/executor.py`, dispatched from
`_HANDLERS["fabric_pattern"]` (the pattern every other executor in that dict already follows —
see `_run_llm_api`, `_run_note_editor`). The model calls the tool with structured args
(`pattern_name`, `content_input`, optional `audience`/`focus`/`tone`/`priority`); the handler
fuzzy-matches `pattern_name` against the on-disk catalog (the model's phrasing of a pattern
name won't always be the exact file stem), fills the matched template's `{{placeholders}}`,
sends the filled prompt to the workshop's own backend (Ollama on Private via `_QWEN_MODEL`,
LiteLLM on Open via `_LITELLM_DEFAULT_MODEL`), and returns the model's output. Two registry
entries (JSON-Schema `parameters` blocks, matching every other 15a-era tool) make it
selectable. No new dependencies, no changes to `main.py`, `approval.py`, or `decision.py`.

**Tech Stack:** Python 3.11, FastAPI, pytest, stdlib `re`/`pathlib`. Existing helpers
`_ollama_complete` / `_openai_complete` from `decision.py`.

## Global Constraints

- Every behavior change lands with tests in `cooper-core/test_executor.py`; full suite must
  pass: `cd cooper-core && .venv/bin/python -m pytest`
- Standard library first — no new entries in `requirements.txt`
- No new JSON/YAML policy files; extend the two existing tool registries only
- **Registry `parameters` blocks must match the JSON-Schema subset `registry.validate_args`
  actually understands** (`type: object`/`string`/`array`, `required`, `additionalProperties:
  false`, per-string `no_path_separators`, per-array-items `url_only`) — see
  `cooper-core/registry.py`'s module docstring and `validate_args` for the exact supported
  shape. Copy the style of `lite_llm_router`'s or `obsidian_note_writer`'s existing entries in
  `Config/general_tool_registry.yaml`, not the pre-15a `inputs:`/`outputs:`-only shape (those
  two list fields may stay alongside `parameters` for human-readable docs — every current
  entry keeps both — but `parameters` is what the model and `validate_args` actually see).
- Every tool MUST carry a `workshop:` field — `check_tool()` is fail-closed and will raise
  `WorkshopViolation` without it (Gotchas 2026-07-02)
- **Do not repeat the `note_editor` mistake** (Gotchas 2026-08-04): no magic literal syntax.
  An unresolvable `pattern_name` returns the list of available patterns, never a "use this
  exact phrasing" error
- Executor handlers read from the validated `args: dict` the same way every other 2026-08-24+
  handler does (`_run_llm_api(args)`, `_run_note_editor(args)`) — never regex-parse the raw
  chat `message` for structured data; `message` reaches handlers today only for the couple of
  handlers that still want it for logging (e.g. `_run_informational`)
- Registries and the Fabric directory are **baked into the cooper-core image**, not
  bind-mounted — live verification requires `up -d --build` (Gotchas 2026-07-21, 2026-07-08)
- Live verification is native-tool-calling era, not classifier era: there is no more
  "`decision`:`dispatch` vs `answer`" classifier-reachability failure mode to route around
  (that gotcha was superseded outright by 15a — see `Obsidian Vault/brain/Gotchas.md`'s
  2026-08-24 entry). Verify by sending a chat message that plausibly prompts the model to
  call the `fabric_pattern_writer` tool, confirming the `Halt — Fabric Pattern Writer ...`
  approval message appears, approving, and confirming the filled artifact with no stray
  `{{placeholder}}` text. Also run one round-trip through the real browser (Open WebUI, both
  stacks) per the pattern this repo now follows for every dispatch-capable feature (see
  PROGRESS.md's 2026-08-25 decision-log entry) — `claude-in-chrome` is available this session.
- Commit after each task

---

### Task 1: Pattern catalog and lenient name resolution

**Files:**
- Modify: `cooper-core/executor.py` (constants block, near `_OBSIDIAN_INBOX_DIR`; new helpers
  after `_run_local_read`)
- Test: `cooper-core/test_executor.py`

**Interfaces:**
- Consumes: `_REPO_ROOT` (existing, `executor.py`)
- Produces: `_FABRIC_DIR: Path`, `_fabric_catalog() -> dict[str, Path]` (pattern key → file
  path), `_normalize(text: str) -> str`, `_resolve_pattern(name: str, catalog: dict) ->
  tuple[str | None, Path | None]` — takes a single name/phrase string (the model's
  `pattern_name` arg value), NOT a full chat message.

- [ ] **Step 1: Write the failing tests**

Add to `cooper-core/test_executor.py`:

```python
def test_fabric_catalog_finds_shipped_patterns():
    catalog = executor._fabric_catalog()
    assert "report-summary" in catalog
    assert "security-triage" in catalog
    assert catalog["report-summary"].parent.name == "Reporting"


def test_fabric_catalog_empty_when_dir_missing(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_FABRIC_DIR", tmp_path / "nope")
    assert executor._fabric_catalog() == {}


def test_resolve_pattern_matches_exact_key():
    catalog = executor._fabric_catalog()
    key, path = executor._resolve_pattern("report-summary", catalog)
    assert key == "report-summary"
    assert path.parent.name == "Reporting"


def test_resolve_pattern_matches_loosely_spaced_name():
    catalog = executor._fabric_catalog()
    key, _ = executor._resolve_pattern("Report Summary", catalog)
    assert key == "report-summary"


def test_resolve_pattern_falls_back_to_category():
    catalog = executor._fabric_catalog()
    key, path = executor._resolve_pattern("security", catalog)
    assert path.parent.name == "Security"


def test_resolve_pattern_returns_none_when_unmatched():
    catalog = executor._fabric_catalog()
    key, path = executor._resolve_pattern("something nobody named", catalog)
    assert key is None and path is None


def test_resolve_pattern_returns_none_for_empty_name():
    catalog = executor._fabric_catalog()
    key, path = executor._resolve_pattern("", catalog)
    assert key is None and path is None
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && .venv/bin/python -m pytest test_executor.py -k fabric -v`
Expected: FAIL — `AttributeError: module 'executor' has no attribute '_fabric_catalog'`

- [ ] **Step 3: Write minimal implementation**

Add to the constants block, after `_OBSIDIAN_INBOX_DIR`:

```python
_FABRIC_DIR = _REPO_ROOT / "PDA-Fabric"
```

Add these helpers after `_run_local_read()`:

```python
def _normalize(text: str) -> str:
    """Lowercase, punctuation-to-space — so 'Report Summary', 'report-summary'
    and 'report_summary' all compare equal. Deliberately lenient: naming a
    pattern must never require exact syntax (Gotchas 2026-08-04)."""
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def _fabric_catalog() -> dict:
    """Map pattern key (file stem, lowercased) -> pattern file path. Layout is
    PDA-Fabric/<Category>/<pattern-name>.md."""
    catalog = {}
    if not _FABRIC_DIR.is_dir():
        return catalog
    for path in sorted(_FABRIC_DIR.glob("*/*.md")):
        catalog[path.stem.lower()] = path
    return catalog


def _resolve_pattern(name: str, catalog: dict):
    """Match a single name/phrase (the model's pattern_name arg) against the
    catalog: exact/loose key match first (longest key first, so a two-word
    name beats a one-word category), then category-name fallback."""
    norm = f" {_normalize(name)} "
    if norm.strip():
        for key in sorted(catalog, key=len, reverse=True):
            if f" {_normalize(key)} " in norm:
                return key, catalog[key]
        for key in sorted(catalog):
            path = catalog[key]
            if f" {_normalize(path.parent.name)} " in norm:
                return key, path
    return None, None
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && .venv/bin/python -m pytest test_executor.py -k fabric -v`
Expected: 6 passed

- [ ] **Step 5: Commit**

```bash
git add cooper-core/executor.py cooper-core/test_executor.py
git commit -m "feat(fabric): pattern catalog + lenient name resolution

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Template filling

**Files:**
- Modify: `cooper-core/executor.py` (constants block; helper after `_resolve_pattern`)
- Test: `cooper-core/test_executor.py`

**Interfaces:**
- Produces: `_MAX_FABRIC_INPUT_BYTES: int`, `_FABRIC_DEFAULTS: dict`,
  `_FABRIC_PLACEHOLDER_RE`, `_FABRIC_SYSTEM_PROMPT`, `_fill_pattern(template: str, values:
  dict) -> str`

- [ ] **Step 1: Write the failing tests**

Add to `cooper-core/test_executor.py`:

```python
def test_fabric_fill_pattern_substitutes_known_and_defaults():
    out = executor._fill_pattern(
        "A={{content_input}} B={{pattern_name}} C={{audience}} D={{mystery}}",
        {"content_input": "raw", "pattern_name": "report-summary"},
    )
    assert "A=raw" in out
    assert "B=report-summary" in out
    assert "C=the owner" in out
    assert "D=unspecified" in out


def test_fabric_fill_pattern_prefers_provided_value_over_default():
    out = executor._fill_pattern("{{tone}}", {"tone": "formal"})
    assert out == "formal"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && .venv/bin/python -m pytest test_executor.py -k fabric -v`
Expected: FAIL — `AttributeError: module 'executor' has no attribute '_fill_pattern'`

- [ ] **Step 3: Write minimal implementation**

Add to the constants block, after `_FABRIC_DIR`:

```python
_MAX_FABRIC_INPUT_BYTES = 65_536  # same cap as the note/DMZ writers

# The shipped patterns' optional knobs. Anything a pattern asks for that the
# caller didn't supply resolves to "unspecified" rather than leaving a raw
# {{placeholder}} in the prompt sent to the model.
_FABRIC_DEFAULTS = {
    "audience": "the owner",
    "focus": "the main point of the input",
    "tone": "direct and neutral",
    "priority": "normal",
}
_FABRIC_PLACEHOLDER_RE = re.compile(r"\{\{([a-z_]+)\}\}")
_FABRIC_SYSTEM_PROMPT = (
    "You are COOPER's Fabric pattern processor. Follow the pattern's Instructions "
    "section exactly and produce only the finished artifact — no preamble, no "
    "commentary about the pattern itself."
)
```

Add this helper after `_resolve_pattern()`:

```python
def _fill_pattern(template: str, values: dict) -> str:
    def _sub(match):
        key = match.group(1)
        if key in values:
            return str(values[key])
        return _FABRIC_DEFAULTS.get(key, "unspecified")
    return _FABRIC_PLACEHOLDER_RE.sub(_sub, template)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && .venv/bin/python -m pytest test_executor.py -k fabric -v`
Expected: 8 passed

- [ ] **Step 5: Commit**

```bash
git add cooper-core/executor.py cooper-core/test_executor.py
git commit -m "feat(fabric): template placeholder fill

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: The executor handler

**Files:**
- Modify: `cooper-core/executor.py` (module docstring; `_HANDLERS` dict; new handler after
  `_run_note_editor`)
- Test: `cooper-core/test_executor.py`

**Interfaces:**
- Consumes: `_fabric_catalog()`, `_resolve_pattern()` (Task 1); `_fill_pattern()`,
  `_FABRIC_SYSTEM_PROMPT`, `_MAX_FABRIC_INPUT_BYTES` (Task 2); existing
  `_ollama_complete(base_url, model, messages)`, `_openai_complete(base_url, api_key, model,
  messages)`, `ExecutionError`, `_MAX_OUTPUT`, `_QWEN_MODEL`, `_OLLAMA_HOST`,
  `_LITELLM_BASE_URL`, `_LITELLM_API_KEY`, `_LITELLM_DEFAULT_MODEL`
- Produces: `_run_fabric_pattern(args: dict, workshop: str) -> str`; `_HANDLERS["fabric_pattern"]`
  entry, wired the same way every other entry in that dict is (see `_run_llm_api`/`_run_note_editor`)

- [ ] **Step 1: Write the failing tests**

Add to `cooper-core/test_executor.py` (mirrors the existing `test_llm_api_executor_*` style —
`executor.run(tool_dict, message, workshop, args_dict)`):

```python
def test_fabric_executor_open_routes_through_litellm(monkeypatch):
    captured = {}

    async def fake_complete(base_url, api_key, model, messages, **kw):
        captured["prompt"] = messages[1]["content"]
        return "  finished report  "
    monkeypatch.setattr(executor, "_openai_complete", fake_complete)
    out = asyncio.run(executor.run(
        {"executor_type": "fabric_pattern"}, "run", "open",
        {"pattern_name": "report-summary", "content_input": "we shipped the link checker today"},
    ))
    assert "finished report" in out
    assert "report-summary" in out
    assert "we shipped the link checker today" in captured["prompt"]
    assert "{{" not in captured["prompt"]


def test_fabric_executor_private_routes_through_ollama(monkeypatch):
    async def fake_complete(base_url, model, messages, **kw):
        return "local draft"
    monkeypatch.setattr(executor, "_ollama_complete", fake_complete)
    out = asyncio.run(executor.run(
        {"executor_type": "fabric_pattern"}, "run", "private",
        {"pattern_name": "security-triage", "content_input": "odd inbound traffic on port 8788"},
    ))
    assert "local draft" in out
    assert "security-triage" in out


def test_fabric_executor_applies_overrides(monkeypatch):
    captured = {}

    async def fake_complete(base_url, api_key, model, messages, **kw):
        captured["prompt"] = messages[1]["content"]
        return "ok"
    monkeypatch.setattr(executor, "_openai_complete", fake_complete)
    asyncio.run(executor.run(
        {"executor_type": "fabric_pattern"}, "run", "open",
        {
            "pattern_name": "report-summary",
            "content_input": "quarterly numbers",
            "audience": "the board",
            "tone": "formal",
        },
    ))
    assert "the board" in captured["prompt"]
    assert "formal" in captured["prompt"]


def test_fabric_executor_lists_patterns_when_name_unresolved():
    out = asyncio.run(executor.run(
        {"executor_type": "fabric_pattern"}, "run", "open",
        {"pattern_name": "something nobody named", "content_input": "hi"},
    ))
    assert "report-summary" in out
    assert "security-triage" in out
    assert "use this exact" not in out.lower()


def test_fabric_executor_rejects_oversized_input(monkeypatch):
    monkeypatch.setattr(executor, "_MAX_FABRIC_INPUT_BYTES", 10)
    out = asyncio.run(executor.run(
        {"executor_type": "fabric_pattern"}, "run", "open",
        {"pattern_name": "report-summary", "content_input": "x" * 50},
    ))
    assert "over the" in out


def test_fabric_executor_raises_execution_error_on_backend_failure(monkeypatch):
    async def boom(base_url, api_key, model, messages, **kw):
        raise RuntimeError("gateway down")
    monkeypatch.setattr(executor, "_openai_complete", boom)
    try:
        asyncio.run(executor.run(
            {"executor_type": "fabric_pattern"}, "run", "open",
            {"pattern_name": "report-summary", "content_input": "text"},
        ))
        assert False, "expected ExecutionError"
    except executor.ExecutionError as exc:
        assert "gateway down" in str(exc)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && .venv/bin/python -m pytest test_executor.py -k fabric -v`
Expected: FAIL — falls through to `_stub()`, so assertions on "finished report" fail with the
"not yet wired" string

- [ ] **Step 3: Write minimal implementation**

Add the handler after `_run_note_editor()`:

```python
async def _run_fabric_pattern(args: dict, workshop: str) -> str:
    """Fabric Pattern Writer (both workshops). Applies a PDA-Fabric prompt
    pattern to the model-supplied content and returns the filled artifact.
    The Fabric layer was specified in the governance corpus and never wired
    until Step 14a.

    Runs on the workshop's OWN backend — Private's content never leaves the
    machine, matching _run_local_llm's boundary."""
    catalog = _fabric_catalog()
    if not catalog:
        return "Workbench: no Fabric patterns are installed under PDA-Fabric/."

    pattern_name = str(args.get("pattern_name", ""))
    key, path = _resolve_pattern(pattern_name, catalog)
    if key is None:
        listing = ", ".join(f"{k} ({catalog[k].parent.name})" for k in sorted(catalog))
        return (
            "Workbench: no matching Fabric pattern found for "
            f"'{pattern_name}'. Available patterns: {listing}."
        )

    content = str(args.get("content_input", "")).strip()
    if not content:
        return f"Workbench: Fabric pattern '{key}' has no input content to work from."
    size = len(content.encode("utf-8"))
    if size > _MAX_FABRIC_INPUT_BYTES:
        return (
            f"Workbench: input is {size} bytes, over the "
            f"{_MAX_FABRIC_INPUT_BYTES}-byte cap for a Fabric pattern."
        )

    values = dict(_FABRIC_DEFAULTS)
    for knob in ("audience", "focus", "tone", "priority"):
        if args.get(knob):
            values[knob] = str(args[knob])
    values.update({
        "content_input":    content,
        "pattern_name":     key,
        "pattern_category": path.parent.name,
    })
    prompt = _fill_pattern(path.read_text(encoding="utf-8"), values)
    messages = [
        {"role": "system", "content": _FABRIC_SYSTEM_PROMPT},
        {"role": "user",   "content": prompt},
    ]
    try:
        if workshop == "private":
            filled = await _ollama_complete(_OLLAMA_HOST, _QWEN_MODEL, messages)
        else:
            filled = await _openai_complete(
                _LITELLM_BASE_URL, _LITELLM_API_KEY, _LITELLM_DEFAULT_MODEL, messages
            )
    except Exception as exc:
        raise ExecutionError(f"Fabric pattern '{key}' failed — {exc}")
    return f"[Fabric — {key} ({path.parent.name})]\n{filled.strip()[:_MAX_OUTPUT]}"
```

Add the dispatch entry to `_HANDLERS`, alongside the other lambdas:

```python
    "fabric_pattern": lambda tool, message, workshop, args: _run_fabric_pattern(args, workshop),
```

Update the module docstring: change `All 13 registry-referenced executor_types` to `All 14`,
and add to the "Supported executor_types" list after the `cli_launcher` entry:

```
  fabric_pattern — applies a PDA-Fabric prompt pattern to model-supplied content on
                  the workshop's own backend (both workshops; Private stays local)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && .venv/bin/python -m pytest test_executor.py -k fabric -v`
Expected: 14 passed

- [ ] **Step 5: Run the full suite**

Run: `cd cooper-core && .venv/bin/python -m pytest`
Expected: all pass (248 baseline + 14 new = 262 — confirm the actual current baseline count
first with a plain `pytest` run before this task, since it may have drifted since 15a's
248-test fix-forward review)

- [ ] **Step 6: Commit**

```bash
git add cooper-core/executor.py cooper-core/test_executor.py
git commit -m "feat(fabric): fabric_pattern executor, workshop-native backend

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Registry entries and live verification

**Files:**
- Modify: `Config/general_tool_registry.yaml` (append to the tools list)
- Modify: `Config/private_tool_registry.yaml` (append to the tools list)
- Modify: `cooper-core/test_registry.py` only if it hardcodes a total tool count

**Interfaces:**
- Consumes: `executor_type: fabric_pattern` from Task 3
- Produces: tool ids `fabric_pattern_writer` (Open) and `fabric_pattern_writer_private`
  (Private), rendered as OpenAI tool schemas by `registry.render_workshop_tools()` and attached
  to every turn per 15a

- [ ] **Step 1: Add the Open Workshop entry**

Append to `Config/general_tool_registry.yaml`, matching the existing two-space list
indentation and the `parameters:` JSON-Schema shape used by `lite_llm_router` /
`obsidian_note_writer` just above it in the same file:

```yaml
  - id: fabric_pattern_writer
    name: Fabric Pattern Writer
    drawer: Knowledge Shelf
    workshop: Open Workshop
    description: >-
      Fill a reusable Fabric prompt pattern from raw notes, conversation text, or workflow
      output. Available patterns: report-summary (Reporting), research-synthesis (Research),
      review-checklist (Review), security-triage (Security). Name the pattern by its id or
      category, and pass the raw text to work from as content_input.
    permission_level: 3
    approval_required: true
    executor_type: fabric_pattern
    enabled: true
    parameters:
      type: object
      properties:
        pattern_name:
          type: string
          description: "Which Fabric pattern to apply, e.g. 'report-summary' or 'security'. Loosely matched — exact id or category name both work."
        content_input:
          type: string
          description: "The raw text (notes, conversation, workflow output) the pattern should be applied to."
        audience:
          type: string
          description: "Optional — who the output is for. Defaults to 'the owner' if omitted."
        focus:
          type: string
          description: "Optional — what the output should emphasize. Defaults to the main point of the input if omitted."
        tone:
          type: string
          description: "Optional — desired tone. Defaults to direct and neutral if omitted."
        priority:
          type: string
          description: "Optional — urgency framing. Defaults to normal if omitted."
      required:
        - pattern_name
        - content_input
      additionalProperties: false
    inputs:
      - pattern_name
      - content_input
    outputs:
      - filled_template
    notes: Open Workshop only. Input is sent to the cloud gateway — Category 1 data only.
```

- [ ] **Step 2: Add the Private Workshop entry**

Append to `Config/private_tool_registry.yaml`. Level 2 mirrors `qwen_local_assistant` — same
class of action (local model, no external egress):

```yaml
  - id: fabric_pattern_writer_private
    name: Fabric Pattern Writer
    drawer: Local Models
    workshop: Private Workshop
    description: >-
      Fill a reusable Fabric prompt pattern from raw notes or conversation text, using the
      local model only. Available patterns: report-summary (Reporting), research-synthesis
      (Research), review-checklist (Review), security-triage (Security). Name the pattern by
      its id or category, and pass the raw text to work from as content_input.
    permission_level: 2
    approval_required: true
    executor_type: fabric_pattern
    enabled: true
    parameters:
      type: object
      properties:
        pattern_name:
          type: string
          description: "Which Fabric pattern to apply, e.g. 'report-summary' or 'security'. Loosely matched — exact id or category name both work."
        content_input:
          type: string
          description: "The raw text (notes, conversation, workflow output) the pattern should be applied to."
        audience:
          type: string
          description: "Optional — who the output is for. Defaults to 'the owner' if omitted."
        focus:
          type: string
          description: "Optional — what the output should emphasize. Defaults to the main point of the input if omitted."
        tone:
          type: string
          description: "Optional — desired tone. Defaults to direct and neutral if omitted."
        priority:
          type: string
          description: "Optional — urgency framing. Defaults to normal if omitted."
      required:
        - pattern_name
        - content_input
      additionalProperties: false
    inputs:
      - pattern_name
      - content_input
    outputs:
      - filled_template
    notes: Private Workshop only. Runs on local Ollama — content never leaves the machine.
```

- [ ] **Step 3: Verify the registries still parse and both tools are visible**

Run:
```bash
cd cooper-core && .venv/bin/python -c "
import registry
for ws in ('open', 'private'):
    names = [t['name'] for t in registry.list_tools(ws)]
    print(ws, len(names), 'Fabric Pattern Writer' in names)
    schema = [s for s in registry.render_workshop_tools(ws) if s['function']['name'].startswith('fabric_pattern_writer')]
    print(ws, 'schema ok:', bool(schema) and 'pattern_name' in schema[0]['function']['parameters']['properties'])
"
```
Expected: both workshops show `True` twice each. (Do not hardcode an expected tool *count* in
this command — read the printed count and sanity-check it went up by exactly one per workshop
versus the pre-Task-4 baseline, since the exact baseline may have drifted.)

- [ ] **Step 4: Run the full suite**

Run: `cd cooper-core && .venv/bin/python -m pytest`
Expected: all pass. `test_registry.py` may assert tool counts — if it does, update the expected
counts in that test as part of this task.

- [ ] **Step 5: Rebuild both stacks and live-verify via native tool-calling**

The registry and `PDA-Fabric/` are baked into the image, so a restart is not enough:

```bash
docker compose -f PDA-Runtime/docker-compose.yml up -d --build cooper-core
docker compose -f PDA-Runtime/docker-compose.private.yml up -d --build cooper-core
```

Get the API key (the plan's implementer should ask the owner to supply it interactively if
`.env` is not readable in that session — it was access-denied to Claude by permission
settings in the 2026-08-25 session; do not assume that's universal, try reading it first):
```bash
KEY=$(grep '^COOPER_API_KEYS=' PDA-Runtime/.env | cut -d= -f2 | cut -d, -f1)
```

Open stack:
```bash
curl -s -X POST http://localhost:8001/chat -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"message":"Could you please run the report-summary fabric pattern on this: today we wired the fabric executor into both workshops and added JSON-schema tool args"}'
```
Expected: a `Halt — Fabric Pattern Writer … requires approval` reply with an `Args —` line
showing `pattern_name`/`content_input`. There is no `decision` field to check against a
classifier outcome anymore (15a retired that) — the halt message itself is the proof the
tool_call fired.

```bash
curl -s -X POST http://localhost:8001/chat -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" -d '{"message":"yes, go ahead"}'
```
Expected: a `[Fabric — report-summary (Reporting)]` header followed by a structured summary,
with no `{{placeholder}}` text anywhere in the output.

Repeat the same two-step round trip against Private (`localhost:8000`), naming a Private-scope
phrasing (e.g. "run the security-triage pattern on this: repeated failed logins from the same
IP").

- [ ] **Step 6: Browser click-through, both stacks**

This repo's now-standard verification step for any dispatch-capable feature (see PROGRESS.md's
2026-08-25 decision-log entry): using `claude-in-chrome`, open Open WebUI on each stack
(`localhost:3000` Open, `localhost:3001` Private), send a chat message phrased to invoke the
Fabric Pattern Writer, approve the halt, and confirm the filled artifact renders in the
browser. Before sending anything, check each stack's Admin → Connections shows exactly the
documented `cooper-core:<port>/v1` entry (plus Open's sanctioned OpenRouter connection) — the
2026-08-25 session found and fixed real drift here twice in one day; don't assume it's still
correct without looking.

- [ ] **Step 7: Commit**

```bash
git add Config/general_tool_registry.yaml Config/private_tool_registry.yaml cooper-core/test_registry.py
git commit -m "feat(fabric): register Fabric Pattern Writer in both workshops

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Record the outcome**

Append a dated entry to `PROGRESS.md`'s decision log covering: 14a shipped, the live dispatch
result on both stacks (blocking + browser), and any new gotcha discovered. Update
`Obsidian Vault/brain/North Star.md` to mark 14a done and 15c/14b (whichever the owner
confirms) next per the execution order in PROGRESS.md's roadmap table.

---

## Self-Review

**Spec coverage (14a row of the Step 14 spec):** "`fabric_pattern` executor + registry entry
(T4)" — Tasks 1-3 build the executor, Task 4 registers it. DoD "name a pattern, paste raw
text, approve, get the filled template back; verified against a real conversation" — Task 4
Steps 5-6, using real session content as the input, verified both via blocking API and browser.

**What changed from the 2026-08-04 original and why:** dropped `_split_fabric_request()` and
`_parse_overrides()` entirely — post-15a, the model supplies `pattern_name`, `content_input`,
and any override knobs as separate structured `tool_call` arguments, validated against the
registry's `parameters` JSON-Schema before the approval gate ever sees them, so there is no
raw message left to colon-split or regex-scan for `key=value` pairs. `_resolve_pattern()` now
matches a single name/phrase argument instead of scanning a whole free-text message. Registry
entries gained a `parameters` JSON-Schema block (the mechanism 15a actually uses to render
tool schemas and validate args) alongside the legacy `inputs`/`outputs` lists that every
existing entry still carries for human-readable docs. Live verification dropped the
classifier-phrasing workaround (Gotchas 2026-08-04, superseded outright by 15a) in favor of
checking for the native `Halt — ... requires approval` message, and gained a browser
click-through step matching the standard this repo established the same day as this revision.

**Placeholders:** none — every step carries runnable code or an exact command.

**Type consistency:** `_fabric_catalog()` returns `dict[str, Path]`, consumed that way by
`_resolve_pattern()` in Tasks 1 and 3; `_run_fabric_pattern(args: dict, workshop: str)` matches
the calling convention every other `_HANDLERS` entry uses; `_ollama_complete(base_url, model,
messages)` and `_openai_complete(base_url, api_key, model, messages)` match the signatures the
existing tests already mock (`test_llm_api_executor_*`, `test_local_llm_*`).

**Known deviation from the spec:** the spec listed 14a as chat-only; this plan also registers
the Private entry, since the executor is workshop-agnostic and gating Private behind a later
slice would leave a working capability artificially disabled — same deviation the 2026-08-04
original already made and recorded.
