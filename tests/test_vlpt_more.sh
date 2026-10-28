#!/bin/bash
# Test: vlpt loop (vlpt_more="10002,10003" = instances 2, 3, ...).
# No new variable per instance: install loops (Xray + Sing-box),
# display/subscription loops over tags actually present in xr/sb.json,
# ufw loops over the list, egress alias is generic for any vlptN.
# vlpt is instance 1; vlpt2 (script-side) is unchanged for backward
# compatibility, and when it is set vlpt_more starts at 3 instead of 2.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
# 1. generated script carries the loop blocks, not per-instance copies
grep -Fq 'vlpt_more="10002,10003" installs instances 2, 3' "$ROOT/argosbx.sh" || fail "xray loop comment missing"
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
# 5. generator: only one vlpt field (its port value is the comma
# list); no vlpt_more field, no vlpt2 checkbox. Section note under
# "必选内核协议端口：" explains comma = multiple instances.
grep -Fq 'id="vlpt_more"' "$ROOT/index.html" && fail "generator vlpt_more field must be removed (vlpt itself is the list)"
grep -Fq 'data-proto="vlpt2"' "$ROOT/index.html" && fail "generator vlpt2 checkbox must be removed"
grep -Fq 'class="section-note"' "$ROOT/index.html" || fail "generator section-note missing"
grep -Fq '逗号个数 + 1 = 实例数' "$ROOT/index.html" || fail "generator comma rule missing"
grep -Fq '10001, = 第 1 个固定 10001、第 2 个随机' "$ROOT/index.html" || fail "generator comma example missing"
grep -Fq '全部协议都支持' "$ROOT/index.html" || fail "generator must state all protocols support comma now"
grep -Fq 'class="field-note"' "$ROOT/index.html" || fail "generator field-note missing"
grep -Fq '所有 vlpt 实例共用此内核' "$ROOT/index.html" || fail "generator kernel note missing"
grep -Fq 'Vless-tcp-reality 内核（' "$ROOT/index.html" && fail "vlpt_kernel label must be short (note goes below)"
grep -Fq 'grid-column: 1 / -1' "$ROOT/index.html" || fail "field-note must span the grid row"
# paste-back migration: old vlpt2/vlpt_more fold into vlpt list
grep -Fq "params['vlpt_more']" "$ROOT/index.html" || fail "generator paste migration missing vlpt_more"
# 6. install loop start index: 2 without vlpt2, 3 with vlpt2
python3 - "$ROOT/argosbx.sh" "$TMP/xray_loop.sh" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"# vlpt more instances on Xray.*?^fi\n\n", t, re.S | re.M)
assert m, "vlpt-more xray module not found in built script"
open(sys.argv[2], "w").write(m.group(0))
PY
mkdir -p "$TMP/agsbx"
out=$(HOME="$TMP" bash -c 'uuid="11111111-2222-3333-4444-555555555555"; ym_vl_re="apple.com"; private_key_x="PRIVX"; short_id_x="SIDX"; vlpt_on="xray"; vlpt_more="20002,20003"; : > "$HOME/agsbx/xr.json"; source "$1"' _ "$TMP/xray_loop.sh" 2>&1)
grep -Fq '"tag":"reality-vision-2"' "$TMP/agsbx/xr.json" || fail "loop without vlpt2 must start at 2: $out"
grep -Fq '"tag":"reality-vision-3"' "$TMP/agsbx/xr.json" || fail "loop without vlpt2 must include 3: $out"
: > "$TMP/agsbx/xr.json"
out=$(HOME="$TMP" bash -c 'uuid="11111111-2222-3333-4444-555555555555"; ym_vl_re="apple.com"; private_key_x="PRIVX"; short_id_x="SIDX"; vlpt_on="xray"; vlp2=yes; vlpt_more="20003,20004"; : > "$HOME/agsbx/xr.json"; source "$1"' _ "$TMP/xray_loop.sh" 2>&1)
grep -Fq '"tag":"reality-vision-2"' "$TMP/agsbx/xr.json" && fail "loop with vlpt2 must not overwrite instance 2"
grep -Fq '"tag":"reality-vision-3"' "$TMP/agsbx/xr.json" || fail "loop with vlpt2 must start at 3: $out"
grep -Fq '"tag":"reality-vision-4"' "$TMP/agsbx/xr.json" || fail "loop with vlpt2 must include 4: $out"
# 7. comma expansion + while-loop random: "10001," must create
# instance 2 (trailing empty is NOT dropped), "," must create 2
# random instances, and a second run must reuse the same random ports.
python3 - "$ROOT/argosbx.sh" "$TMP/comma.sh" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"# vlpt comma list.*?^export uuid=", t, re.S | re.M)
assert m, "vlpt comma module not found"
open(sys.argv[2], "w").write(m.group(0).rsplit("export uuid=", 1)[0])
PY
out=$(bash -c 'vlpt="10001,"; source "$1"; echo "vlpt=[$vlpt] more=[$vlpt_more]"' _ "$TMP/comma.sh")
echo "$out" | grep -Fq 'vlpt=[10001] more=[random]' || fail "comma expansion 10001, wrong: $out"
out=$(bash -c 'vlpt=","; source "$1"; echo "vlpt=[$vlpt] more=[$vlpt_more]"' _ "$TMP/comma.sh")
echo "$out" | grep -Fq 'vlpt=[] more=[random]' || fail "comma expansion , wrong: $out"
out=$(bash -c 'vlpt="10001,10002"; source "$1"; echo "vlpt=[$vlpt] more=[$vlpt_more]"' _ "$TMP/comma.sh")
echo "$out" | grep -Fq 'vlpt=[10001] more=[10002]' || fail "comma expansion 10001,10002 wrong: $out"
out=$(bash -c 'vlpt="10001"; vlpt2="20002"; vlpt_more="30003"; source "$1"; echo "vlpt=[$vlpt] more=[$vlpt_more] vlpt2=[$vlpt2]"' _ "$TMP/comma.sh")
echo "$out" | grep -Fq 'vlpt=[10001] more=[30003] vlpt2=[20002]' || fail "single vlpt must keep legacy vlpt2/vlpt_more: $out"
# while-loop: "10001," via xray loop must write port files for
# instance 1? (instance 1 is the vlpt block, not this loop) - here
# check the loop alone: vlpt_more="random" must write a random port
# file for instance 2, and a second run must reuse it.
: > "$TMP/agsbx/xr.json"
out=$(HOME="$TMP" bash -c 'uuid="11111111-2222-3333-4444-555555555555"; ym_vl_re="apple.com"; private_key_x="PRIVX"; short_id_x="SIDX"; vlpt_on="xray"; vlpt_more="random"; : > "$HOME/agsbx/xr.json"; source "$1"' _ "$TMP/xray_loop.sh" 2>&1)
p1=$(cat "$TMP/agsbx/port_vl_re2" 2>/dev/null)
case "$p1" in ''|*[!0-9]*) fail "random instance 2 port file missing/invalid: $p1";; esac
grep -Fq '"tag":"reality-vision-2"' "$TMP/agsbx/xr.json" || fail "random instance 2 tag missing"
: > "$TMP/agsbx/xr.json"
out=$(HOME="$TMP" bash -c 'uuid="11111111-2222-3333-4444-555555555555"; ym_vl_re="apple.com"; private_key_x="PRIVX"; short_id_x="SIDX"; vlpt_on="xray"; vlpt_more="random"; : > "$HOME/agsbx/xr.json"; source "$1"' _ "$TMP/xray_loop.sh" 2>&1)
p2=$(cat "$TMP/agsbx/port_vl_re2" 2>/dev/null)
[ "$p1" = "$p2" ] || fail "random port must be reused on second run: $p1 vs $p2"
echo "PASS: vlpt loop (vlpt_more)"
