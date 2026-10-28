#!/bin/bash
# Self-signed pinning + vmess-ws-tls (main + container + generator).
# No network, no real install, no kernel startup (sing-box check only
# if /tmp/kernels/sing-box is present, otherwise skipped).
set -u
cd "$(dirname "$0")/.." || exit 1
FAIL=0
F=argosbx.sh
C=container/nodejs/start.sh
U=upstream/argosbx.sh
UC=upstream/container/nodejs/start.sh
need() { # $1=file $2=needle
  grep -Fq "$2" "$1" || { echo "FAIL: $1 missing: $2"; FAIL=1; }
}
absent_up() { # $1=file $2=needle (must NOT be in upstream)
  grep -Fq "$2" "$1" && { echo "FAIL: upstream $1 contains private: $2"; FAIL=1; }
}
# 1. String presence, built files only, upstream pristine
for needle in "pin_sha" "pin_spki" "cl_pin_line" "sb_pin_field" "certificate_public_key_sha256" \
             "xrsbvmtls" "vmess-tls-xr" "vmess-tls-sb" "sbvmtlspt" "clvmtlspt" "vmtls" \
             "skip-cert-verify: \$cl_skip" '"insecure": $sb_insecure$sb_pin_field,'; do
  need "$F" "$needle"
done
need "$C" "xrsbvmtls"
need "$C" "vmess-tls-xr"
need "$C" "vmess-tls-sb"
need "$C" 'hy2_c_pin="&pinSHA256=$hy2_c_sha"'
need "index.html" 'data-proto="vmtls"'
need "index.html" "'vmtls'"
absent_up "$U" "pin_sha"
absent_up "$U" "xrsbvmtls"
absent_up "$UC" "xrsbvmtls"
# Counts: Clash skip lines = 8 old + 6 new proto-more (xupt, xcpt, anpt,
# tupt, hypt, vmtls); sing-box insecure = 4 old + 4 new proto-more
# (anpt, tupt, hypt, vmtls). Other proto-more Clash/SB nodes have no
# skip/insecure field (shadowsocks, vmess-ws, naive, any-reality).
ncl=$(grep -c 'skip-cert-verify: $cl_skip' "$F"); [ "$ncl" = "14" ] || { echo "FAIL: Clash pinned skip lines [$ncl] want 14"; FAIL=1; }
nsb=$(grep -c '"insecure": $sb_insecure$sb_pin_field,' "$F"); [ "$nsb" = "8" ] || { echo "FAIL: sing-box pinned insecure lines [$nsb] want 8"; FAIL=1; }
# Old skip/insecure variables must be gone from subscriptions (only in
# pin-compute fallback assignment and in non-subscription contexts)
[ "$(grep -c 'skip-cert-verify: $msins' "$F")" = "0" ] || { echo "FAIL: old Clash skip \$msins remains"; FAIL=1; }
[ "$(grep -c '"insecure": $msins,' "$F")" = "0" ] || { echo "FAIL: old sing-box insecure \$msins remains"; FAIL=1; }
# Vars persistence
need modules/vars.sh "vmtls"
need modules/container-vars.sh "vmtls"
need "$F" 'export port_vm_tls=${vmtls'
need "$F" 'get_func sbvmtlspt;'
need "$F" 'get_func clvmtlspt;'

