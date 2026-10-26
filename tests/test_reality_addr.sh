#!/bin/bash
# Reality address = ym (domain) when set, server IP otherwise; SNI stays reym.
set -u
cd "$(dirname "$0")/.." || exit 1
FAIL=0
# 1. Built script: Reality links + client configs use $reality_addr, SNI still $ym_vl_re
for link in 'vl_xh_link="vless://$uuid@$reality_addr:$port_xh' \
            'vl_link="vless://$uuid@$reality_addr:$port_vl_re' \
            'ar_link="anytls://$uuid@$reality_addr:$port_ar'; do
  grep -Fq "$link" argosbx.sh || { echo "FAIL: missing $link"; FAIL=1; }
done
grep -Fq '"server": "$reality_addr"' argosbx.sh || { echo "FAIL: sb reality server not reality_addr"; FAIL=1; }
grep -Fq 'server: $reality_addr' argosbx.sh || { echo "FAIL: clash reality server not reality_addr"; FAIL=1; }
for link in 'vl_xh_link="vless://$uuid@$reality_addr' 'vl_link="vless://$uuid@$reality_addr' 'ar_link="anytls://$uuid@$reality_addr'; do
  grep -Fq "$link" argosbx.sh || true
done
grep -Fq 'reality_addr="$domain_addr"' argosbx.sh || { echo "FAIL: reality_addr not alias of domain_addr"; FAIL=1; }
# SNI unchanged on all three Reality links
for l in vl_xh_link vl_link ar_link; do
  grep -F "$l=" argosbx.sh | grep -q 'sni=$ym_vl_re' || { echo "FAIL: $l SNI changed"; FAIL=1; }
done
# 2. Isolation: run only the reality_addr snippet with fake HOME
# Source the whole module: it only defines domain_addr/reality_addr.
run_case() { # $1=label $2=ym_file_content_or_EMPTY $3=ym_var $4=expected
  local td; td=$(mktemp -d); mkdir -p "$td/agsbx"
  [ "$2" != "EMPTY" ] && printf '%s' "$2" > "$td/agsbx/ym"
  local out
  out=$(HOME="$td" server_ip="1.2.3.4" ym="$3" bash -c "source modules/reality-addr.sh; echo \"\$reality_addr\"")
  [ "$out" = "$4" ] || { echo "FAIL: $1 got [$out] want [$4]"; FAIL=1; }
  rm -rf "$td"
}
run_case "ym file wins" "node.example.com" "" "node.example.com"
run_case "ym var fallback" "EMPTY" "var.example.com" "var.example.com"
run_case "no ym -> IP" "EMPTY" "" "1.2.3.4"
[ $FAIL -eq 0 ] && echo "PASS: reality address (ym, fallback IP, SNI reym)"
exit $FAIL
