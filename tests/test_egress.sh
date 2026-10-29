#!/bin/bash
# Test: egress module in isolation (no network, no server).
# Extracts the EGRESS MODULE block from built argosbx.sh, runs it
# with 5 nodes (socks, reality, tls-ws, socks, grpc) + 2 bind IPs +
# 4 rules + 1 invalid rule, and validates the generated JSON fragments.
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
egress_nodes=""; egress_bind=""; egress_rules=""; egress_init
[ -z "$egress_sb_outbounds" ] && [ -z "$egress_xr_outbounds" ] || { echo "FAIL: empty egress should produce empty outbounds"; exit 1; }
egress_nodes='socks5://u1:p1@10.0.0.1:1080#socks-out;vless://11111111-2222-3333-4444-555555555555@203.0.113.10:443?security=reality&pbk=AbCdEfGh&sid=abcd&sni=example.com&fp=chrome&flow=xtls-rprx-vision&type=tcp#reality-out;vless://22222222-2222-3333-4444-555555555555@203.0.113.11:443?security=tls&sni=tls.example.com&type=ws&path=/ws&host=tls.example.com#tls-ws-out;socks5://u2:p2@10.0.0.2:1080#socks2;vless://33333333-3333-3333-3333-333333333333@203.0.113.12:8443?security=tls&sni=g.example.com&type=grpc&serviceName=svc#grpc-out'
egress_bind='1.2.3.4,2001:db8::2'
egress_rules='domain:example.com,foo.org=>socks-out;ip:1.2.3.0/24=>reality-out;source:10.0.0.0/8=>bind1;inbound:vm-ws=>bind2;domain:bad.example=>no-such-tag'
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
assert [o["tag"] for o in sb["outbounds"]] == ["socks-out","reality-out","tls-ws-out","socks2","grpc-out","bind1","bind2","direct"], sb["outbounds"]
reality = [o for o in sb["outbounds"] if o["tag"]=="reality-out"][0]
assert reality["tls"]["reality"]["public_key"]=="AbCdEfGh" and reality["flow"]=="xtls-rprx-vision", reality
xr = json.load(open(f"{tmp}/xr_out.json"))
assert [o["tag"] for o in xr["outbounds"]] == ["socks-out","reality-out","tls-ws-out","socks2","grpc-out","bind1","bind2","direct"]
assert [o for o in xr["outbounds"] if o["tag"]=="reality-out"][0]["streamSettings"]["security"]=="reality"
# Xray >= 26.x refuses to start a vless outbound whose users lack
# "encryption":"none" ("please add/set encryption:none for every user"),
# which used to surface as "Argosbx脚本进程未启动，安装失败".
for o in xr["outbounds"]:
    if o.get("protocol")=="vless":
        for u in o["settings"]["vnext"][0]["users"]:
            assert u.get("encryption")=="none", o["tag"]
rules = json.load(open(f"{tmp}/sb_rules.json"))
assert len(rules["rules"])==5, rules  # 4 valid rules + 1 final placeholder, invalid rule skipped
print("PASS: egress (unlimited nodes, reality, bind, rules, invalid-rule skip)")
PY
