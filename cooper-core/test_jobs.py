import asyncio
import json
from pathlib import Path

import pytest
import yaml

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


# ── PII research helpers (Step 14c) ──────────────────────────────────────
def _write_queries(tmp_path, queries, next_index=0):
    path = tmp_path / "Config" / "pii_research_queries.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"queries": queries, "next_index": next_index}), encoding="utf-8")
    return path


def test_next_seed_query_returns_query_at_index_and_advances(tmp_path):
    path = _write_queries(tmp_path, ["alpha", "beta", "gamma"], next_index=0)

    assert jobs.next_seed_query(path) == "alpha"
    assert json.loads(path.read_text())["next_index"] == 1
    assert jobs.next_seed_query(path) == "beta"
    assert json.loads(path.read_text())["next_index"] == 2


def test_next_seed_query_wraps_at_end_of_list(tmp_path):
    path = _write_queries(tmp_path, ["alpha", "beta"], next_index=1)

    assert jobs.next_seed_query(path) == "beta"
    assert json.loads(path.read_text())["next_index"] == 0
    assert jobs.next_seed_query(path) == "alpha"


def test_next_seed_query_recovers_from_out_of_range_index(tmp_path):
    path = _write_queries(tmp_path, ["alpha", "beta"], next_index=99)
    assert jobs.next_seed_query(path) == "alpha"


def test_next_seed_query_raises_when_no_queries_configured(tmp_path):
    path = _write_queries(tmp_path, [])
    with pytest.raises(jobs.JobError, match="no seed queries"):
        jobs.next_seed_query(path)


def test_next_seed_query_raises_when_file_missing(tmp_path):
    with pytest.raises(jobs.JobError, match="no seed queries"):
        jobs.next_seed_query(tmp_path / "nope.json")


def test_existing_entry_sites_extracts_recorded_names(tmp_path):
    note = tmp_path / "note.md"
    note.write_text(
        "# Data Brokers\n\n"
        "**Site:** Acme Data\n**Collects:** emails\n**Source:** https://a.example\n\n"
        "**Site:** Beta Corp\n**Collects:** addresses\n**Source:** https://b.example\n",
        encoding="utf-8",
    )
    assert jobs.existing_entry_sites(note) == ["Acme Data", "Beta Corp"]


def test_existing_entry_sites_returns_empty_for_missing_file(tmp_path):
    assert jobs.existing_entry_sites(tmp_path / "absent.md") == []


def test_existing_entry_sites_returns_empty_for_unparseable_note(tmp_path):
    note = tmp_path / "note.md"
    note.write_text("free-form prose with no entries at all\n", encoding="utf-8")
    assert jobs.existing_entry_sites(note) == []


def test_format_pii_entries_renders_all_fields(tmp_path):
    block = jobs.format_pii_entries(
        [{"site": "Acme Data", "what_it_collects": "emails", "source_url": "https://a.example"}],
        "2026-09-04",
    )
    assert "**Site:** Acme Data" in block
    assert "**Collects:** emails" in block
    assert "**Source:** https://a.example" in block
    assert "**Found:** 2026-09-04" in block


def test_format_pii_entries_returns_empty_string_for_no_entries():
    assert jobs.format_pii_entries([], "2026-09-04") == ""


# ── pii_research job branch (Step 14c) ───────────────────────────────────
PII_JOB = {
    "id": "data-broker-research",
    "job_type": "pii_research",
    "workshop": "open",
    "schedule_hint": "daily, randomized 00:00-06:00",
    "steps": ["web_search", "pii_extract", "note_append"],
    "read_scope": ["Obsidian Vault/02_Projects/opt-out/Data-Brokers.md"],
    "write_scope": ["Obsidian Vault/02_Projects/opt-out/Data-Brokers.md"],
    "quota": {"queries_per_run": 1, "entries_per_run": 5},
    "permission_level": 3,
    "approved": True,
}


def _approved_pii_job(**overrides):
    entry = {**PII_JOB, **overrides}
    entry["envelope_hash"] = jobs.compute_envelope_hash(entry)
    return entry


def _fake_search(results):
    async def _inner(query, max_results=10):
        _inner.query = query
        return results
    return _inner


