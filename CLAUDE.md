# CLAUDE.md — COOPER Repo Operating Manual

This file is read automatically every session. It describes the repo as it actually exists.
Full scope plan: `PRD.md` (repo root). Full governance spec: `01_AI Ecosystem Architecture.md` through `06_Automation & Workflow Catalog.md`.

> Deployment host since 2026-07-30: Pop!_OS laptop, repo at
> `/home/zb6/Documents/Projects/01_AI_Ecosystem`. The Windows 11/WSL2-era instructions
> (D:\ paths, `.venv-win`, `powershell.exe` interop, mirrored networking) are retired —
> they survive in git history if ever needed.

---

## Project summary

COOPER (Command Operations Orchestrator for Planning, Execution, and Reporting) is a governed AI operations platform (owner: ThemisEidos). It exposes two workshops — Open (cloud-capable via LiteLLM, port 8001) and Private (local-only, Ollama `COOPER-Private`, port 8000) — each with a 6-level permission ladder and Category 1/2 data classification. The runtime is the FastAPI backend in `cooper-core/`, deployed as Docker Compose stacks; it owns conversation, classification (`decision.py`), the approval gate, and the tool registry (all 13 `executor_type`s wired). See `PRD.md` for the full plan.

---

## Directory map

| Path | Contents |
|---|---|
| `cooper-core/` | **The runtime.** FastAPI backend (`main.py`, `decision.py`, `executor.py`, `skills.py`, …), full pytest suite, `Dockerfile`, Linux venv at `.venv/`. Runs in Docker via the compose stacks; bare-metal dev path below. |
| `PDA-Runtime/` | Docker Compose files (`docker-compose.yml` = Open, `docker-compose.private.yml` = Private), `.env` (client keys — gitignored), `.env.example`. The `*.ps1` launch/stop/status wrappers are Windows-era legacy. |
| `Scripts/` | ~200 PowerShell scripts — the v1 backend, now legacy. Some remain callable as registry tools via the `powershell` executor (the cooper-core image ships its own `pwsh`). ~20 JSON policy/config files still read by the runtime. |
| `Config/` | Workshop identity YAML, tool registries (`general_tool_registry.yaml`, `private_tool_registry.yaml`), `skills_registry.yaml`, workflow definitions (`workflows.yaml`) |
| `Skills/` | Learned-skill store: `learned/` (promoted, governed by `Config/skills_registry.yaml`), `_drafts/` (auto-drafted by the self-improvement loop, inert until promoted) |
| `litellm/` | LiteLLM config (`litellm_config.yaml`) and `.env.local` (cloud keys — gitignored) |
| `Models/cooper-personality/` | Ollama Modelfile + personality JSON. At runtime `main.py` only extracts the SYSTEM prompt from the Modelfile; the `FROM gemma3:12b` line is legacy — the served weights are Ollama's `gemma4:12b` aliased as `COOPER-Private` |
| `Open WebUI/` | Python Pipe function (`PDA_ChatBridge_Pipe.py`) from the v1 bridge; pytest test file |
| `State/` | `COOPER_ProjectMemory.json`, `COOPER_Skills.json`, `Workflow_Evidence/` completion records |
| `n8n Workflow/` | n8n workflow JSON exports (import via n8n UI) |
| `Tests/Fixtures/Workflow_Evidence/` | JSON fixtures for evidence schema validation (valid + invalid cases) |
| `Roadmap/` | `PDA-Roadmap.json` (build runner roadmap), `PDA-BuildRunnerPolicy.json` |
| `Codex_Tasks/` | Generated task markdown files (also a bind mount of the Open stack's `cli_launcher` tool) |
| `Documentation/` | Architecture and integration docs — **`PDA-Portable-Deployment.md` is the install/migration guide**, with `PDA-Migration-Checklist.md` as its companion |
| `Docs/` | Design docs, phase exit reviews |
| `PDA-Fabric/` | 4 Fabric prompt pattern templates (reporting, research, review, security) |
| `Legacy_Docs/` | Superseded docs — do not update |
| `PDA-Backups/` | Build runner logs and nightly artifacts — do not modify |
| `PDA-Agent-Runs/` | Agent run records |
| `Obsidian Vault/` | Human knowledge vault incl. `brain/` (North Star, Gotchas, Patterns); output subdirs are gitignored |

---

## Start / stop / status commands

**Fresh machine install:** `sudo bash setup-linux.sh` (system apps: Docker + Compose v2,
NVIDIA toolkit if GPU present, host Ollama + model, pwsh, python; `--minimal` for
Docker-only hosts), then `bash install-cooper.sh [--private]`. Full guide incl. the
application list and which secret/state files carry COOPER's identity:
`Documentation/PDA-Portable-Deployment.md`.

### Bring stacks up / down (Docker Compose)

```bash
# Private stack — cooper-core :8000, Open WebUI :3001, in-container GPU Ollama
bash install-cooper.sh --private          # seeds .env if missing + health-polls
docker compose -f PDA-Runtime/docker-compose.private.yml up -d    # equivalent, no polling
docker compose -f PDA-Runtime/docker-compose.private.yml down

# Open stack — cooper-core :8001, Open WebUI :3000, LiteLLM :4000, n8n :5678, signal-cli
bash install-cooper.sh
docker compose -f PDA-Runtime/docker-compose.yml up -d
docker compose -f PDA-Runtime/docker-compose.yml down
```

Fresh-machine gotcha: `docker-compose.yml` declares the `open-webui` volume
`external: true` — `install-cooper.sh` creates it; for a bare `docker compose up` run
`docker volume create open-webui` once first.

**Desktop launchers:** `./launch-cooper.sh --install-desktop` installs "COOPER Private" /
"COOPER Open" app-grid entries (pin to dock). Each runs `launch-cooper.sh <stack>`:
brings the stack up via `install-cooper.sh`, waits for health, opens the WebUI in the
browser; progress via desktop notifications, failures logged to `tmp/launch-<stack>.log`.

### Port map

| Port | Service | Stack |
|---|---|---|
| 8000 | cooper-core (Private) | Private |
| 8001 | cooper-core (Open; container port 8000) | Open |
| 3001 | Open WebUI (Private; loopback only) | Private |
| 3000 | Open WebUI (Open) | Open |
| 4000 | LiteLLM | Open |
| 5678 | n8n | Open |
| 8080 | signal-cli REST API (loopback only) | Open |

### Status / health

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}'     # pda-* containers
curl -s http://localhost:8000/health                   # private → {"status":"ok","workshop":"private",...}
curl -s http://localhost:8001/health                   # open    → {"status":"ok","workshop":"open",...}
docker compose -f PDA-Runtime/docker-compose.private.yml logs cooper-core --tail 50
```

### Auth

`/health` is unauthenticated. Everything else requires `Authorization: Bearer <key>` where
the key is the `COOPER_API_KEYS` value in `PDA-Runtime/.env` (generated by
`install-cooper.sh`, printed once at seed time). No auth → 401.

```bash
KEY=$(grep '^COOPER_API_KEYS=' PDA-Runtime/.env | cut -d= -f2)
curl -s -X POST http://localhost:8000/chat \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"message":"hi"}'
```

**Test the API, not the browser.** Open WebUI is just a client of `/v1/chat/completions`.
`POST /chat` additionally returns the routing `decision` field for debugging;
`POST /v1/chat/completions` mirrors browser behavior. Use the browser only for a single
final visual confirmation per step, not per iteration.

### Bare-metal dev path (optional — Docker is the deployed truth)

`cooper-core/.venv` is a Linux venv with the full dependency set. To run the server
outside Docker against **host** Ollama (a compose stack must not be holding the port):

```bash
cd cooper-core
WORKSHOP=private OLLAMA_HOST=http://localhost:11434 COOPER_ALLOW_ANON=1 \
  .venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Key env vars (see `main.py` top): `WORKSHOP` (`open`/`private`), `OLLAMA_HOST`,
