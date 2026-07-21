"""
COOPER Core — FastAPI conversational runtime.

WORKSHOP env var selects the backend:
  open    (default) — GPT-4o-mini via LiteLLM's governed gateway (the "openai" alias).
                       Requires OPENAI_API_KEY to hold LiteLLM's master key, not a raw OpenAI key.
  private           — COOPER-Private (Ollama, local gemma4:12b weights). Fully local.

Endpoints:
  GET  /health                — liveness + active workshop/model info
  POST /chat                  — {message, history} -> {reply, decision, reason}
  GET  /v1/models             — OpenAI-compatible model list (for Open WebUI)
  POST /v1/chat/completions   — OpenAI-compatible chat; stream=true uses real streaming
"""
import asyncio
import hashlib
import json
import os
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import AsyncIterator, List, Optional

import httpx
from fastapi import Depends, FastAPI, HTTPException, Security
from fastapi.responses import StreamingResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field

from decision import TurnDecision, route_turn, route_turn_stream
import registry
import approval
import executor
import review
import workshop
import archivist
import proposer
import skills
import gateway

# ── Config ─────────────────────────────────────────────────────────────────────
_REPO_ROOT = Path(__file__).resolve().parent.parent
_MODELFILE  = _REPO_ROOT / "Models" / "cooper-personality" / "Modelfile"

WORKSHOP = os.environ.get("WORKSHOP", "open").strip().lower()

# Ollama (used by private workshop and as classifier fallback)
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")

# OpenAI (used by open workshop, routed through LiteLLM's governed gateway rather
# than directly — see Docs/superpowers/specs/2026-07-07-open-workshop-containerization-design.md §2)
OPENAI_BASE_URL = os.environ.get("OPENAI_BASE_URL", "http://litellm:4000/v1")
OPENAI_API_KEY  = os.environ.get("OPENAI_API_KEY", "")

# Per-workshop model and backend selection
if WORKSHOP == "private":
    BACKEND          = "ollama"
    COOPER_MODEL     = os.environ.get("COOPER_MODEL", "COOPER-Private")
    CLASSIFIER_MODEL = os.environ.get("COOPER_CLASSIFIER_MODEL", "COOPER-Private")
    BACKEND_URL      = OLLAMA_HOST
    BACKEND_KEY      = "ollama"
else:  # open
    BACKEND          = "openai"
    COOPER_MODEL     = os.environ.get("COOPER_MODEL", "openai")
    CLASSIFIER_MODEL = os.environ.get("COOPER_CLASSIFIER_MODEL", "openai")
    BACKEND_URL      = OPENAI_BASE_URL
    BACKEND_KEY      = OPENAI_API_KEY

# Branded id reported to OpenAI-compatible clients (Open WebUI's model dropdown, etc.)
# — decoupled from COOPER_MODEL so Open Workshop's real backend model (the "openai" LiteLLM
# alias, itself resolving to gpt-4o-mini) never has to leak into the UI.
DISPLAY_MODEL = f"COOPER-{WORKSHOP.capitalize()}"


def _load_system_prompt() -> str:
    if not _MODELFILE.exists():
        return (
            "You are COOPER (Command Operations Orchestrator for Planning, Execution, "
            "and Reporting). TARS-inspired. Direct, concise, dry humor at 35%, "
            "professionalism at 90%. Lead with the answer. Surface risks early."
        )
    text = _MODELFILE.read_text(encoding="utf-8")
    start = text.find('SYSTEM """')
    if start == -1:
        return ""
    start += len('SYSTEM """')
    end = text.find('"""', start)
    return text[start:end].strip() if end != -1 else ""


SYSTEM_PROMPT = _load_system_prompt()

# ── Archivist (Step 8) ───────────────────────────────────────────────────────────
_ARCHIVIST_CONN = archivist.get_conn()

# ── Auth ───────────────────────────────────────────────────────────────────────
_bearer     = HTTPBearer(auto_error=False)
_ALLOW_ANON = os.environ.get("COOPER_ALLOW_ANON", "").strip() == "1"


