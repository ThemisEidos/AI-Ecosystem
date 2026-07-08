# Step 11 — Self-Improvement Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a successful dispatch→review cycle, COOPER drafts a candidate `SKILL.md` into `Skills/_drafts/` (never loadable); the operator promotes it through the approval gate; every knowledge-skill activation is counted in `cooper_memory.db`.

**Architecture:** New `cooper-core/proposer.py` reuses the archivist's LLM-extraction pattern (JSON-schema-constrained call) to write drafts. Promotion is a new approval-gated `promote_skill` registry tool reusing Step 10's `register_import`-style promotion. Stats live in a new `skillmd_stats` table beside the archivist's tables. Spec: `Docs/superpowers/specs/2026-07-08-cooper-hermes-merge-design.md` §4.

**Tech Stack:** Python 3.11+, sqlite3 (stdlib), PyYAML, pytest. No new dependencies.

**DEPENDS ON: Step 10 must be merged first** — this plan consumes `skills.parse_skill_md`, `skills.compute_content_hash`, `skills._append_manifest_entry`, `skills.skill_context_for`, and the `Config/skills_registry.yaml` manifest.

## Global Constraints

- Branch from the branch where Step 10 landed (e.g. `step-11-proposer` off `step-10-skills` or off `step-9-dockerize` after merge).
- Stdlib + existing deps only. No new pip installs.
- `Skills/_drafts/` is never loadable (enforced by Step 10's `_RESERVED_DIRS`) — this plan relies on that, tests re-verify it.
- Drafting is **non-fatal**: any proposer failure must never break the dispatch reply (mirror `archivist.remember`'s try/except treatment in `main._execute`).
- Prompt-level self-optimization (DSPy/GEPA) is OUT OF SCOPE (spec §4).
- Tests: `cd cooper-core && python3 -m pytest test_proposer.py -v`.
- v1 proposes a draft only when the tool that ran has NO existing skill covering it (dedupe by manifest id and by existing draft dir).

---

### Task 1: proposer.py — draft generation

**Files:**
- Create: `cooper-core/proposer.py`
- Test: `cooper-core/test_proposer.py`

**Interfaces:**
- Consumes: `skills.parse_skill_md`, `skills.load_manifest` (Step 10); `decision._ollama_complete` / `decision._openai_complete` signatures (same as archivist).
- Produces: `async draft_skill(tool: dict, message: str, raw_output: str, *, base_url, api_key, model, backend, repo_root=None, manifest_path=None, extract_fn=None) -> Optional[Path]` — returns the created draft dir, or None when skipped/failed. `slugify(name: str) -> str`.

- [ ] **Step 1: Write the failing tests**

```python
# cooper-core/test_proposer.py
"""Tests for the self-improvement draft loop (Step 11)."""
import asyncio
from pathlib import Path

import pytest
import yaml

import proposer
import skills


FAKE_DRAFT = {
    "name": "stack-health-check",
    "description": "Run the stack health script and interpret its output.",
    "body": "## Procedure\nRun Test-PDAStack.ps1 and report failures first.",
}


def fake_extract(*args, **kwargs):
    async def _inner():
        return dict(FAKE_DRAFT)
    return _inner()


def run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


def _draft(tmp_path, extract=fake_extract, manifest_entries=None):
    manifest = tmp_path / "Config" / "skills_registry.yaml"
    manifest.parent.mkdir(exist_ok=True)
    manifest.write_text(yaml.safe_dump({"skills": manifest_entries or []}), encoding="utf-8")
    return run(proposer.draft_skill(
        {"id": "stack_test", "name": "Stack Test"},
        "check the stack health",
        "[Test-PDAStack.ps1 — OK]\nall green",
        base_url="", api_key="", model="", backend="ollama",
        repo_root=tmp_path, manifest_path=manifest,
        extract_fn=lambda *a, **k: extract(),
    ))


def test_draft_written_to_drafts_dir(tmp_path):
    path = _draft(tmp_path)
    assert path == tmp_path / "Skills" / "_drafts" / "stack-health-check"
    meta, body = skills.parse_skill_md((path / "SKILL.md").read_text(encoding="utf-8"))
    assert meta["name"] == "stack-health-check"
    assert "Procedure" in body


def test_draft_is_not_loadable(tmp_path):
    _draft(tmp_path)
    manifest = tmp_path / "Config" / "skills_registry.yaml"
    assert skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path) == []


def test_no_draft_when_skill_already_registered(tmp_path):
    entry = {"id": "stack-health-check", "path": "Skills/x", "workshop": "open",
             "permission_level": 1, "content_hash": "aa"}
    assert _draft(tmp_path, manifest_entries=[entry]) is None


def test_no_duplicate_draft(tmp_path):
    assert _draft(tmp_path) is not None
    assert _draft(tmp_path) is None  # second run: draft dir already exists


def test_extraction_failure_returns_none(tmp_path):
    def broken(*a, **k):
        async def _inner():
            raise RuntimeError("llm down")
        return _inner()
    assert _draft(tmp_path, extract=broken) is None
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && python3 -m pytest test_proposer.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'proposer'`.

- [ ] **Step 3: Write the implementation**

```python
# cooper-core/proposer.py
"""
COOPER Proposer — self-improvement loop, draft side (Step 11).

After a successful dispatch→review cycle, draft a candidate SKILL.md into
Skills/_drafts/<slug>/. Drafts are inert (Step 10 reserves _drafts) until
the operator promotes one through the approval gate (promote_skill tool).

Governance: the agent may PROPOSE skills; only an approval can ACTIVATE one.
Spec: Docs/superpowers/specs/2026-07-08-cooper-hermes-merge-design.md §4.
"""
import json
import re
from pathlib import Path
from typing import Awaitable, Callable, Optional

from decision import _ollama_complete, _openai_complete
import skills

_REPO_ROOT = Path(__file__).resolve().parent.parent

_DRAFT_SYSTEM = """\
You are COOPER's Proposer. A dispatched task just succeeded. If the procedure is
worth reusing, write it as a skill. Output JSON only — no other text.

{"name":"<lowercase-hyphen slug, 2-4 words>","description":"<one line: when to use this>","body":"<markdown: '## When to use' and '## Procedure' sections, under 300 words>"}\
"""

_DRAFT_SCHEMA = {
    "type": "object",
    "properties": {
        "name":        {"type": "string"},
        "description": {"type": "string"},
        "body":        {"type": "string"},
    },
    "required": ["name", "description", "body"],
}


def slugify(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return slug or "unnamed-skill"


async def _extract_draft(
    message: str, raw_output: str, *,
    base_url: str, api_key: str, model: str, backend: str,
) -> dict:
    msgs = [
        {"role": "system", "content": _DRAFT_SYSTEM},
        {"role": "user", "content": f"Request: {message}\n\nResult:\n{raw_output[:2000]}"},
    ]
    if backend == "openai":
        raw = await _openai_complete(
            base_url, api_key, model, msgs, temperature=0,
            response_format={"type": "json_schema", "json_schema": {
                "name": "skill_draft", "strict": True,
                "schema": {**_DRAFT_SCHEMA, "additionalProperties": False},
            }},
        )
    else:
        raw = await _ollama_complete(
            base_url, model, msgs, options={"temperature": 0}, fmt=_DRAFT_SCHEMA,
        )
    return json.loads(raw)


async def draft_skill(
    tool: dict,
    message: str,
    raw_output: str,
    *,
    base_url: str,
    api_key: str,
    model: str,
    backend: str,
    repo_root: Optional[Path] = None,
    manifest_path: Optional[Path] = None,
    extract_fn: Optional[Callable[..., Awaitable[dict]]] = None,
) -> Optional[Path]:
    """Draft a SKILL.md into Skills/_drafts/<slug>/. Returns the dir, or None
    when skipped (already covered / duplicate) or on any failure (non-fatal)."""
    extract_fn = extract_fn or _extract_draft
    root = repo_root or _REPO_ROOT
    try:
        draft = await extract_fn(
            message, raw_output,
            base_url=base_url, api_key=api_key, model=model, backend=backend,
        )
        name = slugify(str(draft.get("name", "")))
        description = str(draft.get("description", "")).strip()
        body = str(draft.get("body", "")).strip()
        if not description or not body:
            return None
        registered = {str(e.get("id", "")) for e in skills.load_manifest(manifest_path)}
        if name in registered:
            return None
        draft_dir = root / "Skills" / "_drafts" / name
        if draft_dir.exists():
            return None
        draft_dir.mkdir(parents=True)
        (draft_dir / "SKILL.md").write_text(
            f"---\nname: {name}\ndescription: {description}\n---\n\n{body}\n",
            encoding="utf-8",
        )
        return draft_dir
    except Exception as exc:
        print(f"  [!!] proposer.draft_skill failed (non-fatal): {exc}")
        return None
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && python3 -m pytest test_proposer.py test_skills.py -v`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/proposer.py cooper-core/test_proposer.py
git commit -m "feat(step-11): proposer drafts candidate skills into inert _drafts"
```

---

### Task 2: Wire drafting into the dispatch pipeline + surface the offer

**Files:**
- Modify: `cooper-core/main.py` (`_execute`, after the `archivist.remember` block)
- Test: `cooper-core/test_proposer.py` (append)

**Interfaces:**
- Consumes: Task 1's `draft_skill`; `review.govern` verdict flow in `main._execute`.
- Produces: dispatch replies gain a one-line draft offer: `\n\n[Proposer] Drafted skill '<name>' from this run — say "promote skill <name>" to review and activate it.`

- [ ] **Step 1: Write the failing test (append to test_proposer.py)**

```python
def test_offer_line_format(tmp_path):
    path = _draft(tmp_path)
    assert proposer.offer_line(path) == (
        '\n\n[Proposer] Drafted skill \'stack-health-check\' from this run — '
        'say "promote skill stack-health-check" to review and activate it.'
    )
    assert proposer.offer_line(None) == ""
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd cooper-core && python3 -m pytest test_proposer.py -v`
Expected: FAIL — `offer_line` missing.

- [ ] **Step 3: Implement**

3a. Append to `proposer.py`:

```python
def offer_line(draft_dir: Optional[Path]) -> str:
    """One-line promotion offer appended to the dispatch reply. '' when no draft."""
    if draft_dir is None:
        return ""
    name = draft_dir.name
    return (
        f"\n\n[Proposer] Drafted skill '{name}' from this run — "
        f'say "promote skill {name}" to review and activate it.'
    )
```

3b. In `main.py`: add `import proposer` beside `import skills`, then in `_execute()` — after the `archivist.remember` try/except and before `return review.govern(raw_output, verdict)` — add:

```python
    draft_offer = ""
    if verdict.verdict == "pass":
        try:
            draft_dir = await proposer.draft_skill(
                tool, message, raw_output,
                base_url=BACKEND_URL, api_key=BACKEND_KEY,
                model=CLASSIFIER_MODEL, backend=BACKEND,
            )
            draft_offer = proposer.offer_line(draft_dir)
        except Exception as exc:
            print(f"  [!!] proposer failed (non-fatal): {exc}")

    return review.govern(raw_output, verdict) + draft_offer
```

(Replace the existing bare `return review.govern(raw_output, verdict)`.)

- [ ] **Step 4: Run the full suite**

Run: `cd cooper-core && python3 -m pytest -v`
Expected: all pass (existing `_execute` tests unaffected because drafting is fail-silent).

- [ ] **Step 5: Commit**

```bash
git add cooper-core/proposer.py cooper-core/main.py cooper-core/test_proposer.py
git commit -m "feat(step-11): dispatch pipeline drafts skills and offers promotion"
```

---

### Task 3: promote_skill tool — approval-gated draft activation

**Files:**
- Modify: `cooper-core/skills.py` (promotion helpers)
- Modify: `cooper-core/executor.py` (new executor_type `skill_promote`)
- Modify: `cooper-core/main.py` (`_handle_dispatch` preview special-case gains `skill_promote`)
- Modify: `Config/general_tool_registry.yaml` AND `Config/private_tool_registry.yaml` (promotion is local-only, both workshops get it)
- Test: `cooper-core/test_skills.py`, `cooper-core/test_executor.py` (append)

**Interfaces:**
- Consumes: Step 10's `compute_content_hash`, `_append_manifest_entry`, `parse_skill_md`; Task 1's draft layout.
- Produces: `skills.parse_promote_request(message: str) -> str` (draft name); `skills.preview_promote(message: str, *, repo_root=None) -> str`; `skills.register_promotion(message: str, *, workshop: str = "open", repo_root=None, manifest_path=None) -> dict` (moves `Skills/_drafts/<name>` → `Skills/learned/<name>`, hashes, registers).

- [ ] **Step 1: Write the failing tests (append to test_skills.py)**

```python
def make_draft(root: Path, name: str = "stack-health-check") -> Path:
    d = root / "Skills" / "_drafts" / name
    d.mkdir(parents=True)
    (d / "SKILL.md").write_text(
        f"---\nname: {name}\ndescription: Drafted procedure.\n---\n\n## Procedure\nDo it.\n",
        encoding="utf-8",
    )
    return d


def test_parse_promote_request():
    assert skills.parse_promote_request("promote skill stack-health-check") == "stack-health-check"
    with pytest.raises(skills.SkillError):
        skills.parse_promote_request("promote something")


def test_promotion_flow(tmp_path):
    make_draft(tmp_path)
    manifest = write_manifest(tmp_path, [])
    preview = skills.preview_promote("promote skill stack-health-check", repo_root=tmp_path)
    assert "Drafted procedure" in preview
    entry = skills.register_promotion(
        "promote skill stack-health-check",
        workshop="open", repo_root=tmp_path, manifest_path=manifest,
    )
    assert entry["id"] == "stack-health-check"
    assert (tmp_path / "Skills" / "learned" / "stack-health-check" / "SKILL.md").exists()
    assert not (tmp_path / "Skills" / "_drafts" / "stack-health-check").exists()
    loaded = skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path)
    assert [s.name for s in loaded] == ["stack-health-check"]


def test_promote_missing_draft_raises(tmp_path):
    with pytest.raises(skills.SkillError):
        skills.preview_promote("promote skill ghost", repo_root=tmp_path)


def test_promote_registered_open_skill_into_private(tmp_path):
    # no draft — the skill is already live in Open; promotion adds a Private entry
    d = make_skill_dir(tmp_path, name="hello-cooper")
    manifest = write_manifest(tmp_path, [approved_entry(tmp_path, d)])
    entry = skills.register_promotion(
        "promote skill hello-cooper",
        workshop="private", repo_root=tmp_path, manifest_path=manifest,
    )
    assert entry["workshop"] == "private"
    # both workshops now load it — the Open entry survived the append
    assert len(skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path)) == 1
    assert len(skills.list_skills("private", manifest_path=manifest, repo_root=tmp_path)) == 1
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd cooper-core && python3 -m pytest test_skills.py -v`
Expected: new tests FAIL with `AttributeError`.

- [ ] **Step 3: Implement**

3a. Append to `skills.py`:

```python
# ── Draft promotion (Step 11; approval-gated via the promote_skill tool) ─────
_PROMOTE_RE = re.compile(r"promote\s+skill\s+([a-z0-9][a-z0-9-]*)", re.IGNORECASE)


