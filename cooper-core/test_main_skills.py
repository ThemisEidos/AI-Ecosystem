"""main.py skill wiring: catalog query short-circuit + GET /skills (Step 10)."""
import asyncio
import os

os.environ.setdefault("WORKSHOP", "open")
os.environ.setdefault("COOPER_ALLOW_ANON", "1")
os.environ.pop("COOPER_API_KEY", None)

from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402
import skills  # noqa: E402

_IMPORT_SKILL_TOOL = {
    "id": "import_skill",
    "name": "Import Skill",
    "drawer": "Skills",
    "workshop": "Open Workshop",
    "permission_level": 2,
    "approval_required": True,
    "executor_type": "skill_import",
}


def test_chat_answers_skill_query_without_llm(monkeypatch):
    # main is a module cached across the pytest session — if another test file
    # imports it first (e.g. test_main_auth.py, alphabetically earlier), the
    # env-var-driven globals below are already frozen by the time this file's
    # os.environ.setdefault() calls run. Force them directly so lifespan's
    # _check_auth_config() gate passes regardless of import order.
    monkeypatch.setattr(main, "_API_KEYS", set())
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
    monkeypatch.setattr(main, "_API_KEYS", set())
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


def test_get_skills_endpoint_isolates_per_entry_status_failure(monkeypatch):
    # skill_status() has no internal guard (unlike _load_skill), so GET /skills
    # must catch per-entry to avoid one bad entry 500-ing the whole response.
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main, "_ALLOW_ANON", True)
    monkeypatch.setattr(main.skills, "load_manifest", lambda: [
        {"id": "good-skill", "path": "Skills/examples/good-skill",
         "workshop": "open", "permission_level": 1, "content_hash": "dead"},
        {"id": "bad-skill", "path": "Skills/examples/bad-skill",
         "workshop": "open", "permission_level": 1, "content_hash": "beef"},
    ])

    def _skill_status(e):
        if e.get("id") == "bad-skill":
            raise PermissionError("simulated unreadable skill file")
        return "ok"

    monkeypatch.setattr(main.skills, "skill_status", _skill_status)
    with TestClient(main.app) as client:
        resp = client.get("/skills")
    assert resp.status_code == 200
    data = resp.json()
    assert data["count"] == 2
    by_id = {s["id"]: s["status"] for s in data["skills"]}
    assert by_id["good-skill"] == "ok"
    assert by_id["bad-skill"] == "error"


def test_rejected_preview_never_opens_an_approval_ticket(monkeypatch):
    # Core security property of Step 10: if skills.preview_import() raises before
    # approval.request() is ever called, _handle_dispatch() must return the
    # rejection immediately and MUST NOT leave a dangling approval ticket behind.
    # Previously verified only by a manual live-curl transcript — this pins it down.
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main, "_ALLOW_ANON", True)

    async def _select_import_skill(*args, **kwargs):
        return dict(_IMPORT_SKILL_TOOL)

    monkeypatch.setattr(main.registry, "select_tool_llm", _select_import_skill)

    def _boom(message):
        raise skills.SkillError("bad tap")

    monkeypatch.setattr(main.skills, "preview_import", _boom)

    approval_calls = []
    monkeypatch.setattr(
        main.approval, "request",
        lambda *args, **kwargs: approval_calls.append((args, kwargs)),
    )

    reply = asyncio.run(
        main._handle_dispatch("import skill tap-skill from https://x/y")
    )

    assert "rejected" in reply.lower()
    assert "bad tap" in reply
    assert approval_calls == []


def test_execute_reply_unchanged_when_proposer_raises(monkeypatch):
    # Step 11's core fail-safety property: proposer.draft_skill sits in every
    # successful dispatch's hot path now. If it (or offer_line) raises, the
    # governed reply must reach the user completely unchanged — not 500,
    # not truncated, not silently missing content.
    tool = {"id": "stack_test", "name": "Stack Test", "executor_type": "noop"}

    async def _run(*args, **kwargs):
        return "[Test-PDAStack.ps1 — OK]\nall green"

    monkeypatch.setattr(main.executor, "run", _run)

    verdict = main.review.ReviewVerdict(verdict="pass", reason="looked fine")

    async def _review(*args, **kwargs):
        return verdict

    monkeypatch.setattr(main.review, "review", _review)

    async def _remember(*args, **kwargs):
        return None

    monkeypatch.setattr(main.archivist, "remember", _remember)

    async def _boom(*args, **kwargs):
        raise RuntimeError("llm down")

    monkeypatch.setattr(main.proposer, "draft_skill", _boom)

    expected = main.review.govern("[Test-PDAStack.ps1 — OK]\nall green", verdict)
    reply = asyncio.run(main._execute(tool, "check the stack health"))
    assert reply == expected
