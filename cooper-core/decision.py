"""
COOPER decision layer — classify each turn before generating a reply.

Supports two backends selected by WORKSHOP env var:
  open    → OpenAI API (gpt-4o-mini). Classify via json_schema, generate via /v1 streaming.
  private → Ollama native (gemma4:12b). Classify via format+schema, generate via /api/chat streaming.

Public API
----------
route_turn(message, history, *, generate_answer, base_url, api_key, model, classifier_model, backend)
  Blocking.  Used by POST /chat and POST /v1/chat/completions stream=False.

route_turn_stream(message, history, *, system_prompt, base_url, api_key, model, classifier_model, backend)
  -> (TurnDecision, AsyncIterator[str])
  Classifies (blocking), returns a streaming content iterator.

Decisions
---------
  answer   — COOPER can answer directly
  clarify  — request too vague; return one clarifying question
  dispatch — specific actionable task; return stub (step 3 wires execution)
"""
import json
from dataclasses import dataclass
from typing import AsyncIterator, Awaitable, Callable, List, Optional, Tuple

import httpx

# ── Classifier prompt ──────────────────────────────────────────────────────────
_CLASSIFIER_SYSTEM = """\
Classify the user message into one of three categories. Output JSON only — no other text.

CATEGORIES:
  dispatch — the message contains a concrete verb AND a named noun (logs, server, files, database, certs, cache, backups, etc.). Dispatch even when the exact path or time range is unspecified — the executor handles specifics.
  clarify  — the verb is concrete but the object is ONLY a pronoun or demonstrative with no named noun ("it", "that", "those", "this", "them", "things").
  answer   — everything else: questions, greetings, statements, requests for information.

EXAMPLES (use these to calibrate):
"archive last week's logs"   → {"decision":"dispatch","reason":"verb+named noun"}
"restart the API server"     → {"decision":"dispatch","reason":"verb+named noun"}
"delete temp files"          → {"decision":"dispatch","reason":"verb+named noun"}
"back up the database"       → {"decision":"dispatch","reason":"verb+named noun"}
"rotate the certs"           → {"decision":"dispatch","reason":"verb+named noun"}
"sort it out"                → {"decision":"clarify","reason":"pronoun object, no named noun"}
"fix that"                   → {"decision":"clarify","reason":"demonstrative object, no named noun"}
"handle those things"        → {"decision":"clarify","reason":"pronoun object, no named noun"}
"how are you"                → {"decision":"answer","reason":"greeting"}
"what is the disk usage"     → {"decision":"answer","reason":"information request"}

Output format — JSON only:
{"decision":"answer"|"clarify"|"dispatch","reason":"<brief phrase>"}\
"""

# ── Clarify prompt ─────────────────────────────────────────────────────────────
_CLARIFY_SYSTEM = """\
You are COOPER. The user's request is too vague to execute safely.
Ask exactly ONE short, direct clarifying question.
Do not explain why. Do not offer options. One question only.\
"""

# ── Dispatch fallback (used only if no dispatch_handler is wired) ─────────────
_DISPATCH_FALLBACK = "Acknowledged. No dispatch handler is wired for this request."

VALID_DECISIONS  = frozenset({"answer", "clarify", "dispatch"})
BACKENDS         = frozenset({"ollama", "openai"})
_ALLOWED_ROLES   = frozenset({"user", "assistant"})
_MAX_HISTORY_CONTENT = 500


def _truncate(s: str, n: int = _MAX_HISTORY_CONTENT) -> str:
    return s[:n] + "…" if len(s) > n else s


@dataclass
class TurnDecision:
    decision: str  # "answer" | "clarify" | "dispatch"
    reason: str


