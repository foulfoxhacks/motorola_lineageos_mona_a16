#!/usr/bin/env bash
#
# Progress bar + ETA for `repo sync` (lineage-24.0 on mona).
#
#   bash scripts/sync-watch.sh              # live, loops
#   bash scripts/sync-watch.sh --once       # single snapshot
#
# Progress comes from disk usage of the source tree: it grows monotonically
# and does not care whether repo thinks it is on a TTY. The phase word comes
# from the tail of the sync log, otherwise from the `repo sync` process.
#
# Two output modes:
#   TTY      one line redrawn in place with \r
#   not TTY  one timestamped line per sample (PowerShell pipes are not TTYs,
#            and it would otherwise buffer the redraws until the next \n)
#
# Env overrides:
#   SRC_DIR=~/lineage     source tree
#   LOG=~/sync.log        where lineage-sync.sh writes
#   TARGET_GB=150         expected final size (source only, no out/)
#   INTERVAL=20           seconds between samples
#   HEARTBEAT=300         seconds between status lines in TTY mode
#   DU_PATH=...           defaults to $SRC_DIR/.repo
#
set -uo pipefail

SRC_DIR="${SRC_DIR:-$HOME/lineage}"
LOG="${LOG:-$HOME/sync.log}"
SESSION="${SESSION:-sync}"
# Measured on lineage-24.0: .repo settles at ~111 GiB. The old 150 default
# made the bar stop at 74 % even though the sync had finished.
TARGET_GB="${TARGET_GB:-115}"
INTERVAL="${INTERVAL:-20}"
HEARTBEAT="${HEARTBEAT:-300}"
DU_PATH="${DU_PATH:-$SRC_DIR/.repo}"

ONCE=0
[ "${1:-}" = "--once" ] && ONCE=1

TARGET=$(( TARGET_GB * 1024 * 1024 * 1024 ))
WIDTH=32
MILESTONES="10 25 50 75 90 100"

# shellcheck disable=SC2034
declare -A seen

TTY=0
[ -t 1 ] && TTY=1

repeat() {  # repeat <char> <count>
    local c="$1" n="$2" out=''
    while [ "${#out}" -lt "$n" ]; do out="$out$c"; done
    printf '%s' "$out"
}

human() {   # bytes -> "1.2 GiB"
    awk -v b="${1:-0}" 'BEGIN{
        n=split("B KiB MiB GiB TiB", u, " ");
        i=1;
        while (b >= 1024 && i < n) { b /= 1024; i++ }
        if (i == 1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
    }'
}

eta() {     # seconds -> "1h 04m" / "12m 30s" / "--"
    local s="${1:--1}"
    if [ "$s" -lt 0 ]; then printf '%s' '--'; return; fi
    if [ "$s" -ge 3600 ]; then printf '%dh %02dm' $(( s / 3600 )) $(( (s % 3600) / 60 ))
    elif [ "$s" -ge 60 ]; then printf '%dm %02ds' $(( s / 60 )) $(( s % 60 ))
    else printf '%ds' "$s"; fi
}

tail_log() {  # last 200 KiB only: the log reaches hundreds of MB
    [ -f "$LOG" ] || return 0
    tail -c 200000 "$LOG" 2>/dev/null
}

sync_running() {
    # Three probes, most reliable first:
    #   tmux       - the sync is launched in a session, so if the session
    #                exists the sync is running
    #   pgrep      - procps may be missing, and repo runs as `python3 .../repo`
    #   log mtime  - repo writes progress continuously, so a log touched in the
    #                last few minutes means the sync is alive
    if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$SESSION" 2>/dev/null; then
        return 0
    fi
    if command -v pgrep >/dev/null 2>&1 && pgrep -f 'repo sync' >/dev/null 2>&1; then
        return 0
    fi
    if [ -f "$LOG" ]; then
        local mt now
        mt=$(stat -c %Y "$LOG" 2>/dev/null) || mt=0
        now=$(date +%s)
        if [ "${mt:-0}" -gt 0 ] && [ $(( now - mt )) -le 300 ]; then
            return 0
        fi
    fi
    return 1
}