# 2. Pin computation, self-signed case
TD=$(mktemp -d); mkdir -p "$TD/agsbx/selfsigned"
openssl req -x509 -newkey rsa:2048 -keyout "$TD/agsbx/selfsigned/private.key" -out "$TD/agsbx/selfsigned/cert.crt" -days 36500 -nodes -subj "/CN=www.bing.com" -addext "subjectAltName=DNS:www.bing.com" >/dev/null 2>&1
openssl x509 -in "$TD/agsbx/selfsigned/cert.crt" -outform DER 2>/dev/null | sha256sum | cut -d' ' -f1 > "$TD/agsbx/SHA256.txt"
SPKI=$(openssl x509 -in "$TD/agsbx/selfsigned/cert.crt" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform der 2>/dev/null | openssl dgst -sha256 -binary 2>/dev/null | openssl enc -base64 2>/dev/null | tr -d '\n')
# Extract the pin block from the built file (pin_sha= ... sb_pin_field=)
awk '/^pin_sha=""; pin_spki=""; pin_on=0/{f=1} f{print} /^if \[ "\$pin_on" = "1" \]; then sb_pin_field/{exit}' "$F" > "$TD/pin.sh"
HOME="$TD" msins=true bash -c 'source "$0"; echo "pin_on=$pin_on cl_skip=$cl_skip sb_insecure=$sb_insecure"; echo "cl_pin_line=$cl_pin_line"; echo "sb_pin_field=$sb_pin_field"' "$TD/pin.sh" > "$TD/pin.out" 2>&1
grep -q "pin_on=1 cl_skip=false sb_insecure=false" "$TD/pin.out" || { echo "FAIL: pinned pin_on/cl_skip/sb_insecure:"; cat "$TD/pin.out"; FAIL=1; }
grep -Fq "fingerprint: $(cat "$TD/agsbx/SHA256.txt")" "$TD/pin.out" || { echo "FAIL: Clash fingerprint != SHA256.txt"; FAIL=1; }
grep -Fq "\"certificate_public_key_sha256\": [\"$SPKI\"]" "$TD/pin.out" || { echo "FAIL: sing-box SPKI pin != computed SPKI"; FAIL=1; }
# Domain case: no pin, normal CA verification values
HOME="$TD" msins=false bash -c 'source "$0"; echo "pin_on=$pin_on cl_skip=$cl_skip sb_insecure=$sb_insecure sb_pin_field=[$sb_pin_field] cl_pin_line=[$cl_pin_line]"' "$TD/pin.sh" > "$TD/pin2.out" 2>&1
grep -q "pin_on=0 cl_skip=false sb_insecure=false sb_pin_field=\[\] cl_pin_line=\[\]" "$TD/pin2.out" || { echo "FAIL: domain case must not pin:"; cat "$TD/pin2.out"; FAIL=1; }

# 3. vmtls inbound fragments are valid JSON (Xray + sing-box, main)
extract_fn() { # $1=file $2=fnname $3=out
  awk -v fn="$2" '$0 ~ "^"fn"\\(\\)\\{"{f=1} f{print} f && /^}$/{exit}' "$1" > "$3"
}
extract_fn "$F" "xrsbvmtls" "$TD/vmtls_fn.sh"
TD2=$(mktemp -d); mkdir -p "$TD2/agsbx"
HOME="$TD2" uuid="11111111-2222-3333-4444-555555555555" port_vm_tls="" certificateHTA="/tmp/cert.crt" keyHTA="/tmp/private.key" vmt=1 bash -c 'source "$0"; xrsbvmtls' "$TD/vmtls_fn.sh" >/dev/null 2>&1 || true
# The function writes to xr.json when it exists, else sb.json; force xr first
: > "$TD2/agsbx/xr.json"
HOME="$TD2" uuid="11111111-2222-3333-4444-555555555555" port_vm_tls="" certificateHTA="/tmp/cert.crt" keyHTA="/tmp/private.key" vmt=1 bash -c 'source "$0"; xrsbvmtls' "$TD/vmtls_fn.sh" >/dev/null 2>&1
python3 - "$TD2/agsbx/xr.json" <<'PY' || { echo "FAIL: Xray vmtls fragment not valid JSON"; FAIL=1; }
import json, sys
raw = open(sys.argv[1]).read().rstrip()
if raw.endswith(','): raw = raw[:-1]
objs = json.loads('[' + raw + ']')
o = objs[0]
assert o['tag'] == 'vmess-tls-xr', o
assert o['protocol'] == 'vmess', o
assert o['streamSettings']['security'] == 'tls', o
assert o['streamSettings']['network'] == 'ws', o
assert o['streamSettings']['wsSettings']['path'].endswith('-vmtls'), o
assert o['streamSettings']['tlsSettings']['certificates'][0]['certificateFile'] == '/tmp/cert.crt', o
PY
rm -f "$TD2/agsbx/xr.json"
HOME="$TD2" uuid="11111111-2222-3333-4444-555555555555" port_vm_tls="" certificateHTA="/tmp/cert.crt" keyHTA="/tmp/private.key" vmt=1 bash -c 'source "$0"; xrsbvmtls' "$TD/vmtls_fn.sh" >/dev/null 2>&1
python3 - "$TD2/agsbx/sb.json" <<'PY' || { echo "FAIL: sing-box vmtls fragment not valid JSON"; FAIL=1; }
import json, sys
raw = open(sys.argv[1]).read().rstrip()
if raw.endswith(','): raw = raw[:-1]
objs = json.loads('[' + raw + ']')
o = objs[0]
assert o['tag'] == 'vmess-tls-sb', o
assert o['type'] == 'vmess', o
assert o['transport']['type'] == 'ws', o
assert o['transport']['path'].endswith('-vmtls'), o
assert o['tls']['enabled'] is True, o
assert o['tls']['certificate_path'] == '/tmp/cert.crt', o
PY
# sing-box check on the sb inbound, if a binary is available
if [ -x /tmp/kernels/sing-box ]; then
  # Build a minimal sing-box config around the fragment
  frag=$(cat "$TD2/agsbx/sb.json")
  cat > "$TD2/sbcheck.json" <<EOF
{"log": {"level": "error"}, "inbounds": [${frag%,}], "outbounds": [{"type": "direct", "tag": "direct"}]}
EOF
  /tmp/kernels/sing-box check -c "$TD2/sbcheck.json" >/dev/null 2>&1 || { echo "FAIL: sing-box check rejects vmtls inbound"; FAIL=1; }
