#!/usr/bin/env bash
set -uo pipefail

echo "==> Scanning prebuilts for uncommitted / broken git states..."
find /home/builder/lineage/prebuilts/ -name ".git" 2>/dev/null | while read -r gitdir; do
    repo_dir="$(dirname "$gitdir")"
    st=$(git -C "$repo_dir" status -s 2>/dev/null | head -5 || true)
    if [ -n "$st" ]; then
        echo "DIRTY: $repo_dir"
        echo "$st"
        echo "---"
    fi
done
echo "==> Scan complete."
