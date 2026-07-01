# CLAUDE.md — COOPER Repo Operating Manual

This file is read automatically every session. It describes the repo as it actually exists.
Full scope plan: `PRD.md` (repo root). Full governance spec: `01_AI Ecosystem Architecture.md` through `06_Automation & Workflow Catalog.md`.

---

## Project summary

COOPER (Command Operations Orchestrator for Planning, Execution, and Reporting) is a governed AI operations platform (owner: ThemisEidos). It exposes two workshops — Open (cloud-capable, Claude Sonnet default, port 3000) and Private (local-only, Qwen via Ollama, port 3001) — each with a 6-level permission ladder and Category 1/2 data classification. The v2 runtime is a FastAPI backend (`cooper-core/`) that owns conversation and routes to local Ollama. The old PowerShell webhook server remains in place (untouched) until FastAPI proves out. See `PRD.md` for the full plan.

---

## Directory map

| Path | Contents |
|---|---|
| `PDA-Runtime/` | Docker Compose files (`docker-compose.yml`, `docker-compose.open.yml`, `docker-compose.private.yml`), launch/stop/status/dashboard PowerShell wrappers, `.env.example` |
| `Scripts/` | ~200 PowerShell scripts — the current backend runtime (router, approval gate, workers, build runner, webhook server) plus ~20 JSON policy/config files |
| `Config/` | Workshop identity YAML, tool registries (`general_tool_registry.yaml`, `private_tool_registry.yaml`), workflow definitions (`workflows.yaml`) |
| `litellm/` | LiteLLM config (`litellm_config.yaml`) and `.env.local.example` |
| `Models/cooper-personality/` | COOPER Ollama Modelfile (base: gemma3:12b) and personality JSON |
| `Open WebUI/` | Python Pipe function (`PDA_ChatBridge_Pipe.py`) deployed into Open WebUI; pytest test file |
| `State/` | `COOPER_ProjectMemory.json`, `COOPER_Skills.json`, `Workflow_Evidence/` completion records |
| `n8n Workflow/` | n8n workflow JSON exports (import via n8n UI) |
| `Tests/Fixtures/Workflow_Evidence/` | JSON fixtures for evidence schema validation (valid + invalid cases) — no runner script, consumed by future tests |
| `Roadmap/` | `PDA-Roadmap.json` (9-task build runner roadmap), `PDA-BuildRunnerPolicy.json` |
| `Codex_Tasks/` | WF-002 generated task markdown files |
| `Documentation/` | Architecture and integration docs |
| `Docs/` | Design docs, phase exit reviews |
| `PDA-Fabric/` | 4 Fabric prompt pattern templates (reporting, research, review, security) |
| `Legacy_Docs/` | Superseded docs — do not update |
| `PDA-Backups/` | Build runner logs and nightly artifacts — do not modify |
| `PDA-Agent-Runs/` | Agent run records |
| `Obsidian Vault/` | Human knowledge vault (agent output files; output subdirs are gitignored) |
| `cooper-core/` | **FastAPI conversational backend (v2 runtime).** `main.py`, `decision.py` (step 2 turn classifier), `requirements.txt`, `Start-CooperCore.ps1` (detached auto-reload launcher). Run from Windows PowerShell (see below). |

---

## Start / stop / status commands

All paths verified to exist. Commands assume PowerShell and Docker Desktop available.

### Profile functions (requires one-time setup)

```powershell
# One-time: install profile functions
pwsh -File setup-pda-profile.ps1
. $PROFILE

# After setup:
aiec-start      # Start Open Stack: Docker Desktop → compose up → webhook server → open browser
pda             # Alias for aiec-start
pdadown         # docker compose down (Open Stack)
aiec-status     # Show container + service + webhook health
pda-status      # Alias for aiec-status
pda-go          # Run Build Runner (next Codex task from Roadmap)
pda-dashboard   # Refresh Obsidian dashboard notes and open them
pda-console     # Alias for pda-dashboard
aiec            # cd to repo root
pdaroot         # cd to PDA-Runtime/
```

