# COOPER Portable Deployment Guide

> Rewritten 2026-07-30 for the v2 FastAPI runtime and Linux targets (laptops, home server).
> Supersedes the Windows/PowerShell-era version of this document; the legacy validators it
> referenced (`Test-PDADeployment.ps1`, `Install-PDAEcosystem.ps1`, Fabric CLI, NotebookLM
> packaging) still exist under `Scripts/` but are not part of the v2 install path.

Installing COOPER on a new machine is three layers:

1. **System provisioning** — install the required applications → `setup-linux.sh` (run once, needs sudo)
2. **Stack bootstrap** — seed `.env`, build and start the containers → `install-cooper.sh`
3. **Identity & state** — copy the secret files and (optionally) COOPER's memory → manual, see below

Supported targets: any Debian/Ubuntu-family distro (Pop!_OS, Ubuntu, Debian), desktop or
headless. An NVIDIA GPU is optional (see the GPU-less section).

---

## Application list

Everything COOPER needs on a target machine. `setup-linux.sh` installs all of it; the table
is the reference for what "installed" means, and for non-apt platforms.

### Required on every machine

| Application | Version | Why COOPER needs it | Installed by |
|---|---|---|---|
| Git | ≥ 2.34 | clone/update the repo; `fetch_tap` skill imports inside the container | `setup-linux.sh` (apt) |
| curl | any | health checks, installers | `setup-linux.sh` (apt) |
| Docker Engine | ≥ 24 | runs the entire stack (cooper-core, Open WebUI, Ollama, LiteLLM, n8n) | `setup-linux.sh` (apt: `docker.io`) |
| Docker Compose v2 | ≥ 2.24 | `docker compose` — both stack definitions | `setup-linux.sh` (apt: `docker-compose-v2`) |
| Docker Buildx | any | building the `cooper-core` image | `setup-linux.sh` (apt: `docker-buildx`) |

### Required only if the machine has an NVIDIA GPU

| Application | Why | Installed by |
|---|---|---|
| NVIDIA proprietary driver | GPU inference for private-ollama | distro (Pop!_OS preinstalls it; others: distro driver tool) |
| nvidia-container-toolkit | exposes the GPU to Docker containers | `setup-linux.sh` (auto-skipped when no GPU is detected) |

### Optional — bare-metal dev path (skipped by `setup-linux.sh --minimal`)

Only needed to run/test `cooper-core` outside Docker. A Docker-only machine (e.g. the home
server) does not need any of these.

