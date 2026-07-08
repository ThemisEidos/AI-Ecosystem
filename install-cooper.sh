#!/usr/bin/env bash
# install-cooper.sh — one-command COOPER stack bootstrap (Step 13).
# Usage: ./install-cooper.sh [--private]
# Idempotent: safe to re-run. Never overwrites an existing .env.
set -euo pipefail

STACK="open"
COMPOSE_FILE="PDA-Runtime/docker-compose.yml"
HEALTH_PORT="8001"
if [[ "${1:-}" == "--private" ]]; then
    STACK="private"
    COMPOSE_FILE="PDA-Runtime/docker-compose.private.yml"
    HEALTH_PORT="8000"
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
    git clone https://github.com/ThemisEidos/AI-Ecosystem.git cooper
    cd cooper
fi

# 3. Seed .env (never overwrite)
ENV_FILE="PDA-Runtime/.env"
if [[ -f "$ENV_FILE" ]]; then
    say ".env exists — leaving it untouched."
else
    cp PDA-Runtime/.env.example "$ENV_FILE"
    KEY="cooper-$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    printf '\nCOOPER_API_KEY=\nCOOPER_API_KEYS=%s\n' "$KEY" >> "$ENV_FILE"
    say "Seeded $ENV_FILE with a generated client key:"
    say "    $KEY"
    say "Use it as the Bearer token / Open WebUI connection key."
    say "Note: the old shared default key ('cooper-local') no longer works once this"
    say ".env exists — reconfigure Open WebUI's connection manually (Settings ->"
    say "Connections, see CLAUDE.md) with the key above."
fi

# 4. Up
say "Starting the $STACK stack…"
docker compose -f "$COMPOSE_FILE" up -d

# 5. Health poll (cooper-core answers /health without auth)
say "Waiting for COOPER core…"
for i in $(seq 1 30); do
    if curl -sf --max-time 2 "http://localhost:$HEALTH_PORT/health" >/dev/null 2>&1; then
        say "COOPER is up: http://localhost:$HEALTH_PORT/health"
        say "Open WebUI:   http://localhost:$([[ $STACK == private ]] && echo 3001 || echo 3000)"
        exit 0
    fi
    sleep 2
done
fail "COOPER core did not become healthy in 60s — check: docker compose -f $COMPOSE_FILE logs cooper-core"
