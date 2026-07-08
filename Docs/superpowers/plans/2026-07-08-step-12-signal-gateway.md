# Step 12 — Signal Messaging Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Message COOPER from Signal: a `signal-cli-rest-api` container joins the Open compose stack; `cooper-core/gateway.py` long-polls it, filters by sender allowlist, routes each message through the same chat pipeline as Open WebUI, and replies.

**Architecture:** In-process asyncio background task started from `main.py`'s lifespan when `GATEWAY_ENABLED=1` and `WORKSHOP=open` (Open workshop ONLY — spec ruling). A small `main.py` refactor extracts `_chat_core()` so the gateway, `/chat`, and `/v1/chat/completions` share one routing path. Spec: `Docs/superpowers/specs/2026-07-08-cooper-hermes-merge-design.md` §5.

**Tech Stack:** Python 3.11+, httpx (already a dep), `bbernhard/signal-cli-rest-api` Docker image, pytest. No new pip installs.

**INDEPENDENT of Steps 10/11/13** — can be built in a parallel worktree. Merge note: Steps 10/11 also touch `main.py`'s `chat()`/`oai_chat()`/`_stream_sse` branch chains; whoever merges second reconciles those few lines (the `_chat_core` refactor here actually makes their branches simpler).

**Human prerequisite (do in parallel, before Task 4):** a Signal account for COOPER — either register a dedicated number or link as a secondary device to an existing account (Task 4 Step 5 has the commands).

## Global Constraints

- Branch from `step-9-dockerize` (e.g. `step-12-gateway`).
- Gateway starts ONLY when `GATEWAY_ENABLED=1` AND `WORKSHOP == "open"` — a private-workshop process must refuse with a printed `[!!]` warning. Fail closed.
- Empty/unset `SIGNAL_ALLOWED_SENDERS` means NOBODY is allowed (fail closed), not everybody.
- The gateway never crashes the server: every poll-loop error is caught, logged, and retried after a backoff sleep.
- The signal-cli container port binds to loopback only (`127.0.0.1:8080:8080`).
- v1 sender pairing = the operator edits `SIGNAL_ALLOWED_SENDERS` in `.env` and restarts (operator-level approval). A chat-dispatched `pair_sender` tool is deferred; recorded as a spec §5 v1 ruling.
- Tests: `cd cooper-core && python3 -m pytest test_gateway.py -v`.

---

### Task 1: main.py refactor — extract `_chat_core`

**Files:**
- Modify: `cooper-core/main.py`
- Test: `cooper-core/test_gateway.py` (created here with the refactor tests)

**Interfaces:**
- Consumes: existing `chat()` / `oai_chat()` branch logic (registry query → approval response → `route_turn`).
- Produces: `async _chat_core(message: str, history: List[dict]) -> tuple[str, TurnDecision]` — the single routing entry the HTTP endpoints and the gateway both call.

- [ ] **Step 1: Write the failing tests**

```python
# cooper-core/test_gateway.py
"""Signal gateway tests (Step 12): _chat_core refactor, allowlist, poll loop."""
import asyncio
import os

os.environ.setdefault("WORKSHOP", "open")
os.environ.setdefault("COOPER_ALLOW_ANON", "1")
os.environ.pop("COOPER_API_KEY", None)

import main  # noqa: E402


def run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


def test_chat_core_short_circuits_registry_query(monkeypatch):
    monkeypatch.setattr(main.registry, "format_tool_list", lambda w: f"TOOLS[{w}]")
    reply, td = run(main._chat_core("what tools do you have?", []))
    assert reply == "TOOLS[open]"
    assert td.decision == "answer"
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd cooper-core && python3 -m pytest test_gateway.py -v`
Expected: FAIL — `main` has no `_chat_core`.

- [ ] **Step 3: Implement**

Add to `main.py` (above the `POST /chat` section), consolidating the branch chain that currently lives in both `chat()` and `oai_chat()`:

```python
async def _chat_core(message: str, history: List[dict]) -> tuple:
    """One routing path for every front door (HTTP endpoints + gateway):
    registry/skill catalog queries, approval responses, then route_turn."""
    if registry.is_registry_query(message):
        return registry.format_tool_list(WORKSHOP), TurnDecision(
            decision="answer", reason="registry query answered directly by Quartermaster")
    if approval.has_pending(WORKSHOP) and approval.is_response(message):
        return await _resolve_approval(message), TurnDecision(
            decision="answer", reason="approval gate resolved")
    return await route_turn(
        message, history,
        generate_answer=_generate,
        base_url=BACKEND_URL, api_key=BACKEND_KEY,
        model=COOPER_MODEL, classifier_model=CLASSIFIER_MODEL,
        backend=BACKEND, dispatch_handler=_handle_dispatch,
    )
```

