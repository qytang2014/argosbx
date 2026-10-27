#!/bin/bash
# Test: egress geo databases (route 1) - detection, sing-box route
# config, gated download (fake curl, no network), xray asset dir.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Container carries the same geo code + hooks
grep -q 'egress_geo_setup' "$ROOT/container/nodejs/start.sh" || { echo "FAIL: container missing egress_geo_setup"; exit 1; }
grep -q 'egress_sb_geo_cfg' "$ROOT/container/nodejs/start.sh" || { echo "FAIL: container missing sb geo cfg hook"; exit 1; }
python3 - "$ROOT/argosbx.sh" "$TMP/egress.sh" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"# ===== EGRESS MODULE BEGIN.*?# ===== EGRESS MODULE END =====\n", t, re.S)
assert m, "EGRESS MODULE not found in argosbx.sh"
open(sys.argv[2], "w").write(m.group(0))
PY
# Fake curl: writes FAKE to the -o target
mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/curl" << 'EOF'
#!/bin/bash
out=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; *) shift;; esac; done
printf 'FAKE' > "$out"
EOF
chmod +x "$TMP/fakebin/curl"
cat > "$TMP/run.sh" << 'RUN'
#!/bin/bash
source "$1"
# Case A: geo rule -> needed, sb cfg, sb/xr rules present
egress_nodes="socks5://u:p@203.0.113.10:1080#socks-out"; egress_bind=""; egress_rules="geoip:cn=>socks-out;geosite:google=>socks-out"
egress_init
[ "$egress_geo_needed" = 1 ] || { echo "FAIL: geo needed not set"; exit 1; }
case "$egress_sb_geo_cfg" in *"geoip.db"*|*"geosite.db"*) ;; *) echo "FAIL: sb geo cfg missing db paths"; exit 1;; esac
printf '{"route": {%s"rules": [\n%s{"action":"route","outbound":"direct"}\n]}}\n' "$egress_sb_geo_cfg" "$egress_sb_rules" > "$2/sb_route.json"
# Case B: domain value containing 'geosite' must NOT trigger geo
egress_rules="domain:geosite.example.com=>socks-out"; egress_init
[ "$egress_geo_needed" = 0 ] || { echo "FAIL: domain rule wrongly triggers geo"; exit 1; }
[ -z "$egress_sb_geo_cfg" ] || { echo "FAIL: non-geo cfg not empty"; exit 1; }
# Case C: empty -> nothing
egress_nodes=""; egress_bind=""; egress_rules=""; egress_init
[ "$egress_geo_needed" = 0 ] && [ -z "$egress_sb_geo_cfg" ] && [ -z "$egress_sb_rules" ] || { echo "FAIL: empty egress not clean"; exit 1; }
# Case D: download with fake curl, then skip existing
export HOME="$2/home"
egress_nodes="socks5://u:p@203.0.113.10:1080#socks-out"; egress_rules="geoip:cn=>socks-out"; egress_init
egress_geo_setup
for f in geoip.db geosite.db geoip.dat geosite.dat; do
  [ "$(cat "$HOME/agsbx/$f")" = "FAKE" ] || { echo "FAIL: $f not downloaded by fake curl"; exit 1; }
done
[ "$XRAY_LOCATION_ASSET" = "$HOME/agsbx" ] || { echo "FAIL: XRAY_LOCATION_ASSET not set"; exit 1; }
for f in geoip.db geosite.db geoip.dat geosite.dat; do printf 'EXISTING' > "$HOME/agsbx/$f"; done
egress_geo_setup
for f in geoip.db geosite.db geoip.dat geosite.dat; do
  [ "$(cat "$HOME/agsbx/$f")" = "EXISTING" ] || { echo "FAIL: existing $f was re-downloaded"; exit 1; }
done
# Case E: download failure warns, removes partial file, setup does not abort
cat > "$2/fakebin/curl" << 'EOF2'
#!/bin/bash
exit 1
EOF2
chmod +x "$2/fakebin/curl"
rm -f "$HOME/agsbx/geoip.db"
egress_geo_setup || true
[ ! -e "$HOME/agsbx/geoip.db" ] || { echo "FAIL: failed download left a file"; exit 1; }
RUN
PATH="$TMP/fakebin:$PATH" bash "$TMP/run.sh" "$TMP/egress.sh" "$TMP"
python3 - "$TMP" << 'PY'
import json, sys
tmp = sys.argv[1]
d = json.load(open(f"{tmp}/sb_route.json"))
assert d["route"]["geoip"]["path"].endswith("/agsbx/geoip.db"), d["route"]
assert d["route"]["geosite"]["path"].endswith("/agsbx/geosite.db"), d["route"]
rules = d["route"]["rules"]
assert rules[0]["geoip"] == ["cn"], rules[0]
assert rules[1]["geosite"] == ["google"], rules[1]
print("PASS: egress geo (detection, sb route cfg, gated download, xray asset, failure handling)")
PY