### Direct script commands (no profile needed)

```powershell
# Open Stack
pwsh -File PDA-Runtime/launch-pda.ps1
pwsh -File PDA-Runtime/stop-pda.ps1
pwsh -File PDA-Runtime/status-pda.ps1

# Private Stack (port 3001, local-only, no cloud)
pwsh -File Scripts/Start-PDAPrivateStack.ps1

# Build Runner
pwsh -File Scripts/Start-PDABuildRunner.ps1 -ExecuteCodexTask

# Webhook server (auto-started by aiec-start; port 8788)
pwsh -File Scripts/Start-PDAWebhookServer.ps1
```

### Docker Compose direct

```bash
# Open Stack
docker compose -f PDA-Runtime/docker-compose.yml up -d
docker compose -f PDA-Runtime/docker-compose.yml down

# Private Stack
docker compose -f PDA-Runtime/docker-compose.private.yml up -d
docker compose -f PDA-Runtime/docker-compose.private.yml down
```

### One-time model setup

```powershell
# Build COOPER Ollama personality model (requires Ollama running, gemma3:12b pulled)
ollama create COOPER -f Models/cooper-personality/Modelfile
```

---

### COOPER Core (FastAPI backend — run from Windows PowerShell)

Ollama binds to Windows loopback (`127.0.0.1:11434`). The FastAPI server must run on the Windows side to reach it. **Run from a Windows PowerShell terminal**, not WSL2:

```powershell
# One-time: create venv and install dependencies
cd D:\D_Projects\01_AI_Ecosystem\cooper-core
python -m venv .venv-win
.venv-win\Scripts\pip install -r requirements.txt

# One-time: build COOPER model (requires Ollama running, gemma3:12b already pulled)
cd D:\D_Projects\01_AI_Ecosystem
ollama create COOPER -f Models\cooper-personality\Modelfile

# Start the server (interactive, foreground — blocks the terminal)
cd D:\D_Projects\01_AI_Ecosystem\cooper-core
.venv-win\Scripts\uvicorn main:app --host 0.0.0.0 --port 8000
```

**Agent-friendly start (detached, auto-reload — preferred).** `cooper-core/Start-CooperCore.ps1` launches uvicorn as a **detached background process** with `--reload`, frees port 8000 first (so it doubles as a restart), and redirects output to `cooper-core.out.log` / `cooper-core.err.log`. Because it's detached, it can be fired from a one-shot `powershell.exe -Command` call — an agent in WSL2 can start, restart, and stop the server itself without an interactive terminal:

```bash
# from WSL2 — start or restart
powershell.exe -Command "cd D:\D_Projects\01_AI_Ecosystem\cooper-core; .\Start-CooperCore.ps1"
# check startup
cat /mnt/d/D_Projects/01_AI_Ecosystem/cooper-core/cooper-core.err.log
# stop
powershell.exe -Command "Get-NetTCPConnection -LocalPort 8000 -State Listen | ForEach-Object { Stop-Process -Id \$_.OwningProcess -Force }"
```

With `--reload` running, edits to `main.py`/`decision.py` take effect without a restart. Re-run the script only for dependency changes or if reload wedges. Caveat: `--reload`'s file watcher is unreliable across the `/mnt/d` DrvFs boundary (agent edits from WSL while uvicorn watches from Windows) — if an edit doesn't take, re-run `Start-CooperCore.ps1` to force a clean restart.

