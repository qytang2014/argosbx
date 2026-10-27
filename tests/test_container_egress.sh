#!/bin/bash
# Test: container egress parity - same egress module as main script,
# extracted from container/nodejs/start.sh, with its 4 xrsbout hooks
# present in the built file.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F="$ROOT/container/nodejs/start.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Hooks: egress_init at xrsbout start + 4 fragment placeholders in xrsbout
grep -q '^xrsbout(){' "$F" || { echo "FAIL: xrsbout missing"; exit 1; }
awk '/^xrsbout\(\)\{/{flag=1} flag && /^egress_init$/{found=1} /^ins\(\)\{/{flag=0} END{exit !found}' "$F" || { echo "FAIL: egress_init not at xrsbout start"; exit 1; }
for h in 'egress_xr_outbounds' 'egress_xr_rules' 'egress_sb_outbounds' 'egress_sb_rules'; do
  grep -q "^\${$h}" "$F" || { echo "FAIL: container hook missing: $h"; exit 1; }
done
# Env passthrough in ins()
grep -q 'export egress_nodes=${egress_nodes}' "$F" || { echo "FAIL: egress_nodes not exported in container ins()"; exit 1; }
grep -q 'export egress_bind=${egress_bind}' "$F" || { echo "FAIL: egress_bind not exported"; exit 1; }
grep -q 'export egress_rules=${egress_rules}' "$F" || { echo "FAIL: egress_rules not exported"; exit 1; }
python3 - "$F" "$TMP/egress.sh" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"# ===== EGRESS MODULE BEGIN.*?# ===== EGRESS MODULE END =====\n", t, re.S)
assert m, "EGRESS MODULE not found in container start.sh"
open(sys.argv[2], "w").write(m.group(0))
PY
cat > "$TMP/run.sh" << 'RUN'
#!/bin/bash
source "$1"
egress_nodes=""; egress_bind=""; egress_rules=""; egress_init
[ -z "$egress_sb_outbounds" ] && [ -z "$egress_xr_outbounds" ] || { echo "FAIL: empty egress should produce empty outbounds"; exit 1; }
egress_nodes='trojan://pass123@203.0.113.20:443?sni=troj.example.com&type=ws&path=/trojan&host=troj.example.com#trojan-out'
egress_bind='1.2.3.4'
egress_rules='geoip:CN=>trojan-out;port:443=>bind1'
egress_init
printf '{"outbounds":[\n%s{"type":"direct","tag":"direct"}\n]}\n' "$egress_sb_outbounds" > "$2/sb_out.json"
printf '{"outbounds":[\n%s{"protocol":"freedom","tag":"direct"}\n]}\n' "$egress_xr_outbounds" > "$2/xr_out.json"
printf '{"rules":[\n%s{"action":"route","outbound":"direct"}\n]}\n' "$egress_sb_rules" > "$2/sb_rules.json"
printf '{"rules":[\n%s{"type":"field","outboundTag":"direct"}\n]}\n' "$egress_xr_rules" > "$2/xr_rules.json"
RUN
bash "$TMP/run.sh" "$TMP/egress.sh" "$TMP"
python3 - "$TMP" << 'PY'
import json, sys
tmp = sys.argv[1]
for f in ["sb_out.json", "xr_out.json", "sb_rules.json", "xr_rules.json"]:
    json.load(open(f"{tmp}/{f}"))
sb = json.load(open(f"{tmp}/sb_out.json"))
assert [o["tag"] for o in sb["outbounds"]] == ["trojan-out","bind1","direct"], sb["outbounds"]
assert sb["outbounds"][0]["type"] == "trojan"
sbr = json.load(open(f"{tmp}/sb_rules.json"))["rules"]
assert sbr[0]["geoip"] == ["CN"] and sbr[0]["outbound"] == "trojan-out"
assert sbr[1]["port"] == [443] and sbr[1]["outbound"] == "bind1"
print("PASS: container egress (module + hooks + env passthrough, empty zero-change)")
PY