def _fake_extract(entries):
    async def _inner(query, results, existing_sites, **kw):
        _inner.existing_sites = existing_sites
        return entries
    return _inner


def _setup_pii(tmp_path, monkeypatch, *, search_results, extracted, note_text=None):
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(jobs.council, "final_review", _fake_final_review)
    queries = _write_queries(tmp_path, ["data broker opt out list"])
    monkeypatch.setattr(jobs, "_QUERIES_PATH", queries)
    search = _fake_search(search_results)
    extract = _fake_extract(extracted)
    monkeypatch.setattr(jobs.executor, "_run_web_search", search)
    monkeypatch.setattr(jobs, "extract_pii_entries", extract)
    note = tmp_path / "Obsidian Vault" / "02_Projects" / "opt-out" / "Data-Brokers.md"
    if note_text is not None:
        note.parent.mkdir(parents=True, exist_ok=True)
        note.write_text(note_text, encoding="utf-8")
    return note, search, extract


def test_run_job_pii_research_appends_entry_and_writes_evidence(conn, tmp_path, monkeypatch):
    note, search, _ = _setup_pii(
        tmp_path, monkeypatch,
        search_results=[{"title": "Acme", "url": "https://a.example", "snippet": "sells data"}],
        extracted=[{"site": "Acme Data", "what_it_collects": "emails",
                    "source_url": "https://a.example"}],
    )
    job_entry = _approved_pii_job()
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})

    result = asyncio.run(jobs.run_job("data-broker-research", conn, **_RUN_JOB_KWARGS))

    assert result["status"] == "completed"
    assert result["entries_added"] == 1
    assert result["results_found"] == 1
    assert result["query"] == "data broker opt out list"
    assert search.query == "data broker opt out list"

    text = note.read_text(encoding="utf-8")
    assert "**Site:** Acme Data" in text
    assert "**Source:** https://a.example" in text

    record = json.loads(Path(result["evidence_path"]).read_text(encoding="utf-8"))
    assert record["job_id"] == "data-broker-research"
    assert record["run_id"] == result["run_id"]
    assert evidence.validate_completion(record, []) == []


def test_run_job_pii_research_passes_existing_sites_for_dedupe(conn, tmp_path, monkeypatch):
    _, _, extract = _setup_pii(
        tmp_path, monkeypatch,
        search_results=[{"title": "B", "url": "https://b.example", "snippet": "x"}],
        extracted=[],
        note_text="**Site:** Acme Data\n**Collects:** emails\n**Source:** https://a.example\n",
    )
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [_approved_pii_job()]})

    asyncio.run(jobs.run_job("data-broker-research", conn, **_RUN_JOB_KWARGS))

    assert extract.existing_sites == ["Acme Data"]


def test_run_job_pii_research_zero_findings_is_a_successful_run(conn, tmp_path, monkeypatch):
    note, _, _ = _setup_pii(
        tmp_path, monkeypatch,
        search_results=[{"title": "B", "url": "https://b.example", "snippet": "x"}],
        extracted=[],
    )
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [_approved_pii_job()]})

    result = asyncio.run(jobs.run_job("data-broker-research", conn, **_RUN_JOB_KWARGS))

    assert result["status"] == "completed"
    assert result["entries_added"] == 0
    assert not note.exists()
    record = json.loads(Path(result["evidence_path"]).read_text(encoding="utf-8"))
    assert evidence.validate_completion(record, []) == []


def test_run_job_pii_research_caps_entries_at_quota(conn, tmp_path, monkeypatch):
    note, _, _ = _setup_pii(
        tmp_path, monkeypatch,
        search_results=[{"title": "R", "url": "https://r.example", "snippet": "x"}],
        extracted=[
            {"site": f"Broker {i}", "what_it_collects": "data",
             "source_url": f"https://{i}.example"}
            for i in range(9)
        ],
    )
    monkeypatch.setattr(
        jobs, "load_registry",
        lambda path=None: {"jobs": [_approved_pii_job(
            quota={"queries_per_run": 1, "entries_per_run": 3})]},
    )

    result = asyncio.run(jobs.run_job("data-broker-research", conn, **_RUN_JOB_KWARGS))

    assert result["entries_added"] == 3
    assert note.read_text(encoding="utf-8").count("**Site:**") == 3