`COOPER_MODEL` (default `COOPER-Private`), `OPENAI_BASE_URL`/`OPENAI_API_KEY` (Open
workshop → LiteLLM), `COOPER_API_KEYS`/`COOPER_ALLOW_ANON=1`, `GATEWAY_ENABLED=1`,
`COOPER_EMBED_MODEL` (semantic skill matching — default `nomic-embed-text` on Ollama,
`text-embedding-3-small` via LiteLLM; keyword fallback if unavailable).
With `--reload`, edits take effect without a restart.

**After editing cooper-core for the Docker stacks**, rebuild + recreate:

```bash
docker compose -f PDA-Runtime/docker-compose.private.yml up -d --build cooper-core
```

### One-time model setup (host Ollama)

Done by `setup-linux.sh`; manually it is:

```bash
ollama pull gemma4:12b
ollama cp gemma4:12b COOPER-Private
ollama pull nomic-embed-text     # semantic skill matching
# OPTIONAL — legacy. `ollama create COOPER -f Models/cooper-personality/Modelfile` only
# if you want `ollama run COOPER` for manual testing; the runtime doesn't use it.
```

### Open WebUI wiring (per machine, manual — env vars ignored after first run)

Open WebUI stores connections in its own SQLite volume, which takes precedence over
compose env vars. On a fresh volume:

