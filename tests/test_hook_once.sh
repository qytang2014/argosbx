#!/bin/bash
# Test: lifecycle hooks fire each handler EXACTLY once.
# Regression for the 3c14dc8b refactor follow-up: the direct calls
# that used to duplicate every hook (vars_merge, vars_save, fw_sync,
# cert_remove_watch, sub_https_stop, fw_cleanup, egress_init,
# egress_geo_setup) were removed from build.py; only run_hook remains.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }

# 1. structural: no direct call may sit right after its run_hook
python3 - "$ROOT/argosbx.sh" << 'PY' || fail "duplicate direct call still present"
import re, sys
t = open(sys.argv[1]).read()
dups = [
    ('run_hook on_init "$1"\nvars_merge "$1"', "on_init/vars_merge"),
    ('run_hook on_complete\nvars_save', "on_complete/vars_save"),
    ('run_hook post_start\nrun_hook on_complete\nvars_save', "post_start/vars_save"),
    ('run_hook post_start\nrun_hook on_complete\nif [ -n "$sub" ]; then\nsubtokenipsub',
     None),  # placeholder, replaced below
    ('run_hook pre_xrsbout\negress_init', "pre_xrsbout/egress_init"),
    ('run_hook pre_xrsbout\negress_geo_setup', "pre_xrsbout/egress_geo_setup"),
    ('run_hook on_uninstall\ncert_remove_watch', "on_uninstall/cert_remove_watch"),
    ('run_hook on_uninstall\ncleandel\nsub_https_stop', "on_uninstall/sub_https_stop"),
]
for old, name in dups:
    if name is None:
        continue
    assert old not in t, f"duplicate direct call: {name}"
# after ins: post_start + on_complete, then straight to the sub block
assert 'ins\nrun_hook post_start\nrun_hook on_complete\nif [ -n "$sub" ]; then' in t, \
    "post-ins hook sequence wrong"
# del branch: on_uninstall, then cleandel directly
assert 'run_hook on_uninstall\ncleandel\n' in t, "del hook sequence wrong"
print("ok: no duplicate direct calls after run_hook")
PY

# 2. functional: register every block from the generated script, stub
# the handlers, fire each event once, assert single execution
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
python3 - "$ROOT/argosbx.sh" "$TMP/regs.sh" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
blocks = re.findall(r'command -v register_hook >/dev/null 2>&1 && \{\n(?:.*\n)*?\}\n', t)
assert len(blocks) >= 5, f"expected >=5 registration blocks, got {len(blocks)}"
open(sys.argv[2], "w").write("\n".join(blocks))
PY
cat > "$TMP/run.sh" << 'RUN'
#!/bin/bash
. "$1"   # modules/hook.sh: register_hook / run_hook
. "$2"   # all registration blocks extracted from argosbx.sh
TRACE=""
for h in vars_merge vars_save sub_https_sync sub_https_stop fw_sync fw_cleanup cert_remove_watch egress_init egress_geo_setup; do
  eval "$h(){ TRACE=\"\${TRACE}$h;\"; }"
done
run_hook on_init "add"
run_hook pre_xrsbout
run_hook post_start
run_hook on_complete
run_hook on_uninstall
echo "$TRACE"
RUN
chmod +x "$TMP/run.sh"
TRACE=$(bash "$TMP/run.sh" "$ROOT/modules/hook.sh" "$TMP/regs.sh")
for h in vars_merge vars_save sub_https_sync sub_https_stop fw_sync fw_cleanup cert_remove_watch egress_init egress_geo_setup; do
  n=$(printf '%s' "$TRACE" | tr ';' '\n' | grep -cx "$h" || true)
  [ "$n" = "1" ] || fail "handler $h fired $n times (trace: $TRACE)"
done
echo "ok: each lifecycle handler fired exactly once"
echo "PASS: hook once"
