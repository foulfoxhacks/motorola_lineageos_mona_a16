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

# Memory/concurrency for a ~10 GB WSL. soong_build alone peaks ~9.5 GB; raise -j once WSL has >= 16 GB.
export _JAVA_OPTIONS="-Xmx4g"
export NINJA_ARGS="-j4"

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