1. `http://localhost:3000` (Open) or `:3001` (Private) → complete the admin-account wizard.
2. Avatar → **Settings → Connections** → under **OpenAI API** click **+**:
   - URL: `http://cooper-core:8000/v1` (container DNS — same value on both stacks)
   - Key: the `COOPER_API_KEYS` value from `PDA-Runtime/.env`
3. Save (it pings the server and fetches models), then pick **COOPER** in the model dropdown.

---

## Running tests

```bash
# Full cooper-core suite — 173 tests, ~1.5 s (run from cooper-core/)
cd cooper-core && .venv/bin/python -m pytest

# v1 Pipe unit tests (legacy bridge, run from repo root)
cooper-core/.venv/bin/python -m pytest "Open WebUI/Test_PDA_ChatBridge_Pipe.py"
```

`Tests/Fixtures/Workflow_Evidence/` contains JSON schema fixtures (valid + invalid) for
evidence validation, exercised by `cooper-core/test_evidence.py`. Standalone runner:
`cooper-core/.venv/bin/python cooper-core/evidence.py <dir>` (exit 1 on any invalid record).

---

## Coding conventions (observed in existing code)

**Python (`cooper-core/`):**
- FastAPI + standard library-first; dependencies stay minimal (`requirements.txt`).
- No new JSON policy files — implement the existing ones (`Config/`, `Scripts/*.json`).
- Every behavior change lands with tests in the sibling `test_*.py` file.

**PowerShell (`Scripts/` — legacy, maintained not extended):**
- `[CmdletBinding()]` on every script; typed `param()` blocks; Verb-Noun naming.
- Path params default to `$PSScriptRoot`-relative values; never hardcode absolute paths.
- All policy in declarative JSON files — no inline policy logic in scripts.

**JSON configs (`Scripts/`, `Config/`):**
- All runtime policy declarative: `PDA_ApprovalPolicy.json`, `PDA_ModelRouting.json`, `PDA_RetryPolicy.json`, `PDA_LifecyclePolicy.json`.
- Worker registry shape: `{name, purpose, model, input_type, output_type, next_worker}`.
- Tool registry shape: `{name, drawer, role, permission_level, executor, approval_required, io_shape, security_notes}`.

---

## DO NOT TOUCH

```
PDA-Runtime/.env                # Secrets — never commit
litellm/.env.local              # Secrets — never commit
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

## Architecture (current)

**Live (v2):** Open WebUI → cooper-core (FastAPI) per workshop. cooper-core owns
conversation, turn classification (`decision.py`), the approval gate
(dispatch → approve → execute), the tool registry (13 executor types), skills
(draft → promote loop, stats in `cooper_memory.db`), and routes inference to
in-container Ollama (Private) or LiteLLM → cloud (Open). n8n and signal-cli run as
containers in the Open stack. SQLite memory travels in the
`pda-private-cooper-core-data` volume (`/app/data/cooper_memory.db`).

**Legacy (v1, retired):** Open WebUI Pipe → n8n → PowerShell raw TCP socket (port 8788) →
`Scripts/COOPER_ConversationalRouter.ps1`. The scripts remain for the `powershell`
executor tools and for reference; do not extend them.

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
curl -s --max-time 3 http://localhost:8000/health   # private
curl -s --max-time 3 http://localhost:8001/health   # open
```
Expected: `{"status":"ok","workshop":...}`. If down:
```bash
docker compose -f PDA-Runtime/docker-compose.private.yml up -d   # or docker-compose.yml (open)
docker compose -f PDA-Runtime/docker-compose.private.yml logs cooper-core --tail 50
```

**3. State position in one sentence before touching code:**
> "Step N in progress. Server up. Today: [DoD for current step]. Gotcha: [if any]."

**4. Proceed.** Do not ask the user to repeat context that's already in PROGRESS.md or the brain files.

### Brain skills available
- `/om-review` — load full brain context
- `/om-daily` — startup sequence + health check
- `/om-capture` — capture a new decision/pattern/gotcha
- `/om-search <term>` — search brain files
- `/om-update <file> <content>` — append to a brain file
