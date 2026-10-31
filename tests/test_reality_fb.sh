#!/bin/bash
# Test: Reality own-domain fallback (ym_vl_fb)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 8 fallback locations use ym_vl_fb
[ "$(grep -c 'ym_vl_fb:-$ym_vl_re' "$ROOT/argosbx.sh")" = "8" ] || { echo "FAIL: expected 8 ym_vl_fb fallbacks"; exit 1; }

# ym_vl_re auto-fills from ym; ym_vl_fb set when ym_vl_re == ym
grep -Fq 'export ym_vl_re=${reym:-$ym}' "$ROOT/argosbx.sh" || { echo "FAIL: ym_vl_re auto-fill missing"; exit 1; }
grep -Fq 'export ym_vl_fb="127.0.0.1"' "$ROOT/argosbx.sh" || { echo "FAIL: ym_vl_fb logic missing"; exit 1; }

# No old-style fallback remains (all 8 converted)
[ "$(grep -c '"dest": "${ym_vl_re}:443"' "$ROOT/argosbx.sh")" = "0" ] || { echo "FAIL: old dest remains"; exit 1; }
[ "$(grep -c '"target": "${ym_vl_re}:443"' "$ROOT/argosbx.sh")" = "0" ] || { echo "FAIL: old target remains"; exit 1; }
[ "$(grep -c '"server": "${ym_vl_re}"' "$ROOT/argosbx.sh")" = "0" ] || { echo "FAIL: old handshake server remains"; exit 1; }

# SNI fields untouched
[ "$(grep -c '"server_name": "${ym_vl_re}"' "$ROOT/argosbx.sh")" -ge "1" ] || { echo "FAIL: SNI server_name missing"; exit 1; }

echo "PASS: reality fallback"
