#!/usr/bin/env bash
# start-build.sh - run scripts/run_build.sh detached in a tmux session.
#
#   bash scripts/start-build.sh            # refuses if a "build" session already exists
#   bash scripts/start-build.sh --force    # kill the existing session first
#
# Why tmux: a build started from `wsl -e bash -c ...` (or any terminal) dies with
# SIGHUP when that window closes. On a 10 GB WSL, soong analysis alone takes ~3 h,
# and one closed window has already thrown away a finished analysis.
# Follow it with:
#   wsl -d lineage-build -u builder -- tmux attach -t build      (Ctrl-b d to detach)
#   wsl -d lineage-build -u builder -- tail -f ~/build.log
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_LOG="${BUILD_LOG:-$HOME/build.log}"
command -v tmux >/dev/null || { echo "ERROR: tmux missing (sudo apt install tmux)" >&2; exit 1; }

if tmux has-session -t build 2>/dev/null; then
    if [ "${1:-}" != "--force" ]; then
        echo "ERROR: a tmux 'build' session already exists. Attach with: tmux attach -t build" >&2
        echo "       or re-run with --force to kill it (an in-progress build is lost)." >&2
        exit 1
    fi
    tmux kill-session -t build
    # killing the last session shuts the tmux server down; starting a new session while it
    # is still exiting fails with "server exited unexpectedly", so wait for it to go away
    for _ in $(seq 1 20); do tmux ls >/dev/null 2>&1 || break; sleep 0.5; done
    sleep 1
fi

# strip CRLF in case the repo was checked out on Windows
runner="$(mktemp --suffix=.sh)"
tr -d '\r' < "$HERE/run_build.sh" > "$runner"
post="$(mktemp --suffix=.sh)"
tr -d '\r' < "$HERE/post-build.sh" > "$post"
first_line=$(( $(wc -l < "$BUILD_LOG" 2>/dev/null || echo 0) + 1 ))

# run_build.sh tees everything to $BUILD_LOG; the session stays open afterwards so the
# exit code and last screen remain visible.
tmux new-session -d -s build -x 220 -y 50 \
    "BUILD_LOG='$BUILD_LOG' bash '$runner'; echo BUILD-EXIT=\$? | tee -a '$BUILD_LOG'; exec bash"

sleep 2
if ! tmux has-session -t build 2>/dev/null; then
    echo "ERROR: the tmux 'build' session did not start. Check: tmux ls; tail ~/build.log" >&2
    exit 1
fi

# post-build: when this run ends, copy the zip/images to C:\mona_work\out, write
# BUILD_RESULT.txt and stop the WSL keepalive, with nobody watching
tmux kill-session -t post 2>/dev/null || true
tmux new-session -d -s post \
    "BUILD_LOG='$BUILD_LOG' PS_SCRIPTS='$HERE' bash '$post' $first_line; exec bash"
tmux list-sessions
echo
echo "Build launched (log: $BUILD_LOG). Follow it with:"
echo "  wsl -d lineage-build -u builder -- tmux attach -t build"
echo "  wsl -d lineage-build -u builder -- tail -f $BUILD_LOG"
