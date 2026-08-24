"""
COOPER decision layer — one tool-attached model call per turn (Step 15a).

The persona model receives the workshop's tool registry as OpenAI-format
`tools` on every turn. A text reply is the answer (including the model's
own clarifying questions — there is no separate clarify step). A `tool_call`
in the reply is the dispatch signal; the caller resolves and validates it
before anything runs.

Public API
----------
route_turn(message, history, *, generate_answer, tools=None, tool_call_handler=None)
  Blocking. Used by POST /chat and POST /v1/chat/completions stream=False.

route_turn_stream(message, history, *, system_prompt, base_url, api_key, model,
                   backend, tools=None, tool_call_handler=None)
  -> (TurnDecision, AsyncIterator[str])
  Streams the backend response; buffers silently if tool_call deltas appear,
  then emits the dispatch result as content chunks (spec §2 streaming specifics).

Decisions
---------
  answer   — the model replied with text (including its own clarifying questions)
  dispatch — the model emitted a tool_call; tool_call_handler ran it
"""
import json
from dataclasses import dataclass
from typing import AsyncIterator, Awaitable, Callable, Dict, List, Optional, Tuple

import httpx

_DISPATCH_FALLBACK = "Acknowledged. No dispatch handler is wired for this request."

_ALLOWED_ROLES = frozenset({"user", "assistant"})


@dataclass
class TurnDecision:
    decision: str  # "answer" | "dispatch"
    reason: str


@dataclass
class ToolCall:
    id: str
    name: str
    arguments: dict


@dataclass
class ModelReply:
    content: str
    tool_calls: List[ToolCall]


def _dropped_calls_note(tool_calls: List[ToolCall]) -> str:
    if len(tool_calls) <= 1:
        return ""
    n = len(tool_calls) - 1
    return (
        f"\n\n(Note: {n} additional tool call{'s' if n != 1 else ''} were proposed "
        "and dropped — COOPER dispatches one action per turn.)"
    )


# ── route_turn — one tool-attached call, tool_call = dispatch ────────────────
async def route_turn(
    message: str,
    history: List[dict],
    *,
    generate_answer: Callable[..., Awaitable[ModelReply]],
    tools: Optional[List[dict]] = None,
    tool_call_handler: Optional[Callable[[str, dict, str], Awaitable[str]]] = None,
) -> Tuple[str, TurnDecision]:
    try:
        reply_obj = await generate_answer(message, history, tools=tools)
    except Exception as exc:
        return (
            f"[COOPER error: backend unavailable — {exc}]",
            TurnDecision(decision="answer", reason=f"backend error: {exc}"),
        )

    if reply_obj.tool_calls:
        primary = reply_obj.tool_calls[0]
        extra_note = _dropped_calls_note(reply_obj.tool_calls)
        td = TurnDecision(decision="dispatch", reason=f"tool_call: {primary.name}")
        if tool_call_handler is None:
            return _DISPATCH_FALLBACK + extra_note, td
        reply = await tool_call_handler(primary.name, primary.arguments, message)
        return reply + extra_note, td

    return reply_obj.content, TurnDecision(decision="answer", reason="no tool call emitted")


# ── Streaming event generators — yield {"content": str} or
#    {"tool_call_delta": dict} items in arrival order ──────────────────────
async def _stream_ollama_events(
    base_url: str, model: str, messages: List[dict], tools: Optional[List[dict]]
) -> AsyncIterator[dict]:
    payload: dict = {"model": model, "messages": messages, "stream": True, "think": False}
    if tools:
        payload["tools"] = tools
    async with httpx.AsyncClient(timeout=120.0) as client:
        async with client.stream("POST", f"{base_url}/api/chat", json=payload) as resp:
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                if not line.strip():
                    continue
                try:
                    data = json.loads(line)
                except json.JSONDecodeError:
                    continue
                msg = data.get("message", {})
                for tc in msg.get("tool_calls") or []:
                    yield {"tool_call_delta": tc}
                content = msg.get("content", "")
                if content:
                    yield {"content": content}
                if data.get("done", False):
                    return


