#!/bin/bash
# Test: vlpt pbk/sid on a pure-Xray install (no sing-box binary).
# Regression for 2026-10-28: vlpt_pbk/sid used to be assigned inside
# the `if [ -e sing-box ]` display block, so a pure-Xray machine
# printed pbk=&sid= even though xrk/ was fine. The assignment must
# now be AFTER that block's fi, defaulting to Xray, overriding to
# Sing-box only when sb.json contains vl-reality-sb.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
# 1. structural: assignment comes after the sing-box display fi,
# not inside it (sskey line, fi, assignment, xhttp block, in order)
python3 - "$ROOT/argosbx.sh" << 'PY' || fail "pbk assignment not after sing-box fi"
import re, sys
t = open(sys.argv[1]).read()
# find the display assignment (the one followed by the xhttp block)
m = re.search(r'sskey=\$\(cat "\$HOME/agsbx/sskey" 2>/dev/null\)\nfi\nif grep -q "vl-reality-sb" "\$HOME/agsbx/sb\.json" 2>/dev/null; then vlpt_pbk="\$public_key_s"; vlpt_sid="\$short_id_s"; else vlpt_pbk="\$public_key_x"; vlpt_sid="\$short_id_x"; fi\nif grep xhttp-reality', t)
assert m, "display pbk assignment not in fi-outside position"
PY
echo "ok: vlpt_pbk assignment outside sing-box block"
# 2. functional: pure Xray, no sing-box binary, xrk present
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/agsbx/xrk"
touch "$TMP/agsbx/xray"
echo "PKX" > "$TMP/agsbx/xrk/public_key"
echo "SIDX" > "$TMP/agsbx/xrk/short_id"
echo '{"inbounds":[]}' > "$TMP/agsbx/sb.json"
python3 - "$ROOT/argosbx.sh" "$TMP/display.sh" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
# display block: xray read block through the vlpt_pbk assignment
m = re.search(r'if \[ -e "\$HOME/agsbx/xray" \]; then\nprivate_key_x=.*?vlpt_sid="\$short_id_x"; fi\n', t, re.S)
assert m, "display pbk block not found"
open(sys.argv[2], "w").write(m.group(0))
PY
out=$(HOME="$TMP" bash -c 'source "$1"; echo "pbk=[$vlpt_pbk] sid=[$vlpt_sid]"' _ "$TMP/display.sh")
echo "$out" | grep -Fq 'pbk=[PKX] sid=[SIDX]' || fail "pure-Xray vlpt_pbk wrong: $out"
echo "ok: pure-Xray vlpt_pbk/sid from xrk"
# 3. functional: Sing-box vlpt still wins when sb.json has vl-reality-sb
mkdir -p "$TMP/agsbx/sbk"
touch "$TMP/agsbx/sing-box"
echo "PKS" > "$TMP/agsbx/sbk/public_key"
echo "SIDS" > "$TMP/agsbx/sbk/short_id"
echo '{"inbounds":[{"tag": "vl-reality-sb"}]}' > "$TMP/agsbx/sb.json"
out=$(HOME="$TMP" bash -c 'source "$1"; echo "pbk=[$vlpt_pbk] sid=[$vlpt_sid]"' _ "$TMP/display.sh")
echo "$out" | grep -Fq 'pbk=[PKS] sid=[SIDS]' || fail "sing-box vlpt_pbk wrong: $out"
echo "ok: sing-box vlpt_pbk/sid from sbk"
echo "PASS: vlpt pbk/sid display"
