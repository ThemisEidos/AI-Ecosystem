# Step 14a — Fabric Pattern Executor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the four existing `PDA-Fabric/` prompt patterns into cooper-core as a governed `fabric_pattern` executor, so raw conversation/workflow text can be turned into a filled template through chat.

**Architecture:** One new executor handler in `cooper-core/executor.py` (the repo's established pattern — one handler function per `executor_type`, dispatched from `run()`). It discovers patterns from disk, resolves which pattern the user named, substitutes `{{placeholders}}`, sends the filled template to the workshop's own backend (Ollama on Private, LiteLLM on Open), and returns the model's output. Two registry entries make it selectable. No new dependencies, no changes to `main.py`, `approval.py`, or the classifier.

**Tech Stack:** Python 3.11, FastAPI, pytest, stdlib `re`/`pathlib`. Existing helpers `_ollama_complete` / `_openai_complete` from `decision.py`.

## Global Constraints

- Every behavior change lands with tests in `cooper-core/test_executor.py`; full suite must pass: `cd cooper-core && .venv/bin/python -m pytest`
- Standard library first — no new entries in `requirements.txt`
- No new JSON/YAML policy files; extend the two existing tool registries only
- Tool registry entry shape is fixed: `{id, name, drawer, workshop, description, permission_level, approval_required, executor_type, enabled, inputs, outputs, notes}`
- Every tool MUST carry a `workshop:` field — `check_tool()` is fail-closed and will raise `WorkshopViolation` without it (Gotchas 2026-07-02)
- **Do not repeat the `note_editor` mistake** (Gotchas 2026-08-04): no magic literal syntax. An unrecognized request returns the list of available patterns, never a "use this exact phrasing" error
- Registries and the Fabric directory are **baked into the cooper-core image**, not bind-mounted — live verification requires `up -d --build` (Gotchas 2026-07-21, 2026-07-08)
- Commit after each task

---

### Task 1: Pattern catalog and resolution

**Files:**
- Modify: `cooper-core/executor.py` (constants block ~line 63-121; new helpers after `_run_local_read`)
- Test: `cooper-core/test_executor.py`

**Interfaces:**
- Consumes: `_REPO_ROOT` (existing, `executor.py:59`)
- Produces: `_FABRIC_DIR: Path`, `_fabric_catalog() -> dict[str, Path]` (pattern key → file path), `_normalize(text: str) -> str`, `_resolve_pattern(message: str, catalog: dict) -> tuple[str | None, Path | None]`

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


def test_resolve_pattern_matches_pattern_name():
    catalog = executor._fabric_catalog()
    key, path = executor._resolve_pattern("run the report-summary pattern: hi", catalog)
    assert key == "report-summary"
    assert path.parent.name == "Reporting"


def test_resolve_pattern_matches_loosely_spaced_name():
    catalog = executor._fabric_catalog()
    key, _ = executor._resolve_pattern("apply the Report Summary template: hi", catalog)
    assert key == "report-summary"


def test_resolve_pattern_falls_back_to_category():
    catalog = executor._fabric_catalog()
    key, path = executor._resolve_pattern("use the security fabric pattern: hi", catalog)
    assert path.parent.name == "Security"


def test_resolve_pattern_returns_none_when_unnamed():
    catalog = executor._fabric_catalog()
    key, path = executor._resolve_pattern("do something useful with this text", catalog)
    assert key is None and path is None
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && .venv/bin/python -m pytest test_executor.py -k fabric -v`
Expected: FAIL — `AttributeError: module 'executor' has no attribute '_fabric_catalog'`

- [ ] **Step 3: Write minimal implementation**

Add to the constants block in `cooper-core/executor.py`, after `_OBSIDIAN_INBOX_DIR` (line 63):

```python
_FABRIC_DIR = _REPO_ROOT / "PDA-Fabric"
```

Add these helpers after `_run_local_read()` (which ends at line 288):

```python
def _normalize(text: str) -> str:
    """Lowercase, punctuation-to-space — so 'Report Summary', 'report-summary'
    and 'report_summary' all compare equal. Deliberately lenient: naming a
    pattern must never require exact syntax (Gotchas 2026-08-04)."""
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def _fabric_catalog() -> dict:
    """Map pattern key (file stem, lowercased) -> SKILL-style pattern path.
    Layout is PDA-Fabric/<Category>/<pattern-name>.md."""
    catalog = {}
    if not _FABRIC_DIR.is_dir():
        return catalog
    for path in sorted(_FABRIC_DIR.glob("*/*.md")):
        catalog[path.stem.lower()] = path
    return catalog


def _resolve_pattern(message: str, catalog: dict):
    """Find which pattern the message names. Longest pattern name first (so a
    two-word name beats a one-word category), then category fallback."""
    norm = f" {_normalize(message)} "
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

### Task 2: Template filling and request parsing

**Files:**
- Modify: `cooper-core/executor.py` (constants block; helpers after `_resolve_pattern`)
- Test: `cooper-core/test_executor.py`

**Interfaces:**
- Consumes: `_normalize()` from Task 1
- Produces: `_FABRIC_DEFAULTS: dict`, `_MAX_FABRIC_INPUT_BYTES: int`, `_parse_overrides(text: str) -> dict`, `_fill_pattern(template: str, values: dict) -> str`, `_split_fabric_request(message: str) -> tuple[str, str]` returning `(head, content)`

- [ ] **Step 1: Write the failing tests**

Add to `cooper-core/test_executor.py`:

```python
def test_fabric_split_request_takes_text_after_first_colon():
    head, content = executor._split_fabric_request(
        "run the report-summary pattern: line one\nline two: with a colon"
    )
    assert head == "run the report-summary pattern"
    assert content == "line one\nline two: with a colon"


def test_fabric_split_request_without_colon_uses_whole_message():
    head, content = executor._split_fabric_request("report-summary of my day")
    assert content == "report-summary of my day"


def test_fabric_parse_overrides_reads_key_values():
    got = executor._parse_overrides("report-summary audience=my manager; tone=formal")
    assert got == {"audience": "my manager", "tone": "formal"}


def test_fabric_parse_overrides_ignores_unknown_keys():
    assert executor._parse_overrides("colour=red focus=budget") == {"focus": "budget"}


def test_fabric_fill_pattern_substitutes_known_and_defaults():
    out = executor._fill_pattern(
        "A={{content_input}} B={{pattern_name}} C={{audience}} D={{mystery}}",
        {"content_input": "raw", "pattern_name": "report-summary"},
    )
    assert "A=raw" in out
    assert "B=report-summary" in out
    assert "C=the owner" in out
    assert "D=unspecified" in out
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && .venv/bin/python -m pytest test_executor.py -k fabric -v`
Expected: FAIL — `AttributeError: module 'executor' has no attribute '_split_fabric_request'`

- [ ] **Step 3: Write minimal implementation**

Add to the constants block, after `_FABRIC_DIR`:

```python
_MAX_FABRIC_INPUT_BYTES = 65_536  # same cap as the note/DMZ writers

# The shipped patterns' knobs. Anything a pattern asks for that we can't fill
# resolves to "unspecified" rather than leaving a raw {{placeholder}} in the prompt.
_FABRIC_DEFAULTS = {
    "audience": "the owner",
    "focus": "the main point of the input",
    "tone": "direct and neutral",
    "priority": "normal",
}
_FABRIC_PLACEHOLDER_RE = re.compile(r"\{\{([a-z_]+)\}\}")
_FABRIC_OVERRIDE_RE = re.compile(
    r"\b(audience|focus|tone|priority)\s*=\s*([^\n;]+)", re.IGNORECASE
)
_FABRIC_SYSTEM_PROMPT = (
    "You are COOPER's Fabric pattern processor. Follow the pattern's Instructions "
    "section exactly and produce only the finished artifact — no preamble, no "
    "commentary about the pattern itself."
)
```

Add these helpers after `_resolve_pattern()`:

```python
def _split_fabric_request(message: str):
    """'<pattern naming + options>: <raw content>'. Everything after the FIRST
    colon is content (raw conversations contain colons); the head carries the
    pattern name and any key=value overrides. No colon -> the whole message is
    content and the head is empty."""
    head, sep, tail = message.partition(":")
    if sep and tail.strip():
        return head.strip(), tail.strip()
    return "", message.strip()


def _parse_overrides(text: str) -> dict:
    """Optional 'audience=... tone=...' knobs. Unknown keys are ignored."""
    return {
        m.group(1).lower(): m.group(2).strip()
        for m in _FABRIC_OVERRIDE_RE.finditer(text)
    }


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
Expected: 11 passed

- [ ] **Step 5: Commit**

```bash
git add cooper-core/executor.py cooper-core/test_executor.py
git commit -m "feat(fabric): request parsing, overrides, placeholder fill

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: The executor handler

**Files:**
- Modify: `cooper-core/executor.py` (module docstring lines 4 and 19-39; `run()` dispatch ~line 266; new handler after `_run_note_editor`)
- Test: `cooper-core/test_executor.py`

**Interfaces:**
- Consumes: `_fabric_catalog()`, `_resolve_pattern()` (Task 1); `_split_fabric_request()`, `_parse_overrides()`, `_fill_pattern()`, `_FABRIC_SYSTEM_PROMPT`, `_MAX_FABRIC_INPUT_BYTES` (Task 2); existing `_ollama_complete(base_url, model, messages)`, `_openai_complete(base_url, api_key, model, messages)`, `ExecutionError`, `_MAX_OUTPUT`
- Produces: `_run_fabric_pattern(message: str, workshop: str) -> str`; `executor_type == "fabric_pattern"` routed from `run()`

- [ ] **Step 1: Write the failing tests**

Add to `cooper-core/test_executor.py`:

```python
def test_fabric_executor_open_routes_through_litellm(monkeypatch):
    captured = {}

    async def fake_complete(base_url, api_key, model, messages, **kw):
        captured["prompt"] = messages[1]["content"]
        return "  finished report  "
    monkeypatch.setattr(executor, "_openai_complete", fake_complete)
    out = asyncio.run(executor.run(
        {"executor_type": "fabric_pattern"},
        "run the report-summary pattern: we shipped the link checker today",
        "open",
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
        {"executor_type": "fabric_pattern"},
        "run the security-triage pattern: odd inbound traffic on port 8788",
        "private",
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
        {"executor_type": "fabric_pattern"},
        "report-summary audience=the board; tone=formal: quarterly numbers",
        "open",
    ))
    assert "the board" in captured["prompt"]
    assert "formal" in captured["prompt"]


def test_fabric_executor_lists_patterns_when_none_named():
    out = asyncio.run(executor.run(
        {"executor_type": "fabric_pattern"}, "do the thing with this", "open"
    ))
    assert "report-summary" in out
    assert "security-triage" in out
    assert "use this exact" not in out.lower()


def test_fabric_executor_rejects_oversized_input(monkeypatch):
    monkeypatch.setattr(executor, "_MAX_FABRIC_INPUT_BYTES", 10)
    out = asyncio.run(executor.run(
        {"executor_type": "fabric_pattern"},
        "report-summary: " + "x" * 50,
        "open",
    ))
    assert "over the" in out


def test_fabric_executor_raises_execution_error_on_backend_failure(monkeypatch):
    async def boom(base_url, api_key, model, messages, **kw):
        raise RuntimeError("gateway down")
    monkeypatch.setattr(executor, "_openai_complete", boom)
    try:
        asyncio.run(executor.run(
            {"executor_type": "fabric_pattern"}, "report-summary: text", "open"
        ))
        assert False, "expected ExecutionError"
    except executor.ExecutionError as exc:
        assert "gateway down" in str(exc)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && .venv/bin/python -m pytest test_executor.py -k fabric -v`
Expected: FAIL — the executor falls through to `_stub()`, so assertions on "finished report" fail with the "not yet wired" string

- [ ] **Step 3: Write minimal implementation**

Add the handler after `_run_note_editor()` (which ends at line 398):

```python
async def _run_fabric_pattern(message: str, workshop: str) -> str:
    """Fabric Pattern Writer (both workshops). Applies a PDA-Fabric prompt
    pattern to raw input and returns the model's filled artifact. The Fabric
    layer was specified in the governance corpus and never wired until Step 14a.

    Runs on the workshop's OWN backend — Private's content never leaves the
    machine, matching _run_local_llm's boundary."""
    catalog = _fabric_catalog()
    if not catalog:
        return "Workbench: no Fabric patterns are installed under PDA-Fabric/."

    key, path = _resolve_pattern(message, catalog)
    if key is None:
        listing = ", ".join(f"{k} ({catalog[k].parent.name})" for k in sorted(catalog))
        return (
            "Workbench: the request didn't name a Fabric pattern. "
            f"Available patterns: {listing}."
        )

    head, content = _split_fabric_request(message)
    if not content:
        return f"Workbench: Fabric pattern '{key}' has no input content to work from."
    size = len(content.encode("utf-8"))
    if size > _MAX_FABRIC_INPUT_BYTES:
        return (
            f"Workbench: input is {size} bytes, over the "
            f"{_MAX_FABRIC_INPUT_BYTES}-byte cap for a Fabric pattern."
        )

    values = dict(_FABRIC_DEFAULTS)
    values.update(_parse_overrides(head))
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

Add the dispatch branch in `run()`, immediately after the `cli_launcher` branch (line 266-267):

```python
    if executor_type == "fabric_pattern":
        return await _run_fabric_pattern(message, workshop)
```

Update the module docstring: change `All 13 registry-referenced executor_types` (line 4) to `All 14`, and add to the supported list after the `cli_launcher` entry (line 39):

```
  fabric_pattern — applies a PDA-Fabric prompt pattern to raw input on the
                  workshop's own backend (both workshops; Private stays local)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && .venv/bin/python -m pytest test_executor.py -k fabric -v`
Expected: 17 passed

- [ ] **Step 5: Run the full suite**

Run: `cd cooper-core && .venv/bin/python -m pytest`
Expected: all pass (206 baseline + 17 new = 223)

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

**Interfaces:**
- Consumes: `executor_type: fabric_pattern` from Task 3
- Produces: tool ids `fabric_pattern_writer` (Open) and `fabric_pattern_writer_private` (Private), selectable by `registry.select_tool_llm`

- [ ] **Step 1: Add the Open Workshop entry**

Append to `Config/general_tool_registry.yaml`, matching the existing two-space list indentation:

```yaml
  - id: fabric_pattern_writer
    name: Fabric Pattern Writer
    drawer: Knowledge Shelf
    workshop: Open Workshop
    description: Fill a reusable Fabric template or prompt pattern (reporting, research, review, security) from raw notes, conversation text, or workflow output.
    permission_level: 3
    approval_required: true
    executor_type: fabric_pattern
    enabled: true
    inputs:
      - pattern_name
      - content_input
    outputs:
      - filled_template
    notes: Open Workshop only. Input is sent to the cloud gateway — Category 1 data only.
```

- [ ] **Step 2: Add the Private Workshop entry**

Append to `Config/private_tool_registry.yaml`. Level 2 mirrors `qwen_local_assistant` — same class of action (local model, no external egress):

```yaml
  - id: fabric_pattern_writer_private
    name: Fabric Pattern Writer
    drawer: Local Models
    workshop: Private Workshop
    description: Fill a reusable Fabric template or prompt pattern (reporting, research, review, security) from raw notes or conversation text, using the local model only.
    permission_level: 2
    approval_required: true
    executor_type: fabric_pattern
    enabled: true
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
    names = [t['name'] for t in registry.load_tools(ws)]
    print(ws, len(names), 'Fabric Pattern Writer' in names)
"
```
Expected: `open 12 True` and `private 9 True`. If `load_tools` is named differently, read `registry.py`'s public functions and use the one backing `GET /tools`.

- [ ] **Step 4: Run the full suite**

Run: `cd cooper-core && .venv/bin/python -m pytest`
Expected: all pass. `test_registry.py` may assert tool counts — if it does, update the expected counts in that test as part of this task.

- [ ] **Step 5: Rebuild and live-verify on the Open stack**

The registry and `PDA-Fabric/` are baked into the image, so a restart is not enough:

```bash
docker compose -f PDA-Runtime/docker-compose.yml up -d --build cooper-core
KEY=$(grep '^COOPER_API_KEYS=' PDA-Runtime/.env | cut -d= -f2 | cut -d, -f1)
curl -s -X POST http://localhost:8001/chat -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"message":"run the report-summary fabric pattern: today we wired the fabric executor, fixed the open webui key, and added openrouter as a second connection"}'
```

Expected: `"decision":"dispatch"` and a `Halt — Fabric Pattern Writer … requires approval` reply.

**Check the `decision` field, not the prose.** If it returns `"decision":"answer"`, the tool did NOT run — that is the known classifier-reachability failure (Gotchas 2026-08-04). Record the exact phrasings tried in that gotcha entry; do not redesign the executor around it.

- [ ] **Step 6: Approve and confirm the artifact**

```bash
curl -s -X POST http://localhost:8001/chat -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" -d '{"message":"approve"}'
```

Expected: a `[Fabric — report-summary (Reporting)]` header followed by a structured summary of the input, with no `{{placeholder}}` text anywhere in the output.

- [ ] **Step 7: Commit**

```bash
git add Config/general_tool_registry.yaml Config/private_tool_registry.yaml cooper-core/test_registry.py
git commit -m "feat(fabric): register Fabric Pattern Writer in both workshops

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Record the outcome**

Append a dated entry to `PROGRESS.md`'s decision log covering: 14a shipped, the live dispatch result (including whether the classifier routed it on the first phrasing), and any new gotcha discovered. Update `Obsidian Vault/brain/North Star.md` to mark 14a done and 14b next.

---

## Self-Review

**Spec coverage (14a row of the Step 14 spec):** "`fabric_pattern` executor + registry entry (T4)" — Tasks 1-3 build the executor, Task 4 registers it. DoD "paste raw text, name a pattern, approve, get the filled template back; verified against a real conversation" — Task 4 Steps 5-6, using real session content as the input.

**Placeholders:** none — every step carries runnable code or an exact command.

**Type consistency:** `_fabric_catalog()` returns `dict[str, Path]` and is consumed as such by `_resolve_pattern()` in Tasks 1 and 3; `_split_fabric_request()` returns `(head, content)` and is destructured that way in Task 3; `_ollama_complete(base_url, model, messages)` and `_openai_complete(base_url, api_key, model, messages)` match the signatures the existing tests already mock.

**Known deviation from the spec:** the spec listed 14a as chat-only; this plan also registers the Private entry, since the executor is workshop-agnostic and gating Private behind a later slice would leave a working capability artificially disabled.
