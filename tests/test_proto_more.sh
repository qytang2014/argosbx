#!/bin/bash
# Other protocols comma multi-instance: expansion, install loops,
# display loops, ufw tag scan, egress aliases.
# Mock-only: extracts functions/modules from the generated script
# and runs them in a temp HOME, never a real install.
set -u
cd "$(dirname "$0")/.." || exit 1
if ! command -v shuf >/dev/null 2>&1; then
  SHUF_DIR="$(mktemp -d)"; cat > "$SHUF_DIR/shuf" << 'EOF'
#!/bin/bash
python3 -c 'import random; print(random.randint(10000, 65535))'
EOF
  chmod +x "$SHUF_DIR/shuf"; export PATH="$SHUF_DIR:$PATH"
fi
fail=0
ok(){ echo "ok: $1"; }
bad(){ echo "FAIL: $1"; fail=1; }

# --- comma expansion ---
extract(){ python3 - "$1" << 'PY'
import sys, re
t=open('argosbx.sh').read()
# proto-comma block is between the vlpt comma case and the export uuid line
m=re.search(r"case \"\$vlpt\" in \*,\*\)(.*?)\nfor _pc_var", t, re.S)
# Simpler: take the proto-comma module file directly
print(open('modules/proto-comma.sh').read())
PY
}
# Test expansion by sourcing the module file directly
for case in "10001,10002" "," "10001," ",10002"; do
  :
done
# xhpt
xhpt="10001,10002"; vxpt=","; sspt="10003,"; hypt="10004,10005,10006"
# shellcheck disable: source module
. modules/proto-comma.sh
[ "$xhpt" = "10001" ] && [ "$xhpt_more" = "10002" ] && ok "xhpt comma split" || bad "xhpt comma split: $xhpt / ${xhpt_more:-}"
[ "$vxpt" = "" ] && [ "$vxpt_more" = "random" ] && ok "vxpt ',' -> random sentinel" || bad "vxpt ',' split: '$vxpt' / '${vxpt_more:-}'"
[ "$sspt" = "10003" ] && [ "$sspt_more" = "random" ] && ok "sspt trailing comma -> random" || bad "sspt split: $sspt / ${sspt_more:-}"
[ "$hypt" = "10004" ] && [ "$hypt_more" = "10005,10006" ] && ok "hypt 3-item split" || bad "hypt split: $hypt / ${hypt_more:-}"
# single, no comma, unchanged
tupt="20001"; . modules/proto-comma.sh
[ "$tupt" = "20001" ] && [ -z "${tupt_more:-}" ] && ok "single port unchanged" || bad "single port changed"
# direct *_more is NOT a user input any more (same as vlpt_more):
# it is cleared at the top of proto-comma, before expansion, so a
# command that still passes xhpt_more= / sspt_more= does nothing
# with them; only a comma in the main variable creates a _more list.
xhpt="10001"; xhpt_more="99999"; sspt=""; sspt_more="88888"; . modules/proto-comma.sh
[ "$xhpt" = "10001" ] && [ -z "${xhpt_more:-}" ] && [ -z "${sspt_more:-}" ] && ok "direct *_more cleared" || bad "direct *_more must be cleared: xhpt_more='${xhpt_more:-}' sspt_more='${sspt_more:-}'"
# top list (sh.txt save loop, the loop right after cmd="") must not
# carry *_more any more (vars_save, a different loop, still does).
python3 - argosbx.sh << 'PY' > /tmp/proto_top_check.txt 2>&1 || true
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r'cmd=""\nfor v in ([^;]+);', t)
print(m.group(1) if m else "NOTFOUND")
PY
grep -q '_more' /tmp/proto_top_check.txt && bad "sh.txt top list must not contain *_more: $(cat /tmp/proto_top_check.txt)" || ok "sh.txt top list without *_more"
# recovery line (bashrc) must not carry *_more any more
grep -Fq 'proto-more-recovery-' build/build.py && bad "recovery line must not contain *_more" || ok "recovery line without *_more"

