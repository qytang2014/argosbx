#!/bin/bash
# Non-TLS protocols use domain_addr (ym when set, IP otherwise);
# TLS (via $add) and CDN links are untouched.
set -u
cd "$(dirname "$0")/.." || exit 1
FAIL=0
for link in 'vl_vx_link="vless://$uuid@$domain_addr:$port_vx' \
            'vl_vw_link="vless://$uuid@$domain_addr:$port_vw' \
            '2022-blake3-aes-128-gcm:$sskey@$domain_addr:$port_ss' \
            '\"add\": \"$domain_addr\", \"port\": \"$port_vm_ws\"'; do
  grep -Fq "$link" argosbx.sh || { echo "FAIL: missing $link"; FAIL=1; }
done
# ss + vmess client configs
grep -Fq '      "tag": "${sxname}Shadowsocks-2022-$hostname",' argosbx.sh || FAIL=1
grep -A1 'Shadowsocks-2022-$hostname' argosbx.sh | grep -Fq '"server": "$domain_addr"' || { echo "FAIL: ss sb config"; FAIL=1; }
grep -Fq '  server: $domain_addr' argosbx.sh || { echo "FAIL: ss/vm clash config"; FAIL=1; }
# TLS still via $add, CDN still via cdnip1/shopify
grep -Fq 'vl_xc2_link="vless://$uuid@$add:$port_xc' argosbx.sh || { echo "FAIL: TLS link changed"; FAIL=1; }
grep -Fq 'vl_vx_cdn_link="vless://$uuid@$cdnip1:$port_vx' argosbx.sh || { echo "FAIL: CDN link changed"; FAIL=1; }
grep -Fq '\"add\": \"www.shopify.com\"' argosbx.sh || { echo "FAIL: vm CDN link changed"; FAIL=1; }
# No live (uncommented) link still uses $server_ip as address
if grep -v '^#' argosbx.sh | grep -Eq '_link=.*\$server_ip'; then echo "FAIL: live link still uses server_ip"; FAIL=1; fi
# Isolation: domain_addr fallback
run_case() {
  local td; td=$(mktemp -d); mkdir -p "$td/agsbx"
  [ "$2" != "EMPTY" ] && printf '%s' "$2" > "$td/agsbx/ym"
  local out
  out=$(HOME="$td" server_ip="1.2.3.4" ym="$3" bash -c "source modules/reality-addr.sh; echo \"\$domain_addr\"")
  [ "$out" = "$4" ] || { echo "FAIL: $1 got [$out] want [$4]"; FAIL=1; }
  rm -rf "$td"
}
run_case "ym file wins" "node.example.com" "" "node.example.com"
run_case "no ym -> IP" "EMPTY" "" "1.2.3.4"
[ $FAIL -eq 0 ] && echo "PASS: plain (non-TLS) address (ym, fallback IP, TLS/CDN untouched)"
exit $FAIL