def parse_promote_request(message: str) -> str:
    m = _PROMOTE_RE.search(message)
    if not m:
        raise SkillError("could not parse — use: promote skill <name>")
    return m.group(1).lower()


def _draft_dir(name: str, repo_root: Optional[Path] = None) -> Path:
    root = repo_root or _REPO_ROOT
    d = root / "Skills" / "_drafts" / name
    if not (d / "SKILL.md").exists():
        raise SkillError(f"no draft named '{name}' in Skills/_drafts/")
    return d


def preview_promote(
    message: str,
    *,
    repo_root: Optional[Path] = None,
    manifest_path: Optional[Path] = None,
) -> str:
    """SKILL.md text for the approval question — from the draft, or (fallback,
    matching register_promotion) from an already-registered skill being
    promoted into another workshop."""
    name = parse_promote_request(message)
    root = repo_root or _REPO_ROOT
    try:
        d = _draft_dir(name, repo_root)
    except SkillError:
        existing = next(
            (e for e in load_manifest(manifest_path) if str(e.get("id")) == name), None
        )
        if existing is None:
            raise
        d = (root / str(existing["path"])).resolve()
        if not (d / "SKILL.md").exists():
            raise SkillError(f"registered skill '{name}' has no SKILL.md on disk")
    text = (d / "SKILL.md").read_text(encoding="utf-8")
    return text[:_PREVIEW_MAX] + ("\n[... preview truncated]" if len(text) > _PREVIEW_MAX else "")


