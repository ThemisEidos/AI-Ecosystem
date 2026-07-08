# Step 13 — Session-Bound Approvals + Friends & Family Packaging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Approval tickets bind to the session (credential) that opened them — client A can never approve client B's action — and a one-command bootstrap script installs the stack for friends and family. Closes the audit's deferred "approval-ticket session binding before multi-client exposure" item.

**Architecture:** `ApprovalTicket` gains a `session_id`; the pending-ticket store keys on `(workshop, session_id)`. Session identity derives from the presented bearer token (multi-key support via `COOPER_API_KEYS`), so each client with their own key is their own approval domain. `install-cooper.sh` wraps the existing Step 9 compose stack. Spec: `Docs/superpowers/specs/2026-07-08-cooper-hermes-merge-design.md` §6.

**Tech Stack:** Python 3.11+, hashlib (stdlib), bash, Docker Compose. No new pip installs.

**INDEPENDENT of Steps 10/11/12** — can be built in a parallel worktree. Task 4 is a consolidation task that runs only after Step 12 merges.

## Global Constraints

- Branch from `step-9-dockerize` (e.g. `step-13-sessions`).
- **No remembered permissions** (Phase 1 rule): tickets stay single-use, 10-minute TTL — this plan changes WHO can consume a ticket, never how long it lives.
- Anonymous access (`COOPER_ALLOW_ANON=1`) maps every client to session `"anon"` — acceptable for single-operator dev, and exactly why the bootstrap script generates a real key.
- The bootstrap script must be idempotent: safe to re-run on a half-installed machine.
- Never write into `.env` if it already exists — print what's missing instead.
- Tests: `cd cooper-core && python3 -m pytest test_approval.py test_main_auth.py -v`.

---

### Task 1: approval.py — session-keyed tickets

**Files:**
- Modify: `cooper-core/approval.py`
- Test: `cooper-core/test_approval.py` (append)

**Interfaces:**
- Consumes: existing `ApprovalTicket`, `_pending`, TTL logic.
- Produces: `ApprovalTicket.session_id: str`; `request(workshop, tool, message, session_id: str = "local")`; `has_pending(workshop, session_id="local")`, `peek(workshop, session_id="local")`, `consume(workshop, session_id="local")` — all scoped so a ticket is visible ONLY to the session that opened it. Existing single-session callers/tests keep working via the `"local"` default.

- [ ] **Step 1: Write the failing tests (append to test_approval.py, matching its existing style)**

```python
def _tool():
    return {"id": "t", "name": "T", "permission_level": 2}


def test_ticket_bound_to_opening_session():
    approval._pending.clear()
    approval.request("open", _tool(), "do it", session_id="client-a")
    # a different session sees nothing and cannot consume
    assert not approval.has_pending("open", "client-b")
    assert approval.peek("open", "client-b") is None
    assert approval.consume("open", "client-b") is None
    # the opening session still holds a live ticket after the foreign attempt
    assert approval.has_pending("open", "client-a")
    ticket = approval.consume("open", "client-a")
    assert ticket is not None and ticket.session_id == "client-a"
    assert not approval.has_pending("open", "client-a")


def test_sessions_have_independent_tickets():
    approval._pending.clear()
    approval.request("open", _tool(), "task a", session_id="client-a")
    approval.request("open", _tool(), "task b", session_id="client-b")
    assert approval.consume("open", "client-a").message == "task a"
    assert approval.consume("open", "client-b").message == "task b"


def test_default_session_is_local():
    approval._pending.clear()
    approval.request("open", _tool(), "solo")
    assert approval.has_pending("open")
    assert approval.consume("open").session_id == "local"
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd cooper-core && python3 -m pytest test_approval.py -v`
Expected: new tests FAIL (`request()` rejects the `session_id` kwarg).

- [ ] **Step 3: Implement — replace the ticket/store section of approval.py**