phase() {
    local p=''
    p=$(tail_log | tr '\r' '\n' |
        grep -aoE 'Fetching projects?|Checking out|Garbage collecting|Receiving objects|Resolving deltas|synced into' |
        tail -1)
    if [ -z "$p" ]; then
        if sync_running; then p='syncing'; else p='idle'; fi
    fi
    printf '%s' "$p"
}

last_line() {
    tail_log | tr '\r' '\n' | grep -av '^[[:space:]]*$' | tail -1 | cut -c1-110
}

draw() {
    local pct=$1 bytes=$2 rate=$3 remain=$4 ph=$5
    local filled=$(( pct * WIDTH / 100 ))
    local empty=$(( WIDTH - filled ))
    local bar
    bar="$(repeat '#' "$filled")$(repeat '-' "$empty")"
    local r='--'
    [ "$rate" -gt 0 ] && r="$(human "$rate")/s"
    printf '[%s] %3d%%  %s / %d GiB  %s  ETA %s  %s' \
        "$bar" "$pct" "$(human "$bytes")" "$TARGET_GB" "$r" "$(eta "$remain")" "$ph"
}

if [ ! -d "$SRC_DIR" ]; then
    echo "no $SRC_DIR yet - start the sync first:"
    echo "  bash \"$(cd "$(dirname "$0")" && pwd)/sync-start.sh\""
    exit 1
fi

prev=0
prev_t=$(date +%s)
first=1
seeded=0
last_beat=0
last_printed=''

while :; do
    bytes=$(du -sb "$DU_PATH" 2>/dev/null | cut -f1)
    bytes=${bytes:-0}

    now=$(date +%s)
    dt=$(( now - prev_t ))
    [ "$dt" -lt 1 ] && dt=1

    rate=0
    if [ "$first" = 1 ]; then
        first=0                      # baseline sample: no rate yet
    else
        rate=$(( (bytes - prev) / dt ))
        [ "$rate" -lt 0 ] && rate=0
    fi

    pct=$(( bytes * 100 / TARGET ))
    [ "$pct" -gt 100 ] && pct=100

    # Joined mid-sync? Mark milestones already passed as seen, otherwise
    # 10/25/50 all fire at once on the first sample.
    if [ "$seeded" = 0 ]; then
        for m in $MILESTONES; do
            [ "$pct" -ge "$m" ] && seen[$m]=1
        done
        seeded=1
    fi

    remain=-1
    if [ "$rate" -gt 0 ] && [ "$bytes" -lt "$TARGET" ]; then
        remain=$(( (TARGET - bytes) / rate ))
    fi

    ph=$(phase)
    line=$(draw "$pct" "$bytes" "$rate" "$remain" "$ph")

    if [ "$ONCE" = 1 ]; then
        echo "$line"
        echo "  log: $(last_line)"
        exit 0
    fi

    if [ "$TTY" = 1 ]; then
        printf '\r%s\033[K' "$line"
    elif [ "$line" != "$last_printed" ]; then
        # Not a TTY: emit a normal line so it actually reaches the caller.
        printf '%s  %s\n' "$(date +%H:%M:%S)" "$line"
    fi
    last_printed="$line"

    for m in $MILESTONES; do
        if [ "$pct" -ge "$m" ] && [ -z "${seen[$m]:-}" ]; then
            seen[$m]=1
            printf '\n  >> milestone %3d%%   %s on disk   ETA %s\n' \
                "$m" "$(human "$bytes")" "$(eta "$remain")"
            [ "$TTY" = 1 ] && printf '%s' "$line"
        fi
    done

    if [ "$HEARTBEAT" -gt 0 ] && [ "$last_beat" -gt 0 ] && [ $(( now - last_beat )) -ge "$HEARTBEAT" ]; then
        printf '\n  >> %s   %d%%  %s/s  ETA %s\n' \
            "$(date +%H:%M:%S)" "$pct" "$(human "$rate")" "$(eta "$remain")"
        last_beat=$now
        [ "$TTY" = 1 ] && printf '%s' "$line"
    fi
    [ "$last_beat" = 0 ] && last_beat=$now

    if tail_log | grep -qa 'synced into'; then
        printf '\n  >> sync finished (%s on disk)\n' "$(human "$bytes")"
        exit 0
    fi

    prev=$bytes
    prev_t=$now
    sleep "$INTERVAL"
done