async def _stream_openai_events(
    base_url: str, api_key: str, model: str, messages: List[dict], tools: Optional[List[dict]]
) -> AsyncIterator[dict]:
    payload: dict = {"model": model, "messages": messages, "stream": True}
    if tools:
        payload["tools"] = tools
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    async with httpx.AsyncClient(timeout=120.0) as client:
        async with client.stream(
            "POST", f"{base_url}/chat/completions", json=payload, headers=headers
        ) as resp:
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                if not line.strip() or line == "data: [DONE]":
                    continue
                if not line.startswith("data: "):
                    continue
                try:
                    data = json.loads(line[6:])
                    delta = data["choices"][0]["delta"]
                except (json.JSONDecodeError, KeyError, IndexError):
                    continue
                for tc in delta.get("tool_calls") or []:
                    yield {"tool_call_delta": tc}
                content = delta.get("content")
                if content:
                    yield {"content": content}


def _stream_events(
    base_url: str, api_key: str, model: str, messages: List[dict],
    *, backend: str, tools: Optional[List[dict]],
) -> AsyncIterator[dict]:
    if backend == "openai":
        return _stream_openai_events(base_url, api_key, model, messages, tools)
    return _stream_ollama_events(base_url, model, messages, tools)


class _ToolCallAccumulator:
    """Accumulates OpenAI-style fragmented tool_call deltas (by `index`,
    arguments arrive as a partial JSON string across chunks) or Ollama-style
    single-chunk tool_calls (arguments arrive as a whole dict already)."""

    def __init__(self) -> None:
        self._by_index: Dict[int, dict] = {}
        self._order: List[int] = []

    def add(self, fragment: dict) -> None:
        index = fragment.get("index", len(self._order))
        if index not in self._by_index:
            self._by_index[index] = {"id": "", "name": "", "arguments": ""}
            self._order.append(index)
        entry = self._by_index[index]
        if fragment.get("id"):
            entry["id"] = fragment["id"]
        fn = fragment.get("function") or {}
        if fn.get("name"):
            entry["name"] = fn["name"]
        raw_args = fn.get("arguments")
        if isinstance(raw_args, str):
            entry["arguments"] += raw_args
        elif isinstance(raw_args, dict):
            entry["arguments"] = raw_args

    def finish(self) -> List[ToolCall]:
        calls = []
        for i, index in enumerate(self._order):
            entry = self._by_index[index]
            args = entry["arguments"]
            if isinstance(args, str):
                try:
                    args = json.loads(args) if args else {}
                except json.JSONDecodeError:
                    args = {}
            calls.append(ToolCall(id=entry["id"] or str(i), name=entry["name"], arguments=args))
        return calls


# ── route_turn_stream — real-time content streaming; silent buffer + single
#    dispatch chunk if a tool_call appears (spec §2 streaming specifics) ─────
async def route_turn_stream(
    message: str,
    history: List[dict],
    *,
    system_prompt: str,
    base_url: str,
    api_key: str,
    model: str,
    backend: str = "ollama",
    tools: Optional[List[dict]] = None,
    tool_call_handler: Optional[Callable[[str, dict, str], Awaitable[str]]] = None,
) -> Tuple[TurnDecision, AsyncIterator[str]]:
    msgs = _build_answer_messages(message, history, system_prompt)
    events = _stream_events(base_url, api_key, model, msgs, backend=backend, tools=tools)

    accumulator = _ToolCallAccumulator()
    first_content: Optional[str] = None

    async for ev in events:
        if "tool_call_delta" in ev:
            accumulator.add(ev["tool_call_delta"])
            # A tool_call turn: drain the rest of the stream silently — any
            # stray content after this point is buffered, never forwarded
            # (a turn is either streamed text OR a buffered dispatch, never
            # interleaved).
            async for ev2 in events:
                if "tool_call_delta" in ev2:
                    accumulator.add(ev2["tool_call_delta"])
            tool_calls = accumulator.finish()
            primary = tool_calls[0]
            extra_note = _dropped_calls_note(tool_calls)
            td = TurnDecision(decision="dispatch", reason=f"tool_call: {primary.name}")
            if tool_call_handler is None:
                return td, _single_chunk(_DISPATCH_FALLBACK + extra_note)
            reply = await tool_call_handler(primary.name, primary.arguments, message)
            return td, _single_chunk(reply + extra_note)
        first_content = ev["content"]
        break

    td = TurnDecision(decision="answer", reason="no tool call emitted")
    if first_content is None:
        return td, _single_chunk("")
    return td, _forward_remaining(first_content, events)


