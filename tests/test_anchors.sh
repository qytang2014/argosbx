#!/bin/bash
# Test: anchor registry check passes on current upstream.
# Usage: bash tests/test_anchors.sh  (from repo root)
# Runs `python3 build/build.py --check-anchors` (writes no files)
# and fails if any anchor reports STALE or the exit code is non-zero.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if ! out=$(python3 build/build.py --check-anchors 2>&1); then
  echo "FAIL: --check-anchors exit non-zero"
  echo "$out" | tail -5
  exit 1
fi
if echo "$out" | grep -q "STALE"; then
  echo "FAIL: stale anchors reported"
  echo "$out" | grep "STALE"
  exit 1
fi
if ! echo "$out" | grep -q "Anchor check: .* OK, 0 failed"; then
  echo "FAIL: no clean anchor summary"
  exit 1
fi
echo "PASS: anchors (registry check, no STALE)"
