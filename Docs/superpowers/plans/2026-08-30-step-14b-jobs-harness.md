# Step 14b — Jobs Harness (T1 Link-Checker) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give COOPER a governed, per-job-approved autonomous job harness — envelope
hash-pinning (skills.py's pattern, reused), quota/scope enforcement in code (never in
prompts), an exception queue for anything that would exceed the envelope, a
Workflow_Evidence record per run, and a daily digest note — proven live end-to-end by
the T1 link-checker job (`csv_next_rows` → `url_verify` → `csv_line_edit`).

**Architecture:** `cooper-core/jobs.py` is the new module: it loads
`Config/jobs_registry.yaml`, verifies a job's content hash + `approved` flag before any
run (fail-closed, mirroring `skills.py`'s `compute_content_hash`/`skill_status`),
executes a job's named steps directly (bypassing the chat classifier entirely — jobs
never go through `route_turn`), enforces `read_scope`/`write_scope`/`quota` mechanically,
writes a job-linked Workflow_Evidence completion record per run, and enqueues anything
that would exceed the envelope into a new `job_exceptions` SQLite table instead of
either doing it or silently dropping it. A new `file_edit` executor type gives jobs a
bounded, dynamically-scoped write primitive (same containment pattern as the existing
`_run_filesystem`/`_run_note_editor` handlers, but the allowed root comes from the job's
own `write_scope`, not a fixed constant). `main.py` gains one new route,
`POST /jobs/run/{job_id}`, bearer-authed like every other endpoint, calling straight
into `jobs.run_job()`.

