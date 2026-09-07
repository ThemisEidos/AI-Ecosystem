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
        assert job_id == "news-reel"
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
        resp = client.post("/jobs/run/news-reel")

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
        resp = client.post("/jobs/run/news-reel")

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










# --- Step 15i: cockpit endpoints ----------------------------------------------

import shutil  # noqa: E402

import jobs  # noqa: E402
import yaml  # noqa: E402


def _client(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main, "_ALLOW_ANON", True)
    return TestClient(main.app)


def _copy_registry(tmp_path):
    """A throwaway registry so approval tests never write the real one."""
    dst = tmp_path / "jobs_registry.yaml"
    shutil.copyfile(jobs._REGISTRY_PATH, dst)
    return dst


def test_get_jobs_lists_envelopes_with_state(monkeypatch):
    r = _client(monkeypatch).get("/jobs")
    assert r.status_code == 200
    body = r.json()
    ids = {j["id"] for j in body["jobs"]}
    assert {"news-reel", "repo-steward"} == ids
    j = next(x for x in body["jobs"] if x["id"] == "news-reel")
    for field in ("job_type", "workshop", "read_scope", "write_scope",
                  "quota", "permission_level", "approved", "envelope_hash"):
        assert field in j, field


def test_get_jobs_requires_auth_when_keys_are_set(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", {"real-key"})
    monkeypatch.setattr(main, "_ALLOW_ANON", False)
    assert TestClient(main.app).get("/jobs").status_code == 401


def test_post_job_approval_flips_state(monkeypatch, tmp_path):
    monkeypatch.setattr(jobs, "_REGISTRY_PATH", _copy_registry(tmp_path))
    c = _client(monkeypatch)
    assert c.post("/jobs/news-reel/approval", json={"approved": False}).json()["approved"] is False
    assert c.post("/jobs/news-reel/approval", json={"approved": True}).json()["approved"] is True


def test_post_job_approval_unknown_job_is_404(monkeypatch, tmp_path):
    monkeypatch.setattr(jobs, "_REGISTRY_PATH", _copy_registry(tmp_path))
    assert _client(monkeypatch).post("/jobs/nope/approval", json={"approved": True}).status_code == 404


def test_patch_job_settings_voids_approval(monkeypatch, tmp_path):
    monkeypatch.setattr(jobs, "_REGISTRY_PATH", _copy_registry(tmp_path))
    c = _client(monkeypatch)
    c.post("/jobs/news-reel/approval", json={"approved": True})
    r = c.patch("/jobs/news-reel/settings", json={"quota": {"fetches_per_run": 9}})
    assert r.status_code == 200
    assert r.json()["approved"] is False, "editing an envelope must revoke approval"


def test_patch_job_settings_refuses_scope_edits(monkeypatch, tmp_path):
    monkeypatch.setattr(jobs, "_REGISTRY_PATH", _copy_registry(tmp_path))
    r = _client(monkeypatch).patch("/jobs/news-reel/settings", json={"write_scope": ["/etc/"]})
    assert r.status_code == 400


def test_get_job_runs_and_exceptions(monkeypatch):
    c = _client(monkeypatch)
    assert c.get("/jobs/runs").status_code == 200
    assert "exceptions" in c.get("/jobs/exceptions").json()


def test_cockpit_page_is_served_without_auth(monkeypatch):
    # The shell carries no data: it fetches everything with the key the operator
    # supplies in the browser, so serving it needs no auth.
    monkeypatch.setattr(main, "_API_KEYS", {"real-key"})
    monkeypatch.setattr(main, "_ALLOW_ANON", False)
    r = TestClient(main.app).get("/cockpit")
    assert r.status_code == 200
    assert "text/html" in r.headers["content-type"]
    assert "COOPER" in r.text


def test_cockpit_page_embeds_no_api_key(monkeypatch):
    body = _client(monkeypatch).get("/cockpit").text
    assert "cooper-local" not in body
    for key in main._API_KEYS:
        assert key not in body


def test_cockpit_page_strips_a_handed_over_key_from_the_url(monkeypatch):
    # The launcher passes the key in the URL fragment. The page must clear it
    # from the address bar so it does not sit in browser history.
    body = _client(monkeypatch).get("/cockpit").text
    assert "location.hash" in body
    assert "history.replaceState" in body


def test_cockpit_page_never_reads_the_key_from_a_query_string(monkeypatch):
    # A query string WOULD reach the server's access log; a fragment never does.
    # Assert on the code that extracts the key, not on a function name.
    import re
    js = re.search(r"<script>(.*?)</script>",
                   _client(monkeypatch).get("/cockpit").text, re.S).group(1)
    extractor = js[:js.index("history.replaceState")]
    assert "location.hash" in extractor
    assert "location.search" not in extractor


def test_pair_new_requires_auth_and_claim_does_not(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", {"real-key"})
    monkeypatch.setattr(main, "_ALLOW_ANON", False)
    c = TestClient(main.app)
    assert c.post("/pair/new").status_code == 401
    # claim is open by necessity — the claiming device has no key yet
    assert c.post("/pair/claim", json={"code": "000000"}).status_code == 400


def test_pairing_round_trip_hands_over_the_presented_key(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", {"real-key"})
    monkeypatch.setattr(main, "_ALLOW_ANON", False)
    monkeypatch.setattr(main, "_PAIRING", main.pairing.PairingStore())
    c = TestClient(main.app)
    code = c.post("/pair/new", headers={"Authorization": "Bearer real-key"}).json()["code"]
    assert c.post("/pair/claim", json={"code": code}).json()["key"] == "real-key"
    # single use
    assert c.post("/pair/claim", json={"code": code}).status_code == 400


def test_cockpit_every_element_the_script_touches_exists(monkeypatch):
    """The bug this exists to prevent (2026-09-06).

    Three elements the script wires up at load — the pairing input, its button
    and the remember checkbox — were missing because two edits to the markup
    silently no-opped. `$("claim").addEventListener` then threw a TypeError on
    load, which killed the script before it reached ANY of its work: the page
    rendered blank, and the key handed over in the URL fragment was never
    stripped from the address bar. One missing element, both symptoms.

    A blank page and a leaked key are the same class of failure as everything
    else caught today: something did nothing and said nothing about it.
    """
    import re
    html = _client(monkeypatch).get("/cockpit").text
    script = re.search(r"<script>(.*?)</script>", html, re.S)
    assert script, "cockpit page has no script block"
    used = set(re.findall(r'\$\("([^"]+)"\)', script.group(1)))
    present = set(re.findall(r'id="([^"]+)"', html))
    assert used, "no element lookups found — did the helper get renamed?"
    assert not (used - present), (
        "the script looks up elements that do not exist in the page: "
        + ", ".join(sorted(used - present))
    )


def test_cockpit_strips_the_fragment_before_anything_that_can_throw(monkeypatch):
    """The strip must not depend on the rest of the script surviving.

    It used to run last; a TypeError higher up meant the key stayed in the
    address bar. It now runs first, so the only code that can precede it is the
    strip itself.
    """
    import re
    js = re.search(r"<script>(.*?)</script>",
                   _client(monkeypatch).get("/cockpit").text, re.S).group(1)
    strip_at = js.index("history.replaceState")
    # nothing that touches the DOM may run before the strip
    head = js[:strip_at]
    assert "getElementById" not in head
    assert "addEventListener" not in head
    assert 'document.querySelector' not in head


def test_cockpit_chat_pane_is_present(monkeypatch):
    body = _client(monkeypatch).get("/cockpit").text
    for el in ('id="chatview"', 'id="msgs"', 'id="composer"', 'id="approvalslot"',
               'id="v-chat"', 'id="v-jobs"'):
        assert el in body, el


def test_cockpit_approve_buttons_use_the_existing_chat_gate(monkeypatch):
    """The approve/deny buttons must not get their own endpoint.

    They send the words "approve"/"deny" through POST /chat -- the exact path
    typing them takes -- so the gate has one code path rather than two, and a UI
    bug cannot invent a way past it. A dedicated /approve route would be a second
    door onto the same room.
    """
    import re
    js = re.search(r"<script>(.*?)</script>",
                   _client(monkeypatch).get("/cockpit").text, re.S).group(1)
    assert 'send("approve", true)' in js and 'send("deny", true)' in js
    # send() is the ordinary conversational path -- the same one typing uses.
    # Verified live 2026-09-07: a halt raised through /v1/chat/completions opens
    # a real ticket, and "deny" sent the same way clears it.
    assert '"/v1/chat/completions"' in js and '"/pending"' in js
    for forbidden in ('"/approve"', '"/deny"', "/pending/approve", "/approval/consume"):
        assert forbidden not in js, forbidden


def test_cockpit_streams_through_the_openai_endpoint(monkeypatch):
    """Streaming goes through /v1/chat/completions, which runs the SAME
    tool-call handler as POST /chat -- so an approval halt behaves identically
    and the gate is not weakened by streaming."""
    import re
    js = re.search(r"<script>(.*?)</script>",
                   _client(monkeypatch).get("/cockpit").text, re.S).group(1)
    assert '"/v1/chat/completions"' in js
    assert "stream: true" in js
    assert "getReader" in js


def test_cockpit_history_excludes_ui_annotations(monkeypatch):
    """System lines ("decision: …") are UI annotations, not conversation. Sending
    them back as history would teach the model to imitate them."""
    import re
    js = re.search(r"<script>(.*?)</script>",
                   _client(monkeypatch).get("/cockpit").text, re.S).group(1)
    fn = js[js.index("function historyForServer"):]
    fn = fn[:fn.index("\n  }")]
    assert 'm.cls === "me" || m.cls === ""' in fn
    assert "slice(-CHAT_SEND)" in fn


def test_cockpit_history_is_capped(monkeypatch):
    # The server caps history at 50; an unbounded local log would eventually
    # exceed it and every request would 422.
    body = _client(monkeypatch).get("/cockpit").text
    assert "CHAT_SEND = 20" in body
    assert "CHAT_MAX = 60" in body
