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
import embeddings
import proposer
import skills
import gateway
import model_routing

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

# Per-workshop backend selection
if WORKSHOP == "private":
    BACKEND          = "ollama"
    BACKEND_URL      = OLLAMA_HOST
    BACKEND_KEY      = "ollama"
else:  # open
    BACKEND          = "openai"
    BACKEND_URL      = OPENAI_BASE_URL
    BACKEND_KEY      = OPENAI_API_KEY

# Per-role model routing (Step 15c): Scripts/PDA_ModelRouting.json is the source of
# truth. COOPER_MODEL stays overridable via env var for the documented bare-metal dev
# path (CLAUDE.md); the other three live roles resolve straight from the map — each
# call site below names its own role explicitly so a future slice (15d/15e) can point
# one role at a different alias by editing the JSON alone.
COOPER_MODEL    = os.environ.get("COOPER_MODEL", model_routing.model_for("brain", WORKSHOP))
REVIEWER_MODEL  = model_routing.model_for("reviewer", WORKSHOP)
DRAFTER_MODEL   = model_routing.model_for("drafter", WORKSHOP)
ARCHIVIST_MODEL = model_routing.model_for("archivist", WORKSHOP)

# Semantic skill selection: embeddings via the workshop's own backend, keyword
# fallback inside select_skill_semantic on any failure — so a missing embedding
# model degrades to Step 10 behavior, never to an error.
EMBED_MODEL = os.environ.get(
    "COOPER_EMBED_MODEL",
    "nomic-embed-text" if BACKEND == "ollama" else "text-embedding-3-small",
)

# Branded id reported to OpenAI-compatible clients (Open WebUI's model dropdown, etc.)
# — decoupled from COOPER_MODEL so Open Workshop's real backend model (the "openai" LiteLLM
# alias, itself resolving to gpt-4o-mini) never has to leak into the UI.
DISPLAY_MODEL = f"COOPER-{WORKSHOP.capitalize()}"


