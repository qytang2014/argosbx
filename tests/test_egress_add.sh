#!/bin/bash
# Test: egress_add one-time append (main + container share modules/egress.sh).
# No network, no server. Extracts EGRESS MODULE from built argosbx.sh.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
python3 - "$ROOT/argosbx.sh" "$TMP/egress.sh" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"# ===== EGRESS MODULE BEGIN.*?# ===== EGRESS MODULE END =====\n", t, re.S)
assert m, "EGRESS MODULE not found in argosbx.sh"
open(sys.argv[2], "w").write(m.group(0))
PY
cat > "$TMP/run.sh" << 'RUN'
#!/bin/bash
source "$1"
# 1. Append to existing nodes, with ? & = # in URLs (glob chars must not break dedup)
egress_nodes='socks5://u1:p1@10.0.0.1:1080#socks-out'
egress_bind=''; egress_rules=''
egress_add='vless://11111111-2222-3333-4444-555555555555@203.0.113.10:443?security=reality&pbk=AbCdEfGh&sid=abcd&sni=example.com&fp=chrome&flow=xtls-rprx-vision&type=tcp#reality-out'
egress_init
[ "$egress_nodes" = 'socks5://u1:p1@10.0.0.1:1080#socks-out;vless://11111111-2222-3333-4444-555555555555@203.0.113.10:443?security=reality&pbk=AbCdEfGh&sid=abcd&sni=example.com&fp=chrome&flow=xtls-rprx-vision&type=tcp#reality-out' ] || { echo "FAIL: append result: $egress_nodes"; exit 1; }
echo "$egress_sb_outbounds" | grep -q 'reality-out' || { echo "FAIL: appended node not parsed"; exit 1; }
# 2. Idempotent: second init with same egress_add must not duplicate
egress_init
n=$(printf '%s' "$egress_nodes" | tr ';' '\n' | grep -c 'reality-out' || true)
[ "$n" = "1" ] || { echo "FAIL: duplicate append, count=$n"; exit 1; }
# 3. Append to empty egress_nodes, and skip an already-present node in a multi-add
egress_nodes=''; egress_add='socks5://u:p@1.1.1.1:1080#a;socks5://u:p@1.1.1.1:1080#a;socks5://u:p@2.2.2.2:1080#b'
egress_init
[ "$egress_nodes" = 'socks5://u:p@1.1.1.1:1080#a;socks5://u:p@2.2.2.2:1080#b' ] || { echo "FAIL: empty/multi append: $egress_nodes"; exit 1; }
# 4. egress_add alone must not early-return (geo check + parse must run)
egress_nodes=''; egress_add='socks5://u:p@3.3.3.3:1080#only'
egress_init
echo "$egress_sb_outbounds" | grep -q 'only' || { echo "FAIL: egress_add-only not parsed"; exit 1; }
RUN
bash "$TMP/run.sh" "$TMP/egress.sh"
echo "PASS: egress_add"
