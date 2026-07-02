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