```python
@dataclass
class ApprovalTicket:
    id: str
    workshop: str
    tool: dict
    message: str
    created_at: float
    session_id: str = "local"


_pending: Dict[tuple, ApprovalTicket] = {}  # (workshop, session_id) -> ticket


def request(workshop: str, tool: dict, message: str, session_id: str = "local") -> ApprovalTicket:
    """Open a pending ticket for this (workshop, session), replacing any prior one.
    Session binding (Step 13): only the session that opened a ticket can see or
    consume it — client A can never approve client B's action."""
    ticket = ApprovalTicket(
        id=uuid.uuid4().hex[:8],
        workshop=workshop,
        tool=tool,
        message=message,
        created_at=time.time(),
        session_id=session_id,
    )
    _pending[(workshop, session_id)] = ticket
    return ticket


def _get_live(workshop: str, session_id: str = "local") -> Optional[ApprovalTicket]:
    key = (workshop, session_id)
    ticket = _pending.get(key)
    if ticket is None:
        return None
    if time.time() - ticket.created_at > _TICKET_TTL_SECONDS:
        _pending.pop(key, None)
        return None
    return ticket


def has_pending(workshop: str, session_id: str = "local") -> bool:
    return _get_live(workshop, session_id) is not None


def peek(workshop: str, session_id: str = "local") -> Optional[ApprovalTicket]:
    """Read the session's pending ticket without consuming it (GET /pending)."""
    return _get_live(workshop, session_id)


def consume(workshop: str, session_id: str = "local") -> Optional[ApprovalTicket]:
    """Consume and return this session's live ticket, or None."""
    ticket = _get_live(workshop, session_id)
    _pending.pop((workshop, session_id), None)
    return ticket
```

(Keep `needs_approval`, the regexes, `is_response`, `is_approved`, `is_denied` untouched.)

- [ ] **Step 4: Run the suite**

Run: `cd cooper-core && python3 -m pytest test_approval.py -v`
Expected: all pass, including the pre-existing tests (defaults preserve old behavior).

- [ ] **Step 5: Commit**

```bash
git add cooper-core/approval.py cooper-core/test_approval.py
git commit -m "feat(step-13): approval tickets bound to opening session"
```

---

### Task 2: main.py — multi-key auth, session derivation, threading

