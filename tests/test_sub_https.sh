#!/bin/bash
# HTTPS domain subscription: mode decide, memory gate, Caddy start/stop,
# 443 handling, websbx stop on https, display URLs, del stop, and
# cert-restart integration. Mock caddy/ufw/crontab/ps only; no real
# Caddy, no real ufw, no real network, no real install.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail(){ echo "FAIL: $1"; exit 1; }
check(){ grep -q "$2" "$1" || fail "$3"; }

# --- built file checks ---
python3 build/build.py >/dev/null 2>&1 || fail "build failed"
check argosbx.sh "sub_https_sync" "built script missing sub_https_sync"
check argosbx.sh "sub_https_display" "built script missing sub_https_display"
check argosbx.sh "subhttpsync" "built script missing subhttpsync dispatch"
check argosbx.sh "sub_https_stop" "built script missing sub_https_stop"
check argosbx.sh "Caddyfile.sub" "built script missing Caddyfile.sub"
check argosbx.sh "subhttpsync 重新同步" "built script missing showmode subhttpsync line"
# Original http-IP display block must be gone (replaced by sync+display);
# the unquoted outer-if sequence appears only in the old block, while
# the module display uses the quoted form.
if grep -q 'if \[ -s \$HOME/agsbx/subport.log \]; then' argosbx.sh; then fail "old display block still present"; fi
# Upstream must stay pristine (same check as test_build, cheap re-check)
grep -q "yonggekkk/argosbx/main/argosbx.sh" upstream/argosbx.sh || fail "upstream changed"

# --- isolated HOME + mocks ---
TESTHOME="$(mktemp -d)"; export HOME="$TESTHOME"
mkdir -p "$HOME/agsbx" "$HOME/websbx/token-123"
MOCKBIN="$(mktemp -d)"; export PATH="$MOCKBIN:$PATH"
UFLOG="$TESTHOME/ufw.log"; CRONFILE="$TESTHOME/crontab.txt"; touch "$CRONFILE"
export UFLOG CRONFILE
cat > "$MOCKBIN/caddy" <<'EOF'
#!/bin/bash
# Do NOT exec sleep: the process cmdline must keep the Caddyfile.sub
# argument, so subhttps_caddy_running can verify it (real Caddy's
# cmdline also contains its config path). The orphan sleep is killed
# by the pkill cleanup at the end of this test.
sleep 1000
EOF
chmod +x "$MOCKBIN/caddy"
cat > "$MOCKBIN/ufw" <<'EOF'
#!/bin/bash
if [ "$1" = "status" ]; then echo "Status: active"; exit 0; fi
echo "$@" >> "$UFLOG"
exit 0
EOF
chmod +x "$MOCKBIN/ufw"
cat > "$MOCKBIN/crontab" <<'EOF'
#!/bin/bash
if [ "$1" = "-l" ]; then cat "$CRONFILE" 2>/dev/null || true; exit 0; fi
cp "$1" "$CRONFILE"
exit 0
EOF
chmod +x "$MOCKBIN/crontab"
cat > "$MOCKBIN/ps" <<'EOF'
#!/bin/bash
echo "1234 user 0 0 0 0 ? Ss 00:00 0:00 busybox httpd -f -p $MOCK_PS_PORT -h $HOME/websbx"
EOF
chmod +x "$MOCKBIN/ps"

# shellcheck disable=SC1091
source "$ROOT/modules/sub-https.sh"

# --- cert + token/ym/port/ip setup ---
mkdir -p "$HOME/agsbx/cert"
openssl req -new -x509 -days 365 -nodes -keyout "$HOME/agsbx/cert/private.key" -out "$HOME/agsbx/cert/cert.crt" -subj "/CN=example.test" -addext "subjectAltName=DNS:example.test" >/dev/null 2>&1 || fail "cert generation failed"
echo "example.test" > "$HOME/agsbx/ym"
echo "token-123" > "$HOME/agsbx/subtoken.log"
echo "18080" > "$HOME/agsbx/subport.log"
echo "1.2.3.4" > "$HOME/agsbx/server_ip.log"
export MOCK_PS_PORT="18080"

