import asyncio
import json
from pathlib import Path

import pytest

import archivist
import council
import evidence
import executor
import jobs


async def _fake_final_review(*a, **k):
    return [{"member": "test-reviewer", "verdict": "pass", "reason": "ok"}]


_RUN_JOB_KWARGS = dict(
    base_url="http://test", api_key="test-key", backend="ollama",
    workshop="open", reviewer_model="test-reviewer-model",
)


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


def test_write_job_evidence_includes_verdicts():
    job_entry = _approved_job()
    verdicts = [{"member": "openai", "verdict": "pass", "reason": "ok"}]
    path = jobs.write_job_evidence(
        job_id="link-checker", run_id="run-1", job_entry=job_entry,
        status="completed", artifact_paths=["State/LinkAudit/links.csv"],
        notes="test run", verdicts=verdicts,
    )
    record = json.loads(path.read_text(encoding="utf-8"))
    assert record["verdicts"] == verdicts
    path.unlink()


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
    result = asyncio.run(jobs.run_job("link-checker", conn, **_RUN_JOB_KWARGS))
    assert result["status"] == "refused"
    assert "not approved" in result["reason"].lower()


def test_run_job_refuses_unknown_job_id(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": []})
    result = asyncio.run(jobs.run_job("does-not-exist", conn, **_RUN_JOB_KWARGS))
    assert result["status"] == "refused"


def test_run_job_enqueues_exception_for_out_of_scope_write(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(jobs.council, "final_review", _fake_final_review)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [("https://a.example", "", "", "")])
    on_disk_before = csv_path.read_text()

    job_entry = _approved_job(write_scope=["State/LinkAudit/other.csv"])
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify())

    result = asyncio.run(jobs.run_job("link-checker", conn, **_RUN_JOB_KWARGS))

    assert result["status"] == "completed"
    assert result["exceptions_raised"] == 1
    pending = jobs.list_exceptions(conn, status="pending")
    assert len(pending) == 1
    assert pending[0]["job_id"] == "link-checker"
    assert csv_path.read_text() == on_disk_before


def test_run_job_full_success_writes_csv_and_evidence(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(jobs.council, "final_review", _fake_final_review)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [
        ("https://a.example", "", "", ""),
        ("https://b.example", "", "", ""),
    ])

    job_entry = _approved_job()
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify(reachable=True))

    result = asyncio.run(jobs.run_job("link-checker", conn, **_RUN_JOB_KWARGS))

    assert result["status"] == "completed"
    assert result["rows_checked"] == 2
    assert result["exceptions_raised"] == 0
    assert jobs.list_exceptions(conn, status="pending") == []

    updated = csv_path.read_text()
    assert "url,last_checked,status,notes" in updated
    assert ",,,\n" not in updated

    evidence_path = Path(result["evidence_path"])
    assert evidence_path.exists()
    record = json.loads(evidence_path.read_text(encoding="utf-8"))
    assert record["job_id"] == "link-checker"
    assert record["run_id"] == result["run_id"]
    assert record["envelope_hash"] == job_entry["envelope_hash"]
    assert record["verdicts"] == [{"member": "test-reviewer", "verdict": "pass", "reason": "ok"}]
    errs = evidence.validate_completion(record, [])
    assert errs == []


def test_run_job_council_tier_produces_named_per_member_verdicts(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)

    async def fake_council_final_review(job_entry, workshop, message, raw_output, **kw):
        assert council.needs_council_tier(job_entry)  # link-checker writes files -> council tier
        return [
            {"member": "openai", "verdict": "pass", "reason": "ok"},
            {"member": "claude", "verdict": "pass", "reason": "ok"},
            {"member": "gemini", "verdict": "pass", "reason": "ok"},
        ]

    monkeypatch.setattr(jobs.council, "final_review", fake_council_final_review)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [("https://a.example", "", "", "")])

    job_entry = _approved_job()
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify(reachable=True))

    result = asyncio.run(jobs.run_job("link-checker", conn, **_RUN_JOB_KWARGS))

    record = json.loads(Path(result["evidence_path"]).read_text(encoding="utf-8"))
    assert len(record["verdicts"]) == 3
    assert {v["member"] for v in record["verdicts"]} == {"openai", "claude", "gemini"}
    errs = evidence.validate_completion(record, [])
    assert errs == []


def test_run_job_respects_rows_per_run_quota(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(jobs.council, "final_review", _fake_final_review)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [
        ("https://a.example", "", "", ""),
        ("https://b.example", "", "", ""),
        ("https://c.example", "", "", ""),
    ])

    job_entry = _approved_job(quota={"rows_per_run": 2, "fetches_per_run": 30})
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify(reachable=True))

    result = asyncio.run(jobs.run_job("link-checker", conn, **_RUN_JOB_KWARGS))

    assert result["status"] == "completed"
    assert result["rows_checked"] == 2

    updated = csv_path.read_text()
    assert "https://c.example,,," in updated.replace("\r", "")


def test_run_job_caps_fetches_at_fetches_per_run_quota(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(jobs.council, "final_review", _fake_final_review)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [
        ("https://a.example", "", "", ""),
        ("https://b.example", "", "", ""),
        ("https://c.example", "", "", ""),
    ])

    job_entry = _approved_job(quota={"rows_per_run": 10, "fetches_per_run": 1})
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify(reachable=True))

    result = asyncio.run(jobs.run_job("link-checker", conn, **_RUN_JOB_KWARGS))

    assert result["status"] == "completed"
    assert result["rows_checked"] == 1


# ── write_digest (Task 7) ────────────────────────────────────────────────────

