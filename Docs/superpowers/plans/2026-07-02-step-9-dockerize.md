# Step 9 — Dockerize + Portability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `docker compose -f PDA-Runtime/docker-compose.private.yml up -d` brings COOPER (cooper-core + Ollama + Open WebUI, Private Workshop) fully online on a fresh checkout with no Windows dependency.

**Architecture:** Add a `cooper-core` container and a one-shot `model-init` provisioning container to the existing private compose stack. cooper-core reaches Ollama via container DNS (`http://private-ollama:11434`), eliminating the Windows-loopback workarounds. The SQLite memory DB moves to a named volume via a new `COOPER_DB_PATH` env override. Source spec: `Docs/superpowers/specs/2026-07-01-cooper-dockerize-portability-design.md` (§8 amendments are binding).

**Tech Stack:** Docker Compose, `python:3.12-slim` + PowerShell (Debian 12 package), uvicorn/FastAPI, Ollama (`gemma4:12b`).

## Global Constraints

- Work on branch `step-9-dockerize` directly (it is the integration branch; commits are per-task).
- The `Start-CooperCore.ps1` / `.venv-win` dev-mode path must keep working — do not modify it or `main.py`.
- `COOPER_API_KEY` is mandatory at startup (`main.py:_check_auth_config`) — every container run must set it (spec §8.1).
- Image must contain `Config/` registry YAMLs, `Models/cooper-personality/Modelfile`, `Scripts/Test-Exec.ps1`, and `pwsh` (spec §8.2–8.3).
- No `--reload` in the container CMD.
- Suite baseline: 64 passing (`cooper-core/.venv/bin/python -m pytest cooper-core/ -q` from repo root).
- The Windows-side server on port 8000 must be **stopped** before live verification (port conflict): `powershell.exe -Command "Get-NetTCPConnection -LocalPort 8000 -State Listen | ForEach-Object { Stop-Process -Id \$_.OwningProcess -Force }"`.
- **Known risk (flag in final report, do not silently fix):** containerized Ollama has no GPU reservation in the existing compose file — gemma4:12b on CPU may be very slow. If verification times out, add the optional GPU block from Task 3 Step 3 and retry; report whichever configuration was actually verified.

---

### Task 1: `COOPER_DB_PATH` env override in archivist.py

**Files:**
- Modify: `cooper-core/archivist.py` (module docstring area, ~line 15 imports; `_DEFAULT_DB_PATH` at ~line 28)
- Test: `cooper-core/test_archivist.py` (append)

**Interfaces:**
- Consumes: nothing new.
- Produces: `archivist._DEFAULT_DB_PATH` honors env var `COOPER_DB_PATH` at import time. `get_conn(db_path=...)` parameter behavior unchanged (tests rely on it).

- [ ] **Step 1: Write the failing test** — append to `cooper-core/test_archivist.py`:

```python
def test_default_db_path_honors_env_override(monkeypatch, tmp_path):
    """COOPER_DB_PATH env var must redirect the default DB location (spec §5)."""
    import importlib
    import archivist as archivist_mod

    target = tmp_path / "data" / "cooper_memory.db"
    monkeypatch.setenv("COOPER_DB_PATH", str(target))
    importlib.reload(archivist_mod)
    try:
        assert archivist_mod._DEFAULT_DB_PATH == target
    finally:
        monkeypatch.delenv("COOPER_DB_PATH")
        importlib.reload(archivist_mod)


def test_default_db_path_falls_back_without_env(monkeypatch):
    import importlib
    import archivist as archivist_mod

    monkeypatch.delenv("COOPER_DB_PATH", raising=False)
    importlib.reload(archivist_mod)
    assert archivist_mod._DEFAULT_DB_PATH.name == "cooper_memory.db"
    assert archivist_mod._DEFAULT_DB_PATH.parent == archivist_mod.Path(archivist_mod.__file__).resolve().parent
```

- [ ] **Step 2: Run to verify failure**

Run: `cooper-core/.venv/bin/python -m pytest cooper-core/test_archivist.py -q -k default_db_path`
Expected: FAIL — `_DEFAULT_DB_PATH` ignores the env var (first test asserts inequality).

- [ ] **Step 3: Implement** — in `cooper-core/archivist.py`, add `import os` to the import block (alphabetical: after `json`), and replace:

```python
_DEFAULT_DB_PATH = Path(__file__).resolve().parent / "cooper_memory.db"
```

with:

```python
_DEFAULT_DB_PATH = Path(os.environ.get("COOPER_DB_PATH") or (Path(__file__).resolve().parent / "cooper_memory.db"))
```

- [ ] **Step 4: Run the full suite**

Run: `cooper-core/.venv/bin/python -m pytest cooper-core/ -q`
Expected: 66 passed.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/archivist.py cooper-core/test_archivist.py
git commit -m "feat(archivist): COOPER_DB_PATH env override for containerized DB volume (step 9)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Dockerfile + .dockerignore