# --- mode decide: no cert -> http-domain, low memory -> http-domain ---
rm "$HOME/agsbx/cert/cert.crt"
[ "$(subhttps_decide_mode)" = "http-domain" ] || fail "no cert should be http-domain"
openssl req -new -x509 -days 365 -nodes -keyout "$HOME/agsbx/cert/private.key" -out "$HOME/agsbx/cert/cert.crt" -subj "/CN=example.test" -addext "subjectAltName=DNS:example.test" >/dev/null 2>&1 || fail "cert regeneration failed"
export SUBHTTPS_MEM_KB=131072
[ "$(subhttps_decide_mode)" = "http-domain" ] || fail "low memory should be http-domain"
export SUBHTTPS_MEM_KB=524288
[ "$(subhttps_decide_mode)" = "https" ] || fail "high memory + cert should be https"

# --- https sync: Caddy starts, cron + 443 + websbx cron removed ---
echo '@reboot sleep 10 && /bin/bash -c "busybox httpd -f -p 18080 -h /tmp/websbx > /dev/null 2>&1 &"' > "$CRONFILE"
sub_https_sync || fail "https sync failed"
[ "$(cat "$HOME/agsbx/subhttps.mode")" = "https" ] || fail "mode file should be https"
check "$HOME/agsbx/Caddyfile.sub" "https://example.test" "Caddyfile missing site"
check "$HOME/agsbx/Caddyfile.sub" "admin off" "Caddyfile missing admin off"
check "$HOME/agsbx/Caddyfile.sub" "file_server" "Caddyfile missing file_server"
check "$HOME/agsbx/Caddyfile.sub" "agsbx/cert/cert.crt" "Caddyfile missing cert path"
subhttps_caddy_running || fail "Caddy should be running after https sync"
PID1="$(cat "$HOME/agsbx/subhttps.pid")"
grep -q "argosbx-subhttps" "$CRONFILE" || fail "subhttps cron missing"
grep -q "websbx" "$CRONFILE" && fail "websbx cron should be removed on https"
grep -q "allow 443/tcp" "$UFLOG" || fail "ufw 443 allow missing"
[ -f "$HOME/agsbx/subhttps.443" ] || fail "443 marker missing"

# --- display: https URLs ---
OUT="$(sub_https_display)"
echo "$OUT" | grep -q "https://example.test/token-123/clmi.yaml" || fail "display https clmi missing"
echo "$OUT" | grep -q "https://example.test/token-123/sbox.json" || fail "display https sbox missing"
echo "$OUT" | grep -q "https://example.test/token-123/jhsub.txt" || fail "display https jhsub missing"
echo "$OUT" | grep -q "http://1.2.3.4" && fail "display should not show http IP in https mode"

# --- second sync idempotent: same pid, no second 443 allow ---
sub_https_sync >/dev/null 2>&1 || fail "second sync failed"
[ "$(cat "$HOME/agsbx/subhttps.pid")" = "$PID1" ] || fail "second sync should not restart Caddy"
[ "$(grep -c "allow 443/tcp" "$UFLOG")" = "1" ] || fail "second sync should not re-allow 443"

# --- cert change restarts Caddy ---
openssl req -new -x509 -days 365 -nodes -keyout "$HOME/agsbx/cert/private.key" -out "$HOME/agsbx/cert/cert.crt" -subj "/CN=example.test" -addext "subjectAltName=DNS:example.test" >/dev/null 2>&1 || fail "cert change generation failed"
sub_https_sync >/dev/null 2>&1 || fail "sync after cert change failed"
subhttps_caddy_running || fail "Caddy should be running after cert change"
[ "$(cat "$HOME/agsbx/subhttps.pid")" != "$PID1" ] || fail "cert change should restart Caddy"

