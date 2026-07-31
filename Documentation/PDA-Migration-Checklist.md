# COOPER Migration Checklist

> Rewritten 2026-07-30 for the v2 FastAPI runtime and Linux targets. Use alongside
> `Documentation/PDA-Portable-Deployment.md` (application list + full procedure).

Use this when standing COOPER up on another machine (laptop or home server).

## On the source machine

- [ ] Commit and push all real work (`git status` clean — don't migrate a dirty tree)
- [ ] Confirm no secrets are committed (`.env`, `*.env.local`, `n8n-api-key.txt` all gitignored)
- [ ] Copy off-git secrets somewhere safe for transfer:
  - [ ] `litellm/.env.local` (cloud provider keys — Open stack)
  - [ ] `PDA-Runtime/.env` (only if keeping the same client key; otherwise skip — the installer regenerates)
  - [ ] `n8n-api-key.txt` (only if using n8n workflows)
- [ ] If carrying COOPER's memory: export `cooper_memory.db`
  - Docker: `docker cp pda-private-cooper-core:/app/data/cooper_memory.db ./`
  - Bare-metal: copy `cooper-core/cooper_memory.db`

## On the target machine

- [ ] Clone the repo
- [ ] `sudo bash setup-linux.sh` (dev machine) or `sudo bash setup-linux.sh --minimal` (Docker-only server)
- [ ] Log out/in (or `newgrp docker`) so the docker group applies
- [ ] Verify: `git --version`, `docker --version`, `docker compose version`
- [ ] Dev machines also: `ollama --version`, `pwsh --version`, `python3 --version`
- [ ] No NVIDIA GPU? Comment out the `deploy:` block on `private-ollama` in
      `PDA-Runtime/docker-compose.private.yml` (see guide, GPU-less section)
- [ ] Place transferred secrets: `litellm/.env.local` (and `PDA-Runtime/.env` if kept)
- [ ] `bash install-cooper.sh --private` and/or `bash install-cooper.sh` (open)
- [ ] Record the generated client key if the installer seeded a fresh `.env`
- [ ] If carrying memory: stop cooper-core, `docker cp` the DB into `/app/data/`, restart

## First-run wiring (per Open WebUI instance)

- [ ] `http://localhost:3000` (open) / `:3001` (private) → create the admin account
- [ ] Settings → Connections → add `http://cooper-core:8000/v1` with the client key
- [ ] Model dropdown shows COOPER-Open / COOPER-Private

## Validation

- [ ] `curl http://localhost:8000/health` (private) / `:8001` (open) → `{"status":"ok",...}`
- [ ] Authenticated `/chat` round trip answers in character
- [ ] A dispatch (`run Test-Exec.ps1`) halts for approval, then executes after "yes, go ahead"
- [ ] `GET /skills` lists the promoted skills (open workshop)
- [ ] Dev machines: pytest suite green (`cooper-core/.venv`)
- [ ] No secret-bearing files staged in git (`git status`)
