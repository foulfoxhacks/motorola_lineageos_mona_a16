#!/usr/bin/env bash
#
# extract-files.py calls the prebuilt LLVM binutils directly:
#
#   prebuilts/clang/host/linux-x86/llvm-binutils-stable/llvm-objdump
#
# If that file is absent (partial sync, or the prebuilt repo layout differs),
# extraction dies with:
#
#   ValueError: Failed to find executable path for:
#   .../llvm-binutils-stable/llvm-objdump
#
# because extract_utils passes an absolute path and only falls back to
# shutil.which() for bare names. This script puts a working llvm-objdump at
# that exact path, preferring the prebuilt clang already in the tree and
# falling back to the distro LLVM.
set -euo pipefail

SRC="${SRC:-$HOME/lineage}"
PRE="$SRC/prebuilts/clang/host/linux-x86"
DEST="$PRE/llvm-binutils-stable"

die() { echo "ERROR: $*" >&2; exit 1; }

if [ -x "$DEST/llvm-objdump" ]; then
    echo "==> ok: $DEST/llvm-objdump"
    "$DEST/llvm-objdump" --version | head -1
    exit 0
fi

echo "==> missing: $DEST/llvm-objdump"

cand=''
# 1. A prebuilt clang in the tree (clang-rXXXXXX/bin/llvm-objdump)
for f in "$PRE"/*/bin/llvm-objdump; do
    [ -x "$f" ] || continue
    cand="$f"
    break
done

# 2. The distro LLVM
if [ -z "$cand" ]; then
    if ! command -v llvm-objdump >/dev/null 2>&1; then
        echo "    no prebuilt clang and no system llvm-objdump; installing llvm"
        sudo -n apt-get install -y llvm || die "could not install llvm"
    fi
    cand=$(command -v llvm-objdump || true)
    if [ -z "$cand" ]; then
        cand=$(ls -1 /usr/bin/llvm-objdump-* 2>/dev/null | sort -V | tail -1 || true)
    fi
fi

[ -n "$cand" ] || die "no llvm-objdump anywhere; run: sudo apt install -y llvm"
echo "    using $cand"

mkdir -p "$DEST"
ln -sf "$cand" "$DEST/llvm-objdump"

# The same directory is used for the other binutils in some fixups.
d=$(dirname "$cand")
for t in llvm-strip llvm-objcopy llvm-readelf llvm-ar llvm-nm; do
    [ -x "$d/$t" ] && ln -sf "$d/$t" "$DEST/$t"
done

"$DEST/llvm-objdump" --version | head -1
echo "==> ok"