**Files:**
- Create: `cooper-core/Dockerfile`
- Create: `.dockerignore` (repo root — the build context is the repo root, spec §8.3)

**Interfaces:**
- Consumes: `cooper-core/requirements.txt`; `_REPO_ROOT`-relative paths hardcoded in code: `/app/Models/cooper-personality/Modelfile` (main.py), `/app/Config/*.yaml` (registry.py), `/app/Scripts/` (executor.py), `/app/Obsidian Vault/brain` (archivist.py — bind-mounted at runtime, not baked in).
- Produces: image built by compose for service `cooper-core`; app root `/app/cooper-core`, listening on 8000.

- [ ] **Step 1: Create `cooper-core/Dockerfile`**

```dockerfile
FROM python:3.12-slim

# PowerShell for executor.py (registry tools run .ps1 scripts; executor tries
# powershell.exe then pwsh). Debian 12 (bookworm) Microsoft repo.
RUN apt-get update \
 && apt-get install -y --no-install-recommends wget ca-certificates \
 && wget -q https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb \
 && dpkg -i packages-microsoft-prod.deb \
 && rm packages-microsoft-prod.deb \
 && apt-get update \
 && apt-get install -y --no-install-recommends powershell \
 && apt-get purge -y wget \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app/cooper-core

COPY cooper-core/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY cooper-core/ .
# _REPO_ROOT resolves to /app — these paths must mirror the repo layout (spec §5, §8.2-8.3)
COPY Models/cooper-personality/Modelfile /app/Models/cooper-personality/Modelfile
COPY Config/general_tool_registry.yaml Config/private_tool_registry.yaml /app/Config/
COPY Scripts/Test-Exec.ps1 /app/Scripts/Test-Exec.ps1

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

- [ ] **Step 2: Create `.dockerignore` at the repo root**

```
*
!cooper-core
!Models/cooper-personality/Modelfile
!Config
!Scripts/Test-Exec.ps1
cooper-core/.venv
cooper-core/.venv-win
cooper-core/__pycache__
cooper-core/*.log
cooper-core/cooper_memory.db
cooper-core/Dockerfile
```

(Deny-all then re-include: keeps the multi-GB repo — Obsidian Vault, PDA-Backups, .git — out of the build context. Later lines win, so the venv/log/db exclusions override `!cooper-core`.)

- [ ] **Step 3: Build the image and verify contents**

```bash
cd /mnt/d/D_Projects/01_AI_Ecosystem
docker build -f cooper-core/Dockerfile -t cooper-core:step9-check .
docker run --rm cooper-core:step9-check sh -c "ls /app/Config /app/Scripts /app/Models/cooper-personality && pwsh -v && ls /app/cooper-core/main.py"
docker run --rm cooper-core:step9-check sh -c "ls /app/cooper-core | grep -c venv || echo CLEAN"
```

Expected: both registry YAMLs, `Test-Exec.ps1`, `Modelfile` listed; `PowerShell 7.x`; `main.py` present; final command prints `CLEAN`.

- [ ] **Step 4: Commit**

```bash
git add cooper-core/Dockerfile .dockerignore
git commit -m "feat(docker): cooper-core image — python3.12-slim + pwsh, registry/Modelfile/script baked in (step 9)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: docker-compose.private.yml — cooper-core + model-init services

**Files:**
- Modify: `PDA-Runtime/docker-compose.private.yml` (full file shown below)

**Interfaces:**
- Consumes: image from Task 2 (`build.context: ..`, `dockerfile: cooper-core/Dockerfile`).
- Produces: services `cooper-core` (port 8000, auth `cooper-local` by default), `model-init` (one-shot `ollama pull gemma4:12b`); volume `pda-private-cooper-core-data`; `pda-private-net` no longer `internal`.

- [ ] **Step 1: Replace the entire file content** of `PDA-Runtime/docker-compose.private.yml` with:

```yaml
name: pda-private

services:
  private-ollama:
    image: ollama/ollama:latest
    container_name: pda-private-ollama
    labels:
      ai.ecosystem.stack: private
    environment:
      - OLLAMA_NO_CLOUD=true
    volumes:
      - private-ollama:/root/.ollama
    networks:
      - pda-private-net
    healthcheck:
      test: ["CMD", "ollama", "list"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 10s
    restart: unless-stopped

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
      context: ..
      dockerfile: cooper-core/Dockerfile
    container_name: pda-private-cooper-core
    labels:
      ai.ecosystem.stack: private
    ports:
      - "8000:8000"
    environment:
      - WORKSHOP=private
      - OLLAMA_HOST=http://private-ollama:11434
      - COOPER_DB_PATH=/app/data/cooper_memory.db
      - COOPER_API_KEY=${COOPER_API_KEY:-cooper-local}
    volumes:
      - cooper-core-data:/app/data
      - type: bind
        source: "../Obsidian Vault/brain"
        target: "/app/Obsidian Vault/brain"
        read_only: true
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
    image: ghcr.io/open-webui/open-webui:main
    container_name: pda-private-open-webui
    labels:
      ai.ecosystem.stack: private
    ports:
      - "127.0.0.1:3001:8080"
    environment:
      - OLLAMA_BASE_URL=http://private-ollama:11434
    volumes:
      - private-open-webui-main:/app/backend/data
    networks:
      - pda-private-net
    depends_on:
      - private-ollama
    restart: unless-stopped

volumes:
  private-ollama:
    name: pda-private-ollama
  private-open-webui-main:
    name: pda-private-open-webui-main
  cooper-core-data:
    name: pda-private-cooper-core-data

networks:
  pda-private-net:
    name: pda-private-net
    # internal: true removed — see spec §4 (confirmed 2026-07-02): it blocked
    # `ollama pull` AND silently disabled the stack's published ports. The
    # Private/Open boundary is enforced at the app layer (workshop.py + auth).
```

- [ ] **Step 2: Validate compose syntax**

Run: `docker compose -f PDA-Runtime/docker-compose.private.yml config --quiet && echo VALID`
Expected: `VALID` (no output before it).

- [ ] **Step 3 (only if CPU inference proves unusable in Task 4):** add under `private-ollama`:

```yaml
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
```

Do NOT add this preemptively — verify CPU first, and report which configuration was verified.

- [ ] **Step 4: Commit**

```bash
git add PDA-Runtime/docker-compose.private.yml
git commit -m "feat(docker): private stack gains cooper-core + model-init; pda-private-net no longer internal (step 9, spec §4/§8)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Live DoD verification + docs

**Files:**
- Modify: `PROGRESS.md` (step 9 checkbox + decisions log), `Obsidian Vault/brain/North Star.md` (current step)

- [ ] **Step 1: Stop the Windows-side server** (frees port 8000):

```bash
powershell.exe -Command "Get-NetTCPConnection -LocalPort 8000 -State Listen | ForEach-Object { Stop-Process -Id \$_.OwningProcess -Force }"
```

- [ ] **Step 2: Bring the stack up** (first run pulls gemma4:12b — multi-GB, several minutes; do NOT run `down -v` unless volumes are known-throwaway):

```bash
docker compose -f PDA-Runtime/docker-compose.private.yml up -d --build
docker compose -f PDA-Runtime/docker-compose.private.yml ps
```

Poll `ps` until `pda-private-cooper-core` is `healthy`. `pda-private-model-init` should show `Exited (0)`.

- [ ] **Step 3: Health + auth**

```bash
curl -s --max-time 5 http://localhost:8000/health
curl -s -X POST http://localhost:8000/chat -H 'Content-Type: application/json' -d '{"message":"hi"}'
curl -s --max-time 300 -X POST http://localhost:8000/chat -H 'Content-Type: application/json' -H 'Authorization: Bearer cooper-local' -d '{"message":"hi"}'
```

Expected, in order: `{"status":"ok","workshop":"private","backend":"ollama",...}`; `{"detail":"Unauthorized"}`; a normal `{"reply":...}` (CPU inference may take minutes — hence `--max-time 300`).

- [ ] **Step 4: Registry, workshop, and dispatch round trip**

```bash
curl -s -H 'Authorization: Bearer cooper-local' http://localhost:8000/tools | head -c 300
curl -s -H 'Authorization: Bearer cooper-local' http://localhost:8000/workshop
curl -s --max-time 300 -X POST http://localhost:8000/chat -H 'Content-Type: application/json' -H 'Authorization: Bearer cooper-local' -d '{"message":"run Test-Exec.ps1"}'
curl -s --max-time 300 -X POST http://localhost:8000/chat -H 'Content-Type: application/json' -H 'Authorization: Bearer cooper-local' -d '{"message":"approve"}'
```

Expected: 7-tool listing; `{"workshop":"private",...}`; Halt/approval question; then `[Test-Exec.ps1 — OK]` output (pwsh runs it; `Host :` line will be empty on Linux — `$env:COMPUTERNAME` is Windows-only, acceptable).

- [ ] **Step 5: Update PROGRESS.md and North Star** — mark step 9 done with date and record the §4 network decision + verification results in the decisions log; set North Star current step to "9 of 9 COMPLETE" and strike the §4-confirmation warning.

- [ ] **Step 6: Commit and restart the dev-mode server** (restore the usual environment):

```bash
git add PROGRESS.md "Obsidian Vault/brain/North Star.md"
git commit -m "docs: step 9 (dockerize) verified live — compose brings COOPER fully online (DoD met)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
docker compose -f PDA-Runtime/docker-compose.private.yml down
powershell.exe -ExecutionPolicy Bypass -Command "cd D:\D_Projects\01_AI_Ecosystem\cooper-core; .\Start-CooperCore.ps1 -Workshop private"
curl -s --max-time 5 http://localhost:8000/health
```

Expected: health returns `workshop:private` from the dev-mode server again.