def test_run_job_pii_research_queues_exception_for_out_of_scope_write(conn, tmp_path, monkeypatch):
    _setup_pii(
        tmp_path, monkeypatch,
        search_results=[{"title": "A", "url": "https://a.example", "snippet": "x"}],
        extracted=[{"site": "Acme", "what_it_collects": "emails",
                    "source_url": "https://a.example"}],
    )
    job_entry = _approved_pii_job(write_scope=["State/SomewhereElse.md"])
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})

    result = asyncio.run(jobs.run_job("data-broker-research", conn, **_RUN_JOB_KWARGS))

    assert result["status"] == "completed"
    assert result["exceptions_raised"] == 1
    assert len(jobs.list_exceptions(conn, status="pending")) == 1


def test_run_job_pii_research_surfaces_search_failure_without_crashing(conn, tmp_path, monkeypatch):
    _setup_pii(tmp_path, monkeypatch, search_results=[], extracted=[])

    async def _boom(query, max_results=10):
        raise executor.ExecutionError("searxng unreachable")

    monkeypatch.setattr(jobs.executor, "_run_web_search", _boom)
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [_approved_pii_job()]})

    result = asyncio.run(jobs.run_job("data-broker-research", conn, **_RUN_JOB_KWARGS))

    assert result["status"] == "failed"
    assert "searxng unreachable" in result["reason"]
    record = json.loads(Path(result["evidence_path"]).read_text(encoding="utf-8"))
    assert record["status"] == "failed"
    assert evidence.validate_completion(record, []) == []


def test_run_job_data_broker_research_failed_extraction_writes_valid_evidence(conn, tmp_path, monkeypatch):
    """An extraction backend failure must still produce a SCHEMA-VALID evidence record —
    an honest failure has to be recordable.

    Deliberately does NOT monkeypatch jobs.extract_pii_entries away (that would bypass
    the exact code under review — its JobError message wording — and the test would
    pass unconditionally). Instead it drives the REAL extract_pii_entries by making the
    underlying backend call raise, so the assembled failure message actually flows
    through run_job into the evidence record's notes/verdicts fields, where
    evidence._sensitive_errors scans it."""
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(jobs.council, "final_review", _fake_final_review)
    queries = _write_queries(tmp_path, ["data broker opt out list"])
    monkeypatch.setattr(jobs, "_QUERIES_PATH", queries)
    monkeypatch.setattr(
        jobs.executor, "_run_web_search",
        _fake_search([{"title": "A", "url": "https://a.example", "snippet": "x"}]),
    )

    async def boom_backend(*a, **k):
        raise RuntimeError("429 rate limited")

    monkeypatch.setattr(jobs, "_ollama_complete", boom_backend)
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [_approved_pii_job()]})

    result = asyncio.run(jobs.run_job("data-broker-research", conn, **_RUN_JOB_KWARGS))

    assert result["status"] == "failed"
    record = json.loads(Path(result["evidence_path"]).read_text(encoding="utf-8"))
    assert record["status"] == "failed"
    assert evidence.validate_completion(record, []) == []      # the actual regression guard


def test_run_job_data_broker_research_refuses_to_overwrite_unreadable_note(conn, tmp_path, monkeypatch):
    """A note that exists with real prior content, but can't be decoded as UTF-8 (e.g.
    hand-edited/pasted from a Windows source and saved Latin-1), must be refused and
    queued as an exception — NOT fail open to an empty base, which would make the
    write below a silent full overwrite and destroy every prior entry while still
    reporting 'completed'. The prior bytes on disk must be byte-for-byte unchanged."""
    note, _, _ = _setup_pii(
        tmp_path, monkeypatch,
        search_results=[{"title": "A", "url": "https://a.example", "snippet": "x"}],
        extracted=[{"site": "Acme", "what_it_collects": "emails",
                    "source_url": "https://a.example"}],
    )
    note.parent.mkdir(parents=True, exist_ok=True)
    prior_bytes = "**Site:** OldBroker Café\n**Collects:** emails\n**Source:** https://old.example\n".encode("latin-1")
    note.write_bytes(prior_bytes)
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [_approved_pii_job()]})

    result = asyncio.run(jobs.run_job("data-broker-research", conn, **_RUN_JOB_KWARGS))

    assert result["status"] == "completed"
    assert result["entries_added"] == 0
    assert result["exceptions_raised"] == 1
    pending = jobs.list_exceptions(conn, status="pending")
    assert len(pending) == 1
    assert "data-broker-research" == pending[0]["job_id"]
    # The actual regression guard: the prior note content must be untouched, byte
    # for byte -- not decoded, not re-encoded, not replaced with new-only content.
    assert note.read_bytes() == prior_bytes