async def _forward_remaining(first_content: str, events: AsyncIterator[dict]) -> AsyncIterator[str]:
    yield first_content
    async for ev in events:
        if "content" in ev and ev["content"]:
            yield ev["content"]
        # a stray tool_call_delta arriving after content has already started
        # streaming is ignored — see the "never interleaved" note above.


# ── Blocking completions ───────────────────────────────────────────────────
# Return a bare `str` when called without `tools` (the pre-existing contract
# every other caller — archivist.py, proposer.py, review.py, executor.py's
# _run_local_llm/_run_llm_api — still relies on). Return a `ModelReply` when
# `tools` is supplied (only the persona-turn call path does this).
async def _ollama_complete(
    base_url: str,
    model: str,
    messages: List[dict],
    *,
    options: Optional[dict] = None,
    fmt: Optional[dict] = None,
    tools: Optional[List[dict]] = None,
):
    payload: dict = {"model": model, "messages": messages, "stream": False, "think": False}
    if options:
        payload["options"] = options
    if fmt:
        payload["format"] = fmt
    if tools:
        payload["tools"] = tools
    async with httpx.AsyncClient(timeout=120.0) as client:
        resp = await client.post(f"{base_url}/api/chat", json=payload)
        resp.raise_for_status()
        data = resp.json()
    message_obj = data["message"]
    if tools is not None:
        return ModelReply(
            content=message_obj.get("content") or "",
            tool_calls=_parse_ollama_tool_calls(message_obj.get("tool_calls") or []),
        )
    return message_obj["content"]


async def _openai_complete(
    base_url: str,
    api_key: str,
    model: str,
    messages: List[dict],
    *,
    temperature: Optional[float] = None,
    response_format: Optional[dict] = None,
    tools: Optional[List[dict]] = None,
):
    payload: dict = {"model": model, "messages": messages}
    if temperature is not None:
        payload["temperature"] = temperature
    if response_format:
        payload["response_format"] = response_format
    if tools:
        payload["tools"] = tools
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(
            f"{base_url}/chat/completions", json=payload, headers=headers
        )
        resp.raise_for_status()
        data = resp.json()
    message_obj = data["choices"][0]["message"]
    if tools is not None:
        return ModelReply(
            content=message_obj.get("content") or "",
            tool_calls=_parse_openai_tool_calls(message_obj.get("tool_calls") or []),
        )
    return message_obj["content"]


def _parse_ollama_tool_calls(raw: List[dict]) -> List[ToolCall]:
    calls = []
    for i, tc in enumerate(raw):
        fn = tc.get("function", {})
        arguments = fn.get("arguments") or {}
        if isinstance(arguments, str):
            try:
                arguments = json.loads(arguments)
            except json.JSONDecodeError:
                arguments = {}
        calls.append(ToolCall(id=str(i), name=fn.get("name", ""), arguments=arguments))
    return calls


def _parse_openai_tool_calls(raw: List[dict]) -> List[ToolCall]:
    calls = []
    for tc in raw:
        fn = tc.get("function", {})
        try:
            arguments = json.loads(fn.get("arguments") or "{}")
        except json.JSONDecodeError:
            arguments = {}
        calls.append(ToolCall(id=tc.get("id", ""), name=fn.get("name", ""), arguments=arguments))
    return calls


# ── Message builders ───────────────────────────────────────────────────────
def _build_answer_messages(
    message: str, history: List[dict], system_prompt: str
) -> List[dict]:
    msgs: List[dict] = [{"role": "system", "content": system_prompt}]
    for turn in history:
        if turn.get("role") in _ALLOWED_ROLES:
            msgs.append({"role": turn["role"], "content": turn.get("content", "")})
    if message.strip():
        msgs.append({"role": "user", "content": message})
    return msgs


# ── Utilities ──────────────────────────────────────────────────────────────
async def _single_chunk(text: str) -> AsyncIterator[str]:
    yield text
