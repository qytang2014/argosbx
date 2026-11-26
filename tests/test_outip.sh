#!/bin/bash
# Test: outbound IPv4/IPv6 strategy (outip) in complete sandbox isolation.
# Never touches host /root/agsbx or any system files/services.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Record host /root/agsbx mtime before test to verify strict host isolation.
HOST_AGSBX_MTIME_BEFORE=$(stat -c '%Y' /root/agsbx 2>/dev/null || echo "none")
export HOME="$TMP/home"
mkdir -p "$HOME/agsbx"

# Extract modules and helpers from built artifacts into sandbox files.
python3 - "$ROOT" "$TMP" << 'PY'
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
tmp = pathlib.Path(sys.argv[2])

main_txt = (root / "argosbx.sh").read_text()
cont_txt = (root / "container/nodejs/start.sh").read_text()
html_txt = (root / "index.html").read_text()

# Check built artifacts contain outip plumbing
assert "egress_resolve_outip" in main_txt, "argosbx.sh missing egress_resolve_outip"
assert "export outip=${outip:-''}" in main_txt, "argosbx.sh missing export outip"
assert "outip=" in main_txt and "agsbx_help" in main_txt, "argosbx.sh missing outip in help"

assert "egress_resolve_outip" in cont_txt, "start.sh missing egress_resolve_outip"
assert "export outip=${outip}" in cont_txt, "start.sh missing export outip"

assert '<select id="outip">' in html_txt, "index.html missing <select id=\"outip\">"
assert "'warp','outip','ippz'" in html_txt, "index.html missing outip in optIds"
assert "getElementById('outip').value = ''" in html_txt, "index.html missing outip reset"
assert "'warp', 'outip', 'uuid'" in html_txt, "index.html missing outip in tobash order"

m_main = re.search(r"# ===== EGRESS MODULE BEGIN.*?# ===== EGRESS MODULE END =====\n", main_txt, re.S)
assert m_main, "EGRESS MODULE not found in argosbx.sh"
(tmp / "egress_main.sh").write_text(m_main.group(0))

m_cont = re.search(r"# ===== EGRESS MODULE BEGIN.*?# ===== EGRESS MODULE END =====\n", cont_txt, re.S)
assert m_cont, "EGRESS MODULE not found in container/nodejs/start.sh"
(tmp / "egress_cont.sh").write_text(m_cont.group(0))

for fn in ["vars_merge", "vars_save"]:
    m = re.search(rf"{fn}\(\)\{{.*?\n\}}\n", main_txt, re.S)
    assert m, f"{fn} not found in argosbx.sh"
    (tmp / f"{fn}.sh").write_text(m.group(0))

for fn in ["container_vars_merge", "container_vars_save"]:
    m = re.search(rf"{fn}\(\)\{{.*?\n\}}\n", cont_txt, re.S)
    assert m, f"{fn} not found in start.sh"
    (tmp / f"{fn}.sh").write_text(m.group(0))
PY
echo "ok: built artifacts contain outip wiring (main, container, index.html)"

