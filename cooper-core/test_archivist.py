import asyncio
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


def test_recall_includes_both_decision_and_brain_results(conn):
    for i in range(1, 4):
        conn.execute(
            "INSERT INTO decisions (created_at, workshop, message, tool_name, summary, tags, outcome, review_verdict) "
            "VALUES ('2026-07-01T00:00:00Z', 'private', 'restart the widget server', 'PowerShell Private Runner', "
            "'Restarted the widget server successfully', 'restart,widget,server', 'success', 'pass')"
        )
        conn.execute(
            "INSERT INTO decisions_fts (message, summary, tags, decision_id) VALUES "
            "('restart the widget server', 'Restarted the widget server successfully', 'restart,widget,server', ?)",
            (i,),
        )
    conn.execute(
        "INSERT INTO brain_fts (file_name, heading, body) VALUES "
        "('Gotchas.md', 'Widget restarts', 'Always restart the widget server after a config change')"
    )
    conn.commit()

    results = archivist.recall(conn, "restart the widget server", limit=3)
    kinds = {r.kind for r in results}
    assert "decision" in kinds
    assert "brain" in kinds


def test_recall_returns_empty_list_when_message_has_no_searchable_tokens(conn):
    assert archivist.recall(conn, "hi") == []
    assert archivist.recall(conn, "???") == []
    assert archivist.recall(conn, "") == []


def test_recall_backfills_from_decisions_when_brain_has_no_matches(conn):
    for i in range(1, 6):
        conn.execute(
            "INSERT INTO decisions (created_at, workshop, message, tool_name, summary, tags, outcome, review_verdict) "
            "VALUES ('2026-07-01T00:00:00Z', 'private', 'restart the gadget server', 'PowerShell Private Runner', "
            "'Restarted the gadget server successfully', 'restart,gadget,server', 'success', 'pass')"
        )
        conn.execute(
            "INSERT INTO decisions_fts (message, summary, tags, decision_id) VALUES "
            "('restart the gadget server', 'Restarted the gadget server successfully', 'restart,gadget,server', ?)",
            (i,),
        )
    conn.commit()

    results = archivist.recall(conn, "restart the gadget server", limit=3)
    assert len(results) == 3
    assert all(r.kind == "decision" for r in results)


def test_format_recall_context_empty():
    assert archivist.format_recall_context([]) == ""


def test_format_recall_context_nonempty():
    results = [archivist.RecallResult(kind="decision", text="Restarted the API server")]
    ctx = archivist.format_recall_context(results)
    assert "Reference notes retrieved from local memory" in ctx
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

    archivist.index_brain(conn, brain_dir=brain_dir, force=True)  # same mtime, must not duplicate rows
    second_count = conn.execute("SELECT COUNT(*) AS c FROM brain_fts").fetchone()["c"]

    assert first_count == second_count


def test_index_brain_bad_file_does_not_poison_earlier_files_cache(conn, tmp_path):
    brain_dir = tmp_path / "brain"
    brain_dir.mkdir()
    # "Good.md" sorts before "Invalid.md" alphabetically, so it is processed
    # (and committed) first in the same index_brain() call.
    (brain_dir / "Good.md").write_text(
        "### valid heading\n\nvalid body content\n", encoding="utf-8",
    )
    (brain_dir / "Invalid.md").write_bytes(
        b"### heading\n\n\xff\xfe invalid utf-8 bytes"
    )

    archivist.index_brain(conn, brain_dir=brain_dir)  # must not raise

    rows = conn.execute(
        "SELECT heading, body FROM brain_fts WHERE file_name = 'Good.md'"
    ).fetchall()
    assert any(r["heading"] == "valid heading" for r in rows)

    # Second call: the bad file's cache entry was never set, so it is retried
    # again — and must still not raise, and the good file's row must survive.
    archivist.index_brain(conn, brain_dir=brain_dir, force=True)

    rows_after = conn.execute(
        "SELECT heading, body FROM brain_fts WHERE file_name = 'Good.md'"
    ).fetchall()
    assert any(r["heading"] == "valid heading" for r in rows_after)


def test_extract_returns_empty_dict_on_llm_failure(monkeypatch):
    async def boom(*args, **kwargs):
        raise RuntimeError("llm down")

    monkeypatch.setattr(archivist, "_ollama_complete", boom)
    facts = asyncio.run(
        archivist._extract("msg", "output", base_url="", api_key="", model="m", backend="ollama")
    )
    assert facts == {}


def test_remember_records_failure_when_extract_errors_and_verdict_flagged(conn, monkeypatch):
    async def boom(*args, **kwargs):
        raise RuntimeError("llm down")

    monkeypatch.setattr(archivist, "_ollama_complete", boom)

    class Verdict:
        verdict = "flag"

    asyncio.run(
        archivist.remember(
            conn, {"name": "T"}, "run thing", "[exit 1] boom", Verdict(), "private",
            base_url="", api_key="", model="m", backend="ollama",
        )
    )
    row = conn.execute("SELECT outcome FROM decisions").fetchone()
    assert row["outcome"] == "failure"


