# Open Workshop Containerization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a containerized `cooper-core` service (WORKSHOP=open) to the Open stack's `PDA-Runtime/docker-compose.yml`, routed through the existing LiteLLM gateway with an `openai -> claude -> gemini` fallback chain, matching the DoD rigor Step 9 already established for the Private stack.

**Architecture:** Reuse the existing `cooper-core/Dockerfile` unchanged (it already bakes in both tool registries). Change `main.py`'s open-workshop defaults so `BACKEND_URL` points at LiteLLM's container-DNS address instead of OpenAI directly. Add a `cooper-core` service to `docker-compose.yml` on `pda-open-net`, host port `8001` (Private already owns `8000`). Add a fallback chain to `litellm_config.yaml` for the `openai` alias.

**Tech Stack:** FastAPI (existing `cooper-core`), Docker Compose, LiteLLM (existing `pda-litellm` container).

## Global Constraints

- No new Docker image — the existing `cooper-core/Dockerfile` (build context `..`, dockerfile `cooper-core/Dockerfile`) serves both workshops via env vars.
- Host port `8001:8000` for Open's `cooper-core` — Private's `cooper-core` already owns `8000`, and per the design decision, both stacks run simultaneously.
- `COOPER_API_KEY` env var pattern matches Private's `${COOPER_API_KEY:-cooper-local}` default.
- n8n is explicitly out of scope — no changes to the `n8n` service.
- `docker-compose.open.yml` (the stale duplicate) is explicitly out of scope — do not touch it.
- Every step must be verified live (curl/docker logs), matching this project's established convention — no claiming "done" from code inspection alone (PRD §10 discipline rule).

---

### Task 1: Route Open Workshop through LiteLLM in `main.py`

**Files:**
- Modify: `cooper-core/main.py:47-62`
- Test: `cooper-core/test_main_open_routing.py` (new)

**Interfaces:**
- Consumes: existing module-level pattern in `main.py` — `WORKSHOP` (str, already parsed at line 41), `os.environ.get`
- Produces: `OPENAI_BASE_URL` (str, module-level, new default `"http://litellm:4000/v1"`), `COOPER_MODEL`/`CLASSIFIER_MODEL` for the open branch (str, new default `"openai"` — the LiteLLM alias name, not a raw model string)

- [ ] **Step 1: Write the failing test**

Create `cooper-core/test_main_open_routing.py`. Module-level config in `main.py` is computed once at import time from `os.environ`, and `main` is a shared module across the whole test session (other files, e.g. `test_main_auth.py`, also `import main`) — so tests that need a *different* env than ambient must reload in a subprocess, not in-process, to avoid leaking a mutated `main` module into every other test file that runs afterward:

```python
"""Open-workshop routing must default through LiteLLM, not directly to OpenAI."""
import subprocess
import sys
import textwrap

import main  # ambient import — WORKSHOP is unset in the test environment, defaults to "open"


def test_open_workshop_defaults_to_litellm_base_url():
    assert main.OPENAI_BASE_URL == "http://litellm:4000/v1"
    assert main.BACKEND_URL == "http://litellm:4000/v1"


def test_open_workshop_defaults_to_openai_alias_model():
    assert main.COOPER_MODEL == "openai"
    assert main.CLASSIFIER_MODEL == "openai"


def _run_main_import_with_env(env_overrides: dict) -> dict:
    """Import main.py in a fresh subprocess with the given env vars set, print the four
    config values as a parseable block, and return them as a dict. Subprocess isolation
    avoids reload()-ing the shared `main` module in-process, which would leak into every
    other test file that imports it later in the same pytest session."""
    script = textwrap.dedent("""
        import main
        print("OPENAI_BASE_URL=" + main.OPENAI_BASE_URL)
        print("COOPER_MODEL=" + main.COOPER_MODEL)
        print("BACKEND_URL=" + main.BACKEND_URL)
    """)
    env = {"COOPER_API_KEY": "test-key", **env_overrides}
    result = subprocess.run(
        [sys.executable, "-c", script],
        cwd="cooper-core", env=env, capture_output=True, text=True, timeout=30,
    )
    assert result.returncode == 0, result.stderr
    return dict(line.split("=", 1) for line in result.stdout.strip().splitlines())


def test_open_workshop_base_url_still_overridable():
    values = _run_main_import_with_env(
        {"WORKSHOP": "open", "OPENAI_BASE_URL": "http://custom:9000/v1"}
    )
    assert values["OPENAI_BASE_URL"] == "http://custom:9000/v1"


def test_private_workshop_unaffected():
    values = _run_main_import_with_env({"WORKSHOP": "private"})
    assert values["COOPER_MODEL"] == "COOPER-Private"
    assert values["BACKEND_URL"] == "http://localhost:11434"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cooper-core && python -m pytest test_main_open_routing.py -v`
