"""Signal gateway tests (Step 12): _chat_core refactor, allowlist, poll loop."""
import asyncio
import os

os.environ.setdefault("WORKSHOP", "open")
os.environ.setdefault("COOPER_ALLOW_ANON", "1")
os.environ.pop("COOPER_API_KEY", None)

import main  # noqa: E402
import gateway  # noqa: E402


def run(coro):
    return asyncio.run(coro)


def test_chat_core_short_circuits_registry_query(monkeypatch):
    monkeypatch.setattr(main.registry, "format_tool_list", lambda w: f"TOOLS[{w}]")
    reply, td = run(main._chat_core("what tools do you have?", []))
    assert reply == "TOOLS[open]"
    assert td.decision == "answer"


ENVELOPES = [
    {"envelope": {"source": "+15551230001",
                  "dataMessage": {"message": "hello cooper"}}},
    {"envelope": {"source": "+15559999999",
                  "dataMessage": {"message": "let me in"}}},
    {"envelope": {"source": "+15551230001", "receiptMessage": {"isRead": True}}},
]


def cfg(**over):
    base = dict(api_url="http://signal-cli:8080", number="+15550001111",
                allowed_senders=frozenset({"+15551230001"}))
    base.update(over)
    return gateway.GatewayConfig(**base)


def test_load_config_requires_all_vars():
    assert gateway.load_config({}) is None
    assert gateway.load_config({"SIGNAL_API_URL": "http://x:8080",
                                "SIGNAL_NUMBER": "+15550001111"}) is None  # no allowlist
    c = gateway.load_config({
        "SIGNAL_API_URL": "http://x:8080",
        "SIGNAL_NUMBER": "+15550001111",
        "SIGNAL_ALLOWED_SENDERS": "+15551230001, +15551230002",
    })
    assert c.allowed_senders == frozenset({"+15551230001", "+15551230002"})


def test_parse_envelopes_extracts_text_messages_only():
    assert gateway.parse_envelopes(ENVELOPES) == [
        ("+15551230001", "hello cooper"),
        ("+15559999999", "let me in"),
    ]
    assert gateway.parse_envelopes("garbage") == []


def test_allowlist_fail_closed():
    assert gateway.is_allowed(cfg(), "+15551230001")
    assert not gateway.is_allowed(cfg(), "+15559999999")
    assert not gateway.is_allowed(cfg(allowed_senders=frozenset()), "+15551230001")
