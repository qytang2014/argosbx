#!/bin/bash
# Container start.sh: layered build + domain cert + domain address.
# No network, no real container, no system writes (all in temp HOME).
set -u
cd "$(dirname "$0")/.." || exit 1
FAIL=0
F=container/nodejs/start.sh
U=upstream/container/nodejs/start.sh
# 1. Upstream pristine, built file carries private changes
for needle in "qytang2014" "domain_addr" "container_cert_setup"; do
  grep -Fq "$needle" "$U" && { echo "FAIL: upstream container contains $needle"; FAIL=1; }
  grep -Fq "$needle" "$F" || { echo "FAIL: built container missing $needle"; FAIL=1; }
done
# Public key download removed from built file (upstream still has it)
grep -Fq "releases/download/argosbx/private.key" "$U" || { echo "FAIL: upstream container missing public-key fallback (expected)"; FAIL=1; }
grep -Fq "releases/download/argosbx/private.key" "$F" && { echo "FAIL: built container still downloads public private.key"; FAIL=1; }
grep -Fq "releases/download/argosbx/cert.pem" "$F" && { echo "FAIL: built container still downloads public cert.pem"; FAIL=1; }
# Kernel binary downloads stay on original release
grep -Fq "releases/download/argosbx/sing-box" "$F" || { echo "FAIL: sing-box download lost"; FAIL=1; }
# Links: Reality + non-TLS use domain_addr, TLS uses add/sni/tls_ins, CDN/Argo untouched
for link in 'vl_xh_link="vless://$uuid@$domain_addr:$xhpt' 'vl_link="vless://$uuid@$domain_addr:$vlpt' \
            'ar_link="anytls://$uuid@$domain_addr:$arpt' 'vl_vx_link="vless://$uuid@$domain_addr:$vxpt' \
            'vl_vw_link="vless://$uuid@$domain_addr:$vwpt' 'hy2_link="hysteria2://$uuid@$add:$hypt?security=tls&alpn=h3&insecure=$tls_ins&sni=$sni' \
            'an_link="anytls://$uuid@$add:$anpt?insecure=$tls_ins'; do
  grep -Fq "$link" "$F" || { echo "FAIL: missing $link"; FAIL=1; }
done
grep -Fq 'vl_vx_cdn_link="vless://$uuid@yg' "$F" || { echo "FAIL: CDN link changed"; FAIL=1; }
grep -Fq 'sni=$reym' "$F" || { echo "FAIL: container Reality SNI changed"; FAIL=1; }
# 2. Cert setup isolation: source only the module function
mkcert() { # $1=dir $2=domain
  mkdir -p "$1/agsbx/cert"
  openssl req -x509 -newkey rsa:2048 -keyout "$1/agsbx/cert/private.key" -out "$1/agsbx/cert/cert.crt" -days 2 -nodes -subj "/CN=$2" -addext "subjectAltName=DNS:$2" >/dev/null 2>&1
}
run_cert() { # $1=label $2=ym $3=cert_domain_or_EMPTY $4=expect_flag
  local td; td=$(mktemp -d); mkdir -p "$td/agsbx"
  [ "$3" != "EMPTY" ] && mkcert "$td" "$3"
  HOME="$td" ym="$2" bash -c "source modules/container-cert.sh; container_cert_setup" >/dev/null 2>&1
  local flag="absent"; [ -f "$td/agsbx/domain_cert_ready" ] && flag=$(cat "$td/agsbx/domain_cert_ready")
  [ "$flag" = "$4" ] || { echo "FAIL: $1 flag [$flag] want [$4]"; FAIL=1; }
  if [ "$4" = "1" ]; then
    [ -L "$td/agsbx/selfsigned/cert.pem" ] || { echo "FAIL: $1 cert.pem not symlink"; FAIL=1; }
    [ -L "$td/agsbx/selfsigned/private.key" ] || { echo "FAIL: $1 private.key not symlink"; FAIL=1; }
  else
    [ -L "$td/agsbx/selfsigned/cert.pem" ] && { echo "FAIL: $1 cert.pem should not be symlink on fallback"; FAIL=1; }
    [ -f "$td/agsbx/selfsigned/private.key" ] || { echo "FAIL: $1 self-signed key missing"; FAIL=1; }
  fi
  rm -rf "$td"
}
run_cert "domain cert matches ym" "node.example.com" "node.example.com" "1"
run_cert "domain cert, ym from cert" "" "cert.example.com" "1"
run_cert "domain cert mismatches ym" "node.example.com" "other.example.com" "absent"
run_cert "no domain cert" "node.example.com" "EMPTY" "absent"
# Old host cert location (argosbx/cert) is still honoured as a fallback
td_old=$(mktemp -d); mkdir -p "$td_old/agsbx" "$td_old/argosbx/cert"
openssl req -x509 -newkey rsa:2048 -keyout "$td_old/argosbx/cert/private.key" -out "$td_old/argosbx/cert/cert.crt" -days 2 -nodes -subj "/CN=node.example.com" -addext "subjectAltName=DNS:node.example.com" >/dev/null 2>&1
HOME="$td_old" ym="node.example.com" bash -c "source modules/container-cert.sh; container_cert_setup" >/dev/null 2>&1
[ -f "$td_old/agsbx/domain_cert_ready" ] && [ "$(cat "$td_old/agsbx/domain_cert_ready")" = "1" ] || { echo "FAIL: old host cert fallback flag"; FAIL=1; }
[ -L "$td_old/agsbx/selfsigned/cert.pem" ] || { echo "FAIL: old host cert fallback symlink"; FAIL=1; }
rm -rf "$td_old"
[ $FAIL -eq 0 ] && echo "PASS: container (layered build, domain cert, domain address, no public key download)"
exit $FAIL
