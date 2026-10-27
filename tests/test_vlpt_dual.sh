#!/bin/bash
# vlpt dual-support: vlpt_kernel=auto/xray/sb, migration by default,
# explicit xray keeps the old link. No network, no real install.
# 1. Built files carry the new logic; upstream files are untouched.
# 2. vlpt_on logic harness: extract the computation block from the built
#    main script and run it under the protocol combinations that matter.
# 3. sing-box check on a vl-reality-sb inbound (skipped if the local
#    sing-box binary is not present, e.g. on a fresh checkout).
set -u
cd "$(dirname "$0")/.." || exit 1
FAIL=0
F=argosbx.sh
C=container/nodejs/start.sh
U=upstream/argosbx.sh
CU=upstream/container/nodejs/start.sh
for needle in 'vl-reality-sb' 'vlpt_on' 'vlpt_kernel' 'vlpt_pbk'; do
  grep -Fq "$needle" "$U" && { echo "FAIL: upstream main contains $needle"; FAIL=1; }
  grep -Fq "$needle" "$CU" && { echo "FAIL: upstream container contains $needle"; FAIL=1; }
  grep -Fq "$needle" "$F" || { echo "FAIL: built main missing $needle"; FAIL=1; }
  grep -Fq "$needle" "$C" || { echo "FAIL: built container missing $needle"; FAIL=1; }
done
for needle in 'vlpt_on" != "sb"' 'vlpt_on" != "xray"' 'vlp=vlptargo'; do
  grep -Fq "$needle" "$F" || { echo "FAIL: built main missing $needle"; FAIL=1; }
done
grep -Fq 'vlpt_on" != "sb"' "$C" || { echo "FAIL: built container missing vlpt_on sb branch"; FAIL=1; }
grep -Fq 'vlpt_on" != "xray"' "$C" || { echo "FAIL: built container missing vlpt_on xray branch"; FAIL=1; }
grep -Fq 'id="vlpt_kernel"' index.html || { echo "FAIL: generator missing vlpt_kernel select"; FAIL=1; }
[ "$(grep -c 'id="vlpt_kernel"' index.html)" = "1" ] || { echo "FAIL: generator has duplicate vlpt_kernel elements"; FAIL=1; }
grep -Fq '<option value="xray">强制 Xray' index.html || { echo "FAIL: generator missing vlpt_kernel xray option"; FAIL=1; }
# vlpt must NOT sit in the Xray group any more: it lives in its own
# dual-kernel group, which comes first, before the Xray group.
grep -Fq '双内核可选协议' index.html || { echo "FAIL: generator missing dual-kernel group"; FAIL=1; }
awk '/双内核可选协议/,/Xray可选协议/' index.html | grep -Fq 'data-proto="vlpt"' || { echo "FAIL: vlpt not in dual-kernel group"; FAIL=1; }
awk '/双内核可选协议/,/Xray可选协议/' index.html | grep -Fq 'id="vlpt_kernel"' || { echo "FAIL: vlpt_kernel not next to vlpt"; FAIL=1; }
awk '/Xray可选协议/,/Singbox可选协议/' index.html | grep -Fq 'data-proto="vlpt"' && { echo "FAIL: vlpt still listed under Xray group"; FAIL=1; }
grep -Fq "vlpt_kernel" modules/vars.sh || { echo "FAIL: vars_save missing vlpt_kernel"; FAIL=1; }
grep -Fq "vlpt_kernel" modules/container-vars.sh || { echo "FAIL: container_vars_save missing vlpt_kernel"; FAIL=1; }
# xhpt link still uses the xray keypair (only vlpt display switches)
grep -Fq 'vl_xh_link="vless://$uuid@$reality_addr:$port_xh?encryption=$enkey&flow=xtls-rprx-vision&security=reality&sni=$ym_vl_re&fp=chrome&pbk=$public_key_x&sid=$short_id_x&type=xhttp' "$F" || { echo "FAIL: xhpt link keypair changed"; FAIL=1; }
# vlpt display must NOT use the xray keypair directly any more
grep -Fq 'pbk=$public_key_x&sid=$short_id_x&type=tcp&headerType=none' "$F" && { echo "FAIL: vlpt link still uses xray keypair"; FAIL=1; }