def _parse_api_keys(keys_env: str, legacy_key: str) -> set:
    """COOPER_API_KEYS (comma-separated, one per client) + legacy COOPER_API_KEY."""
    keys = {k.strip() for k in keys_env.split(",") if k.strip()}
    if legacy_key.strip():
        keys.add(legacy_key.strip())
    return keys


_API_KEYS = _parse_api_keys(
    os.environ.get("COOPER_API_KEYS", ""),
    os.environ.get("COOPER_API_KEY", ""),
)


def _check_auth_config(api_keys: set, allow_anon: bool) -> None:
    """Startup gate: anonymous auth on a network-exposed port must be explicit."""
    if not api_keys and not allow_anon:
        raise RuntimeError(
            "No COOPER_API_KEYS/COOPER_API_KEY set and COOPER_ALLOW_ANON != 1. "
            "Refusing to start with anonymous auth."
        )


def _require_auth(
    creds: Optional[HTTPAuthorizationCredentials] = Security(_bearer),
) -> None:
    if _API_KEYS and (not creds or creds.credentials not in _API_KEYS):
        raise HTTPException(status_code=401, detail="Unauthorized")


def _derive_session_id(token: Optional[str]) -> str:
    """Session identity = the credential presented (Step 13). Each client key is
    its own approval domain; anonymous clients share the 'anon' domain."""
    if not token:
        return "anon"
    return hashlib.sha256(token.encode("utf-8")).hexdigest()[:12]


def _session_id(
    creds: Optional[HTTPAuthorizationCredentials] = Security(_bearer),
) -> str:
    return _derive_session_id(creds.credentials if creds else None)


async def _handle_dispatch(message: str, session_id: str = "local") -> str:
    """
    Quartermaster selects a tool; Safety Officer gates it; Workbench executes
    if the gate passes. L0/L1 auto-run immediately. L2+ halts for approval.
    """
    # Enforce backend integrity before doing anything else
    try:
        workshop.check_backend(BACKEND, WORKSHOP)
    except workshop.WorkshopViolation as exc:
        return f"Workshop violation: {exc}"

    tool = await registry.select_tool_llm(
        WORKSHOP, message,
        base_url=BACKEND_URL, api_key=BACKEND_KEY,
        model=CLASSIFIER_MODEL, backend=BACKEND,
    )
    if tool is None:
        return (
            "Acknowledged. No registered tool in the active workshop matches this "
            "request. Nothing will run — check the registry or rephrase."
        )

    # Enforce workshop boundary before gating or executing
    try:
        workshop.check_tool(tool, WORKSHOP)
    except workshop.WorkshopViolation as exc:
        return f"Workshop violation: {exc}"

    skill_note = ""
    skill = await asyncio.to_thread(
        archivist.get_skill, _ARCHIVIST_CONN, tool.get("name", tool.get("id", "unknown"))
    )
    if skill is not None and skill.trust_score > 0.5:
        skill_note = (
            f" (matches a proven skill — {skill.successful_run_count} successful "
            f"run{'s' if skill.successful_run_count != 1 else ''}, "
            f"{skill.trust_score:.0%} trust)"
        )

    if approval.needs_approval(tool):
        preview = ""
        if tool.get("executor_type") == "skill_import":
            try:
                text = await asyncio.to_thread(skills.preview_import, message)
                preview = f"\n\nSKILL.md under review:\n---\n{text}\n---"
            except skills.SkillError as exc:
                return f"Skill import rejected before approval: {exc}"
            except Exception as exc:
                return f"Skill import rejected before approval (unexpected error): {exc}"
        approval.request(WORKSHOP, tool, message, session_id)
        return (
            f"Halt — {tool.get('name', tool.get('id'))} "
            f"[{tool.get('drawer', 'Uncategorized')}, permission level {tool.get('permission_level', '?')}] "
            f"requires approval before it can proceed{skill_note}. Reply 'approve' or 'deny'."
            f"{preview}"
        )

    # L0/L1: execute immediately
    if skill_note:
        print(f"  [archivist] {tool.get('name')}{skill_note}")
    return await _execute(tool, message)