# --- install loops (Xray) ---
T=$(mktemp -d); export HOME="$T"; mkdir -p "$HOME/agsbx"
uuid="11111111-2222-3333-4444-555555555555"; dekey="seed123"; ym_vl_re="apple.com"
private_key_x="pkx"; short_id_x="sid1"; certificateHTA="/tmp/cert.crt"; keyHTA="/tmp/key.key"
cat > "$HOME/agsbx/xr.json" << 'EOF'
{
"inbounds": [
EOF
xhpt_more="10002,random"; vxpt_more="10003"
# extract xray loop module from generated script: it is between the
# vlpt-more xray block end and installsb, but easiest is to source
# the module file directly (it only uses variables + xr.json)
. modules/proto-more-xray.sh
grep -q '"tag":"xhttp-reality-2"' "$HOME/agsbx/xr.json" && grep -q '"tag":"xhttp-reality-3"' "$HOME/agsbx/xr.json" && ok "xhpt loop tags -2 -3" || bad "xhpt loop tags"
grep -q '"tag":"vless-xhttp-2"' "$HOME/agsbx/xr.json" && ok "vxpt loop tag -2" || bad "vxpt loop tag"
[ -f "$HOME/agsbx/port_xh2" ] && [ "$(cat "$HOME/agsbx/port_xh2")" = "10002" ] && ok "xhpt port file 2" || bad "xhpt port file 2"
[ -f "$HOME/agsbx/port_xh3" ] && [ "$(cat "$HOME/agsbx/port_xh3")" -ge 10000 ] 2>/dev/null && ok "xhpt random port file 3" || bad "xhpt random port file 3"
# second run reuses random port
p3=$(cat "$HOME/agsbx/port_xh3"); xhpt_more="10002,random"; . modules/proto-more-xray.sh
[ "$(cat "$HOME/agsbx/port_xh3")" = "$p3" ] && ok "xhpt random port reused on rerun" || bad "xhpt random port changed on rerun"

# --- install loops (SB) ---
cat > "$HOME/agsbx/sb.json" << 'EOF'
{
"inbounds": [
EOF
sspt_more="10004"; sskey="sskey123"; echo "sskey123" > "$HOME/agsbx/sskey"
. modules/proto-more-sb.sh
grep -q '"tag":"ss-2022-2"' "$HOME/agsbx/sb.json" && ok "sspt loop tag -2" || bad "sspt loop tag"
[ "$(cat "$HOME/agsbx/port_ss2" 2>/dev/null)" = "10004" ] && ok "sspt port file 2" || bad "sspt port file 2"

# --- auto loop (hypt, sb branch) ---
rm -f "$HOME/agsbx/xr.json"
cat > "$HOME/agsbx/sb.json" << 'EOF'
{
"inbounds": [
EOF
hypt_more="10005"
. modules/proto-more-hy.sh
grep -q '"tag": "hy2-sb-2"' "$HOME/agsbx/sb.json" && ok "hypt sb loop tag -2" || bad "hypt sb loop tag"

# --- ufw tag scan ---
cat > "$HOME/agsbx/xr.json" << 'EOF'
{"tag":"xhttp-reality-2"}
{"tag":"xhttp-reality-3"}
EOF
cat > "$HOME/agsbx/sb.json" << 'EOF'
{"tag":"ss-2022-2"}
EOF
# ufw_desired_rules needs the ufw module; source it (functions only)
. modules/ufw.sh
vlp=""; vlp2=""; vlpt_more=""; xhp=""; vxp=""; vwp=""; xup=""; xcp=""; nvp=""; tup=""; anp=""; arp=""; ssp=""; hyp=""; vmp=""; vmt=""; sop=""
xhpt_more=""; vxpt_more=""; vwpt_more=""; xupt_more=""; xcpt_more=""; nvpt_more=""; tupt_more=""; anpt_more=""; arpt_more=""; sspt_more=""; hypt_more=""; vmpt_more=""; vmtls_more=""; sopt_more=""
port_xh=""; port_vx=""; port_vw=""; port_xu=""; port_xc=""; port_nv=""; port_tu=""; port_an=""; port_ar=""; port_ss=""; port_hy2=""; port_vm_ws=""; port_vm_tls=""; port_so=""; port_vl_re=""; port_vl_re2=""
rules=$(ufw_desired_rules | sort -u)
echo "$rules" | grep -q "^10002/tcp$" && echo "$rules" | grep -q "^10004/tcp$" && ok "ufw tag scan opens xhpt-2 and sspt-2" || bad "ufw tag scan: $rules"
# random xhpt port 3 should also be in rules (port file exists, tag exists)
echo "$rules" | grep -q "/tcp$" && ok "ufw rules non-empty" || bad "ufw rules empty"

# --- egress aliases ---
. modules/egress.sh
[ "$(egress_inbound_tags xhpt2)" = "xhttp-reality-2" ] && ok "egress xhpt2" || bad "egress xhpt2: $(egress_inbound_tags xhpt2)"
[ "$(egress_inbound_tags sspt3)" = "ss-2022-3" ] && ok "egress sspt3" || bad "egress sspt3"
[ "$(egress_inbound_tags hypt2)" = "hy2-xr-2,hy2-sb-2" ] && ok "egress hypt2 dual" || bad "egress hypt2: $(egress_inbound_tags hypt2)"
[ "$(egress_inbound_tags vmpt2)" = "vmess-xr-2,vmess-sb-2" ] && ok "egress vmpt2 dual" || bad "egress vmpt2"
[ "$(egress_inbound_tags sopt2)" = "socks5-xr-2,socks5-sb-2" ] && ok "egress sopt2 dual" || bad "egress sopt2"
[ "$(egress_inbound_tags xhpt)" = "xhttp-reality" ] && ok "egress xhpt unchanged" || bad "egress xhpt changed"

# --- display loops ---
sxname=""; hostname="testhost"; add="1.2.3.4"; server_ip="1.2.3.4"; sni="www.bing.com"; domain_addr="1.2.3.4"; reality_addr="1.2.3.4"; ym_vl_re="apple.com"; enkey="seed123"; public_key_x="pkx"; short_id_x="sid1"; public_key_s="pks"; short_id_s="sid2"; sskey="sskey123"; cl_skip="true"; cl_pin_line=""; sb_insecure="true"; sb_pin_field=""; jhins="true"; pin_on="0"; pin_sha=""
cat > "$HOME/agsbx/xr.json" << 'EOF'
{"tag":"xhttp-reality-2"}
EOF
cat > "$HOME/agsbx/sb.json" << 'EOF'
{"tag":"ss-2022-2"}
EOF
echo "10002" > "$HOME/agsbx/port_xh2"; echo "10004" > "$HOME/agsbx/port_ss2"
: > "$HOME/agsbx/jhsub.txt"
. modules/proto-more-display.sh > "$T/display.out" 2>&1
grep -q "vl-xhttp-reality-enc-2-testhost" "$T/display.out" && grep -q "Shadowsocks-2022-2-testhost" "$T/display.out" && ok "display native links xhpt2/sspt2" || bad "display native links: $(cat "$T/display.out")"
sbsspt_more > "$T/sb.out" 2>&1; grep -q "Shadowsocks-2022-2-testhost" "$T/sb.out" && ok "display sb sspt_more" || bad "display sb sspt_more"
clsspt_more > "$T/cl.out" 2>&1; grep -q "Shadowsocks-2022-2-testhost" "$T/cl.out" && ok "display cl sspt_more" || bad "display cl sspt_more"

# --- generator note ---
grep -q "全部协议都支持" index.html && ok "generator note all protocols" || bad "generator note still vlpt-only"
grep -q "inbound:xhpt2" index.html && ok "generator note xhpt2 example" || bad "generator note xhpt2 example"
# --- vars_save includes *_more ---
grep -q "xhpt_more" modules/vars.sh && grep -q "sspt_more" modules/vars.sh && ok "vars_save *_more" || bad "vars_save *_more missing"

rm -rf "$T"
[ "$fail" = 0 ] && echo "ALL proto_more TESTS PASS" || { echo "proto_more TESTS FAILED"; exit 1; }
