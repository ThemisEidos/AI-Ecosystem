# Step 15e (narrow) — Planner: parameterized CSV-monitor job drafting — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `POST /jobs/draft` — a big-brain (planner) alias drafts a new job envelope from an owner's natural-language goal, but *only* in the exact shape 14b's `run_job` already knows how to execute (a parameterized CSV-monitor job: `csv_next_rows` → `url_verify` → `csv_line_edit`), then automatically runs it through 15d's planning-time council critique before returning to the owner for hand-approval.

**Architecture:** A new `cooper-core/planner.py` module resolves the owner's goal into the *few* fields a CSV-monitor job actually varies by (id, which CSV to monitor, quota, schedule hint) via one JSON-schema-constrained LLM call on the `planner` role's alias, validates every field in code (path containment, file existence, CSV shape, quota ceilings, id-collision), and persists the result into `Config/jobs_registry.yaml` with `approved: false` — never touching `steps`, `permission_level`, or `workshop`, which stay fixed in code so the LLM can never draft a new tool-calling surface. `main.py` wires `POST /jobs/draft` to call `planner.draft_envelope()` and then the same council-critique logic `POST /jobs/critique/{job_id}` already runs (factored into a shared helper), so the response the owner sees is one council-reviewed envelope ready for the existing hand-approval → `POST /jobs/run/{job_id}` flow — completely unmodified.

**Tech Stack:** Python 3 / FastAPI / Pydantic (existing `cooper-core/` stack — no new dependencies).

**Spec:** `Docs/superpowers/specs/2026-08-18-step-15-max-metrics-design.md` §3's 15e row (line 122) and target architecture diagram (§2). Narrow-scope decision: `PROGRESS.md`'s "Blocked / needs owner input" section, "15e scope — DECIDED 2026-09-01: (a) narrow" entry, and `Obsidian Vault/brain/North Star.md`'s Current Position.

## Global Constraints

- **No slice may spend M4 (governance) or M7 (audit) to buy another metric** (spec §1). This plan must never weaken `verify_job`'s hash-then-approve gate or skip the evidence/critique-note record.
- **G1 (DECIDED 2026-08-23): no Private plan-handoff.** A drafted envelope's `workshop` field is always the process's own `WORKSHOP` constant, never LLM-chosen — satisfied structurally since one `cooper-core` process serves exactly one workshop.
- **G2 (DECIDED 2026-08-23): planner alias starts as `gpt-4o-mini` on Open** (the `"openai"` LiteLLM alias) / `COOPER-Private` on Private — already mapped in `Scripts/PDA_ModelRouting.json`'s `roles.planner`; this plan is that role's first call site.
- **Narrow-scope decision (owner, 2026-09-01):** the planner drafts *only* jobs of the existing CSV-monitor shape. `steps`, `permission_level`, and `workshop` are fixed in code, never read from the LLM's output. No new autonomous tool-calling surface, no generic step dispatcher.
- **Rejected and staying rejected (spec §7):** no mid-run council checkpoints, no runtime LLM-picks-the-LLM routing. This plan adds none.
- **Repo rule:** no new declarative policy files — `Scripts/PDA_ModelRouting.json` already has the `planner` role; this plan only updates its `notes` field to record the new call site.
- **Every behavior change lands with tests in the sibling `test_*.py`; full suite (`cd cooper-core && .venv/bin/python -m pytest`) must stay green.**

---

## File Structure

| File | Responsibility |
|---|---|
| `cooper-core/jobs.py` (existing, +1 function) | Add `append_job_entry()` — the registry writer job drafting needs; mirrors `skills.py`'s `_append_manifest_entry` dedupe-by-id-then-append pattern. Everything else in `jobs.py` (including `run_job`) is untouched. |
| `cooper-core/planner.py` (new) | Narrow-scope envelope drafting: resolves a goal to CSV-monitor-job fields via one LLM call, validates every field in code, persists via `jobs.append_job_entry`. Owns the one place `steps`/`permission_level` are hardcoded. |
| `cooper-core/main.py` (existing, +1 endpoint) | `PLANNER_MODEL` constant (mirrors `REVIEWER_MODEL`/`DRAFTER_MODEL`), `POST /jobs/draft` endpoint, `_critique_and_note()` helper factored out of the existing `critique_job` endpoint so both share one code path. |
| `Scripts/PDA_ModelRouting.json` (existing, doc-only) | `roles.planner.notes` updated to record the call site now exists. |
| `cooper-core/test_jobs.py` / `cooper-core/test_planner.py` (new) / `cooper-core/test_main_jobs.py` | Tests for each of the above, following this repo's existing `test_<module>.py` / `test_main_<feature>.py` split. |

