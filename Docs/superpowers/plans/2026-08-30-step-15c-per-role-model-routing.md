# Step 15c — Per-Role Model Routing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each of cooper-core's LLM-calling roles (brain, reviewer, drafter, archivist —
classifier/planner/executor reserved for later slices) its own resolvable model alias per
workshop, driven by `Scripts/PDA_ModelRouting.json`; switch Private's role weights to
`gemma4:e4b-it-qat` per the 2026-08-30 benchmark; add a same-alias LiteLLM deployment pool
so Open survives a single provider key dying mid-conversation.

**Architecture:** A new pure-lookup module (`cooper-core/model_routing.py`) reads the
existing (rewritten) `Scripts/PDA_ModelRouting.json` role→alias map and exposes
`model_for(role, workshop)`. `main.py` resolves each of its four live call sites (brain,
reviewer, drafter, archivist) through this module instead of sharing one `UTILITY_MODEL`
global, so each call site is independently traceable to its own mapped alias (the spec's
DoD: "each role provably queries its mapped alias"). Private's `COOPER-Private` Ollama
alias is repointed from `gemma4:12b` to `gemma4:e4b-it-qat`. Open's `openai` LiteLLM alias
gains a second deployment (via OpenRouter) so the router can fail over within the same
alias before falling through to the existing cross-alias `fallbacks:` chain.

**Tech Stack:** Python 3.12, FastAPI, pytest, Ollama (Private), LiteLLM proxy (Open),
Docker Compose.

**Spec:** `Docs/superpowers/specs/2026-08-18-step-15-max-metrics-design.md` (15c row, line
120); role-split rationale in `Obsidian Vault/brain/North Star.md`'s 2026-08-18 entry;
G2 decision (`Open brain/planner alias starts as gpt-4o-mini`) in
`PROGRESS.md`'s 2026-08-23 entry.

## Global Constraints

- Repo rule: **no new JSON policy files** — this plan rewrites the existing
  `Scripts/PDA_ModelRouting.json`, it does not create a new one.
- Repo rule: all runtime policy stays declarative in JSON; no inline policy logic in
  Python beyond a pure lookup function.
- Every behavior change lands with tests in the sibling `test_*.py` file; full suite
  (`cd cooper-core && .venv/bin/python -m pytest`) must stay green after every task.
- After editing cooper-core, a Docker stack must be rebuilt with
  `docker compose -f PDA-Runtime/docker-compose.<stack>.yml up -d --build cooper-core`
  before live-testing — `up -d` alone serves stale code.
- **2026-08-30 benchmark evidence** (do not re-derive, cite it):
  `gemma4:e4b-it-qat` — 100% GPU resident (3.1GB), 46.5 tok/s avg, 11/11 (100%) tool-call
  accuracy on the real private registry schemas. `gemma4:12b` — 44%/56% CPU/GPU split
  (not fully resident despite flash-attention + q8_0 KV cache), 8.7 tok/s avg, 10/11 (91%)
  accuracy (misrouted one case). Model-swap cost measured at ~5-13s per direction on this
  6GB-VRAM host.
- **Owner decision, 2026-08-30:** Private routes ALL four live roles (brain, reviewer,
  drafter, archivist) to `gemma4:e4b-it-qat` via the `COOPER-Private` alias — not a
  12b-for-reviewer split — specifically to avoid paying the VRAM swap cost on every
  dispatch turn (execute → review → archivist/drafter would otherwise swap models twice).
  `gemma4:12b` is not deleted, just no longer the default for any role; a future slice can
  point a role back at it via the JSON map alone, no code change needed.
- **G2 (2026-08-23, already decided, do not re-litigate):** Open's brain and planner
  roles start on the `openai` alias (`gpt-4o-mini`).

---

### Task 1: Rewrite `Scripts/PDA_ModelRouting.json` to the role-map schema