async def _execute(tool: dict, message: str) -> str:
    """
    Run an approved/auto-run tool through the Workbench (Worker), then have
    the Reviewer check the result (Step 7) and the Archivist remember it
    (Step 8) before it reaches the user.
    """
    try:
        raw_output = await executor.run(tool, message, WORKSHOP)
    except executor.ExecutionError as exc:
        return f"Workbench error: {exc}"

    verdict = await review.review(
        tool, message, raw_output,
        base_url=BACKEND_URL,
        api_key=BACKEND_KEY,
        model=CLASSIFIER_MODEL,
        backend=BACKEND,
    )

    try:
        await archivist.remember(
            _ARCHIVIST_CONN, tool, message, raw_output, verdict, WORKSHOP,
            base_url=BACKEND_URL, api_key=BACKEND_KEY,
            model=CLASSIFIER_MODEL, backend=BACKEND,
        )
    except Exception as exc:
        print(f"  [!!] archivist.remember failed (non-fatal): {exc}")

    draft_offer = ""
    if verdict.verdict == "pass":
        try:
            draft_dir = await proposer.draft_skill(
                tool, message, raw_output,
                base_url=BACKEND_URL, api_key=BACKEND_KEY,
                model=CLASSIFIER_MODEL, backend=BACKEND,
            )
            draft_offer = proposer.offer_line(draft_dir)
        except Exception as exc:
            print(f"  [!!] proposer failed (non-fatal): {exc}")

    return review.govern(raw_output, verdict) + draft_offer


async def _resolve_approval(message: str, session_id: str = "local") -> str:
    """
    Consume the pending ticket and execute on approve, or cancel on deny.
    Called only when approval.has_pending() and approval.is_response() are both true.
    """
    if approval.is_denied(message):
        ticket = approval.consume(WORKSHOP, session_id)
        if ticket is None:
            return "No pending action to cancel."
        name = ticket.tool.get("name", ticket.tool.get("id"))
        return f"Cancelled. {name} will not run."

    ticket = approval.consume(WORKSHOP, session_id)
    if ticket is None:
        return "No pending action to approve. Nothing queued."

    return await _execute(ticket.tool, ticket.message)


async def _chat_core(message: str, history: List[dict], session_id: str = "local") -> tuple:
    """One routing path for every front door (HTTP endpoints + gateway):
    registry/skill catalog queries, approval responses, then route_turn."""
    if registry.is_registry_query(message):
        return registry.format_tool_list(WORKSHOP), TurnDecision(
            decision="answer", reason="registry query answered directly by Quartermaster")
    if skills.is_skill_query(message):
        return skills.format_skill_list(WORKSHOP), TurnDecision(
            decision="answer", reason="skill catalog answered directly")
    if approval.has_pending(WORKSHOP, session_id) and approval.is_response(message):
        return await _resolve_approval(message, session_id), TurnDecision(
            decision="answer", reason="approval gate resolved")
    return await route_turn(
        message, history,
        generate_answer=_generate,
        base_url=BACKEND_URL, api_key=BACKEND_KEY,
        model=COOPER_MODEL, classifier_model=CLASSIFIER_MODEL,
        backend=BACKEND, dispatch_handler=lambda m: _handle_dispatch(m, session_id),
    )