# 2. vlpt_on harness (main script, flags are yes/unset)
BLOCK=$(awk '/^vlpt_on=""$/ {p=1} p {print} /^fi$/ && p {exit}' "$F")
[ -n "$BLOCK" ] || { echo "FAIL: could not extract vlpt_on block"; FAIL=1; }
run_case() { # $1=label $2=vlpt_kernel_or_EMPTY $3=want $4..=flags to set to yes
  local label="$1" k="$2" want="$3"; shift 3
  vlp=yes; xhp=""; vxp=""; vwp=""; xup=""; xcp=""; nvp=""; tup=""; anp=""; arp=""; ssp=""; vlpt_kernel=""
  for f in "$@"; do eval "$f=yes"; done
  [ "$k" != "EMPTY" ] && vlpt_kernel="$k"
  eval "$BLOCK"
  [ "$vlpt_on" = "$want" ] || { echo "FAIL: $label vlpt_on=[$vlpt_on] want [$want]"; FAIL=1; }
}
run_case "vlpt+tuic auto" EMPTY sb tup
run_case "vlpt alone auto" EMPTY xray
run_case "vlpt+xhttp auto" EMPTY xray xhp
run_case "vlpt+tuic explicit xray" xray xray tup
run_case "vlpt+xhttp explicit sb" sb sb xhp
run_case "vlpt+tuic invalid kernel" bogus sb tup
# no vlpt at all -> empty, regardless of other protocols
vlp=""; xhp=""; vxp=""; vwp=""; xup=""; xcp=""; nvp=""; tup=yes; anp=""; arp=""; ssp=""; vlpt_kernel=""
eval "$BLOCK"
[ -z "$vlpt_on" ] || { echo "FAIL: no-vlpt vlpt_on=[$vlpt_on] want empty"; FAIL=1; }
# ins() branch decisions under the same cases (conditions as in built file)
# vlpt+tuic auto: sb only (first branch false via vlpt_on=sb, second true)
vlp=yes; tup=yes; xhp=""; vxp=""; vwp=""; xup=""; xcp=""; nvp=""; anp=""; arp=""; ssp=""; vlpt_kernel=""; eval "$BLOCK"
if [ "$vlpt_on" = "sb" ] && { [ "$nvp" != yes ] && [ "$tup" != yes ] && [ "$anp" != yes ] && [ "$arp" != yes ] && [ "$ssp" != yes ] && [ "$vlpt_on" != "sb" ]; }; then echo "FAIL: vlpt+tuic auto should not be xray-only"; FAIL=1; fi
if [ "$xhp" != yes ] && [ "$vxp" != yes ] && [ "$vwp" != yes ] && [ "$xup" != yes ] && [ "$xcp" != yes ] && [ "$vlpt_on" != "xray" ]; then :; else echo "FAIL: vlpt+tuic auto should be sb-only"; FAIL=1; fi
# vlpt alone auto: xray only
tup=""; eval "$BLOCK"
if [ "$nvp" != yes ] && [ "$tup" != yes ] && [ "$anp" != yes ] && [ "$arp" != yes ] && [ "$ssp" != yes ] && [ "$vlpt_on" != "sb" ]; then :; else echo "FAIL: vlpt alone auto should be xray-only"; FAIL=1; fi
# vlpt+xhttp explicit sb: both (first false via vlpt_on=sb, second false via xhp)
xhp=yes; vlpt_kernel=sb; eval "$BLOCK"
if [ "$nvp" != yes ] && [ "$tup" != yes ] && [ "$anp" != yes ] && [ "$arp" != yes ] && [ "$ssp" != yes ] && [ "$vlpt_on" != "sb" ]; then echo "FAIL: vlpt+xhttp sb should not be xray-only"; FAIL=1; fi
if [ "$xhp" != yes ] && [ "$vxp" != yes ] && [ "$vwp" != yes ] && [ "$xup" != yes ] && [ "$xcp" != yes ] && [ "$vlpt_on" != "xray" ]; then echo "FAIL: vlpt+xhttp sb should not be sb-only"; FAIL=1; fi

# 3. sing-box check on a vl-reality-sb inbound
SB=/tmp/kernels/sing-box
if [ -x "$SB" ]; then
  td=$(mktemp -d); trap 'rm -rf "$td"' EXIT
  kp=$("$SB" generate reality-keypair)
  pk=$(echo "$kp" | awk '/PrivateKey/ {print $2}' | tr -d '"')
  sid=$("$SB" generate rand --hex 4)
  cat > "$td/sb.json" <<EOF
{
  "inbounds": [
    {
        "type": "vless",
        "tag": "vl-reality-sb",
        "listen": "::",
        "listen_port": 23456,
        "users": [{ "uuid": "11111111-2222-3333-4444-555555555555", "flow": "xtls-rprx-vision" }],
        "tls": {
            "enabled": true,
            "server_name": "apple.com",
            "reality": {
                "enabled": true,
                "handshake": { "server": "apple.com", "server_port": 443 },
                "private_key": "$pk",
                "short_id": ["$sid"]
            }
        }
    }
  ]
}
EOF
  "$SB" check -c "$td/sb.json" >/dev/null 2>&1 || { echo "FAIL: sing-box check rejected vl-reality-sb inbound"; FAIL=1; }
else
  echo "SKIP: sing-box binary not present, vl-reality-sb check skipped"
fi

[ "$FAIL" = 0 ] && echo "test_vlpt_dual: PASS" || { echo "test_vlpt_dual: FAIL"; exit 1; }
