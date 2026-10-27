#!/bin/bash
# ufw firewall sync: main script, host helper, container prompt.
# No real ufw, no real docker, no real install: mock ufw/docker in PATH,
# temp HOME, and string checks on built vs upstream files.
set -u
cd "$(dirname "$0")/.." || exit 1
FAIL=0
fail(){ echo "FAIL: $1"; FAIL=1; }

# 1. Built files carry ufw; upstream files do not (private feature).
grep -Fq 'ufw_sync' argosbx.sh || fail "built main missing ufw_sync"
grep -Fq 'ufw_cleanup' argosbx.sh || fail "built main missing ufw_cleanup"
grep -Fq 'ufwsync' argosbx.sh || fail "built main missing ufwsync dispatch"
grep -Fq 'ufw --force delete allow' argosbx.sh || fail "built main missing ufw delete"
grep -Fq 'container_ufw_prompt' container/nodejs/start.sh || fail "built container missing container_ufw_prompt"
grep -Fq 'ufw_sync' upstream/argosbx.sh && fail "upstream main unexpectedly has ufw_sync"
grep -Fq 'container_ufw_prompt' upstream/container/nodejs/start.sh && fail "upstream container unexpectedly has container_ufw_prompt"
# Safety: never enable ufw, never open SSH/cert ports by name.
grep -Fq 'ufw enable' argosbx.sh && fail "built main must never ufw enable"
grep -Fq 'ufw enable' ufw-host.sh && fail "host helper must never ufw enable"
grep -Fq 'ufw-host' container/nodejs/Dockerfile && fail "host helper must not be copied into the container image"

td=$(mktemp -d); trap 'rm -rf "$td"' EXIT
mkdir -p "$td/bin" "$td/home"
cat > "$td/bin/ufw" <<'EOF'
#!/bin/bash
if [ "$1" = "status" ]; then echo "Status: ${UFW_MOCK_STATUS:-active}"; exit 0; fi
echo "ufw $*" >> "${UFW_MOCK_LOG:-/dev/null}"
exit 0
EOF
cat > "$td/bin/docker" <<'EOF'
#!/bin/bash
if [ "$1" = "port" ]; then
  echo "50001/tcp -> 0.0.0.0:60001"
  echo "50001/tcp -> [::]:60001"
  echo "50002/udp -> 0.0.0.0:60002"
  exit 0
fi
exit 0
EOF
chmod +x "$td/bin/ufw" "$td/bin/docker"

# Helper to run the main ufw module in a clean subshell.
# $1 = protocol/port assignments (eval'd), $2 = function to call.
run_main(){
  local assignments="$1" fn="$2"
  HOME="$td/home" PATH="$td/bin:/usr/bin:/bin" UFW_MOCK_LOG="$td/ufw.log" UFW_MOCK_STATUS="${UFW_STATUS:-active}" bash -c '
    vlp=""; xhp=""; vxp=""; vwp=""; xup=""; xcp=""; nvp=""; tup=""; anp=""; arp=""; ssp=""; hyp=""; vmp=""; vmt=""; sop="";
    port_vl_re=""; port_xh=""; port_vx=""; port_vw=""; port_xu=""; port_xc=""; port_nv=""; port_tu=""; port_an=""; port_ar=""; port_ss=""; port_hy2=""; port_vm_ws=""; port_vm_tls=""; port_so="";
    eval "$1"
    source "modules/ufw.sh"
    "$2"
  ' _ "$assignments" "$fn"
}

# 2. Active, fresh sync: mapping, no over-opening, no targo, no bad port.
UFW_STATUS=active
: > "$td/ufw.log"
run_main 'vlp=vlpt; port_vl_re=10001; hyp=hypt; port_hy2=10002; ssp=sspt; port_ss=10003; xup=xupt; port_xu=10004; xcp=xcpt; port_xc=10005; sop=sopt; port_so=10006; xhp=xhptargo; vmp=vmpt; port_vm_ws=99999' ufw_sync
cat "$td/home/agsbx/ufw.rules" 2>/dev/null | sort > "$td/state1" || fail "state file missing after active sync"
cat > "$td/expected1" <<'EOF'
10001/tcp
10002/udp
10003/tcp
10003/udp
10004/udp
10005/tcp
10006/tcp
10006/udp
EOF
diff "$td/expected1" "$td/state1" >/dev/null || fail "fresh sync state mismatch (mapping/targo/bad-port)"
grep -Fq "ufw allow 10001/tcp" "$td/ufw.log" || fail "fresh sync did not allow vlpt tcp"
grep -Fq "ufw allow 10002/udp" "$td/ufw.log" || fail "fresh sync did not allow hy2 udp"
grep -Fq "ufw allow 10003/udp" "$td/ufw.log" || fail "fresh sync did not allow ss udp"
grep -Fq "ufw allow 10005/udp" "$td/ufw.log" && fail "xcpt must be tcp only, not udp (UDP variants are CDN, not direct)"
grep -Fq "ufw allow 99999" "$td/ufw.log" && fail "out-of-range port must be skipped"

