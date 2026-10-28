#!/bin/bash
# Test: Lifecycle Hook Engine (modules/hook.sh)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/modules/hook.sh"

TRACE=""
step1(){ TRACE="${TRACE}1($1)"; }
step2(){ TRACE="${TRACE}2($1)"; }
step_fail(){ echo "should not fail execution"; }

register_hook "test_event" "step1"
register_hook "test_event" "step2"
# Duplicate registration should be ignored
register_hook "test_event" "step1"

run_hook "test_event" "arg"

[ "$TRACE" = "1(arg)2(arg)" ] || { echo "FAIL: hook execution trace mismatch: $TRACE"; exit 1; }

# Empty / unregistered hook should do nothing and return 0
run_hook "non_existent_event"

echo "PASS: hook engine"
