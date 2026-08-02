#!/usr/bin/env bash
# launch-cooper.sh — GUI-friendly launcher for a COOPER stack (backend for the
# desktop buttons). Brings the stack up if needed (via install-cooper.sh), waits
# for health, then opens Open WebUI in the browser. Progress via desktop
# notifications so it works with Terminal=false .desktop entries.
#
# Usage:
#   ./launch-cooper.sh private            # COOPER Private → WebUI on :3001
#   ./launch-cooper.sh open               # COOPER Open    → WebUI on :3000
#   ./launch-cooper.sh --install-desktop  # write ~/.local/share/applications entries
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"
ICON_DIR="$REPO_ROOT/PDA-Runtime/launchers"

notify() { # notify(title, body, [icon]) — desktop notification + stdout echo
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a COOPER ${3:+-i "$3"} "$1" "$2" 2>/dev/null || true
    fi
    printf '[cooper-launch] %s — %s\n' "$1" "$2"
}

install_desktop() {
    local apps_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    mkdir -p "$apps_dir"
    local stack name comment
    for stack in private open; do
        if [[ "$stack" == private ]]; then
            name="COOPER Private"; comment="Local-only workshop (Ollama, ports 8000/3001)"
        else
            name="COOPER Open"; comment="Cloud-capable workshop (LiteLLM, ports 8001/3000)"
        fi
        cat > "$apps_dir/cooper-$stack.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Comment=$comment
Exec=$REPO_ROOT/launch-cooper.sh $stack
Icon=$ICON_DIR/cooper-$stack.svg
Terminal=false
Categories=Development;
Keywords=COOPER;AI;workshop;
StartupNotify=false
EOF
        echo "Installed $apps_dir/cooper-$stack.desktop"
    done
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$apps_dir" || true
    echo "Done — find 'COOPER Private' / 'COOPER Open' in the app launcher (pin to dock as desired)."
}

if [[ "${1:-}" == "--install-desktop" ]]; then
    install_desktop
    exit 0
fi

STACK="${1:-}"
case "$STACK" in
    private) INSTALL_ARGS=(--private); WEBUI_URL="http://localhost:3001" ;;
    open)    INSTALL_ARGS=();          WEBUI_URL="http://localhost:3000" ;;
    *) echo "Usage: launch-cooper.sh <private|open> | --install-desktop" >&2; exit 2 ;;
esac
ICON="$ICON_DIR/cooper-$STACK.svg"
mkdir -p tmp
LOG="$REPO_ROOT/tmp/launch-$STACK.log"

notify "COOPER ${STACK^}" "Starting the $STACK stack…" "$ICON"
if ! bash install-cooper.sh "${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}" >"$LOG" 2>&1; then
    notify "COOPER ${STACK^} failed to start" "See $LOG" "$ICON"
    exit 1
fi

# install-cooper.sh polled cooper-core; also wait for Open WebUI itself so the
# browser doesn't land on a connection error during a cold start.
for _ in $(seq 1 30); do
    curl -sf --max-time 2 "$WEBUI_URL" >/dev/null 2>&1 && break
    sleep 2
done

if ! xdg-open "$WEBUI_URL" >/dev/null 2>&1; then
    notify "COOPER ${STACK^} is up" "Open $WEBUI_URL in your browser." "$ICON"
    exit 0
fi
notify "COOPER ${STACK^} is ready" "$WEBUI_URL" "$ICON"