# ── Startup ────────────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    _check_auth_config(_API_KEYS, _ALLOW_ANON)
    print(f"\n  workshop : {WORKSHOP}")
    print(f"  backend  : {BACKEND}")
    print(f"  model    : {COOPER_MODEL}")
    print(f"  classify : {CLASSIFIER_MODEL}")

    if BACKEND == "ollama":
        async with httpx.AsyncClient(timeout=5.0) as client:
            try:
                resp = await client.get(f"{OLLAMA_HOST}/api/tags")
                models = [m["name"] for m in resp.json().get("models", [])]
                known = {m.lower() for m in models} | {m.split(":")[0].lower() for m in models}
                for name in {COOPER_MODEL, CLASSIFIER_MODEL}:
                    ok = name.lower() in known
                    print(f"  {'[ok]' if ok else '[!!]'} ollama model: {name}")
            except Exception as exc:
                print(f"  [!!] cannot reach Ollama at {OLLAMA_HOST}: {exc}")
    else:
        if not OPENAI_API_KEY:
            print("  [!!] OPENAI_API_KEY is not set - Open Workshop will fail on generation")
        else:
            print(f"  [ok] OPENAI_API_KEY present ({len(OPENAI_API_KEY)} chars)")

    # Workshop boundary integrity check
    try:
        workshop.check_backend(BACKEND, WORKSHOP)
        print(f"  [ok] workshop boundary: {WORKSHOP} -> {BACKEND}")
    except workshop.WorkshopViolation as exc:
        print(f"  [!!] WORKSHOP VIOLATION at startup: {exc}")

    archivist.init_db(_ARCHIVIST_CONN)
    archivist.index_brain(_ARCHIVIST_CONN, force=True)
    print("  [ok] archivist: schema ready, brain indexed")

    gateway_task = None
    if os.environ.get("GATEWAY_ENABLED", "").strip() == "1":
        if WORKSHOP != "open":
            print("  [!!] GATEWAY_ENABLED=1 but workshop is not 'open' — gateway refused (spec §5)")
        else:
            gw_cfg = gateway.load_config()
            if gw_cfg is None:
                print("  [!!] gateway enabled but SIGNAL_API_URL/SIGNAL_NUMBER/SIGNAL_ALLOWED_SENDERS incomplete — not started (fail closed)")
            else:
                async def _gateway_handler(text: str, sender: str) -> str:
                    reply, _td = await _chat_core(text, [], session_id=f"signal:{sender}")
                    return reply
                gateway_task = asyncio.create_task(gateway.run_loop(gw_cfg, _gateway_handler))

    print()
    yield

    if gateway_task is not None:
        gateway_task.cancel()
        try:
            await gateway_task
        except asyncio.CancelledError:
            pass


app = FastAPI(title="COOPER Core", version="2.1.0", lifespan=lifespan)


# ── Health ─────────────────────────────────────────────────────────────────────
@app.get("/health")
async def health():
    return {
        "status":     "ok",
        "workshop":   WORKSHOP,
        "backend":    BACKEND,
        "model":      COOPER_MODEL,
        "classifier": CLASSIFIER_MODEL,
    }


# ── Registry (Quartermaster) ────────────────────────────────────────────────
@app.get("/tools", dependencies=[Depends(_require_auth)])
async def list_tools():
    try:
        tools = registry.list_tools(WORKSHOP)
    except registry.RegistryError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    return {"workshop": WORKSHOP, "count": len(tools), "tools": tools}


# ── Skills (Step 10) ─────────────────────────────────────────────────────────
@app.get("/skills", dependencies=[Depends(_require_auth)])
async def list_skill_registry():
    entries = skills.load_manifest()
    report = []
    for e in entries:
        if str(e.get("workshop", "open")).lower() != WORKSHOP:
            continue
        try:
            status = skills.skill_status(e)
        except Exception as exc:
            print(f"  [!!] skill status check failed for '{e.get('id')}': {exc}")
            status = "error"
        report.append({
            "id":               e.get("id"),
            "path":             e.get("path"),
            "permission_level": e.get("permission_level"),
            "status":           status,
        })
    return {"workshop": WORKSHOP, "count": len(report), "skills": report}


# ── Approval gate (Safety Officer) ──────────────────────────────────────────
@app.get("/pending", dependencies=[Depends(_require_auth)])
async def pending(session_id: str = Depends(_session_id)):
    ticket = approval.peek(WORKSHOP, session_id)
    if ticket is None:
        return {"workshop": WORKSHOP, "pending": None}
    return {
        "workshop": WORKSHOP,
        "pending": {
            "id":                ticket.id,
            "tool":              ticket.tool.get("name", ticket.tool.get("id")),
            "permission_level":  ticket.tool.get("permission_level"),
            "requested_message": ticket.message,
            "age_seconds":       round(time.time() - ticket.created_at, 1),
        },
    }


