#!/bin/bash
# Test: cert functions in isolation, verifying strict convergence to caddy_proxy.sh.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/certdir"
python3 - "$ROOT/argosbx.sh" "$TMP/certdir" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
for name in ["detect_certsrc", "detect_certmode", "cert_setup_caddy_proxy", "caddy_fetch_cert", "wait_domain_cert", "domain_cert_valid"]:
    m = re.search(rf"{name}\(\)\{{.*?\n\}}\n", t, re.S)
    assert m, f"{name} not found"
    open(f"{sys.argv[2]}/{name}.sh", "w").write(m.group(0))
# Verify legacy direct-edit bypass functions are completely converged out of argosbx.sh
for removed in ["write_caddyfile()", "ensure_caddy_download()", "cleanup_legacy_argosbx_caddyfile()"]:
    assert removed not in t, f"legacy bypass function {removed} should be removed from argosbx.sh"
PY

# detect_certsrc: explicit overrides win, auto returns caddy or acme
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

# cert_setup_caddy_proxy: strict delegation + --no-default / --root / --proxy routing
cat > "$TMP/run_proxy_setup.sh" << 'RUN'
#!/bin/bash
export HOME="$1"
ROOT="$3"
mkdir -p "$1/.local/bin" "$1/agsbx"
ensure_proxy_script() { return 0; }
check_and_prompt_force_email() { echo ""; }
source "$ROOT/modules/camouflage-blog.sh"
source "$2/certdir/cert_setup_caddy_proxy.sh"

# Test 1: No proxy script -> fails loudly (returns 1)
cert_setup_caddy_proxy "test.example.com" "http" "" "$1/www" "" "" 2>/dev/null && { echo "FAIL: missing proxy script should return 1"; exit 1; }

# Install mock caddy_proxy.sh
cat > "$1/.local/bin/caddy_proxy.sh" << 'PROXY'
#!/bin/bash
echo "$@" >> "$HOME/proxy_calls.log"
exit 0
PROXY
chmod +x "$1/.local/bin/caddy_proxy.sh"

# Test 2: ym != reym (or reym empty) -> --no-default, NO blog deployed
: > "$1/proxy_calls.log"
ym="test.example.com" reym="" vlp="yes" cert_setup_caddy_proxy "test.example.com" "http" "admin@example.com" "$1/www-skip" "" "" || { echo "FAIL: no-default mode should return 0"; exit 1; }
grep -q "init --email admin@example.com" "$1/proxy_calls.log" || { echo "FAIL: init call missing"; exit 1; }
grep -q "site --domain test.example.com --no-default --email admin@example.com --force" "$1/proxy_calls.log" || { echo "FAIL: expected --no-default site call, got: $(cat "$1/proxy_calls.log")"; exit 1; }
[ ! -e "$1/www-skip/index.html" ] || { echo "FAIL: blog should not be deployed when reym is empty"; exit 1; }
[ "$(cat "$1/agsbx/caddyfile_path")" = "/etc/caddy/Caddyfile" ] || { echo "FAIL: caddyfile_path not written"; exit 1; }

# Test 3: Reality + reym == ym -> deploys blog and passes --root
: > "$1/proxy_calls.log"
deploy_camouflage_blog() { mkdir -p "$1"; echo "blog" > "$1/index.html"; }
ym="test.example.com" reym="test.example.com" vlp="yes" cert_setup_caddy_proxy "test.example.com" "dns" "admin@example.com" "$1/www-same" "" "" || { echo "FAIL: same-domain mode should return 0"; exit 1; }
grep -q "site --domain test.example.com --root $1/www-same --email admin@example.com --dns cloudflare --force" "$1/proxy_calls.log" || { echo "FAIL: expected --root + --dns cloudflare call, got: $(cat "$1/proxy_calls.log")"; exit 1; }
[ -f "$1/www-same/index.html" ] || { echo "FAIL: blog should be deployed when Reality + reym == ym"; exit 1; }

