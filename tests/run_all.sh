#!/bin/bash
# Run everything: build first, then all tests. Fails fast on first failure.
# Usage: bash tests/run_all.sh  (from repo root)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
bash tests/test_build.sh
bash tests/test_egress.sh
bash tests/test_cert.sh
python3 tests/test_index.py
echo "ALL TESTS PASS"
