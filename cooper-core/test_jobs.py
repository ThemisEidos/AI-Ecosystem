import asyncio
import json
from pathlib import Path

import pytest

import archivist
import evidence
import executor
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
    # Matches the fixture convention used by test_archivist.py / test_proposer.py:
    # archivist.get_conn() + archivist.init_db() against a real in-memory DB, so this
    # test can't drift from the real schema.
    c = archivist.get_conn(db_path=":memory:")
    archivist.init_db(c)
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


# ── run_job orchestration (Task 6) ──────────────────────────────────────────

def _approved_job(**overrides):
    """A link-checker-shaped job entry, approved with a matching envelope_hash
    computed AFTER overrides so a test can freely reshape read_scope/write_scope/
    quota and still get a hash that verify_job accepts."""
    entry = {
        "id": "link-checker",
        "workshop": "open",
        "schedule_hint": "daily 03:00",
        "steps": ["csv_next_rows", "url_verify", "csv_line_edit"],
        "read_scope": ["State/LinkAudit/links.csv"],
        "write_scope": ["State/LinkAudit/links.csv"],
        "quota": {"rows_per_run": 10, "fetches_per_run": 30},
        "permission_level": 3,
        "approved": True,
    }
    entry.update(overrides)
    entry["envelope_hash"] = jobs.compute_envelope_hash(entry)
    return entry


def _write_links_csv(path: Path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ["url,last_checked,status,notes"]
    for url, last_checked, status, notes in rows:
        lines.append(f"{url},{last_checked},{status},{notes}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _fake_url_verify(reachable=True, content_changed=None):
    def _fn(url, expected_hash):
        return {
            "url": url,
            "reachable": reachable,
            "status_code": 200 if reachable else None,
            "content_changed": content_changed,
            "checked_at": "2026-08-30T00:00:00Z",
        }
    return _fn


def test_run_job_refuses_unapproved_job(conn, tmp_path, monkeypatch):
    registry = {"jobs": [{**MINIMAL_JOB, "approved": False, "id": "link-checker"}]}
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: registry)
    result = asyncio.run(jobs.run_job("link-checker", conn))
    assert result["status"] == "refused"
    assert "not approved" in result["reason"].lower()


def test_run_job_refuses_unknown_job_id(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": []})
    result = asyncio.run(jobs.run_job("does-not-exist", conn))
    assert result["status"] == "refused"


def test_run_job_enqueues_exception_for_out_of_scope_write(conn, tmp_path, monkeypatch):
    # write_scope deliberately does NOT include the CSV path read_scope/csv_next_rows
    # will actually target, so the csv_line_edit -> _run_file_edit call must raise
    # ExecutionError, and run_job must catch it (not raise, not silently succeed).
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    original = "url,last_checked,status,notes\nhttps://a.example,,,\n"
    _write_links_csv(csv_path, [("https://a.example", "", "", "")])
    on_disk_before = csv_path.read_text()

    job_entry = _approved_job(write_scope=["State/LinkAudit/other.csv"])
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify())

    result = asyncio.run(jobs.run_job("link-checker", conn))

    assert result["status"] == "completed"
    assert result["exceptions_raised"] == 1
    pending = jobs.list_exceptions(conn, status="pending")
    assert len(pending) == 1
    assert pending[0]["job_id"] == "link-checker"
    # The file was NOT written.
    assert csv_path.read_text() == on_disk_before


def test_run_job_full_success_writes_csv_and_evidence(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [
        ("https://a.example", "", "", ""),
        ("https://b.example", "", "", ""),
    ])

    job_entry = _approved_job()
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify(reachable=True))

    result = asyncio.run(jobs.run_job("link-checker", conn))

    assert result["status"] == "completed"
    assert result["rows_checked"] == 2
    assert result["exceptions_raised"] == 0
    assert jobs.list_exceptions(conn, status="pending") == []

    updated = csv_path.read_text()
    assert "url,last_checked,status,notes" in updated
    assert ",,,\n" not in updated  # both rows got last_checked/status filled in

    evidence_path = Path(result["evidence_path"])
    assert evidence_path.exists()
    record = json.loads(evidence_path.read_text(encoding="utf-8"))
    assert record["job_id"] == "link-checker"
    assert record["run_id"] == result["run_id"]
    assert record["envelope_hash"] == job_entry["envelope_hash"]
    errs = evidence.validate_completion(record, [])
    assert errs == []


def test_run_job_respects_rows_per_run_quota(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [
        ("https://a.example", "", "", ""),
        ("https://b.example", "", "", ""),
        ("https://c.example", "", "", ""),
    ])

    job_entry = _approved_job(quota={"rows_per_run": 2, "fetches_per_run": 30})
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify(reachable=True))

    result = asyncio.run(jobs.run_job("link-checker", conn))

    assert result["status"] == "completed"
    assert result["rows_checked"] == 2

    updated = csv_path.read_text()
    # third row untouched — still no last_checked/status.
    assert "https://c.example,,," in updated.replace("\r", "")


def test_run_job_caps_fetches_at_fetches_per_run_quota(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [
        ("https://a.example", "", "", ""),
        ("https://b.example", "", "", ""),
        ("https://c.example", "", "", ""),
    ])

    job_entry = _approved_job(quota={"rows_per_run": 10, "fetches_per_run": 1})
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify(reachable=True))

    result = asyncio.run(jobs.run_job("link-checker", conn))

    assert result["status"] == "completed"
    assert result["rows_checked"] == 1


def test_run_job_counts_rows_changed(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [("https://a.example", "", "", "")])

    job_entry = _approved_job()
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify(reachable=True, content_changed=True))

    result = asyncio.run(jobs.run_job("link-checker", conn))
    assert result["rows_changed"] == 1
