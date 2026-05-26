#!/bin/bash
set -euo pipefail

echo "=== Building Zyquo Release Binary ==="
echo ""

# Build universal binary (arm64 + x86_64)
echo "Building universal binary..."
swift build -c release --arch arm64 --arch x86_64

BINARY=".build/apple/Products/Release/zyquo"

if [ ! -f "$BINARY" ]; then
    echo "Universal binary not found at $BINARY"
    echo "Falling back to single-arch release build..."
    swift build -c release
    BINARY=".build/release/zyquo"
fi

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Release binary not found"
    exit 1
fi

# Strip debug symbols
echo "Stripping debug symbols..."
strip "$BINARY" 2>/dev/null || true

# Show binary info
echo ""
echo "=== Binary Info ==="
ls -lh "$BINARY"
file "$BINARY"

# Show size
SIZE=$(ls -l "$BINARY" | awk '{print $5}')
SIZE_MB=$(echo "scale=1; $SIZE / 1048576" | bc)
echo "Size: ${SIZE_MB} MB"

# Check size budget (< 25 MB)
SIZE_LIMIT=$((25 * 1048576))
if [ "$SIZE" -gt "$SIZE_LIMIT" ]; then
    echo "WARNING: Binary exceeds 25 MB size budget"
else
    echo "Size budget: OK (< 25 MB)"
fi

echo ""
echo "=== Build Complete ==="
echo "Binary: $BINARY"
