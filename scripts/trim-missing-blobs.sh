#!/usr/bin/env bash
#
# Trim 'file not found' entries out of the proprietary-files lists and re-run
# blob extraction until it completes cleanly and writes the makefiles.
#
# Why: the Lineage 24.0 mona/sm6475-common trees pin blobs from firmware build
# W1UANS36H.29-25-2-6, which is not our stock build (W1VAS36.62-22-16-1-18).
# Verified against the live phone: the "missing" files do not exist in stock
# vendor either -- they are tree artifacts, not extraction faults.
#
# extract-files.py REFUSES to write mona-vendor.mk / BoardConfigVendor.mk while
# any listed file is missing, so the only way forward is to prune those lines.
# The original lists are backed up as *.orig (only on first trim). After a clean
# run extract-utils rewrites the lists itself, updating pinned hashes to our
# blobs.
#
#   bash /mnt/c/mona_work/motorola_lineageos_mona_a16/scripts/trim-missing-blobs.sh
#
set -euo pipefail

SRC="${SRC:-$HOME/lineage}"
LOG="${LOG:-$HOME/work/extract.log}"
MONA="$SRC/device/motorola/mona"
COMMON="$SRC/device/motorola/sm6475-common"
MAX_ITER="${MAX_ITER:-3}"

LISTS=(
    "$MONA/proprietary-firmware.txt"
    "$MONA/proprietary-files-carriersettings.txt"
    "$MONA/proprietary-files.txt"
    "$COMMON/proprietary-files.txt"
)

die() { echo "ERROR: $*" >&2; exit 1; }

[ -f "$LOG" ] || die "no log at $LOG — run extract-blobs.sh first"

count_missing() {
    # log lines are wrapped in ANSI color codes; strip them first or the
    # end-of-line anchor never matches
    sed -e 's/\x1b\[[0-9;]*m//g' "$LOG" \
        | grep -E ': file not found$' \
        | sed 's/: file not found$//' \
        | sort -u || true
}

iter=0
MISSING_ACCUM="$HOME/work/missing-trimmed.txt"
: > "$MISSING_ACCUM"
while :; do
    iter=$((iter + 1))
    mkdir -p "$(dirname "$LOG")"
    count_missing > "$HOME/work/missing.txt"

    total=$(wc -l < "$HOME/work/missing.txt" | tr -d ' ')

    if [ "$total" -eq 0 ]; then
        echo "==> iteration $iter: no missing entries left"
        break
    fi
    if [ "$iter" -gt "$MAX_ITER" ]; then
        echo "==> still $total entries missing after $MAX_ITER trims:" >&2
        head -20 "$HOME/work/missing.txt" >&2
        die "see $HOME/work/missing.txt"
    fi

    echo "==> iteration $iter: $total entries missing → trimming"

    for list in "${LISTS[@]}"; do
        [ -f "$list" ] || continue
        [ -f "$list.orig" ] || cp "$list" "$list.orig"
    done

    python3 - "$HOME/work/missing.txt" "$MISSING_ACCUM" "${LISTS[@]}" <<'PY'
import sys, pathlib

missing = {l.strip() for l in open(sys.argv[1]) if l.strip()}
if not missing:
    sys.exit(0)

# running record of everything trimmed this session
accum = pathlib.Path(sys.argv[2])
already = {l.strip() for l in accum.read_text().splitlines() if l.strip()}
accum.write_text('\n'.join(sorted(already | missing)) + '\n')

def dst_of(s: str) -> str:
    left = s.split(';', 1)[0].split('|', 1)[0].strip()
    if left.startswith('-'):          # drop the leading flag
        left = left[1:]
    return left.rsplit(':', 1)[1].strip() if ':' in left else left

for listpath in sys.argv[3:]:
    p = pathlib.Path(listpath)
    if not p.is_file():
        continue
    kept, removed = [], 0
    for line in p.read_text().splitlines():
        s = line.strip()
        if not s or s.startswith('#'):
            kept.append(line)
            continue
        if dst_of(s) in missing:
            removed += 1
            continue
        kept.append(line)
    if removed:
        p.write_text('\n'.join(kept) + '\n')
        print(f"    {p.name}: removed {removed}")
PY

    echo "==> re-extracting (mirror + extract, ~15 min)"
    bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/extract-blobs.sh"
    # loop re-reads the fresh $LOG written by extract-blobs.sh
done

echo
echo "==> makefiles (must all exist):"
ok=1
for f in \
    "$SRC/vendor/motorola/mona/mona-vendor.mk" \
    "$SRC/vendor/motorola/mona/BoardConfigVendor.mk" \
    "$SRC/vendor/motorola/sm6475-common/sm6475-common-vendor.mk" \
    "$SRC/vendor/motorola/sm6475-common/BoardConfigCommonVendor.mk"; do
    if [ -f "$f" ]; then echo "    ok  ${f#$SRC/}"; else echo "    MISSING  ${f#$SRC/}"; ok=0; fi
done
[ "$ok" -eq 1 ] || die "makefiles still missing — paste the output above"

echo
if [ -s "$MISSING_ACCUM" ]; then
    echo "==> trimmed this session: $(wc -l < "$MISSING_ACCUM" | tr -d ' ') entries, saved at $MISSING_ACCUM"
fi
echo "Next:"
echo "  cd $SRC && source build/envsetup.sh && lunch lineage_mona-userdebug && get_build_var TARGET_PRODUCT"