fi

# 4. sb/cl vmtls templates render valid JSON / YAML-shaped output when pinned
extract_fn "$F" "sbvmtlspt" "$TD/sbvmtls_fn.sh"
HOME="$TD" add="1.2.3.4" sni="www.bing.com" port_vm_tls="12345" uuid="11111111-2222-3333-4444-555555555555" hostname="test" sxname="" sb_insecure=false sb_pin_field=", \"certificate_public_key_sha256\": [\"$SPKI\"]" bash -c 'source "$0"; sbvmtlspt' "$TD/sbvmtls_fn.sh" > "$TD/sbout.json" 2>&1
# sbout is a fragment ending with a comma; strip only the last line's comma
sed '$ s/,$//' "$TD/sbout.json" > "$TD/sbout2.json"
python3 -c "import json,sys; o=json.load(open(sys.argv[1])); assert o['type']=='vmess' and o['tls']['enabled'] is True and o['tls']['insecure'] is False and 'certificate_public_key_sha256' in o['tls'] and o['tls']['server_name']=='www.bing.com' and o['transport']['path'].endswith('-vmtls'), o" "$TD/sbout2.json" || { echo "FAIL: sbvmtlspt fields wrong"; cat "$TD/sbout.json"; FAIL=1; }
extract_fn "$F" "clvmtlspt" "$TD/clvmtls_fn.sh"
HOME="$TD" add="1.2.3.4" sni="www.bing.com" port_vm_tls="12345" uuid="11111111-2222-3333-4444-555555555555" hostname="test" sxname="" cl_skip=false cl_pin_line="  fingerprint: $(cat "$TD/agsbx/SHA256.txt")" bash -c 'source "$0"; clvmtlspt' "$TD/clvmtls_fn.sh" > "$TD/clout.yml" 2>&1
grep -Fq "skip-cert-verify: false" "$TD/clout.yml" || { echo "FAIL: clvmtlspt skip not false"; FAIL=1; }
grep -Fq "fingerprint: $(cat "$TD/agsbx/SHA256.txt")" "$TD/clout.yml" || { echo "FAIL: clvmtlspt fingerprint missing"; FAIL=1; }
grep -Fq "tls: true" "$TD/clout.yml" || { echo "FAIL: clvmtlspt tls not true"; FAIL=1; }

rm -rf "$TD" "$TD2"
[ "$FAIL" = "0" ] || exit 1
echo "PASS: pin + vmess-ws-tls"