| Application | Why | Installed by |
|---|---|---|
| Python 3.11+ with `venv` + `pip` | run `cooper-core` bare-metal; run the pytest suite | `setup-linux.sh` (apt: `python3-venv`, `python3-pip`) |
| Ollama (host install) | fast local inference for bare-metal dev | `setup-linux.sh` (official installer) |
| Ollama model `gemma4:12b`, aliased `COOPER-Private` | COOPER's private-workshop model (~7.6 GB download) | `setup-linux.sh` (`ollama pull` + `ollama cp`) |
| PowerShell 7 (`pwsh`) | the `powershell` executor tools when running bare-metal (the Docker image installs its own) | `setup-linux.sh` (GitHub tarball — Microsoft's apt repo is SHA1-signed and rejected by modern apt, see `Gotchas.md` 2026-07-02) |
| sqlite3 CLI | inspecting `cooper_memory.db` | `setup-linux.sh` (apt) |

### Not needed by the runtime

- **Obsidian (the app)** — optional, human-side viewing of `Obsidian Vault/`; the runtime
  reads/writes the vault as plain markdown files.
- **Node.js / npm** — not used by COOPER.
- **Fabric CLI, host n8n** — legacy PowerShell-era tooling; n8n runs as a container in the
  Open stack.

---

## Install procedure (new machine)

```bash
# 1. Get the repo
git clone https://github.com/ThemisEidos/AI-Ecosystem.git 01_AI_Ecosystem
cd 01_AI_Ecosystem

# 2. Provision the system (one-time, idempotent)
sudo bash setup-linux.sh              # dev machine
sudo bash setup-linux.sh --minimal    # Docker-only target (e.g. headless server)

# 3. Apply the docker group without relogging (or just log out/in)
newgrp docker

# 4. Copy secrets from the old machine (see "State & secrets" below) — at minimum
#    litellm/.env.local if the Open stack will make cloud calls.

# 5. Bring the stack up (seeds PDA-Runtime/.env with a fresh client key if absent)
bash install-cooper.sh --private      # Private stack → cooper-core :8000, Open WebUI :3001
bash install-cooper.sh                # Open stack    → cooper-core :8001, Open WebUI :3000
```

`install-cooper.sh` is idempotent, never overwrites an existing `.env`, and health-polls
cooper-core before declaring success. **Record the generated client key it prints** — that is
the Bearer token / Open WebUI connection key for this machine.

### Desktop launcher buttons (optional, per machine)

```bash
./launch-cooper.sh --install-desktop
```

Installs **COOPER Private** and **COOPER Open** into the app launcher (pin to the dock as
desired). Clicking one runs `launch-cooper.sh <stack>`: brings that stack up via
`install-cooper.sh`, waits for cooper-core and Open WebUI health, then opens the WebUI in
the default browser. Progress is reported via desktop notifications; on failure the
notification points at `tmp/launch-<stack>.log`. The `.desktop` entries embed this
checkout's absolute path — re-run `--install-desktop` if the repo moves.

### First-run wiring (per machine, manual)

Open WebUI stores its config in its own Docker volume, so on a fresh machine each instance
starts blank:

1. Open `http://localhost:3000` (open) or `:3001` (private) → complete the admin-account wizard.
2. Settings → Connections → add an OpenAI-API connection:
   - Open stack: URL `http://cooper-core:8000/v1` (container DNS)
   - Private stack: URL `http://cooper-core:8000/v1`
   - Key: the client key `install-cooper.sh` generated (in `PDA-Runtime/.env`, `COOPER_API_KEYS`)
3. Pick **COOPER-Open** / **COOPER-Private** in the model dropdown.

---

## GPU-less machines (home server)

`PDA-Runtime/docker-compose.private.yml` reserves an NVIDIA device for the `private-ollama`
service (`deploy.resources.reservations.devices`). On a machine with no NVIDIA GPU,
`docker compose up` fails with `could not select device driver "nvidia"`.

Fix: comment out the whole `deploy:` block on the `private-ollama` service before bringing
the stack up. Inference then runs CPU-only — slow per turn on small machines, acceptable on
high-RAM/many-core hosts. `setup-linux.sh` prints a reminder when it detects no GPU.

The Open stack has no GPU requirement (cloud backends via LiteLLM).

---

## State & secrets — what actually carries COOPER's identity

Everything else is in git. These are the files/volumes that make a deployment *yours*:

| Item | Contains | How to move |
|---|---|---|
| `litellm/.env.local` | cloud provider API keys (Open stack) | copy manually — gitignored, never commit |
| `PDA-Runtime/.env` | `LITELLM_MASTER_KEY`, `COOPER_API_KEYS` client key | copy manually, **or** let `install-cooper.sh` generate a fresh one (then re-enter the new key in Open WebUI) |
| `n8n-api-key.txt` | n8n API credential | copy only if using the n8n workflows |
| COOPER memory DB | decisions log, learned skills stats, trust scores | Docker: named volume `pda-private-cooper-core-data` (path `/app/data/cooper_memory.db` — move with `docker cp` into the new container, or a volume backup). Bare-metal: the file `cooper-core/cooper_memory.db` |
| `Skills/learned/` + `Config/skills_registry.yaml` | promoted skills + governance manifest | in git — nothing to do |
| `Obsidian Vault/brain/` | North Star, Gotchas, Patterns | in git — nothing to do |
| Open WebUI volumes (`open-webui`, `pda-private-open-webui-main`) | accounts, chat history, connections | optional volume backup; simpler to redo the 2-minute first-run wiring |

A fresh machine with none of these copied still works — COOPER just starts with empty
memory, a new client key, and no cloud keys until `litellm/.env.local` is provided.

---

## Verification

```bash
# Core alive (no auth required on /health)
curl -s http://localhost:8000/health     # private → {"status":"ok","workshop":"private",...}
curl -s http://localhost:8001/health     # open

# Authenticated round trip (key from PDA-Runtime/.env)
curl -s -X POST http://localhost:8000/chat \
  -H "Authorization: Bearer <COOPER_API_KEYS value>" \
  -H "Content-Type: application/json" -d '{"message":"hi"}'

# Full test suite (dev machines only)
cd cooper-core && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt \
  && .venv/bin/python -m pytest
```

Companion checklist: `Documentation/PDA-Migration-Checklist.md`.
