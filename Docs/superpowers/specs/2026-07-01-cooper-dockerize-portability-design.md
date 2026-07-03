# COOPER Step 9 — Dockerize + Portability Design

> Status: approved for implementation. Written 2026-07-01/02 during brainstorming.
> DoD (PRD §5, step 9): `docker compose up` brings COOPER fully online on a fresh checkout.
> Target: "clean deploy on WSL2 now, Pop!_OS later" (PRD §5) — local-first, no Windows dependency.

## 1. Scope

**Private Workshop only.** The Open Workshop stack (`docker-compose.yml`: Open WebUI + n8n +
LiteLLM) has no Windows-loopback problem to solve — it just needs an OpenAI API key — and stays
out of scope for this step. `docker-compose.private.yml` (private-ollama + private-open-webui)
gets a new `cooper-core` service plus a `model-init` provisioning service.

## 2. Why this eliminates most of this project's documented Gotchas

Today, `cooper-core` runs outside Docker specifically because Ollama binds to Windows loopback
(`127.0.0.1:11434`) and WSL2 can't reach that without mirrored networking. `docker-compose.private.yml`
already runs Ollama *in a container* (`private-ollama`). Containerizing `cooper-core` onto the same
Docker network lets it reach Ollama via container DNS (`http://private-ollama:11434`) instead —
eliminating, for this deployment path, every Gotcha tied to the Windows-loopback workaround:
the cmd.exe trailing-space env var bug, the WSL2 mirrored-networking requirement, and
`--reload`'s DrvFs file-watcher flakiness. None of those are Docker-networking problems.

The existing `Start-CooperCore.ps1` / `.venv-win` dev-mode path is **not removed** — it stays for
local iteration with live-reload. This step adds a second, containerized path alongside it.

## 3. Key finding: the custom `COOPER:latest` Ollama model is unused at runtime

`main.py`'s `COOPER_MODEL` defaults to the raw base model name (`gemma4:12b`), not `COOPER` or
`COOPER:latest`. `_load_system_prompt()` reads `Models/cooper-personality/Modelfile`'s `SYSTEM`
block as **plain text** and injects it as a system-role message in every API call — it never
calls Ollama's `/api/create` to build a named model. This means provisioning only needs
`ollama pull gemma4:12b`; `ollama create COOPER -f Modelfile` is not required for the app to
work. (The Modelfile itself is baked into the `cooper-core` image at build time, since
`_load_system_prompt()` reads it from disk relative to `_REPO_ROOT`.)

## 4. Architectural decision: `pda-private-net` loses `internal: true`

`docker-compose.private.yml`'s `pda-private-net` network is currently `internal: true` — no
container on it has any internet route. This predates this step and is not something Step 9
introduces, but it directly conflicts with model provisioning: `ollama pull` is executed by the
CLI (in `model-init`) but the actual download happens *inside* `private-ollama` itself, which
needs to reach Ollama's registry. With `internal: true`, that pull cannot succeed for anyone,
under any workflow — this looks like a pre-existing, never-exercised gap in the private stack.

**Decision:** drop `internal: true` from `pda-private-net`. The real Private-vs-Open security
boundary already lives at the application layer — `workshop.py`'s `check_backend()`/`check_tool()`,
verified thoroughly in Step 6 (`private+openai` blocked, cloud executors blocked, etc.) — not at
the Docker network layer. The network flag was redundant defense that, as discovered here, also
happened to block legitimate operation. Application-layer enforcement is unaffected by this
change and remains the actual control preventing a Private Workshop chat from reaching a cloud
LLM.

*(This specific call was made under a response timeout during brainstorming — flagged here
explicitly in case it should be revisited. The alternative considered was baking the model into
a custom Ollama image at build time, keeping `internal: true` intact at the cost of a multi-GB
custom image and losing the ability to update the model without a rebuild.)*

**Re-reviewed and CONFIRMED 2026-07-02** (post audit-remediation), with two additional findings
that strengthen the decision:
1. Docker does not publish container ports on `internal: true` networks — so the existing
   `private-open-webui` `127.0.0.1:3001` publish (and the planned `cooper-core` `8000`) never
   worked through this network as configured. The flag wasn't just blocking `ollama pull`; it
   was silently breaking the stack's own port publishing.
2. The audit made API auth mandatory at startup (`COOPER_API_KEY`, fail-closed —
   `main.py:_check_auth_config`), so the exposure surface argument for keeping the network
   internal is weaker than when this spec was written: the app layer now enforces both the
   workshop boundary *and* authentication.

## 5. Components

### `cooper-core/Dockerfile` (new)

- Base: `python:3.12-slim` (matches the Python 3.12 already in use via `.venv-win`)
- `COPY requirements.txt`, `pip install --no-cache-dir -r requirements.txt`
- `COPY` the `cooper-core/` source tree
- `COPY` `Models/cooper-personality/Modelfile` to the equivalent `_REPO_ROOT`-relative path
  inside the image (`_REPO_ROOT = Path(__file__).resolve().parent.parent`, so if `cooper-core/`
  lands at `/app/cooper-core`, the Modelfile must land at `/app/Models/cooper-personality/Modelfile`)
- `CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]` — **no `--reload`**; that
  flag is a Windows-dev-mode convenience tied to `Start-CooperCore.ps1`, not needed here
- `EXPOSE 8000`

### `archivist.py` — one-line addition: `COOPER_DB_PATH` env override

`_DEFAULT_DB_PATH` is currently hardcoded relative to `archivist.py`'s own file location. Add:

