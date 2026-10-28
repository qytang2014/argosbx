#!/bin/bash
# Test: incremental update state (vars.env) - merge, save, failures.
# No network, no real install, all in temp HOME.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
python3 - "$ROOT/argosbx.sh" "$TMP" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
for name in ["vars_merge", "vars_save"]:
    m = re.search(rf"{name}\(\)\{{.*?\n\}}\n", t, re.S)
    assert m, f"{name} not found"
    open(f"{sys.argv[2]}/{name}.sh", "w").write(m.group(0))
PY
# 1. Merge: explicit wins, unset inherits, unset stays unset, special chars survive
mkdir -p "$TMP/home1/agsbx"
# vars.env is always written by vars_save (%q escaped), so generate it that way
cat > "$TMP/setup_old.sh" << 'RUN'
#!/bin/bash
source "$1/vars_save.sh"
export HOME="$2"
vlpt=12345; vmpt=; reym=old.example.com
egress_nodes='socks5://user:p@ss@1.2.3.4:1080#tag1;vless://u@2.2.2.2:443?security=tls#tag2'
cfip=1.1.1.1
vars_save
RUN
bash "$TMP/setup_old.sh" "$TMP" "$TMP/home1" || exit 1
cat > "$TMP/run_merge.sh" << 'RUN'
#!/bin/bash
source "$1/vars_merge.sh"
source "$1/vars_save.sh"
export HOME="$2"
# explicit override + new protocol, others inherit
vlpt=54321; hypt=9999
vars_merge add
[ "$vlpt" = "54321" ] || { echo "FAIL: override vlpt=$vlpt"; exit 1; }
[ "$hypt" = "9999" ] || { echo "FAIL: new hypt"; exit 1; }
[ "${vmpt+x}" = "x" ] && [ -z "$vmpt" ] || { echo "FAIL: inherited empty vmpt"; exit 1; }
[ "$reym" = "old.example.com" ] || { echo "FAIL: inherited reym"; exit 1; }
[ "$egress_nodes" = 'socks5://user:p@ss@1.2.3.4:1080#tag1;vless://u@2.2.2.2:443?security=tls#tag2' ] || { echo "FAIL: egress round-trip: $egress_nodes"; exit 1; }
[ "$cfip" = "1.1.1.1" ] || { echo "FAIL: inherited cfip"; exit 1; }
[ -z "${anpt+x}" ] || { echo "FAIL: unset anpt leaked in"; exit 1; }
# Save merged state, then reload it clean
vars_save
[ "$(stat -c %a "$HOME/agsbx/vars.env" 2>/dev/null || stat -f %Lp "$HOME/agsbx/vars.env" 2>/dev/null)" = "600" ] || { echo "FAIL: vars.env mode not 600"; exit 1; }
grep -q "^vlpt=54321" "$HOME/agsbx/vars.env" || { echo "FAIL: saved vlpt"; exit 1; }
grep -q "^anpt=" "$HOME/agsbx/vars.env" && { echo "FAIL: saved unset anpt"; exit 1; }
exit 0
RUN
bash "$TMP/run_merge.sh" "$TMP" "$TMP/home1" || exit 1
# 2. Missing vars.env -> add fails, does not proceed
cat > "$TMP/run_missing.sh" << 'RUN'
#!/bin/bash
source "$1/vars_merge.sh"
export HOME="$2"
vars_merge add
echo "FAIL: merge should have exited"
RUN
mkdir -p "$TMP/home2/agsbx"
bash "$TMP/run_missing.sh" "$TMP" "$TMP/home2" >/dev/null 2>&1 && { echo "FAIL: missing vars.env should fail"; exit 1; }
# 3. Merged set with no protocol -> add fails
mkdir -p "$TMP/home3/agsbx"
printf 'name=test\n' > "$TMP/home3/agsbx/vars.env"
bash "$TMP/run_missing.sh" "$TMP" "$TMP/home3" >/dev/null 2>&1 && { echo "FAIL: no-protocol merge should fail"; exit 1; }
# 4. Non-add runs do not merge (vars.env ignored, no exit)
cat > "$TMP/run_noadd.sh" << 'RUN'
#!/bin/bash
source "$1/vars_merge.sh"
export HOME="$2"
vars_merge list
[ -z "${vlpt+x}" ] || { echo "FAIL: non-add merged"; exit 1; }
RUN
bash "$TMP/run_noadd.sh" "$TMP" "$TMP/home1" || exit 1
echo "PASS: vars (merge override/inherit, save 600, missing/no-protocol fail, non-add untouched)"