**Tech Stack:** Python 3.12, FastAPI, pytest, SQLite (`cooper_memory.db`), `httpx` (for
`url_verify`'s HTTP checks), n8n (scheduler, unchanged).

**Spec:** `Docs/superpowers/specs/2026-08-04-step-14-autonomous-jobs-design.md` — §2
"New pieces" (source of the file/table/endpoint list below) and §3's DoD row for 14b.

## Global Constraints

- Repo rule: no new JSON policy files where a declarative shape already fits;
  `Config/jobs_registry.yaml` is a NEW file (the spec explicitly calls for it — this is
  not the "no new policy files" case, that rule is about `Scripts/*.json`), but it must
  follow the same discipline as `Config/skills_registry.yaml`: content-hashed, approval
  gates the hash, any edit voids approval.
- **Owner decision, this session:** ship everything inert. `Config/jobs_registry.yaml`'s
  `link-checker` entry ships with `approved: false`. The n8n Cron workflow is imported
  but left DEACTIVATED. Only the owner flips `approved: true` and activates the n8n
  workflow — that is also the moment the spec's "≥2 consecutive days unattended" DoD
  clock can start; it cannot be closed out inside this plan's own execution.
- **Owner decision, this session:** `State/LinkAudit/links.csv` ships with a header row
  plus 2-3 clearly-fake placeholder rows (e.g. `https://example.com/placeholder-1`) —
  enough to prove the runner works end-to-end. The owner supplies real links later.
- **Governance amendment already owner-approved** (2026-08-04, per the spec's own
  decision record) — per-job envelope approval replacing per-action approval is not a
  new decision this plan needs to re-litigate; it's what this plan implements. Chat's
  per-action approval path (`approval.py`) is untouched — jobs are a parallel path, not
  a replacement.
- **Envelope enforcement lives in code, not prompts** (spec §5, explicit risk called
  out) — the runner checks `read_scope`/`write_scope`/quota mechanically in Python; no
  step is ever "trusted" to stay in bounds on its own.
- `file_edit` is scoped to jobs only in this slice — it is NOT added to
  `Config/general_tool_registry.yaml` or `private_tool_registry.yaml` (no new
  chat-reachable arbitrary-file-write tool without its own owner-reviewed
  `permission_level`/`approval_required`, which is out of this plan's scope to decide).
- Every behavior change lands with tests in the sibling `test_*.py` file; full suite
  (`cd cooper-core && .venv/bin/python -m pytest`) must stay green after every task.
- After editing cooper-core, a Docker stack must be rebuilt with
  `docker compose -f PDA-Runtime/docker-compose.yml up -d --build cooper-core` (Open
  stack — jobs run on `workshop: open` per the registry entry below) before live-testing.

---

### Task 1: `job_exceptions` table

**Files:**
- Modify: `cooper-core/archivist.py` (the `_SCHEMA` string inside `init_db`)
- Test: `cooper-core/test_archivist.py`

**Interfaces:**
- Produces: a `job_exceptions` table other tasks' code reads/writes directly via SQL
  (no ORM in this codebase) — columns: `id INTEGER PRIMARY KEY AUTOINCREMENT`,
  `job_id TEXT NOT NULL`, `run_id TEXT NOT NULL`, `proposed_action TEXT NOT NULL`,
  `reason TEXT NOT NULL`, `status TEXT NOT NULL DEFAULT 'pending'`,
  `created_at TEXT NOT NULL`.

- [ ] **Step 1: Read `cooper-core/archivist.py`'s `init_db` function and its `_SCHEMA`
  string in full** before editing — confirm the exact `CREATE TABLE IF NOT EXISTS`
  idiom used by the existing tables (`decisions`, `skills`, etc.) so the new table
  matches the file's own style exactly (column ordering conventions, whether `NOT NULL`
  is used elsewhere, `AUTOINCREMENT` vs bare `INTEGER PRIMARY KEY`, etc.).

- [ ] **Step 2: Write the failing test**

```python
def test_init_db_creates_job_exceptions_table(tmp_path):
    conn = archivist.init_db(str(tmp_path / "test.db"))
    cols = [r[1] for r in conn.execute("PRAGMA table_info(job_exceptions)").fetchall()]
    assert cols == ["id", "job_id", "run_id", "proposed_action", "reason", "status", "created_at"]
    conn.close()
```

(Adapt to whatever `init_db`'s actual signature/connection-return pattern is — read the
existing tests in `test_archivist.py` for `decisions`/`skills` table creation, which
already exercise `init_db`, and match that exact calling convention.)

- [ ] **Step 3: Run to verify failure**

Run: `cd cooper-core && .venv/bin/python -m pytest test_archivist.py -k job_exceptions -v`
Expected: FAIL — table doesn't exist.

- [ ] **Step 4: Add the table to `_SCHEMA`**

```sql
CREATE TABLE IF NOT EXISTS job_exceptions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id TEXT NOT NULL,
    run_id TEXT NOT NULL,
    proposed_action TEXT NOT NULL,
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TEXT NOT NULL
);
```

Insert this in the same `_SCHEMA` string as the existing tables, in the file's own
established style (match quoting/formatting exactly).

- [ ] **Step 5: Run to verify pass**

Run: `cd cooper-core && .venv/bin/python -m pytest test_archivist.py -v`
Expected: all pass, including the new test.

- [ ] **Step 6: Commit**

```bash
git add cooper-core/archivist.py cooper-core/test_archivist.py
git commit -m "feat(jobs): add job_exceptions table to cooper_memory.db schema (14b)"
```

---

### Task 2: `evidence.py` — job-linked completion records

**Files:**
- Modify: `cooper-core/evidence.py`
- Test: `cooper-core/test_evidence.py`

**Interfaces:**
- Produces: `evidence.is_job_linked(record: dict) -> bool` (True iff `record.get("job_id")`
  is truthy). Extends `validate_completion` so a job-linked open-workshop completion is
  valid WITHOUT an `approval_id` (empty string allowed, same as Private today), but
  additionally requires `job_id: str`, `envelope_hash: str`, `run_id: str` all present
  and non-empty when job-linked. Task 3's `jobs.py` writes records satisfying this shape.

- [ ] **Step 1: Write the failing tests**

```python
def _job_completion(**overrides):
    base = {
        "workflow_id": "link-checker", "workflow_name": "CSV Link Checker",
        "execution_id": "run-abc123", "status": "completed",
        "completion_time": "2026-08-30T12:00:00Z", "workshop_id": "open",
        "workshop_name": "Open Workshop", "approval_id": "",
        "artifact_paths": ["State/LinkAudit/links.csv"],
        "review_status": "pass", "user_accepted": True,
        "job_id": "link-checker", "envelope_hash": "a" * 64, "run_id": "run-abc123",
    }
    base.update(overrides)
    return base


def test_job_linked_open_completion_valid_without_approval_id():
    errs = evidence.validate_completion(_job_completion(), [])
    assert errs == []


def test_job_linked_completion_requires_envelope_hash():
    rec = _job_completion()
    del rec["envelope_hash"]
    errs = evidence.validate_completion(rec, [])
    assert any("envelope_hash" in e for e in errs)


def test_job_linked_completion_requires_job_id_and_run_id_together():
    rec = _job_completion()
    del rec["run_id"]
    errs = evidence.validate_completion(rec, [])
    assert any("run_id" in e for e in errs)


def test_non_job_open_completion_still_requires_approval_id():
    # Regression: existing per-action-approval behavior must be untouched.
    rec = _job_completion(job_id="", envelope_hash="", run_id="")
    errs = evidence.validate_completion(rec, [])
    assert any("requires an approval_id" in e for e in errs)


def test_is_job_linked():
    assert evidence.is_job_linked(_job_completion()) is True
    assert evidence.is_job_linked(_job_completion(job_id="")) is False
```

- [ ] **Step 2: Run to verify failure**

Run: `cd cooper-core && .venv/bin/python -m pytest test_evidence.py -v`
Expected: FAIL — `is_job_linked` doesn't exist; job-linked completions fail the existing
"requires an approval_id" check.

- [ ] **Step 3: Implement**

Add near the top of `evidence.py`, after `_APPROVAL_REQUIRED`:

```python
_JOB_LINKAGE_REQUIRED = {"job_id": str, "envelope_hash": str, "run_id": str}


def is_job_linked(record: dict) -> bool:
    return bool(record.get("job_id"))
```

In `validate_completion`, change:

```python
    workshop = record["workshop_id"]
    approval_id = record["approval_id"]
    if approval_id:
        ...
    elif workshop == "open":
        errs.append("linkage: open-workshop completion requires an approval_id")
```

to:

```python
    workshop = record["workshop_id"]
    approval_id = record["approval_id"]
    job_linked = is_job_linked(record)
    if job_linked:
        errs += _schema_errors(record, _JOB_LINKAGE_REQUIRED)
    if approval_id:
        ...  # unchanged existing approval-linkage block
    elif workshop == "open" and not job_linked:
        errs.append("linkage: open-workshop completion requires an approval_id")
```

(Leave the `if approval_id:` block's contents exactly as they are — only the
surrounding `elif` condition changes, and the new `job_linked` schema-check block is
inserted before it.)

- [ ] **Step 4: Run to verify pass**

Run: `cd cooper-core && .venv/bin/python -m pytest test_evidence.py -v`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/evidence.py cooper-core/test_evidence.py
git commit -m "feat(jobs): evidence.py accepts job_id+envelope_hash linkage for job runs (14b)"
```

---

### Task 3: `cooper-core/jobs.py` — envelope loading, hash verification, exception queue

**Files:**
- Create: `cooper-core/jobs.py`
- Create: `Config/jobs_registry.yaml` (minimal — just enough for this task's tests to
  load a real file; Task 5 adds the real `link-checker` entry)
- Test: `cooper-core/test_jobs.py`

**Interfaces:**
- Consumes: `sqlite3.Connection` (same connection object `archivist.py` hands out —
  read `archivist.py`'s `init_db`/connection-management pattern and match it, don't
  invent a new one).
- Produces:
  - `class JobError(Exception)`, `class QuotaExceeded(JobError)`
  - `load_registry(path: Optional[Path] = None) -> dict` — reads
    `Config/jobs_registry.yaml`, same fail-closed-to-`{"jobs": []}`-on-read-error
    pattern as `skills.py`'s `load_manifest`.
  - `get_job(job_id: str, registry: Optional[dict] = None) -> Optional[dict]`
  - `compute_envelope_hash(job_entry: dict) -> str` — SHA-256 hex digest over the job
    entry's canonical JSON (`json.dumps(entry, sort_keys=True)`, UTF-8 encoded), with
    the entry's own `envelope_hash` and `approved` keys EXCLUDED from what's hashed
    (hashing the hash would be circular, and `approved` must be flippable without
    changing the hash it gates).
  - `verify_job(job_entry: dict) -> Optional[str]` — returns `None` if the job is
    approved and its stored `envelope_hash` matches `compute_envelope_hash(job_entry)`;
    otherwise returns a human-readable reason string (`"not approved"` or
    `"hash mismatch — envelope was edited after approval"`). This is Task 4/6's gate:
    `run_job` must call this first and refuse to run on any non-`None` result.
  - `enqueue_exception(conn, job_id: str, run_id: str, proposed_action: str, reason: str) -> None`
  - `list_exceptions(conn, status: str = "pending") -> List[dict]`
  - `resolve_exception(conn, exception_id: int, status: str) -> None`

- [ ] **Step 1: Write the failing tests**

```python
# cooper-core/test_jobs.py
import sqlite3
import pytest

import jobs


MINIMAL_JOB = {
    "id": "test-job",
    "workshop": "open",
    "schedule_hint": "daily 03:00",
    "steps": ["noop"],
    "read_scope": [],
    "write_scope": [],
    "quota": {"rows_per_run": 1},
    "permission_level": 3,
    "approved": False,
}


def test_compute_envelope_hash_excludes_hash_and_approved_fields():
    entry_a = {**MINIMAL_JOB, "envelope_hash": "", "approved": False}
    entry_b = {**MINIMAL_JOB, "envelope_hash": "somehash", "approved": True}
    assert jobs.compute_envelope_hash(entry_a) == jobs.compute_envelope_hash(entry_b)


def test_compute_envelope_hash_changes_on_content_edit():
    entry_a = {**MINIMAL_JOB, "envelope_hash": "", "approved": False}
    entry_b = {**entry_a, "quota": {"rows_per_run": 999}}
    assert jobs.compute_envelope_hash(entry_a) != jobs.compute_envelope_hash(entry_b)


def test_verify_job_refuses_unapproved():
    entry = {**MINIMAL_JOB, "approved": False}
    entry["envelope_hash"] = jobs.compute_envelope_hash(entry)
    assert jobs.verify_job(entry) is not None
    assert "not approved" in jobs.verify_job(entry).lower()


def test_verify_job_refuses_hash_mismatch():
    entry = {**MINIMAL_JOB, "approved": True, "envelope_hash": "stale-hash"}
    reason = jobs.verify_job(entry)
    assert reason is not None and "hash" in reason.lower()


def test_verify_job_passes_when_approved_and_hash_matches():
    entry = {**MINIMAL_JOB, "approved": True}
    entry["envelope_hash"] = jobs.compute_envelope_hash(entry)
    assert jobs.verify_job(entry) is None


def test_load_registry_fails_closed_on_missing_file(tmp_path):
    registry = jobs.load_registry(tmp_path / "does-not-exist.yaml")
    assert registry == {"jobs": []}


def test_get_job_returns_none_for_unknown_id():
    registry = {"jobs": [MINIMAL_JOB]}
    assert jobs.get_job("nonexistent", registry) is None
    assert jobs.get_job("test-job", registry) == MINIMAL_JOB


@pytest.fixture
def conn():
    c = sqlite3.connect(":memory:")
    # Match whichever init helper archivist.py exposes — read archivist.py first and
    # call the real schema-creation function here instead of hand-writing SQL, so this
    # test can't drift from the real schema.
    import archivist
    archivist._init_schema(c)  # adjust to the real function name/signature you find
    yield c
    c.close()


def test_enqueue_and_list_exceptions(conn):
    jobs.enqueue_exception(conn, "test-job", "run-1", "write outside scope", "path not in write_scope")
    pending = jobs.list_exceptions(conn, status="pending")
    assert len(pending) == 1
    assert pending[0]["job_id"] == "test-job"
    assert pending[0]["proposed_action"] == "write outside scope"


def test_resolve_exception_changes_status(conn):
    jobs.enqueue_exception(conn, "test-job", "run-1", "action", "reason")
    exc_id = jobs.list_exceptions(conn, status="pending")[0]["id"]
    jobs.resolve_exception(conn, exc_id, "dismissed")
    assert jobs.list_exceptions(conn, status="pending") == []
    assert len(jobs.list_exceptions(conn, status="dismissed")) == 1
```

Before writing the implementation, read `cooper-core/archivist.py` in full to find its
actual schema-initialization function name/signature (Task 1 added `job_exceptions` to
whatever function builds `_SCHEMA`) and its actual DB-path/connection convention —
adjust the fixture above to call the real function, don't guess at a name.

- [ ] **Step 2: Run to verify failure**

Run: `cd cooper-core && .venv/bin/python -m pytest test_jobs.py -v`
Expected: FAIL — `jobs` module doesn't exist.

- [ ] **Step 3: Create `Config/jobs_registry.yaml` (minimal, real file)**

```yaml
jobs: []
```

- [ ] **Step 4: Implement `cooper-core/jobs.py`**

```python
"""Job runner (Step 14b): loads Config/jobs_registry.yaml, verifies a job's content
hash + approved flag before any run (same fail-closed pattern as skills.py's
compute_content_hash/skill_status — any edit to an approved job's envelope voids the
approval), and enforces its quota/scope boundaries in code. Jobs skip the chat
classifier entirely: the envelope names its steps directly, main.py's
POST /jobs/run/{job_id} calls straight into run_job() below."""
import hashlib
import json
import sqlite3
import time
import uuid
from pathlib import Path
from typing import List, Optional

import yaml

_REPO_ROOT = Path(__file__).resolve().parent.parent
_REGISTRY_PATH = _REPO_ROOT / "Config" / "jobs_registry.yaml"

_HASH_EXCLUDED_KEYS = {"envelope_hash", "approved"}


class JobError(Exception):
    pass


class QuotaExceeded(JobError):
    pass


def load_registry(path: Optional[Path] = None) -> dict:
    try:
        with open(path or _REGISTRY_PATH, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except (OSError, yaml.YAMLError):
        return {"jobs": []}
    if not isinstance(data, dict) or "jobs" not in data:
        return {"jobs": []}
    return data


def get_job(job_id: str, registry: Optional[dict] = None) -> Optional[dict]:
    registry = registry if registry is not None else load_registry()
    for job in registry.get("jobs", []):
        if job.get("id") == job_id:
            return job
    return None


def compute_envelope_hash(job_entry: dict) -> str:
    canonical = {k: v for k, v in job_entry.items() if k not in _HASH_EXCLUDED_KEYS}
    payload = json.dumps(canonical, sort_keys=True).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def verify_job(job_entry: dict) -> Optional[str]:
    if not job_entry.get("approved"):
        return "job is not approved"
    stored = job_entry.get("envelope_hash", "")
    computed = compute_envelope_hash(job_entry)
    if stored != computed:
        return "hash mismatch — envelope was edited after approval"
    return None


def enqueue_exception(
    conn: sqlite3.Connection, job_id: str, run_id: str, proposed_action: str, reason: str
) -> None:
    conn.execute(
        "INSERT INTO job_exceptions (job_id, run_id, proposed_action, reason, status, created_at) "
        "VALUES (?, ?, ?, ?, 'pending', ?)",
        (job_id, run_id, proposed_action, reason, time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())),
    )
    conn.commit()


def list_exceptions(conn: sqlite3.Connection, status: str = "pending") -> List[dict]:
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        "SELECT * FROM job_exceptions WHERE status = ? ORDER BY created_at", (status,)
    ).fetchall()
    return [dict(r) for r in rows]