# --- low memory exception: Caddy already running stays https ---
export SUBHTTPS_MEM_KB=131072
[ "$(subhttps_decide_mode)" = "https" ] || fail "already-running Caddy should bypass memory gate"
# --- low memory after stop: falls back to http-domain, cleans up ---
subhttps_stop_caddy
sub_https_sync >/dev/null 2>&1 || fail "low-memory sync failed"
[ "$(cat "$HOME/agsbx/subhttps.mode")" = "http-domain" ] || fail "low memory after stop should be http-domain"
grep -q "delete allow 443/tcp" "$UFLOG" || fail "ufw 443 delete missing on fallback"
[ ! -f "$HOME/agsbx/subhttps.443" ] || fail "443 marker should be removed on fallback"
grep -q "argosbx-subhttps" "$CRONFILE" && fail "subhttps cron should be removed on fallback"
OUT="$(sub_https_display)"
echo "$OUT" | grep -q "http://example.test:18080/token-123/clmi.yaml" || fail "display http-domain clmi missing"

# --- subscription port: http opens it, port change diffs, https closes it ---
[ "$(cat "$HOME/agsbx/subhttps.subport" 2>/dev/null)" = "18080/tcp" ] || fail "http-domain should open subport 18080/tcp"
grep -q "allow 18080/tcp" "$UFLOG" || fail "ufw subport allow missing"
echo "18081" > "$HOME/agsbx/subport.log"
sub_https_sync >/dev/null 2>&1 || fail "subport change sync failed"
[ "$(cat "$HOME/agsbx/subhttps.subport" 2>/dev/null)" = "18081/tcp" ] || fail "subport change should update marker to 18081/tcp"
grep -q "delete allow 18080/tcp" "$UFLOG" || fail "ufw old subport delete missing on port change"
grep -q "allow 18081/tcp" "$UFLOG" || fail "ufw new subport allow missing on port change"
export SUBHTTPS_MEM_KB=524288
sub_https_sync >/dev/null 2>&1 || fail "https switch sync failed"
[ "$(cat "$HOME/agsbx/subhttps.mode")" = "https" ] || fail "https switch should be https"
[ ! -f "$HOME/agsbx/subhttps.subport" ] || fail "https should close subport"
grep -q "delete allow 18081/tcp" "$UFLOG" || fail "ufw subport delete missing on https switch"
# restore http-domain state for the following phases
export SUBHTTPS_MEM_KB=131072
echo "18080" > "$HOME/agsbx/subport.log"
subhttps_stop_caddy
sub_https_sync >/dev/null 2>&1 || fail "restore http-domain sync failed"

# --- caddy missing: http-domain, no start ---
mkdir -p "$TESTHOME/no-caddy-bin"
for b in ufw crontab ps; do cp "$MOCKBIN/$b" "$TESTHOME/no-caddy-bin/$b"; done
export PATH="$TESTHOME/no-caddy-bin:/usr/bin:/bin"
export SUBHTTPS_MEM_KB=524288
[ "$(subhttps_decide_mode)" = "http-domain" ] || fail "missing caddy should be http-domain"
sub_https_sync >/dev/null 2>&1 || fail "missing-caddy sync failed"
[ "$(cat "$HOME/agsbx/subhttps.mode")" = "http-domain" ] || fail "missing caddy mode should be http-domain"
[ ! -f "$HOME/agsbx/subhttps.pid" ] || fail "missing caddy should not leave pid"

# --- caddy start failure: falls back to http-domain ---
mkdir -p "$TESTHOME/fail-caddy-bin"
for b in ufw crontab ps; do cp "$MOCKBIN/$b" "$TESTHOME/fail-caddy-bin/$b"; done
printf '#!/bin/bash\nexit 1\n' > "$TESTHOME/fail-caddy-bin/caddy"; chmod +x "$TESTHOME/fail-caddy-bin/caddy"
export PATH="$TESTHOME/fail-caddy-bin:/usr/bin:/bin"
sub_https_sync >/dev/null 2>&1 || fail "fail-caddy sync should not fail the script"
[ "$(cat "$HOME/agsbx/subhttps.mode")" = "http-domain" ] || fail "failed Caddy start should fall back to http-domain"

