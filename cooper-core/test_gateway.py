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


import httpx
import json as _json


def make_mock_client(receive_payload, sent: list):
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.startswith("/v1/receive/"):
            return httpx.Response(200, json=receive_payload)
        if request.url.path == "/v2/send":
            sent.append(_json.loads(request.content))
            return httpx.Response(201, json={"timestamp": "1"})
        return httpx.Response(404)
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


def test_poll_once_replies_to_allowed_and_ignores_others():
    sent: list = []
    replies: list = []

    async def fake_handler(text: str) -> str:
        replies.append(text)
        return f"echo: {text}"

    client = make_mock_client(ENVELOPES, sent)
    handled = run(gateway.poll_once(cfg(), client, fake_handler))
    assert handled == 1                      # only the allowlisted sender
    assert replies == ["hello cooper"]
    assert len(sent) == 1
    assert sent[0]["recipients"] == ["+15551230001"]
    assert sent[0]["message"] == "echo: hello cooper"
    assert sent[0]["number"] == "+15550001111"


def test_poll_once_survives_handler_error():
    sent: list = []

    async def broken(text: str) -> str:
        raise RuntimeError("pipeline down")

    client = make_mock_client(ENVELOPES[:1], sent)
    handled = run(gateway.poll_once(cfg(), client, broken))
    assert handled == 1
    assert "error" in sent[0]["message"].lower()   # operator still gets a reply


def test_run_loop_bounded_iterations():
    sent: list = []

    async def fake_handler(text: str) -> str:
        return "ok"

    client = make_mock_client([], sent)
    run(gateway.run_loop(cfg(), fake_handler, client=client, max_iterations=3))
    # completes without hanging — loop honored the iteration bound