# ── route_turn — blocking two-call ────────────────────────────────────────────
async def route_turn(
    message: str,
    history: List[dict],
    *,
    generate_answer: Callable[..., Awaitable[str]],
    base_url: str,
    api_key: str,
    model: str,
    classifier_model: str,
    backend: str = "ollama",
    dispatch_handler: Optional[Callable[[str], Awaitable[str]]] = None,
) -> Tuple[str, TurnDecision]:
    td = await _classify(
        message, history,
        base_url=base_url, api_key=api_key,
        model=classifier_model, backend=backend,
    )

    if td.decision == "dispatch":
        reply = await dispatch_handler(message) if dispatch_handler else _DISPATCH_FALLBACK
        return reply, td

    if td.decision == "clarify":
        try:
            reply = await _clarify(
                message, history,
                base_url=base_url, api_key=api_key,
                model=model, backend=backend,
            )
        except Exception as exc:
            reply = f"[COOPER error: backend unavailable — {exc}]"
        return reply, td

    try:
        reply = await generate_answer(message, history)
    except Exception as exc:
        reply = f"[COOPER error: backend unavailable — {exc}]"
    return reply, td


# ── route_turn_stream — classify then stream ──────────────────────────────────
async def route_turn_stream(
    message: str,
    history: List[dict],
    *,
    system_prompt: str,
    base_url: str,
    api_key: str,
    model: str,
    classifier_model: str,
    backend: str = "ollama",
    dispatch_handler: Optional[Callable[[str], Awaitable[str]]] = None,
) -> Tuple[TurnDecision, AsyncIterator[str]]:
    td = await _classify(
        message, history,
        base_url=base_url, api_key=api_key,
        model=classifier_model, backend=backend,
    )

    if td.decision == "dispatch":
        reply = await dispatch_handler(message) if dispatch_handler else _DISPATCH_FALLBACK
        return td, _single_chunk(reply)

    if td.decision == "clarify":
        msgs = _build_clarify_messages(message, history)
        return td, _stream_chat(base_url, api_key, model, msgs, backend=backend)

    msgs = _build_answer_messages(message, history, system_prompt)
    return td, _stream_chat(base_url, api_key, model, msgs, backend=backend)


# ── Classification ─────────────────────────────────────────────────────────────
async def _classify(
    message: str,
    history: List[dict],
    *,
    base_url: str,
    api_key: str,
    model: str,
    backend: str,
) -> TurnDecision:
    history_block = ""
    if history:
        lines = [
            f"{t.get('role','user').upper()}: {_truncate(t.get('content',''))}"
            for t in history[-4:] if t.get("role") in _ALLOWED_ROLES
        ]
        if lines:
            history_block = "\n\nRecent conversation:\n" + "\n".join(lines)

    messages = [
        {"role": "system", "content": _CLASSIFIER_SYSTEM},
        {"role": "user", "content": f"User message: {message}{history_block}"},
    ]

    try:
        if backend == "openai":
            raw = await _openai_complete(
                base_url, api_key, model, messages,
                temperature=0,
                response_format={
                    "type": "json_schema",
                    "json_schema": {
                        "name": "classification",
                        "strict": True,
                        "schema": {
                            "type": "object",
                            "properties": {
                                "decision": {"type": "string", "enum": ["answer", "clarify", "dispatch"]},
                                "reason":   {"type": "string"},
                            },
                            "required": ["decision", "reason"],
                            "additionalProperties": False,
                        },
                    },
                },
            )
        else:
            raw = await _ollama_complete(
                base_url, model, messages,
                options={"temperature": 0},
                fmt={
                    "type": "object",
                    "properties": {
                        "decision": {"type": "string", "enum": ["answer", "clarify", "dispatch"]},
                        "reason":   {"type": "string"},
                    },
                    "required": ["decision", "reason"],
                },
            )

        data = json.loads(raw)
        decision = data.get("decision", "answer")
        if decision not in VALID_DECISIONS:
            decision = "answer"
        return TurnDecision(decision=decision, reason=data.get("reason", ""))

    except Exception as exc:
        return TurnDecision(decision="answer", reason=f"classifier error (safe fallback): {exc}")