def test_run_job_still_runs_csv_link_check_by_default(conn, tmp_path, monkeypatch):
    """An entry with no job_type field keeps the 14b behavior — no silent break."""
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(jobs.council, "final_review", _fake_final_review)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [("https://a.example", "", "", "")])
    job_entry = _approved_job()
    assert "job_type" not in job_entry
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify(reachable=True))

    result = asyncio.run(jobs.run_job("link-checker", conn, **_RUN_JOB_KWARGS))

    assert result["status"] == "completed"
    assert result["rows_checked"] == 1


def test_extract_pii_entries_drops_entries_missing_required_fields():
    async def fake_backend(*a, **k):
        return json.dumps({"entries": [
            {"site": "Good", "what_it_collects": "emails", "source_url": "https://g.example"},
            {"site": "No URL", "what_it_collects": "emails"},
            {"what_it_collects": "emails", "source_url": "https://n.example"},
        ]})

    entries = asyncio.run(jobs.extract_pii_entries(
        "q", [{"title": "t", "url": "https://g.example", "snippet": "s"}], [],
        base_url="", api_key="", model="m", backend="ollama", complete_fn=fake_backend,
    ))
    assert entries == [
        {"site": "Good", "what_it_collects": "emails", "source_url": "https://g.example"}
    ]


def test_extract_pii_entries_drops_sites_already_recorded():
    async def fake_backend(*a, **k):
        return json.dumps({"entries": [
            {"site": "Acme Data", "what_it_collects": "emails", "source_url": "https://a.example"},
            {"site": "Fresh Co", "what_it_collects": "phones", "source_url": "https://f.example"},
        ]})

    entries = asyncio.run(jobs.extract_pii_entries(
        "q", [{"title": "t", "url": "https://a.example", "snippet": "s"}], ["acme data"],
        base_url="", api_key="", model="m", backend="ollama", complete_fn=fake_backend,
    ))
    assert [e["site"] for e in entries] == ["Fresh Co"]


def test_extract_pii_entries_flattens_newlines_that_would_forge_an_entry():
    """A site name carrying a newline + a second '**Site:**' marker must not be able
    to forge an extra entry in the vault note (untrusted-content injection vector)."""
    async def fake_backend(*a, **k):
        return json.dumps({"entries": [
            {"site": "Acme Data\n**Site:** Phantom Broker",
             "what_it_collects": "emails", "source_url": "https://a.example"},
        ]})

    entries = asyncio.run(jobs.extract_pii_entries(
        "q", [{"title": "t", "url": "https://a.example", "snippet": "s"}], [],
        base_url="", api_key="", model="m", backend="ollama", complete_fn=fake_backend,
    ))
    assert len(entries) == 1
    assert "\n" not in entries[0]["site"]
    block = jobs.format_pii_entries(entries, "2026-09-04")
    assert len(jobs._PII_SITE_RE.findall(block)) == 1


def test_extract_pii_entries_raises_job_error_on_backend_failure():
    async def boom(*a, **k):
        raise RuntimeError("429 rate limited")

    with pytest.raises(jobs.JobError, match="429"):
        asyncio.run(jobs.extract_pii_entries(
            "q", [{"title": "t", "url": "https://a.example", "snippet": "s"}], [],
            base_url="", api_key="", model="m", backend="ollama", complete_fn=boom,
        ))


def test_extract_pii_entries_returns_empty_without_calling_backend_on_no_results():
    async def must_not_run(*a, **k):
        raise AssertionError("backend must not be called when there are no results")

    entries = asyncio.run(jobs.extract_pii_entries(
        "q", [], [], base_url="", api_key="", model="m",
        backend="ollama", complete_fn=must_not_run,
    ))
    assert entries == []