# ── Workshop status ───────────────────────────────────────────────────────────
@app.get("/workshop", dependencies=[Depends(_require_auth)])
async def workshop_status():
    violation = None
    try:
        workshop.check_backend(BACKEND, WORKSHOP)
    except workshop.WorkshopViolation as exc:
        violation = str(exc)
    return {
        "workshop":  WORKSHOP,
        "backend":   BACKEND,
        "model":     COOPER_MODEL,
        "boundary":  "enforced" if violation is None else "VIOLATED",
        "violation": violation,
    }


# ── POST /chat ────────────────────────────────────────────────────────────────
class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=32_000)
    history: List[dict] = Field(default=[], max_length=50)


class ChatResponse(BaseModel):
    reply:    str
    decision: str = "answer"
    reason:   str = ""


@app.post("/chat", response_model=ChatResponse, dependencies=[Depends(_require_auth)])
async def chat(req: ChatRequest, session_id: str = Depends(_session_id)):
    reply, td = await _chat_core(req.message, req.history, session_id)
    return {"reply": reply, "decision": td.decision, "reason": td.reason}


# ── OpenAI-compatible endpoints ────────────────────────────────────────────────
@app.get("/v1/models", dependencies=[Depends(_require_auth)])
async def list_models():
    return {
        "object": "list",
        "data": [{
            "id":       DISPLAY_MODEL,
            "object":   "model",
            "created":  0,
            "owned_by": f"cooper-{WORKSHOP}",
        }],
    }


class _OAIMessage(BaseModel):
    role:    str
    content: str


class _OAIChatRequest(BaseModel):
    model:       Optional[str]   = None
    messages:    List[_OAIMessage]
    stream:      bool            = False
    temperature: Optional[float] = None
    max_tokens:  Optional[int]   = None


def _estimate_usage(messages: List[_OAIMessage], reply: str) -> dict:
    prompt_chars = sum(len(m.content) for m in messages)
    return {
        "prompt_tokens": prompt_chars // 4,
        "completion_tokens": len(reply) // 4,
        "total_tokens": (prompt_chars + len(reply)) // 4,
    }


@app.post("/v1/chat/completions", dependencies=[Depends(_require_auth)])
async def oai_chat(req: _OAIChatRequest, session_id: str = Depends(_session_id)):
    if not req.messages:
        raise HTTPException(status_code=422, detail="messages list is empty")

    non_system = [m for m in req.messages if m.role != "system"]
    if not non_system:
        raise HTTPException(status_code=422, detail="no non-system messages")

    last    = non_system[-1]
    message = last.content if last.role == "user" else ""
    history = [{"role": m.role, "content": m.content} for m in non_system[:-1]]

    if req.stream:
        return StreamingResponse(
            _stream_sse(message, history, session_id),
            media_type="text/event-stream",
            headers={"X-Accel-Buffering": "no", "Cache-Control": "no-cache"},
        )

    reply, td = await _chat_core(message, history, session_id)
    request_id = f"chatcmpl-{uuid.uuid4().hex[:8]}"
    return {
        "id":      request_id,
        "object":  "chat.completion",
        "created": int(time.time()),
        "model":   DISPLAY_MODEL,
        "choices": [{
            "index":        0,
            "message":      {"role": "assistant", "content": reply},
            "finish_reason": "stop",
        }],
        # chars/4 estimate — backends don't surface real counts through this path
        "usage": _estimate_usage(req.messages, reply),
    }


