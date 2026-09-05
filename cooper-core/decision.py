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
  Streams content deltas in real time; a tool_call is accumulated silently
  regardless of when it arrives relative to content, and if one completes,
  the dispatch result is appended as additional chunks after the content
  (spec §2 streaming specifics) — never dropped, matching route_turn. The
  returned TurnDecision is mutated in place and only reaches its final
  "dispatch"/"answer" value once content_iter has been fully drained — a
  caller that inspects it right after the await, before draining, always
  sees "answer".

Decisions
---------
  answer   — the model replied with text (including its own clarifying questions)
  dispatch — the model emitted a tool_call; tool_call_handler ran it
"""
import json
from dataclasses import dataclass
from typing import AsyncIterator, Awaitable, Callable, Dict, List, Optional, Tuple

import httpx

import retry_policy

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
    verb = "was" if n == 1 else "were"
    return (
        f"\n\n(Note: {n} additional tool call{'s' if n != 1 else ''} {verb} proposed "
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
    single-chunk tool_calls (arguments arrive as a whole dict already).

    Some providers behind LiteLLM omit `index` entirely on every fragment of
    a call. A fragment carrying an explicit `index` always opens/continues
    that exact slot; a fragment with no `index` continues whichever slot was
    most recently opened, except the very first fragment ever seen, which
    opens a new slot. This keeps a single index-less call's fragments
    together instead of shredding them into one slot per fragment.

    Ollama's native tool_calls shape also omits `index`, but each entry is a
    COMPLETE, STANDALONE call with its own `function.name` — never a
    continuation fragment of the previous one (a genuine continuation only
    ever repeats `arguments`, never `name`). So an index-less fragment that
    carries a name while the most-recently-opened slot already has one is
    treated as a new call and opens a new slot, rather than overwriting the
    slot in place."""

    def __init__(self) -> None:
        self._by_index: Dict[int, dict] = {}
        self._order: List[int] = []

    def add(self, fragment: dict) -> None:
        fn = fragment.get("function") or {}
        incoming_name = fn.get("name")
        if "index" in fragment:
            index = fragment["index"]
        elif self._order and not (incoming_name and self._by_index[self._order[-1]]["name"]):
            # No explicit index: continue the most recently opened slot UNLESS
            # this fragment brings its own name while that slot already has
            # one — that's a second complete call arriving without an index
            # (e.g. Ollama's per-item tool_calls shape, where every entry is a
            # standalone call carrying its own name), not a continuation
            # fragment of the same call (which never repeats the name).
            index = self._order[-1]
        else:
            index = len(self._order)
        if index not in self._by_index:
            self._by_index[index] = {"id": "", "name": "", "arguments": ""}
            self._order.append(index)
        entry = self._by_index[index]
        if fragment.get("id"):
            entry["id"] = fragment["id"]
        if incoming_name:
            entry["name"] = incoming_name
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


# ── route_turn_stream — content streams in real time; a tool_call is never
#    dropped regardless of when it arrives relative to content ────────────
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
    # Step 15f-ii: bound the stream per-chunk, not in total. A backend that
    # accepts the connection but never emits a token -- or dies mid-generation --
    # otherwise hangs the user's turn with no upper bound at all. The cap is
    # time-to-first-event and time-between-events, so a legitimately long
    # generation is never killed for being long. No retry: replaying a
    # partially-delivered stream would repeat tokens the user already saw.
    events = retry_policy.stream_with_budget(events, retry_policy.budget_for("brain"))
    td = TurnDecision(decision="answer", reason="no tool call emitted")
    return td, _stream_and_maybe_dispatch(events, td, message, tool_call_handler)


async def _stream_and_maybe_dispatch(
    events: AsyncIterator[dict],
    td: TurnDecision,
    message: str,
    tool_call_handler: Optional[Callable[[str, dict, str], Awaitable[str]]],
) -> AsyncIterator[str]:
    """Forwards content deltas in real time as they arrive. Tool_call
    fragments are accumulated silently throughout, regardless of when they
    arrive relative to content — the model's own tool_call is never dropped
    (fix-forward Important #1). If any tool_call completed by stream end,
    the dispatch runs and its result is appended after a visible separator
    only when content was actually streamed first; a pure tool_call turn
    (no preceding content) is unchanged from before this fix — a single
    chunk, no separator. `td` is mutated in place once the true outcome is
    known, since it can't be determined before the stream ends."""
    accumulator = _ToolCallAccumulator()
    any_content = False
    async for ev in events:
        if "tool_call_delta" in ev:
            accumulator.add(ev["tool_call_delta"])
            continue
        content = ev.get("content")
        if content:
            any_content = True
            yield content

    tool_calls = accumulator.finish()
    if not tool_calls:
        return

    primary = tool_calls[0]
    extra_note = _dropped_calls_note(tool_calls)
    td.decision = "dispatch"
    td.reason = f"tool_call: {primary.name}"
    if tool_call_handler is None:
        reply = _DISPATCH_FALLBACK
    else:
        reply = await tool_call_handler(primary.name, primary.arguments, message)
    if any_content:
        yield "\n\n---\n"
    yield reply + extra_note


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
