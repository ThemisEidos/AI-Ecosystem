import asyncio
import json

import decision


def _run(coro):
    return asyncio.run(coro)


async def _collect(aiter):
    out = []
    async for chunk in aiter:
        out.append(chunk)
    return out


# ── route_turn (blocking) ────────────────────────────────────────────────────
def test_route_turn_dispatches_on_tool_call():
    async def gen(message, history, tools=None):
        return decision.ModelReply(
            content="", tool_calls=[decision.ToolCall(id="1", name="status_summary", arguments={})]
        )

    async def handler(tool_id, args, raw):
        return f"ran {tool_id}"

    reply, td = _run(decision.route_turn(
        "status", [], generate_answer=gen, tools=[], tool_call_handler=handler,
    ))
    assert reply == "ran status_summary"
    assert td.decision == "dispatch"
    assert td.reason == "tool_call: status_summary"


def test_route_turn_answers_when_no_tool_call():
    async def gen(message, history, tools=None):
        return decision.ModelReply(content="hi there", tool_calls=[])

    reply, td = _run(decision.route_turn("hello", [], generate_answer=gen))
    assert reply == "hi there"
    assert td.decision == "answer"


def test_route_turn_falls_back_without_a_handler():
    async def gen(message, history, tools=None):
        return decision.ModelReply(
            content="", tool_calls=[decision.ToolCall(id="1", name="a", arguments={})]
        )

    reply, td = _run(decision.route_turn("do stuff", [], generate_answer=gen))
    assert reply == decision._DISPATCH_FALLBACK
    assert td.decision == "dispatch"


def test_route_turn_multiple_tool_calls_drops_extra_with_note():
    async def gen(message, history, tools=None):
        return decision.ModelReply(content="", tool_calls=[
            decision.ToolCall(id="1", name="a", arguments={}),
            decision.ToolCall(id="2", name="b", arguments={}),
        ])

    async def handler(tool_id, args, raw):
        return "ran a"

    reply, td = _run(decision.route_turn(
        "do stuff", [], generate_answer=gen, tool_call_handler=handler,
    ))
    assert reply.startswith("ran a")
    assert "1 additional tool call" in reply
    assert "dropped" in reply


def test_route_turn_backend_error_is_caught():
    async def gen(message, history, tools=None):
        raise RuntimeError("boom")

    reply, td = _run(decision.route_turn("hi", [], generate_answer=gen))
    assert "backend unavailable" in reply
    assert td.decision == "answer"


# ── _openai_complete / _ollama_complete ──────────────────────────────────────
class _FakeHTTPResp:
    def __init__(self, data):
        self._data = data
    def raise_for_status(self):
        pass
    def json(self):
        return self._data


class _FakeHTTPClient:
    def __init__(self, data):
        self._data = data
    async def __aenter__(self):
        return self
    async def __aexit__(self, *a):
        return False
    async def post(self, url, **kw):
        return _FakeHTTPResp(self._data)


def test_openai_complete_returns_plain_string_without_tools(monkeypatch):
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeHTTPClient(
        {"choices": [{"message": {"content": "plain answer"}}]}
    ))
    result = _run(decision._openai_complete("http://x", "k", "m", [{"role": "user", "content": "hi"}]))
    assert result == "plain answer"


def test_openai_complete_returns_model_reply_with_tools(monkeypatch):
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeHTTPClient(
        {"choices": [{"message": {
            "content": "",
            "tool_calls": [{"id": "1", "function": {"name": "status_summary", "arguments": "{}"}}],
        }}]}
    ))
    result = _run(decision._openai_complete(
        "http://x", "k", "m", [{"role": "user", "content": "hi"}],
        tools=[{"type": "function", "function": {"name": "status_summary"}}],
    ))
    assert isinstance(result, decision.ModelReply)
    assert result.tool_calls[0].name == "status_summary"
    assert result.tool_calls[0].arguments == {}


def test_ollama_complete_returns_plain_string_without_tools(monkeypatch):
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeHTTPClient(
        {"message": {"content": "plain"}}
    ))
    result = _run(decision._ollama_complete("http://x", "m", [{"role": "user", "content": "hi"}]))
    assert result == "plain"


def test_ollama_complete_returns_model_reply_with_tools(monkeypatch):
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeHTTPClient(
        {"message": {"content": "", "tool_calls": [
            {"function": {"name": "status_summary", "arguments": {}}}
        ]}}
    ))
    result = _run(decision._ollama_complete(
        "http://x", "m", [{"role": "user", "content": "hi"}],
        tools=[{"type": "function", "function": {"name": "status_summary"}}],
    ))
    assert isinstance(result, decision.ModelReply)
    assert result.tool_calls[0].name == "status_summary"


# ── route_turn_stream — fixture-driven, no live LLM (spec §6.6) ─────────────
class _FakeStreamResp:
    def __init__(self, lines):
        self._lines = lines
    def raise_for_status(self):
        pass
    async def aiter_lines(self):
        for line in self._lines:
            yield line


class _FakeStreamCtx:
    def __init__(self, resp):
        self._resp = resp
    async def __aenter__(self):
        return self._resp
    async def __aexit__(self, *a):
        return False


class _FakeStreamClient:
    def __init__(self, lines):
        self._lines = lines
    async def __aenter__(self):
        return self
    async def __aexit__(self, *a):
        return False
    def stream(self, method, url, **kw):
        return _FakeStreamCtx(_FakeStreamResp(self._lines))