# ── Clarify ────────────────────────────────────────────────────────────────────
async def _clarify(
    message: str,
    history: List[dict],
    *,
    base_url: str,
    api_key: str,
    model: str,
    backend: str,
) -> str:
    msgs = _build_clarify_messages(message, history)
    if backend == "openai":
        return await _openai_complete(base_url, api_key, model, msgs)
    return await _ollama_complete(base_url, model, msgs)


# ── Streaming ──────────────────────────────────────────────────────────────────
async def _stream_chat(
    base_url: str,
    api_key: str,
    model: str,
    messages: List[dict],
    *,
    backend: str,
) -> AsyncIterator[str]:
    if backend == "openai":
        async for chunk in _stream_openai_chat(base_url, api_key, model, messages):
            yield chunk
    else:
        async for chunk in _stream_ollama_chat(base_url, model, messages):
            yield chunk


async def _stream_ollama_chat(
    base_url: str, model: str, messages: List[dict]
) -> AsyncIterator[str]:
    payload = {"model": model, "messages": messages, "stream": True, "think": False}
    async with httpx.AsyncClient(timeout=120.0) as client:
        async with client.stream("POST", f"{base_url}/api/chat", json=payload) as resp:
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                if not line.strip():
                    continue
                try:
                    data = json.loads(line)
                    chunk = data.get("message", {}).get("content", "")
                    if chunk:
                        yield chunk
                    if data.get("done", False):
                        return
                except json.JSONDecodeError:
                    continue


async def _stream_openai_chat(
    base_url: str, api_key: str, model: str, messages: List[dict]
) -> AsyncIterator[str]:
    payload = {"model": model, "messages": messages, "stream": True}
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    async with httpx.AsyncClient(timeout=120.0) as client:
        async with client.stream(
            "POST", f"{base_url}/chat/completions", json=payload, headers=headers
        ) as resp:
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                if not line.strip() or line == "data: [DONE]":
                    continue
                if line.startswith("data: "):
                    try:
                        data = json.loads(line[6:])
                        chunk = data["choices"][0]["delta"].get("content", "")
                        if chunk:
                            yield chunk
                    except (json.JSONDecodeError, KeyError, IndexError):
                        continue


# ── Blocking completions ───────────────────────────────────────────────────────
async def _ollama_complete(
    base_url: str,
    model: str,
    messages: List[dict],
    *,
    options: Optional[dict] = None,
    fmt: Optional[dict] = None,
) -> str:
    # think=false prevents gemma4/thinking-capable models from running extended
    # reasoning before the response, which adds 30-50s per call.
    payload: dict = {"model": model, "messages": messages, "stream": False, "think": False}
    if options:
        payload["options"] = options
    if fmt:
        payload["format"] = fmt
    async with httpx.AsyncClient(timeout=120.0) as client:
        resp = await client.post(f"{base_url}/api/chat", json=payload)
        resp.raise_for_status()
        return resp.json()["message"]["content"]


async def _openai_complete(
    base_url: str,
    api_key: str,
    model: str,
    messages: List[dict],
    *,
    temperature: Optional[float] = None,
    response_format: Optional[dict] = None,
) -> str:
    payload: dict = {"model": model, "messages": messages}
    if temperature is not None:
        payload["temperature"] = temperature
    if response_format:
        payload["response_format"] = response_format
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(
            f"{base_url}/chat/completions", json=payload, headers=headers
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]


# ── Message builders ───────────────────────────────────────────────────────────
def _build_clarify_messages(message: str, history: List[dict]) -> List[dict]:
    msgs: List[dict] = [{"role": "system", "content": _CLARIFY_SYSTEM}]
    for turn in history[-4:]:
        if turn.get("role") in _ALLOWED_ROLES:
            msgs.append({"role": turn["role"], "content": turn.get("content", "")})
    msgs.append({"role": "user", "content": message})
    return msgs


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


# ── Utilities ──────────────────────────────────────────────────────────────────
async def _single_chunk(text: str) -> AsyncIterator[str]:
    yield text