# ── SSE streaming ──────────────────────────────────────────────────────────────
async def _stream_sse(message: str, history: List[dict], session_id: str = "local") -> AsyncIterator[str]:
    request_id = f"chatcmpl-{uuid.uuid4().hex[:8]}"
    created    = int(time.time())

    try:
        if registry.is_registry_query(message):
            content_iter = _single_text_chunk(registry.format_tool_list(WORKSHOP))
        elif skills.is_skill_query(message):
            content_iter = _single_text_chunk(skills.format_skill_list(WORKSHOP))
        elif approval.has_pending(WORKSHOP, session_id) and approval.is_response(message):
            content_iter = _single_text_chunk(await _resolve_approval(message, session_id))
        else:
            system_prompt = SYSTEM_PROMPT
            try:
                await asyncio.to_thread(archivist.index_brain, _ARCHIVIST_CONN)
                recall_context = archivist.format_recall_context(
                    await asyncio.to_thread(archivist.recall, _ARCHIVIST_CONN, message)
                )
                if recall_context:
                    system_prompt = f"{SYSTEM_PROMPT}\n\n{recall_context}"
            except Exception as exc:
                print(f"  [!!] archivist.recall failed (non-fatal): {exc}")
            try:
                skill_ctx = skills.skill_context_for(WORKSHOP, message)
            except Exception as exc:
                print(f"  [!!] skill context injection failed (non-fatal): {exc}")
                skill_ctx = ""
            if skill_ctx:
                system_prompt = f"{system_prompt}\n\n{skill_ctx}"
            td, content_iter = await route_turn_stream(
                message,
                history,
                system_prompt=system_prompt,
                base_url=BACKEND_URL,
                api_key=BACKEND_KEY,
                model=COOPER_MODEL,
                classifier_model=CLASSIFIER_MODEL,
                backend=BACKEND,
                dispatch_handler=lambda m: _handle_dispatch(m, session_id),
            )

        async for chunk in content_iter:
            data = {
                "id":      request_id,
                "object":  "chat.completion.chunk",
                "created": created,
                "model":   DISPLAY_MODEL,
                "choices": [{"index": 0, "delta": {"content": chunk}, "finish_reason": None}],
            }
            yield f"data: {json.dumps(data)}\n\n"

    except Exception as exc:
        err = {
            "id":      request_id,
            "object":  "chat.completion.chunk",
            "created": created,
            "model":   DISPLAY_MODEL,
            "choices": [{"index": 0, "delta": {"content": f"[COOPER error: {exc}]"}, "finish_reason": None}],
        }
        yield f"data: {json.dumps(err)}\n\n"

    yield f"data: {json.dumps({'id': request_id, 'object': 'chat.completion.chunk', 'created': created, 'model': DISPLAY_MODEL, 'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'stop'}]})}\n\n"
    yield "data: [DONE]\n\n"


# ── Generation helper (for blocking route_turn) ────────────────────────────────
async def _single_text_chunk(text: str) -> AsyncIterator[str]:
    yield text


async def _generate(message: str, history: List[dict]) -> str:
    try:
        await asyncio.to_thread(archivist.index_brain, _ARCHIVIST_CONN)
        recall_context = archivist.format_recall_context(
            await asyncio.to_thread(archivist.recall, _ARCHIVIST_CONN, message)
        )
    except Exception as exc:
        print(f"  [!!] archivist.recall failed (non-fatal): {exc}")
        recall_context = ""
    try:
        skill_ctx = skills.skill_context_for(WORKSHOP, message)
    except Exception as exc:
        print(f"  [!!] skill context injection failed (non-fatal): {exc}")
        skill_ctx = ""
    msgs = _build_messages(history, message)
    if recall_context:
        msgs.insert(1, {"role": "system", "content": recall_context})
    if skill_ctx:
        msgs.insert(1, {"role": "system", "content": skill_ctx})
    if BACKEND == "openai":
        from decision import _openai_complete
        return await _openai_complete(BACKEND_URL, BACKEND_KEY, COOPER_MODEL, msgs)
    from decision import _ollama_complete
    return await _ollama_complete(BACKEND_URL, COOPER_MODEL, msgs)


def _build_messages(history: List[dict], user_message: str) -> List[dict]:
    msgs: List[dict] = [{"role": "system", "content": SYSTEM_PROMPT}]
    for turn in history:
        if turn.get("role") != "system":
            msgs.append({"role": turn["role"], "content": turn.get("content", "")})
    if user_message.strip():
        msgs.append({"role": "user", "content": user_message})
    return msgs
