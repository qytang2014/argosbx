#!/bin/bash
# Test: cert functions in isolation, without touching /etc/caddy.
# write_caddyfile is tested with /etc/caddy replaced by a temp dir
# in a copy of the function, so the test never writes to the real system.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/certdir"
python3 - "$ROOT/argosbx.sh" "$TMP/certdir" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
# cert module functions live in modules/cert.sh in source, but in the
# built file they are inline; extract by function names.
for name in ["detect_certsrc", "detect_certmode", "write_caddyfile"]:
    m = re.search(rf"{name}\(\)\{{.*?\n\}}\n", t, re.S)
    assert m, f"{name} not found"
    open(f"{sys.argv[2]}/{name}.sh", "w").write(m.group(0))
PY
# detect_certsrc: explicit overrides win, auto without caddy -> acme
cat > "$TMP/run_certsrc.sh" << 'RUN'
#!/bin/bash
source "$1/detect_certsrc.sh"
certsrc="caddy"; [ "$(detect_certsrc)" = "caddy" ] || { echo "FAIL: explicit caddy"; exit 1; }
certsrc="acme"; [ "$(detect_certsrc)" = "acme" ] || { echo "FAIL: explicit acme"; exit 1; }
certsrc=""; out="$(detect_certsrc)"; case "$out" in caddy|acme) ;; *) echo "FAIL: auto certsrc=$out"; exit 1;; esac
echo "certsrc explicit/auto OK: auto=$out"
RUN
bash "$TMP/run_certsrc.sh" "$TMP/certdir"
# detect_certmode: explicit, argo -> dns, otherwise http (no server_ip.log in test home)
cat > "$TMP/run_certmode.sh" << 'RUN'
#!/bin/bash
export HOME="$1"
source "$2/detect_certmode.sh"
certmode="http"; argo=""; agn=""; [ "$(detect_certmode)" = "http" ] || { echo "FAIL: explicit http"; exit 1; }
certmode="dns"; [ "$(detect_certmode)" = "dns" ] || { echo "FAIL: explicit dns"; exit 1; }
certmode=""; argo="y"; [ "$(detect_certmode)" = "dns" ] || { echo "FAIL: argo should be dns"; exit 1; }
certmode=""; argo=""; agn=""; [ "$(detect_certmode)" = "http" ] || { echo "FAIL: default should be http without server_ip.log"; exit 1; }
echo "certmode explicit/argo/default OK"
RUN
mkdir -p "$TMP/fakehome/agsbx"
bash "$TMP/run_certmode.sh" "$TMP/fakehome" "$TMP/certdir"
# write_caddyfile: system path replaced by temp dir, import added once, not duplicated
sed -e 's|/etc/caddy|'"$TMP"'/testetc|g' -e 's|"$(id -u 2>/dev/null)" = "0"|"0" = "0"|g' "$TMP/certdir/write_caddyfile.sh" > "$TMP/write_test.sh"
cat > "$TMP/run_write.sh" << 'RUN'
#!/bin/bash
export HOME="$1"
mkdir -p "$1/agsbx" "$2/testetc"
printf 'example.com {\n  reverse_proxy localhost:8080\n}\n' > "$2/testetc/Caddyfile"
source "$3"
ym="test.example.com"; certmode_selected="http"; write_caddyfile
grep -q "import argosbx.caddyfile" "$2/testetc/Caddyfile" || { echo "FAIL: import missing"; exit 1; }
grep -q 'test.example.com' "$2/testetc/argosbx.caddyfile" || { echo "FAIL: domain missing in caddyfile"; exit 1; }
ym="test.example.com"; certmode_selected="dns"; write_caddyfile
[ "$(grep -c "import argosbx.caddyfile" "$2/testetc/Caddyfile")" = "1" ] || { echo "FAIL: import duplicated"; exit 1; }
grep -q "dns cloudflare" "$2/testetc/argosbx.caddyfile" || { echo "FAIL: dns caddyfile missing cloudflare"; exit 1; }
echo "write_caddyfile system/import/dns OK"
RUN
bash "$TMP/run_write.sh" "$TMP/fakehome" "$TMP" "$TMP/write_test.sh"
echo "PASS: cert (certsrc, certmode, write_caddyfile)"
