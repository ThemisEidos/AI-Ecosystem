# COOPER Step 8 — Memory + Skill Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give COOPER a persistent memory: a `decisions` audit log, a trust-scored `skills`
table, and a read-only FTS5 mirror of the Obsidian brain — queried deterministically at recall
time, written via one LLM-extraction call after a reviewed dispatch succeeds or fails.

**Architecture:** New module `cooper-core/archivist.py` — a fifth pipeline role (Archivist)
alongside Quartermaster/Safety Officer/Workbench/Reviewer. Read path (`recall()`, `get_skill()`)
is deterministic SQLite FTS5/exact lookup, no LLM call. Write path (`remember()`) makes one
JSON-schema-constrained Ollama/OpenAI call (same shape as `decision.py`'s classifier and
`review.py`'s reviewer) to extract `{summary, tags, outcome}`, then writes rows. Wired into
`main.py` at three points: lifespan startup (init + brain indexing), post-execution
(`remember`), and pre-reply (`recall`/`get_skill` context injection). `approval.py`'s security
logic is never touched.

**Tech Stack:** Python stdlib `sqlite3` (FTS5 built in), no new runtime dependency. `pytest` added
to `cooper-core/requirements.txt` for the new unit tests (first tests this package has had).

Full design: `Docs/superpowers/specs/2026-07-01-cooper-memory-skill-loop-design.md`

## Global Constraints

- No new dependency beyond Python stdlib `sqlite3` and `pytest` (test-only). No ChromaDB, no
  embedding model, no new framework — per the Step 8 design doc §2–3.
- `approval.py`'s permission-ladder logic must not change. Archivist is purely additive.
- All Ollama calls use `temperature=0`, `think:false`, JSON-schema-constrained output — matching
  `decision.py` and `review.py`'s existing pattern exactly.
- DB file: `cooper-core/cooper_memory.db` — already covered by the repo's blanket `*.db`
  gitignore rule (`.gitignore:88`), no new ignore entry needed.
- Fail-safe on LLM extraction errors: `remember()` must never raise and never block the reply
  reaching the user — same fail-open posture as `review.py`.

---

### Task 1: SQLite schema + connection helper

**Files:**
- Create: `cooper-core/archivist.py`
- Create: `cooper-core/test_archivist.py`
- Modify: `cooper-core/requirements.txt` (add `pytest>=8.0.0`)

**Interfaces:**
- Produces: `get_conn(db_path: Optional[Path] = None) -> sqlite3.Connection`,
  `init_db(conn: sqlite3.Connection) -> None`

**Deviation from the design doc:** §4 of the spec lists a `skills_fts` virtual table, omitted
here. `get_skill()` (Task 2) is an exact `tool_name` lookup, not a fuzzy search — an FTS index
over `skills` has no consumer. `decisions_fts` and `brain_fts` (genuinely searched by `recall()`)
are kept as specified.

- [ ] **Step 1: Add pytest to requirements**

Modify `cooper-core/requirements.txt`, appending one line:

```
pytest>=8.0.0
```

- [ ] **Step 2: Write the failing test**

Create `cooper-core/test_archivist.py`:

```python
import sqlite3

import pytest

import archivist


@pytest.fixture
def conn():
    c = archivist.get_conn(db_path=":memory:")
    archivist.init_db(c)
    yield c
    c.close()


def test_init_db_creates_all_tables(conn):
    tables = {
        row[0]
        for row in conn.execute("SELECT name FROM sqlite_master WHERE type IN ('table', 'table')")
    }
    assert "decisions" in tables
    assert "skills" in tables

    fts_tables = {
        row[0]
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE sql LIKE '%fts5%'"
        )
    }
    assert "decisions_fts" in fts_tables
    assert "brain_fts" in fts_tables


def test_init_db_is_idempotent(conn):
    archivist.init_db(conn)  # calling twice must not raise
    archivist.init_db(conn)
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd cooper-core && .venv-win/Scripts/python.exe -m pytest test_archivist.py -v`
(from WSL2: `powershell.exe -Command "cd D:\D_Projects\01_AI_Ecosystem\cooper-core; .venv-win\Scripts\python.exe -m pytest test_archivist.py -v"`)
Expected: FAIL with `ModuleNotFoundError: No module named 'archivist'` (or import error — the
file doesn't exist yet).

- [ ] **Step 4: Write archivist.py schema + connection code**

Create `cooper-core/archivist.py`:

```python
"""
COOPER Archivist — memory + skill loop (Step 8).

Fifth pipeline role, alongside Quartermaster/Safety Officer/Workbench/Reviewer.

Storage: SQLite (FTS5), not ChromaDB — see
Docs/superpowers/specs/2026-07-01-cooper-memory-skill-loop-design.md for the full rationale.
Obsidian Vault/brain/ stays the human-curated source of truth; this module mirrors it into a
read-only FTS5 table (brain_fts) so recall() can search decisions and doctrine together.

Read path  — recall() / get_skill(): deterministic FTS5 / exact lookup, no LLM call.
Write path — remember(): one JSON-schema-constrained Ollama/OpenAI call extracts
             {summary, tags, outcome} from a completed dispatch, then writes a row.
"""
import re
import sqlite3
import time
from pathlib import Path
from typing import Optional, Union

_REPO_ROOT = Path(__file__).resolve().parent.parent
_DEFAULT_DB_PATH = Path(__file__).resolve().parent / "cooper_memory.db"
_BRAIN_DIR = _REPO_ROOT / "Obsidian Vault" / "brain"

_SCHEMA = """
CREATE TABLE IF NOT EXISTS decisions (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at     TEXT NOT NULL,
    workshop       TEXT NOT NULL,
    message        TEXT NOT NULL,
    tool_name      TEXT,
    summary        TEXT NOT NULL,
    tags           TEXT NOT NULL,
    outcome        TEXT NOT NULL,
    review_verdict TEXT,
    hrr_vector     BLOB
);
CREATE VIRTUAL TABLE IF NOT EXISTS decisions_fts USING fts5(
    message, summary, tags, decision_id UNINDEXED
);
CREATE TABLE IF NOT EXISTS skills (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_name             TEXT NOT NULL UNIQUE,
    tags                  TEXT NOT NULL,
    successful_run_count  INTEGER NOT NULL DEFAULT 0,
    failed_run_count      INTEGER NOT NULL DEFAULT 0,
    trust_score           REAL NOT NULL DEFAULT 0.0,
    last_success          TEXT,
    last_failure          TEXT,
    example_message       TEXT NOT NULL,
    example_output        TEXT,
    hrr_vector            BLOB
);
CREATE VIRTUAL TABLE IF NOT EXISTS brain_fts USING fts5(
    file_name, heading, body
);
"""


def get_conn(db_path: Optional[Union[str, Path]] = None) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path) if db_path else str(_DEFAULT_DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript(_SCHEMA)
    conn.commit()


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd cooper-core && .venv-win/Scripts/python.exe -m pytest test_archivist.py -v`
Expected: `test_init_db_creates_all_tables PASSED`, `test_init_db_is_idempotent PASSED`

- [ ] **Step 6: Commit**

```bash
git add cooper-core/archivist.py cooper-core/test_archivist.py cooper-core/requirements.txt
git commit -m "feat(cooper-core): add Archivist SQLite schema (Step 8, task 1/7)"
```

---

### Task 2: Read path — `recall()` and `get_skill()`

**Files:**
- Modify: `cooper-core/archivist.py`
- Modify: `cooper-core/test_archivist.py`

**Interfaces:**
- Consumes: `get_conn`, `init_db` from Task 1
- Produces: `RecallResult(kind: str, text: str)` dataclass; `recall(conn, message: str, limit:
  int = 3) -> list[RecallResult]`; `format_recall_context(results: list[RecallResult]) -> str`;
  `SkillRecord(tool_name: str, successful_run_count: int, failed_run_count: int, trust_score:
  float, last_success: Optional[str])` dataclass; `get_skill(conn, tool_name: str) ->
  Optional[SkillRecord]`

- [ ] **Step 1: Write the failing tests**

Append to `cooper-core/test_archivist.py`:

```python
def test_recall_finds_matching_decision(conn):
    conn.execute(
        "INSERT INTO decisions (created_at, workshop, message, tool_name, summary, tags, outcome, review_verdict) "
        "VALUES ('2026-07-01T00:00:00Z', 'private', 'restart the api server', 'PowerShell Private Runner', "
        "'Restarted the API server successfully', 'restart,api,server', 'success', 'pass')"
    )
    conn.execute(
        "INSERT INTO decisions_fts (message, summary, tags, decision_id) VALUES "
        "('restart the api server', 'Restarted the API server successfully', 'restart,api,server', 1)"
    )
    conn.commit()

    results = archivist.recall(conn, "can you restart the api again")
    assert any(r.kind == "decision" and "API server" in r.text for r in results)


def test_recall_returns_empty_list_for_no_matches(conn):
    assert archivist.recall(conn, "completely unrelated query xyz") == []


def test_format_recall_context_empty():
    assert archivist.format_recall_context([]) == ""


def test_format_recall_context_nonempty():
    results = [archivist.RecallResult(kind="decision", text="Restarted the API server")]
    ctx = archivist.format_recall_context(results)
    assert "Relevant memory" in ctx
    assert "Restarted the API server" in ctx


def test_get_skill_returns_none_when_absent(conn):
    assert archivist.get_skill(conn, "PowerShell Private Runner") is None


def test_get_skill_returns_record_when_present(conn):
    conn.execute(
        "INSERT INTO skills (tool_name, tags, successful_run_count, failed_run_count, trust_score, "
        "last_success, example_message, example_output) VALUES "
        "('PowerShell Private Runner', 'restart,api', 3, 1, 0.75, '2026-07-01T00:00:00Z', "
        "'run Test-Exec.ps1', 'OK')"
    )
    conn.commit()

    skill = archivist.get_skill(conn, "PowerShell Private Runner")
    assert skill is not None
    assert skill.successful_run_count == 3
    assert skill.failed_run_count == 1
    assert skill.trust_score == 0.75
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && .venv-win/Scripts/python.exe -m pytest test_archivist.py -v`
Expected: FAIL with `AttributeError: module 'archivist' has no attribute 'recall'` (and similar
for `RecallResult`, `format_recall_context`, `get_skill`).

- [ ] **Step 3: Implement the read path**

Append to `cooper-core/archivist.py` (add `dataclass` and `List` to the existing imports —
change `from typing import Optional, Union` to `from typing import List, Optional, Union` and
add `from dataclasses import dataclass` near the top):

```python
@dataclass
class RecallResult:
    kind: str   # "decision" | "brain"
    text: str


def _fts_query(message: str) -> str:
    """Build a safe FTS5 MATCH query from free text: OR of alphanumeric tokens, 3+ chars."""
    tokens = re.findall(r"[A-Za-z0-9]{3,}", message.lower())
    if not tokens:
        return ""
    return " OR ".join(dict.fromkeys(tokens))  # dedupe, preserve order


def recall(conn: sqlite3.Connection, message: str, limit: int = 3) -> List[RecallResult]:
    """Deterministic FTS5 search across past decisions and the Obsidian brain. No LLM call."""
    query = _fts_query(message)
    if not query:
        return []
    results: List[RecallResult] = []

    for row in conn.execute(
        "SELECT summary FROM decisions_fts WHERE decisions_fts MATCH ? ORDER BY rank LIMIT ?",
        (query, limit),
    ).fetchall():
        results.append(RecallResult(kind="decision", text=row["summary"]))

    for row in conn.execute(
        "SELECT file_name, heading, body FROM brain_fts WHERE brain_fts MATCH ? ORDER BY rank LIMIT ?",
        (query, limit),
    ).fetchall():
        results.append(
            RecallResult(kind="brain", text=f"{row['file_name']} — {row['heading']}: {row['body']}")
        )

    return results[:limit]


def format_recall_context(results: List[RecallResult]) -> str:
    if not results:
        return ""
    lines = [f"- ({r.kind}) {r.text}" for r in results]
    return "Relevant memory:\n" + "\n".join(lines)


@dataclass
class SkillRecord:
    tool_name: str
    successful_run_count: int
    failed_run_count: int
    trust_score: float
    last_success: Optional[str]


def get_skill(conn: sqlite3.Connection, tool_name: str) -> Optional[SkillRecord]:
    row = conn.execute(
        "SELECT tool_name, successful_run_count, failed_run_count, trust_score, last_success "
        "FROM skills WHERE tool_name = ?",
        (tool_name,),
    ).fetchone()
    if row is None:
        return None
    return SkillRecord(
        tool_name=row["tool_name"],
        successful_run_count=row["successful_run_count"],
        failed_run_count=row["failed_run_count"],
        trust_score=row["trust_score"],
        last_success=row["last_success"],
    )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && .venv-win/Scripts/python.exe -m pytest test_archivist.py -v`
Expected: all tests PASS (8 total: 2 from Task 1, 6 new).

- [ ] **Step 5: Commit**

```bash
git add cooper-core/archivist.py cooper-core/test_archivist.py
git commit -m "feat(cooper-core): add Archivist recall/get_skill read path (Step 8, task 2/7)"
```

---

### Task 3: Write path — `remember()`

**Files:**
- Modify: `cooper-core/archivist.py`
- Modify: `cooper-core/test_archivist.py`

**Interfaces:**
- Consumes: `_now()`, schema from Task 1
- Produces: `async def remember(conn, tool: dict, message: str, raw_output: str, verdict, workshop:
  str, *, base_url: str, api_key: str, model: str, backend: str, extract_fn=None) -> None`
  (`verdict` duck-types `review.ReviewVerdict` — needs only a `.verdict` attribute, `"pass"` or
  `"flag"`; `extract_fn` is an injectable `async def (message, raw_output, *, base_url, api_key,
  model, backend) -> dict` used by tests to avoid a live LLM call — production default is
  `_extract`, added in Task 5)

- [ ] **Step 1: Write the failing tests**

Append to `cooper-core/test_archivist.py`:

```python
import asyncio


class _FakeVerdict:
    def __init__(self, verdict):
        self.verdict = verdict
        self.reason = "test"


async def _fake_extract(message, raw_output, *, base_url, api_key, model, backend):
    return {"summary": "Did the thing successfully", "tags": "test,fake", "outcome": "success"}


def test_remember_writes_decision_row(conn):
    tool = {"name": "PowerShell Private Runner", "id": "ps-private"}
    asyncio.run(archivist.remember(
        conn, tool, "run Test-Exec.ps1", "[Test-Exec.ps1 - OK]", _FakeVerdict("pass"), "private",
        base_url="unused", api_key="unused", model="unused", backend="ollama",
        extract_fn=_fake_extract,
    ))
    row = conn.execute("SELECT * FROM decisions").fetchone()
    assert row["tool_name"] == "PowerShell Private Runner"
    assert row["summary"] == "Did the thing successfully"
    assert row["outcome"] == "success"
    assert row["review_verdict"] == "pass"

    fts_row = conn.execute("SELECT * FROM decisions_fts WHERE decisions_fts MATCH 'thing'").fetchone()
    assert fts_row is not None


def test_remember_creates_skill_on_first_pass(conn):
    tool = {"name": "PowerShell Private Runner", "id": "ps-private"}
    asyncio.run(archivist.remember(
        conn, tool, "run Test-Exec.ps1", "[Test-Exec.ps1 - OK]", _FakeVerdict("pass"), "private",
        base_url="unused", api_key="unused", model="unused", backend="ollama",
        extract_fn=_fake_extract,
    ))
    skill = archivist.get_skill(conn, "PowerShell Private Runner")
    assert skill.successful_run_count == 1
    assert skill.failed_run_count == 0
    assert skill.trust_score == 1.0


def test_remember_increments_skill_on_repeat_pass(conn):
    tool = {"name": "PowerShell Private Runner", "id": "ps-private"}
    for _ in range(2):
        asyncio.run(archivist.remember(
            conn, tool, "run Test-Exec.ps1", "[Test-Exec.ps1 - OK]", _FakeVerdict("pass"), "private",
            base_url="unused", api_key="unused", model="unused", backend="ollama",
            extract_fn=_fake_extract,
        ))
    skill = archivist.get_skill(conn, "PowerShell Private Runner")
    assert skill.successful_run_count == 2
    assert skill.trust_score == 1.0


def test_remember_demotes_trust_on_flag(conn):
    tool = {"name": "PowerShell Private Runner", "id": "ps-private"}
    asyncio.run(archivist.remember(
        conn, tool, "run Test-Exec.ps1", "[Test-Exec.ps1 - OK]", _FakeVerdict("pass"), "private",
        base_url="unused", api_key="unused", model="unused", backend="ollama",
        extract_fn=_fake_extract,
    ))
    asyncio.run(archivist.remember(
        conn, tool, "run NotARealScript.ps1", "Workbench: no .ps1 script path found",
        _FakeVerdict("flag"), "private",
        base_url="unused", api_key="unused", model="unused", backend="ollama",
        extract_fn=_fake_extract,
    ))
    skill = archivist.get_skill(conn, "PowerShell Private Runner")
    assert skill.successful_run_count == 1
    assert skill.failed_run_count == 1
    assert skill.trust_score == 0.5
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && .venv-win/Scripts/python.exe -m pytest test_archivist.py -v`
Expected: FAIL with `AttributeError: module 'archivist' has no attribute 'remember'`

- [ ] **Step 3: Implement `remember()`**

Append to `cooper-core/archivist.py` (add `Awaitable, Callable` to the `typing` import line —
it becomes `from typing import Awaitable, Callable, List, Optional, Union`):

```python
async def remember(
    conn: sqlite3.Connection,
    tool: dict,
    message: str,
    raw_output: str,
    verdict,
    workshop: str,
    *,
    base_url: str,
    api_key: str,
    model: str,
    backend: str,
    extract_fn: Optional[Callable[..., Awaitable[dict]]] = None,
) -> None:
    """Write path: extract a structured fact, log it to decisions, upsert the skills row."""
    extract_fn = extract_fn or _extract
    tool_name = tool.get("name", tool.get("id", "unknown"))

    try:
        facts = await extract_fn(
            message, raw_output,
            base_url=base_url, api_key=api_key, model=model, backend=backend,
        )
    except Exception:
        facts = {}
    summary = facts.get("summary") or raw_output[:200]
    tags = facts.get("tags") or ""
    outcome = facts.get("outcome") or ("success" if verdict.verdict == "pass" else "failure")

    now = _now()
    cur = conn.execute(
        "INSERT INTO decisions (created_at, workshop, message, tool_name, summary, tags, outcome, review_verdict) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (now, workshop, message, tool_name, summary, tags, outcome, verdict.verdict),
    )
    conn.execute(
        "INSERT INTO decisions_fts (message, summary, tags, decision_id) VALUES (?, ?, ?, ?)",
        (message, summary, tags, cur.lastrowid),
    )

    if verdict.verdict == "pass":
        conn.execute(
            "INSERT INTO skills (tool_name, tags, successful_run_count, failed_run_count, trust_score, "
            "last_success, example_message, example_output) VALUES (?, ?, 1, 0, 1.0, ?, ?, ?) "
            "ON CONFLICT(tool_name) DO UPDATE SET "
            "successful_run_count = successful_run_count + 1, "
            "tags = excluded.tags, "
            "trust_score = CAST(successful_run_count + 1 AS REAL) / (successful_run_count + 1 + failed_run_count), "
            "last_success = excluded.last_success, "
            "example_message = excluded.example_message, "
            "example_output = excluded.example_output",
            (tool_name, tags, now, message, raw_output[:500]),
        )
    else:
        conn.execute(
            "INSERT INTO skills (tool_name, tags, successful_run_count, failed_run_count, trust_score, "
            "last_failure, example_message, example_output) VALUES (?, ?, 0, 1, 0.0, ?, ?, ?) "
            "ON CONFLICT(tool_name) DO UPDATE SET "
            "failed_run_count = failed_run_count + 1, "
            "trust_score = CAST(successful_run_count AS REAL) / (successful_run_count + failed_run_count + 1), "
            "last_failure = excluded.last_failure",
            (tool_name, tags, now, message, raw_output[:500]),
        )
    conn.commit()
```

This defines `_extract` as a forward reference used at default-arg-resolution time (inside the
function body, not the signature), so it's fine that Task 5 adds `_extract` later — Task 3's
tests always pass `extract_fn=_fake_extract` explicitly, never hitting the `_extract` fallback.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && .venv-win/Scripts/python.exe -m pytest test_archivist.py -v`
Expected: all tests PASS. Note `test_remember_demotes_trust_on_flag`'s expected math: after 1
pass + 1 flag, `trust_score = 1 / (1 + 1) = 0.5`.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/archivist.py cooper-core/test_archivist.py
git commit -m "feat(cooper-core): add Archivist remember() write path (Step 8, task 3/7)"
```

---

### Task 4: Obsidian brain indexer

**Files:**
- Modify: `cooper-core/archivist.py`
- Modify: `cooper-core/test_archivist.py`

**Interfaces:**
- Consumes: schema from Task 1
- Produces: `index_brain(conn: sqlite3.Connection, brain_dir: Optional[Path] = None) -> None`

- [ ] **Step 1: Write the failing tests**

Append to `cooper-core/test_archivist.py`:

```python
def test_index_brain_chunks_by_heading(conn, tmp_path):
    brain_dir = tmp_path / "brain"
    brain_dir.mkdir()
    (brain_dir / "Gotchas.md").write_text(
        "# Gotchas\n\n"
        "### 2026-07-01 · asyncio subprocess broken on Windows\n\n"
        "Use run_in_executor instead.\n\n"
        "### 2026-07-01 · Unicode crash on Windows startup\n\n"
        "Use ASCII only in print statements.\n",
        encoding="utf-8",
    )

    archivist.index_brain(conn, brain_dir=brain_dir)

    rows = conn.execute("SELECT heading, body FROM brain_fts WHERE file_name = 'Gotchas.md'").fetchall()
    headings = {r["heading"] for r in rows}
    assert "2026-07-01 · asyncio subprocess broken on Windows" in headings
    assert "2026-07-01 · Unicode crash on Windows startup" in headings


def test_index_brain_is_searchable(conn, tmp_path):
    brain_dir = tmp_path / "brain"
    brain_dir.mkdir()
    (brain_dir / "Gotchas.md").write_text(
        "### 2026-07-01 · Unicode crash on Windows startup\n\nUse ASCII only.\n",
        encoding="utf-8",
    )
    archivist.index_brain(conn, brain_dir=brain_dir)

    results = archivist.recall(conn, "unicode crash windows")
    assert any(r.kind == "brain" and "Unicode crash" in r.text for r in results)


def test_index_brain_skips_unchanged_files(conn, tmp_path, monkeypatch):
    brain_dir = tmp_path / "brain"
    brain_dir.mkdir()
    f = brain_dir / "Gotchas.md"
    f.write_text("### heading one\n\nbody one\n", encoding="utf-8")

    archivist.index_brain(conn, brain_dir=brain_dir)
    first_count = conn.execute("SELECT COUNT(*) AS c FROM brain_fts").fetchone()["c"]

    archivist.index_brain(conn, brain_dir=brain_dir)  # same mtime, must not duplicate rows
    second_count = conn.execute("SELECT COUNT(*) AS c FROM brain_fts").fetchone()["c"]

    assert first_count == second_count
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && .venv-win/Scripts/python.exe -m pytest test_archivist.py -v`
Expected: FAIL with `AttributeError: module 'archivist' has no attribute 'index_brain'`

- [ ] **Step 3: Implement `index_brain()`**

Append to `cooper-core/archivist.py` (add `Tuple` to the `typing` import line — it becomes
`from typing import Awaitable, Callable, List, Optional, Tuple, Union`):

```python
_brain_mtime_cache: dict = {}


def index_brain(conn: sqlite3.Connection, brain_dir: Optional[Path] = None) -> None:
    """Mirror Obsidian Vault/brain/*.md into brain_fts, chunked by ### heading. Mtime-cached —
    matches registry.py's existing cache-by-mtime pattern for the YAML tool registry."""
    directory = brain_dir or _BRAIN_DIR
    if not directory.exists():
        return
    for path in sorted(directory.glob("*.md")):
        mtime = path.stat().st_mtime
        cache_key = str(path)
        if _brain_mtime_cache.get(cache_key) == mtime:
            continue
        conn.execute("DELETE FROM brain_fts WHERE file_name = ?", (path.name,))
        for heading, body in _chunk_by_heading(path.read_text(encoding="utf-8")):
            conn.execute(
                "INSERT INTO brain_fts (file_name, heading, body) VALUES (?, ?, ?)",
                (path.name, heading, body),
            )
        _brain_mtime_cache[cache_key] = mtime
    conn.commit()


def _chunk_by_heading(text: str) -> List[Tuple[str, str]]:
    """Split markdown into (heading, body) chunks on ### headings; whole doc if none found."""
    parts = re.split(r"^###\s+(.+)$", text, flags=re.MULTILINE)
    if len(parts) == 1:
        return [("(document)", text.strip())]
    chunks: List[Tuple[str, str]] = []
    if parts[0].strip():
        chunks.append(("(preamble)", parts[0].strip()))
    for i in range(1, len(parts), 2):
        heading = parts[i].strip()
        body = parts[i + 1].strip() if i + 1 < len(parts) else ""
        chunks.append((heading, body))
    return chunks
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && .venv-win/Scripts/python.exe -m pytest test_archivist.py -v`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/archivist.py cooper-core/test_archivist.py
git commit -m "feat(cooper-core): add Archivist brain indexer (Step 8, task 4/7)"
```

---

### Task 5: Production LLM extractor — `_extract()`

**Files:**
- Modify: `cooper-core/archivist.py`

**Interfaces:**
- Consumes: `_ollama_complete`, `_openai_complete` from `decision.py` (already imported
  elsewhere in this codebase with this exact signature: `async def _ollama_complete(base_url,
  model, messages, *, options=None, fmt=None) -> str`; `async def _openai_complete(base_url,
  api_key, model, messages, *, temperature=None, response_format=None) -> str`)
- Produces: `async def _extract(message: str, raw_output: str, *, base_url: str, api_key: str,
  model: str, backend: str) -> dict` — the default `extract_fn` for `remember()`

This task has no new unit test: `_extract` makes a live LLM call, and every other LLM-calling
function in this codebase (`decision.py`'s `_classify`, `review.py`'s `review`) is verified live
via `curl`, not pytest, for the same reason — mocking the HTTP layer would test the mock, not
the integration. Task 7 verifies this function live.

- [ ] **Step 1: Add the import and system prompt**

Modify `cooper-core/archivist.py`: add this import near the top, after the existing `from typing
import ...` line:

```python
from decision import _ollama_complete, _openai_complete
```

Add this constant after `_BRAIN_DIR = ...`:

```python
_EXTRACT_SYSTEM = """\
You are COOPER's Archivist. A dispatched task just finished. Extract a short structured record \
of what happened. Output JSON only — no other text.

{"summary":"<one sentence, what was done and the result>","tags":"<comma-separated keywords>","outcome":"success"|"failure"}\
"""
```

- [ ] **Step 2: Implement `_extract()`**

Also add `json` to the imports at the top of `cooper-core/archivist.py` (`import json` alongside
the existing `import re`). Append to `cooper-core/archivist.py`:

```python
async def _extract(
    message: str,
    raw_output: str,
    *,
    base_url: str,
    api_key: str,
    model: str,
    backend: str,
) -> dict:
    """Production extractor: one JSON-schema-constrained LLM call. Fails safe on error."""
    messages = [
        {"role": "system", "content": _EXTRACT_SYSTEM},
        {"role": "user", "content": f"Request: {message}\n\nResult:\n{raw_output[:2000]}"},
    ]
    try:
        if backend == "openai":
            raw = await _openai_complete(
                base_url, api_key, model, messages,
                temperature=0,
                response_format={
                    "type": "json_schema",
                    "json_schema": {
                        "name": "extraction",
                        "strict": True,
                        "schema": {
                            "type": "object",
                            "properties": {
                                "summary": {"type": "string"},
                                "tags":    {"type": "string"},
                                "outcome": {"type": "string", "enum": ["success", "failure"]},
                            },
                            "required": ["summary", "tags", "outcome"],
                            "additionalProperties": False,
                        },
                    },
                },
            )
        else:
            raw = await _ollama_complete(
                base_url, model, messages,
                options={"temperature": 0},
                fmt={
                    "type": "object",
                    "properties": {
                        "summary": {"type": "string"},
                        "tags":    {"type": "string"},
                        "outcome": {"type": "string", "enum": ["success", "failure"]},
                    },
                    "required": ["summary", "tags", "outcome"],
                },
            )
        return json.loads(raw)
    except Exception:
        return {"summary": raw_output[:200], "tags": "", "outcome": "success"}
```

- [ ] **Step 3: Run the full test suite to verify nothing broke**

Run: `cd cooper-core && .venv-win/Scripts/python.exe -m pytest test_archivist.py -v`
Expected: all tests from Tasks 1–4 still PASS (this task adds no new tests, only production
code — `remember()`'s tests all pass `extract_fn` explicitly, so `_extract` is never invoked by
the existing suite).

- [ ] **Step 4: Commit**

```bash
git add cooper-core/archivist.py
git commit -m "feat(cooper-core): add Archivist production LLM extractor (Step 8, task 5/7)"
```

---

### Task 6: Wire into `main.py`

**Files:**
- Modify: `cooper-core/main.py`

**Interfaces:**
- Consumes: `archivist.get_conn`, `archivist.init_db`, `archivist.index_brain`,
  `archivist.recall`, `archivist.format_recall_context`, `archivist.get_skill`,
  `archivist.remember` (all from Tasks 1–5)
- Produces: no new public interface — this task only wires existing functions into the running
  server

No new unit test — this task modifies FastAPI request-handling code that is verified live via
`curl` in Task 7, matching how every prior step (3 through 7) was verified in this codebase (see
`PROGRESS.md` "What actually runs today").

- [ ] **Step 1: Add the import and a module-level connection**

Modify `cooper-core/main.py`. Change the import block:

```python
import registry
import approval
import executor
import review
import workshop
```

to:

```python
import registry
import approval
import executor
import review
import workshop
import archivist
```

Then add a module-level connection right after `SYSTEM_PROMPT = _load_system_prompt()`:

```python
SYSTEM_PROMPT = _load_system_prompt()

# ── Archivist (Step 8) ───────────────────────────────────────────────────────────
_ARCHIVIST_CONN = archivist.get_conn()
```

- [ ] **Step 2: Initialize schema and index the brain at startup**

Modify the `lifespan` function in `cooper-core/main.py`. Find:

```python
    # Workshop boundary integrity check
    try:
        workshop.check_backend(BACKEND, WORKSHOP)
        print(f"  [ok] workshop boundary: {WORKSHOP} -> {BACKEND}")
    except workshop.WorkshopViolation as exc:
        print(f"  [!!] WORKSHOP VIOLATION at startup: {exc}")

    print()
    yield
```

Replace with:

```python
    # Workshop boundary integrity check
    try:
        workshop.check_backend(BACKEND, WORKSHOP)
        print(f"  [ok] workshop boundary: {WORKSHOP} -> {BACKEND}")
    except workshop.WorkshopViolation as exc:
        print(f"  [!!] WORKSHOP VIOLATION at startup: {exc}")

    archivist.init_db(_ARCHIVIST_CONN)
    archivist.index_brain(_ARCHIVIST_CONN)
    print("  [ok] archivist: schema ready, brain indexed")

    print()
    yield
```

- [ ] **Step 3: Call `remember()` after execution**

Modify `_execute()` in `cooper-core/main.py`. Find:

```python
async def _execute(tool: dict, message: str) -> str:
    """
    Run an approved/auto-run tool through the Workbench (Worker), then have
    the Reviewer check the result before it reaches the user (Step 7).
    """
    try:
        raw_output = await executor.run(tool, message, WORKSHOP)
    except executor.ExecutionError as exc:
        return f"Workbench error: {exc}"

    verdict = await review.review(
        tool, message, raw_output,
        base_url=BACKEND_URL,
        api_key=BACKEND_KEY,
        model=CLASSIFIER_MODEL,
        backend=BACKEND,
    )
    return review.govern(raw_output, verdict)
```

Replace with:

```python
async def _execute(tool: dict, message: str) -> str:
    """
    Run an approved/auto-run tool through the Workbench (Worker), then have
    the Reviewer check the result (Step 7) and the Archivist remember it
    (Step 8) before it reaches the user.
    """
    try:
        raw_output = await executor.run(tool, message, WORKSHOP)
    except executor.ExecutionError as exc:
        return f"Workbench error: {exc}"

    verdict = await review.review(
        tool, message, raw_output,
        base_url=BACKEND_URL,
        api_key=BACKEND_KEY,
        model=CLASSIFIER_MODEL,
        backend=BACKEND,
    )

    try:
        await archivist.remember(
            _ARCHIVIST_CONN, tool, message, raw_output, verdict, WORKSHOP,
            base_url=BACKEND_URL, api_key=BACKEND_KEY,
            model=CLASSIFIER_MODEL, backend=BACKEND,
        )
    except Exception as exc:
        print(f"  [!!] archivist.remember failed (non-fatal): {exc}")

    return review.govern(raw_output, verdict)
```

- [ ] **Step 4: Note a matching skill in the dispatch halt/auto-run reply**

Modify `_handle_dispatch()` in `cooper-core/main.py`. Find:

```python
    # Enforce workshop boundary before gating or executing
    try:
        workshop.check_tool(tool, WORKSHOP)
    except workshop.WorkshopViolation as exc:
        return f"Workshop violation: {exc}"

    if approval.needs_approval(tool):
        approval.request(WORKSHOP, tool, message)
        return (
            f"Halt — {tool.get('name', tool.get('id'))} "
            f"[{tool.get('drawer', 'Uncategorized')}, permission level {tool.get('permission_level', '?')}] "
            f"requires approval before it can proceed. Reply 'approve' or 'deny'."
        )

    # L0/L1: execute immediately
    return await _execute(tool, message)
```

Replace with:

```python
    # Enforce workshop boundary before gating or executing
    try:
        workshop.check_tool(tool, WORKSHOP)
    except workshop.WorkshopViolation as exc:
        return f"Workshop violation: {exc}"

    skill_note = ""
    skill = archivist.get_skill(_ARCHIVIST_CONN, tool.get("name", tool.get("id", "unknown")))
    if skill is not None and skill.trust_score > 0.5:
        skill_note = (
            f" (matches a proven skill — {skill.successful_run_count} successful "
            f"run{'s' if skill.successful_run_count != 1 else ''}, "
            f"{skill.trust_score:.0%} trust)"
        )

    if approval.needs_approval(tool):
        approval.request(WORKSHOP, tool, message)
        return (
            f"Halt — {tool.get('name', tool.get('id'))} "
            f"[{tool.get('drawer', 'Uncategorized')}, permission level {tool.get('permission_level', '?')}] "
            f"requires approval before it can proceed{skill_note}. Reply 'approve' or 'deny'."
        )

    # L0/L1: execute immediately
    if skill_note:
        print(f"  [archivist] {tool.get('name')}{skill_note}")
    return await _execute(tool, message)
```

- [ ] **Step 5: Inject recalled decisions into answer-path generation**

Modify `_generate()` in `cooper-core/main.py`. Find:

```python
async def _generate(message: str, history: List[dict]) -> str:
    msgs = _build_messages(history, message)
    if BACKEND == "openai":
        from decision import _openai_complete
        return await _openai_complete(BACKEND_URL, BACKEND_KEY, COOPER_MODEL, msgs)
    from decision import _ollama_complete
    return await _ollama_complete(BACKEND_URL, COOPER_MODEL, msgs)
```

Replace with:

```python
async def _generate(message: str, history: List[dict]) -> str:
    recall_context = archivist.format_recall_context(archivist.recall(_ARCHIVIST_CONN, message))
    msgs = _build_messages(history, message)
    if recall_context:
        msgs.insert(1, {"role": "system", "content": recall_context})
    if BACKEND == "openai":
        from decision import _openai_complete
        return await _openai_complete(BACKEND_URL, BACKEND_KEY, COOPER_MODEL, msgs)
    from decision import _ollama_complete
    return await _ollama_complete(BACKEND_URL, COOPER_MODEL, msgs)
```

`msgs.insert(1, ...)` places the recall context right after the system prompt (index 0) and
before conversation history — `_build_messages` always puts the system prompt at index 0, so
this index is safe regardless of history length.

- [ ] **Step 6: Restart the server and confirm it starts clean**

From WSL2:

```bash
powershell.exe -ExecutionPolicy Bypass -File "D:\D_Projects\01_AI_Ecosystem\cooper-core\Start-CooperCore.ps1" -Workshop private
```

Then:

```bash
sleep 6
cat /mnt/d/D_Projects/01_AI_Ecosystem/cooper-core/cooper-core.err.log | tail -20
curl -s --max-time 5 http://localhost:8000/health
```

Expected log lines include `[ok] archivist: schema ready, brain indexed` and
`{"status":"ok","workshop":"private",...}` from the health check. If the log shows an
`ImportError` or `AttributeError`, re-check Steps 1–5 for a typo before proceeding — do not
skip to Task 7 with a broken server.

- [ ] **Step 7: Commit**

```bash
git add cooper-core/main.py
git commit -m "feat(cooper-core): wire Archivist into main.py turn loop (Step 8, task 6/7)"
```

---

### Task 7: Live verification of both DoD scenarios

**Files:** none modified — this task only runs `curl` against the live server and records the
result in `PROGRESS.md` and the Obsidian brain, matching the verification convention already
used for every prior step.

**Interfaces:** none — this task consumes the running server from Task 6.

- [ ] **Step 1: Verify skill reuse (first DoD scenario)**

With the server from Task 6 still running, dispatch a tool, approve it, and let it succeed:

```bash
curl -s --max-time 90 -X POST http://localhost:8000/chat -H "Content-Type: application/json" \
  -d '{"message":"run Test-Exec.ps1"}'
echo
curl -s --max-time 90 -X POST http://localhost:8000/chat -H "Content-Type: application/json" \
  -d '{"message":"approve"}'
echo
```

Then dispatch the same request again:

```bash
curl -s --max-time 90 -X POST http://localhost:8000/chat -H "Content-Type: application/json" \
  -d '{"message":"run Test-Exec.ps1"}'
echo
```

Expected: the second dispatch's `"Halt — PowerShell Private Runner..."` reply now includes the
skill note, e.g. `"...requires approval before it can proceed (matches a proven skill — 1
successful run, 100% trust). Reply 'approve' or 'deny'."` — this is the observable "reuses a
saved skill at runtime" behavior. Approve it again to leave the system in a clean state:

```bash
curl -s --max-time 90 -X POST http://localhost:8000/chat -H "Content-Type: application/json" \
  -d '{"message":"approve"}'
echo
```

- [ ] **Step 2: Verify decision recall (second DoD scenario)**

```bash
curl -s --max-time 90 -X POST http://localhost:8000/chat -H "Content-Type: application/json" \
  -d '{"message":"have we run Test-Exec.ps1 before, what happened?"}'
echo
```

Expected: `decision:"answer"` and a reply that references the prior successful run captured in
the `decisions` table (not just a generic "I don't have that information" response) — this is
the observable "COOPER recalls a prior decision" behavior. If the reply doesn't clearly
reference the past run, inspect what `archivist.recall()` actually returned for this query:

```bash
powershell.exe -Command "cd D:\D_Projects\01_AI_Ecosystem\cooper-core; .venv-win\Scripts\python.exe -c \"import archivist; c = archivist.get_conn(); print(archivist.recall(c, 'have we run Test-Exec.ps1 before'))\""
```

and adjust `_fts_query`'s tokenization or the `_EXTRACT_SYSTEM` prompt's summary wording if the
match quality is poor — this is a tuning step, not a structural one; do not add new tables or
change the schema to fix a wording mismatch.

- [ ] **Step 3: Record the verification in `PROGRESS.md`**

Add a bullet under "What actually runs today" in `PROGRESS.md`, following the exact format
already used for Steps 3–7 (see the existing `- **Sub-agent Reviewer (cooper-core/review.py).**
Verified live 2026-07-01: ...` entry as the template), pasting the actual `curl` output observed
in Steps 1–2 above. Mark Step 8 `[x]` in the roadmap checklist and update "Current step" to `9`.

- [ ] **Step 4: Update the Obsidian brain**

Add a `### 2026-07-01 · Step 8 (Archivist) verified live` entry to `Obsidian Vault/brain/Key
Decisions.md` summarizing what was verified, and update `Obsidian Vault/brain/North Star.md`'s
roadmap table (mark step 8 `done 2026-07-01`, step 9 `CURRENT`) — same pattern used after every
prior step's completion this session.

- [ ] **Step 5: Commit**

```bash
git add PROGRESS.md "Obsidian Vault/brain/Key Decisions.md" "Obsidian Vault/brain/North Star.md"
git commit -m "docs: verify Step 8 (Archivist) live, advance to Step 9"
```