# --- http-ip display (mock ps shows websbx port) ---
export PATH="$MOCKBIN:/usr/bin:/bin"
echo "http-ip" > "$HOME/agsbx/subhttps.mode"
rm -f "$HOME/agsbx/ym"
OUT="$(sub_https_display)"
echo "$OUT" | grep -q "http://1.2.3.4:18080/token-123/clmi.yaml" || fail "display http-ip clmi missing"

# --- cert-restart integration: guarded call runs when defined ---
export HOME="$TESTHOME"
CERT_CRT="$HOME/agsbx/cert/cert.crt"
echo '{"tls": {"certificate_path": "/root/agsbx/cert/cert.crt"}}' > "$HOME/agsbx/sb.json"
sbrestart(){ echo "sb restarted" >> "$TESTHOME/restart.log"; }
xrestart(){ echo "xr restarted" >> "$TESTHOME/restart.log"; }
source "$ROOT/modules/cert-watch.sh"
sub_https_sync(){ echo "sub sync called" >> "$TESTHOME/restart.log"; }
cert_restart
grep -q "sub sync called" "$TESTHOME/restart.log" || fail "cert_restart should call sub_https_sync when defined"
# Restore the real sub_https_sync (the stub above overrode it in this shell)
source "$ROOT/modules/sub-https.sh"

# --- del stop: everything removed, Caddy dead ---
export PATH="$MOCKBIN:/usr/bin:/bin"
echo "example.test" > "$HOME/agsbx/ym"
export SUBHTTPS_MEM_KB=524288
sub_https_sync >/dev/null 2>&1 || fail "re-https before del stop failed"
subhttps_caddy_running || fail "Caddy should be running before del stop"
sub_https_stop
subhttps_caddy_running && fail "Caddy should be dead after del stop"
[ ! -f "$HOME/agsbx/subhttps.mode" ] || fail "mode file should be removed on del stop"
[ ! -f "$HOME/agsbx/Caddyfile.sub" ] || fail "Caddyfile should be removed on del stop"
[ ! -f "$HOME/agsbx/subhttps.pid" ] || fail "pid file should be removed on del stop"

# --- ufwsync re-applies node + subscription ports ---
source "$ROOT/modules/ufw.sh"
echo "9999/tcp" > "$HOME/agsbx/ufw.rules"
echo "http-ip" > "$HOME/agsbx/subhttps.mode"
echo "18080" > "$HOME/agsbx/subport.log"
echo "token-123" > "$HOME/agsbx/subtoken.log"
rm -f "$HOME/agsbx/subhttps.subport" "$HOME/agsbx/subhttps.443"
: > "$UFLOG"
ufw_apply_saved >/dev/null 2>&1 || fail "ufw_apply_saved failed"
grep -q "allow 9999/tcp" "$UFLOG" || fail "ufwsync should re-apply node port"
grep -q "allow 18080/tcp" "$UFLOG" || fail "ufwsync should re-apply subscription port"
[ "$(cat "$HOME/agsbx/subhttps.subport" 2>/dev/null)" = "18080/tcp" ] || fail "ufwsync should write subport marker"

# --- del stop deletes the subscription port too ---
export SUBHTTPS_MEM_KB=131072
echo "example.test" > "$HOME/agsbx/ym"
sub_https_sync >/dev/null 2>&1 || fail "http-domain sync before del-subport failed"
[ -f "$HOME/agsbx/subhttps.subport" ] || fail "subport marker should exist before del stop"
: > "$UFLOG"
sub_https_stop
[ ! -f "$HOME/agsbx/subhttps.subport" ] || fail "subport marker should be removed on del stop"
grep -q "delete allow 18080/tcp" "$UFLOG" || fail "ufw subport delete missing on del stop"

# cleanup: kill any leftover mock caddy (exec sleep) from earlier phases
pkill -f "sleep 1000" 2>/dev/null || true
rm -rf "$TESTHOME" "$MOCKBIN" "$TESTHOME/no-caddy-bin" "$TESTHOME/fail-caddy-bin" 2>/dev/null || true
echo "test_sub_https PASS"