# 3. Idempotent second sync: no new allow calls.
n_before=$(grep -c "ufw allow" "$td/ufw.log")
run_main 'vlp=vlpt; port_vl_re=10001; hyp=hypt; port_hy2=10002; ssp=sspt; port_ss=10003; xup=xupt; port_xu=10004; xcp=xcpt; port_xc=10005; sop=sopt; port_so=10006' ufw_sync
n_after=$(grep -c "ufw allow" "$td/ufw.log")
[ "$n_before" = "$n_after" ] || fail "second sync must not re-allow existing rules"

# 4. Port change + protocol removal: stale rules deleted, new added.
run_main 'hyp=hypt; port_hy2=20002; ssp=sspt; port_ss=10003; xup=xupt; port_xu=10004; xcp=xcpt; port_xc=10005; sop=sopt; port_so=10006' ufw_sync
grep -Fq "ufw --force delete allow 10001/tcp" "$td/ufw.log" || fail "removed vlpt rule not deleted"
grep -Fq "ufw --force delete allow 10002/udp" "$td/ufw.log" || fail "old hy2 rule not deleted on port change"
grep -Fq "ufw allow 20002/udp" "$td/ufw.log" || fail "new hy2 rule not allowed"
grep -Fq "20002/udp" "$td/home/agsbx/ufw.rules" || fail "state not updated after port change"

# 5. Inactive ufw: state still written, no allow calls for new rules.
: > "$td/ufw.log"
UFW_STATUS=inactive
run_main 'vlp=vlpt; port_vl_re=30001' ufw_sync
grep -Fq "30001/tcp" "$td/home/agsbx/ufw.rules" || fail "inactive sync must still record desired rules"
grep -Fq "ufw allow" "$td/ufw.log" && fail "inactive sync must not call ufw allow"
UFW_STATUS=active

# 6. ufwsync (apply saved): re-allows recorded rules when active.
: > "$td/ufw.log"
run_main '' ufw_apply_saved
grep -Fq "ufw allow 30001/tcp" "$td/ufw.log" || fail "ufwsync did not re-allow recorded rule"

# 7. Cleanup: deletes recorded rules, removes state; fallback via port files.
run_main '' ufw_cleanup
grep -Fq "ufw --force delete allow 30001/tcp" "$td/ufw.log" || fail "cleanup did not delete recorded rule"
[ -f "$td/home/agsbx/ufw.rules" ] && fail "cleanup must remove state file"
echo "31001" > "$td/home/agsbx/port_xh"
echo "31002" > "$td/home/agsbx/port_hy2"
: > "$td/ufw.log"
run_main '' ufw_cleanup
grep -Fq "ufw --force delete allow 31001/tcp" "$td/ufw.log" || fail "cleanup fallback did not delete xhpt port file rule"
grep -Fq "ufw --force delete allow 31002/udp" "$td/ufw.log" || fail "cleanup fallback did not delete hy2 port file rule"

# 8. Missing ufw: sync still writes state and returns 0.
rm -rf "$td/home/agsbx"
HOME="$td/home" PATH="/usr/bin:/bin" bash -c '
  vlp=vlpt; port_vl_re=40001; hyp=""; xhp=""; vxp=""; vwp=""; xup=""; xcp=""; nvp=""; tup=""; anp=""; arp=""; ssp=""; vmp=""; vmt=""; sop="";
  port_xh=""; port_vx=""; port_vw=""; port_xu=""; port_xc=""; port_nv=""; port_tu=""; port_an=""; port_ar=""; port_ss=""; port_hy2=""; port_vm_ws=""; port_vm_tls=""; port_so="";
  source "modules/ufw.sh"; ufw_sync
