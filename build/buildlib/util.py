"""Shared build helpers: paths, file reads, anchor registry, patch primitives.

ROOT is the repository root (this file lives at build/buildlib/util.py).
Every replace()/insert_after() call registers its anchor in REGISTRY so
`python3 build/build.py --check-anchors` can report upstream drift
without editing any output file. In check mode a failed anchor is
recorded as STALE and the text is left unchanged instead of exiting.
Chain limitation: an anchor whose pattern is produced by an earlier
replace will also report STALE if that earlier replace failed, so
stale entries are listed in execution order and a later STALE does
not by itself prove its own pattern is wrong.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent

# Upstream HEAD (short SHA) these anchors were last verified against.
# Bump on every upstream sync.
UPSTREAM_VERIFIED = "d029aa4"

# Set by compose before each patch module runs; replace()/insert_after()
# record it as the anchor's area. "index"/"container" for those builders.
CURRENT_AREA = "main"
# When True, replace()/insert_after() record failures instead of exiting.
CHECK_MODE = False
# When False, builders skip writing output files (check mode).
WRITE = True
# Registry entries: {"name", "area", "expected", "found", "ok"}.
REGISTRY = []


def read(p):
    return (ROOT / p).read_text()


def build_camouflage():
    """Build deploy_camouflage_blog() with embedded templates.
    Reads modules/camouflage-blog.sh and modules/camouflage/*,
    replaces the CAMOUFLAGE_TEMPLATES block with _camouflage_write calls."""
    import os
    mod = read("modules/camouflage-blog.sh")
    tpl_dir = ROOT / "modules" / "camouflage"
    blocks = []
    for root, dirs, files in os.walk(tpl_dir):
        for f in sorted(files):
            fpath = os.path.join(root, f)
            rel = os.path.relpath(fpath, tpl_dir)
            content = pathlib.Path(fpath).read_text()
            if "CAMOUFLAGE_TPL_EOF" in content:
                print(f"BUILD FAIL: delimiter clash in {fpath}", file=sys.stderr)
                sys.exit(1)
            # Ensure content ends with newline for clean heredoc
            if not content.endswith("\n"):
                content += "\n"
            blocks.append('_camouflage_write "$webroot/' + rel + '" << \'CAMOUFLAGE_TPL_EOF\'\n' + content + 'CAMOUFLAGE_TPL_EOF')
    tpl_code = "\n".join(blocks)
    start = "# CAMOUFLAGE_TEMPLATES_START"
    end = "# CAMOUFLAGE_TEMPLATES_END"
    si = mod.find(start)
    ei = mod.find(end)
    if si < 0 or ei < 0:
        print("BUILD FAIL: camouflage template markers not found", file=sys.stderr)
        sys.exit(1)
    mod = mod[:si] + tpl_code + mod[ei + len(end):]
    return mod


def _record(name, expected, found):
    """Record one anchor check. expected None or ">=1" means 'at least one'."""
    if expected is None or expected == ">=1":
        ok = found > 0
        exp = ">=1"
    else:
        ok = found == expected
        exp = expected
    REGISTRY.append({"name": name, "area": CURRENT_AREA,
                     "expected": exp, "found": found, "ok": ok})
    return ok


def replace(t, old, new, name, expected=None):
    n = t.count(old)
    ok = _record(name, expected, n)
    if CHECK_MODE:
        if not ok:
            return t
        return t.replace(old, new)
    if expected is not None and n != expected:
        print(f"BUILD FAIL: {name}: expected {expected} occurrence(s), found {n}", file=sys.stderr)
        sys.exit(1)
    if n == 0:
        print(f"BUILD FAIL: anchor missing: {name}", file=sys.stderr)
        sys.exit(1)
    return t.replace(old, new)


def insert_after(t, anchor, text, name):
    n = t.count(anchor)
    ok = _record(name, ">=1", n)
    if CHECK_MODE:
        if not ok:
            return t
        return t.replace(anchor, anchor + text, 1)
    if anchor not in t:
        print(f"BUILD FAIL: anchor missing: {name}", file=sys.stderr)
        sys.exit(1)
    return t.replace(anchor, anchor + text, 1)


def report_table():
    """Print the anchor-check table. Returns 0 if all OK, else 1."""
    total = len(REGISTRY)
    ok_count = sum(1 for e in REGISTRY if e["ok"])
    print(f"Anchor check (upstream verified: {UPSTREAM_VERIFIED})")
    print(f"{'name':<38} {'area':<10} {'expected':<8} {'found':<5} status")
    for e in REGISTRY:
        status = "OK" if e["ok"] else "STALE"
        print(f"{e['name']:<38} {e['area']:<10} {str(e['expected']):<8} {e['found']:<5} {status}")
    print(f"Anchor check: {ok_count}/{total} OK, {total - ok_count} failed")
    return 0 if ok_count == total else 1