def register_promotion(
    message: str,
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
    name = parse_promote_request(message)
    root = repo_root or _REPO_ROOT
    try:
        src = _draft_dir(name, repo_root)
    except SkillError:
        existing = next(
            (e for e in load_manifest(manifest_path) if str(e.get("id")) == name), None
        )
        if existing is None:
            raise
        skill_dir = (root / str(existing["path"])).resolve()
        entry = {
            "id": name,
            "path": existing["path"],
            "workshop": workshop,
            "permission_level": int(existing.get("permission_level", 1)),
            "approval_required": bool(existing.get("approval_required", False)),
            "content_hash": compute_content_hash(skill_dir),
        }
        _append_manifest_entry(entry, manifest_path)
        return entry
    final = root / "Skills" / "learned" / name
    final.parent.mkdir(parents=True, exist_ok=True)
    if final.exists():
        shutil.rmtree(final)
    shutil.move(str(src), str(final))
    entry = {
        "id": name,
        "path": str(final.relative_to(root)).replace("\\", "/"),
        "workshop": workshop,
        "permission_level": 1,
        "approval_required": False,
        "content_hash": compute_content_hash(final),
    }
    _append_manifest_entry(entry, manifest_path)
    return entry
```

3b. `executor.py` — add branch + handler (promotion registers for the ACTIVE workshop, purely local, allowed in Private):

```python
    if executor_type == "skill_promote":
        return await _run_skill_promote(message, workshop)
```

```python
async def _run_skill_promote(message: str, workshop: str) -> str:
    loop = asyncio.get_running_loop()

    def _sync() -> str:
        entry = skills.register_promotion(message, workshop=workshop)
        return (
            f"Skill '{entry['id']}' promoted from draft and registered for the "
            f"{entry['workshop']} workshop (hash {entry['content_hash'][:12]}…)."
        )

    try:
        return await loop.run_in_executor(None, _sync)
    except skills.SkillError as exc:
        return f"Workbench: skill promotion failed — {exc}"
```

3c. `main.py` `_handle_dispatch` — extend the preview special-case from Step 10 Task 6:

```python
        if tool.get("executor_type") == "skill_import":
            ...existing...
        elif tool.get("executor_type") == "skill_promote":
            try:
                text = await asyncio.to_thread(skills.preview_promote, message)
                preview = f"\n\nDraft SKILL.md under review:\n---\n{text}\n---"
            except skills.SkillError as exc:
                return f"Skill promotion rejected before approval: {exc}"
```

3d. Registry entries. `Config/general_tool_registry.yaml`:

```yaml
  - id: promote_skill
    name: Promote Skill
    drawer: Skills
    workshop: Open Workshop
    description: Promote a drafted skill from Skills/_drafts into the live registry. Usage — promote skill <name>. Shows the draft SKILL.md for review before approval.
    permission_level: 2
    approval_required: true
    executor_type: skill_promote
    enabled: true
    inputs:
      - skill_name
    outputs:
      - manifest_entry
    notes: Local filesystem only. Drafts are created by the Proposer after successful runs.
```

`Config/private_tool_registry.yaml`: identical entry but `workshop: Private Workshop` and note "Registers the skill for the private workshop."

- [ ] **Step 4: Run the full suite**

Run: `cd cooper-core && python3 -m pytest -v`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/skills.py cooper-core/executor.py cooper-core/main.py Config/general_tool_registry.yaml Config/private_tool_registry.yaml cooper-core/test_skills.py cooper-core/test_executor.py
git commit -m "feat(step-11): promote_skill tool — approval-gated draft activation"
```

---

### Task 4: Activation stats in cooper_memory.db + live verification

**Files:**
- Modify: `cooper-core/archivist.py` (`_SCHEMA` — add table)
- Modify: `cooper-core/skills.py` (`record_activation`, stats in `format_skill_list`)
- Modify: `cooper-core/main.py` (count on injection)
- Test: `cooper-core/test_proposer.py` (append)

**Interfaces:**
- Consumes: `archivist.get_conn`, `archivist._DB_LOCK`, Step 10's injection call sites.
- Produces: table `skillmd_stats(skill_id TEXT PRIMARY KEY, activation_count INTEGER, last_activated TEXT)`; `skills.record_activation(conn, skill_id: str) -> None`; `skills.get_activation_count(conn, skill_id: str) -> int`.

- [ ] **Step 1: Write the failing test (append to test_proposer.py)**

```python
import archivist
import skills as skills_mod


def test_activation_stats_roundtrip(tmp_path):
    conn = archivist.get_conn(tmp_path / "t.db")
    archivist.init_db(conn)
    assert skills_mod.get_activation_count(conn, "hello-cooper") == 0
    skills_mod.record_activation(conn, "hello-cooper")
    skills_mod.record_activation(conn, "hello-cooper")
    assert skills_mod.get_activation_count(conn, "hello-cooper") == 2
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd cooper-core && python3 -m pytest test_proposer.py -v`
Expected: FAIL — no `skillmd_stats` table / missing functions.

- [ ] **Step 3: Implement**

3a. `archivist.py` — append to `_SCHEMA` (before the closing `"""`):

```sql
CREATE TABLE IF NOT EXISTS skillmd_stats (
    skill_id         TEXT PRIMARY KEY,
    activation_count INTEGER NOT NULL DEFAULT 0,
    last_activated   TEXT
);
```

3b. `skills.py` — append (add `import time` to module imports; the lock import stays local to avoid a circular import at module load):

```python
# ── Activation stats (Step 11; stored beside the archivist's tables) ─────────
def record_activation(conn, skill_id: str) -> None:
    """Count one knowledge-skill activation. Non-fatal on any error."""
    from archivist import _DB_LOCK
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    try:
        with _DB_LOCK:
            conn.execute(
                "INSERT INTO skillmd_stats (skill_id, activation_count, last_activated) "
                "VALUES (?, 1, ?) ON CONFLICT(skill_id) DO UPDATE SET "
                "activation_count = activation_count + 1, last_activated = excluded.last_activated",
                (skill_id, now),
            )
            conn.commit()
    except Exception as exc:
        print(f"  [!!] skills.record_activation failed (non-fatal): {exc}")


def get_activation_count(conn, skill_id: str) -> int:
    from archivist import _DB_LOCK
    with _DB_LOCK:
        row = conn.execute(
            "SELECT activation_count FROM skillmd_stats WHERE skill_id = ?", (skill_id,)
        ).fetchone()
    return int(row[0]) if row else 0
```

3c. `main.py` — at both injection sites (Step 10's `_generate` and `_stream_sse` changes), replace the plain `skill_context_for` call pattern with select-then-record so the activation is counted:

```python
    skill_ctx = ""
    matched = skills.select_skill(WORKSHOP, message)
    if matched is not None:
        skill_ctx = skills.format_skill_context(matched)
        await asyncio.to_thread(skills.record_activation, _ARCHIVIST_CONN, matched.id)
```

- [ ] **Step 4: Run the full suite**

Run: `cd cooper-core && python3 -m pytest -v`
Expected: all pass.

- [ ] **Step 5: Live verification (Definition of Done)**

```bash
# restart server, then:
# 1. Trigger a successful L0/L1 dispatch (e.g. status summary) → expect
#    "[Proposer] Drafted skill '<name>' ..." appended to the reply.
curl -s -X POST http://localhost:8000/chat -H "Authorization: Bearer cooper-local" \
  -H "Content-Type: application/json" -d '{"message": "run a status summary"}'

# 2. Promote it:
curl -s -X POST http://localhost:8000/chat -H "Authorization: Bearer cooper-local" \
  -H "Content-Type: application/json" -d '{"message": "promote skill <name>"}'
# expect: Halt + draft SKILL.md preview
curl -s -X POST http://localhost:8000/chat -H "Authorization: Bearer cooper-local" \
  -H "Content-Type: application/json" -d '{"message": "approve"}'
# expect: promoted + registered; GET /skills shows it "ok"

# 3. Use it, then confirm the count incremented:
python3 -c "
import sqlite3
conn = sqlite3.connect('cooper-core/cooper_memory.db')
print(conn.execute('SELECT * FROM skillmd_stats').fetchall())
"
```

Final browser confirmation: in Open WebUI, run the dispatch and see the Proposer offer line render.

- [ ] **Step 6: Commit**

```bash
git add cooper-core/archivist.py cooper-core/skills.py cooper-core/main.py cooper-core/test_proposer.py
git commit -m "feat(step-11): skill activation stats in cooper_memory.db"
```