```python
_DEFAULT_DB_PATH = Path(os.environ.get("COOPER_DB_PATH") or (Path(__file__).resolve().parent / "cooper_memory.db"))
```

(requires `import os`, not currently imported in `archivist.py`). This lets a named Docker volume
mount cleanly at a dedicated data directory rather than fighting Docker's file-vs-directory
volume-mount semantics. No other `archivist.py` behavior changes — `get_conn()`'s existing
`db_path` parameter (used by tests) still takes precedence when explicitly passed.

### `docker-compose.private.yml` — two new services, one healthcheck addition

```yaml
services:
  private-ollama:
    # ... existing config unchanged ...
    healthcheck:
      test: ["CMD", "ollama", "list"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 10s

  model-init:
    image: ollama/ollama:latest
    container_name: pda-private-model-init
    labels:
      ai.ecosystem.stack: private
    environment:
      - OLLAMA_HOST=http://private-ollama:11434
    entrypoint: ["ollama", "pull", "gemma4:12b"]
    networks:
      - pda-private-net
    depends_on:
      private-ollama:
        condition: service_healthy
    restart: "no"

  cooper-core:
    build:
      context: ../cooper-core
      dockerfile: Dockerfile
    container_name: pda-private-cooper-core
    labels:
      ai.ecosystem.stack: private
    ports:
      - "8000:8000"
    environment:
      - WORKSHOP=private
      - OLLAMA_HOST=http://private-ollama:11434
      - COOPER_DB_PATH=/app/data/cooper_memory.db
    volumes:
      - cooper-core-data:/app/data
      - ../Obsidian Vault/brain:/app/Obsidian Vault/brain:ro
    networks:
      - pda-private-net
    depends_on:
      private-ollama:
        condition: service_healthy
      model-init:
        condition: service_completed_successfully
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 15s
    restart: unless-stopped

  private-open-webui:
    # ... existing config unchanged ...

volumes:
  # ... existing volumes unchanged ...
  cooper-core-data:
    name: pda-private-cooper-core-data

networks:
  pda-private-net:
    name: pda-private-net
    # internal: true removed — see §4

## 6. Testing / Verification plan

No unit tests apply to Docker/Compose configuration itself. The actual DoD test is live,
end-to-end, matching this project's established convention (every prior step verified via
`curl` against a running server):

1. On a checkout with no pre-existing Docker state for this stack (`docker compose -f
   PDA-Runtime/docker-compose.private.yml down -v` first, to simulate "fresh checkout" — this
   destroys the `cooper-core-data` and `private-ollama` volumes, so only run this against a
   throwaway/test environment, never against volumes holding real data),
   `docker compose -f PDA-Runtime/docker-compose.private.yml up -d`.
2. Poll `docker compose ps` until `cooper-core` reports healthy (model pull takes several
   minutes on first run — multi-GB download).
3. `curl http://localhost:8000/health` → `{"status":"ok","workshop":"private","backend":"ollama",...}`.
4. Re-run a representative slice of the Steps 1–8 live checks already used throughout this
   project (`POST /chat` greeting, `GET /tools`, a dispatch→approve→execute→review round trip,
   `GET /workshop`) to confirm the containerized server behaves identically to the `.venv-win`
   dev-mode server — this is what "fully online," not just "container started," actually means.

## 7. Explicitly out of scope for this step

- Open Workshop containerization (see §1)
- Pop!_OS-specific testing (PRD names it as a future target; this step's DoD only requires
  working on WSL2 now)
- Any change to `private-open-webui`'s existing direct-to-Ollama wiring
- Rewriting `Start-CooperCore.ps1` or removing the `.venv-win` dev-mode path

## 8. Post-audit amendments (2026-07-02 review — required before implementation)

The 2026-07-02 audit remediation landed after this spec was written and invalidates three
details above. Verified against the code as of commit `134c702`:

1. **`COOPER_API_KEY` must be set in the `cooper-core` service env.** `main.py` now refuses to
   start without it (`_check_auth_config`, audit S1) unless `COOPER_ALLOW_ANON=1`. The §5
   compose env block predates this and would crash-loop the container. Add
   `COOPER_API_KEY=${COOPER_API_KEY:-cooper-local}` (overridable via `.env`, matching the
   launcher's default).

2. **The image must contain `Config/` (registry YAMLs).** `registry.py` resolves
   `_REPO_ROOT/Config/{general,private}_tool_registry.yaml`. §5's Dockerfile copies only
   `cooper-core/` + the Modelfile — without `Config/`, `list_tools()` raises `RegistryError`
   and every dispatch degrades to "no registered tool matches". `COPY` both registry YAMLs to
   `/app/Config/` (same `_REPO_ROOT`-relative trick as the Modelfile).

3. **The image needs PowerShell (`pwsh`) and `Scripts/` for the §6 round-trip test.**
   `executor.py` tries `powershell.exe` then `pwsh` and resolves scripts from
   `_REPO_ROOT/Scripts/`; `python:3.12-slim` has neither. Install `powershell` from the
   Microsoft Debian 12 repo (~180 MB) and `COPY Scripts/Test-Exec.ps1` (the allowlisted
   smoke script) to `/app/Scripts/`. `Test-PDAStack.ps1` stays allowlisted but is expected to
   fail in-container (needs Docker CLI) — the §6 step 4 round trip targets `Test-Exec.ps1`.
   Note: build context must widen from `../cooper-core` to the repo root (with a
   `.dockerignore`) so `Config/`, `Scripts/`, and the Modelfile are all reachable by `COPY`.