Then reduce `chat()` to:

```python
@app.post("/chat", response_model=ChatResponse, dependencies=[Depends(_require_auth)])
async def chat(req: ChatRequest):
    reply, td = await _chat_core(req.message, req.history)
    return {"reply": reply, "decision": td.decision, "reason": td.reason}
```

and the non-stream branch of `oai_chat()` to:

```python
    reply, td = await _chat_core(message, history)
```

(Delete the now-duplicated registry/approval branches from both. `_stream_sse` keeps its own streaming path unchanged. If Step 10 merged first, fold its `skills.is_skill_query` branch INTO `_chat_core` as the second branch and delete it from the endpoints.)

- [ ] **Step 4: Run the full suite**

Run: `cd cooper-core && python3 -m pytest -v`
Expected: all pass — `test_main_auth.py` and `test_main_open_routing.py` prove the endpoints still behave.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/main.py cooper-core/test_gateway.py
git commit -m "refactor(step-12): extract _chat_core as the single routing entry"
```

---

### Task 2: gateway.py — config, envelope parsing, allowlist

**Files:**
- Create: `cooper-core/gateway.py`
- Test: `cooper-core/test_gateway.py` (append)

**Interfaces:**
- Consumes: env vars `SIGNAL_API_URL`, `SIGNAL_NUMBER`, `SIGNAL_ALLOWED_SENDERS`.
- Produces: `GatewayConfig` dataclass (`api_url, number, allowed_senders: frozenset, poll_timeout: int = 20`); `load_config(env: Optional[dict] = None) -> Optional[GatewayConfig]`; `parse_envelopes(payload) -> list[tuple[str, str]]` ((sender, text) pairs); `is_allowed(cfg, sender: str) -> bool`.

- [ ] **Step 1: Write the failing tests (append to test_gateway.py)**

```python
import gateway  # noqa: E402

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
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd cooper-core && python3 -m pytest test_gateway.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'gateway'`.

- [ ] **Step 3: Write the implementation**

```python
# cooper-core/gateway.py
"""
COOPER Signal gateway (Step 12).

Long-polls a local signal-cli-rest-api container for incoming Signal
messages, filters by sender allowlist (fail closed), routes each message
through main._chat_core, and replies via /v2/send.

Open workshop ONLY (spec §5): messages traverse a remotely reachable
channel, so the gateway must never front the Private workshop.
"""
import asyncio
import os
from dataclasses import dataclass, field
from typing import Awaitable, Callable, List, Optional, Tuple

import httpx

_ERROR_BACKOFF = 10  # seconds after a failed poll


@dataclass
class GatewayConfig:
    api_url: str
    number: str
    allowed_senders: frozenset = field(default_factory=frozenset)
    poll_timeout: int = 20


def load_config(env: Optional[dict] = None) -> Optional[GatewayConfig]:
    """None unless api_url, number, AND a non-empty allowlist are configured."""
    e = os.environ if env is None else env
    api_url = (e.get("SIGNAL_API_URL") or "").strip().rstrip("/")
    number  = (e.get("SIGNAL_NUMBER") or "").strip()
    senders = frozenset(
        s.strip() for s in (e.get("SIGNAL_ALLOWED_SENDERS") or "").split(",") if s.strip()
    )
    if not api_url or not number or not senders:
        return None
    return GatewayConfig(api_url=api_url, number=number, allowed_senders=senders)


def parse_envelopes(payload) -> List[Tuple[str, str]]:
    """(sender, text) for every dataMessage in a /v1/receive payload."""
    out: List[Tuple[str, str]] = []
    if not isinstance(payload, list):
        return out
    for item in payload:
        env = item.get("envelope", {}) if isinstance(item, dict) else {}
        text = (env.get("dataMessage") or {}).get("message")
        sender = env.get("source")
        if sender and text:
            out.append((str(sender), str(text)))
    return out


def is_allowed(cfg: GatewayConfig, sender: str) -> bool:
    """Fail closed: empty allowlist admits nobody."""
    return sender in cfg.allowed_senders
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && python3 -m pytest test_gateway.py -v`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/gateway.py cooper-core/test_gateway.py
git commit -m "feat(step-12): gateway config, envelope parsing, fail-closed allowlist"
```

