#!/usr/bin/env bash
# backup-cooper.sh — second copy of COOPER's identity (2026-09-07).
#
# cooper_memory.db (decisions, skill trust, brain index, driver setting) lives
# in one Docker volume per stack on one laptop; before this script there was no
# second copy anywhere. Uses sqlite's own backup API via docker exec -- a raw
# file copy of a hot WAL database can capture a torn state; .backup cannot.
# Backups land in PDA-Backups/memory/ (gitignored), newest kept, older pruned.
#
#   ./backup-cooper.sh                  # back up both stacks now
#   ./backup-cooper.sh --install-timer  # daily systemd user timer at 05:00
set -euo pipefail
cd "$(dirname "$0")"
DEST="PDA-Backups/memory"
KEEP=14

if [ "${1:-}" = "--install-timer" ]; then
    mkdir -p ~/.config/systemd/user
    cat > ~/.config/systemd/user/cooper-backup.service <<UNIT
[Unit]
Description=COOPER memory backup
[Service]
Type=oneshot
ExecStart=$(pwd)/backup-cooper.sh
UNIT
    cat > ~/.config/systemd/user/cooper-backup.timer <<UNIT
[Unit]
Description=Daily COOPER memory backup
[Timer]
OnCalendar=*-*-* 05:00:00
Persistent=true
[Install]
WantedBy=timers.target
UNIT
    systemctl --user daemon-reload
    systemctl --user enable --now cooper-backup.timer
    echo "[backup] daily timer installed (05:00, catches up after sleep)"
    exit 0
fi

mkdir -p "$DEST"
STAMP="$(date +%Y%m%d-%H%M%S)"
ok=0
for pair in "pda-open-cooper-core:open" "pda-private-cooper-core:private"; do
    c="${pair%%:*}"; label="${pair##*:}"
    if ! docker inspect "$c" >/dev/null 2>&1; then
        echo "[backup] $label: container absent — skipped"
        continue
    fi
    if docker exec "$c" python -c "
import sqlite3
src = sqlite3.connect('/app/data/cooper_memory.db')
dst = sqlite3.connect('/tmp/backup.db')
src.backup(dst)
dst.close()
" 2>/dev/null && docker cp "$c:/tmp/backup.db" "$DEST/cooper_memory-$label-$STAMP.db" >/dev/null; then
        docker exec "$c" rm -f /tmp/backup.db
        size=$(stat -c%s "$DEST/cooper_memory-$label-$STAMP.db")
        echo "[backup] $label: $DEST/cooper_memory-$label-$STAMP.db (${size} bytes)"
        ok=$((ok+1))
    else
        echo "[backup] $label: FAILED" >&2
    fi
done

# prune: keep the newest $KEEP per stack
for label in open private; do
    ls -1t "$DEST"/cooper_memory-$label-*.db 2>/dev/null | tail -n +$((KEEP+1)) | xargs -r rm -f
done

[ "$ok" -gt 0 ] || { echo "[backup] nothing backed up" >&2; exit 1; }
