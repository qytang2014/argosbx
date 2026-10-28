#!/bin/bash
# Test: vlpt loop (vlpt_more="10003,10004" = instances 3, 4, ...).
# No new variable per instance: install loops (Xray + Sing-box),
# display/subscription loops over tags actually present in xr/sb.json,
# ufw loops over the list, egress alias is generic for any vlptN.
# vlpt/vlpt2 (instances 1/2) are unchanged for backward compatibility.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
# 1. generated script carries the loop blocks, not per-instance copies
grep -Fq 'vlpt_more="10003,10004" installs instances 3, 4' "$ROOT/argosbx.sh" || fail "xray loop comment missing"
grep -Fq 'tag":"reality-vision-$_vlpt_more_idx"' "$ROOT/argosbx.sh" || fail "xray loop tag missing"
grep -Fq '"tag": "vl-reality-sb-$_vlpt_more_idx"' "$ROOT/argosbx.sh" || fail "sb loop tag missing"
grep -Fq 'vlpt_more_idx_list' "$ROOT/argosbx.sh" || fail "display loop helper missing"
for f in sbvlpt_more clvlpt_more sbvlpt_more_1 clvlpt_more_1; do
  grep -Fq "$f" "$ROOT/argosbx.sh" || fail "subscription loop function $f missing"
done
grep -Fq 'get_func sbvlpt_more' "$ROOT/argosbx.sh" || fail "sbxy missing sbvlpt_more"
grep -Fq 'get_func clvlpt_more' "$ROOT/argosbx.sh" || fail "clxy missing clvlpt_more"
# no vlpt3 variable: the 3rd instance must come from the list, not a copy
grep -Fq 'vlpt3=' "$ROOT/argosbx.sh" && fail "vlpt3 variable must not exist (loop, not copies)"
grep -Fq 'for v in uuid vlpt vlpt2 vlpt_more vmpt' "$ROOT/argosbx.sh" || fail "top list missing vlpt_more"
grep -Fq 'vlpt_more=' "$ROOT/argosbx.sh" || fail "recovery/sh missing vlpt_more"
# 2. egress alias generic: vlpt3, vlpt4, vlpt10 all expand, vlpt unchanged
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
python3 - "$ROOT/argosbx.sh" "$TMP/egress.sh" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"# ===== EGRESS MODULE BEGIN.*?# ===== EGRESS MODULE END =====\n", t, re.S)
assert m, "EGRESS MODULE not found"
open(sys.argv[2], "w").write(m.group(0))
PY
out=$(bash -c 'source "$1"; egress_inbound_tags vlpt3; egress_inbound_tags vlpt10; egress_inbound_tags vlpt; egress_inbound_tags vlpt2' _ "$TMP/egress.sh")
echo "$out" | grep -Fqx "reality-vision-3,vl-reality-sb-3" || fail "alias vlpt3 wrong: $out"
echo "$out" | grep -Fqx "reality-vision-10,vl-reality-sb-10" || fail "alias vlpt10 wrong: $out"
echo "$out" | grep -Fqx "reality-vision,vl-reality-sb" || fail "alias vlpt changed: $out"
echo "$out" | grep -Fqx "reality-vision-2,vl-reality-sb-2" || fail "alias vlpt2 changed: $out"
# 3. ufw: loop over vlpt_more list, plus fallback scan of port files
python3 - "$ROOT/argosbx.sh" "$TMP/ufw.sh" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"# ufw firewall sync.*?^ufw_desired_rules\(\)\{.*?\n\}\n", t, re.S | re.M)
assert m, "ufw module not found"
open(sys.argv[2], "w").write(m.group(0))
PY
out=$(bash -c 'source "$1"; vlpt_more="20003,20004"; ufw_desired_rules' _ "$TMP/ufw.sh")
echo "$out" | grep -Fqx "20003/tcp" || fail "ufw loop missing 20003: $out"
echo "$out" | grep -Fqx "20004/tcp" || fail "ufw loop missing 20004: $out"
# 4. display loop: tags in xr/sb.json decide, stale port files do not
mkdir -p "$TMP/agsbx"
cat > "$TMP/agsbx/xr.json" << 'JSON'
{"inbounds": [{"tag":"reality-vision-3"}, {"tag":"reality-vision-5"}]}
JSON
cat > "$TMP/agsbx/sb.json" << 'JSON'
{"inbounds": []}
JSON
echo "30003" > "$TMP/agsbx/port_vl_re3"
echo "30005" > "$TMP/agsbx/port_vl_re5"
echo "99999" > "$TMP/agsbx/port_vl_re4"
python3 - "$ROOT/argosbx.sh" "$TMP/display.sh" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"# vlpt more instances display.*?^clvlpt_more_1\(\)\{.*?\n\}\n", t, re.S | re.M)
assert m, "vlpt-more display module not found in built script"
open(sys.argv[2], "w").write(m.group(0))
PY
out=$(HOME="$TMP" bash -c 'source "$1"; uuid="11111111-2222-3333-4444-555555555555"; reality_addr="203.0.113.10"; ym_vl_re="apple.com"; sxname=""; hostname="test"; public_key_x="PKX"; short_id_x="SIDX"; public_key_s="PKS"; short_id_s="SIDS"; vlpt_more_idx_list; sbvlpt_more_1' _ "$TMP/display.sh")
echo "$out" | grep -Fqx '"vless-3-test",' || fail "display loop missing instance 3: $out"
echo "$out" | grep -Fqx '"vless-5-test",' || fail "display loop missing instance 5: $out"
echo "$out" | grep -Fq "vless-4" && fail "stale port file 4 must not appear: $out"
# 4b. native link loop + sb node loop (these use the port check that
# a missing space before ] would break: [ -n "$port" ] must be exact)
out2=$(HOME="$TMP" bash -c 'uuid="11111111-2222-3333-4444-555555555555"; reality_addr="203.0.113.10"; ym_vl_re="apple.com"; sxname=""; hostname="test"; public_key_x="PKX"; short_id_x="SIDX"; public_key_s="PKS"; short_id_s="SIDS"; source "$1"; sbvlpt_more' _ "$TMP/display.sh" 2>&1)
echo "$out2" | grep -Fq '"server_port": 30003' || fail "sb loop missing port 30003: $out2"
echo "$out2" | grep -Fq '"server_port": 30005' || fail "sb loop missing port 30005: $out2"
echo "$out2" | grep -Fq "30004" && fail "sb loop must not include stale 4: $out2"
# 5. generator: vlpt_more field in the dual group, in optIds
grep -Fq 'id="vlpt_more"' "$ROOT/index.html" || fail "generator vlpt_more field missing"
grep -Fq "'vlpt_more'" "$ROOT/index.html" || fail "generator optIds missing vlpt_more"
awk '/双内核可选协议/,/Xray可选协议/' "$ROOT/index.html" | grep -Fq 'id="vlpt_more"' || fail "vlpt_more not in dual group"
echo "PASS: vlpt loop (vlpt_more)"
