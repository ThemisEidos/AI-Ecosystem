"""main.py skill wiring: catalog query short-circuit + GET /skills (Step 10)."""
import os

os.environ.setdefault("WORKSHOP", "open")
os.environ.setdefault("COOPER_ALLOW_ANON", "1")
os.environ.pop("COOPER_API_KEY", None)

from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402


def test_chat_answers_skill_query_without_llm(monkeypatch):
    # main is a module cached across the pytest session — if another test file
    # imports it first (e.g. test_main_auth.py, alphabetically earlier), the
    # env-var-driven globals below are already frozen by the time this file's
    # os.environ.setdefault() calls run. Force them directly so lifespan's
    # _check_auth_config() gate passes regardless of import order.
    monkeypatch.setattr(main, "_API_KEY", "")
    monkeypatch.setattr(main, "_ALLOW_ANON", True)
    monkeypatch.setattr(main.skills, "format_skill_list",
                        lambda workshop: f"SKILL-LIST[{workshop}]")
    with TestClient(main.app) as client:
        resp = client.post("/chat", json={"message": "what skills do you have?"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["reply"] == "SKILL-LIST[open]"
    assert body["decision"] == "answer"


def test_get_skills_endpoint(monkeypatch):
    monkeypatch.setattr(main, "_API_KEY", "")
    monkeypatch.setattr(main, "_ALLOW_ANON", True)
    monkeypatch.setattr(main.skills, "load_manifest", lambda: [
        {"id": "hello-cooper", "path": "Skills/examples/hello-cooper",
         "workshop": "open", "permission_level": 1, "content_hash": "dead"},
    ])
    monkeypatch.setattr(main.skills, "skill_status", lambda e: "hash_mismatch")
    with TestClient(main.app) as client:
        resp = client.get("/skills")
    assert resp.status_code == 200
    data = resp.json()
    assert data["workshop"] == "open"
    assert data["skills"][0]["status"] == "hash_mismatch"
