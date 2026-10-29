#!/bin/bash
# Test: egress new protocol branches (no network, no server).
# - hysteria2/hy2: DUAL kernel (Xray implements Hysteria2; verified with the
#   pinned Xray 26.3.27 binary: "protocol": "hysteria" + streamSettings
#   network "hysteria", both requiring "version": 2).
# - tuic / anytls / naive: sing-box ONLY. Without sb.json they are skipped
#   with a kernel-aware message; rules pointing at their tags are emitted
#   for sing-box but skipped on the Xray side (no dangling outbound refs).
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

run_case() { # $1 = case name, $2 = 1 if sb.json exists
  local name="$1" sbjson="$2"
  local home="$TMP/$name"
  mkdir -p "$home/agsbx"
  [ "$sbjson" = "1" ] && touch "$home/agsbx/sb.json"
  cat > "$home/run.sh" << RUN
#!/bin/bash
source "$TMP/egress.sh"
export HOME="$home"
egress_nodes='tuic://11111111-2222-3333-4444-555555555555:mypass@203.0.113.20:443?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=tuic.example.com#tuic-node;hysteria2://hy2pass@203.0.113.21:443?sni=hy2.example.com&alpn=h3#hy2-node;anytls://anypass@203.0.113.22:443?sni=any.example.com#anytls-node;naive+https://nuser:npass@203.0.113.23:443?sni=naive.example.com#naive-node'
egress_bind=''; egress_rules='domain:google.com=>tuic-node;domain:example.com=>hy2-node'
egress_init
printf '{"outbounds":[\n%s{"type":"direct","tag":"direct"}\n]}\n' "\$egress_sb_outbounds" > "$home/sb_out.json"
printf '{"outbounds":[\n%s{"protocol":"freedom","tag":"direct"}\n]}\n' "\$egress_xr_outbounds" > "$home/xr_out.json"
printf '{"rules":[\n%s{"action":"route","outbound":"direct"}\n]}\n' "\$egress_sb_rules" > "$home/sb_rules.json"
printf '{"rules":[\n%s{"type":"field","outboundTag":"direct"}\n]}\n' "\$egress_xr_rules" > "$home/xr_rules.json"
RUN
  bash "$home/run.sh" > "$home/msgs.txt" 2>&1
}

run_case dual 1
run_case xrayonly 0

python3 - "$TMP" << 'PY'
import json, sys
tmp = sys.argv[1]

def load(case, f):
    return json.load(open(f"{tmp}/{case}/{f}"))

# ---- dual kernel: everything parses, rules split per kernel ----
sb = load("dual", "sb_out.json"); xr = load("dual", "xr_out.json")
sb_tags = [o["tag"] for o in sb["outbounds"]]; xr_tags = [o["tag"] for o in xr["outbounds"]]
assert [o["type"] for o in sb["outbounds"] if o["tag"] == "tuic-node"] == ["tuic"], sb_tags
tuic = [o for o in sb["outbounds"] if o["tag"] == "tuic-node"][0]
assert tuic["uuid"] == "11111111-2222-3333-4444-555555555555" and tuic["password"] == "mypass"
assert tuic["tls"]["server_name"] == "tuic.example.com" and tuic["congestion_control"] == "bbr"
assert [o["type"] for o in sb["outbounds"] if o["tag"] == "hy2-node"] == ["hysteria2"]
assert [o["type"] for o in sb["outbounds"] if o["tag"] == "anytls-node"] == ["anytls"]
assert [o["type"] for o in sb["outbounds"] if o["tag"] == "naive-node"] == ["naive"]
assert [o["protocol"] for o in xr["outbounds"] if o["tag"] == "hy2-node"] == ["hysteria"], xr_tags
hy2xr = [o for o in xr["outbounds"] if o["tag"] == "hy2-node"][0]
assert hy2xr["settings"] == {"version": 2, "address": "203.0.113.21", "port": 443}, hy2xr["settings"]
assert hy2xr["streamSettings"]["network"] == "hysteria"
assert hy2xr["streamSettings"]["hysteriaSettings"] == {"version": 2, "auth": "hy2pass"}, hy2xr["streamSettings"]
assert "tuic-node" not in xr_tags and "anytls-node" not in xr_tags and "naive-node" not in xr_tags, xr_tags
sbr = [r["outbound"] for r in load("dual", "sb_rules.json")["rules"]]
xrr = [r["outboundTag"] for r in load("dual", "xr_rules.json")["rules"]]
assert "tuic-node" in sbr and "hy2-node" in sbr, sbr
assert "tuic-node" not in xrr and "hy2-node" in xrr, xrr
msgs = open(f"{tmp}/dual/msgs.txt").read()
assert "仅 sing-box 支持，Xray 侧已跳过该规则" in msgs, msgs

# ---- xray only: sb-only nodes skipped with kernel message ----
sb = load("xrayonly", "sb_out.json"); xr = load("xrayonly", "xr_out.json")
sb_tags = [o["tag"] for o in sb["outbounds"]]; xr_tags = [o["tag"] for o in xr["outbounds"]]
assert "hy2-node" in sb_tags and "tuic-node" not in sb_tags and "anytls-node" not in sb_tags, sb_tags
assert "hy2-node" in xr_tags and "tuic-node" not in xr_tags and "anytls-node" not in xr_tags, xr_tags
xrr = [r["outboundTag"] for r in load("xrayonly", "xr_rules.json")["rules"]]
assert xrr == ["hy2-node", "direct"], xrr
msgs = open(f"{tmp}/xrayonly/msgs.txt").read()
assert "tuic 节点 tuic-node 仅 sing-box 支持，当前未安装 sing-box，已跳过" in msgs, msgs
assert "anytls 节点 anytls-node 仅 sing-box 支持，当前未安装 sing-box，已跳过" in msgs, msgs
assert "naive 节点 naive-node 仅 sing-box 支持，当前未安装 sing-box，已跳过" in msgs, msgs
assert "分流规则目标出口不存在，已跳过：domain:google.com=>tuic-node" in msgs, msgs
print("PASS: egress new protocol branches (hy2 dual-kernel, tuic/anytls/naive sing-box-only)")
PY