**Files:**
- Modify: `cooper-core/main.py`
- Test: `cooper-core/test_main_auth.py` (append — follow that file's existing isolation pattern for env-dependent main imports)

**Interfaces:**
- Consumes: Task 1's session-keyed approval API.
- Produces: `COOPER_API_KEYS` env (comma-separated; falls back to legacy `COOPER_API_KEY`); `_derive_session_id(token: Optional[str]) -> str` (sha256 hex[:12], `"anon"` for None/empty); `_session_id` FastAPI dependency; `session_id` threaded through `chat`/`oai_chat`/`_stream_sse`/`_handle_dispatch`/`_resolve_approval`/`GET /pending`.

- [ ] **Step 1: Write the failing tests (append to test_main_auth.py, using its existing import/isolation pattern)**

```python
def test_derive_session_id_is_stable_and_anonymous_safe():
    import main
    a = main._derive_session_id("key-alpha")
    assert a == main._derive_session_id("key-alpha")      # stable
    assert a != main._derive_session_id("key-beta")       # distinct per key
    assert len(a) == 12
    assert main._derive_session_id(None) == "anon"
    assert main._derive_session_id("") == "anon"


def test_parse_api_keys_multi_and_legacy():
    import main
    assert main._parse_api_keys("k1, k2 ,k3", "") == {"k1", "k2", "k3"}
    assert main._parse_api_keys("", "legacy") == {"legacy"}
    assert main._parse_api_keys("k1", "legacy") == {"k1", "legacy"}
    assert main._parse_api_keys("", "") == set()
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd cooper-core && python3 -m pytest test_main_auth.py -v`
Expected: new tests FAIL — helpers missing.

- [ ] **Step 3: Implement**

3a. Replace the Auth section of `main.py` (add `import hashlib` to the stdlib imports):

```python
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
```

Update the lifespan call `_check_auth_config(_API_KEY, _ALLOW_ANON)` → `_check_auth_config(_API_KEYS, _ALLOW_ANON)`.

3b. Thread the session through the routing path. `_handle_dispatch` and `_resolve_approval` gain a parameter:

```python
async def _handle_dispatch(message: str, session_id: str = "local") -> str:
```
— its `approval.request(WORKSHOP, tool, message)` becomes `approval.request(WORKSHOP, tool, message, session_id)`.

```python
async def _resolve_approval(message: str, session_id: str = "local") -> str:
```
— both `approval.consume(WORKSHOP)` calls become `approval.consume(WORKSHOP, session_id)`.

3c. `_chat_core` (from Step 12; if Step 12 hasn't merged yet, apply the same edits to the duplicated branches in `chat()`/`oai_chat()`/`_stream_sse` instead) gains the parameter and passes it down:

```python
async def _chat_core(message: str, history: List[dict], session_id: str = "local") -> tuple:
```
— `approval.has_pending(WORKSHOP)` → `approval.has_pending(WORKSHOP, session_id)`; `_resolve_approval(message)` → `_resolve_approval(message, session_id)`; and `route_turn(...)`'s `dispatch_handler=_handle_dispatch` becomes `dispatch_handler=lambda m: _handle_dispatch(m, session_id)`.

3d. Endpoints acquire the dependency:

```python
@app.post("/chat", response_model=ChatResponse, dependencies=[Depends(_require_auth)])
async def chat(req: ChatRequest, session_id: str = Depends(_session_id)):
    reply, td = await _chat_core(req.message, req.history, session_id)
    ...

@app.post("/v1/chat/completions", dependencies=[Depends(_require_auth)])
async def oai_chat(req: _OAIChatRequest, session_id: str = Depends(_session_id)):
    # pass session_id into _chat_core and _stream_sse(message, history, session_id)

@app.get("/pending", dependencies=[Depends(_require_auth)])
async def pending(session_id: str = Depends(_session_id)):
    ticket = approval.peek(WORKSHOP, session_id)
    ...
```

`_stream_sse(message, history, session_id="local")` threads it to its `approval.*` branch and `dispatch_handler` the same way.

- [ ] **Step 4: Run the full suite**

Run: `cd cooper-core && python3 -m pytest -v`
Expected: all pass — single-key clients now map to one consistent session (their key's hash), and pre-existing tests that use one client see unchanged behavior.

Caution: `_check_auth_config`'s first parameter changed type (str → set). If any pre-existing test in `test_main_auth.py` calls it with a string, update that call site to pass a set (e.g. `{"cooper-local"}`) — that is an intended signature change, not a regression.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/main.py cooper-core/test_main_auth.py
git commit -m "feat(step-13): multi-key auth with per-credential approval sessions"
```

---

### Task 3: install-cooper.sh — one-command bootstrap

**Files:**
- Create: `install-cooper.sh` (repo root)

**Interfaces:**
- Consumes: the existing Step 9 compose stacks (`PDA-Runtime/docker-compose.yml`, `docker-compose.private.yml`) and `PDA-Runtime/.env.example`.
- Produces: `./install-cooper.sh [--private]` — prereq checks, `.env` seeding with a generated API key, stack up, health poll.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# install-cooper.sh — one-command COOPER stack bootstrap (Step 13).
# Usage: ./install-cooper.sh [--private]
# Idempotent: safe to re-run. Never overwrites an existing .env.
set -euo pipefail

STACK="open"
COMPOSE_FILE="PDA-Runtime/docker-compose.yml"
if [[ "${1:-}" == "--private" ]]; then
    STACK="private"
    COMPOSE_FILE="PDA-Runtime/docker-compose.private.yml"
fi

say()  { printf '\033[1;36m[cooper]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[cooper]\033[0m %s\n' "$*" >&2; exit 1; }

# 1. Prerequisites
command -v git >/dev/null    || fail "git is required — install it and re-run."
command -v docker >/dev/null || fail "Docker is required — install Docker Desktop/Engine and re-run."
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is required (docker compose)."
docker info >/dev/null 2>&1  || fail "Docker daemon is not running — start it and re-run."

# 2. Repo root (clone if run via curl outside a checkout)
if [[ ! -f "PDA-Runtime/docker-compose.yml" ]]; then
    say "Not inside a COOPER checkout — cloning…"
    git clone https://github.com/ThemisEidos/01_AI_Ecosystem.git cooper
    cd cooper
fi

# 3. Seed .env (never overwrite)
ENV_FILE="PDA-Runtime/.env"
if [[ -f "$ENV_FILE" ]]; then
    say ".env exists — leaving it untouched."
else
    cp PDA-Runtime/.env.example "$ENV_FILE"
    KEY="cooper-$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    printf '\nCOOPER_API_KEYS=%s\n' "$KEY" >> "$ENV_FILE"
    say "Seeded $ENV_FILE with a generated client key:"
    say "    $KEY"
    say "Use it as the Bearer token / Open WebUI connection key."
fi

# 4. Up
say "Starting the $STACK stack…"
docker compose -f "$COMPOSE_FILE" up -d

# 5. Health poll (cooper-core answers /health without auth)
say "Waiting for COOPER core…"
for i in $(seq 1 30); do
    if curl -sf --max-time 2 http://localhost:8000/health >/dev/null 2>&1; then
        say "COOPER is up: http://localhost:8000/health"
        say "Open WebUI:   http://localhost:$([[ $STACK == private ]] && echo 3001 || echo 3000)"
        exit 0
    fi
    sleep 2
done
fail "COOPER core did not become healthy in 60s — check: docker compose -f $COMPOSE_FILE logs cooper-core"
```

(Adjust the clone URL to the real remote at implementation time — check `git remote get-url origin`. If cooper-core's health port differs in the private compose, read the actual mapped port from the compose file and fix the poll URL accordingly — verify, don't assume.)

- [ ] **Step 2: Syntax-check and mark executable**

Run: `bash -n install-cooper.sh && chmod +x install-cooper.sh && echo OK`
Expected: `OK`.

- [ ] **Step 3: Dry-run the idempotency guard**

Run: `./install-cooper.sh` on the dev machine (stack already configured — expect ".env exists — leaving it untouched", stack up, health OK).

- [ ] **Step 4: Commit**

```bash
git add install-cooper.sh
git commit -m "feat(step-13): one-command bootstrap script for the compose stack"
```

- [ ] **Step 5: Live verification (Definition of Done)**

1. Clean-machine test (VM or a wiped clone dir): run `./install-cooper.sh` end-to-end — expect generated key printed, stack up, health OK.
2. Session binding live test — two clients, two keys (set `COOPER_API_KEYS=key-a,key-b` in `PDA-Runtime/.env`, restart):

```bash
# client A triggers an approval-gated dispatch
curl -s -X POST http://localhost:8000/chat -H "Authorization: Bearer key-a" \
  -H "Content-Type: application/json" -d '{"message": "<L2+ dispatch>"}'
# expect: Halt ... requires approval

# client B tries to approve it
curl -s -X POST http://localhost:8000/chat -H "Authorization: Bearer key-b" \
  -H "Content-Type: application/json" -d '{"message": "approve"}'
# expect: NOT an execution — B has no pending ticket in its session

# client A approves its own
curl -s -X POST http://localhost:8000/chat -H "Authorization: Bearer key-a" \
  -H "Content-Type: application/json" -d '{"message": "approve"}'
# expect: execution result
```

Final browser confirmation: Open WebUI still chats and can approve its own dispatches.

---

### Task 4 (CONSOLIDATION — only after Step 12 merges): gateway sessions

**Files:**
- Modify: `cooper-core/gateway.py`, `cooper-core/main.py`
- Test: `cooper-core/test_gateway.py` (append)

**Interfaces:**
- Consumes: Step 12's `poll_once`/`run_loop` handler contract; this plan's session-aware `_chat_core`.
- Produces: handler signature `handler(text: str, sender: str) -> Awaitable[str]`; each Signal sender is their own approval session (`signal:<number>`).

- [ ] **Step 1: Update the failing test** — in `test_gateway.py`, change the fake handlers to accept `(text, sender)` and assert the sender arrives:

```python
    async def fake_handler(text: str, sender: str) -> str:
        replies.append((sender, text))
        return f"echo: {text}"
```

- [ ] **Step 2: Implement** — in `gateway.poll_once`, change `reply = await handler(text)` to `reply = await handler(text, sender)` and the type hint to `Callable[[str, str], Awaitable[str]]`. In `main.py`'s lifespan:

```python
                async def _gateway_handler(text: str, sender: str) -> str:
                    reply, _td = await _chat_core(text, [], session_id=f"signal:{sender}")
                    return reply
```

- [ ] **Step 3: Run the full suite**

Run: `cd cooper-core && python3 -m pytest -v`
Expected: all pass.

- [ ] **Step 4: Live verification** — from your phone (allowlisted): trigger an approval-gated dispatch over Signal, approve it over Signal; confirm a browser client's `approve` at the same moment does NOT consume the Signal session's ticket.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/gateway.py cooper-core/main.py cooper-core/test_gateway.py
git commit -m "feat(step-13): per-sender approval sessions over the signal gateway"
```