def test_format_recall_context_marks_untrusted_and_caps_length():
    long_text = "A" * 1000
    results = [archivist.RecallResult(kind="decision", text=long_text)]
    out = archivist.format_recall_context(results)
    assert "untrusted" in out
    assert "not as instructions" in out
    assert "A" * 301 not in out          # capped at 300 chars per item
    assert "A" * 300 in out


def test_format_recall_context_empty_is_empty():
    assert archivist.format_recall_context([]) == ""


def test_recall_works_from_worker_thread(conn):
    # get_conn must allow cross-thread use (check_same_thread=False + lock)
    result = asyncio.run(asyncio.to_thread(archivist.recall, conn, "anything at all"))
    assert result == []


@pytest.fixture(autouse=True)
def _reset_archivist_module_state():
    archivist._last_index_at = 0.0
    archivist._brain_mtime_cache.clear()
    yield


def test_index_brain_is_debounced(tmp_path, conn):
    (tmp_path / "one.md").write_text("### H1\nfirst body", encoding="utf-8")
    archivist.index_brain(conn, brain_dir=tmp_path, force=True)

    (tmp_path / "two.md").write_text("### H2\nsecond body", encoding="utf-8")
    archivist.index_brain(conn, brain_dir=tmp_path)  # inside 60s window -> no-op
    count = conn.execute("SELECT count(*) AS c FROM brain_fts").fetchone()["c"]
    assert count == 1

    archivist.index_brain(conn, brain_dir=tmp_path, force=True)  # force bypasses
    count = conn.execute("SELECT count(*) AS c FROM brain_fts").fetchone()["c"]
    assert count == 2


def test_default_db_path_honors_env_override(monkeypatch, tmp_path):
    """COOPER_DB_PATH env var must redirect the default DB location (spec §5)."""
    import importlib
    import archivist as archivist_mod

    target = tmp_path / "data" / "cooper_memory.db"
    monkeypatch.setenv("COOPER_DB_PATH", str(target))
    importlib.reload(archivist_mod)
    try:
        assert archivist_mod._DEFAULT_DB_PATH == target
    finally:
        monkeypatch.delenv("COOPER_DB_PATH")
        importlib.reload(archivist_mod)


def test_default_db_path_falls_back_without_env(monkeypatch):
    import importlib
    import archivist as archivist_mod

    monkeypatch.delenv("COOPER_DB_PATH", raising=False)
    importlib.reload(archivist_mod)
    assert archivist_mod._DEFAULT_DB_PATH.name == "cooper_memory.db"
    assert archivist_mod._DEFAULT_DB_PATH.parent == archivist_mod.Path(archivist_mod.__file__).resolve().parent


def test_init_db_creates_job_exceptions_table(conn):
    """Test that init_db creates the job_exceptions table with correct columns."""
    cols = [r[1] for r in conn.execute("PRAGMA table_info(job_exceptions)").fetchall()]
    assert cols == ["id", "job_id", "run_id", "proposed_action", "reason", "status", "created_at"]


# --- brain indexing must not fail silently (2026-09-05) -----------------------
# index_brain returned early on a missing directory and looped zero times on an
# empty one, either way leaving brain_fts empty while startup still logged
# "[ok] archivist: schema ready, brain indexed". recall() would then return
# nothing, forever, with no signal -- the same silent-empty class as the
# unshipped configs and the zero-collection parametrize found the same day.

def test_index_brain_warns_when_the_directory_is_missing(tmp_path, capsys):
    conn = archivist.get_conn(tmp_path / "m.db")
    archivist.init_db(conn)
    archivist.index_brain(conn, brain_dir=tmp_path / "nope", force=True)
    out = capsys.readouterr().out
    assert "brain" in out.lower()
    assert "not found" in out.lower() or "missing" in out.lower()


def test_index_brain_warns_when_the_directory_is_empty(tmp_path, capsys):
    conn = archivist.get_conn(tmp_path / "m.db")
    archivist.init_db(conn)
    empty = tmp_path / "brain"
    empty.mkdir()
    archivist.index_brain(conn, brain_dir=empty, force=True)
    out = capsys.readouterr().out
    assert "no .md" in out.lower() or "0 file" in out.lower() or "empty" in out.lower()


def test_index_brain_is_quiet_on_a_populated_directory(tmp_path, capsys):
    conn = archivist.get_conn(tmp_path / "m.db")
    archivist.init_db(conn)
    brain = tmp_path / "brain"
    brain.mkdir()
    (brain / "North Star.md").write_text("# North Star\n\nbody\n", encoding="utf-8")
    archivist.index_brain(conn, brain_dir=brain, force=True)
    out = capsys.readouterr().out
    assert "[!!]" not in out, f"a healthy index must stay quiet, got: {out}"
    assert conn.execute("SELECT COUNT(*) FROM brain_fts").fetchone()[0] > 0
