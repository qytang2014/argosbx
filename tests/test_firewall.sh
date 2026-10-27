#!/bin/bash
# Layered firewall: ufw + firewalld auto, raw iptables/nft prompt,
# cloud checklist, fwsync/fwstatus. No real firewall, no real install:
# mock ufw/firewall-cmd/iptables in PATH, temp HOME.
set -u
cd "$(dirname "$0")/.." || exit 1
FAIL=0
fail(){ echo "FAIL: $1"; FAIL=1; }

grep -Fq 'fw_sync' argosbx.sh || fail "built main missing fw_sync"
grep -Fq 'firewalld_sync' argosbx.sh || fail "built main missing firewalld_sync"
grep -Fq 'fwstatus' argosbx.sh || fail "built main missing fwstatus dispatch"
grep -Fq 'fwsync' argosbx.sh || fail "built main missing fwsync dispatch"
grep -Fq 'fw_raw_blocking' argosbx.sh || fail "built main missing raw blocking detection"
grep -Fq 'firewall-cmd --permanent' argosbx.sh || fail "built main missing firewall-cmd permanent"

td=$(mktemp -d); trap 'rm -rf "$td"' EXIT
mkdir -p "$td/bin" "$td/home"
cat > "$td/bin/ufw" <<'EOF'
#!/bin/bash
if [ "$1" = "status" ]; then echo "Status: ${UFW_MOCK_STATUS:-active}"; exit 0; fi
echo "ufw $*" >> "${UFW_MOCK_LOG:-/dev/null}"
exit 0
EOF
cat > "$td/bin/firewall-cmd" <<'EOF'
#!/bin/bash
if [ "$1" = "--state" ]; then echo "${FWD_MOCK_STATE:-running}"; exit 0; fi
if [ "$1" = "--get-default-zone" ]; then echo "public"; exit 0; fi
echo "firewall-cmd $*" >> "${FWD_MOCK_LOG:-/dev/null}"
exit 0
EOF
cat > "$td/bin/iptables" <<'EOF'
#!/bin/bash
if [ "$1" = "-S" ]; then
  if [ "${IPT_MOCK_BLOCKING:-0}" = "1" ]; then echo "-P INPUT DROP"; echo "-A INPUT -j DROP"; else echo "-P INPUT ACCEPT"; fi
  exit 0
fi
if [ "$1" = "-C" ]; then exit 1; fi
echo "iptables $*" >> "${IPT_MOCK_LOG:-/dev/null}"
exit 0
EOF
chmod +x "$td/bin/ufw" "$td/bin/firewall-cmd" "$td/bin/iptables"

run_fw(){
  local assignments="$1" fn="$2"
  HOME="$td/home" PATH="$td/bin:/usr/bin:/bin" UFW_MOCK_LOG="$td/ufw.log" FWD_MOCK_LOG="$td/fwd.log" UFW_MOCK_STATUS="${UFW_STATUS:-active}" FWD_MOCK_STATE="${FWD_STATE:-running}" IPT_MOCK_BLOCKING="${IPT_BLOCKING:-0}" bash -c '
    vlp=""; xhp=""; vxp=""; vwp=""; xup=""; xcp=""; nvp=""; tup=""; anp=""; arp=""; ssp=""; hyp=""; vmp=""; vmt=""; sop="";
    port_vl_re=""; port_xh=""; port_vx=""; port_vw=""; port_xu=""; port_xc=""; port_nv=""; port_tu=""; port_an=""; port_ar=""; port_ss=""; port_hy2=""; port_vm_ws=""; port_vm_tls=""; port_so="";
    eval "$1"
    source "modules/ufw.sh"
    "$2"
  ' _ "$assignments" "$fn"
}

# 1. firewalld only: ufw inactive, firewalld running.
UFW_STATUS=inactive; FWD_STATE=running; IPT_BLOCKING=0
: > "$td/fwd.log"; : > "$td/ufw.log"
run_fw 'vlp=vlpt; port_vl_re=11001; hyp=hypt; port_hy2=11002' fw_sync
grep -Fq "11001/tcp" "$td/home/agsbx/firewalld.rules" || fail "firewalld sync state missing vlpt"
grep -Fq "11002/udp" "$td/home/agsbx/firewalld.rules" || fail "firewalld sync state missing hy2"
grep -Fq "firewall-cmd --permanent --zone=public --add-port=11001/tcp" "$td/fwd.log" || fail "firewalld sync did not add vlpt"
grep -Fq "firewall-cmd --reload" "$td/fwd.log" || fail "firewalld sync must reload once"
grep -Fq "ufw allow" "$td/ufw.log" && fail "firewalld-only sync must not call ufw allow"

# 2. Both active: both backends get rules. Clear state first, or the
# firewalld side would be idempotent (already has the rules from 1)
# and would correctly add nothing.
rm -f "$td/home/agsbx/ufw.rules" "$td/home/agsbx/firewalld.rules"
UFW_STATUS=active; FWD_STATE=running
: > "$td/fwd.log"; : > "$td/ufw.log"
run_fw 'vlp=vlpt; port_vl_re=11001; hyp=hypt; port_hy2=11002' fw_sync
grep -Fq "ufw allow 11001/tcp" "$td/ufw.log" || fail "both-active sync must allow via ufw"
grep -Fq "firewall-cmd --permanent --zone=public --add-port=11001/tcp" "$td/fwd.log" || fail "both-active sync must allow via firewalld"

