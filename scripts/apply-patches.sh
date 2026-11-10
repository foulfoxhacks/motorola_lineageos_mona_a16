#!/usr/bin/env bash
# Apply this repo's patches/ to a synced lineage-24.0 tree.
#
#   bash scripts/apply-patches.sh               # SRC defaults to ~/lineage
#   SRC=/path/to/lineage bash scripts/apply-patches.sh
#
# Idempotent: already-applied patches are skipped. Stops on the first patch that
# neither applies nor is already applied. Never resets or discards local changes.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_ROOT="$REPO_DIR/patches"
SRC="${SRC:-$HOME/lineage}"

[ -d "$SRC/.repo" ] || { echo "ERROR: $SRC is not a repo checkout (no .repo/). Set SRC=..." >&2; exit 1; }

applied=0 skipped=0
while IFS= read -r -d '' patch; do
    rel="${patch#"$PATCH_ROOT"/}"
    project="$(dirname "$rel")"
    dir="$SRC/$project"
    [ -d "$dir" ] || { echo "ERROR: project $project not found under $SRC" >&2; exit 1; }

    if git -C "$dir" apply --check --reverse "$patch" >/dev/null 2>&1; then
        echo "skip   $rel (already applied)"
        skipped=$((skipped + 1))
    elif git -C "$dir" apply --check "$patch" >/dev/null 2>&1; then
        git -C "$dir" apply "$patch"
        echo "apply  $rel"
        applied=$((applied + 1))
    else
        echo "ERROR: $rel does not apply to $project (HEAD $(git -C "$dir" rev-parse --short HEAD))." >&2
        echo "       Upstream probably moved; see patches/README.md for the base commit." >&2
        git -C "$dir" apply --check -v "$patch" || true
        exit 1
    fi
done < <(find "$PATCH_ROOT" -name '*.patch' -print0 | sort -z)

echo "done: $applied applied, $skipped already present"