**Interfaces every task below relies on:**
- `jobs.append_job_entry(entry: dict, registry_path: Optional[Path] = None) -> None` (Task 1)
- `planner.draft_envelope(goal: str, *, workshop: str, base_url: str, api_key: str, model: str, backend: str, repo_root: Optional[Path] = None, registry_path: Optional[Path] = None, extract_fn=None) -> dict` (Task 2) — returns the persisted job entry dict (with `envelope_hash`), or raises `planner.PlannerError`.
- `planner.PlannerError(Exception)` — the one exception type `main.py` catches to turn a bad goal into a 422, never a 500.

---

### Task 1: Registry writer — `jobs.append_job_entry`

**Files:**
- Modify: `cooper-core/jobs.py` (add function after `get_job`, i.e. after line 83, before `compute_envelope_hash`)
- Test: `cooper-core/test_jobs.py` (append after the existing `test_get_job_returns_none_for_unknown_id`, i.e. after line 76)

**Interfaces:**
- Produces: `append_job_entry(entry: dict, registry_path: Optional[Path] = None) -> None`. Writes/overwrites `Config/jobs_registry.yaml` (or `registry_path` if given). Dedupes by `id`: a new entry with an id already present in the registry **replaces** that entry.

- [ ] **Step 1: Write the failing tests**

Add to `cooper-core/test_jobs.py` (after line 76, `test_get_job_returns_none_for_unknown_id`):

```python
def test_append_job_entry_writes_new_entry_to_empty_registry(tmp_path):
    registry_path = tmp_path / "jobs_registry.yaml"
    entry = {**MINIMAL_JOB, "id": "new-job"}
    jobs.append_job_entry(entry, registry_path=registry_path)

    reg = jobs.load_registry(registry_path)
    assert jobs.get_job("new-job", reg) == entry


def test_append_job_entry_preserves_other_existing_entries(tmp_path):
    registry_path = tmp_path / "jobs_registry.yaml"
    registry_path.write_text(
        yaml.safe_dump({"jobs": [{**MINIMAL_JOB, "id": "existing-job"}]}), encoding="utf-8"
    )
    jobs.append_job_entry({**MINIMAL_JOB, "id": "new-job"}, registry_path=registry_path)

    reg = jobs.load_registry(registry_path)
    assert jobs.get_job("existing-job", reg) is not None
    assert jobs.get_job("new-job", reg) is not None
    assert len(reg["jobs"]) == 2


def test_append_job_entry_replaces_existing_entry_with_same_id(tmp_path):
    registry_path = tmp_path / "jobs_registry.yaml"
    registry_path.write_text(
        yaml.safe_dump({"jobs": [{**MINIMAL_JOB, "id": "dup-job", "schedule_hint": "old"}]}),
        encoding="utf-8",
    )
    jobs.append_job_entry({**MINIMAL_JOB, "id": "dup-job", "schedule_hint": "new"}, registry_path=registry_path)

    reg = jobs.load_registry(registry_path)
    assert len(reg["jobs"]) == 1
    assert jobs.get_job("dup-job", reg)["schedule_hint"] == "new"
```

Add `import yaml` to `cooper-core/test_jobs.py`'s import block (it currently has `asyncio`, `json`, `pathlib.Path`, `pytest`, `archivist`, `council`, `evidence`, `executor`, `jobs` — `yaml` is new).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && .venv/bin/python -m pytest test_jobs.py -k append_job_entry -v`
Expected: FAIL with `AttributeError: module 'jobs' has no attribute 'append_job_entry'`

- [ ] **Step 3: Implement `append_job_entry`**

In `cooper-core/jobs.py`, insert immediately after `get_job` (after line 83, before `compute_envelope_hash` at line 86):

```python
def append_job_entry(entry: dict, registry_path: Optional[Path] = None) -> None:
    """Persist one job envelope into Config/jobs_registry.yaml, replacing any
    existing entry with the same id. Same dedupe-by-id-then-append-then-
    safe_dump pattern as skills.py's _append_manifest_entry (Step 11) — the
    only registry writer jobs.py has today; everything else (load_registry,
    get_job) only reads."""
    p = registry_path or _REGISTRY_PATH
    data = {}
    if p.exists():
        data = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    entries = [e for e in (data.get("jobs") or []) if e.get("id") != entry["id"]]
    entries.append(entry)
    data["jobs"] = entries
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && .venv/bin/python -m pytest test_jobs.py -v`
Expected: PASS — all existing `test_jobs.py` tests plus the 3 new ones.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/jobs.py cooper-core/test_jobs.py
git commit -m "feat(jobs): add append_job_entry registry writer (15e narrow, Task 1)"
```

---

### Task 2: `cooper-core/planner.py` — narrow-scope envelope drafting

**Files:**
- Create: `cooper-core/planner.py`
- Create: `cooper-core/test_planner.py`

**Interfaces:**
- Consumes: `jobs.append_job_entry(entry, registry_path=None)`, `jobs.load_registry(path=None)`, `jobs.get_job(job_id, registry=None)`, `jobs.compute_envelope_hash(job_entry)` (all Task 1 / existing `jobs.py`); `decision._ollama_complete` / `decision._openai_complete` (existing, same signatures proposer.py and council.py already use).
- Produces: `planner.draft_envelope(goal, *, workshop, base_url, api_key, model, backend, repo_root=None, registry_path=None, extract_fn=None) -> dict`, `planner.PlannerError(Exception)`, `planner.slugify(name: str) -> str`.

- [ ] **Step 1: Write the failing tests**

Create `cooper-core/test_planner.py`:

```python
"""Tests for narrow-scope job drafting (Step 15e, narrow — owner decision 2026-09-01)."""
import asyncio

