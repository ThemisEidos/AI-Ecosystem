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

        async def fake_run(tool, message, workshop, args=None):
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


import approval  # noqa: E402


def test_handle_tool_call_refuses_unknown_tool_id():
    reply = asyncio.run(main._handle_tool_call("nonexistent_tool", {}, "do it", "s1"))
    assert "unregistered tool" in reply.lower()


def test_handle_tool_call_refuses_invalid_args(monkeypatch):
    monkeypatch.setattr(main.registry, "get_tool", lambda ws, tid: {
        "id": "status_summary", "name": "Status Summary", "permission_level": 0,
        "workshop": "Open Workshop", "executor_type": "informational",
    })
    monkeypatch.setattr(main.registry, "validate_args", lambda tool, args: ["missing required argument 'x'"])
    reply = asyncio.run(main._handle_tool_call("status_summary", {}, "do it", "s1"))
    assert "invalid call" in reply.lower()
    assert "missing required argument" in reply


def test_handle_tool_call_opens_ticket_with_rendered_args_preview(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main.registry, "get_tool", lambda ws, tid: {
        "id": "obsidian_note_writer", "name": "Obsidian Note Writer",
        "workshop": "Open Workshop", "permission_level": 2,
        "approval_required": True, "executor_type": "note_editor",
        "drawer": "Knowledge Shelf",
    })
    monkeypatch.setattr(main.registry, "validate_args", lambda tool, args: [])
    approval._pending.clear()
    reply = asyncio.run(main._handle_tool_call(
        "obsidian_note_writer",
        {"filename": "x.md", "content": "y" * 100},
        "write it", "s2",
    ))
    assert "Halt —" in reply
    assert "filename: 'x.md'" in reply
    assert "content: 100 chars" in reply
    ticket = approval.peek(main.WORKSHOP, "s2")
    assert ticket.args == {"filename": "x.md", "content": "y" * 100}


def test_handle_tool_call_refuses_when_ticket_already_pending(monkeypatch):
    # Regression: a second tool call for the same session while a ticket is
    # already live (e.g. Open WebUI background housekeeping sharing
    # session_id="local" with the visible chat) must not silently replace the
    # human's pending ticket.
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main.registry, "get_tool", lambda ws, tid: {
        "id": "obsidian_note_writer", "name": "Obsidian Note Writer",
        "workshop": "Open Workshop", "permission_level": 2,
        "approval_required": True, "executor_type": "note_editor",
        "drawer": "Knowledge Shelf",
    })
    monkeypatch.setattr(main.registry, "validate_args", lambda tool, args: [])
    approval._pending.clear()
    approval.request(main.WORKSHOP, {"id": "t1", "name": "First Tool"}, "first message", "s4")

    reply = asyncio.run(main._handle_tool_call(
        "obsidian_note_writer", {"filename": "x.md", "content": "y"}, "second message", "s4",
    ))

    assert "First Tool" in reply
    assert "approve" in reply.lower() or "deny" in reply.lower()
    # the original ticket is untouched, not replaced by the new tool call
    ticket = approval.peek(main.WORKSHOP, "s4")
    assert ticket is not None and ticket.tool.get("name") == "First Tool"
    assert ticket.message == "first message"


def test_approve_executes_with_ticket_stored_args(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", set())
    tool = {"id": "obsidian_note_writer", "name": "Obsidian Note Writer",
            "workshop": "Open Workshop", "executor_type": "note_editor"}
    approval._pending.clear()
    approval.request(main.WORKSHOP, tool, "write it", "s3",
                      args={"filename": "x.md", "content": "hi"})

    seen = {}

    async def fake_run(t, message, workshop, args=None):
        seen["args"] = args
        return "wrote it"

    monkeypatch.setattr(main.executor, "run", fake_run)

    verdict = main.review.ReviewVerdict(verdict="pass", reason="ok")

    async def fake_review(*a, **k):
        return verdict

    monkeypatch.setattr(main.review, "review", fake_review)

    async def fake_remember(*a, **k):
        return None

    monkeypatch.setattr(main.archivist, "remember", fake_remember)

    async def fake_draft(*a, **k):
        return None

    monkeypatch.setattr(main.proposer, "draft_skill", fake_draft)

    reply = asyncio.run(main._resolve_approval("approve", "s3"))
    assert seen["args"] == {"filename": "x.md", "content": "hi"}
    assert "wrote it" in reply


def test_execute_passes_each_role_its_own_mapped_model(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", set())
    tool = {"id": "obsidian_note_writer", "name": "Obsidian Note Writer",
            "workshop": "Open Workshop", "executor_type": "note_editor"}

    async def fake_run(t, message, workshop, args=None):
        return "wrote it"

    monkeypatch.setattr(main.executor, "run", fake_run)

    seen = {}

    async def fake_review(tool, message, raw_output, base_url, api_key, model, backend):
        seen["reviewer_model"] = model
        return main.review.ReviewVerdict(verdict="pass", reason="ok")

    monkeypatch.setattr(main.review, "review", fake_review)

    async def fake_remember(conn, tool, message, raw_output, verdict, workshop,
                             base_url, api_key, model, backend):
        seen["archivist_model"] = model

    monkeypatch.setattr(main.archivist, "remember", fake_remember)

    async def fake_draft(tool, message, raw_output, base_url, api_key, model, backend):
        seen["drafter_model"] = model
        return None

    monkeypatch.setattr(main.proposer, "draft_skill", fake_draft)

    async def _run():
        result = await main._execute(
            tool, "write it", "s5", {"filename": "x.md", "content": "hi"}
        )
        # _post_dispatch runs as a fire-and-forget background task (asyncio.create_task
        # inside _execute) — drain it in the SAME event loop before asserting. A second,
        # separate asyncio.run() call cannot await a task created in the first call's
        # loop, since that loop is already closed by the time the second one starts.
        if main._BG_TASKS:
            await asyncio.gather(*main._BG_TASKS)
        return result

    asyncio.run(_run())

    assert seen["reviewer_model"] == main.REVIEWER_MODEL
    assert seen.get("archivist_model") == main.ARCHIVIST_MODEL
    assert seen.get("drafter_model") == main.DRAFTER_MODEL


def test_unknown_workflow_is_refused_without_opening_a_ticket():
    tool = main.registry.get_tool("open", "n8n_general_workflows")
    assert tool is not None
    reply = asyncio.run(main._handle_tool_call(
        "n8n_general_workflows", {"workflow": "not_real", "payload": "hi"}, "run it", "s-inv"
    ))
    assert "invalid call" in reply.lower()
    assert not approval.has_pending(main.WORKSHOP, "s-inv")


def test_render_args_preview_uses_repr_length_for_threshold():
    # str(value) has length 59 (under the 60-char threshold), but repr(value)
    # adds two quote chars -> 61, over threshold. The branch decision must be
    # driven by the repr length (what verbatim rendering would actually cost),
    # so this must take the "N chars" branch, reporting the plain str() length.
    value = "x" * 59
    preview = main._render_args_preview({"content": value})
    assert "content: 59 chars" in preview
    assert "'" not in preview  # not rendered verbatim with repr quoting
