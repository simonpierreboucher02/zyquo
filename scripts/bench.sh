#!/bin/bash
set -euo pipefail

BINARY=".build/release/zyquo"

if [ ! -f "$BINARY" ]; then
    echo "Release binary not found. Building..."
    swift build -c release
fi

echo "=== Zyquo Performance Benchmarks ==="
echo ""

echo "--- Cold Start: --help ---"
time "$BINARY" --help > /dev/null 2>&1
echo ""

echo "--- Cold Start: version ---"
time "$BINARY" version > /dev/null 2>&1
echo ""

echo "--- Cold Start: doctor ---"
time "$BINARY" doctor > /dev/null 2>&1
echo ""

echo "--- Cold Start: status ---"
time "$BINARY" status > /dev/null 2>&1
echo ""

# Multiple runs for averaging
echo "--- 10x --help (averaged) ---"
START=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
for i in $(seq 1 10); do
    "$BINARY" --help > /dev/null 2>&1
done
END=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
if [ "$START" != "" ] && [ "$END" != "" ]; then
    ELAPSED=$(( (END - START) / 10000000 ))
    echo "Average: ${ELAPSED}ms per invocation"
fi

echo ""
echo "--- Memory at idle (RSS) ---"
"$BINARY" --help > /dev/null 2>&1 &
PID=$!
sleep 0.1
if ps -p $PID > /dev/null 2>&1; then
    RSS=$(ps -o rss= -p $PID 2>/dev/null || echo "unknown")
    echo "RSS: ${RSS} KB"
    kill $PID 2>/dev/null || true
else
    echo "Process exited before measurement (fast startup)"
fi

echo ""
echo "=== Benchmarks Complete ==="
