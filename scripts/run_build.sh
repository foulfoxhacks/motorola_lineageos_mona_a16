#!/bin/bash

SRC="${SRC:-$HOME/lineage}"
BUILD_LOG="${BUILD_LOG:-$HOME/build.log}"
exec > >(tee -a "${BUILD_LOG}") 2>&1

echo "========================================="
echo "Build started at: $(date)"
echo "Host: $(hostname)"
echo "Directory: $(pwd)"
echo "========================================="

cd "$SRC" || { echo "no source tree at $SRC (set SRC=...)"; exit 1; }

# Ensure temp directory exists
mkdir -p out/soong/.temp

# A build killed while soong was writing its ninja file leaves a 0-byte
# out/soong/build.<product>.ninja. soong_ui then panics in dumpvars
# ("Could not open out/soong/build.<product>.0.ninja"), lunch fails, and breakfast
# falls back to roomservice and a repo sync. Remove the stub so analysis re-runs cleanly.
for f in out/soong/build.*.ninja; do
    [ -e "$f" ] && [ ! -s "$f" ] && { echo "removing truncated $f (interrupted analysis)"; rm -f "$f"; }
done

# Memory/concurrency for a ~10 GB WSL. soong_build alone peaks ~9.5 GB; raise -j once WSL has >= 16 GB.
export _JAVA_OPTIONS="-Xmx4g"
# Do NOT set NINJA_ARGS="-j4": lineage-24.0 executes with siso, whose Go flag parser
# rejects "-j4" ("flag provided but not defined: -j4") and kills the build right after
# Kati. The job count reaches siso as --local_jobs via `mka bacon -j4` below.
unset NINJA_ARGS

# Source LineageOS build environment
source build/envsetup.sh

# Run breakfast to target mona
breakfast mona

# Configure ccache
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
ccache -M 50G

echo "========================================="
echo "Starting mka bacon -j4 (memory-optimized)..."
echo "========================================="

mka bacon -j4
BUILD_STATUS=$?

echo "========================================="
echo "Build finished at: $(date) with exit code: ${BUILD_STATUS}"
echo "========================================="
exit ${BUILD_STATUS}