import pytest
import yaml

import jobs
import planner


FAKE_DRAFT = {
    "id": "newsletter-links",
    "csv_path": "State/LinkAudit/links.csv",
    "rows_per_run": 10,
    "fetches_per_run": 30,
    "schedule_hint": "daily 03:00",
}


def fake_extract(**overrides):
    async def _inner(*args, **kwargs):
        return {**FAKE_DRAFT, **overrides}
    return _inner


def run(coro):
    return asyncio.run(coro)


def _write_csv(path, header="url,last_checked,status,notes\n"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(header + "https://a.example,,,\n", encoding="utf-8")


def _draft(tmp_path, *, extract=None, goal="watch the newsletter links CSV"):
    registry_path = tmp_path / "Config" / "jobs_registry.yaml"
    registry_path.parent.mkdir(parents=True, exist_ok=True)
    return run(planner.draft_envelope(
        goal, workshop="open",
        base_url="", api_key="", model="", backend="ollama",
        repo_root=tmp_path, registry_path=registry_path,
        extract_fn=extract or fake_extract(),
    ))


def test_draft_envelope_persists_fixed_csv_monitor_shape(tmp_path):
    _write_csv(tmp_path / "State" / "LinkAudit" / "links.csv")
    entry = _draft(tmp_path)

    assert entry["id"] == "newsletter-links"
    assert entry["workshop"] == "open"
    assert entry["steps"] == ["csv_next_rows", "url_verify", "csv_line_edit"]
    assert entry["permission_level"] == 3
    assert entry["approved"] is False
    assert entry["read_scope"] == ["State/LinkAudit/links.csv"]
    assert entry["write_scope"] == ["State/LinkAudit/links.csv"]
    assert entry["envelope_hash"] == jobs.compute_envelope_hash(entry)

    registry = jobs.load_registry(tmp_path / "Config" / "jobs_registry.yaml")
    assert jobs.get_job("newsletter-links", registry) == entry


def test_draft_envelope_ignores_llm_chosen_steps_and_permission_level(tmp_path):
    """The narrow-scope invariant: even if the LLM output carried extra keys
    trying to widen the job shape, draft_envelope must never read them —
    steps/permission_level/workshop are fixed in code, not in the schema."""
    _write_csv(tmp_path / "State" / "LinkAudit" / "links.csv")
    hostile = fake_extract(steps=["shell_exec"], permission_level=6, workshop="private")
    entry = _draft(tmp_path, extract=hostile)

    assert entry["steps"] == ["csv_next_rows", "url_verify", "csv_line_edit"]
    assert entry["permission_level"] == 3
    assert entry["workshop"] == "open"


def test_draft_envelope_rejects_empty_csv_path(tmp_path):
    with pytest.raises(planner.PlannerError, match="did not name"):
        _draft(tmp_path, extract=fake_extract(csv_path=""))


def test_draft_envelope_rejects_path_outside_repo(tmp_path):
    with pytest.raises(planner.PlannerError, match="not a safe repo-relative"):
        _draft(tmp_path, extract=fake_extract(csv_path="../outside.csv"))


def test_draft_envelope_rejects_nonexistent_csv(tmp_path):
    with pytest.raises(planner.PlannerError, match="does not exist"):
        _draft(tmp_path, extract=fake_extract(csv_path="State/LinkAudit/missing.csv"))


def test_draft_envelope_rejects_csv_without_url_column(tmp_path):
    csv_path = tmp_path / "State" / "LinkAudit" / "notes.csv"
    _write_csv(csv_path, header="topic,body\n")
    with pytest.raises(planner.PlannerError, match="no 'url' column"):
        _draft(tmp_path, extract=fake_extract(csv_path="State/LinkAudit/notes.csv"))


def test_draft_envelope_rejects_duplicate_job_id(tmp_path):
    _write_csv(tmp_path / "State" / "LinkAudit" / "links.csv")
    registry_path = tmp_path / "Config" / "jobs_registry.yaml"
    registry_path.parent.mkdir(parents=True, exist_ok=True)
    registry_path.write_text(
        yaml.safe_dump({"jobs": [{"id": "newsletter-links", "workshop": "open"}]}), encoding="utf-8"
    )
    with pytest.raises(planner.PlannerError, match="already exists"):
        _draft(tmp_path)

    # Must not have touched the existing entry.
    reg = jobs.load_registry(registry_path)
    assert len(reg["jobs"]) == 1


def test_draft_envelope_clamps_quota_to_max(tmp_path):
    _write_csv(tmp_path / "State" / "LinkAudit" / "links.csv")
    entry = _draft(tmp_path, extract=fake_extract(rows_per_run=99999, fetches_per_run=99999))
    assert entry["quota"]["rows_per_run"] == planner._MAX_ROWS_PER_RUN
    assert entry["quota"]["fetches_per_run"] == planner._MAX_FETCHES_PER_RUN


def test_draft_envelope_defaults_quota_on_bad_values(tmp_path):
    _write_csv(tmp_path / "State" / "LinkAudit" / "links.csv")
    entry = _draft(tmp_path, extract=fake_extract(rows_per_run="not-a-number", fetches_per_run=None))
    assert entry["quota"]["rows_per_run"] == 10
    assert entry["quota"]["fetches_per_run"] >= entry["quota"]["rows_per_run"]


def test_slugify_matches_proposer_convention():
    assert planner.slugify("Newsletter Links!!") == "newsletter-links"
    assert planner.slugify("") == "unnamed-job"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && .venv/bin/python -m pytest test_planner.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'planner'` (the file doesn't exist yet — note this is a *different* module name collision-free from the existing `proposer.py`).

- [ ] **Step 3: Implement `cooper-core/planner.py`**

```python
"""
COOPER Planner — narrow-scope job drafting (Step 15e, narrow).

Owner scope decision 2026-09-01 (PROGRESS.md, "15e scope"): the planner only
drafts new jobs of the exact shape run_job (14b, jobs.py) already knows how
to execute — a parameterized CSV-monitor job (csv_next_rows -> url_verify ->
csv_line_edit). No new autonomous tool-calling surface: `steps`,
`permission_level`, and `workshop` are fixed by this module and never read
from the LLM's output. The planner LLM only proposes the handful of fields a
CSV-monitor job actually varies by — id, which CSV file to monitor, quota,
and a schedule hint — and every one of those is validated in code before
anything is written to jobs_registry.yaml.

Flow: draft (this module) -> council critique (council.py, 15d) -> owner
hand-approval (flip approved: true in jobs_registry.yaml, same as 14b/15d
today) -> existing run_job (jobs.py, completely unmodified) -> 14b hash
mechanic. The planner alias is called exactly once, here, and never again
during a job's execution — satisfying the spec's 15e DoD ("big-brain alias
is called zero times during execution").

Spec: Docs/superpowers/specs/2026-08-18-step-15-max-metrics-design.md §3's
15e row.
"""
import csv
import json
import re
from pathlib import Path
from typing import Optional

from decision import _ollama_complete, _openai_complete
import jobs

_REPO_ROOT = Path(__file__).resolve().parent.parent

# The one job shape this planner may ever draft — fixed here, never read from
# the LLM's output. This is the narrow-scope security boundary itself.
_LINK_CHECKER_STEPS = ["csv_next_rows", "url_verify", "csv_line_edit"]
_FIXED_PERMISSION_LEVEL = 3  # matches the existing link-checker job

_MAX_ROWS_PER_RUN = 50
_MAX_FETCHES_PER_RUN = 100

_SLUG_RE = re.compile(r"[^a-z0-9]+")

_DRAFT_SYSTEM = """\
You are COOPER's Planner. The owner described a goal for an unattended job \
that periodically checks a CSV file of URLs for reachability and content \
changes -- the only job shape this planner is allowed to draft. From the \
goal, propose: a short id slug, the repo-relative path to the CSV file to \
monitor (the owner's goal should name or clearly imply it), how many rows \
to check per run, how many URL fetches to allow per run, and a plain \
schedule hint (e.g. "daily 03:00"). If the goal does not name or clearly \
imply an existing CSV file to monitor, set "csv_path" to "".

Output JSON only -- no other text.
{"id":"<lowercase-hyphen slug, 2-4 words>","csv_path":"<repo-relative path ending in .csv, or empty>","rows_per_run":<int>,"fetches_per_run":<int>,"schedule_hint":"<short phrase>"}\
"""

_DRAFT_SCHEMA = {
    "type": "object",
    "properties": {
        "id":              {"type": "string"},
        "csv_path":        {"type": "string"},
        "rows_per_run":    {"type": "integer"},
        "fetches_per_run": {"type": "integer"},
        "schedule_hint":   {"type": "string"},
    },
    "required": ["id", "csv_path", "rows_per_run", "fetches_per_run", "schedule_hint"],
}


class PlannerError(Exception):
    """A goal that cannot be drafted into the one supported job shape, or a
    drafted field that fails validation. Never partially written — a raised
    PlannerError means jobs_registry.yaml was not touched."""


def slugify(name: str) -> str:
    slug = _SLUG_RE.sub("-", name.lower()).strip("-")
    return slug or "unnamed-job"


async def _extract_fields(
    goal: str, *, base_url: str, api_key: str, model: str, backend: str,
) -> dict:
    messages = [
        {"role": "system", "content": _DRAFT_SYSTEM},
        {"role": "user", "content": f"Goal: {goal}"},
    ]
    if backend == "openai":
        raw = await _openai_complete(
            base_url, api_key, model, messages, temperature=0,
            response_format={"type": "json_schema", "json_schema": {
                "name": "job_draft", "strict": True,
                "schema": {**_DRAFT_SCHEMA, "additionalProperties": False},
            }},
        )
    else:
        raw = await _ollama_complete(
            base_url, model, messages, options={"temperature": 0}, fmt=_DRAFT_SCHEMA,
        )
    return json.loads(raw)


def _validate_csv_path(csv_path: str, *, repo_root: Path) -> str:
    """Reject anything but an existing, in-repo, header-bearing CSV with a
    'url' column -- the exact shape csv_next_rows (jobs.py) already reads.
    Returns the validated repo-relative path. Same .resolve()+relative_to()
    containment technique executor.py uses for every write-scope check."""
    if not csv_path:
        raise PlannerError("goal did not name an existing CSV file to monitor")
    rel = csv_path.strip().replace("\\", "/").lstrip("/")
    if not rel.endswith(".csv") or ".." in Path(rel).parts:
        raise PlannerError(f"'{csv_path}' is not a safe repo-relative .csv path")
    full = (repo_root / rel).resolve()
    try:
        full.relative_to(repo_root.resolve())
    except ValueError:
        raise PlannerError(f"'{csv_path}' resolves outside the repo")
    if not full.is_file():
        raise PlannerError(f"'{rel}' does not exist — create the CSV before drafting a job for it")
    try:
        with open(full, newline="", encoding="utf-8") as f:
            fieldnames = csv.DictReader(f).fieldnames or []
    except Exception as exc:
        raise PlannerError(f"'{rel}' is not readable as CSV: {exc}")
    if "url" not in fieldnames:
        raise PlannerError(f"'{rel}' has no 'url' column — not a link-checker-shaped CSV")
    return rel


def _clamp(value, *, minimum: int, maximum: int, default: int) -> int:
    try:
        value = int(value)
    except (TypeError, ValueError):
        return default
    return max(minimum, min(maximum, value))


async def draft_envelope(
    goal: str,
    *,
    workshop: str,
    base_url: str,
    api_key: str,
    model: str,
    backend: str,
    repo_root: Optional[Path] = None,
    registry_path: Optional[Path] = None,
    extract_fn=None,
) -> dict:
    """Draft one CSV-monitor job envelope from a natural-language goal and
    persist it into jobs_registry.yaml as approved: false. Raises
    PlannerError (never writes anything) if the goal can't be drafted into
    the one supported job shape, or any field fails validation, or the
    drafted id collides with an already-registered job."""
    root = repo_root or _REPO_ROOT
    extract_fn = extract_fn or _extract_fields
    draft = await extract_fn(goal, base_url=base_url, api_key=api_key, model=model, backend=backend)

    job_id = slugify(str(draft.get("id", "")))
    existing = jobs.load_registry(registry_path)
    if jobs.get_job(job_id, existing) is not None:
        raise PlannerError(
            f"job id '{job_id}' already exists in the registry — rephrase the goal to draft a distinct job"
        )

    csv_path = _validate_csv_path(str(draft.get("csv_path", "")), repo_root=root)
    rows_per_run = _clamp(draft.get("rows_per_run"), minimum=1, maximum=_MAX_ROWS_PER_RUN, default=10)
    fetches_per_run = _clamp(
        draft.get("fetches_per_run"), minimum=rows_per_run, maximum=_MAX_FETCHES_PER_RUN,
        default=max(rows_per_run, 30),
    )
    schedule_hint = str(draft.get("schedule_hint", "")).strip() or "manual"

    job_entry = {
        "id": job_id,
        "workshop": workshop,                       # process-owned (G1), never LLM-chosen
        "schedule_hint": schedule_hint,
        "steps": list(_LINK_CHECKER_STEPS),          # fixed shape, never LLM-chosen
        "read_scope": [csv_path],
        "write_scope": [csv_path],
        "quota": {"rows_per_run": rows_per_run, "fetches_per_run": fetches_per_run},
        "permission_level": _FIXED_PERMISSION_LEVEL,  # fixed, never LLM-chosen
        "approved": False,
    }
    job_entry["envelope_hash"] = jobs.compute_envelope_hash(job_entry)

    jobs.append_job_entry(job_entry, registry_path=registry_path)
    return job_entry
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && .venv/bin/python -m pytest test_planner.py -v`
Expected: PASS — all 10 tests.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/planner.py cooper-core/test_planner.py
git commit -m "feat(planner): narrow-scope CSV-monitor job drafting (15e narrow, Task 2)"
```

---

### Task 3: Wire `POST /jobs/draft` into `main.py`

**Files:**
- Modify: `cooper-core/main.py` (import, `PLANNER_MODEL` constant, startup print, `JobDraftRequest` model, `_critique_and_note` helper + refactor `critique_job`, new `draft_job` endpoint)
- Modify: `Scripts/PDA_ModelRouting.json` (`roles.planner.notes` — doc-only)
- Test: `cooper-core/test_main_jobs.py`

**Interfaces:**
- Consumes: `planner.draft_envelope(...)` / `planner.PlannerError` (Task 2), `council.critique_envelope`, `council.verdicts_to_dicts`, `council.has_objection`, `jobs.compute_envelope_hash`, `jobs.write_critique_note` (all existing).
- Produces: `POST /jobs/draft` — request `{"goal": str}` → response `{"job_entry": {...}, "job_id": str, "objection": bool, "verdicts": [...], "note_path": str, "envelope_hash": str}`.

- [ ] **Step 1: Write the failing tests**

Append to `cooper-core/test_main_jobs.py` (after `test_critique_endpoint_404s_for_unknown_job`, i.e. after line 119):

```python
def test_post_jobs_draft_returns_envelope_and_critique(monkeypatch, tmp_path):
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main, "_ALLOW_ANON", True)
    monkeypatch.setattr(main.jobs, "_DIGEST_DIR", tmp_path / "inbox")

    drafted_entry = {
        "id": "newsletter-links", "workshop": "open", "schedule_hint": "daily 03:00",
        "steps": ["csv_next_rows", "url_verify", "csv_line_edit"],
        "read_scope": ["State/LinkAudit/links.csv"], "write_scope": ["State/LinkAudit/links.csv"],
        "quota": {"rows_per_run": 10, "fetches_per_run": 30},
        "permission_level": 3, "approved": False,
    }
    drafted_entry["envelope_hash"] = main.jobs.compute_envelope_hash(drafted_entry)

    async def fake_draft_envelope(goal, **kw):
        assert goal == "watch the newsletter links CSV"
        assert kw["model"] == main.PLANNER_MODEL
        return drafted_entry

    async def fake_critique_envelope(job_entry, workshop, **kw):
        assert job_entry == drafted_entry
        return [main.council.CouncilVerdict(member="openai", verdict="pass", reason="looks proportionate")]

    monkeypatch.setattr(main.planner, "draft_envelope", fake_draft_envelope)
    monkeypatch.setattr(main.council, "critique_envelope", fake_critique_envelope)

    with TestClient(main.app) as client:
        resp = client.post("/jobs/draft", json={"goal": "watch the newsletter links CSV"})

    assert resp.status_code == 200
    body = resp.json()
    assert body["job_entry"] == drafted_entry
    assert body["job_id"] == "newsletter-links"
    assert body["objection"] is False
    assert len(body["verdicts"]) == 1
    assert body["envelope_hash"] == drafted_entry["envelope_hash"]
    assert Path(body["note_path"]).exists()


def test_post_jobs_draft_422s_on_planner_error(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main, "_ALLOW_ANON", True)

    async def boom(goal, **kw):
        raise main.planner.PlannerError("goal did not name an existing CSV file to monitor")

    monkeypatch.setattr(main.planner, "draft_envelope", boom)

    with TestClient(main.app) as client:
        resp = client.post("/jobs/draft", json={"goal": "do something vague"})

    assert resp.status_code == 422
    assert "did not name" in resp.json()["detail"]


def test_post_jobs_draft_requires_auth(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", {"secret-key"})
    monkeypatch.setattr(main, "_ALLOW_ANON", False)

    with TestClient(main.app) as client:
        resp = client.post("/jobs/draft", json={"goal": "watch a CSV"})

    assert resp.status_code == 401


def test_post_jobs_draft_rejects_empty_goal(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main, "_ALLOW_ANON", True)

    with TestClient(main.app) as client:
        resp = client.post("/jobs/draft", json={"goal": ""})

    assert resp.status_code == 422
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && .venv/bin/python -m pytest test_main_jobs.py -k draft -v`
Expected: FAIL — `404 Not Found` for the new endpoint (route doesn't exist yet), and `AttributeError: module 'main' has no attribute 'planner'`.

- [ ] **Step 3: Implement the `main.py` wiring**

3a. Add `import planner` in the import block, right after `import proposer` (main.py:~40, alongside the other `import skills` / `import jobs` / `import council` lines already there):

```python
import proposer
import planner
import skills
```

3b. Add `PLANNER_MODEL` next to the other three role constants (main.py:75-78):

```python
COOPER_MODEL    = os.environ.get("COOPER_MODEL", model_routing.model_for("brain", WORKSHOP))
REVIEWER_MODEL  = model_routing.model_for("reviewer", WORKSHOP)
DRAFTER_MODEL   = model_routing.model_for("drafter", WORKSHOP)
ARCHIVIST_MODEL = model_routing.model_for("archivist", WORKSHOP)
PLANNER_MODEL   = model_routing.model_for("planner", WORKSHOP)
```

3c. Add it to the startup print block and the Ollama-model-presence check set (main.py:407-410, 418):

```python
    print(f"  model    : {COOPER_MODEL}")
    print(f"  reviewer : {REVIEWER_MODEL}")
    print(f"  drafter  : {DRAFTER_MODEL}")
    print(f"  archivist: {ARCHIVIST_MODEL}")
    print(f"  planner  : {PLANNER_MODEL}")
```

and

```python
                for name in {COOPER_MODEL, REVIEWER_MODEL, DRAFTER_MODEL, ARCHIVIST_MODEL, PLANNER_MODEL}:
```

3d. Replace the existing `critique_job` endpoint (main.py:550-568) with a shared helper plus both endpoints calling it:

```python
async def _critique_and_note(job_id: str, job_entry: dict) -> dict:
    verdicts = await council.critique_envelope(
        job_entry, WORKSHOP,
        base_url=BACKEND_URL, api_key=BACKEND_KEY, backend=BACKEND,
    )
    verdict_dicts = council.verdicts_to_dicts(verdicts)
    envelope_hash = jobs.compute_envelope_hash(job_entry)
    note_path = jobs.write_critique_note(job_id, verdict_dicts, envelope_hash)
    return {
        "job_id": job_id,
        "objection": council.has_objection(verdicts),
        "verdicts": verdict_dicts,
        "note_path": str(note_path),
        "envelope_hash": envelope_hash,
    }


@app.post("/jobs/critique/{job_id}", dependencies=[Depends(_require_auth)])
async def critique_job(job_id: str):
    job_entry = jobs.get_job(job_id)
    if job_entry is None:
        raise HTTPException(status_code=404, detail=f"unknown job id '{job_id}'")
    return await _critique_and_note(job_id, job_entry)


class JobDraftRequest(BaseModel):
    goal: str = Field(..., min_length=1, max_length=2000)


@app.post("/jobs/draft", dependencies=[Depends(_require_auth)])
async def draft_job(body: JobDraftRequest):
    try:
        job_entry = await planner.draft_envelope(
            body.goal, workshop=WORKSHOP,
            base_url=BACKEND_URL, api_key=BACKEND_KEY,
            model=PLANNER_MODEL, backend=BACKEND,
        )
    except planner.PlannerError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    critique = await _critique_and_note(job_entry["id"], job_entry)
    return {"job_entry": job_entry, **critique}
```

3e. Update `Scripts/PDA_ModelRouting.json`'s `roles.planner.notes` field:

```json
    "planner": {
      "private": "COOPER-Private",
      "open": "openai",
      "notes": "Call site: planner.draft_envelope(), invoked once per POST /jobs/draft (Step 15e, narrow scope — 2026-09-01). Never called during job execution (run_job, jobs.py, is unmodified)."
    },
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && .venv/bin/python -m pytest -q`
Expected: PASS — full suite green (was 343 before this task; +3 from Task 1, +10 from Task 2, +4 from this task).

- [ ] **Step 5: Commit**

```bash
git add cooper-core/main.py cooper-core/test_main_jobs.py Scripts/PDA_ModelRouting.json
git commit -m "feat(main): wire POST /jobs/draft — planner-executor narrow scope (15e narrow, Task 3)"
```

---

### Task 4: Live verification against the real running Open stack

Not a code task — this is the live-proof step this repo requires before any "done" claim (CLAUDE.md's Discipline rule + Operating mindset: "ground every claim in the running system"). Matches the process 14b/15d used (PROGRESS.md's 2026-08-30/2026-08-31 entries).

- [ ] **Step 1: Rebuild the Open stack's `cooper-core` image with this branch's code**

```bash
docker compose -f PDA-Runtime/docker-compose.yml up -d --build cooper-core
curl -s http://localhost:8001/health
```
Expected: `{"status":"ok","workshop":"open",...}`.

- [ ] **Step 2: Create a throwaway test CSV and confirm `/jobs/draft` refuses a goal naming a nonexistent one**

```bash
KEY=$(grep '^COOPER_API_KEYS=' PDA-Runtime/.env | cut -d= -f2)
curl -s -X POST http://localhost:8001/jobs/draft \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"goal":"monitor a CSV of links that does not exist yet"}'
```
Expected: HTTP 422, `detail` mentions the goal not naming an existing CSV (exact wording depends on what the live planner alias returns for `csv_path` — confirm the response is a 422 refusal, not a 500 or a silently-written registry entry).

- [ ] **Step 3: Create a real throwaway CSV and draft a real job for it**

```bash
mkdir -p State/LinkAudit
printf 'url,last_checked,status,notes\nhttps://example.com,,,\n' > State/LinkAudit/test-15e-links.csv

curl -s -X POST http://localhost:8001/jobs/draft \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"goal":"check the links in State/LinkAudit/test-15e-links.csv daily and flag broken ones"}'
```
Expected: HTTP 200. Response's `job_entry.steps == ["csv_next_rows","url_verify","csv_line_edit"]`, `job_entry.permission_level == 3`, `job_entry.approved == false`, `job_entry.workshop == "open"`. `verdicts` is a non-empty array from the real Open council roster (`openai`/`claude`/`gemini`). `note_path` points at a real file under `Obsidian Vault/00_Inbox/`.

- [ ] **Step 4: Confirm the envelope actually landed in the registry, hash-pinned**

```bash
grep -A 12 "id: " Config/jobs_registry.yaml | tail -15
cat "Obsidian Vault/00_Inbox/COOPER-Job-Critique-"*.md
```
Confirm the new entry is present with `approved: false` and an `envelope_hash` that matches the one in the API response, and the critique note's envelope hash matches too.

- [ ] **Step 5: Confirm the planner alias was called exactly once (DoD: "big-brain alias is called zero times during execution")**

```bash
docker compose -f PDA-Runtime/docker-compose.yml logs litellm --tail 100 | grep -i "openai\|planner"
```
This step only confirms the draft call happened. There is no `run_job` call in this test (that's already covered by 14b/15d's own live verification and is unchanged by this plan) — the point is to confirm no *new* LLM call site was introduced inside execution, which is true by construction (Task 2's `draft_envelope` is the only caller of `PLANNER_MODEL`, and it's never imported by `jobs.run_job`). Note this in the session's PROGRESS.md entry as "confirmed by code inspection, not a separate live run_job trace" rather than overclaiming a log-based proof this step doesn't actually produce.

- [ ] **Step 6: Full suite green**

```bash
cd cooper-core && .venv/bin/python -m pytest -q
```
Expected: all tests pass, no regressions.

- [ ] **Step 7: Revert every temporary change, confirm clean**

```bash
cd /home/zb6/Documents/Projects/01_AI_Ecosystem
git diff Config/jobs_registry.yaml   # review the drafted entry
git checkout -- Config/jobs_registry.yaml   # revert the test draft
rm State/LinkAudit/test-15e-links.csv
rm "Obsidian Vault/00_Inbox/COOPER-Job-Critique-"*.md   # the throwaway critique note(s) from Steps 2-3
git status   # confirm clean — no leftover test artifacts
```

- [ ] **Step 8: Update `PROGRESS.md` and `Obsidian Vault/brain/North Star.md`**

Following this repo's convention (14b/15d entries): one dated entry in `PROGRESS.md` under 2026-09-01 (or the actual ship date) summarizing what shipped, the live-verification commands + real output from Steps 2-6 above, and any findings; update North Star's Current Position to point at 15e narrow shipped and name the next roadmap item (`14c(+15f-i)` per the execution order in the spec, §4).

Not a commit with code changes — this is the same "write findings down the day they happen" step 15d's finishing session did. Use `superpowers:finishing-a-development-branch` to close out the branch (merge, whole-branch review, worktree/branch cleanup) once Steps 1-7 are clean.

---

## Self-Review Notes (writing-plans skill)

**Spec coverage:** 15e row's DoD — "Owner states a goal in chat; a council-reviewed envelope arrives for approval" → Task 3's `POST /jobs/draft` returns `job_entry` + critique in one call. "on approval the job runs unattended within it" → unchanged `run_job`/`POST /jobs/run/{job_id}`, not touched by this plan. "big-brain alias is called zero times during execution" → satisfied by construction (Task 2), verified by code-path inspection in Task 4 Step 5. Narrow-scope owner decision (steps/permission_level/workshop fixed, no new tool-calling surface) → Task 2's `_LINK_CHECKER_STEPS`/`_FIXED_PERMISSION_LEVEL` constants + the dedicated test that a hostile LLM output can't override them.

**Placeholder scan:** no TBD/TODO; every step has real code or a real shell command.

**Type consistency:** `planner.draft_envelope` returns a `dict` (the persisted job entry) everywhere it's referenced (Task 2's tests, Task 3's `main.py` wiring, Task 3's tests). `PlannerError` is the one exception type raised and caught. `_critique_and_note` signature `(job_id: str, job_entry: dict) -> dict` matches both call sites (existing `critique_job`, new `draft_job`).
