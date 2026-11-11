#!/usr/bin/env bash
# build-status.sh - one-line machine-readable status of the current/last build.
# Prints:  STATE|DETAIL
#   STATE: running-soong | running-kati | running-compile | running | done-ok | done-fail | idle
BUILD_LOG="${BUILD_LOG:-$HOME/build.log}"

last="$(grep -n "Build started at" "$BUILD_LOG" 2>/dev/null | tail -1 | cut -d: -f1)"
if [ -z "$last" ]; then echo "idle|no build has run yet"; exit 0; fi
run() { tail -n +"$last" "$BUILD_LOG"; }
started="$(run | grep -m1 -o 'Build started at: .*' | cut -d' ' -f4-)"

code="$(run | grep -o 'BUILD-EXIT=[0-9]*' | tail -1 | cut -d= -f2)"
if [ -n "$code" ]; then
    [ "$code" = 0 ] && echo "done-ok|started $started" || echo "done-fail|exit $code, started $started"
    exit 0
fi

if ! tmux has-session -t build 2>/dev/null; then echo "idle|build session not running (last run started $started)"; exit 0; fi

if pgrep -x soong_build >/dev/null; then
    echo "running-soong|soong analysis, $(ps -o etime= -C soong_build | head -1 | tr -d ' ') elapsed (~3.5 h total)"
elif pgrep -x ckati >/dev/null; then
    echo "running-kati|Kati (product makefiles)"
else
    # current run only; compile steps number in the tens of thousands (Kati's own
    # "[ 97% 40/41]" lines must not count)
    prog="$(run | tail -c 20000 | tr '\r' '\n' | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '^\[ *[0-9]+% [0-9]+/[0-9]{4,}\]' | tail -1)"
    if [ -n "$prog" ]; then echo "running-compile|compile $prog"
    elif run | grep -q "Running product configuration"; then echo "running|product config / waiting for soong (started $started)"
    else echo "running|breakfast / setup (started $started)"; fi
fi