---

### Task 3: Poll/send loop + lifespan startup

**Files:**
- Modify: `cooper-core/gateway.py` (append)
- Modify: `cooper-core/main.py` (lifespan)
- Test: `cooper-core/test_gateway.py` (append)

**Interfaces:**
- Consumes: Task 1's `main._chat_core`, Task 2's config/parse/allowlist.
- Produces: `async poll_once(cfg, client, handler) -> int` (messages handled); `async send(cfg, client, recipient: str, text: str) -> None`; `async run_loop(cfg, handler, *, client: Optional[httpx.AsyncClient] = None, max_iterations: Optional[int] = None)`; gateway task started/cancelled in `main.lifespan`.

- [ ] **Step 1: Write the failing tests (append to test_gateway.py)**

```python
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
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd cooper-core && python3 -m pytest test_gateway.py -v`
Expected: new tests FAIL with `AttributeError` on the missing functions.

- [ ] **Step 3: Implement (append to gateway.py)**

```python
async def send(cfg: GatewayConfig, client: httpx.AsyncClient, recipient: str, text: str) -> None:
    resp = await client.post(
        f"{cfg.api_url}/v2/send",
        json={"message": text, "number": cfg.number, "recipients": [recipient]},
        timeout=30.0,
    )
    resp.raise_for_status()


async def poll_once(
    cfg: GatewayConfig,
    client: httpx.AsyncClient,
    handler: Callable[[str], Awaitable[str]],
) -> int:
    """One receive→filter→handle→reply pass. Returns messages handled."""
    resp = await client.get(
        f"{cfg.api_url}/v1/receive/{cfg.number}",
        params={"timeout": cfg.poll_timeout},
        timeout=float(cfg.poll_timeout) + 15.0,
    )
    resp.raise_for_status()
    handled = 0
    for sender, text in parse_envelopes(resp.json()):
        if not is_allowed(cfg, sender):
            print(f"  [!!] gateway: ignored message from non-allowlisted {sender}")
            continue
        handled += 1
        try:
            reply = await handler(text)
        except Exception as exc:
            print(f"  [!!] gateway: handler failed: {exc}")
            reply = f"COOPER gateway error — the message was received but processing failed: {exc}"
        try:
            await send(cfg, client, sender, reply)
        except Exception as exc:
            print(f"  [!!] gateway: send to {sender} failed: {exc}")
    return handled


async def run_loop(
    cfg: GatewayConfig,
    handler: Callable[[str], Awaitable[str]],
    *,
    client: Optional[httpx.AsyncClient] = None,
    max_iterations: Optional[int] = None,
) -> None:
    """Poll forever (or max_iterations, for tests). Never raises out."""
    own_client = client is None
    client = client or httpx.AsyncClient()
    print(f"  [ok] gateway: polling {cfg.api_url} as {cfg.number} "
          f"({len(cfg.allowed_senders)} allowed sender(s))")
    iterations = 0
    try:
        while max_iterations is None or iterations < max_iterations:
            iterations += 1
            try:
                await poll_once(cfg, client, handler)
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                print(f"  [!!] gateway: poll failed ({exc}) — retrying in {_ERROR_BACKOFF}s")
                await asyncio.sleep(_ERROR_BACKOFF)
    finally:
        if own_client:
            await client.aclose()
```

Then in `main.py`'s `lifespan()`, before `yield`:

```python
    gateway_task = None
    if os.environ.get("GATEWAY_ENABLED", "").strip() == "1":
        if WORKSHOP != "open":
            print("  [!!] GATEWAY_ENABLED=1 but workshop is not 'open' — gateway refused (spec §5)")
        else:
            gw_cfg = gateway.load_config()
            if gw_cfg is None:
                print("  [!!] gateway enabled but SIGNAL_API_URL/SIGNAL_NUMBER/SIGNAL_ALLOWED_SENDERS incomplete — not started (fail closed)")
            else:
                async def _gateway_handler(text: str) -> str:
                    reply, _td = await _chat_core(text, [])
                    return reply
                gateway_task = asyncio.create_task(gateway.run_loop(gw_cfg, _gateway_handler))
```

and after `yield`:

```python
    if gateway_task is not None:
        gateway_task.cancel()
        try:
            await gateway_task
        except asyncio.CancelledError:
            pass
```

(Add `import gateway` beside the other module imports.)

- [ ] **Step 4: Run the full suite**

