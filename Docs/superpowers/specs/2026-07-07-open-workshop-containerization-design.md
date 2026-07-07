# COOPER — Open Workshop Containerization Design

> Status: approved for implementation. Written 2026-07-07 during brainstorming.
> Follows Step 9 (Private Workshop containerization, see
> `2026-07-01-cooper-dockerize-portability-design.md`), which explicitly scoped Open
> Workshop out. This spec closes that gap: `cooper-core` (WORKSHOP=open) joins
> `docker-compose.yml` alongside `open-webui`, `n8n`, and `litellm`.

## 1. Scope

Add a `cooper-core` service to `PDA-Runtime/docker-compose.yml` (the Open stack), built from the
existing `cooper-core/Dockerfile` — no new image needed; that Dockerfile already `COPY`s both
tool registry YAMLs and the Modelfile, so the identical image serves either workshop depending on
env vars. No changes to `docker-compose.private.yml` or the Private stack.

## 2. Architectural decision: route Open Workshop through LiteLLM, not directly to OpenAI

Today, `main.py`'s `else: # open` branch defaults `BACKEND_URL` to `https://api.openai.com/v1` —
direct to OpenAI, completely bypassing the `litellm` container that already runs in the Open
stack with Claude/Gemini/OpenRouter/local-Ollama aliases and fallback chains configured
(`litellm/litellm_config.yaml`). Meanwhile every legacy PowerShell tool (`Scripts/Invoke-PDAModel.ps1`,
`Get-PDAStatus.ps1`, etc.) already treats LiteLLM at `:4000` as *the* governed multi-provider
gateway. Containerized `cooper-core` bypassing it would be a second, inconsistent path to cloud
models — the same class of problem as the LiteLLM decoy alias found in the Private Workshop
(`PROGRESS.md`, 2026-07-02).

**Decision:** Open Workshop's `cooper-core` talks to `http://litellm:4000/v1` (container DNS)
instead of OpenAI directly, with `COOPER_MODEL` defaulting to the `openai` alias already defined
in `litellm_config.yaml`. This unifies the new runtime with the existing governed-gateway design
and gets fallback protection for free.

### Fallback chain addition to `litellm/litellm_config.yaml`

`router_settings.fallbacks` currently only covers `qwen2.5:7b` and `gemini`. Add:

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

So a GPT-4o-mini outage cascades to Claude Sonnet, then Gemini, before the user sees an error.

## 3. `main.py` changes

`OPENAI_BASE_URL` default changes from `https://api.openai.com/v1` to LiteLLM's container-DNS
address:

```python
OPENAI_BASE_URL = os.environ.get("OPENAI_BASE_URL", "http://litellm:4000/v1")
```

`COOPER_MODEL`/`CLASSIFIER_MODEL` open-workshop defaults change from `gpt-4o-mini` to `openai`
(the LiteLLM alias name, not the raw model string — LiteLLM resolves `openai` → `gpt-4o-mini`
internally per its `model_list`). `BACKEND_KEY` for the open branch becomes LiteLLM's master key
(`LITELLM_MASTER_KEY`, already defined in `litellm/.env.local`) instead of a real
`OPENAI_API_KEY` — `cooper-core` no longer needs direct OpenAI credentials at all once it talks
through the gateway.

No other `main.py` logic changes. `DISPLAY_MODEL` (`f"COOPER-{WORKSHOP.capitalize()}"` →
`COOPER-Open`) already works correctly for this workshop without modification.

## 4. `docker-compose.yml` — one new service, one existing-service fix

```yaml
services:
  open-webui:
    # ... existing config ...
    environment:
      # Was pointing at a Windows-host dev server (host.docker.internal:8000) — wrong once
      # cooper-core is a real container on this network. Container DNS instead:
      - OPENAI_API_BASE_URL=http://cooper-core:8000/v1
      - OPENAI_API_KEY=cooper-local

  n8n:
    # ... existing config unchanged ...

  litellm:
    # ... existing config unchanged ...

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

Host port `8001` (not `8000`) — both stacks run simultaneously (confirmed with user), and
`pda-private-cooper-core` already owns `8000`.

Archivist's `Obsidian Vault/brain` mount is duplicated from the Private pattern: `recall()` isn't
workshop-gated in `archivist.py`, so Open Workshop gets the same brain-search recall capability.
Brain content is internal engineering notes (North Star, Gotchas, Patterns, Key Decisions,
Skills) — not Category 2/Restricted data — so sending it as LLM context through a cloud provider
is not a governance boundary violation.

## 5. Testing / Verification plan

Same convention as Step 9 (live, end-to-end, not just "container started"):

1. `docker compose -f PDA-Runtime/docker-compose.yml build cooper-core`
2. `docker compose -f PDA-Runtime/docker-compose.yml up -d`
3. `curl http://localhost:8001/health` → `{"status":"ok","workshop":"open","backend":"openai",...}`
4. `curl http://localhost:8001/v1/models` → lists `COOPER-Open`
5. `POST /chat` through to a real reply, confirming the call actually traverses LiteLLM (check
   `docker logs pda-litellm` for the inbound request, not just a 200 from `cooper-core`)
6. Force a primary-model failure (e.g. temporarily bad `OPENAI_API_KEY` in `litellm/.env.local`)
   and confirm the fallback chain actually engages — cascades to `claude`, not a bare error
7. One final browser confirmation: Open WebUI (`localhost:3000`) dropdown shows `COOPER-Open`,
   a chat turn completes and reads correctly

## 6. Explicitly out of scope

- n8n rewiring or integration with `cooper-core` (confirmed with user — n8n stays as-is)
- Reconciling `docker-compose.open.yml`, which appears to be a stale duplicate of
  `docker-compose.yml` missing the `open-webui` fallback env vars added 2026-07-07 — flagged,
  not touched
- Any change to the Private stack or `docker-compose.private.yml`
- Real OpenAI/Claude/Gemini API keys — `litellm/.env.local` already handles these; this step
  only wires `cooper-core` to the gateway that holds them
