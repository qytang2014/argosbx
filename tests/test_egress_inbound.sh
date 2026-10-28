#!/bin/bash
# Test: inbound: rules accept protocol variable names (vlpt, hypt, ...)
# and expand them to the real server inbound tags. Old real tags and
# unknown values must pass through unchanged.
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
egress_nodes='vless://11111111-2222-3333-4444-555555555555@203.0.113.10:443?security=reality&pbk=AbCd&sid=abcd&sni=example.com&fp=chrome&flow=xtls-rprx-vision&type=tcp#node1;socks5://u:p@10.0.0.1:1080#node2'
egress_bind='1.2.3.4'
egress_rules='inbound:vlpt=>node1;inbound:hypt,vmpt=>node2;inbound:xhpt=>node1;inbound:reality-vision=>node1;inbound:vm-ws=>node2;inbound:VLPT=>node1'
egress_init
printf '{"rules":[\n%s{"action":"route","outbound":"direct"}\n]}\n' "$egress_sb_rules" > "$2/sb_rules.json"
printf '{"rules":[\n%s{"type":"field","outboundTag":"direct"}\n]}\n' "$egress_xr_rules" > "$2/xr_rules.json"
RUN
bash "$TMP/run.sh" "$TMP/egress.sh" "$TMP"
python3 - "$TMP" << 'PY'
import json, sys
tmp = sys.argv[1]
sb = json.load(open(f"{tmp}/sb_rules.json"))
xr = json.load(open(f"{tmp}/xr_rules.json"))
# 6 rules + 1 placeholder
assert len(sb["rules"]) == 7, sb
assert len(xr["rules"]) == 7, xr
# vlpt expands to both kernels' tags, so the rule matches whichever installed it
assert sb["rules"][0]["inbound"] == ["reality-vision", "vl-reality-sb"], sb["rules"][0]
assert xr["rules"][0]["inboundTag"] == ["reality-vision", "vl-reality-sb"], xr["rules"][0]
# hypt + vmpt expand to 4 tags, in order, deduped
assert sb["rules"][1]["inbound"] == ["hy2-xr", "hy2-sb", "vmess-xr", "vmess-sb"], sb["rules"][1]
# xhpt is Xray-only
assert sb["rules"][2]["inbound"] == ["xhttp-reality"], sb["rules"][2]
# old real tag passes through unchanged
assert sb["rules"][3]["inbound"] == ["reality-vision"], sb["rules"][3]
# unknown value passes through unchanged (old test_egress.sh vm-ws case)
assert sb["rules"][4]["inbound"] == ["vm-ws"], sb["rules"][4]
# uppercase alias works
assert sb["rules"][5]["inbound"] == ["reality-vision", "vl-reality-sb"], sb["rules"][5]
print("PASS: egress inbound alias")
PY
