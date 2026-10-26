#!/bin/bash
# Test: egress v2 (step 3) - trojan, vmess (URL form), shadowsocks
# (plain + base64, incl. 2022), vless xhttp, and geoip/geosite/port/
# protocol rules. Also: vmess base64 form is skipped, invalid port
# rules are skipped whole (an empty rule would match everything).
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
SS2022_B64=$(printf '2022-blake3-aes-128-gcm:secret2022@203.0.113.23:8389' | base64 -w0)
cat > "$TMP/run.sh" << 'RUN'
#!/bin/bash
source "$1"
egress_nodes="trojan://pass123@203.0.113.20:443?sni=troj.example.com&type=ws&path=/trojan&host=troj.example.com#trojan-out;vmess://11111111-2222-3333-4444-555555555555@203.0.113.21:443?security=tls&sni=vm.example.com&type=ws&path=/vm&host=vm.example.com#vmess-out;ss://aes-256-gcm:secret123@203.0.113.22:8388#ss-out;ss://$SS2022_B64#ss2022-out;vless://22222222-2222-3333-4444-555555555555@203.0.113.24:443?security=tls&sni=xh.example.com&type=xhttp&path=/xhttp&host=xh.example.com&mode=auto#xhttp-out;vmess://eyJ2IjoiMiJ9#bad-vmess"
egress_bind=""
egress_rules='geoip:CN,US=>trojan-out;geosite:google=>vmess-out;port:80,443=>ss-out;port:1000-2000=>xhttp-out;protocol:http,tls=>trojan-out;port:abc=>ss-out'
egress_init
printf '{"outbounds":[\n%s{"type":"direct","tag":"direct"}\n]}\n' "$egress_sb_outbounds" > "$2/sb_out.json"
printf '{"outbounds":[\n%s{"protocol":"freedom","tag":"direct"}\n]}\n' "$egress_xr_outbounds" > "$2/xr_out.json"
printf '{"rules":[\n%s{"action":"route","outbound":"direct"}\n]}\n' "$egress_sb_rules" > "$2/sb_rules.json"
printf '{"rules":[\n%s{"type":"field","outboundTag":"direct"}\n]}\n' "$egress_xr_rules" > "$2/xr_rules.json"
RUN
SS2022_B64="$SS2022_B64" bash "$TMP/run.sh" "$TMP/egress.sh" "$TMP"
python3 - "$TMP" << 'PY'
import json, sys
tmp = sys.argv[1]
for f in ["sb_out.json", "xr_out.json", "sb_rules.json", "xr_rules.json"]:
    json.load(open(f"{tmp}/{f}"))
sb = json.load(open(f"{tmp}/sb_out.json"))
tags = [o["tag"] for o in sb["outbounds"]]
assert tags == ["trojan-out","vmess-out","ss-out","ss2022-out","xhttp-out","direct"], tags
by = {o["tag"]: o for o in sb["outbounds"]}
assert by["trojan-out"]["type"] == "trojan" and by["trojan-out"]["password"] == "pass123"
assert by["trojan-out"]["tls"]["server_name"] == "troj.example.com"
assert by["trojan-out"]["transport"]["type"] == "ws" and by["trojan-out"]["transport"]["path"] == "/trojan"
assert by["vmess-out"]["type"] == "vmess" and by["vmess-out"]["alter_id"] == 0 and by["vmess-out"]["security"] == "auto"
assert by["vmess-out"]["tls"]["server_name"] == "vm.example.com"
assert by["ss-out"]["method"] == "aes-256-gcm" and by["ss-out"]["password"] == "secret123"
assert by["ss2022-out"]["method"] == "2022-blake3-aes-128-gcm" and by["ss2022-out"]["udp_over_tcp"]["version"] == 2
assert by["xhttp-out"]["transport"]["type"] == "xhttp" and by["xhttp-out"]["transport"]["mode"] == "auto"
xr = json.load(open(f"{tmp}/xr_out.json"))
xby = {o["tag"]: o for o in xr["outbounds"]}
assert xby["trojan-out"]["protocol"] == "trojan" and xby["trojan-out"]["streamSettings"]["network"] == "ws"
assert xby["vmess-out"]["protocol"] == "vmess"
assert xby["ss2022-out"]["settings"]["servers"][0]["uot"] is True
assert xby["xhttp-out"]["streamSettings"]["network"] == "xhttp"
assert xby["xhttp-out"]["streamSettings"]["xhttpSettings"]["mode"] == "auto"
sbr = json.load(open(f"{tmp}/sb_rules.json"))["rules"]
assert sbr[0]["geoip"] == ["CN", "US"] and sbr[0]["outbound"] == "trojan-out", sbr[0]
assert sbr[1]["geosite"] == ["google"] and sbr[1]["outbound"] == "vmess-out", sbr[1]
assert sbr[2]["port"] == [80, 443] and sbr[2]["outbound"] == "ss-out", sbr[2]
assert sbr[3]["port_range"] == ["1000:2000"] and sbr[3]["outbound"] == "xhttp-out", sbr[3]
assert sbr[4]["protocol"] == ["http", "tls"], sbr[4]
xrr = json.load(open(f"{tmp}/xr_rules.json"))["rules"]
assert xrr[0]["geoip"] == ["CN", "US"], xrr[0]
assert xrr[1]["domain"] == ["geosite:google"], xrr[1]
assert xrr[2]["port"] == "80,443", xrr[2]
assert xrr[3]["port"] == "1000-2000", xrr[3]
assert xrr[4]["protocol"] == ["http", "tls"], xrr[4]
# port:abc has no valid port, so the whole rule is skipped (an empty
# rule would match everything, which would be wrong); total = 5 + placeholder
assert len(sbr) == 6, sbr
assert len(xrr) == 6, xrr
print("PASS: egress v2 (trojan, vmess, ss incl. 2022, vless xhttp, geoip/geosite/port/protocol)")
PY
