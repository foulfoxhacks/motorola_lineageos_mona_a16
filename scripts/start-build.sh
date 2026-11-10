#!/usr/bin/env bash
# start-build.sh - Launch mka bacon in a tmux session
set -e

cd ~/lineage

# Kill any existing build session
tmux kill-session -t build 2>/dev/null || true

# Launch tmux with build command, logging to /tmp/build.log
tmux new-session -d -s build -x 220 -y 50 \
  'cd ~/lineage && source build/envsetup.sh && breakfast mona && export USE_CCACHE=1 && export CCACHE_EXEC=/usr/bin/ccache && ccache -M 50G && mka bacon -j8 2>&1 | tee /tmp/build.log; echo "EXIT_CODE=$?" >> /tmp/build.log'

sleep 2
echo "=== tmux sessions ==="
tmux list-sessions
echo ""
echo "Build launched. Monitor with:"
echo "  wsl -d lineage-build -u builder -- tail -f /tmp/build.log"
echo "  wsl -d lineage-build -u builder -- tmux attach -t build"
