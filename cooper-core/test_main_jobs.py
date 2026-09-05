"""main.py jobs wiring: POST /jobs/run/{job_id} (Step 14b Task 6)."""
import os
from pathlib import Path

os.environ.setdefault("WORKSHOP", "open")
os.environ.setdefault("COOPER_ALLOW_ANON", "1")
os.environ.pop("COOPER_API_KEY", None)

from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402


def test_post_jobs_run_returns_run_job_result(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main, "_ALLOW_ANON", True)
    monkeypatch.setattr(main.jobs, "get_job", lambda job_id, registry=None: {"id": job_id})

    async def fake_run_job(job_id, conn, **kwargs):
        assert job_id == "link-checker"
        assert conn is main._ARCHIVIST_CONN
        assert kwargs == {
            "base_url": main.BACKEND_URL, "api_key": main.BACKEND_KEY,
            "backend": main.BACKEND, "workshop": main.WORKSHOP,
            "reviewer_model": main.REVIEWER_MODEL, "drafter_model": main.DRAFTER_MODEL,
        }
        return {
            "status": "completed",
            "run_id": "abc123",
            "rows_checked": 2,
            "rows_changed": 0,
            "exceptions_raised": 0,
            "fetches_used": 2,
            "fetches_capped": False,
            "evidence_path": "/tmp/fake.json",
        }

    monkeypatch.setattr(main.jobs, "run_job", fake_run_job)
    digest_calls = []
    monkeypatch.setattr(
        main.jobs, "write_digest", lambda conn: digest_calls.append(conn) or "/tmp/fake-digest.md"
    )

    with TestClient(main.app) as client:
        resp = client.post("/jobs/run/link-checker")

    assert digest_calls == [main._ARCHIVIST_CONN]

    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "completed"
    assert body["run_id"] == "abc123"
    assert body["rows_checked"] == 2


def test_post_jobs_run_404s_for_unknown_job(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main, "_ALLOW_ANON", True)
    monkeypatch.setattr(main.jobs, "get_job", lambda job_id, registry=None: None)

    with TestClient(main.app) as client:
        resp = client.post("/jobs/run/does-not-exist")

    assert resp.status_code == 404


def test_post_jobs_run_requires_auth(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", {"secret-key"})
    monkeypatch.setattr(main, "_ALLOW_ANON", False)

    with TestClient(main.app) as client:
        resp = client.post("/jobs/run/link-checker")

    assert resp.status_code == 401


def test_critique_endpoint_returns_objection_and_writes_note(monkeypatch, tmp_path):
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main, "_ALLOW_ANON", True)
    monkeypatch.setattr(main.jobs, "_DIGEST_DIR", tmp_path / "inbox")
    job_entry = {
        "id": "test-job", "workshop": "open", "permission_level": 3,
        "write_scope": ["/"], "read_scope": [], "quota": {}, "approved": False,
    }
    monkeypatch.setattr(main.jobs, "get_job", lambda job_id, registry=None: job_entry)

    async def fake_critique_envelope(job_entry, workshop, **kw):
        return [
            main.council.CouncilVerdict(member="openai", verdict="pass", reason="ok"),
            main.council.CouncilVerdict(member="claude", verdict="flag", reason="write_scope is repo-wide"),
        ]

    monkeypatch.setattr(main.council, "critique_envelope", fake_critique_envelope)

    with TestClient(main.app) as client:
        resp = client.post("/jobs/critique/test-job")

    assert resp.status_code == 200
    body = resp.json()
    assert body["objection"] is True
    assert len(body["verdicts"]) == 2
    assert Path(body["note_path"]).exists()
    # Finding 3 (15d final review): the response and the written note both
    # carry the envelope hash the critique ran against, so the owner can
    # detect a stale critique (envelope edited since) before approving.
    expected_hash = main.jobs.compute_envelope_hash(job_entry)
    assert body["envelope_hash"] == expected_hash
    assert expected_hash in Path(body["note_path"]).read_text(encoding="utf-8")


def test_critique_endpoint_404s_for_unknown_job(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main, "_ALLOW_ANON", True)
    monkeypatch.setattr(main.jobs, "get_job", lambda job_id, registry=None: None)

    with TestClient(main.app) as client:
        resp = client.post("/jobs/critique/nonexistent")

    assert resp.status_code == 404


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