def _load_system_prompt() -> str:
    if not _MODELFILE.exists():
        return (
            "You are COOPER (Command Operations Orchestrator for Planning, Execution, "
            "and Reporting). TARS-inspired. Direct, concise, dry humor at 55%, "
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

_EMBED_FN = embeddings.make_fetcher(BACKEND, BACKEND_URL, BACKEND_KEY, EMBED_MODEL)


async def _select_skill(message: str):
    """One semantic-selection call shared by the blocking and streaming paths."""
    return await skills.select_skill_semantic(
        WORKSHOP, message, conn=_ARCHIVIST_CONN, model=EMBED_MODEL,
        embed_fn=_EMBED_FN, lock=archivist._DB_LOCK,
    )

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


_ARGS_PREVIEW_CHAR_THRESHOLD = 60


def _render_args_preview(args: dict) -> str:
    """Approval-halt preview line: short values verbatim, long ones as a
    char count (spec §4 main.py — 'note: ...md, content: 214 chars')."""
    if not args:
        return ""
    parts = []
    for key, value in args.items():
        rendered = repr(value)
        if len(rendered) > _ARGS_PREVIEW_CHAR_THRESHOLD:
            parts.append(f"{key}: {len(str(value))} chars")
        else:
            parts.append(f"{key}: {rendered}")
    return "\n\nArgs — " + ", ".join(parts)


async def _handle_tool_call(
    tool_id: str, args: dict, raw_message: str, session_id: str = "local"
) -> str:
    """
    The model's tool_call IS the dispatch (spec §2 step 4-5). Resolve
    tool_id to a registry entry, validate args, gate via approval, execute
    if the gate passes. L0/L1 auto-run immediately. L2+ halts for approval.
    Every failure here is fail-closed and spends no approval (spec §5).
    """
    try:
        workshop.check_backend(BACKEND, WORKSHOP)
    except workshop.WorkshopViolation as exc:
        return f"Workshop violation: {exc}"

    tool = registry.get_tool(WORKSHOP, tool_id)
    if tool is None:
        return f"COOPER proposed a call to unregistered tool '{tool_id}'. Nothing ran."

    try:
        workshop.check_tool(tool, WORKSHOP)
    except workshop.WorkshopViolation as exc:
        return f"Workshop violation: {exc}"

    violations = registry.validate_args(tool, args)
    if violations:
        return (
            f"COOPER proposed an invalid call to {tool.get('name', tool_id)}: "
            f"{'; '.join(violations)}. Nothing ran."
        )

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
                text = await asyncio.to_thread(
                    skills.preview_import, args.get("skill_name", ""), args.get("tap_url", "")
                )
                preview = f"\n\nSKILL.md under review:\n---\n{text}\n---"
            except skills.SkillError as exc:
                return f"Skill import rejected before approval: {exc}"
            except Exception as exc:
                return f"Skill import rejected before approval (unexpected error): {exc}"
        elif tool.get("executor_type") == "skill_promote":
            try:
                text = await asyncio.to_thread(skills.preview_promote, args.get("skill_name", ""))
                preview = f"\n\nDraft SKILL.md under review:\n---\n{text}\n---"
            except skills.SkillError as exc:
                return f"Skill promotion rejected before approval: {exc}"
            except Exception as exc:
                return f"Skill promotion rejected before approval (unexpected error): {exc}"
        try:
            approval.request(WORKSHOP, tool, raw_message, session_id, args=args)
        except approval.ApprovalConflictError as exc:
            existing_name = exc.existing.tool.get("name", exc.existing.tool.get("id"))
            return (
                f"Halt — {existing_name} is already waiting on your approval. "
                f"Reply 'approve' or 'deny' before starting {tool.get('name', tool.get('id'))}."
            )
        return (
            f"Halt — {tool.get('name', tool.get('id'))} "
            f"[{tool.get('drawer', 'Uncategorized')}, permission level {tool.get('permission_level', '?')}] "
            f"requires approval before it can proceed{skill_note}. Reply 'approve' or 'deny'."
            f"{_render_args_preview(args)}"
            f"{preview}"
        )

    # L0/L1: execute immediately
    if skill_note:
        print(f"  [archivist] {tool.get('name')}{skill_note}")
    return await _execute(tool, raw_message, session_id, args)


# Post-dispatch notices: background work (memory writes, skill drafts) reports
# back on the session's NEXT turn instead of blocking this one.
_SESSION_NOTICES: dict = {}
_BG_TASKS: set = set()  # strong refs — bare create_task results can be GC'd


def _queue_notice(session_id: str, text: str) -> None:
    _SESSION_NOTICES.setdefault(session_id, []).append(text)


def _drain_notices(session_id: str) -> str:
    notes = _SESSION_NOTICES.pop(session_id, [])
    return "".join(f"\n\n{n}" for n in notes)


async def _post_dispatch(tool: dict, message: str, raw_output: str, verdict, session_id: str) -> None:
    """Memory write + skill draft — the two chained LLM calls that used to run
    inside the request (and once blew the 120s timeout under CPU load)."""
    try:
        await archivist.remember(
            _ARCHIVIST_CONN, tool, message, raw_output, verdict, WORKSHOP,
            base_url=BACKEND_URL, api_key=BACKEND_KEY,
            model=ARCHIVIST_MODEL, backend=BACKEND,
        )
    except Exception as exc:
        print(f"  [!!] archivist.remember failed (non-fatal): {exc}")

    if verdict.verdict == "pass":
        try:
            draft_dir = await proposer.draft_skill(
                tool, message, raw_output,
                base_url=BACKEND_URL, api_key=BACKEND_KEY,
                model=DRAFTER_MODEL, backend=BACKEND,
            )
            offer = proposer.offer_line(draft_dir).strip()
            if offer:
                _queue_notice(session_id, offer)
        except Exception as exc:
            print(f"  [!!] proposer failed (non-fatal): {exc}")


async def _execute(
    tool: dict, message: str, session_id: str = "local", args: Optional[dict] = None
) -> str:
    """
    Run an approved/auto-run tool through the Workbench (Worker), then have
    the Reviewer check the result (Step 7) before it reaches the user.
    Memory + skill drafting happen in the background (_post_dispatch).
    """
    args = args or {}
    try:
        raw_output = await executor.run(tool, message, WORKSHOP, args)
    except executor.ExecutionError as exc:
        return f"Workbench error: {exc}"

    verdict = await review.review(
        tool, message, raw_output,
        base_url=BACKEND_URL,
        api_key=BACKEND_KEY,
        model=REVIEWER_MODEL,
        backend=BACKEND,
    )

    task = asyncio.create_task(
        _post_dispatch(tool, message, raw_output, verdict, session_id))
    _BG_TASKS.add(task)
    task.add_done_callback(_BG_TASKS.discard)

    return review.govern(raw_output, verdict)


async def _resolve_approval(message: str, session_id: str = "local") -> str:
    """
    Consume the pending ticket and execute on approve, or cancel on deny.
    Called only when approval.has_pending() and approval.is_response() are both true.
    """
    if approval.is_denied(message):
        ticket = approval.consume(WORKSHOP, session_id)
        if ticket is None:
            return "No pending action to cancel."
        if ticket.tool.get("executor_type") == "skill_import":
            try:
                skills.discard_staged(ticket.args.get("skill_name", ""))
            except Exception as exc:
                print(f"  [!!] discard_staged failed (non-fatal): {exc}")
        name = ticket.tool.get("name", ticket.tool.get("id"))
        return f"Cancelled. {name} will not run."

    ticket = approval.consume(WORKSHOP, session_id)
    if ticket is None:
        return "No pending action to approve. Nothing queued."

    return await _execute(ticket.tool, ticket.message, session_id, ticket.args)


async def _chat_core(message: str, history: List[dict], session_id: str = "local") -> tuple:
    """One routing path for every front door (HTTP endpoints + gateway):
    registry/skill catalog queries, approval responses, then route_turn.
    Queued background notices (skill drafts, …) ride along on the reply."""
    reply, td = await _chat_core_inner(message, history, session_id)
    return reply + _drain_notices(session_id), td


async def _chat_core_inner(message: str, history: List[dict], session_id: str = "local") -> tuple:
    if registry.is_registry_query(message):
        return registry.format_tool_list(WORKSHOP), TurnDecision(
            decision="answer", reason="registry query answered directly by Quartermaster")
    if skills.is_skill_query(message):
        return skills.format_skill_list(WORKSHOP), TurnDecision(
            decision="answer", reason="skill catalog answered directly")
    if approval.has_pending(WORKSHOP, session_id) and approval.is_response(message):
        return await _resolve_approval(message, session_id), TurnDecision(
            decision="answer", reason="approval gate resolved")
    try:
        tools = registry.render_workshop_tools(WORKSHOP)
    except registry.RegistryError as exc:
        print(f"  [!!] render_workshop_tools failed (non-fatal): {exc}")
        tools = []
    return await route_turn(
        message, history,
        generate_answer=_generate,
        tools=tools,
        tool_call_handler=lambda tid, a, raw: _handle_tool_call(tid, a, raw, session_id),
    )


# ── Startup ────────────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    _check_auth_config(_API_KEYS, _ALLOW_ANON)
    print(f"\n  workshop : {WORKSHOP}")
    print(f"  backend  : {BACKEND}")
    print(f"  model    : {COOPER_MODEL}")
    print(f"  reviewer : {REVIEWER_MODEL}")
    print(f"  drafter  : {DRAFTER_MODEL}")
    print(f"  archivist: {ARCHIVIST_MODEL}")

    if BACKEND == "ollama":
        async with httpx.AsyncClient(timeout=5.0) as client:
            try:
                resp = await client.get(f"{OLLAMA_HOST}/api/tags")
                models = [m["name"] for m in resp.json().get("models", [])]
                known = {m.lower() for m in models} | {m.split(":")[0].lower() for m in models}
                for name in {COOPER_MODEL, REVIEWER_MODEL, DRAFTER_MODEL, ARCHIVIST_MODEL}:
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
        "status":   "ok",
        "workshop": WORKSHOP,
        "backend":  BACKEND,
        "model":    COOPER_MODEL,
        "roles": {
            "brain":     COOPER_MODEL,
            "reviewer":  REVIEWER_MODEL,
            "drafter":   DRAFTER_MODEL,
            "archivist": ARCHIVIST_MODEL,
        },
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
            skill_ctx = ""
            try:
                matched = await _select_skill(message)
                if matched is not None:
                    skill_ctx = skills.format_skill_context(matched)
                    await asyncio.to_thread(skills.record_activation, _ARCHIVIST_CONN, matched.id)
            except Exception as exc:
                print(f"  [!!] skill context injection failed (non-fatal): {exc}")
                skill_ctx = ""
            if skill_ctx:
                system_prompt = f"{system_prompt}\n\n{skill_ctx}"
            try:
                stream_tools = registry.render_workshop_tools(WORKSHOP)
            except registry.RegistryError as exc:
                print(f"  [!!] render_workshop_tools failed (non-fatal): {exc}")
                stream_tools = []
            td, content_iter = await route_turn_stream(
                message,
                history,
                system_prompt=system_prompt,
                base_url=BACKEND_URL,
                api_key=BACKEND_KEY,
                model=COOPER_MODEL,
                backend=BACKEND,
                tools=stream_tools,
                tool_call_handler=lambda tid, a, raw: _handle_tool_call(tid, a, raw, session_id),
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

        notices = _drain_notices(session_id)
        if notices:
            data = {
                "id":      request_id,
                "object":  "chat.completion.chunk",
                "created": created,
                "model":   DISPLAY_MODEL,
                "choices": [{"index": 0, "delta": {"content": notices}, "finish_reason": None}],
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


async def _generate(message: str, history: List[dict], tools: Optional[List[dict]] = None):
    try:
        await asyncio.to_thread(archivist.index_brain, _ARCHIVIST_CONN)
        recall_context = archivist.format_recall_context(
            await asyncio.to_thread(archivist.recall, _ARCHIVIST_CONN, message)
        )
    except Exception as exc:
        print(f"  [!!] archivist.recall failed (non-fatal): {exc}")
        recall_context = ""
    skill_ctx = ""
    try:
        matched = await _select_skill(message)
        if matched is not None:
            skill_ctx = skills.format_skill_context(matched)
            await asyncio.to_thread(skills.record_activation, _ARCHIVIST_CONN, matched.id)
    except Exception as exc:
        print(f"  [!!] skill context injection failed (non-fatal): {exc}")
        skill_ctx = ""
    msgs = _build_messages(history, message)
    # Same injection order as the streaming path: SYSTEM, recall, skill.
    if skill_ctx:
        msgs.insert(1, {"role": "system", "content": skill_ctx})
    if recall_context:
        msgs.insert(1, {"role": "system", "content": recall_context})
    if BACKEND == "openai":
        from decision import _openai_complete
        return await _openai_complete(BACKEND_URL, BACKEND_KEY, COOPER_MODEL, msgs, tools=tools)
    from decision import _ollama_complete
    return await _ollama_complete(BACKEND_URL, COOPER_MODEL, msgs, tools=tools)


def _build_messages(history: List[dict], user_message: str) -> List[dict]:
    msgs: List[dict] = [{"role": "system", "content": SYSTEM_PROMPT}]
    for turn in history:
        if turn.get("role") != "system":
            msgs.append({"role": turn["role"], "content": turn.get("content", "")})
    if user_message.strip():
        msgs.append({"role": "user", "content": user_message})
    return msgs
