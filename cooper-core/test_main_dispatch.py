"""Post-dispatch pipeline: memory/draft LLM calls run off the request path,
and their outcomes reach the user as next-turn notices."""
import asyncio
import os
from pathlib import Path

os.environ.setdefault("WORKSHOP", "open")
os.environ.setdefault("COOPER_ALLOW_ANON", "1")
os.environ.pop("COOPER_API_KEY", None)

import main  # noqa: E402
import review  # noqa: E402

_TOOL = {
    "id": "test_exec",
    "name": "Test Exec",
    "drawer": "Workbench",
    "permission_level": 1,
    "approval_required": False,
    "executor_type": "powershell",
}


def test_execute_returns_before_memory_and_draft_run(monkeypatch):
    """The reply must not wait on archivist.remember / proposer.draft_skill —
    they run in the background; the draft offer arrives as a session notice."""
    ran = {}

    async def scenario():
        gate = asyncio.Event()

        async def fake_run(tool, message, workshop):
            return "RAW-OUTPUT"

        async def fake_review(*a, **k):
            return review.ReviewVerdict(verdict="pass", reason="ok")

        async def fake_remember(*a, **k):
            await gate.wait()
            ran["remember"] = True

        async def fake_draft(*a, **k):
            await gate.wait()
            ran["draft"] = True
            return Path("Skills/_drafts/fresh-skill")

        monkeypatch.setattr(main.executor, "run", fake_run)
        monkeypatch.setattr(main.review, "review", fake_review)
        monkeypatch.setattr(main.review, "govern", lambda raw, v: raw)
        monkeypatch.setattr(main.archivist, "remember", fake_remember)
        monkeypatch.setattr(main.proposer, "draft_skill", fake_draft)

        reply = await main._execute(_TOOL, "run test exec", "sess-bg")
        assert reply == "RAW-OUTPUT"      # no draft offer inline
        assert ran == {}                  # nothing post-dispatch ran yet

        gate.set()
        await asyncio.sleep(0.05)         # let the background task finish
        assert ran == {"remember": True, "draft": True}

        notice = main._drain_notices("sess-bg")
        assert "fresh-skill" in notice and "promote skill" in notice
        assert main._drain_notices("sess-bg") == ""  # drained exactly once

    asyncio.run(scenario())


def test_chat_core_appends_queued_notice_to_next_reply(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main, "_ALLOW_ANON", True)
    monkeypatch.setattr(main.skills, "format_skill_list", lambda w: "SKILL-LIST")

    main._queue_notice("sess-n", "[Proposer] Drafted skill 'x'.")
    reply, td = asyncio.run(
        main._chat_core("what skills do you have?", [], "sess-n"))
    assert reply.startswith("SKILL-LIST")
    assert reply.endswith("[Proposer] Drafted skill 'x'.")
    # a different session must not see it
    main._queue_notice("sess-other", "OTHER")
    reply2, _ = asyncio.run(
        main._chat_core("what skills do you have?", [], "sess-n"))
    assert "OTHER" not in reply2
