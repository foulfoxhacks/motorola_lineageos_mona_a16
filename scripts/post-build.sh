#!/usr/bin/env bash
# post-build.sh - finish a build without anyone watching.
#
# Runs detached (start-build.sh starts it in tmux session "post"). Waits for the
# current build to end, then:
#   success : copies the flashable images + zip to $OUT_WIN, with SHA256SUMS.txt
#   always  : writes $OUT_WIN/BUILD_RESULT.txt (result, times, errors of this run)
#   always  : stops the Windows-side WSL keepalive (KEEPALIVE_STOP=0 to skip), so
#             the 10 GB WSL VM can shut down. A later `wsl` command restarts it.
#
#   bash scripts/post-build.sh [START_LINE]
#     START_LINE: build.log line from which the run to wait for starts
#                 (default: the last "Build started at" line).
set -uo pipefail

SRC="${SRC:-$HOME/lineage}"
BUILD_LOG="${BUILD_LOG:-$HOME/build.log}"
OUT_WIN="${OUT_WIN:-/mnt/c/mona_work/out}"
PRODUCT_OUT="${PRODUCT_OUT:-$SRC/out/target/product/mona}"
KEEPALIVE_STOP="${KEEPALIVE_STOP:-1}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

START="${1:-$(grep -n "Build started at" "$BUILD_LOG" 2>/dev/null | tail -1 | cut -d: -f1)}"
START="${START:-1}"
run_log() { tail -n +"$START" "$BUILD_LOG" 2>/dev/null; }

echo "post-build: waiting for BUILD-EXIT after line $START of $BUILD_LOG"
until run_log | grep -q "BUILD-EXIT="; do sleep 60; done

code="$(run_log | grep -o "BUILD-EXIT=[0-9]*" | tail -1 | cut -d= -f2)"
mkdir -p "$OUT_WIN"
result="$OUT_WIN/BUILD_RESULT.txt"
clean() { sed 's/\x1b\[[0-9;]*m//g' | tr '\r' '\n' | grep -v '^\s*$' | grep -v 'memory stall'; }

{
    echo "mona LineageOS build result"
    echo "==========================="
    run_log | grep -m1 "Build started at"
    run_log | grep "Build finished at" | tail -1
    echo "exit code: $code"
    echo
} > "$result"

if [ "$code" = "0" ]; then
    echo "RESULT: SUCCESS" >> "$result"
    copied=()
    for f in boot.img init_boot.img dtbo.img vendor_boot.img recovery.img vbmeta.img vbmeta_system.img; do
        [ -f "$PRODUCT_OUT/$f" ] && cp -f "$PRODUCT_OUT/$f" "$OUT_WIN/" && copied+=("$f")
    done
    zip="$(ls -t "$PRODUCT_OUT"/lineage-*.zip 2>/dev/null | head -1)"
    [ -n "$zip" ] && cp -f "$zip" "$OUT_WIN/" && copied+=("$(basename "$zip")")
    (cd "$OUT_WIN" && sha256sum "${copied[@]}" > SHA256SUMS.txt) 2>/dev/null
    {
        echo
        echo "Copied to C:\\mona_work\\out :"
        printf '  %s\n' "${copied[@]}"
        [ -f "$PRODUCT_OUT/init_boot.img" ] || echo "  (no init_boot.img built: install with STOCK init_boot, RUNBOOK step 3.2)"
        echo
        echo "Next: docs/RUNBOOK.md Phase 3 (install)."
    } >> "$result"
else
    {
        echo "RESULT: FAILED"
        echo
        echo "Errors in this run:"
        run_log | clean | grep -E "^error:|FAILED:|error: " | head -40
        echo
        echo "Last 40 log lines:"
        run_log | clean | grep -vE "^\s+-|^\s{4}\S" | tail -40
        echo
        echo "Also see: ~/lineage/out/error.log (WSL)"
    } >> "$result"
fi
echo "post-build: wrote $result"

if [ "$KEEPALIVE_STOP" = "1" ] && command -v powershell.exe >/dev/null 2>&1; then
    ps1_path="${PS_SCRIPTS:-$HERE}/wsl-keepalive.ps1"   # start-build.sh passes the repo's scripts dir
    [ -f "$ps1_path" ] || ps1_path="/mnt/c/mona_work/motorola_lineageos_mona_a16/scripts/wsl-keepalive.ps1"
    # A detached tmux session inherits the WSL_INTEROP socket of the terminal that
    # started it; once that terminal closes, Windows interop fails. Pick a live socket
    # (the keepalive's own session always has one).
    for s in $(ls -t /run/WSL/*_interop 2>/dev/null); do
        if WSL_INTEROP="$s" timeout 30 powershell.exe -NoProfile -Command "exit 0" >/dev/null 2>&1; then
            export WSL_INTEROP="$s"; break
        fi
    done
    echo "post-build: stopping WSL keepalive ($ps1_path)"
    timeout 60 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$ps1_path")" -Stop \
        || echo "post-build: could not reach Windows; stop it by hand: scripts\\wsl-keepalive.ps1 -Stop"
fi