# 3. Port change via firewalld: old deleted, new added.
: > "$td/fwd.log"
run_fw 'hyp=hypt; port_hy2=11003' fw_sync
grep -Fq "firewall-cmd --permanent --zone=public --remove-port=11001/tcp" "$td/fwd.log" || fail "firewalld port change must remove old vlpt"
grep -Fq "firewall-cmd --permanent --zone=public --add-port=11003/udp" "$td/fwd.log" || fail "firewalld port change must add new hy2"

# 4. Neither active + raw iptables blocking: record + prompt, no auto add.
UFW_STATUS=inactive; FWD_STATE=not\ running; IPT_BLOCKING=1
: > "$td/fwd.log"; : > "$td/ufw.log"
out=$(run_fw 'vlp=vlpt; port_vl_re=12001' fw_sync 2>&1)
grep -Fq "12001/tcp" "$td/home/agsbx/ufw.rules" || fail "neither-active sync must still record desired rules"
echo "$out" | grep -Fq "iptables -I INPUT" || fail "raw blocking prompt must print iptables INSERT commands"
echo "$out" | grep -Fq "云厂商安全组" || fail "sync must print cloud checklist"
grep -Fq "firewall-cmd --permanent" "$td/fwd.log" && fail "neither-active sync must not call firewall-cmd add"

# 5. fwstatus: prints backends and recorded ports.
UFW_STATUS=active; FWD_STATE=running; IPT_BLOCKING=0
out=$(run_fw '' fw_status 2>&1)
echo "$out" | grep -Fq "ufw 在运行" || fail "fwstatus must list ufw"
echo "$out" | grep -Fq "firewalld 在运行" || fail "fwstatus must list firewalld"

# 6. fw_cleanup: deletes from both backends.
: > "$td/fwd.log"; : > "$td/ufw.log"
run_fw '' fw_cleanup
grep -Fq "firewall-cmd --permanent --zone=public --remove-port=11003/udp" "$td/fwd.log" || fail "fw_cleanup must remove firewalld rule"
[ -f "$td/home/agsbx/firewalld.rules" ] && fail "fw_cleanup must remove firewalld state"

# 7. Subscription port + 443 via firewalld (sub-https module, mock caddy/cron/ps).
mkdir -p "$td/subbin"
cat > "$td/subbin/crontab" <<'EOF'
#!/bin/bash
if [ "$1" = "-l" ]; then cat "${CRONFILE:-/dev/null}" 2>/dev/null; exit 0; fi
cat > "${CRONFILE:-/dev/null}"; exit 0
EOF
cat > "$td/subbin/ps" <<'EOF'
#!/bin/bash
echo "  1234 websbx 18080"
exit 0
EOF
chmod +x "$td/subbin/crontab" "$td/subbin/ps"
export CRONFILE="$td/cronfile"; : > "$CRONFILE"
HOME="$td/home" PATH="$td/subbin:$td/bin:/usr/bin:/bin" UFW_MOCK_LOG="$td/ufw.log" FWD_MOCK_LOG="$td/fwd.log" UFW_MOCK_STATUS=inactive FWD_MOCK_STATE=running bash -c '
  source "modules/ufw.sh"
  source "modules/sub-https.sh"
  mkdir -p "$HOME/agsbx"
  echo "token-123" > "$HOME/agsbx/subtoken.log"
  echo "18080" > "$HOME/agsbx/subport.log"
  echo "http-ip" > "$HOME/agsbx/subhttps.mode"
  subhttps_manage_subport "http-ip"
  [ "$(cat "$HOME/agsbx/subhttps.firewalld.subport")" = "18080/tcp" ] || { echo "FAIL: firewalld subport marker missing"; exit 1; }
  subhttps_manage_443 "https"
  [ "$(cat "$HOME/agsbx/subhttps.firewalld.443")" = "443/tcp" ] || { echo "FAIL: firewalld 443 marker missing"; exit 1; }
  subhttps_manage_subport "https"
  [ -f "$HOME/agsbx/subhttps.firewalld.subport" ] && { echo "FAIL: https must delete firewalld subport"; exit 1; }
  exit 0
' || fail "subport/443 via firewalld failed"
grep -Fq "firewall-cmd --permanent --zone=public --add-port=18080/tcp" "$td/fwd.log" || fail "firewalld subport add missing"
grep -Fq "firewall-cmd --permanent --zone=public --add-port=443/tcp" "$td/fwd.log" || fail "firewalld 443 add missing"
grep -Fq "firewall-cmd --permanent --zone=public --remove-port=18080/tcp" "$td/fwd.log" || fail "firewalld subport delete on https missing"

# 8. Host helper via firewalld.
cat > "$td/envfile" <<'EOF'
vlpt=13001
hypt=13002
EOF
: > "$td/fwd.log"
HOME="$td/home" PATH="$td/bin:/usr/bin:/bin" FWD_MOCK_LOG="$td/fwd.log" UFW_MOCK_STATUS=inactive FWD_MOCK_STATE=running bash ufw-host.sh apply --env "$td/envfile" --state "$td/hostfw.rules" >/dev/null || fail "host helper firewalld apply failed"
grep -Fq "13001/tcp" "$td/hostfw.rules.firewalld" || fail "host helper firewalld state missing vlpt"
grep -Fq "firewall-cmd --permanent --zone=public --add-port=13001/tcp" "$td/fwd.log" || fail "host helper firewalld add missing"
HOME="$td/home" PATH="$td/bin:/usr/bin:/bin" FWD_MOCK_LOG="$td/fwd.log" bash ufw-host.sh delete --state "$td/hostfw.rules" >/dev/null || fail "host helper firewalld delete failed"
[ -f "$td/hostfw.rules.firewalld" ] && fail "host helper delete must remove firewalld state"

[ "$FAIL" = 0 ] && echo "test_firewall: PASS" || { echo "test_firewall: FAIL"; exit 1; }