# Helper to run strategy evaluation in a clean subshell for both main and container egress modules.
assert_strategy() {
  local label="$1" outip_v="$2" v4="$3" v6="$4" s1="$5" s2="$6" sip_v="$7" x1="$8" x2="$9" xip_v="${10}" warp_v="${11}" want_sb="${12}" want_xr="${13}" want_wx="${14}" want_warn="${15:-}"
  local mod err_f got_sb got_xr got_wx
  for mod in "$TMP/egress_main.sh" "$TMP/egress_cont.sh"; do
    err_f="$TMP/err.log"
    : > "$err_f"
    eval "$(
      bash -c '
        source "$1"
        export HOME="$2"
        outip="$3" v4_ok="$4" v6_ok="$5"
        s1outtag="$6" s2outtag="$7" sip="$8"
        x1outtag="$9" x2outtag="${10}" xip="${11}" warp="${12}"
        egress_nodes="" egress_bind="" egress_rules="" egress_add=""
        sbyx="stale_sb" xryx="stale_xr" wxryx="stale_wx"
        egress_init
        printf "got_sb=%q got_xr=%q got_wx=%q\n" "$sbyx" "$xryx" "$wxryx"
      ' _ "$mod" "$HOME" "$outip_v" "$v4" "$v6" "$s1" "$s2" "$sip_v" "$x1" "$x2" "$xip_v" "$warp_v" 2>"$err_f"
    )"
    [ "$got_sb" = "$want_sb" ] || { echo "FAIL [$label] ($mod): sbyx=$got_sb want=$want_sb"; exit 1; }
    [ "$got_xr" = "$want_xr" ] || { echo "FAIL [$label] ($mod): xryx=$got_xr want=$want_xr"; exit 1; }
    [ "$got_wx" = "$want_wx" ] || { echo "FAIL [$label] ($mod): wxryx=$got_wx want=$want_wx"; exit 1; }
    if [ -n "$want_warn" ]; then
      grep -qF "$want_warn" "$err_f" || { echo "FAIL [$label] ($mod): expected warning [$want_warn] in stderr: $(cat "$err_f")"; exit 1; }
    elif [ -s "$err_f" ]; then
      echo "FAIL [$label] ($mod): unexpected stderr: $(cat "$err_f")"
      exit 1
    fi
  done
  echo "ok: $label -> sb=$want_sb xr=$want_xr wx=$want_wx"
}

# 1. Default auto mode (no WARP) across dual-stack / pure IPv4 / pure IPv6
assert_strategy "dual-stack direct default" "" "true" "true" "direct" "direct" '"::/0", "0.0.0.0/0"' "direct" "direct" '"::/0", "0.0.0.0/0"' "no" "prefer_ipv4" "ForceIPv4v6" "ForceIPv4v6"
assert_strategy "pure-v4 direct fixes prefer_ipv6 bug" "" "true" "" "direct" "direct" '"::/0", "0.0.0.0/0"' "direct" "direct" '"::/0", "0.0.0.0/0"' "no" "ipv4_only" "ForceIPv4" "ForceIPv4v6"
assert_strategy "pure-v6 direct fixes prefer_ipv4 bug" "" "" "true" "direct" "direct" '"::/0", "0.0.0.0/0"' "direct" "direct" '"::/0", "0.0.0.0/0"' "no" "ipv6_only" "ForceIPv6" "ForceIPv4v6"

# 2. Dual-stack WARP & single-stack WARP coordination
assert_strategy "dual-stack WARP (sx)" "" "true" "true" "warp-out" "warp-out" '"::/0", "0.0.0.0/0"' "warp-out" "warp-out" '"::/0", "0.0.0.0/0"' "sx" "prefer_ipv4" "ForceIPv4v6" "ForceIPv4v6"
assert_strategy "pure-v4 + warp=s6 enables v6 route match" "" "true" "" "warp-out" "direct" '"::/0"' "direct" "direct" '"::/0", "0.0.0.0/0"' "s6" "prefer_ipv6" "ForceIPv4" "ForceIPv4v6"
assert_strategy "pure-v6 + warp=s6 uses ipv6_only" "" "" "true" "warp-out" "direct" '"::/0"' "direct" "direct" '"::/0", "0.0.0.0/0"' "s6" "ipv6_only" "ForceIPv6" "ForceIPv4v6"
assert_strategy "dual-stack + warp=x6 sets wxryx ForceIPv6" "" "true" "true" "direct" "direct" '"::/0", "0.0.0.0/0"' "warp-out" "direct" '"::/0"' "x6" "prefer_ipv4" "ForceIPv4v6" "ForceIPv6"
assert_strategy "pure-v6 + warp=s4 enables v4 route match" "" "" "true" "warp-out" "direct" '"0.0.0.0/0"' "direct" "direct" '"::/0", "0.0.0.0/0"' "s4" "prefer_ipv4" "ForceIPv6" "ForceIPv4v6"

