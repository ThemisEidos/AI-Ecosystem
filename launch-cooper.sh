#!/usr/bin/env bash
# launch-cooper.sh — GUI-friendly launcher for a COOPER stack (backend for the
# desktop buttons). Brings the stack up if needed (via install-cooper.sh), waits
# for health, then opens the stack's landing page in the browser. Progress via
# desktop notifications so it works with Terminal=false .desktop entries.
#
# Open lands on the Cockpit (:8001/cockpit, Step 15i) rather than Open WebUI:
# the governance surface is what the desktop button is for. Private still lands
# on its WebUI — /cockpit is deliberately Open-only for now, and Private mounts
# no jobs registry at all (G4), so a cockpit there would only ever be empty.
#
# Usage:
#   ./launch-cooper.sh private            # COOPER Private → WebUI on :3001
#   ./launch-cooper.sh open               # COOPER Open    → Cockpit on :8001
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
            name="COOPER Open"; comment="Cloud-capable workshop — opens the Cockpit (:8001)"
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
    private) INSTALL_ARGS=(--private); LANDING_URL="http://localhost:3001" ;;
    open)    INSTALL_ARGS=();          LANDING_URL="http://localhost:8001/cockpit" ;;
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

# install-cooper.sh polled cooper-core's /health; also wait for the landing page
# itself so the browser doesn't hit a connection error during a cold start.
for _ in $(seq 1 30); do
    curl -sf --max-time 2 "$LANDING_URL" >/dev/null 2>&1 && break
    sleep 2
done

# Hand the API key to the Cockpit so the button does not make you type it.
# It goes in the URL FRAGMENT, which is never sent to the server (no request
# log, no proxy, no access log sees it) and which the page strips from the
# address bar on load. OPEN_URL is only ever passed to xdg-open; every
# notification and log line below uses $LANDING_URL, so the key never reaches
# the desktop notification, the terminal, or tmp/launch-<stack>.log.
OPEN_URL="$LANDING_URL"
if [ "$STACK" = "open" ] && [ -r "$REPO_ROOT/PDA-Runtime/.env" ]; then
    COOPER_KEY="$(grep -m1 '^COOPER_API_KEYS=' "$REPO_ROOT/PDA-Runtime/.env" 2>/dev/null | cut -d= -f2- | cut -d, -f1 | tr -d '[:space:]')"
    if [ -n "${COOPER_KEY:-}" ]; then
        OPEN_URL="${LANDING_URL}#key=${COOPER_KEY}"
    fi
fi

if ! xdg-open "$OPEN_URL" >/dev/null 2>&1; then
    notify "COOPER ${STACK^} is up" "Open $LANDING_URL in your browser." "$ICON"
    exit 0
fi
notify "COOPER ${STACK^} is ready" "$LANDING_URL" "$ICON"
