#!/usr/bin/env bash
# setup-linux.sh — one-time system provisioning for a COOPER machine.
# Debian/Ubuntu family (incl. Pop!_OS). Installs the applications COOPER needs;
# repo/stack bootstrap stays in install-cooper.sh.
# Full guide: Documentation/PDA-Portable-Deployment.md
#
# Usage:
#   sudo bash setup-linux.sh              # full dev machine (Docker + host Ollama + pwsh + model)
#   sudo bash setup-linux.sh --minimal    # Docker-only target (e.g. headless home server):
#                                         # skips host Ollama, pwsh, and the model pull —
#                                         # the private stack's in-container Ollama still works.
#
# Idempotent: safe to re-run.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash setup-linux.sh [--minimal]" >&2; exit 1; }
REAL_USER="${SUDO_USER:-$USER}"
MINIMAL=0
[[ "${1:-}" == "--minimal" ]] && MINIMAL=1

say() { printf '\033[1;36m[setup]\033[0m %s\n' "$*"; }

say "1/5 apt packages (git, curl, python venv/pip, sqlite3, Docker Engine + Compose v2)…"
apt-get update
apt-get install -y git curl jq ca-certificates gnupg \
    python3-venv python3-pip sqlite3 \
    docker.io docker-compose-v2 docker-buildx
if [[ $MINIMAL -eq 0 ]]; then
    # libicu for pwsh (package name varies by release; harmless if neither exists)
    apt-get install -y libicu74 2>/dev/null || apt-get install -y libicu72 2>/dev/null || true
fi

systemctl enable --now docker
usermod -aG docker "$REAL_USER"

say "2/5 NVIDIA container toolkit (GPU passthrough for private-ollama)…"
if lspci | grep -qi nvidia; then
    if ! command -v nvidia-ctk >/dev/null 2>&1; then
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
            | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
            | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
            > /etc/apt/sources.list.d/nvidia-container-toolkit.list
        apt-get update
        apt-get install -y nvidia-container-toolkit
    fi
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
else
    say "No NVIDIA GPU detected — skipping. NOTE: docker-compose.private.yml reserves an"
    say "NVIDIA device for private-ollama; on this machine comment out that service's"
    say "'deploy:' block before 'compose up' (see the deployment guide, GPU-less section)."
fi

if [[ $MINIMAL -eq 1 ]]; then
    say "3-5/5 skipped (--minimal): host Ollama, pwsh, model pull."
else
    say "3/5 Ollama (host install — fast bare-metal dev path)…"
    # Check the service file too, not just the binary — an interrupted install (e.g. a
    # network drop mid-run) can leave the binary without the systemd unit.
    if ! command -v ollama >/dev/null 2>&1 || [[ ! -f /etc/systemd/system/ollama.service ]]; then
        curl -fsSL https://ollama.com/install.sh | sh
    fi
    systemctl enable --now ollama

    say "4/5 PowerShell (pwsh) via GitHub tarball…"
    # Microsoft's apt repo still signs with SHA1, rejected by modern apt — see Gotchas.md 2026-07-02.
    if ! command -v pwsh >/dev/null 2>&1; then
        # jq, not grep -m1: an early-exiting grep closes the pipe mid-response, curl
        # exits 23, and pipefail aborts the script.
        PWSH_TAG="$(curl -fsSL https://api.github.com/repos/PowerShell/PowerShell/releases/latest \
            | jq -r '.tag_name' | sed 's/^v//')"
        [[ -n "$PWSH_TAG" && "$PWSH_TAG" != "null" ]] \
            || { echo "could not determine latest pwsh release" >&2; exit 1; }
        curl -fsSL -o /tmp/pwsh.tar.gz \
            "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_TAG}/powershell-${PWSH_TAG}-linux-x64.tar.gz"
        mkdir -p /opt/microsoft/powershell/7
        tar -xzf /tmp/pwsh.tar.gz -C /opt/microsoft/powershell/7
        chmod +x /opt/microsoft/powershell/7/pwsh
        ln -sf /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh
        rm /tmp/pwsh.tar.gz
    fi

    say "5/5 Pull the COOPER base model into host Ollama…"
    ollama pull gemma4:12b
    ollama list | grep -q '^COOPER-Private' || ollama cp gemma4:12b COOPER-Private
fi

say "Done. Versions:"
git --version; docker --version; docker compose version
command -v ollama >/dev/null 2>&1 && ollama --version || true
command -v pwsh   >/dev/null 2>&1 && pwsh --version   || true
say ""
say "Log out and back in (or run 'newgrp docker') so the docker group applies."
say "Then bring the stack up:  bash install-cooper.sh --private   (or no flag for open)"