# 3. Explicit outip overrides and aliases
assert_strategy "explicit outip=4" "4" "true" "true" "direct" "direct" '"::/0", "0.0.0.0/0"' "direct" "direct" '"::/0", "0.0.0.0/0"' "" "prefer_ipv4" "ForceIPv4v6" "ForceIPv4v6"
assert_strategy "explicit outip=6" "6" "true" "true" "direct" "direct" '"::/0", "0.0.0.0/0"' "direct" "direct" '"::/0", "0.0.0.0/0"' "" "prefer_ipv6" "ForceIPv6v4" "ForceIPv6v4"
assert_strategy "explicit outip=4only" "4only" "true" "true" "direct" "direct" '"::/0", "0.0.0.0/0"' "direct" "direct" '"::/0", "0.0.0.0/0"' "" "ipv4_only" "ForceIPv4" "ForceIPv4"
assert_strategy "explicit outip=6only" "6only" "true" "true" "direct" "direct" '"::/0", "0.0.0.0/0"' "direct" "direct" '"::/0", "0.0.0.0/0"' "" "ipv6_only" "ForceIPv6" "ForceIPv6"
assert_strategy "alias prefer_ipv6" "prefer_ipv6" "true" "true" "direct" "direct" '"::/0", "0.0.0.0/0"' "direct" "direct" '"::/0", "0.0.0.0/0"' "" "prefer_ipv6" "ForceIPv6v4" "ForceIPv6v4"
assert_strategy "alias ipv4_only" "ipv4_only" "true" "true" "direct" "direct" '"::/0", "0.0.0.0/0"' "direct" "direct" '"::/0", "0.0.0.0/0"' "" "ipv4_only" "ForceIPv4" "ForceIPv4"
assert_strategy "case-insensitive 6ONLY" "6ONLY" "true" "true" "direct" "direct" '"::/0", "0.0.0.0/0"' "direct" "direct" '"::/0", "0.0.0.0/0"' "" "ipv6_only" "ForceIPv6" "ForceIPv6"

# 4. Conflict warnings and invalid fallback
assert_strategy "conflict warp=s6 + outip=4only warns" "4only" "true" "" "warp-out" "direct" '"::/0"' "direct" "direct" '"::/0", "0.0.0.0/0"' "s6" "ipv4_only" "ForceIPv4" "ForceIPv4" "WARP IPv6 分流"
assert_strategy "conflict pure-v4 + outip=6only warns" "6only" "true" "" "direct" "direct" '"::/0", "0.0.0.0/0"' "direct" "direct" '"::/0", "0.0.0.0/0"' "no" "ipv6_only" "ForceIPv6" "ForceIPv6" "仅检测到 IPv4 连通性"
assert_strategy "invalid outip warns and falls back" "foo" "true" "true" "direct" "direct" '"::/0", "0.0.0.0/0"' "direct" "direct" '"::/0", "0.0.0.0/0"' "no" "prefer_ipv4" "ForceIPv4v6" "ForceIPv4v6" "未知 outip 值"

# 5. End-to-end JSON template rendering in isolated $TMP
bash -c '
  source "$1"
  outip="4" v4_ok=true v6_ok=true s1outtag=direct s2outtag=direct x1outtag=direct x2outtag=direct
  sip="\"::/0\", \"0.0.0.0/0\"" xip="\"::/0\", \"0.0.0.0/0\""
  egress_nodes="" egress_bind="" egress_rules="" egress_add=""
  egress_init
  cat > "$2/sb.json" << EOF
{
  "outbounds": [${egress_sb_outbounds}{"type": "direct", "tag": "direct"}],
  "route": {
    ${egress_sb_geo_cfg}
    "rules": [
      {"action": "sniff"},
      {"action": "resolve", "strategy": "${sbyx}"},
      ${egress_sb_rules}
      {"ip_cidr": [${sip}], "outbound": "${s1outtag}"}
    ],
    "final": "${s2outtag}"
  }
}
EOF
  cat > "$2/xr.json" << EOF
{
  "outbounds": [
    ${egress_xr_outbounds}
    {"protocol": "freedom", "tag": "direct", "streamSettings": {"sockopt": {"domainStrategy": "${xryx}"}}},
    {"protocol": "freedom", "tag": "warp-out", "streamSettings": {"sockopt": {"domainStrategy": "${wxryx}", "dialerProxy": "x-warp-out"}}}
  ],
  "routing": {
    "domainStrategy": "IPOnDemand",
    "rules": [${egress_xr_rules}{"type": "field", "network": "tcp,udp", "outboundTag": "${x2outtag}"}]
  }
}
EOF
' _ "$TMP/egress_main.sh" "$TMP"

