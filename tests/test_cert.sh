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
for name in ["detect_certsrc", "detect_certmode", "write_caddyfile", "ensure_caddy_download", "caddy_fetch_cert", "wait_domain_cert"]:
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
# acme.sh --issue must pin --server letsencrypt (default CA is ZeroSSL which needs EAB registration)
[ "$(grep -c 'acme.sh" --issue --server letsencrypt' "$ROOT/argosbx.sh")" = "3" ] || { echo "FAIL: expected 3 --issue --server letsencrypt commands"; exit 1; }
# webroot mode: detect_certmode returns webroot, acme uses -w
grep -q 'if \[ "$certmode" = "webroot" \]; then echo "webroot"; return; fi' "$ROOT/argosbx.sh" || { echo "FAIL: webroot detect_certmode"; exit 1; }
grep -q 'acme.sh" --issue --server letsencrypt -w "$_webroot" -d "$ym"' "$ROOT/argosbx.sh" || { echo "FAIL: webroot --issue"; exit 1; }
# Caddy file_server (not respond "ok")
grep -q 'file_server' "$ROOT/argosbx.sh" || { echo "FAIL: caddy file_server missing"; exit 1; }
! grep -q 'respond "ok"' "$ROOT/argosbx.sh" || { echo "FAIL: respond ok should be gone"; exit 1; }
echo "acme.sh --server letsencrypt pinned OK"
# domain_cert_valid: valid cert -> 0, expiring/wrong-domain/missing -> 1
python3 - "$ROOT/argosbx.sh" "$TMP/certdir" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"domain_cert_valid\(\)\{.*?\n\}\n", t, re.S)
assert m, "domain_cert_valid not found"
open(f"{sys.argv[2]}/domain_cert_valid.sh", "w").write(m.group(0))
PY
cat > "$TMP/run_valid.sh" << 'RUN'
#!/bin/bash
source "$1/certdir/domain_cert_valid.sh"
export CERT_DIR="$1/certs" CERT_CRT="$1/certs/cert.crt" CERT_KEY="$1/certs/private.key"
mkdir -p "$1/certs"
ym="test.example.com"
# valid cert, 30 days, matching SAN -> 0
openssl req -x509 -newkey rsa:2048 -keyout "$CERT_KEY" -out "$CERT_CRT" -days 30 -nodes -subj "/CN=test.example.com" -addext "subjectAltName=DNS:test.example.com" 2>/dev/null
domain_cert_valid || { echo "FAIL: valid cert should pass"; exit 1; }
# expiring in 3 days -> 1
openssl req -x509 -newkey rsa:2048 -keyout "$CERT_KEY" -out "$CERT_CRT" -days 3 -nodes -subj "/CN=test.example.com" -addext "subjectAltName=DNS:test.example.com" 2>/dev/null
domain_cert_valid && { echo "FAIL: expiring cert should fail"; exit 1; }
# wrong domain -> 1
openssl req -x509 -newkey rsa:2048 -keyout "$CERT_KEY" -out "$CERT_CRT" -days 30 -nodes -subj "/CN=other.example.com" -addext "subjectAltName=DNS:other.example.com" 2>/dev/null
domain_cert_valid && { echo "FAIL: wrong domain should fail"; exit 1; }
# missing files -> 1
rm -f "$CERT_CRT" "$CERT_KEY"
domain_cert_valid && { echo "FAIL: missing files should fail"; exit 1; }
echo "domain_cert_valid OK"
RUN
bash "$TMP/run_valid.sh" "$TMP"
# ensure_caddy_download: GitHub Release direct download (generic releases repo), no private-server auth
grep -q 'https://github.com/qytang2014/software/releases/download/${caddy_ver}' "$ROOT/argosbx.sh" || { echo "FAIL: caddy download URL"; exit 1; }
grep -q 'caddy_ver="${CADDY_VER:-caddy-v2.11.7}"' "$ROOT/argosbx.sh" || { echo "FAIL: CADDY_VER default"; exit 1; }
grep -q '缺少 Coraza WAF 模块，拒绝替换' "$ROOT/argosbx.sh" || { echo "FAIL: coraza waf hard check should be back"; exit 1; }
grep -q 'http.handlers.waf' "$ROOT/argosbx.sh" || { echo "FAIL: waf module id check missing"; exit 1; }
! grep -q 'files.quinn.de5.net' "$ROOT/argosbx.sh" || { echo "FAIL: old caddy server should be gone"; exit 1; }
! grep -q 'CADDY_DOWNLOAD_PASS' "$ROOT/argosbx.sh" || { echo "FAIL: CADDY_DOWNLOAD_PASS should be gone"; exit 1; }
! grep -q 'netrc-file' "$ROOT/argosbx.sh" || { echo "FAIL: netrc should be gone"; exit 1; }
! grep -q 'caddy_x86_64' "$ROOT/argosbx.sh" || { echo "FAIL: old caddy_x86_64 name should be gone"; exit 1; }
echo "ensure_caddy_download static checks OK"
# ensure_caddy_download: URL construction per arch, override respected, no auth (curl stubbed to fail after recording args)
sed -e 's|"$(id -u 2>/dev/null)" = "0"|"0" = "0"|g' "$TMP/certdir/ensure_caddy_download.sh" > "$TMP/caddy_dl_test.sh"
cat > "$TMP/run_caddy_dl.sh" << 'RUN'
#!/bin/bash
source "$1"
CURL_ARGS="$2/curl_args"
curl() { printf '%s\n' "$@" > "$CURL_ARGS"; return 1; }
check_url() {
  cpu="$1"; rm -f "$CURL_ARGS"
  unset CADDY_DOWNLOAD_URL
  ensure_caddy_download >/dev/null 2>&1
  grep -q "https://github.com/qytang2014/software/releases/download/caddy-v2.11.7/$2" "$CURL_ARGS" || { echo "FAIL: $3 got: $(cat "$CURL_ARGS" 2>/dev/null)"; exit 1; }
  ! grep -q "netrc" "$CURL_ARGS" || { echo "FAIL: $3 should not use netrc"; exit 1; }
}
check_url amd64 "caddy-linux-amd64" "amd64 url"
check_url arm64 "caddy-linux-arm64" "arm64 url"
cpu="amd64"; CADDY_DOWNLOAD_URL="https://example.com/mirror"; rm -f "$CURL_ARGS"
ensure_caddy_download >/dev/null 2>&1
grep -q "https://example.com/mirror/caddy-linux-amd64" "$CURL_ARGS" || { echo "FAIL: CADDY_DOWNLOAD_URL override"; exit 1; }
cpu="mips"; ensure_caddy_download >/dev/null 2>&1 && { echo "FAIL: mips should fail"; exit 1; }
echo "ensure_caddy_download URL/auth/arch OK"
RUN
bash "$TMP/run_caddy_dl.sh" "$TMP/caddy_dl_test.sh" "$TMP"
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
echo "PASS: cert (certsrc, certmode, write_caddyfile, caddy-download, caddy-fetch)"