**Verify from WSL2 or any terminal** (server binds to 0.0.0.0 so it's accessible everywhere):
```bash
curl http://localhost:8000/health
curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "hi"}'
```

### Testing from WSL2 (mirrored networking + interop)

Ollama and the FastAPI server both run on **Windows**. By default WSL2 uses NAT networking, so `localhost` inside WSL points at WSL's own loopback, not Windows' — an agent in WSL2 cannot reach `8000`/`3000`/`11434` until this is resolved. Two ways through:

**1. Mirrored networking (makes `localhost` work from WSL).** `C:\Users\earth\.wslconfig` already contains `[wsl2]` / `networkingMode=mirrored`, but it is inert until WSL restarts. From a **Windows** terminal: `wsl --shutdown`, wait ~8s, reopen WSL, then confirm inside WSL with `wslinfo --networking-mode` (must print `mirrored`; needs WSL 2.0+ on Win11 22H2+ — `wsl --update` if older). Once active, the agent curls `http://localhost:8000` directly. Caveat: mirrored mode can disrupt Docker Desktop networking — if Open WebUI at `http://localhost:3000` breaks after the switch, that's the tradeoff.

**2. Windows interop fallback (works regardless of networking mode).** The request runs in the Windows context where the port resolves, output returns to the agent's stdout:
```bash
powershell.exe -Command "Invoke-RestMethod -Uri http://localhost:8000/chat -Method Post -ContentType 'application/json' -Body '{\"message\":\"sort it out\"}'"
```
The agent can also run one-shot `powershell.exe -Command "..."` calls but **not** interactive PowerShell sessions — hence the detached `Start-CooperCore.ps1` for the server.

**Test the API, not the browser.** Open WebUI is just a client of `/v1/chat/completions`. To see exactly what the browser would render, hit that endpoint directly. Use the browser only for a single final visual confirmation per step, not per iteration. `POST /chat` additionally returns the routing `decision` field for debugging; `POST /v1/chat/completions` mirrors browser behavior.

**Open WebUI wiring (manual — env var ignored after first run):** Open WebUI v0.9.6 stores connections in SQLite, which takes precedence over env vars set in `docker-compose.yml`. Add the connection manually via the UI:

1. `http://localhost:3000` → avatar → **Settings → Connections**
2. Under **OpenAI API**, click **+** to add a connection
3. URL: `http://host.docker.internal:8000/v1`
4. Key: `cooper-local`
5. Click the checkmark/save — it pings the server and fetches models
6. Select **COOPER** from the model dropdown in the chat interface

The env vars (`OPENAI_API_BASE_URL`, `OPENAI_API_KEY`) remain in `docker-compose.yml` as a fallback for fresh installs where no SQLite DB exists yet.

---

## Running tests

```powershell
# Stack health check
pwsh -File Scripts/Test-PDAStack.ps1
pwsh -File Scripts/Test-PDAStack.ps1 -Deep
pwsh -File Scripts/Test-PDAStack.ps1 -ValidateOpenWebUIChat
```

```bash
# Python Pipe unit tests (requires pytest; no pytest.ini exists, run from repo root)
pytest "Open WebUI/Test_PDA_ChatBridge_Pipe.py"
```

`Tests/Fixtures/Workflow_Evidence/` contains JSON schema fixtures (valid + invalid) for evidence validation. No standalone runner exists yet.

---

## Coding conventions (observed in existing code)

**PowerShell:**
- `[CmdletBinding()]` on every script.
- Typed `param()` block with `[Parameter(Mandatory = $false)]` on all params.
- Verb-Noun naming: `Invoke-AIECStart`, `Get-COOPEROperationalStatus`, `Start-PDABuildRunner`.
- Path params default to `$PSScriptRoot`-relative values; never hardcode absolute paths.
- Switch params for execution modes: `-DryRun`, `-PrepareExecution`, `-ExecuteCodexTask`.
- All policy in declarative JSON files — no inline policy logic in scripts.

**Python (`Open WebUI/PDA_ChatBridge_Pipe.py`):**
- Standard library only; `pydantic` imported with inline `try/except` fallback.
- `Valves` inner class for Open WebUI Pipe configuration.
- No external dependencies — file is deployed into Open WebUI's container environment.

**JSON configs (`Scripts/`, `Config/`):**
- All runtime policy declarative: `PDA_ApprovalPolicy.json`, `PDA_ModelRouting.json`, `PDA_RetryPolicy.json`, `PDA_LifecyclePolicy.json`.
- Worker registry shape: `{name, purpose, model, input_type, output_type, next_worker}`.
- Tool registry shape: `{name, drawer, role, permission_level, executor, approval_required, io_shape, security_notes}`.

**New FastAPI code (step 1+):**
- Python + FastAPI. Match standard library-first approach. No new JSON policy files — implement the existing ones (`Config/`, `Scripts/*.json`).

---

## DO NOT TOUCH

```
.env                            # Secrets — never commit
.env.local                      # Secrets — never commit
n8n-api-key.txt                 # Secrets
insert_api_key.sql              # Secrets
workers.json                    # Runtime state — gitignored
PDA-Logs/                       # Runtime logs — gitignored
PDA-Tasks/                      # Task queue — gitignored
PDA-Memory/                     # Memory candidates — gitignored
PDA-Outputs/                    # Worker outputs — gitignored
PDA-Workers/                    # Worker files — gitignored
tmp/                            # Scratch — gitignored
PDA-Runtime/data/               # Runtime state — gitignored
PDA-Backups/                    # Backup artifacts — do not modify
Restricted DMZ Workspace/       # Category 2 / Private Workshop artifacts — human-only
codex-automation-damage-*.txt   # Damage records — do not modify
codex-automation-damage-*.diff  # Damage records — do not modify
```

Secure Vault and StandardNotes are outside this repo entirely — COOPER must never read or write to them.

---

## Current vs target architecture

**Current:** Open WebUI Pipe → n8n → PowerShell raw TCP socket (port 8788, `Scripts/Start-PDAWebhookServer.ps1`) → `Scripts/COOPER_ConversationalRouter.ps1` (~200 `.ps1` scripts). No conversational path; approval gate is policy JSON only; execution gateway unwired.

**Target (PRD §4, §9):** Python FastAPI backend (replaces the socket/PS routing layer) + Ollama conversational core + LiteLLM routing + ChromaDB memory + SQLite state. Open WebUI and n8n retained. PowerShell scripts wrapped as callable registry tools where they do deterministic work.

---

## Discipline rule

Every artifact produced in this repo must **run**, not describe. New standards, policy, or doctrine documents do not count as done. If you cannot execute it, it is not finished. Before declaring any phase done, apply the anti-drift checklist in `PRD.md §10`.

---

## Session startup (obsidian-mind)

Run this at the start of every build session. Takes ~30 seconds.

**1. Load brain context** (invoke `/om-review` or read manually):
```
Obsidian Vault/brain/North Star.md   ← current step + DoD
Obsidian Vault/brain/Gotchas.md      ← active traps to avoid
Obsidian Vault/brain/Patterns.md     ← confirmed implementation choices
```

**2. Confirm server health:**
```bash
curl -s --max-time 3 http://localhost:8000/health
```
Expected: `{"status":"ok","workshop":"private","backend":"ollama",...}`

If down, restart from Windows PowerShell:
```powershell
cd D:\D_Projects\01_AI_Ecosystem\cooper-core
.\Start-CooperCore.ps1 -Workshop private
```
Then check `cooper-core.err.log` if still failing.

**3. State position in one sentence before touching code:**
> "Step N in progress. Server up. Today: [DoD for current step]. Gotcha: [if any]."

**4. Proceed.** Do not ask the user to repeat context that's already in PROGRESS.md or the brain files.

### Brain skills available
- `/om-review` — load full brain context
- `/om-daily` — startup sequence + health check
- `/om-capture` — capture a new decision/pattern/gotcha
- `/om-search <term>` — search brain files
- `/om-update <file> <content>` — append to a brain file