python3 - "$TMP" << 'PY'
import json, sys
sb = json.load(open(f"{sys.argv[1]}/sb.json"))
xr = json.load(open(f"{sys.argv[1]}/xr.json"))
assert sb["route"]["rules"][1]["strategy"] == "prefer_ipv4", sb["route"]["rules"]
assert xr["outbounds"][0]["streamSettings"]["sockopt"]["domainStrategy"] == "ForceIPv4v6", xr["outbounds"]
assert xr["outbounds"][1]["streamSettings"]["sockopt"]["domainStrategy"] == "ForceIPv4v6", xr["outbounds"]
print("ok: rendered sb.json and xr.json valid with IPv4-priority strategy")
PY

# 6. Persistence round-trip for main (vars.env) & container (container_vars.env) in isolated HOME
bash -c '
  export HOME="$1/home_vars"
  mkdir -p "$HOME/agsbx"
  source "$1/vars_save.sh"
  source "$1/vars_merge.sh"
  vlpt=10001; outip=6
  vars_save
  unset vlpt outip
  vars_merge add
  [ "$outip" = "6" ] || { echo "FAIL: add did not inherit outip=6 (got $outip)"; exit 1; }
  vlpt=10002; outip=""
  vars_merge rep
  [ -z "$outip" ] || { echo "FAIL: explicit outip= on rep should clear inherited value (got $outip)"; exit 1; }

  source "$1/container_vars_save.sh"
  source "$1/container_vars_merge.sh"
  vlpt=10003; outip="4only"
  container_vars_save
  unset vlpt outip
  container_vars_merge
  [ "$outip" = "4only" ] || { echo "FAIL: container_vars_merge did not inherit outip=4only (got $outip)"; exit 1; }
' _ "$TMP"
echo "ok: vars.env (add/rep) & container_vars.env persistence round-trip"