def test_write_digest_includes_todays_job_runs_and_pending_exceptions(conn, tmp_path, monkeypatch):
    import datetime

    monkeypatch.setattr(jobs, "_EVIDENCE_DIR", tmp_path / "evidence")
    monkeypatch.setattr(jobs, "_DIGEST_DIR", tmp_path / "inbox")
    (tmp_path / "evidence").mkdir()
    (tmp_path / "inbox").mkdir()

    today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    evidence_record = {
        "workflow_id": "link-checker",
        "workflow_name": "link-checker",
        "execution_id": "20260830T000000000Z",
        "status": "completed",
        "completion_time": f"{today}T00:00:00.000000Z",
        "workshop_id": "open",
        "workshop_name": "Open Workshop",
        "approval_id": "",
        "artifact_paths": ["State/LinkAudit/links.csv"],
        "review_status": "unknown",
        "user_accepted": False,
        "notes": "run_id=run-1: checked 2 row(s), 1 changed, 2 fetch(es) used.",
        "job_id": "link-checker",
        "envelope_hash": "abc123",
        "run_id": "run-1",
    }
    (tmp_path / "evidence" / "workflow_completion_link-checker_20260830T000000000Z.json").write_text(
        json.dumps(evidence_record), encoding="utf-8"
    )
    # A non-job-linked completion record (no job_id) must not appear as a job run.
    (tmp_path / "evidence" / "workflow_completion_other_20260830T010000000Z.json").write_text(
        json.dumps({**evidence_record, "job_id": "", "workflow_id": "manual-thing"}),
        encoding="utf-8",
    )

    # write one fake today-dated job evidence record + one pending exception, then:
    jobs.enqueue_exception(conn, "link-checker", "run-1", "action", "reason")
    path = jobs.write_digest(conn)
    text = path.read_text()
    assert "link-checker" in text
    assert "reason" in text
    assert "manual-thing" not in text
    assert path.name == f"COOPER-Digest-{today}.md"


def test_write_digest_is_idempotent_per_day(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_EVIDENCE_DIR", tmp_path / "evidence")
    monkeypatch.setattr(jobs, "_DIGEST_DIR", tmp_path / "inbox")
    (tmp_path / "evidence").mkdir()
    (tmp_path / "inbox").mkdir()

    jobs.write_digest(conn)
    jobs.enqueue_exception(conn, "link-checker", "run-2", "action", "second run")
    path_two = jobs.write_digest(conn)

    files = list((tmp_path / "inbox").glob("COOPER-Digest-*.md"))
    assert len(files) == 1
    assert "second run" in path_two.read_text()


def test_run_job_counts_rows_changed(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(jobs.council, "final_review", _fake_final_review)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [("https://a.example", "", "", "")])

    job_entry = _approved_job()
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify(reachable=True, content_changed=True))

    result = asyncio.run(jobs.run_job("link-checker", conn, **_RUN_JOB_KWARGS))
    assert result["rows_changed"] == 1


def test_write_critique_note_reports_objection(tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_DIGEST_DIR", tmp_path / "inbox")
    verdicts = [
        {"member": "openai", "verdict": "pass", "reason": "looks fine"},
        {"member": "claude", "verdict": "flag", "reason": "write_scope too broad"},
    ]
    path = jobs.write_critique_note("test-job", verdicts, "deadbeef")
    assert path.exists()
    text = path.read_text(encoding="utf-8")
    assert "test-job" in text
    assert "OBJECTION" in text
    assert "claude" in text and "write_scope too broad" in text


def test_write_critique_note_reports_clear_when_all_pass(tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_DIGEST_DIR", tmp_path / "inbox")
    verdicts = [{"member": "openai", "verdict": "pass", "reason": "fine"}]
    path = jobs.write_critique_note("test-job", verdicts, "deadbeef")
    text = path.read_text(encoding="utf-8")
    assert "clear" in text.lower()
    assert "OBJECTION" not in text


def test_write_critique_note_includes_envelope_hash(tmp_path, monkeypatch):
    """Finding 3 (15d final review): the note must carry the envelope hash it
    was critiqued against, so the owner can tell a stale note (hash doesn't
    match the current envelope) from a fresh one."""
    monkeypatch.setattr(jobs, "_DIGEST_DIR", tmp_path / "inbox")
    verdicts = [{"member": "openai", "verdict": "pass", "reason": "fine"}]
    path = jobs.write_critique_note("test-job", verdicts, "abc123deadbeef")
    text = path.read_text(encoding="utf-8")
    assert "abc123deadbeef" in text


def test_run_job_council_final_review_fail_open(conn, tmp_path, monkeypatch):
    """Finding 1 (15d final review): a council.final_review exception must not
    lose the run's evidence record -- CSV writes / exception-queue inserts
    already happened by that point. Fail open with a non-empty fallback
    verdicts list, don't let run_job raise."""
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)

    async def boom_final_review(*a, **k):
        raise RuntimeError("model_routing.load_routing: truncated JSON")

    monkeypatch.setattr(jobs.council, "final_review", boom_final_review)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [("https://a.example", "", "", "")])

    job_entry = _approved_job()
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify(reachable=True))

    result = asyncio.run(jobs.run_job("link-checker", conn, **_RUN_JOB_KWARGS))

    assert result["status"] == "completed"
    record = json.loads(Path(result["evidence_path"]).read_text(encoding="utf-8"))
    assert isinstance(record["verdicts"], list) and len(record["verdicts"]) > 0
    fallback = record["verdicts"][0]
    assert fallback["member"] == "council"
    assert fallback["verdict"] == "flag"
    assert "model_routing.load_routing: truncated JSON" in fallback["reason"]
    errs = evidence.validate_completion(record, [])
    assert errs == []
