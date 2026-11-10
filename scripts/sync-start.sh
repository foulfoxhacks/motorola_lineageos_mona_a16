#!/usr/bin/env bash
#
# Start `repo sync` detached in tmux, logging to ~/sync.log.
#
# Exists so PowerShell only ever has to run a single, quote-free command:
#   wsl -d lineage-build -u builder -- bash /mnt/c/.../scripts/sync-start.sh
#
# Idempotent: prints "already running" if the tmux session exists.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION="${SESSION:-sync}"
LOG="${LOG:-$HOME/sync.log}"

if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "already running"
    exit 0
fi

if ! command -v tmux >/dev/null 2>&1; then
    echo "tmux is not installed" >&2
    exit 1
fi

tmux new -d -s "$SESSION" "JOBS='${JOBS:-16}' bash '$HERE/lineage-sync.sh' > '$LOG' 2>&1"

# Give tmux a moment so a failure inside the session is visible immediately.
sleep 2
if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "started"
    echo "log: $LOG"
elif grep -qa 'synced into' "$LOG" 2>/dev/null; then
    echo "already synced"
else
    echo "failed to start; last log lines:" >&2
    tail -20 "$LOG" 2>/dev/null >&2
    exit 1
fi
