#!/usr/bin/env python3
"""Build the distributable argosbx.sh from upstream + private modules.

Usage (from repo root):
    python3 build/build.py [--check-anchors]
Output: argosbx.sh, index.html and container/nodejs/start.sh (generated, do NOT edit by hand)

Layout (step 1 refactor): the build is now the buildlib package.
build/build.py is a thin entry; build/buildlib/compose.py runs the
pipeline; build/buildlib/patches/ holds one apply(t, ctx) per area,
called in the original order; build/buildlib/util.py holds the anchor
registry (see UPSTREAM_VERIFIED) and the patch primitives.

Rules:
- upstream/argosbx.sh is pristine upstream, never edited by hand.
  To sync upstream: replace that file, rerun this script, and fix only
  the anchors it reports as missing.
- modules/*.sh are private features, edited here, never in argosbx.sh.
- Every patch is an anchor replacement with an expected count.
  If an anchor is missing (upstream changed that line), the build
  FAILS with the anchor name, instead of silently producing a broken
  script. That is the whole point: upstream drift is reported, not
  silently merged.
- `python3 build/build.py --check-anchors` verifies all anchors
  against current upstream and prints a table instead of building;
  exit 0 when all OK, 1 when any anchor is STALE.
- The generated file is byte-identical to the previous hand-edited
  private version except for the GENERATED header line after the
  shebang. Verify with: diff <(tail -n +3 argosbx.sh) <previous-private>
  (line 1 = shebang, line 2 = generated header).
"""
import argparse
import sys

from buildlib.compose import build_all


def main():
    parser = argparse.ArgumentParser(
        description="Build argosbx.sh from upstream + private modules.")
    parser.add_argument("--check-anchors", action="store_true",
                        help="Verify all anchors against current upstream, "
                             "print a table, and write no files.")
    args = parser.parse_args()
    sys.exit(build_all(check=args.check_anchors))


if __name__ == "__main__":
    main()