def test_ollama_stream_single_chunk_tool_call_dispatches(monkeypatch):
    lines = [json.dumps({
        "message": {
            "role": "assistant", "content": "",
            "tool_calls": [{"function": {"name": "status_summary", "arguments": {}}}],
        },
        "done": True,
    })]
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeStreamClient(lines))

    captured = {}
    async def handler(tool_id, args, raw):
        captured["tool_id"] = tool_id
        captured["args"] = args
        return "EXECUTED"

    td, content_iter = _run(decision.route_turn_stream(
        "give me a status summary", [], system_prompt="sys",
        base_url="http://x", api_key="", model="m", backend="ollama",
        tools=[{"type": "function", "function": {"name": "status_summary", "parameters": {}}}],
        tool_call_handler=handler,
    ))
    chunks = _run(_collect(content_iter))
    assert td.decision == "dispatch"
    assert td.reason == "tool_call: status_summary"
    assert captured["tool_id"] == "status_summary"
    assert chunks == ["EXECUTED"]


def test_openai_stream_fragmented_tool_call_accumulates(monkeypatch):
    deltas = [
        {"choices": [{"delta": {"tool_calls": [
            {"index": 0, "id": "call_1", "function": {"name": "status_summary", "arguments": ""}}
        ]}}]},
        {"choices": [{"delta": {"tool_calls": [
            {"index": 0, "function": {"arguments": '{"a"'}}
        ]}}]},
        {"choices": [{"delta": {"tool_calls": [
            {"index": 0, "function": {"arguments": ': 1}'}}
        ]}}]},
    ]
    lines = [f"data: {json.dumps(d)}" for d in deltas] + ["data: [DONE]"]
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeStreamClient(lines))

    captured = {}
    async def handler(tool_id, args, raw):
        captured["tool_id"] = tool_id
        captured["args"] = args
        return "EXECUTED"

    td, content_iter = _run(decision.route_turn_stream(
        "status please", [], system_prompt="sys",
        base_url="http://x", api_key="k", model="m", backend="openai",
        tools=[{"type": "function", "function": {"name": "status_summary", "parameters": {}}}],
        tool_call_handler=handler,
    ))
    chunks = _run(_collect(content_iter))
    assert td.decision == "dispatch"
    assert captured["tool_id"] == "status_summary"
    assert captured["args"] == {"a": 1}
    assert chunks == ["EXECUTED"]


def test_ollama_stream_plain_content_forwards_incrementally(monkeypatch):
    lines = [
        json.dumps({"message": {"content": "Hel"}, "done": False}),
        json.dumps({"message": {"content": "lo"}, "done": False}),
        json.dumps({"message": {"content": ""}, "done": True}),
    ]
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeStreamClient(lines))

    # Unlike the dispatch-branch tests above (whose content_iter is a fully
    # self-contained _single_chunk), the "answer" branch's content_iter
    # (_forward_remaining) keeps the underlying _stream_ollama_events
    # generator alive and resumes it lazily. asyncio.run() tears down any
    # async generators still suspended when its loop shuts down
    # (loop.shutdown_asyncgens()), so driving route_turn_stream and then
    # draining content_iter via two separate _run()/asyncio.run() calls
    # force-closes that generator between them. Real callers (a FastAPI
    # request handler) consume both within one event loop, so exercise it
    # the same way here.
    async def scenario():
        td, content_iter = await decision.route_turn_stream(
            "hi", [], system_prompt="sys",
            base_url="http://x", api_key="", model="m", backend="ollama",
            tools=[], tool_call_handler=None,
        )
        chunks = await _collect(content_iter)
        return td, chunks

    td, chunks = _run(scenario())
    assert td.decision == "answer"
    assert chunks == ["Hel", "lo"]


def test_ollama_stream_content_before_tool_call_drops_the_tool_call(monkeypatch):
    """Pins the plan's locked-in 'never interleaved' design decision: once
    content has started streaming, a tool_call_delta that arrives afterward
    is silently dropped — the turn stays an "answer", not a "dispatch"."""
    lines = [
        json.dumps({"message": {"content": "Sure, let me do that"}, "done": False}),
        json.dumps({
            "message": {"content": "", "tool_calls": [
                {"function": {"name": "status_summary", "arguments": {}}}
            ]},
            "done": True,
        }),
    ]
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeStreamClient(lines))

    async def handler(tool_id, args, raw):
        return "EXECUTED"

    # Same single-event-loop pattern as test_ollama_stream_plain_content_forwards_incrementally
    # above — the "answer" branch's content_iter keeps the underlying stream
    # generator alive and must be drained in the same asyncio.run() call.
    async def scenario():
        td, content_iter = await decision.route_turn_stream(
            "do the thing", [], system_prompt="sys",
            base_url="http://x", api_key="", model="m", backend="ollama",
            tools=[{"type": "function", "function": {"name": "status_summary", "parameters": {}}}],
            tool_call_handler=handler,
        )
        chunks = await _collect(content_iter)
        return td, chunks

    td, chunks = _run(scenario())
    assert td.decision == "answer"
    assert chunks == ["Sure, let me do that"]


def test_stream_dispatch_falls_back_without_a_handler(monkeypatch):
    lines = [json.dumps({
        "message": {"content": "", "tool_calls": [{"function": {"name": "x", "arguments": {}}}]},
        "done": True,
    })]
    monkeypatch.setattr(decision.httpx, "AsyncClient", lambda **kw: _FakeStreamClient(lines))

    td, content_iter = _run(decision.route_turn_stream(
        "do it", [], system_prompt="sys",
        base_url="http://x", api_key="", model="m", backend="ollama",
        tools=[], tool_call_handler=None,
    ))
    chunks = _run(_collect(content_iter))
    assert td.decision == "dispatch"
    assert chunks == [decision._DISPATCH_FALLBACK]
