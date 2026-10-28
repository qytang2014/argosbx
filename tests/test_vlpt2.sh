#!/bin/bash
# Test: vlpt second instance (vlpt2). Same uuid/keypair as vlpt,
# different port and inbound tag, shared vlpt_kernel/vlpt_on, and
# egress inbound:vlpt2 must NOT match vlpt1 (and vice versa).
# This suite checks the generated files only (no real install):
# inbound tags, display guards/subscription functions, generator
# checkbox + protoKeys, egress alias, ufw desired rule.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
# 1. main script: Xray + Sing-box inbound tags, distinct from vlpt1
grep -Fq '"tag":"reality-vision-2"' "$ROOT/argosbx.sh" || fail "xray vlpt2 tag missing"
grep -Fq '"tag": "vl-reality-sb-2"' "$ROOT/argosbx.sh" || fail "sb vlpt2 tag missing"
grep -Fq '"tag":"reality-vision"' "$ROOT/argosbx.sh" || fail "xray vlpt tag missing"
grep -Fq '"tag": "vl-reality-sb"' "$ROOT/argosbx.sh" || fail "sb vlpt tag missing"
grep -Fq 'port_vl_re2=$(cat "$HOME/agsbx/port_vl_re2")' "$ROOT/argosbx.sh" || fail "vlpt2 port file missing"
# vlpt2 blocks are gated on the shared vlpt_on, not a new kernel var
grep -Fq 'if [ -n "$vlp2" ] && [ "$vlpt_on" = "xray" ]; then' "$ROOT/argosbx.sh" || fail "vlpt2 xray gate missing"
grep -Fq 'if [ -n "$vlp2" ] && [ "$vlpt_on" = "sb" ]; then' "$ROOT/argosbx.sh" || fail "vlpt2 sb gate missing"
grep -Fq 'vlpt2_kernel' "$ROOT/argosbx.sh" && fail "vlpt2 must not have its own kernel variable"
# vlpt display guard is exact-tag, so a vlpt2-only install does not
# show a broken vlpt link; vlpt2 has its own exact-tag guard
grep -Fq 'if grep -q '"'"'"tag":"reality-vision"'"'"' "$HOME/agsbx/xr.json"' "$ROOT/argosbx.sh" || fail "vlpt display guard not tightened"
grep -Fq 'if grep -q '"'"'"tag":"reality-vision-2"'"'"' "$HOME/agsbx/xr.json"' "$ROOT/argosbx.sh" || fail "vlpt2 display guard missing"
# subscription functions for vlpt2, distinct tags
for f in sbvlpt2 clvlpt2 sbvlpt2_1 clvlpt2_1; do
  grep -Fq "$f" "$ROOT/argosbx.sh" || fail "subscription function $f missing"
done
grep -Fq 'get_func sbvlpt2' "$ROOT/argosbx.sh" || fail "sbxy missing sbvlpt2"
grep -Fq 'get_func clvlpt2' "$ROOT/argosbx.sh" || fail "clxy missing clvlpt2"
# top lists / flag / recovery / port export
grep -Fq 'for v in uuid vlpt vlpt2 vmpt' "$ROOT/argosbx.sh" || fail "top list missing vlpt2"
grep -Fq '[ -z "${vlpt2+x}" ] || vlp2=yes' "$ROOT/argosbx.sh" || fail "vlpt2 flag missing"
grep -Fq 'export port_vl_re2=${vlpt2' "$ROOT/argosbx.sh" || fail "vlpt2 port export missing"
grep -Fq 'vlp2=' "$ROOT/argosbx.sh" || fail "recovery missing vlp2"
# 2. egress alias: vlpt2 -> both -2 tags, vlpt unchanged
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
python3 - "$ROOT/argosbx.sh" "$TMP/egress.sh" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"# ===== EGRESS MODULE BEGIN.*?# ===== EGRESS MODULE END =====\n", t, re.S)
assert m, "EGRESS MODULE not found"
open(sys.argv[2], "w").write(m.group(0))
PY
out=$(bash -c 'source "$1"; egress_inbound_tags vlpt2; egress_inbound_tags vlpt' _ "$TMP/egress.sh")
echo "$out" | grep -Fqx "reality-vision-2,vl-reality-sb-2" || fail "alias vlpt2 wrong: $out"
echo "$out" | grep -Fqx "reality-vision,vl-reality-sb" || fail "alias vlpt changed: $out"
# 3. ufw desired rule for vlpt2 (mock ufw module extraction)
python3 - "$ROOT/argosbx.sh" "$TMP/ufw.sh" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"# ufw firewall sync.*?^ufw_desired_rules\(\)\{.*?\n\}\n", t, re.S | re.M)
assert m, "ufw module not found"
open(sys.argv[2], "w").write(m.group(0))
PY
out=$(bash -c 'source "$1"; vlp2=vlpt2; port_vl_re2=20001; ufw_desired_rules' _ "$TMP/ufw.sh")
echo "$out" | grep -Fqx "20001/tcp" || fail "ufw vlpt2 rule missing: $out"
# 4. generator: vlpt2 checkbox + port, protoKeys, shared kernel label
grep -Fq 'data-proto="vlpt2"' "$ROOT/index.html" || fail "generator vlpt2 checkbox missing"
grep -Fq 'data-port="vlpt2"' "$ROOT/index.html" || fail "generator vlpt2 port missing"
grep -Fq "'vlpt','vlpt2'" "$ROOT/index.html" || fail "generator protoKeys missing vlpt2"
grep -Fq 'vlpt 与 vlpt2 共用' "$ROOT/index.html" || fail "generator kernel label not shared"
echo "PASS: vlpt2 second instance"