Expected: FAIL — `test_open_workshop_defaults_to_litellm_base_url` and
`test_open_workshop_defaults_to_openai_alias_model` fail with
`AssertionError: assert 'https://api.openai.com/v1' == 'http://litellm:4000/v1'` (and similarly
for `gpt-4o-mini` vs `openai`). The other two subprocess-based tests pass already since they
don't depend on the default being changed yet.

- [ ] **Step 3: Write minimal implementation**

Edit `cooper-core/main.py`, lines 47-62 (the config block right after `OLLAMA_HOST`):

```python
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
```

(Only the `OPENAI_BASE_URL` default string and the two `COOPER_MODEL`/`CLASSIFIER_MODEL` default strings in the `else` branch change. Everything else in this block — `BACKEND`, `BACKEND_URL`, `BACKEND_KEY` variable names, the `private` branch, `DISPLAY_MODEL` below it — is unchanged.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd cooper-core && python -m pytest test_main_open_routing.py -v`
Expected: PASS (4 tests)

- [ ] **Step 5: Run the full existing test suite to confirm no regressions**

Run: `cd cooper-core && python -m pytest -v`
Expected: PASS — all previously-passing tests (`test_approval.py`, `test_archivist.py`, `test_executor.py`, `test_main_auth.py`, `test_registry.py`, `test_review.py`, `test_workshop.py`) still pass. None of them assert the open-workshop default values changed in Step 3 (confirmed during planning — grep showed no hits).

- [ ] **Step 6: Commit**

```bash
git add cooper-core/main.py cooper-core/test_main_open_routing.py
git commit -m "$(cat <<'EOF'
feat(cooper-core): route Open Workshop through LiteLLM instead of OpenAI directly

main.py's open branch defaulted straight to https://api.openai.com/v1,
bypassing the LiteLLM gateway that already runs in the Open stack with
Claude/Gemini/OpenRouter fallback chains configured. Now defaults to
http://litellm:4000/v1 (container DNS) with COOPER_MODEL/CLASSIFIER_MODEL
defaulting to the "openai" LiteLLM alias rather than a raw model string.
Both remain overridable via env vars. Private Workshop unaffected.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Add `openai -> claude -> gemini` fallback chain to `litellm_config.yaml`

**Files:**
- Modify: `litellm/litellm_config.yaml:38-44`

**Interfaces:**
- Consumes: existing `model_list` aliases already defined in this file — `openai`, `claude`, `gemini` (no changes to `model_list` itself)
- Produces: nothing consumed by later tasks — this is a standalone config change verified independently

- [ ] **Step 1: Make the change**

Edit `litellm/litellm_config.yaml`, the `router_settings.fallbacks` list (currently lines 38-44):

```yaml
router_settings:
  fallbacks:
    - "qwen2.5:7b":
        - mistral
        - local-llama
    - gemini:
        - gemini-pro
    - openai:
        - claude
        - gemini
```

(Only the new `- openai:` entry is added; the two existing entries are untouched.)

- [ ] **Step 2: Verify the YAML is valid**

Run: `python3 -c "import yaml; yaml.safe_load(open('litellm/litellm_config.yaml'))" && echo "valid YAML"`
Expected: `valid YAML` (no exception)

- [ ] **Step 3: Restart LiteLLM and verify it loads the new config without error**

Run:
```bash
powershell.exe -Command "cd D:\D_Projects\01_AI_Ecosystem; docker compose -f PDA-Runtime/docker-compose.yml up -d --force-recreate litellm"
sleep 5
curl -s http://localhost:4000/v1/models -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```
Expected: JSON listing all configured aliases including `openai`, `claude`, `gemini` — no startup errors in `docker logs pda-litellm`. (If `litellm/.env.local` isn't populated with a real `LITELLM_MASTER_KEY`/`OPENAI_API_KEY`/etc. yet, this step at minimum confirms the container starts and the YAML parses — full live fallback behavior is verified in Task 5.)

- [ ] **Step 4: Commit**

```bash
git add litellm/litellm_config.yaml
git commit -m "$(cat <<'EOF'
feat(litellm): add openai -> claude -> gemini fallback chain

Open Workshop's cooper-core now defaults to the "openai" alias (Task 1). Without
a fallback chain, a GPT-4o-mini outage would surface as a bare error instead of
cascading to another provider, unlike the qwen2.5:7b and gemini aliases which
already have fallback chains defined.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Add `cooper-core` service to the Open stack's `docker-compose.yml`

**Files:**
- Modify: `PDA-Runtime/docker-compose.yml` (full rewrite of the `services`, `volumes`, and `networks` top-level keys — see exact content below)

**Interfaces:**
- Consumes: `cooper-core/Dockerfile` (Task 1's `main.py` changes are already baked in when this builds), `litellm_config.yaml` (Task 2's fallback chain)
- Produces: `pda-open-cooper-core` container reachable at `http://localhost:8001` from the host and `http://cooper-core:8000` from other containers on `pda-open-net`

- [ ] **Step 1: Replace the full file content**

Replace the entire contents of `PDA-Runtime/docker-compose.yml` with:

```yaml
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:v0.9.6
    container_name: pda-open-webui
    labels:
      ai.ecosystem.stack: open
    ports:
      - "3000:8080"
    environment:
      # Fallback for fresh installs only — v0.9.6 SQLite takes precedence after first run.
      # Add the connection manually via Settings → Connections in the UI (see CLAUDE.md).
      # Container DNS, not host.docker.internal — cooper-core is a real container on this network.
      - OPENAI_API_BASE_URL=http://cooper-core:8000/v1
      - OPENAI_API_KEY=cooper-local
    volumes:
      - open-webui:/app/backend/data
    networks:
      - pda-open-net
    restart: unless-stopped

  n8n:
    image: n8nio/n8n:latest
    container_name: pda-n8n
    labels:
      ai.ecosystem.stack: open
    ports:
      - "5678:5678"
    environment:
      - N8N_RESTRICT_FILE_ACCESS_TO=/files
    volumes:
      - n8n-data:/home/node/.n8n
      - ..:/files:ro
    networks:
      - pda-open-net
    restart: unless-stopped

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: pda-litellm
    labels:
      ai.ecosystem.stack: open
    ports:
      - "4000:4000"
    command: --config /app/config.yaml --detailed_debug
    env_file:
      - ../litellm/.env.local
    volumes:
      - ../litellm/litellm_config.yaml:/app/config.yaml:ro
    networks:
      - pda-open-net
    restart: unless-stopped

  cooper-core:
    build:
      context: ..
      dockerfile: cooper-core/Dockerfile
    container_name: pda-open-cooper-core
    labels:
      ai.ecosystem.stack: open
    ports:
      - "8001:8000"
    environment:
      - WORKSHOP=open
      - OPENAI_BASE_URL=http://litellm:4000/v1
      - OPENAI_API_KEY=${LITELLM_MASTER_KEY:-cooper-local}
      - COOPER_DB_PATH=/app/data/cooper_memory.db
      - COOPER_API_KEY=${COOPER_API_KEY:-cooper-local}
    volumes:
      - cooper-core-data:/app/data
      - type: bind
        source: "../Obsidian Vault/brain"
        target: "/app/Obsidian Vault/brain"
        read_only: true
    networks:
      - pda-open-net
    depends_on:
      - litellm
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 15s
    restart: unless-stopped

volumes:
  open-webui:
    external: true
    name: open-webui
  n8n-data:
  cooper-core-data:
    name: pda-open-cooper-core-data

networks:
  pda-open-net:
    name: pda-open-net
```

- [ ] **Step 2: Validate the compose file syntax**

Run: `powershell.exe -Command "cd D:\D_Projects\01_AI_Ecosystem; docker compose -f PDA-Runtime/docker-compose.yml config --quiet"`
Expected: no output, exit code 0 (compose file parses and resolves cleanly)

- [ ] **Step 3: Build the new service**

Run: `powershell.exe -Command "cd D:\D_Projects\01_AI_Ecosystem; docker compose -f PDA-Runtime/docker-compose.yml build cooper-core"`
Expected: build succeeds (this is the same Dockerfile Private already uses, so the image layers are mostly cache-hits unless `cooper-core/` source changed since the last private build)

- [ ] **Step 4: Bring up the whole Open stack**

Run: `powershell.exe -Command "cd D:\D_Projects\01_AI_Ecosystem; docker compose -f PDA-Runtime/docker-compose.yml up -d"`
Expected: `open-webui`, `n8n`, `litellm`, `cooper-core` all report `Created`/`Started`; `docker ps --filter "label=ai.ecosystem.stack=open"` shows 4 containers

- [ ] **Step 5: Commit**

```bash
git add PDA-Runtime/docker-compose.yml
git commit -m "$(cat <<'EOF'
feat(docker): add cooper-core service to the Open stack

Closes the gap Step 9 explicitly left open (Private Workshop only, see
Docs/superpowers/specs/2026-07-01-cooper-dockerize-portability-design.md §1
and §7). Reuses the existing cooper-core/Dockerfile unchanged. Host port 8001
(Private's cooper-core already owns 8000; both stacks run simultaneously per
design decision). Also updates open-webui's OPENAI_API_BASE_URL fallback from
host.docker.internal:8000 (a stale reference to a Windows-host dev server) to
container DNS http://cooper-core:8000/v1, now that a real container exists.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Verify `cooper-core` health and model identity in-container

**Files:**
- None (verification-only task, no file changes)

**Interfaces:**
- Consumes: running `pda-open-cooper-core` container from Task 3

- [ ] **Step 1: Wait for the healthcheck to pass**

Run: `powershell.exe -Command "docker ps --filter 'name=pda-open-cooper-core' --format 'table {{.Names}}\t{{.Status}}'"`
Expected: `STATUS` eventually shows `(healthy)` — poll every ~10s, up to `start_period: 15s` + `retries: 10` × `interval: 10s` ≈ 115s worst case

- [ ] **Step 2: Check `/health`**

Run: `curl -s http://localhost:8001/health`
Expected: `{"status":"ok","workshop":"open","backend":"openai",...}` — note `backend` is `"openai"` (the internal constant name, unchanged by Task 1) even though traffic actually routes through LiteLLM; this mirrors Private's existing convention of `/health` reporting the real backend tag for diagnostics, not the branded display name

- [ ] **Step 3: Check `/v1/models` shows the branded name**

Run: `curl -s http://localhost:8001/v1/models -H "Authorization: Bearer cooper-local"`
Expected: `{"object":"list","data":[{"id":"COOPER-Open","object":"model",...}]}`

- [ ] **Step 4: No commit needed — this task is verification only**

If Step 2 or 3 fails, do not proceed to Task 5 — debug here first (check `docker logs pda-open-cooper-core` for startup errors, most likely a missing/misconfigured `litellm/.env.local` if the container can't reach LiteLLM).

---

### Task 5: Verify a real `/chat` turn actually traverses LiteLLM, and the fallback chain engages on failure

**Files:**
- None (verification-only task, no file changes)

**Interfaces:**
- Consumes: `litellm/.env.local` (real API keys — not committed; must exist locally with at least a valid key for one provider in the fallback chain to do a meaningful test)

- [ ] **Step 1: Send a real chat turn and confirm it reaches LiteLLM**

Run (two terminals, or run the second right after starting the first):
```bash
# Terminal A
powershell.exe -Command "docker logs -f pda-litellm"
```
```bash
# Terminal B
curl -s -X POST http://localhost:8001/chat \
  -H "Content-Type: application/json" -H "Authorization: Bearer cooper-local" \
  -d '{"message": "say hello in exactly three words"}'
```
Expected: Terminal B returns a real reply (not `"[COOPER error: backend unavailable]"`); Terminal A's LiteLLM logs show an inbound request for the `openai` model alias around the same time — this is what actually confirms the call traversed the gateway rather than cooper-core silently falling back to something else

- [ ] **Step 2: Force the primary model to fail and confirm the fallback engages**

Temporarily break the `openai` alias's credentials — edit `litellm/.env.local` and set `OPENAI_API_KEY` to an invalid value (e.g. append `-broken`), then:
```bash
powershell.exe -Command "cd D:\D_Projects\01_AI_Ecosystem; docker compose -f PDA-Runtime/docker-compose.yml up -d --force-recreate litellm"
sleep 5
curl -s -X POST http://localhost:8001/chat \
  -H "Content-Type: application/json" -H "Authorization: Bearer cooper-local" \
  -d '{"message": "say hello in exactly three words"}'
```
Expected: still a real reply (LiteLLM's router silently retries against `claude`, then `gemini`, per Task 2's fallback chain) — confirm via `docker logs pda-litellm` showing the `openai` call fail followed by a `claude` (or `gemini`) call succeeding, not a bare error surfacing to the user

- [ ] **Step 3: Restore the real API key**

Revert `litellm/.env.local`'s `OPENAI_API_KEY` to its real value, then:
```bash
powershell.exe -Command "cd D:\D_Projects\01_AI_Ecosystem; docker compose -f PDA-Runtime/docker-compose.yml up -d --force-recreate litellm"
```
Expected: `docker compose ps` shows `litellm` healthy again; a follow-up `/chat` call succeeds against the primary `openai` alias again (confirm via LiteLLM logs, not just a 200 from cooper-core)

- [ ] **Step 4: No commit needed — this task is verification only**

`litellm/.env.local` is gitignored (never committed) — nothing to commit from this task.

---

### Task 6: Final browser confirmation

**Files:**
- None (verification-only task, no file changes)

**Interfaces:**
- Consumes: `pda-open-webui` container (already running from Task 3), now pointed at the real `cooper-core` container per Task 3's `OPENAI_API_BASE_URL` fix

- [ ] **Step 1: Open Open WebUI**

Open `http://localhost:3000` in a browser.

- [ ] **Step 2: Check Settings → Connections**

If this is the first time `open-webui`'s SQLite DB has seen the updated `OPENAI_API_BASE_URL` (per the known gotcha: "Open WebUI stores connections in SQLite, env vars ignored after first run" — CLAUDE.md), the old `host.docker.internal:8000` connection may still be saved. If so, manually update it: Settings → Connections → find the OpenAI-compatible entry pointed at cooper-core → change URL to `http://cooper-core:8000/v1`, key `cooper-local` → save (pings and refetches models).

- [ ] **Step 3: Confirm the model dropdown shows `COOPER-Open`**

Select it from the dropdown, send a real message, confirm a reply renders correctly in the chat UI — this is the same class of check that caught the Private Workshop's LiteLLM-decoy bug (PROGRESS.md, 2026-07-02): curl alone doesn't prove the UI is wired to the right backend.

- [ ] **Step 4: Update `PROGRESS.md` with the verification result**

Add a dated entry to `PROGRESS.md` (append before the `## Blocked / needs owner input` section, following the existing entry format) recording: Open Workshop containerization DoD met, `cooper-core` live on port 8001, routed through LiteLLM with `openai -> claude -> gemini` fallback verified, browser-confirmed `COOPER-Open` in the dropdown. Then commit:

```bash
git add PROGRESS.md
git commit -m "$(cat <<'EOF'
docs: Open Workshop containerization verified live (DoD met)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Explicitly out of scope (carried over from the design spec)

- n8n rewiring or integration with `cooper-core`
- Reconciling `docker-compose.open.yml` (stale duplicate)
- Any change to the Private stack or `docker-compose.private.yml`
- Provisioning real OpenAI/Claude/Gemini API keys — `litellm/.env.local` must already exist locally with real keys for Task 5 to be meaningful; if it doesn't, Task 5 should be treated as blocked/deferred rather than faked
