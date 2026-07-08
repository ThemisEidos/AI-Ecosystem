"""Signal gateway tests (Step 12): _chat_core refactor, allowlist, poll loop."""
import asyncio
import os

os.environ.setdefault("WORKSHOP", "open")
os.environ.setdefault("COOPER_ALLOW_ANON", "1")
os.environ.pop("COOPER_API_KEY", None)

import main  # noqa: E402


def run(coro):
    return asyncio.run(coro)


def test_chat_core_short_circuits_registry_query(monkeypatch):
    monkeypatch.setattr(main.registry, "format_tool_list", lambda w: f"TOOLS[{w}]")
    reply, td = run(main._chat_core("what tools do you have?", []))
    assert reply == "TOOLS[open]"
    assert td.decision == "answer"
