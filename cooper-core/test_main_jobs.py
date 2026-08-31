"""main.py jobs wiring: POST /jobs/run/{job_id} (Step 14b Task 6)."""
import os

os.environ.setdefault("WORKSHOP", "open")
os.environ.setdefault("COOPER_ALLOW_ANON", "1")
os.environ.pop("COOPER_API_KEY", None)

from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402


def test_post_jobs_run_returns_run_job_result(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main, "_ALLOW_ANON", True)
    monkeypatch.setattr(main.jobs, "get_job", lambda job_id, registry=None: {"id": job_id})

    async def fake_run_job(job_id, conn):
        assert job_id == "link-checker"
        assert conn is main._ARCHIVIST_CONN
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
