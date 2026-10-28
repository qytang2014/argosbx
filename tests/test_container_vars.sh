#!/bin/bash
# Test: container incremental state (container_vars.env) - merge, save, dash no-op.
# No network, no server. Extracts container_vars_* from built container start.sh.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
python3 - "$ROOT/container/nodejs/start.sh" "$TMP" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
for name in ["container_vars_merge", "container_vars_save"]:
    m = re.search(rf"{name}\(\)\{{.*?^}}\n", t, re.S | re.M)
    assert m, f"{name} not found in container start.sh"
    open(f"{sys.argv[2]}/{name}.sh", "w").write(m.group(0))
PY
# 1. Save then merge: explicit wins, unset inherits, egress_add is NOT saved
cat > "$TMP/run1.sh" << 'RUN'
#!/bin/bash
source "$1/container_vars_merge.sh"
source "$1/container_vars_save.sh"
export HOME="$2"
# Simulate a previous container start
vmpt=1111; vlpt=; reym=old.example.com
egress_nodes='socks5://u:p@1.1.1.1:1080#a'
egress_add='socks5://u:p@2.2.2.2:1080#b'
# Simulate egress_init append (egress_nodes merged, egress_add not saved)
egress_nodes="$egress_nodes;$egress_add"
container_vars_save
grep -q "egress_nodes=" "$HOME/agsbx/container_vars.env" || { echo "FAIL: egress_nodes not saved"; exit 1; }
grep -q "egress_add" "$HOME/agsbx/container_vars.env" && { echo "FAIL: egress_add must not be saved"; exit 1; }
[ "$(stat -c %a "$HOME/agsbx/container_vars.env" 2>/dev/null || stat -f %Lp "$HOME/agsbx/container_vars.env" 2>/dev/null)" = "600" ] || { echo "FAIL: mode not 600"; exit 1; }
# Simulate a new container start with only vmpt changed in env
unset vmpt vlpt reym egress_nodes egress_add
vmpt=2222
container_vars_merge
[ "$vmpt" = "2222" ] || { echo "FAIL: explicit vmpt=$vmpt"; exit 1; }
[ -z "$vlpt" ] || { echo "FAIL: inherited vlpt should be empty"; exit 1; }
[ "$reym" = "old.example.com" ] || { echo "FAIL: inherited reym=$reym"; exit 1; }
[ "$egress_nodes" = 'socks5://u:p@1.1.1.1:1080#a;socks5://u:p@2.2.2.2:1080#b' ] || { echo "FAIL: inherited merged egress_nodes=$egress_nodes"; exit 1; }
RUN
mkdir -p "$TMP/home1/agsbx"
bash "$TMP/run1.sh" "$TMP" "$TMP/home1" || exit 1
# 2. Dash direct run: both functions no-op, no file created
mkdir -p "$TMP/home2/agsbx"
cat > "$TMP/run_dash.sh" << 'RUN'
#!/bin/sh
. "$1/container_vars_merge.sh"
. "$1/container_vars_save.sh"
export HOME="$2"
container_vars_merge
container_vars_save
RUN
SH_CMD="sh"; command -v dash >/dev/null 2>&1 && SH_CMD="dash"
"$SH_CMD" "$TMP/run_dash.sh" "$TMP" "$TMP/home2" || { echo "FAIL: dash run failed"; exit 1; }
[ ! -e "$TMP/home2/agsbx/container_vars.env" ] || { echo "FAIL: dash should not save"; exit 1; }
echo "PASS: container_vars"
