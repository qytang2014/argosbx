#!/bin/bash
# Test: '&' combined AND rules. One rule with several conditions must
# become ONE routing object with several fields (AND in both kernels),
# comma lists inside one condition stay OR, rules in order stay
# first-match-wins, and a rule with an unknown condition or no valid
# port is skipped whole, never weakened to a partial AND.
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
egress_rules='inbound:vlpt&domain:google.com=>node1;domain:example.com&ip:1.2.3.0/24=>node2;inbound:hypt&port:443=>node1;geosite:google&domain:example.com=>node2;inbound:vlpt&geoip:cn=>node1;inbound:vlpt&port:abc=>node2;inbound:vlpt&unknown:foo=>node2;domain:google.com=>node1'
egress_init
printf '{"rules":[\n%s{"action":"route","outbound":"direct"}\n]}\n' "$egress_sb_rules" > "$2/sb_rules.json"
printf '{"rules":[\n%s{"type":"field","outboundTag":"direct"}\n]}\n' "$egress_xr_rules" > "$2/xr_rules.json"
# geo detection must see geoip/geosite even when they are not first
egress_rules='inbound:vlpt&geoip:cn=>node1'
egress_geo_needed
echo "$egress_geo_needed" > "$2/geo1"
egress_rules='domain:geosite.example.com=>node1'
egress_geo_needed
echo "$egress_geo_needed" > "$2/geo2"
RUN
bash "$TMP/run.sh" "$TMP/egress.sh" "$TMP"
python3 - "$TMP" << 'PY'
import json, sys
tmp = sys.argv[1]
sb = json.load(open(f"{tmp}/sb_rules.json"))
xr = json.load(open(f"{tmp}/xr_rules.json"))
# 5 valid AND rules + 1 single rule + 1 placeholder; 2 invalid skipped
assert len(sb["rules"]) == 7, sb
assert len(xr["rules"]) == 7, xr
# 1. inbound AND domain: one object, both fields, outbound node1
assert sb["rules"][0]["inbound"] == ["reality-vision", "vl-reality-sb"], sb["rules"][0]
assert sb["rules"][0]["domain_suffix"] == ["google.com"], sb["rules"][0]
assert sb["rules"][0]["outbound"] == "node1", sb["rules"][0]
assert xr["rules"][0]["inboundTag"] == ["reality-vision", "vl-reality-sb"], xr["rules"][0]
assert xr["rules"][0]["domain"] == ["google.com"], xr["rules"][0]
# 2. domain AND ip
assert sb["rules"][1]["domain_suffix"] == ["example.com"], sb["rules"][1]
assert sb["rules"][1]["ip_cidr"] == ["1.2.3.0/24"], sb["rules"][1]
assert xr["rules"][1]["domain"] == ["example.com"], xr["rules"][1]
assert xr["rules"][1]["ip"] == ["1.2.3.0/24"], xr["rules"][1]
# 3. inbound AND port: SB port is a list, XR port is a string
assert sb["rules"][2]["inbound"] == ["hy2-xr", "hy2-sb"], sb["rules"][2]
assert sb["rules"][2]["port"] == [443], sb["rules"][2]
assert xr["rules"][2]["port"] == "443", xr["rules"][2]
# 4. geosite AND domain: SB keeps two keys, XR merges into one domain list
assert sb["rules"][3]["geosite"] == ["google"], sb["rules"][3]
assert sb["rules"][3]["domain_suffix"] == ["example.com"], sb["rules"][3]
assert xr["rules"][3]["domain"] == ["geosite:google", "example.com"], xr["rules"][3]
# 5. inbound AND geoip
assert sb["rules"][4]["inbound"] == ["reality-vision", "vl-reality-sb"], sb["rules"][4]
assert sb["rules"][4]["geoip"] == ["cn"], sb["rules"][4]
# 6. single rule after AND rules still works
assert sb["rules"][5]["domain_suffix"] == ["google.com"], sb["rules"][5]
# geo detection: AND geoip triggers, domain value containing geosite does not
assert open(f"{tmp}/geo1").read().strip() == "1", "AND geoip must trigger geo download"
assert open(f"{tmp}/geo2").read().strip() == "0", "domain value geosite.example.com must not trigger geo"
print("PASS: egress AND rules")
PY
