#!/bin/bash
# Anchor budget (ratchet): the total anchor count must not grow.
# Step 1 (2026-11-21) landed at 242 runtime anchors. Step 3 migrated
# the subcommand dispatch chain (7 anchors) to one `run_hook dispatch`
# call, landing at 236. auto-sni (2026-11-21) adds 2 anchors, landing
# at 238: the auto-sni.sh module insertion (A) and the one call site
# inside ins() (A) — the call must run at a specific point in ins()
# (after vlpt_on, before installxray/installsb) and ins() has no hook
# point there, so it cannot be a hook. When a later step migrates more anchors to
# hooks, update BUDGET to the new total. After that, a new anchor must
# first be justified as un-hookable (see build/README.md and
# build/ANCHORS.md); bumping BUDGET without converting to a hook needs
# a reason in the commit message.
BUDGET=238

cd "$(dirname "$0")/.." || exit 1
out=$(python3 build/build.py --check-anchors 2>&1) || {
    echo "FAIL: --check-anchors itself failed (stale anchors or inline BUILD FAIL)"
    echo "$out" | tail -5
    exit 1
}
total=$(echo "$out" | grep -oE 'Anchor check: [0-9]+/[0-9]+ OK' | grep -oE '[0-9]+/[0-9]+' | cut -d/ -f1)
if [ -z "$total" ]; then
    echo "FAIL: could not parse anchor total from --check-anchors output"
    exit 1
fi
if [ "$total" -gt "$BUDGET" ]; then
    echo "FAIL: anchor count $total exceeds budget $BUDGET -- convert to a hook first (see build/README.md)"
    exit 1
fi
echo "PASS: anchor count $total within budget $BUDGET"