def resolve_exception(conn: sqlite3.Connection, exception_id: int, status: str) -> None:
    conn.execute("UPDATE job_exceptions SET status = ? WHERE id = ?", (status, exception_id))
    conn.commit()
```

Adjust the DB-connection handling (`conn.row_factory` mutation, commit calls) to match
whatever convention `archivist.py` already uses elsewhere in this file for similar
read/write functions — don't introduce a second, inconsistent connection-handling style.

- [ ] **Step 5: Run to verify pass**

Run: `cd cooper-core && .venv/bin/python -m pytest test_jobs.py -v`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add cooper-core/jobs.py cooper-core/test_jobs.py Config/jobs_registry.yaml
git commit -m "feat(jobs): jobs.py envelope hash-pinning + exception queue (14b)"
```

---

### Task 4: `file_edit` executor

**Files:**
- Modify: `cooper-core/executor.py`
- Test: `cooper-core/test_executor.py`

**Interfaces:**
- Consumes: nothing new from prior tasks (this is a standalone executor addition).
- Produces: a new `executor_type` string `"file_edit"` wired into `_HANDLERS`
  (`executor.py`'s dispatch table). Handler signature matches the file's existing
  convention exactly (read `_run_filesystem` and `_run_note_editor` first — copy their
  signature style verbatim). Unlike every other handler, `file_edit`'s allowed root is
  NOT a fixed module-level constant — it's passed at call time via
  `args["write_scope"]` (a `List[str]` of allowed relative paths from repo root,
  supplied by the CALLER — `jobs.py`'s `run_job`, never by an LLM). Required `args`:
  `filename` (str, the path being written, relative to repo root),
  `content` (str, full new file content), `write_scope` (list of allowed relative
  paths — a write is permitted only if `filename` exactly matches one entry in
  `write_scope`, no glob/prefix matching, no directory traversal).

- [ ] **Step 1: Read `_run_filesystem` and `_run_note_editor` in full** in
  `cooper-core/executor.py` before writing anything — this task's containment logic
  must match their `.resolve()` + containment-check pattern exactly, just against a
  dynamic list instead of one fixed directory.

- [ ] **Step 2: Write the failing tests**

```python
def test_file_edit_writes_within_scope(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    args = {
        "filename": "State/LinkAudit/links.csv",
        "content": "url,status\nhttps://example.com,ok\n",
        "write_scope": ["State/LinkAudit/links.csv"],
    }
    result = asyncio.run(executor._run_file_edit({}, "edit", "open", args))
    assert "wrote" in result.lower() or "updated" in result.lower()
    written = (tmp_path / "State/LinkAudit/links.csv").read_text()
    assert written == args["content"]


def test_file_edit_refuses_path_outside_write_scope(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    args = {
        "filename": "PDA-Runtime/.env",
        "content": "malicious",
        "write_scope": ["State/LinkAudit/links.csv"],
    }
    with pytest.raises(executor.ExecutionError):
        asyncio.run(executor._run_file_edit({}, "edit", "open", args))
    assert not (tmp_path / "PDA-Runtime/.env").exists()


def test_file_edit_refuses_path_traversal_even_if_it_resolves_into_scope(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    (tmp_path / "State/LinkAudit").mkdir(parents=True)
    args = {
        "filename": "State/LinkAudit/../../PDA-Runtime/.env",
        "content": "malicious",
        "write_scope": ["State/LinkAudit/links.csv"],
    }
    with pytest.raises(executor.ExecutionError):
        asyncio.run(executor._run_file_edit({}, "edit", "open", args))


def test_file_edit_refuses_when_write_scope_missing_or_empty():
    with pytest.raises(executor.ExecutionError):
        asyncio.run(executor._run_file_edit(
            {}, "edit", "open", {"filename": "x.csv", "content": "y", "write_scope": []}
        ))
```

Check whether `executor.py` already has a `_REPO_ROOT`-style constant to monkeypatch
for tests, or whether existing tests use a different isolation mechanism (e.g.
monkeypatching the specific `_DIR` constant `_run_filesystem` uses) — match whatever
pattern the file's existing executor tests already use for path isolation, don't
introduce a new one.

- [ ] **Step 3: Run to verify failure**

Run: `cd cooper-core && .venv/bin/python -m pytest test_executor.py -k file_edit -v`
Expected: FAIL — `_run_file_edit` doesn't exist.

- [ ] **Step 4: Implement `_run_file_edit` and wire it into `_HANDLERS`**

The exact function body should mirror `_run_filesystem`'s containment technique
(`Path(...).resolve()` then check the resolved path is `relative_to()` an allowed
root) — but checked against each entry in `args["write_scope"]` rather than one fixed
directory constant, and matching `filename` to a write_scope entry BEFORE resolving
(reject on string mismatch first, cheap check), then re-confirming via `.resolve()`
containment against the repo root as defense in depth against traversal tricks (this is
why the traversal test above matters — a string-equality check on `filename` alone
already blocks `../../PDA-Runtime/.env` as literally written, but confirm your
implementation actually rejects it, don't assume). Raise `executor.ExecutionError` (the
same exception type every other handler in this file raises on hard failure) with a
clear message naming the offending path, for every one of the three failure tests
above. Register `"file_edit": _adapter_for_run_file_edit_matching_the_existing_pattern`
in `_HANDLERS` (copy the exact adapter-closure pattern used for `_run_filesystem` or
`_run_note_editor` — do not invent a different registration shape).

- [ ] **Step 5: Run to verify pass**

Run: `cd cooper-core && .venv/bin/python -m pytest test_executor.py -v`
Expected: all pass, `file_edit` present in `WIRED_EXECUTOR_TYPES`.

- [ ] **Step 6: Commit**

```bash
git add cooper-core/executor.py cooper-core/test_executor.py
git commit -m "feat(jobs): file_edit executor with job-supplied write_scope containment (14b)"
```

---

### Task 5: Link-checker job — registry entry, seed CSV, step functions

**Files:**
- Modify: `Config/jobs_registry.yaml` (replace the minimal `jobs: []` with the real
  `link-checker` entry)
- Create: `State/LinkAudit/links.csv`
- Modify: `cooper-core/jobs.py` (add `csv_next_rows`, `url_verify` step functions)
- Test: `cooper-core/test_jobs.py` (extend)

**Interfaces:**
- Consumes: `jobs.compute_envelope_hash` (Task 3), `executor._run_file_edit` (Task 4,
  called by `csv_line_edit` — a thin wrapper, not a new executor).
- Produces: `jobs.csv_next_rows(csv_path: Path, max_rows: int) -> List[dict]` (each dict:
  `{"row_index": int, "url": str, "content_hash": str}` — reads
  `State/LinkAudit/links.csv`, returns up to `max_rows` rows not yet checked today,
  tracked via a `last_checked` column in the CSV itself). `jobs.url_verify(url: str,
  expected_content_hash: Optional[str]) -> dict` (returns
  `{"url": str, "reachable": bool, "status_code": Optional[int], "content_changed":
  Optional[bool], "checked_at": str}` — makes one bounded HTTP GET via `httpx`, short
  timeout, no following of infinite redirect loops).

- [ ] **Step 1: Create `State/LinkAudit/links.csv`**

```csv
url,last_checked,status,notes
https://example.com/placeholder-1,,,PLACEHOLDER — replace with real links before enabling this job
https://example.com/placeholder-2,,,PLACEHOLDER — replace with real links before enabling this job
https://example.com/placeholder-3,,,PLACEHOLDER — replace with real links before enabling this job
```

- [ ] **Step 2: Write the failing tests for `csv_next_rows` and `url_verify`**

```python
def test_csv_next_rows_returns_unchecked_rows_up_to_max(tmp_path):
    csv_path = tmp_path / "links.csv"
    csv_path.write_text(
        "url,last_checked,status,notes\n"
        "https://a.example,,,\n"
        "https://b.example,,,\n"
        "https://c.example,2026-08-29,ok,\n"
    )
    rows = jobs.csv_next_rows(csv_path, max_rows=1)
    assert len(rows) == 1
    assert rows[0]["url"] == "https://a.example"


def test_csv_next_rows_returns_empty_when_all_checked_today(tmp_path):
    import datetime
    today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    csv_path = tmp_path / "links.csv"
    csv_path.write_text(f"url,last_checked,status,notes\nhttps://a.example,{today},ok,\n")
    assert jobs.csv_next_rows(csv_path, max_rows=10) == []


def test_url_verify_reports_unreachable_for_bad_host():
    result = jobs.url_verify("https://this-host-does-not-exist.invalid/", None)
    assert result["reachable"] is False
```

(The third test makes a real network call to a guaranteed-nonexistent host — this is
intentional and matches the repo's live-verification culture; it must fail fast, not
hang, so `url_verify`'s timeout must be short, a few seconds at most.)

- [ ] **Step 3: Run to verify failure**

Run: `cd cooper-core && .venv/bin/python -m pytest test_jobs.py -k "csv_next_rows or url_verify" -v`
Expected: FAIL.

- [ ] **Step 4: Implement `csv_next_rows` and `url_verify` in `cooper-core/jobs.py`**

Use Python's `csv` module for reading/writing (preserve column order, quote consistently
with what's already in the seed file). `csv_next_rows` reads all rows, filters to those
whose `last_checked` is not today's UTC date, returns at most `max_rows` — do not mutate
the file in this function (that's `csv_line_edit`'s job, via `file_edit`, driven by
`run_job` in Task 6). `url_verify` uses `httpx.get(url, timeout=5.0,
follow_redirects=True)`; catch `httpx.HTTPError` (and any exception `httpx` can raise
for a bad host) and return `reachable: False` rather than letting it propagate —
matching this repo's "background/best-effort calls degrade, never crash the caller"
convention seen elsewhere (e.g. `archivist.recall`'s try/except in `main.py`). Content-
change detection: compute `hashlib.sha256(response.text.encode()).hexdigest()` and
compare against `expected_content_hash` if one was supplied (from the CSV's own
`status` column encoding a prior hash, or simply `None` on a link's first-ever check —
keep this heuristic simple, exact design is your call as long as it's real, not a stub
that always returns `content_changed: None`).

- [ ] **Step 5: Add the real `link-checker` entry to `Config/jobs_registry.yaml`**

```yaml
jobs:
  - id: link-checker
    workshop: open
    schedule_hint: "daily 03:00"
    steps: [csv_next_rows, url_verify, csv_line_edit]
    read_scope: ["State/LinkAudit/links.csv"]
    write_scope: ["State/LinkAudit/links.csv"]
    quota:
      rows_per_run: 10
      fetches_per_run: 30
    permission_level: 3
    approved: false
    envelope_hash: ""
```

Then compute the real hash and fill it in — do NOT leave `envelope_hash: ""` in the
committed file (a job with a mismatched/empty hash simply can't run per Task 3's
`verify_job`, but the hash should still be accurate for when the owner reviews and
flips `approved: true`, so `verify_job` only ever fails on the `approved` check, not on
a bogus hash). Compute it with:

```bash
cd cooper-core && .venv/bin/python -c "
import jobs
registry = jobs.load_registry()
entry = jobs.get_job('link-checker', registry)
print(jobs.compute_envelope_hash(entry))
"
```

Paste the printed hash into the YAML's `envelope_hash` field, then re-run the command to
confirm it now matches (hash of the entry WITH the correct hash filled in should still
compute the same, since `envelope_hash` itself is excluded from what's hashed).

- [ ] **Step 6: Run to verify pass**

Run: `cd cooper-core && .venv/bin/python -m pytest test_jobs.py -v`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add Config/jobs_registry.yaml State/LinkAudit/links.csv cooper-core/jobs.py cooper-core/test_jobs.py
git commit -m "feat(jobs): link-checker job entry + csv_next_rows/url_verify steps (14b)"
```

---

### Task 6: `run_job` orchestration + `POST /jobs/run/{job_id}`

**Files:**
- Modify: `cooper-core/jobs.py` (add `run_job`)
- Modify: `cooper-core/main.py` (add the route)
- Test: `cooper-core/test_jobs.py`, `cooper-core/test_main_dispatch.py` (or a new
  `test_main_jobs.py` if `test_main_dispatch.py` is already large — your call, matching
  this repo's existing file-splitting judgment)

**Interfaces:**
- Consumes: everything from Tasks 1-5 — `jobs.verify_job`, `jobs.csv_next_rows`,
  `jobs.url_verify`, `executor._run_file_edit` (via a thin `csv_line_edit` wrapper you
  add in this task), `jobs.enqueue_exception`, `evidence`-shaped record writing (a new
  `jobs.write_job_evidence(...)` function, follow the existing repo convention for
  where completion records land on disk — read how `State/Workflow_Evidence/completion/`
  is populated today, likely by a PowerShell script or manually; this task's version
  writes the same JSON shape directly from Python).
- Produces: `jobs.run_job(job_id: str, conn: sqlite3.Connection) -> dict` — the full
  per-run summary (rows checked, rows changed, exceptions raised, evidence record path)
  that `main.py`'s new route returns as JSON. Route:
  `@app.post("/jobs/run/{job_id}", dependencies=[Depends(_require_auth)])`.

- [ ] **Step 1: Write the failing tests for `run_job`**

```python
def test_run_job_refuses_unapproved_job(conn, tmp_path, monkeypatch):
    registry = {"jobs": [{**MINIMAL_JOB, "approved": False, "id": "link-checker"}]}
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: registry)
    result = jobs.run_job("link-checker", conn)
    assert result["status"] == "refused"
    assert "not approved" in result["reason"].lower()


def test_run_job_enqueues_exception_for_out_of_scope_write(conn, tmp_path, monkeypatch):
    # Construct a job whose write_scope does NOT include the file its own step would
    # target, and confirm run_job catches the resulting ExecutionError and enqueues an
    # exception instead of raising or silently succeeding.
    ...  # concrete construction is your call — the assertion that matters:
    assert len(jobs.list_exceptions(conn, status="pending")) == 1
    # and the file was NOT written
```

Design the remaining `run_job` tests yourself, covering at minimum: a fully successful
run against a real approved+hash-matching job entry with a small in-`tmp_path` CSV
(mocking `url_verify`'s network call via monkeypatch so this test doesn't hit the real
network), quota enforcement (a job whose `rows_per_run` is smaller than the CSV's
unchecked-row count only processes that many), and evidence-record writing (confirm the
written JSON file validates against `evidence.validate_completion` with no errors, using
Task 2's new job-linkage support).

- [ ] **Step 2: Run to verify failure**

Run: `cd cooper-core && .venv/bin/python -m pytest test_jobs.py -k run_job -v`
Expected: FAIL — `run_job` doesn't exist.

- [ ] **Step 3: Implement `run_job` in `cooper-core/jobs.py`**

Shape (adapt exact control flow to what you learned from Tasks 1-5, this is the
contract, not verbatim code to paste):

1. Load the job entry; call `verify_job`. If it returns a reason, return
   `{"status": "refused", "reason": reason}` immediately — no run_id, no evidence
   record, nothing executed.
2. Generate `run_id = uuid.uuid4().hex[:12]`.
3. For the link-checker job specifically: call `csv_next_rows` bounded by
   `quota["rows_per_run"]`; for each row, call `url_verify`; track total fetches against
   `quota["fetches_per_run"]` — if a run would exceed it, stop processing further rows
   (don't raise, just cap) and note this in the run summary.
4. Build updated CSV content (new `last_checked`/`status` values for the rows just
   checked) and write it via `executor._run_file_edit` (async — this function is
   already `async def` per Task 4's tests using `asyncio.run`, so `run_job` itself
   should be `async def` too) with `args["write_scope"] = job_entry["write_scope"]`.
   Catch `executor.ExecutionError` specifically — on catch, call `enqueue_exception`
   with a clear `proposed_action`/`reason`, do NOT re-raise, and continue to evidence
   writing (a refused write is still a completed, reviewable run).
5. Write the job evidence record (job-linked shape from Task 2) to
   `State/Workflow_Evidence/completion/` — filename convention: match whatever the
   existing 12 completion records in that directory use (read a couple of them for the
   naming pattern before inventing your own).
6. Return a summary dict: `{"status": "completed", "run_id": run_id, "rows_checked": N,
   "rows_changed": N, "exceptions_raised": N, "evidence_path": str}`.

- [ ] **Step 4: Add the `/jobs/run/{job_id}` route to `main.py`**

Read `main.py`'s existing route definitions first (`/health`, `/tools`, `/pending`,
etc.) to match the file's exact style — dependency injection for auth, error handling
shape, response shape. The route body is thin: resolve the job via `jobs.get_job`, 404
if unknown, otherwise call `await jobs.run_job(job_id, <the module's DB connection>)`
and return its result as the JSON body. Use whatever connection object `main.py`
already holds for archivist/skills calls (`_ARCHIVIST_CONN` per earlier tasks' context)
— don't open a second, separate connection.

- [ ] **Step 5: Run to verify pass**

Run: `cd cooper-core && .venv/bin/python -m pytest -q`
Expected: all pass, full suite green.

- [ ] **Step 6: Commit**

```bash
git add cooper-core/jobs.py cooper-core/main.py cooper-core/test_jobs.py
git commit -m "feat(jobs): run_job orchestration + POST /jobs/run/{job_id} (14b)"
```

---

### Task 7: Digest note

**Files:**
- Modify: `cooper-core/jobs.py` (add `write_digest`)
- Modify: `cooper-core/main.py` (call `write_digest` at the end of the `/jobs/run`
  route, after a run completes — success or refused)
- Test: `cooper-core/test_jobs.py`

**Interfaces:**
- Produces: `jobs.write_digest(conn: sqlite3.Connection, date: Optional[str] = None) -> Path`
  — writes/overwrites (idempotent per day — re-running today's jobs again updates the
  same note, doesn't duplicate it) `Obsidian Vault/00_Inbox/COOPER-Digest-<date>.md`,
  covering: which jobs ran today (derived from today's `State/Workflow_Evidence/completion/*.json`
  files whose `job_id` is set), what changed (rows updated per run, from the evidence
  records' own summary — you may need to add a `summary` field to what `write_job_evidence`
  stores, beyond the strict `_COMPLETION_REQUIRED`/`_JOB_LINKAGE_REQUIRED` fields;
  evidence.py only validates required fields exist with the right type, extra fields
  are fine), pending exceptions (`jobs.list_exceptions(conn, status="pending")`), and
  any run whose `status` was `"refused"` or contained failures.

- [ ] **Step 1: Write the failing test**

```python
def test_write_digest_includes_todays_job_runs_and_pending_exceptions(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_EVIDENCE_DIR", tmp_path / "evidence")
    monkeypatch.setattr(jobs, "_DIGEST_DIR", tmp_path / "inbox")
    (tmp_path / "evidence").mkdir()
    (tmp_path / "inbox").mkdir()
    # write one fake today-dated job evidence record + one pending exception, then:
    jobs.enqueue_exception(conn, "link-checker", "run-1", "action", "reason")
    path = jobs.write_digest(conn)
    text = path.read_text()
    assert "link-checker" in text
    assert "reason" in text
```

Adapt the monkeypatched directory constants to whatever names you actually introduce in
Step 2 — this test's job is to prove the digest note contains real content pulled from
real evidence/exception state, not to dictate the exact internal variable names.

- [ ] **Step 2: Implement `write_digest`**

Introduce module-level `_EVIDENCE_DIR = _REPO_ROOT / "State" / "Workflow_Evidence" / "completion"`
and `_DIGEST_DIR = _REPO_ROOT / "Obsidian Vault" / "00_Inbox"` constants in `jobs.py` (so
tests can monkeypatch them, matching the pattern other modules in this codebase already
use for testable file-path constants). Read this repo's Obsidian markdown conventions
before writing the note — check `obsidian-markdown` skill guidance if unsure of
frontmatter/formatting conventions this vault already uses (glance at an existing note
under `Obsidian Vault/00_Inbox/` for the real style, e.g. the untracked
`dod-15a-test.md` mentioned in this repo's git status, or any other note there).

- [ ] **Step 3: Wire into `main.py`'s route**

After `jobs.run_job(...)` returns (Task 6's route), call `jobs.write_digest(conn)`
before returning the response — every run updates the day's digest, success or refused.

- [ ] **Step 4: Run to verify pass**

Run: `cd cooper-core && .venv/bin/python -m pytest -q`

- [ ] **Step 5: Commit**

```bash
git add cooper-core/jobs.py cooper-core/main.py cooper-core/test_jobs.py
git commit -m "feat(jobs): daily digest note in Obsidian inbox (14b)"
```

---

### Task 8: Live end-to-end verification + n8n scaffold (inert) + docs

**Files:**
- Create: `n8n Workflow/PDA-JobScheduler-LinkChecker.json` (imported into n8n but left
  DEACTIVATED — see Global Constraints)
- Modify: `PROGRESS.md`, `Obsidian Vault/brain/North Star.md`, `CLAUDE.md` (directory
  map / running-tests section if a new test file was added and CLAUDE.md's test count
  needs updating — check its current claim against the real count first)

**Interfaces:** none — this task is live verification + a scaffold + docs.

- [ ] **Step 1: Rebuild the Open stack**

Run: `docker compose -f PDA-Runtime/docker-compose.yml up -d --build cooper-core`

- [ ] **Step 2: Manually verify the full chain with the job still `approved: false`**

Confirm the endpoint correctly REFUSES to run (this is the DoD-adjacent proof that the
approval gate actually gates):

```bash
KEY=$(grep '^COOPER_API_KEYS=' PDA-Runtime/.env | cut -d= -f2 | cut -d, -f1)
curl -s -X POST http://localhost:8001/jobs/run/link-checker -H "Authorization: Bearer $KEY"
```

Expected: `{"status": "refused", "reason": "job is not approved"}` (or similar) — NOT a
successful run, NOT a 500 error.

- [ ] **Step 3: Temporarily flip `approved: true` in a LOCAL, UNCOMMITTED edit only, to
  prove the runner works end-to-end**

This is for verification only — do not commit this change (Global Constraints: the
owner flips this flag, not this plan). After editing:

```bash
docker compose -f PDA-Runtime/docker-compose.yml up -d --build cooper-core
curl -s -X POST http://localhost:8001/jobs/run/link-checker -H "Authorization: Bearer $KEY"
```

Expected: a real run — `status: "completed"`, `rows_checked` > 0 (against the 3
placeholder URLs), an evidence file written under
`State/Workflow_Evidence/completion/`, and (since `https://example.com/placeholder-1`
etc. are fake paths under a real domain that will 404 or otherwise not be "the expected
content") a plausible mix of reachable/unreachable results — this is expected and fine,
the point is proving the mechanism runs, not that the placeholder URLs are meaningful.
Confirm the CSV's `last_checked` column was actually updated. Confirm a digest note
appeared at `Obsidian Vault/00_Inbox/COOPER-Digest-<today>.md` with real content.

- [ ] **Step 4: Prove the exception-queue path live, deterministically**

Don't rely on the placeholder URLs happening to trigger an out-of-scope write (they
won't, by construction). Instead, directly exercise the mechanism: temporarily call
`jobs.run_job` (or a smaller direct call to `executor._run_file_edit`) with a
deliberately-wrong `write_scope` that excludes the CSV path, confirm
`ExecutionError` → `enqueue_exception` fires and nothing gets written, then confirm via
`curl` (a `/jobs/run` variant or a small ad-hoc script) that the exception is visible
via `jobs.list_exceptions`. Capture this as real evidence in your report — this is the
spec's literal DoD line: "an intentionally out-of-scope write lands in the exception
queue instead of happening."

- [ ] **Step 5: Revert the temporary `approved: true` edit**

```bash
git checkout -- Config/jobs_registry.yaml
docker compose -f PDA-Runtime/docker-compose.yml up -d --build cooper-core
curl -s -X POST http://localhost:8001/jobs/run/link-checker -H "Authorization: Bearer $KEY"
```

Confirm it's back to `"status": "refused"` — the live stack must NOT be left in an
activated state.

- [ ] **Step 6: Build the n8n workflow (imported, deactivated)**

Read `n8n Workflow/PDA_Command_Router.json` or `PDA-ChatBridge-HTTP.json` for the
existing pattern of an n8n workflow calling cooper-core's HTTP API with the bearer key
(header shape, base URL). Build a new workflow: a Cron trigger node (daily, matching
the registry entry's `schedule_hint: "daily 03:00"`) → an HTTP Request node POSTing to
`http://cooper-core:8000/jobs/run/link-checker` (container-internal DNS, matching the
existing pattern) with the bearer auth header. Export it as
`n8n Workflow/PDA-JobScheduler-LinkChecker.json`. Import it into the running n8n
instance via its UI or API (check whether n8n's REST API is reachable for a scripted
import, or whether this needs manual browser import per CLAUDE.md's existing
"`n8n Workflow/` — n8n workflow JSON exports (import via n8n UI)" convention) — leave
it DEACTIVATED after import. If browser-based import isn't feasible in this session,
report that clearly rather than claiming it's imported without verifying.

- [ ] **Step 7: Docs**

Update `PROGRESS.md` (mark 14b's roadmap checkbox, decision-log entry covering what
shipped, what's inert-pending-owner-activation, and the exact steps the owner needs to
take: review `Config/jobs_registry.yaml`'s `link-checker` entry, replace the 3
placeholder rows in `State/LinkAudit/links.csv` with real links, flip `approved: true`,
activate the n8n workflow — only then does the "≥2 consecutive days unattended" DoD
clock start) and `North Star.md` in the established style. Update `CLAUDE.md`'s test
count in "Running tests" if it's now stale (check the real number from this task's own
full-suite run first — don't guess).

- [ ] **Step 8: Commit**

```bash
git add "n8n Workflow/PDA-JobScheduler-LinkChecker.json" PROGRESS.md "Obsidian Vault/brain/North Star.md" CLAUDE.md
git commit -m "docs: 14b shipped — jobs harness live, inert pending owner activation"
```

---

## Self-Review Notes

- **Spec coverage:** `jobs.py` ✓ (Task 3), `Config/jobs_registry.yaml` ✓ (Tasks 3, 5),
  `POST /jobs/run/{job_id}` ✓ (Task 6), evidence-per-run ✓ (Tasks 2, 6), digest note ✓
  (Task 7), exception queue ✓ (Tasks 1, 3, 6, proven live in Task 8), `file_edit`
  executor ✓ (Task 4), link-checker job (T1) ✓ (Task 5). The spec's `web_search`
  executor is explicitly OUT of scope — that's 14c (T2), not 14b.
- **The multi-day DoD cannot close in this plan** — flagged explicitly in Global
  Constraints and Task 8's docs step. This plan's job is to make the mechanism real,
  live-verified, and safely inert; the owner's activation decision and the ensuing
  2-day observation window are necessarily outside any single execution session.
- **No placeholders in code blocks** — checked against the "No Placeholders" list.
  Where exact line numbers/current file text couldn't be pinned down without reading
  the live file first (`archivist.py`'s exact schema-function name, `main.py`'s exact
  connection variable name), tasks explicitly instruct "read the file first" rather
  than guessing at an API that might not exist — this is a deliberate, repo-consistent
  pattern (see the 15c plan's Task 4 for precedent), not a placeholder.
