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