# 7. egress_bind IPv4/IPv6 address-family auto-alignment (Sing-box pre-resolve + inet6/inet4_bind_address & Xray sockopt)
bash -c '
  source "$1"
  outip="" v4_ok=true v6_ok=true s1outtag=direct s2outtag=direct x1outtag=direct x2outtag=direct
  sip="\"::/0\", \"0.0.0.0/0\"" xip="\"::/0\", \"0.0.0.0/0\""
  egress_nodes=""
  egress_bind="2001:db8::2,1.2.3.4"
  egress_rules="domain:mail.google.com=>direct;domain:ai.google.com=>bind1;domain:v4only.example=>bind2;inbound:vlpt&domain:claude.ai=>bind1"
  egress_init
  [ -n "$egress_sb_pre_rules" ] || { echo "FAIL: expected non-empty egress_sb_pre_rules when rules target bindN"; exit 1; }
  cat > "$2/sb_bind.json" << EOF
{
  "inbounds": [{"type": "socks", "tag": "s", "listen": "127.0.0.1", "listen_port": 19997}],
  "outbounds": [${egress_sb_outbounds}{"type": "direct", "tag": "direct"}],
  "route": {
    "rules": [
      {"action": "sniff"},
      ${egress_sb_pre_rules}
      {"action": "resolve", "strategy": "${sbyx}"},
      ${egress_sb_rules}
      {"ip_cidr": [${sip}], "outbound": "${s1outtag}"}
    ],
    "final": "${s2outtag}"
  }
}
EOF
  cat > "$2/xr_bind.json" << EOF
{
  "inbounds": [{"port": 19996, "listen": "127.0.0.1", "protocol": "socks"}],
  "outbounds": [
    ${egress_xr_outbounds}
    {"protocol": "freedom", "tag": "direct", "streamSettings": {"sockopt": {"domainStrategy": "${xryx}"}}}
  ],
  "routing": {
    "domainStrategy": "IPOnDemand",
    "rules": [${egress_xr_rules}{"type": "field", "network": "tcp,udp", "outboundTag": "${x2outtag}"}]
  }
}
EOF
  # Also test geosite rule_set emission for sing-box 1.12+ with IPv6 bind1 (no legacy geosite/geoip fields)
  egress_bind="2001:db8::2"
  egress_rules="geosite:youtube=>bind1"
  egress_init
  cat > "$2/sb_geosite.json" << EOF
{
  "inbounds": [{"type": "socks", "tag": "s", "listen": "127.0.0.1", "listen_port": 19995}],
  "outbounds": [${egress_sb_outbounds}{"type": "direct", "tag": "direct"}],
  "route": {
    ${egress_sb_geo_cfg}
    "rules": [
      {"action": "sniff"},
      ${egress_sb_pre_rules}
      {"action": "resolve", "strategy": "${sbyx}"},
      ${egress_sb_rules}
      {"ip_cidr": [${sip}], "outbound": "${s1outtag}"}
    ],
    "final": "${s2outtag}"
  }
}
EOF
  # Mixed geosite=>bind1 and geoip=>direct: geosite stays pre-resolve only, geoip stays post-resolve only
  egress_rules="geosite:youtube=>bind1;geoip:cn=>direct"
  egress_init
  cat > "$2/sb_mixed_geo.json" << EOF
{
  "inbounds": [{"type": "socks", "tag": "s", "listen": "127.0.0.1", "listen_port": 19994}],
  "outbounds": [${egress_sb_outbounds}{"type": "direct", "tag": "direct"}],
  "route": {
    ${egress_sb_geo_cfg}
    "rules": [
      {"action": "sniff"},
      ${egress_sb_pre_rules}
      {"action": "resolve", "strategy": "${sbyx}"},
      ${egress_sb_rules}
      {"ip_cidr": [${sip}], "outbound": "${s1outtag}"}
    ],
    "final": "${s2outtag}"
  }
}
EOF
  # Also ensure egress_sb_pre_rules stays empty when no rule targets bindN
  egress_rules="domain:example.org=>direct"
  egress_init
  [ -z "$egress_sb_pre_rules" ] || { echo "FAIL: expected empty egress_sb_pre_rules when no rule targets bindN"; exit 1; }
' _ "$TMP/egress_main.sh" "$TMP"