Run: `cd cooper-core && python3 -m pytest -v`
Expected: all pass; server tests unaffected (gateway is opt-in via env).

- [ ] **Step 5: Commit**

```bash
git add cooper-core/gateway.py cooper-core/main.py cooper-core/test_gateway.py
git commit -m "feat(step-12): signal poll/send loop wired into server lifespan"
```

---

### Task 4: Compose service, env plumbing, live verification

**Files:**
- Modify: `PDA-Runtime/docker-compose.yml` (Open Stack — add `signal-cli` service; add gateway env keys to the cooper-core service; match the file's existing style/indentation exactly)
- Modify: `PDA-Runtime/.env.example` (document the new keys)

**Interfaces:**
- Consumes: Task 3's env contract (`GATEWAY_ENABLED`, `SIGNAL_API_URL`, `SIGNAL_NUMBER`, `SIGNAL_ALLOWED_SENDERS`).
- Produces: running end-to-end Signal ↔ COOPER loop.

- [ ] **Step 1: Add the signal-cli service to `PDA-Runtime/docker-compose.yml`**

```yaml
  signal-cli:
    image: bbernhard/signal-cli-rest-api:0.94
    restart: unless-stopped
    environment:
      - MODE=native
    volumes:
      - ./data/signal:/home/.local/share/signal-cli
    ports:
      - "127.0.0.1:8080:8080"   # loopback only — registration/linking via localhost
```

(Pin the image tag to the latest published version at implementation time; check https://hub.docker.com/r/bbernhard/signal-cli-rest-api/tags — do not use `latest`.)

- [ ] **Step 2: Add gateway env to the cooper-core service in the same file**

```yaml
      - GATEWAY_ENABLED=${GATEWAY_ENABLED:-0}
      - SIGNAL_API_URL=http://signal-cli:8080
      - SIGNAL_NUMBER=${SIGNAL_NUMBER:-}
      - SIGNAL_ALLOWED_SENDERS=${SIGNAL_ALLOWED_SENDERS:-}
```

And append to `PDA-Runtime/.env.example`:

```bash
# Step 12 — Signal gateway (Open Workshop only). Leave GATEWAY_ENABLED=0 to disable.
GATEWAY_ENABLED=0
SIGNAL_NUMBER=            # e.g. +15550001111 — the account COOPER sends as
SIGNAL_ALLOWED_SENDERS=   # comma-separated sender numbers; EMPTY = nobody (fail closed)
```

- [ ] **Step 3: Validate compose syntax**

Run: `docker compose -f PDA-Runtime/docker-compose.yml config --quiet && echo OK`
Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add PDA-Runtime/docker-compose.yml PDA-Runtime/.env.example
git commit -m "feat(step-12): signal-cli-rest-api service + gateway env plumbing"
```

- [ ] **Step 5: HUMAN STEP — register/link the Signal account (once)**

```bash
docker compose -f PDA-Runtime/docker-compose.yml up -d signal-cli
# Option A (recommended): link as secondary device to an existing account —
# open this URL, scan the QR with Signal on the phone (Settings → Linked Devices):
#   http://localhost:8080/v1/qrcodelink?device_name=cooper
# Option B: register a dedicated number (needs SMS/voice verification):
#   curl -X POST http://localhost:8080/v1/register/+1<number>
#   curl -X POST http://localhost:8080/v1/register/+1<number>/verify/<code>
```

Then set `GATEWAY_ENABLED=1`, `SIGNAL_NUMBER`, and `SIGNAL_ALLOWED_SENDERS` (your own Signal number) in `PDA-Runtime/.env`.

- [ ] **Step 6: Live verification (Definition of Done)**

```bash
docker compose -f PDA-Runtime/docker-compose.yml up -d
docker compose -f PDA-Runtime/docker-compose.yml logs cooper-core | grep gateway
# expect: "[ok] gateway: polling http://signal-cli:8080 as +1... (1 allowed sender(s))"
```

From your phone, send COOPER's Signal account:
1. `what tools do you have?` → expect the registry listing as a Signal reply.
2. A dispatch that needs approval → expect the Halt message; reply `approve` → expect execution result. (Single-operator only until Step 13's session binding lands — do NOT allowlist anyone else yet.)
3. From a non-allowlisted number (a friend's phone), send anything → expect NO reply and a `[!!] gateway: ignored message` line in the logs.

Final confirmation: Open WebUI at `http://localhost:3000` still chats normally (gateway didn't disturb the HTTP path).
