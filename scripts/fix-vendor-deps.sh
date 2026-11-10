#!/usr/bin/env bash
#
# fix-vendor-deps.sh
# Iteratively resolve all missing vendor shared_libs dependencies.
#
# Pattern:
#   1. Run soong_build to generate the ninja file
#   2. Capture "depends on undefined module" errors
#   3. For each missing module, find the .so in the firmware dump
#   4. Add it to proprietary-files.txt
#   5. Re-run extract-files.py
#   6. Repeat until soong_build passes or we can't find a blob
#
set -uo pipefail

SRC="${HOME}/lineage"
FW="${HOME}/work/fw"
COMMON_LIST="${SRC}/device/motorola/sm6475-common/proprietary-files.txt"
MONA_DEVICE="${SRC}/device/motorola/mona"
MAX_ITER=10
LOG_DIR="${HOME}/work/dep-fix"
mkdir -p "$LOG_DIR"

echo "=== fix-vendor-deps.sh ==="
echo "Source: $SRC"
echo "Firmware: $FW"
echo ""

# Ensure envsetup is loaded
cd "$SRC"
source build/envsetup.sh >/dev/null 2>&1
breakfast mona >/dev/null 2>&1

for iter in $(seq 1 $MAX_ITER); do
    echo "=== Iteration $iter: running soong_build ==="
    
    # Run soong_build and capture stderr
    SOONG_LOG="$LOG_DIR/soong_iter${iter}.log"
    cd "$SRC"
    
    # Use m to trigger soong, capture output, allow failure
    m bacon -j8 2>&1 | head -n 500 > "$SOONG_LOG" || true
    
    # Extract undefined module names from the error output
    MISSING_MODULES=$(grep 'depends on undefined module' "$SOONG_LOG" \
        | sed 's/.*depends on undefined module "\([^"]*\)".*/\1/' \
        | sort -u)
    
    if [ -z "$MISSING_MODULES" ]; then
        echo "=== No more undefined modules! Soong may have passed or hit a different error. ==="
        echo "Check: $SOONG_LOG"
        # Check if it actually succeeded
        if grep -q 'Build Failure' "$SOONG_LOG"; then
            echo "Build failed with a NON-dependency error. Check log."
            tail -30 "$SOONG_LOG"
        else
            echo "BUILD PASSED SOONG! Continuing compilation..."
        fi
        break
    fi
    
    echo "Found $(echo "$MISSING_MODULES" | wc -l) undefined modules:"
    echo "$MISSING_MODULES" | sed 's/^/  /'
    
    # For each missing module, try to find a matching .so in the firmware
    ADDED=0
    NOT_FOUND=""
    for mod in $MISSING_MODULES; do
        # Convert module name to .so filename
        SO_NAME="${mod}.so"
        
        # Search in firmware dump
        FOUND_PATH=$(find "$FW" -name "$SO_NAME" 2>/dev/null | head -1)
        
        if [ -n "$FOUND_PATH" ]; then
            # Get relative path from fw root (e.g. vendor/lib64/foo.so)
            REL_PATH="${FOUND_PATH#$FW/}"
            
            # Check if already in proprietary-files.txt
            if ! grep -qF "$REL_PATH" "$COMMON_LIST" 2>/dev/null; then
                echo "  + $REL_PATH"
                echo "$REL_PATH" >> "$COMMON_LIST"
                ADDED=$((ADDED + 1))
            else
                echo "  ~ $REL_PATH (already listed)"
            fi
        else
            echo "  ! $mod -- NOT FOUND in firmware"
            NOT_FOUND="${NOT_FOUND}${mod}\n"
        fi
    done
    
    echo ""
    echo "Added $ADDED new entries to proprietary-files.txt"
    
    if [ $ADDED -eq 0 ]; then
        echo "=== No new blobs to add. Remaining undefined modules cannot be resolved from firmware. ==="
        if [ -n "$NOT_FOUND" ]; then
            echo "Modules not found in firmware (will need stub or removal):"
            echo -e "$NOT_FOUND" | sed 's/^/  /'
        fi
        break
    fi
    
    # Re-run extract-files.py to copy the new blobs and regenerate Android.bp
    echo "=== Re-extracting blobs ==="
    cd "$MONA_DEVICE"
    ./extract-files.py "$FW" > "$LOG_DIR/extract_iter${iter}.log" 2>&1
    EXTRACT_RC=$?
    if [ $EXTRACT_RC -ne 0 ]; then
        echo "extract-files.py failed (exit $EXTRACT_RC)"
        tail -20 "$LOG_DIR/extract_iter${iter}.log"
    else
        echo "Extraction complete."
    fi
    
    # Clear soong cache so it picks up new Android.bp
    rm -rf "$SRC/out/soong/build.lineage_mona.ninja" 2>/dev/null
    rm -rf "$SRC/out/soong/build.lineage_mona.ninja.glob_results" 2>/dev/null
    
    echo ""
done

echo ""
echo "=== fix-vendor-deps.sh complete ==="
echo "Logs in: $LOG_DIR/"
ls -lh "$LOG_DIR/"
