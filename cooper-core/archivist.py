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
from dataclasses import dataclass
from pathlib import Path
from typing import Awaitable, Callable, List, Optional, Tuple, Union

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

    decision_rows = conn.execute(
        "SELECT summary FROM decisions_fts WHERE decisions_fts MATCH ? ORDER BY rank LIMIT ?",
        (query, limit),
    ).fetchall()
    brain_rows = conn.execute(
        "SELECT file_name, heading, body FROM brain_fts WHERE brain_fts MATCH ? ORDER BY rank LIMIT ?",
        (query, limit),
    ).fetchall()

    decision_results: List[RecallResult] = [
        RecallResult(kind="decision", text=row["summary"]) for row in decision_rows
    ]
    brain_results: List[RecallResult] = [
        RecallResult(kind="brain", text=f"{row['file_name']} — {row['heading']}: {row['body']}")
        for row in brain_rows
    ]

    per_source = -(-limit // 2)  # ceil(limit / 2): each source's guaranteed share
    combined = decision_results[:per_source] + brain_results[:per_source]
    if len(combined) < limit:
        # one source under-supplied its share — top up from the other source's leftovers
        leftover = decision_results[per_source:] + brain_results[per_source:]
        combined += leftover[: limit - len(combined)]
    return combined[:limit]


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
        try:
            text = path.read_text(encoding="utf-8")
            conn.execute("DELETE FROM brain_fts WHERE file_name = ?", (path.name,))
            for heading, body in _chunk_by_heading(text):
                conn.execute(
                    "INSERT INTO brain_fts (file_name, heading, body) VALUES (?, ?, ?)",
                    (path.name, heading, body),
                )
            conn.commit()
        except Exception as exc:
            conn.rollback()
            print(f"  [!!] archivist.index_brain: skipping {path.name} ({exc})")
            continue  # don't cache this file — retry it on the next call
        _brain_mtime_cache[cache_key] = mtime


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
