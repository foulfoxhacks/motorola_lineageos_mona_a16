#!/usr/bin/env bash
# Apply this repo's patches/ to a synced lineage-24.0 tree.
#
#   bash scripts/apply-patches.sh               # SRC defaults to ~/lineage
#   SRC=/path/to/lineage bash scripts/apply-patches.sh
#
# Patches live in patches/<project path>/NNNN-*.patch and form an ordered series
# per project. For each project the script works out how many patches of the
# series are already applied: it rebuilds the touched files from upstream HEAD
# plus the first k patches and compares them with the working tree. Then it
# applies only the remaining ones.
# Idempotent. Stops if a project's files match no prefix of its series (local
# edits or upstream moved). Never resets or discards anything.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_ROOT="$REPO_DIR/patches"
SRC="${SRC:-$HOME/lineage}"

[ -d "$SRC/.repo" ] || { echo "ERROR: $SRC is not a repo checkout (no .repo/). Set SRC=..." >&2; exit 1; }
[ -d "$PATCH_ROOT" ] || { echo "ERROR: no patches/ next to this script ($PATCH_ROOT)" >&2; exit 1; }

# files touched by a set of patches (both sides of every "diff --git a/X b/Y")
touched_paths() {
    sed -n 's#^diff --git a/\(.*\) b/\(.*\)$#\1\n\2#p' "$@" | sort -u
}

# 0 if every touched path in $1 (expected tree) matches the working tree $2
same_files() {
    local exp=$1 dir=$2 f
    while IFS= read -r f; do
        if [ -e "$exp/$f" ] || [ -e "$dir/$f" ]; then
            cmp -s "$exp/$f" "$dir/$f" || return 1
        fi
    done < "$exp/.touched"
}

total_applied=0 total_skipped=0
mapfile -t projects < <(find "$PATCH_ROOT" -name '*.patch' -printf '%h\n' | sort -u)

for pdir in "${projects[@]}"; do
    project="${pdir#"$PATCH_ROOT"/}"
    dir="$SRC/$project"
    [ -d "$dir" ] || { echo "ERROR: project $project not found under $SRC" >&2; exit 1; }
    mapfile -t series < <(find "$pdir" -maxdepth 1 -name '*.patch' | sort)
    n=${#series[@]}

    tmp=$(mktemp -d)
    touched_paths "${series[@]}" > "$tmp/.touched"
    # upstream HEAD copy of just the touched files that exist there
    mapfile -t in_head < <(git -C "$dir" ls-tree -r --name-only HEAD -- $(cat "$tmp/.touched"))
    if [ ${#in_head[@]} -gt 0 ]; then
        git -C "$dir" archive HEAD -- "${in_head[@]}" | tar -x -C "$tmp"
    fi

    # find the longest applied prefix: state after k patches == working tree
    applied=-1
    same_files "$tmp" "$dir" && applied=0
    for ((k = 1; k <= n; k++)); do
        (cd "$tmp" && git apply "${series[k-1]}") || { echo "ERROR: ${series[k-1]#"$PATCH_ROOT"/} does not apply on top of upstream HEAD $(git -C "$dir" rev-parse --short HEAD) + earlier patches" >&2; rm -rf "$tmp"; exit 1; }
        same_files "$tmp" "$dir" && applied=$k
    done
    rm -rf "$tmp"

    if [ "$applied" -lt 0 ]; then
        echo "ERROR: $project has local changes that match no prefix of its patch series." >&2
        echo "       Inspect: git -C $dir status; git -C $dir diff" >&2
        exit 1
    fi

    for ((k = 0; k < n; k++)); do
        rel="${series[k]#"$PATCH_ROOT"/}"
        if [ "$k" -lt "$applied" ]; then
            echo "skip   $rel (already applied)"
            total_skipped=$((total_skipped + 1))
        else
            git -C "$dir" apply "${series[k]}"
            echo "apply  $rel"
            total_applied=$((total_applied + 1))
        fi
    done
done

echo "done: $total_applied applied, $total_skipped already present"