python3 - "$TMP" << 'PY'
import json, sys
sb = json.load(open(f"{sys.argv[1]}/sb_bind.json"))
xr = json.load(open(f"{sys.argv[1]}/xr_bind.json"))
sb_geo = json.load(open(f"{sys.argv[1]}/sb_geosite.json"))
sb_mix = json.load(open(f"{sys.argv[1]}/sb_mixed_geo.json"))
sb_out = {o["tag"]: o for o in sb["outbounds"]}
assert sb_out["bind1"].get("inet6_bind_address") == "2001:db8::2" and "bind_address" not in sb_out["bind1"], sb_out["bind1"]
assert sb_out["bind2"].get("inet4_bind_address") == "1.2.3.4" and "bind_address" not in sb_out["bind2"], sb_out["bind2"]
xr_out = {o["tag"]: o for o in xr["outbounds"]}
assert xr_out["bind1"]["sendThrough"] == "2001:db8::2" and xr_out["bind1"]["streamSettings"]["sockopt"]["domainStrategy"] == "ForceIPv6", xr_out["bind1"]
assert xr_out["bind2"]["sendThrough"] == "1.2.3.4" and xr_out["bind2"]["streamSettings"]["sockopt"]["domainStrategy"] == "ForceIPv4", xr_out["bind2"]
rules = sb["route"]["rules"]
idx_global = next(i for i, r in enumerate(rules) if r.get("action") == "resolve" and set(r.keys()) == {"action", "strategy"})
assert rules[idx_global]["strategy"] == "prefer_ipv4"
pre = rules[1:idx_global]
assert pre[0] == {"domain_suffix": ["mail.google.com"], "action": "resolve", "strategy": "prefer_ipv4"}, pre
assert pre[1] == {"domain_suffix": ["mail.google.com"], "outbound": "direct"}, pre
assert pre[2] == {"domain_suffix": ["ai.google.com"], "action": "resolve", "strategy": "ipv6_only"}, pre
assert pre[3] == {"domain_suffix": ["ai.google.com"], "outbound": "bind1"}, pre
assert pre[4] == {"domain_suffix": ["v4only.example"], "action": "resolve", "strategy": "ipv4_only"}, pre
assert pre[5] == {"domain_suffix": ["v4only.example"], "outbound": "bind2"}, pre
assert pre[7]["outbound"] == "bind1" and pre[6]["strategy"] == "ipv6_only", pre[6:8]
assert rules[idx_global+1:] == [{"ip_cidr": ["::/0", "0.0.0.0/0"], "outbound": "direct"}], rules[idx_global+1:]
# Verify sing-box 1.12+ rule_set migration and deduplication for geosite:youtube=>bind1
assert "geoip" not in sb_geo["route"] and "geosite" not in sb_geo["route"], sb_geo["route"]
rs = {r["tag"]: r for r in sb_geo["route"]["rule_set"]}
assert rs["geosite-youtube"]["format"] == "binary" and rs["geosite-youtube"]["path"].endswith("geosite-youtube.srs"), rs
g_rules = sb_geo["route"]["rules"]
assert len(g_rules) == 5, g_rules
assert g_rules == [
    {"action": "sniff"},
    {"rule_set": ["geosite-youtube"], "action": "resolve", "strategy": "ipv6_only"},
    {"rule_set": ["geosite-youtube"], "outbound": "bind1"},
    {"action": "resolve", "strategy": "prefer_ipv4"},
    {"ip_cidr": ["::/0", "0.0.0.0/0"], "outbound": "direct"},
], g_rules
# Verify mixed geosite (pre-resolve only) + geoip (post-resolve only)
m_rules = sb_mix["route"]["rules"]
assert m_rules == [
    {"action": "sniff"},
    {"rule_set": ["geosite-youtube"], "action": "resolve", "strategy": "ipv6_only"},
    {"rule_set": ["geosite-youtube"], "outbound": "bind1"},
    {"action": "resolve", "strategy": "prefer_ipv4"},
    {"rule_set": ["geoip-cn"], "outbound": "direct"},
    {"ip_cidr": ["::/0", "0.0.0.0/0"], "outbound": "direct"},
], m_rules
print("ok: egress_bind IPv4/IPv6 pre-resolve, bind fields, and sing-box 1.12+ rule_set aligned")
PY

if [ -x /root/agsbx/sing-box ]; then
  /root/agsbx/sing-box check -c "$TMP/sb_bind.json" || { echo "FAIL: real sing-box check failed on sb_bind.json"; exit 1; }
  echo "ok: sing-box check passed on sb_bind.json"
fi
if [ -x /root/agsbx/xray ]; then
  /root/agsbx/xray run -test -format json -c "$TMP/xr_bind.json" >/dev/null || { echo "FAIL: real xray test failed on xr_bind.json"; exit 1; }
  echo "ok: xray run -test passed on xr_bind.json"
fi

# Verify host /root/agsbx was completely untouched
HOST_AGSBX_MTIME_AFTER=$(stat -c '%Y' /root/agsbx 2>/dev/null || echo "none")
[ "$HOST_AGSBX_MTIME_BEFORE" = "$HOST_AGSBX_MTIME_AFTER" ] || { echo "FAIL: host /root/agsbx changed during test!"; exit 1; }
echo "PASS: outip (all strategies, WARP coordination, overrides, persistence, isolated sandbox)"