# Test 4: web_proxy host:port -> passes --proxy, no blog
: > "$1/proxy_calls.log"
ym="test.example.com" reym="test.example.com" vlp="yes" cert_setup_caddy_proxy "test.example.com" "http" "" "$1/www-proxy" "" "127.0.0.1:8080" || { echo "FAIL: web_proxy mode should return 0"; exit 1; }
grep -q "site --domain test.example.com --proxy 127.0.0.1:8080 --force" "$1/proxy_calls.log" || { echo "FAIL: expected --proxy call, got: $(cat "$1/proxy_calls.log")"; exit 1; }
[ ! -e "$1/www-proxy/index.html" ] || { echo "FAIL: blog should not be deployed when web_proxy is set"; exit 1; }

# Test 5: web_proxy /custom/dir -> passes --root /custom/dir, no blog
: > "$1/proxy_calls.log"
ym="test.example.com" reym="test.example.com" vlp="yes" cert_setup_caddy_proxy "test.example.com" "http" "" "$1/www-static" "" "/srv/my-app" || { echo "FAIL: custom static root mode should return 0"; exit 1; }
grep -q "site --domain test.example.com --root /srv/my-app --force" "$1/proxy_calls.log" || { echo "FAIL: expected --root /srv/my-app call, got: $(cat "$1/proxy_calls.log")"; exit 1; }

echo "cert_setup_caddy_proxy OK"
RUN
mkdir -p "$TMP/proxyhome"
bash "$TMP/run_proxy_setup.sh" "$TMP/proxyhome" "$TMP" "$ROOT"

# Scope safety check: modules/cert-main.sh must not contain 'local' declarations outside functions
! grep -E '^[[:space:]]*local[[:space:]]+' "$ROOT/modules/cert-main.sh" || { echo "FAIL: cert-main.sh contains top-level local declaration"; exit 1; }
echo "cert-main.sh scope safety OK"

