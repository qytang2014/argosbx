#!/bin/bash
# Test: kernel-misalignment warning (cheap version, no network, no server).
# vlpt is the only movable inbound. If vlpt_on points at one kernel while
# egress nodes exist that only the other kernel supports, egress_init must
# print an actionable warning naming the nodes and the exact fix
# (vlpt_kernel=...). It must stay silent when there is no misalignment:
# dual-kernel nodes, no vlpt, or vlpt already on the capable kernel.
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

run_case() { # $1 = case name, $2 = vlpt_on value
  local name="$1" von="$2"
  local home="$TMP/$name"
  mkdir -p "$home/agsbx"
  touch "$home/agsbx/sb.json"  # sing-box present so sb-only nodes parse
  cat > "$home/run.sh" << RUN
#!/bin/bash
source "$TMP/egress.sh"
export HOME="$home"
vlpt_on="$von"
egress_nodes='tuic://11111111-2222-3333-4444-555555555555:mypass@203.0.113.20:443?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=tuic.example.com#tuic-node;vless://22222222-2222-3333-4444-555555555555@203.0.113.24:443?encryption=none&security=tls&sni=xhttp.example.com&type=xhttp&path=/x&host=xhttp.example.com#xhttp-node;vless://33333333-2222-3333-4444-555555555555@203.0.113.25:443?encryption=none#dual-node'
egress_bind=''; egress_rules=''
egress_init
RUN
  bash "$home/run.sh" > "$home/msgs.txt" 2>&1
}

run_case xr_on xray
run_case sb_on sb
run_case no_vlpt ""

python3 - "$TMP" << 'PY'
import sys
tmp = sys.argv[1]
def msgs(c): return open(f"{tmp}/{c}/msgs.txt").read()

# 1. vlpt on xray + tuic(sb-only) + xhttp(xr-only) + vless(dual):
#    warns about tuic-node only, suggests vlpt_kernel=sb.
m = msgs("xr_on")
assert "内核错位" in m, m
assert "tuic-node" in m, m
assert "vlpt_kernel=sb" in m, m
assert "xhttp-node" not in m.split("内核错位")[1], m  # xr-only node is fine on xray
assert "dual-node" not in m.split("内核错位")[1], m   # dual node is fine

# 2. vlpt on sb + xhttp(xr-only): warns about xhttp-node, suggests vlpt_kernel=xray.
m = msgs("sb_on")
assert "内核错位" in m, m
assert "xhttp-node" in m, m
assert "vlpt_kernel=xray" in m, m
assert "tuic-node" not in m.split("内核错位")[1], m  # sb-only node is fine on sb

# 3. no vlpt installed: silent, even with single-kernel nodes around.
m = msgs("no_vlpt")
assert "内核错位" not in m, m
print("test_egress_misalign: all assertions passed")
PY