**Files:**
- Modify: `Scripts/PDA_ModelRouting.json` (full rewrite — the current v1 `command_routes`
  schema is retired, this is the file's first cooper-core-consumed version)

**Interfaces:**
- Produces: a `roles` object keyed by role name (`classifier`, `brain`, `planner`,
  `executor`, `reviewer`, `drafter`, `archivist`), each value `{"private": <alias>,
  "open": <alias>, "notes": <string>}`. Task 2 reads this shape.

- [ ] **Step 1: Read the current file to confirm nothing else in the repo still reads the old schema**

  Run: `grep -rn "PDA_ModelRouting\|command_routes\|worker_command_map" --include=*.py --include=*.ps1 .`
  Expected: no hits outside `Scripts/PDA_ModelRouting.json` itself (it is not yet consumed
  anywhere — that's the point of this task). If something unexpected shows up, stop and
  report it before overwriting the file.

- [ ] **Step 2: Overwrite the file**

```json
{
  "schema_version": "2.0",
  "policy_name": "COOPER Per-Role Model Routing",
  "policy_version": "1.0",
  "roles": {
    "classifier": {
      "private": "COOPER-Private",
      "open": "openai",
      "notes": "Folded into 'brain' since 15a's native tool-calling dispatch retired the separate classify call. Kept as its own map entry for 15d/15e forward-compat; no independent call site today."
    },
    "brain": {
      "private": "COOPER-Private",
      "open": "openai",
      "notes": "Main persona/dispatch call (decision.route_turn / route_turn_stream). COOPER-Private is aliased to gemma4:e4b-it-qat as of Step 15c (2026-08-30 benchmark: 100% GPU-resident, 46.5 tok/s vs 12b's 44%/56% CPU/GPU split at 8.7 tok/s, equal-or-better tool-call accuracy)."
    },
    "planner": {
      "private": "COOPER-Private",
      "open": "openai",
      "notes": "No call site yet — reserved for Step 15e (planner-executor). G2 (2026-08-23): starts as gpt-4o-mini on Open."
    },
    "executor": {
      "private": "COOPER-Private",
      "open": "openai",
      "notes": "No call site yet — reserved for Step 15e."
    },
    "reviewer": {
      "private": "COOPER-Private",
      "open": "openai",
      "notes": "review.review(). Owner decision 2026-08-30: e4b on Private, not 12b, to avoid the measured ~5-13s VRAM swap cost between models on this 6GB-VRAM host."
    },
    "drafter": {
      "private": "COOPER-Private",
      "open": "openai",
      "notes": "proposer.draft_skill()."
    },
    "archivist": {
      "private": "COOPER-Private",
      "open": "openai",
      "notes": "archivist.remember()."
    }
  }
}
```

- [ ] **Step 3: Validate it's well-formed JSON**

  Run: `python3 -c "import json; d = json.load(open('Scripts/PDA_ModelRouting.json')); assert set(d['roles']) == {'classifier','brain','planner','executor','reviewer','drafter','archivist'}; print('ok')"`
  Expected: `ok`

- [ ] **Step 4: Commit**

```bash
git add Scripts/PDA_ModelRouting.json
git commit -m "feat(routing): rewrite PDA_ModelRouting.json as the cooper-core role->alias map (15c)"
```

---

### Task 2: `cooper-core/model_routing.py` — the lookup module

**Files:**
- Create: `cooper-core/model_routing.py`
- Test: `cooper-core/test_model_routing.py`

**Interfaces:**
- Consumes: `Scripts/PDA_ModelRouting.json` (Task 1's shape) via
  `<repo_root>/Scripts/PDA_ModelRouting.json`, resolved the same way `main.py` resolves
  `_MODELFILE` (`Path(__file__).resolve().parent.parent / "Scripts" / "PDA_ModelRouting.json"`).
- Produces: `model_for(role: str, workshop: str, routing: Optional[dict] = None) -> str`
  and `load_routing(path: Optional[Path] = None) -> dict`, and `class ModelRoutingError(Exception)`.
  Task 3 imports and calls `model_routing.model_for(...)`.

- [ ] **Step 1: Write the failing tests**

```python
# cooper-core/test_model_routing.py
import pytest

import model_routing


FIXTURE = {
    "roles": {
        "brain": {"private": "COOPER-Private", "open": "openai"},
        "reviewer": {"private": "COOPER-Private", "open": "openai"},
    }
}


def test_model_for_resolves_private():
    assert model_routing.model_for("brain", "private", FIXTURE) == "COOPER-Private"


def test_model_for_resolves_open():
    assert model_routing.model_for("brain", "open", FIXTURE) == "openai"


def test_model_for_raises_on_unknown_role():
    with pytest.raises(model_routing.ModelRoutingError, match="brai"):
        model_routing.model_for("brai", "private", FIXTURE)


def test_model_for_raises_on_unknown_workshop():
    with pytest.raises(model_routing.ModelRoutingError, match="mars"):
        model_routing.model_for("brain", "mars", FIXTURE)


def test_load_routing_reads_the_real_repo_file():
    routing = model_routing.load_routing()
    assert set(routing["roles"]) == {
        "classifier", "brain", "planner", "executor", "reviewer", "drafter", "archivist",
    }
    for role, entry in routing["roles"].items():
        assert entry["private"], f"{role} missing a private alias"
        assert entry["open"], f"{role} missing an open alias"


def test_real_file_current_defaults():
    # Locks in today's values so an accidental edit to the JSON is caught here, not
    # discovered live. Update deliberately if a future slice changes a role's alias.
    routing = model_routing.load_routing()
    assert model_routing.model_for("brain", "private", routing) == "COOPER-Private"
    assert model_routing.model_for("brain", "open", routing) == "openai"
    assert model_routing.model_for("reviewer", "private", routing) == "COOPER-Private"
    assert model_routing.model_for("archivist", "open", routing) == "openai"
```

- [ ] **Step 2: Run to verify failure**

  Run: `cd cooper-core && .venv/bin/python -m pytest test_model_routing.py -v`
  Expected: `ModuleNotFoundError: No module named 'model_routing'`

- [ ] **Step 3: Implement**

```python
# cooper-core/model_routing.py
"""COOPER's per-role model routing map (Step 15c). Implements
Scripts/PDA_ModelRouting.json — repo rule: no new policy files, implement the existing
one. Pure lookup: (role, workshop) -> the model alias that role's call site should pass
to its backend."""
import json
from pathlib import Path
from typing import Optional

_REPO_ROOT = Path(__file__).resolve().parent.parent
_ROUTING_PATH = _REPO_ROOT / "Scripts" / "PDA_ModelRouting.json"


class ModelRoutingError(Exception):
    pass


def load_routing(path: Optional[Path] = None) -> dict:
    with open(path or _ROUTING_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def model_for(role: str, workshop: str, routing: Optional[dict] = None) -> str:
    """Resolve the model alias for `role` on `workshop` ('private' or 'open')."""
    routing = routing if routing is not None else load_routing()
    roles = routing.get("roles", {})
    if role not in roles:
        raise ModelRoutingError(f"unknown role '{role}' — not in {_ROUTING_PATH}")
    entry = roles[role]
    if workshop not in entry:
        raise ModelRoutingError(
            f"role '{role}' has no mapping for workshop '{workshop}'"
        )
    return entry[workshop]
```

- [ ] **Step 4: Run to verify pass**

  Run: `cd cooper-core && .venv/bin/python -m pytest test_model_routing.py -v`
  Expected: 6 passed

- [ ] **Step 5: Commit**

```bash
git add cooper-core/model_routing.py cooper-core/test_model_routing.py
git commit -m "feat(routing): add model_routing.model_for(role, workshop) lookup (15c)"
```

---

### Task 3: Wire `main.py` to resolve each role independently

**Files:**
- Modify: `cooper-core/main.py` (model-slot block ~line 58-70, startup print ~line
  398-407, `/health` ~line 458-467, `_post_dispatch` ~line 281-304, `_execute` ~line
  307-327)
- Test: `cooper-core/test_main_open_routing.py`, `cooper-core/test_main_auth.py`,
  `cooper-core/test_main_dispatch.py`

**Interfaces:**
- Consumes: `model_routing.model_for(role, workshop)` from Task 2.
- Produces: module-level `main.COOPER_MODEL`, `main.REVIEWER_MODEL`,
  `main.DRAFTER_MODEL`, `main.ARCHIVIST_MODEL` (strings). `main.UTILITY_MODEL` is
  **removed** — it was already flagged "no confirmed consumer found" in its own comment
  at the old `/health` `classifier` key.

- [ ] **Step 1: Write the failing tests first**

  In `cooper-core/test_main_open_routing.py`, replace the existing
  `test_open_workshop_defaults_to_openai_alias_model`:

```python
def test_open_workshop_defaults_to_openai_alias_model():
    assert main.COOPER_MODEL == "openai"
    assert main.REVIEWER_MODEL == "openai"
    assert main.DRAFTER_MODEL == "openai"
    assert main.ARCHIVIST_MODEL == "openai"
```

  In `cooper-core/test_main_auth.py`, replace
  `test_health_emits_both_classifier_and_utility_model_keys`:

```python
def test_health_emits_per_role_model_map():
    client = TestClient(main.app)
    body = client.get("/health").json()
    assert "roles" in body
    assert set(body["roles"]) == {"brain", "reviewer", "drafter", "archivist"}
    assert body["roles"]["brain"] == main.COOPER_MODEL
    assert body["roles"]["reviewer"] == main.REVIEWER_MODEL
    assert body["roles"]["drafter"] == main.DRAFTER_MODEL
    assert body["roles"]["archivist"] == main.ARCHIVIST_MODEL
```

  In `cooper-core/test_main_dispatch.py`, add a new test after
  `test_approve_executes_with_ticket_stored_args` (reuses that test's fake-monkeypatch
  pattern, but asserts the `model=` kwarg each fake received):

```python
def test_execute_passes_each_role_its_own_mapped_model(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", set())
    tool = {"id": "obsidian_note_writer", "name": "Obsidian Note Writer",
            "workshop": "Open Workshop", "executor_type": "note_editor"}

    async def fake_run(t, message, workshop, args=None):
        return "wrote it"

    monkeypatch.setattr(main.executor, "run", fake_run)

    seen = {}

    async def fake_review(tool, message, raw_output, base_url, api_key, model, backend):
        seen["reviewer_model"] = model
        return main.review.ReviewVerdict(verdict="pass", reason="ok")

    monkeypatch.setattr(main.review, "review", fake_review)

    async def fake_remember(conn, tool, message, raw_output, verdict, workshop,
                             base_url, api_key, model, backend):
        seen["archivist_model"] = model

    monkeypatch.setattr(main.archivist, "remember", fake_remember)

    async def fake_draft(tool, message, raw_output, base_url, api_key, model, backend):
        seen["drafter_model"] = model
        return None

    monkeypatch.setattr(main.proposer, "draft_skill", fake_draft)

    asyncio.run(main._execute(tool, "write it", "s5", {"filename": "x.md", "content": "hi"}))
    # _post_dispatch runs as a fire-and-forget background task — pump the loop once
    # so its awaits (which are already-resolved coroutines here) get to run.
    asyncio.run(asyncio.sleep(0))

    assert seen["reviewer_model"] == main.REVIEWER_MODEL
    assert seen.get("archivist_model") == main.ARCHIVIST_MODEL
    assert seen.get("drafter_model") == main.DRAFTER_MODEL
```

  Note: `_post_dispatch` is scheduled via `asyncio.create_task` inside `_execute` — if
  the background task hasn't completed by the time the test asserts, tighten this with
  `await asyncio.gather(*main._BG_TASKS)` right before the asserts instead of a bare
  `sleep(0)`. Check `main._BG_TASKS` (defined near `_queue_notice`) for the exact
  mechanism before relying on either approach; use whichever reliably drains it.

- [ ] **Step 2: Run to verify failure**

  Run: `cd cooper-core && .venv/bin/python -m pytest test_main_open_routing.py test_main_auth.py test_main_dispatch.py -v`
  Expected: failures on `AttributeError: module 'main' has no attribute 'REVIEWER_MODEL'`
  (or similar) and the old assertions no longer matching.

- [ ] **Step 3: Implement — model-slot block**

  Replace (main.py, current lines ~58-70):

```python
# Per-workshop model and backend selection
if WORKSHOP == "private":
    BACKEND          = "ollama"
    COOPER_MODEL     = os.environ.get("COOPER_MODEL", "COOPER-Private")
    UTILITY_MODEL    = os.environ.get("COOPER_CLASSIFIER_MODEL", "COOPER-Private")
    BACKEND_URL      = OLLAMA_HOST
    BACKEND_KEY      = "ollama"
else:  # open
    BACKEND          = "openai"
    COOPER_MODEL     = os.environ.get("COOPER_MODEL", "openai")
    UTILITY_MODEL    = os.environ.get("COOPER_CLASSIFIER_MODEL", "openai")
    BACKEND_URL      = OPENAI_BASE_URL
    BACKEND_KEY      = OPENAI_API_KEY
```

  with:

```python
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
```

  Add `import model_routing` next to the other local imports at the top of `main.py`
  (alongside `import skills` / `import gateway`).

- [ ] **Step 4: Implement — startup print block**

  Replace (current ~lines 398-399):

```python
    print(f"  model    : {COOPER_MODEL}")
    print(f"  utility  : {UTILITY_MODEL}")
```

  with:

```python
    print(f"  model    : {COOPER_MODEL}")
    print(f"  reviewer : {REVIEWER_MODEL}")
    print(f"  drafter  : {DRAFTER_MODEL}")
    print(f"  archivist: {ARCHIVIST_MODEL}")
```

  And the model-reachability check a few lines below (current ~line 407):
  `for name in {COOPER_MODEL, UTILITY_MODEL}:` becomes
  `for name in {COOPER_MODEL, REVIEWER_MODEL, DRAFTER_MODEL, ARCHIVIST_MODEL}:`

- [ ] **Step 5: Implement — `/health`**

  Replace (current ~lines 458-467):

```python
@app.get("/health")
async def health():
    return {
        "status":     "ok",
        "workshop":   WORKSHOP,
        "backend":    BACKEND,
        "model":      COOPER_MODEL,
        "classifier":    UTILITY_MODEL,  # deprecated key name — kept for one release, no confirmed consumer found (fix-forward Task 4)
        "utility_model": UTILITY_MODEL,
    }
```

  with:

```python
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
```

- [ ] **Step 6: Implement — `_post_dispatch` and `_execute` call sites**

  In `_post_dispatch` (current ~lines 285-299), change the two `model=UTILITY_MODEL`
  kwargs: the `archivist.remember(...)` call gets `model=ARCHIVIST_MODEL`, the
  `proposer.draft_skill(...)` call gets `model=DRAFTER_MODEL`.

  In `_execute` (current ~line 325), the `review.review(...)` call's `model=UTILITY_MODEL`
  becomes `model=REVIEWER_MODEL`.

- [ ] **Step 7: Run to verify pass**

  Run: `cd cooper-core && .venv/bin/python -m pytest -q`
  Expected: all tests pass (no `UTILITY_MODEL` references remain —
  `grep -rn UTILITY_MODEL cooper-core/` should return nothing).

- [ ] **Step 8: Commit**

```bash
git add cooper-core/main.py cooper-core/test_main_open_routing.py cooper-core/test_main_auth.py cooper-core/test_main_dispatch.py
git commit -m "feat(routing): resolve brain/reviewer/drafter/archivist each through model_routing (15c)"
```

---

### Task 4: Private role split — repoint `COOPER-Private` to `gemma4:e4b-it-qat`

**Files:**
- Modify: `PDA-Runtime/docker-compose.private.yml` (lines ~10-15, ~42)
- Modify: `setup-linux.sh` (lines ~85-87)
- Modify: `CLAUDE.md` (directory-map row for `Models/cooper-personality/`; "One-time
  model setup" section)

**Interfaces:** none — this task changes which weights an existing alias name points to;
no code changes.

- [ ] **Step 1: Read the exact current text before editing**

  `Read` `PDA-Runtime/docker-compose.private.yml` lines 1-50 and `setup-linux.sh` lines
  75-95 to confirm the surrounding text still matches what's quoted below (it was read
  once already this session; confirm no drift before editing).

- [ ] **Step 2: Edit `docker-compose.private.yml`**

  Replace the `OLLAMA_FLASH_ATTENTION`/`OLLAMA_KV_CACHE_TYPE` comment block:

```yaml
      # 6 GB VRAM is the binding constraint on this host. gemma4:e4b-it-qat (~3.1GB
      # loaded) stays 100% GPU-resident; gemma4:12b does not — measured 44%/56%
      # CPU/GPU split even with flash attention + q8_0 KV cache (2026-08-30 benchmark,
      # PROGRESS.md). COOPER-Private is aliased to e4b as of Step 15c.
      - OLLAMA_FLASH_ATTENTION=1
      - OLLAMA_KV_CACHE_TYPE=q8_0
```

  Replace the `model-init` entrypoint:

```yaml
    entrypoint: ["sh", "-c", "ollama pull gemma4:e4b-it-qat && ollama cp gemma4:e4b-it-qat COOPER-Private && ollama pull nomic-embed-text"]
```

- [ ] **Step 3: Edit `setup-linux.sh`**

  Replace the three lines pulling/aliasing the model (adapt to whatever exact
  indentation Step 1 showed):

```bash
    ollama pull gemma4:e4b-it-qat
    ollama list | grep -q '^COOPER-Private' || ollama cp gemma4:e4b-it-qat COOPER-Private
    ollama pull nomic-embed-text   # semantic skill matching (COOPER_EMBED_MODEL)
```

- [ ] **Step 4: Edit `CLAUDE.md`**

  In the directory map table, change the `Models/cooper-personality/` row's trailing
  clause from "the served weights are Ollama's `gemma4:12b` aliased as `COOPER-Private`"
  to "the served weights are Ollama's `gemma4:e4b-it-qat` aliased as `COOPER-Private`
  (Step 15c, 2026-08-30)".

  In "One-time model setup (host Ollama)", change:

```bash
ollama pull gemma4:12b
ollama cp gemma4:12b COOPER-Private
ollama pull nomic-embed-text     # semantic skill matching
```

  to:

```bash
ollama pull gemma4:e4b-it-qat
ollama cp gemma4:e4b-it-qat COOPER-Private
ollama pull nomic-embed-text     # semantic skill matching
```

- [ ] **Step 5: Rebuild and re-init the Private stack**

  Run: `docker compose -f PDA-Runtime/docker-compose.private.yml up -d --build`
  (rebuilds `cooper-core` for Task 3's code changes AND recreates `model-init`, since its
  entrypoint changed, which re-runs the pull/alias).

- [ ] **Step 6: Live-verify the alias actually points at e4b**

  Run: `docker exec pda-private-ollama ollama list`
  Expected: the `ID` column for `COOPER-Private` matches the `ID` for `gemma4:e4b-it-qat`
  (both `ee6656371218` as of this session — confirm the current ID rather than trusting
  this hardcoded value, tags can be repulled).

- [ ] **Step 7: Live-verify via `/health`**

  Run: `curl -s http://localhost:8000/health`
  Expected: `"roles"` object with `brain`, `reviewer`, `drafter`, `archivist` all equal to
  `"COOPER-Private"`.

- [ ] **Step 8: Live-verify a real dispatch turn end-to-end**

  Run (adjust the message if this exact skill/tool phrasing no longer classifies as
  dispatch-shaped — check `/pending` after, per CLAUDE.md's "test the API, not the
  browser" rule):

```bash
KEY=$(grep '^COOPER_API_KEYS=' PDA-Runtime/.env | cut -d= -f2)
curl -s -X POST http://localhost:8000/chat -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"message":"give me a quick summary of the current private workshop status"}'
```

  Expected: `decision.decision == "dispatch"` (or `"answer"` with tool output, depending
  on whether `status_summary_private` needs approval — check the registry) and a
  reasonable reply, proving the full brain -> execute -> review -> archivist/drafter
  chain still works with e4b as every role's model. Cross-check
  `docker logs pda-private-cooper-core --tail 30` to confirm no errors.

- [ ] **Step 9: Commit**

```bash
git add PDA-Runtime/docker-compose.private.yml setup-linux.sh CLAUDE.md
git commit -m "feat(private): repoint COOPER-Private alias to gemma4:e4b-it-qat (15c)"
```

---

### Task 5: Open — LiteLLM same-alias fallback pool

**Files:**
- Modify: `litellm/litellm_config.yaml`

**Interfaces:** none — config-only.

- [ ] **Step 1: Add a second deployment under the existing `openai` model_name**

  In `litellm/litellm_config.yaml`, directly below the existing:

```yaml
  - model_name: openai
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: os.environ/OPENAI_API_KEY
```

  add:

```yaml
  - model_name: openai
    litellm_params:
      model: openrouter/openai/gpt-4o-mini
      api_key: os.environ/OPENROUTER_API_KEY
```

  This makes `openai` a 2-deployment pool (direct OpenAI + the same model via
  OpenRouter) — LiteLLM's router retries the second deployment on the first one's
  failure/cooldown before ever reaching the existing cross-alias `fallbacks:` chain
  (`openai -> [claude, gemini]`), which stays as-is as the outer safety net.

- [ ] **Step 2: Restart LiteLLM to pick up the config (it's a read-only bind mount, no rebuild needed)**

  Run: `docker compose -f PDA-Runtime/docker-compose.yml up -d --force-recreate litellm`

- [ ] **Step 3: Sanity check both deployments individually still work**

```bash
LKEY=$(grep '^LITELLM_MASTER_KEY=' PDA-Runtime/.env | cut -d= -f2)
curl -s -m 15 http://localhost:4000/v1/chat/completions -H "Authorization: Bearer $LKEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"openai","messages":[{"role":"user","content":"say ok"}],"max_tokens":5}'
```

  Expected: a normal completion (LiteLLM picks one of the pool's two deployments —
  don't assume which).

- [ ] **Step 4: Live-verify the actual DoD scenario — kill one deployment, confirm the turn still completes**

  This is the spec's literal acceptance test: "Kill one provider key mid-conversation ->
  turn still completes via fallback (logged)." Do it reversibly, without touching the
  real secret value:

  1. Read `litellm/litellm_config.yaml`'s primary `openai` deployment's `api_key` line
     (currently `os.environ/OPENAI_API_KEY`).
  2. Temporarily change it to `os.environ/OPENAI_API_KEY_DELIBERATELY_UNSET` (an env var
     that does not exist in `litellm/.env.local`), leaving the OpenRouter deployment
     untouched.
  3. `docker compose -f PDA-Runtime/docker-compose.yml up -d --force-recreate litellm`
  4. Re-run the Step 3 curl command 3-5 times.
     Expected: every call still succeeds (served by the OpenRouter deployment, since the
     primary now has no usable key and LiteLLM's router skips/cools it down).
  5. Run: `docker logs pda-litellm --tail 100 | grep -i "fallback\|cooldown\|retry\|openrouter"`
     Expected: log evidence the router chose/retried the surviving deployment — capture
     the relevant lines for the PROGRESS.md write-up.
  6. **Revert** `litellm/litellm_config.yaml`'s primary deployment back to
     `os.environ/OPENAI_API_KEY` exactly as it was before step 2.
  7. `docker compose -f PDA-Runtime/docker-compose.yml up -d --force-recreate litellm`
  8. Re-run Step 3's curl once more to confirm the stack is back to normal (both
     deployments healthy again).

- [ ] **Step 5: Commit**

```bash
git add litellm/litellm_config.yaml
git commit -m "feat(open): add OpenRouter as a same-alias LiteLLM deployment for openai (15c)"
```

---

### Task 6: Full-suite regression pass + docs

**Files:**
- Modify: `PROGRESS.md`, `Obsidian Vault/brain/North Star.md`

**Interfaces:** none.

- [ ] **Step 1: Run the full suite one more time from a clean checkout state**

  Run: `cd cooper-core && .venv/bin/python -m pytest -q`
  Expected: all green, count should be Task-2's-additions + Task-3's-additions higher
  than the pre-15c baseline (267 as of the approval-ticket fix earlier this session).

- [ ] **Step 2: Live-verify both stacks' `/health` one more time side by side**

  Run:
```bash
curl -s http://localhost:8000/health; echo
curl -s http://localhost:8001/health; echo
```
  Expected: Private's `roles` all `"COOPER-Private"`; Open's `roles` all `"openai"`.

- [ ] **Step 3: Write up PROGRESS.md and North Star**

  Follow this session's existing entry style (see the 2026-08-30 approval-ticket-fix
  entry in both files for the format: what changed, why, what was tested, what's next).
  Record: the E4B benchmark numbers, the owner's e4b-for-everything decision and why
  (swap-cost evidence), the role map rewrite, the LiteLLM fallback-pool DoD test result
  (paste the grep'd log lines from Task 5 Step 4.5), and mark 15c's roadmap checkbox
  `[x]` in `PROGRESS.md`'s Steps 14-15 table. Next up per the execution order: 14b.

- [ ] **Step 4: Commit**

```bash
git add PROGRESS.md "Obsidian Vault/brain/North Star.md"
git commit -m "docs: 15c shipped — per-role model routing, e4b live on Private, LiteLLM fallback pool on Open"
```

---

## Self-Review Notes

- **Spec coverage:** role→alias map via existing JSON (Task 1-2) ✓; Private E4B/12B
  split with benchmark as entry gate (done earlier this session, cited in Global
  Constraints, wired in Task 4) ✓; LiteLLM fallback pools (Task 5) ✓; DoD #1 "each role
  provably queries its mapped alias" — satisfied structurally by Task 3's four
  independent module-level constants + the dispatch-level test asserting each fake
  received its own role's model ✓; DoD #2 "kill one provider key -> turn completes via
  fallback, logged" — Task 5 Step 4 is that exact scenario, live-executed and reverted ✓.
- **`classifier`/`planner`/`executor` roles:** intentionally left as map-only entries
  with no call site — they have none in the current codebase (classifier folded into
  brain at 15a; planner/executor don't exist until 15e). Flagged explicitly in Task 1's
  JSON `notes` fields and in this plan's Global Constraints so 15d/15e's authors don't
  have to re-derive why.
- **No placeholders:** every step has real file contents, real commands, real expected
  output — checked against the "No Placeholders" list in the writing-plans skill.