# acme.sh --issue must pin --server letsencrypt (default CA is ZeroSSL which needs EAB registration)
[ "$(grep -c 'acme.sh" --issue --server letsencrypt' "$ROOT/argosbx.sh")" = "3" ] || { echo "FAIL: expected 3 --issue --server letsencrypt commands"; exit 1; }
grep -q 'if \[ "$certmode" = "webroot" \]; then echo "webroot"; return; fi' "$ROOT/argosbx.sh" || { echo "FAIL: webroot detect_certmode"; exit 1; }
grep -q 'acme.sh" --issue --server letsencrypt -w "$_webroot" -d "$ym"' "$ROOT/argosbx.sh" || { echo "FAIL: webroot --issue"; exit 1; }
! grep -q 'respond "ok"' "$ROOT/argosbx.sh" || { echo "FAIL: respond ok should be gone"; exit 1; }
echo "acme.sh --server letsencrypt pinned OK"

# domain_cert_valid: valid cert -> 0, expiring/wrong-domain/missing -> 1
cat > "$TMP/run_valid.sh" << 'RUN'
#!/bin/bash
source "$1/certdir/domain_cert_valid.sh"
export CERT_DIR="$1/certs" CERT_CRT="$1/certs/cert.crt" CERT_KEY="$1/certs/private.key"
mkdir -p "$1/certs"
ym="test.example.com"
openssl req -x509 -newkey rsa:2048 -keyout "$CERT_KEY" -out "$CERT_CRT" -days 30 -nodes -subj "/CN=test.example.com" -addext "subjectAltName=DNS:test.example.com" 2>/dev/null
domain_cert_valid || { echo "FAIL: valid cert should pass"; exit 1; }
openssl req -x509 -newkey rsa:2048 -keyout "$CERT_KEY" -out "$CERT_CRT" -days 3 -nodes -subj "/CN=test.example.com" -addext "subjectAltName=DNS:test.example.com" 2>/dev/null
domain_cert_valid && { echo "FAIL: expiring cert should fail"; exit 1; }
openssl req -x509 -newkey rsa:2048 -keyout "$CERT_KEY" -out "$CERT_CRT" -days 30 -nodes -subj "/CN=other.example.com" -addext "subjectAltName=DNS:other.example.com" 2>/dev/null
domain_cert_valid && { echo "FAIL: wrong domain should fail"; exit 1; }
rm -f "$CERT_CRT" "$CERT_KEY"
domain_cert_valid && { echo "FAIL: missing files should fail"; exit 1; }
echo "domain_cert_valid OK"
RUN
bash "$TMP/run_valid.sh" "$TMP"

# caddy_fetch_cert: sync from Caddy storage to fixed dir (valid -> copy, wrong-domain/missing -> fail)
mkdir -p "$TMP/caddystore/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/test.example.com"
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/caddystore/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/test.example.com/test.example.com.key" -out "$TMP/caddystore/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/test.example.com/test.example.com.crt" -days 30 -nodes -subj "/CN=test.example.com" -addext "subjectAltName=DNS:test.example.com" 2>/dev/null
mkdir -p "$TMP/fakestore/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/other.example.com"
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/fakestore/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/other.example.com/other.example.com.key" -out "$TMP/fakestore/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/other.example.com/other.example.com.crt" -days 30 -nodes -subj "/CN=other.example.com" -addext "subjectAltName=DNS:other.example.com" 2>/dev/null
cat > "$TMP/run_caddy_fetch.sh" << 'RUN'
#!/bin/bash
source "$1/certdir/caddy_fetch_cert.sh"
export CERT_DIR="$2/fetchcert" CERT_CRT="$2/fetchcert/cert.crt" CERT_KEY="$2/fetchcert/private.key"
export CADDY_STORAGE_CANDIDATES="$2/caddystore/.local/share/caddy"
ym="test.example.com"
caddy_fetch_cert || { echo "FAIL: valid caddy cert should sync"; exit 1; }
[ -s "$CERT_CRT" ] && [ -s "$CERT_KEY" ] || { echo "FAIL: files not copied"; exit 1; }
openssl x509 -in "$CERT_CRT" -noout -subject 2>/dev/null | grep -q "test.example.com" || { echo "FAIL: copied cert wrong"; exit 1; }
rm -rf "$2/fetchcert"; export CADDY_STORAGE_CANDIDATES="$2/fakestore/.local/share/caddy"
caddy_fetch_cert && { echo "FAIL: wrong-domain cert should not sync"; exit 1; }
[ ! -e "$CERT_CRT" ] || { echo "FAIL: wrong-domain cert was copied"; exit 1; }
export CADDY_STORAGE_CANDIDATES="$2/nostore"
caddy_fetch_cert && { echo "FAIL: missing storage should fail"; exit 1; }
echo "caddy_fetch_cert OK"
RUN
bash "$TMP/run_caddy_fetch.sh" "$TMP" "$TMP"

# wait_domain_cert in caddy mode picks up the cert via fetch on first iteration (no sleep)
cat > "$TMP/run_wait_caddy.sh" << 'RUN'
#!/bin/bash
source "$1/certdir/caddy_fetch_cert.sh"
source "$1/certdir/wait_domain_cert.sh"
export CERT_DIR="$2/waitcert" CERT_CRT="$2/waitcert/cert.crt" CERT_KEY="$2/waitcert/private.key"
export CADDY_STORAGE_CANDIDATES="$2/caddystore/.local/share/caddy"
ym="test.example.com"; certsrc_selected="caddy"
wait_domain_cert || { echo "FAIL: wait should succeed via caddy fetch"; exit 1; }
echo "wait_domain_cert caddy-mode OK"
RUN
bash "$TMP/run_wait_caddy.sh" "$TMP" "$TMP"

echo "PASS: cert (certsrc, certmode, cert_setup_caddy_proxy, domain_cert_valid, caddy-fetch)"
