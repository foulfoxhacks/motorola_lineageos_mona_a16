#!/usr/bin/env bash
# fix-all-prebuilts.sh
# Scans ALL git repos under ~/lineage for broken git state (staged deletions from interrupted sync)
# and resets them. Run this BEFORE attempting mka bacon.
#
# DRY RUN by default: it only lists dirty repos. Pass --apply to actually run
# `git reset --hard` in them. That DISCARDS local edits, including any hardening patches
# you applied to frameworks/base, art, libcore or system. Re-run scripts/apply-patches.sh afterwards.
set -euo pipefail

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

reset_repo() {
  if [ "$APPLY" -eq 1 ]; then
    rm -f "$1/.git/index.lock"
    git -C "$1" reset --hard HEAD 2>&1 | tail -1
  else
    echo "    (dry run - would: git -C $1 reset --hard HEAD)"
  fi
}

LINEAGE_ROOT="${SRC:-${HOME}/lineage}"
FIXED=0
CLEAN=0
ERRORS=0

echo "=== Prebuilts Full Health Check & Auto-Fix ==="
echo "Root: $LINEAGE_ROOT"
echo ""

# First fix the three known-broken repos explicitly
KNOWN_BROKEN=(
  "prebuilts/clang/host/linux-x86"
  "prebuilts/rust-toolchain/linux-x86"
  "prebuilts/sdk"
)

echo "--- Phase 1: Fix known-broken repos ---"
for rel in "${KNOWN_BROKEN[@]}"; do
  path="$LINEAGE_ROOT/$rel"
  if [ ! -d "$path/.git" ]; then
    echo "  SKIP (no .git): $rel"
    continue
  fi
  dirty=$(git -C "$path" status -s 2>/dev/null | wc -l)
  if [ "$dirty" -gt 0 ]; then
    echo "  FIXING ($dirty dirty): $rel"
    reset_repo "$path"
    FIXED=$((FIXED + 1))
  else
    echo "  CLEAN: $rel"
    CLEAN=$((CLEAN + 1))
  fi
done

echo ""
echo "--- Phase 2: Scan ALL repos under prebuilts/ external/ frameworks/ libcore/ system/ art/ ---"

SCAN_ROOTS=(
  "$LINEAGE_ROOT/prebuilts"
  "$LINEAGE_ROOT/external/conscrypt"
  "$LINEAGE_ROOT/libcore"
  "$LINEAGE_ROOT/frameworks/base"
  "$LINEAGE_ROOT/art"
)

while IFS= read -r gitdir; do
  repo=$(dirname "$gitdir")
  rel="${repo#$LINEAGE_ROOT/}"
  
  # Skip already processed known repos
  skip=0
  for k in "${KNOWN_BROKEN[@]}"; do
    if [ "$rel" = "$k" ]; then skip=1; break; fi
  done
  [ $skip -eq 1 ] && continue

  dirty=$(git -C "$repo" status -s 2>/dev/null | wc -l)
  if [ "$dirty" -gt 0 ]; then
    echo "  DIRTY ($dirty lines): $rel  --> fixing..."
    reset_repo "$repo"
    FIXED=$((FIXED + 1))
  else
    CLEAN=$((CLEAN + 1))
  fi
done < <(find "${SCAN_ROOTS[@]}" -maxdepth 5 -name ".git" -type d 2>/dev/null | sort)

echo ""
echo "=== DONE ==="
echo "  Fixed: $FIXED repos"
echo "  Clean: $CLEAN repos"
echo "  Errors: $ERRORS"
echo ""
if [ "$APPLY" -eq 1 ]; then
  echo "Safe to run: mka bacon"
else
  echo "Dry run only. Re-run with --apply to reset the repos listed above."
fi
