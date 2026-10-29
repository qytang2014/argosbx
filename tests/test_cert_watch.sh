#!/bin/bash
# Test: cert-watch in isolation, with mocked restarts (no real services).
# Cases: first run records hash without restart; unchanged cert does
# nothing; changed valid cert restarts and updates hash; invalid cert
# and wrong-domain cert do NOT restart and do NOT update hash.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
python3 - "$ROOT/argosbx.sh" "$TMP/watch.sh" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
for name in ["cert_cert_hash", "cert_uses_domain_cert", "cert_restart", "cert_watch"]:
    m = re.search(rf"{name}\(\)\{{.*?\n\}}\n", t, re.S)
    assert m, f"{name} not found"
    open(sys.argv[2], "a").write(m.group(0) + "\n")
PY
cat > "$TMP/run.sh" << 'RUN'
#!/bin/bash
export HOME="$1"
export CERT_DIR="$HOME/agsbx/cert"
export CERT_CRT="$CERT_DIR/cert.crt"
export CERT_KEY="$CERT_DIR/private.key"
mkdir -p "$HOME/agsbx" "$CERT_DIR"
printf 'x\n' > "$HOME/agsbx/sb.json"
printf 'agsbx/cert\n' >> "$HOME/agsbx/sb.json"
printf 'x\n' > "$HOME/agsbx/xr.json"
# mock restarts: record a call, do not touch real services
sbrestart(){ echo "sb" >> "$HOME/restart.log"; }
xrestart(){ echo "xr" >> "$HOME/restart.log"; }
source "$2"
mkcert(){ openssl req -new -x509 -days 365 -nodes -out "$CERT_CRT" -keyout "$CERT_KEY" -subj "/CN=$1" >/dev/null 2>&1; }
ym="test.example.com"
# 1. first run: records hash, no restart
mkcert test.example.com
cert_watch; [ ! -f "$HOME/restart.log" ] || { echo "FAIL: first run should not restart"; exit 1; }
[ -f "$HOME/agsbx/cert.hash" ] || { echo "FAIL: hash not recorded"; exit 1; }
# 2. unchanged: no restart
cert_watch; [ ! -f "$HOME/restart.log" ] || { echo "FAIL: unchanged should not restart"; exit 1; }
# 3. changed valid same-domain cert: restart both kernels in test (sb only? xr.json has no agsbx/cert in this test, only sb does)
mkcert test.example.com
cert_watch; grep -q "^sb$" "$HOME/restart.log" || { echo "FAIL: changed valid cert should restart sb"; exit 1; }
rm -f "$HOME/restart.log"
# 4. invalid cert: no restart, hash not updated (still the valid hash from step 3)
echo "not a cert" > "$CERT_CRT"
cert_watch; [ ! -f "$HOME/restart.log" ] || { echo "FAIL: invalid cert should not restart"; exit 1; }
# 5. wrong-domain cert: no restart
mkcert other.example.com
cert_watch; [ ! -f "$HOME/restart.log" ] || { echo "FAIL: wrong-domain cert should not restart"; exit 1; }
# 6. valid same-domain cert again (after the two skipped changes): should restart, proving hash was not updated by skipped cases
mkcert test.example.com
cert_watch; grep -q "^sb$" "$HOME/restart.log" || { echo "FAIL: valid cert after skipped cases should restart"; exit 1; }
rm -f "$HOME/restart.log"
# 7. expiring cert (<7 days): warns about expiry; first run records the new hash
# (restarts), second run has unchanged hash -> warns but does NOT restart
openssl req -new -x509 -days 3 -nodes -out "$CERT_CRT" -keyout "$CERT_KEY" -subj "/CN=test.example.com" >/dev/null 2>&1
rm -f "$HOME/restart.log"
out=$(cert_watch 2>&1); echo "$out" | grep -q "7 天内过期" || { echo "FAIL: expiring cert should warn"; exit 1; }
rm -f "$HOME/restart.log"
out=$(cert_watch 2>&1); echo "$out" | grep -q "7 天内过期" || { echo "FAIL: expiring cert should warn on repeat"; exit 1; }
[ ! -f "$HOME/restart.log" ] || { echo "FAIL: unchanged expiring cert should not restart"; exit 1; }
# 8. long-lived cert: no expiry warning
mkcert test.example.com
out=$(cert_watch 2>&1); echo "$out" | grep -q "7 天内过期" && { echo "FAIL: long-lived cert should not warn"; exit 1; }
echo "cert-watch cases OK"
RUN
bash "$TMP/run.sh" "$TMP/fakehome" "$TMP/watch.sh"
echo "PASS: cert-watch (first/unchanged/changed/invalid/wrong-domain)"