' || fail "sync without ufw must return 0"
grep -Fq "40001/tcp" "$td/home/agsbx/ufw.rules" || fail "sync without ufw must still record rules"

# 9. Container prompt: prints host commands, empty set prints nothing.
out=$(bash -c 'vlpt=41001; hypt=41002; sspt=41003; xhpt=""; vxpt=""; vwpt=""; xupt=""; xcpt=""; nvpt=""; tupt=""; anpt=""; arpt=""; vmpt=""; vmtls=""; sopt=""; source "modules/container-ufw.sh"; container_ufw_prompt')
echo "$out" | grep -Fq "宿主 ufw 提示" || fail "container prompt missing header"
echo "$out" | grep -Fq "ufw allow 41001/tcp" || fail "container prompt missing vlpt tcp"
echo "$out" | grep -Fq "ufw allow 41002/udp" || fail "container prompt missing hy2 udp"
echo "$out" | grep -Fq "ufw allow 41003/tcp" || fail "container prompt missing ss tcp"
echo "$out" | grep -Fq "ufw allow 41003/udp" || fail "container prompt missing ss udp"
echo "$out" | grep -Fq "ufw-host.sh" || fail "container prompt missing helper reference"
out_empty=$(bash -c 'vlpt=""; hypt=""; sspt=""; xhpt=""; vxpt=""; vwpt=""; xupt=""; xcpt=""; nvpt=""; tupt=""; anpt=""; arpt=""; vmpt=""; vmtls=""; sopt=""; source "modules/container-ufw.sh"; container_ufw_prompt')
[ -z "$out_empty" ] || fail "container prompt must be empty with no protocols"

# 10. Host helper: env path, docker path, print, delete.
cat > "$td/envfile" <<'EOF'
vlpt=50001
hypt=50002
sspt=50003
EOF
: > "$td/ufw.log"
HOME="$td/home" PATH="$td/bin:/usr/bin:/bin" UFW_MOCK_LOG="$td/ufw.log" UFW_MOCK_STATUS=active bash ufw-host.sh apply --env "$td/envfile" --state "$td/host.rules" >/dev/null || fail "host helper env apply failed"
grep -Fq "50001/tcp" "$td/host.rules" || fail "host helper env state missing vlpt"
grep -Fq "50002/udp" "$td/host.rules" || fail "host helper env state missing hy2 udp"
grep -Fq "50003/udp" "$td/host.rules" || fail "host helper env state missing ss udp"
grep -Fq "ufw allow 50001/tcp" "$td/ufw.log" || fail "host helper env apply did not allow vlpt"
out_print=$(HOME="$td/home" PATH="$td/bin:/usr/bin:/bin" bash ufw-host.sh print --env "$td/envfile" 2>/dev/null)
echo "$out_print" | grep -Fq "50001/tcp" || fail "host helper print missing vlpt"
: > "$td/ufw.log"
HOME="$td/home" PATH="$td/bin:/usr/bin:/bin" UFW_MOCK_LOG="$td/ufw.log" UFW_MOCK_STATUS=active bash ufw-host.sh apply --container testcontainer --state "$td/host2.rules" >/dev/null || fail "host helper docker apply failed"
grep -Fq "60001/tcp" "$td/host2.rules" || fail "host helper docker state must use host port, not container port"
grep -Fq "60002/udp" "$td/host2.rules" || fail "host helper docker state missing host udp port"
grep -Fq "50001/tcp" "$td/host2.rules" && fail "host helper docker state must not use container port"
: > "$td/ufw.log"
HOME="$td/home" PATH="$td/bin:/usr/bin:/bin" UFW_MOCK_LOG="$td/ufw.log" UFW_MOCK_STATUS=active bash ufw-host.sh delete --state "$td/host2.rules" >/dev/null || fail "host helper delete failed"
grep -Fq "ufw --force delete allow 60001/tcp" "$td/ufw.log" || fail "host helper delete did not delete host rule"
[ -f "$td/host2.rules" ] && fail "host helper delete must remove state file"

[ "$FAIL" = 0 ] && echo "test_ufw: PASS" || { echo "test_ufw: FAIL"; exit 1; }
