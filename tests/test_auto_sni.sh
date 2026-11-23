#!/bin/bash
# Test: Reality auto-SNI (modules/auto-sni.sh + build wiring + standalone mirror).
# No network: curl/dig/host/shuf are stubbed via PATH. The module is
# sourced directly; the ins() trigger guard is extracted from the
# built script and evaluated in a harness.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
BUILT="$ROOT/argosbx.sh"
MOD="$ROOT/modules/auto-sni.sh"
STANDALONE="$ROOT/scripts/auto_find_reality_sni.sh"

# ---------- 1. structural: module present, call placed, generator text ----------
bash -n "$MOD" || fail "modules/auto-sni.sh syntax"
bash -n "$STANDALONE" || fail "scripts/auto_find_reality_sni.sh syntax"
grep -q '^auto_sni_resolve()' "$BUILT" || fail "built script missing auto_sni_resolve()"
grep -q '# auto-sni.sh' "$BUILT" || fail "built script missing auto-sni module header"
n=$(grep -c 'auto_sni_resolve || exit 1' "$BUILT" || true)
[ "$n" = "1" ] || fail "auto_sni_resolve call count $n (expected 1)"
ins_line=$(grep -n '^ins(){' "$BUILT" | head -1 | cut -d: -f1)
call_line=$(grep -n 'auto_sni_resolve || exit 1' "$BUILT" | cut -d: -f1)
vlpt_on_line=$(grep -n '^vlpt_on=""$' "$BUILT" | head -1 | cut -d: -f1)
install_line=$(awk -v s="$ins_line" 'NR>s && /^installxray$/{print NR; exit}' "$BUILT")
[ "$ins_line" -lt "$vlpt_on_line" ] || fail "vlpt_on not inside ins()"
[ "$vlpt_on_line" -lt "$call_line" ] || fail "auto-sni call ($call_line) not after vlpt_on ($vlpt_on_line)"
[ "$call_line" -lt "$install_line" ] || fail "auto-sni call ($call_line) not before first installxray ($install_line)"
# the 6 apple.com fallbacks are kept as the last resort
[ "$(grep -c '^ym_vl_re=apple.com$' "$BUILT" || true)" = "2" ] || fail "direct apple.com fallback count wrong"
[ "$(grep -c 'if \[ -z "\$ym_vl_re" \]; then ym_vl_re=apple.com; fi' "$BUILT" || true)" = "4" ] || fail "guarded apple.com fallback count wrong"
# container reym=apple.com untouched (container does not run ins())
grep -q 'reym=apple.com' "$ROOT/container/nodejs/start.sh" || fail "container reym default changed"
# generator placeholders say auto-detect now
grep -q 'reym 留空则自动探测' "$ROOT/index.html" || fail "ym placeholder not updated"
grep -q '留空自动探测；填自有域名' "$ROOT/index.html" || fail "reym placeholder not updated"
[ "$(grep -c 'apple.com' "$ROOT/index.html" || true)" = "0" ] || fail "index.html still mentions apple.com"
# standalone mirror: shared logic identical to the module (only the
# header and the trailing main() differ)
mirror_diff=$(diff <(sed -n '/^_AUTO_SNI_MAX_TEST_DOMAINS/,$p' "$MOD") \
     <(sed -n '/^_AUTO_SNI_MAX_TEST_DOMAINS/,/^# --- 独立脚本主流程/p' "$STANDALONE") \
  | grep -E '^[<>]' | grep -v '^> *$' | grep -v '^> # --- 独立脚本主流程' || true)
[ -z "$mirror_diff" ] || fail "standalone mirror drifted from modules/auto-sni.sh: $mirror_diff"
echo "ok: structural (module+call in ins, fallbacks kept, generator text, mirror in sync)"

# ---------- 2. functional: stubbed network ----------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/stubbin"

# fake dig/host: supports optional FAKE_CNAME_FILE and FAKE_CN_CNAME_FILE (for +subnet= Geo-DNS tests)
cat > "$TMP/stubbin/dig" << 'FAKEDIG'
#!/bin/bash
is_ecs=0
domain=""
for a in "$@"; do
  case "$a" in
    +subnet=*) is_ecs=1 ;;
    @*|+*|CNAME) ;;
    *) domain="$a" ;;
  esac
done
if [ "$is_ecs" = "1" ] && [ -n "${FAKE_CN_CNAME_FILE:-}" ] && [ -n "$domain" ]; then
  awk -v d="$domain" '$1==d {print $2; exit}' "$FAKE_CN_CNAME_FILE" 2>/dev/null || true
elif [ "$is_ecs" = "0" ] && [ -n "${FAKE_CNAME_FILE:-}" ] && [ -n "$domain" ]; then
  awk -v d="$domain" '$1==d {print $2; exit}' "$FAKE_CNAME_FILE" 2>/dev/null || true
fi
exit 0
FAKEDIG
printf '#!/bin/bash\nexit 0\n' > "$TMP/stubbin/host"
# fake shuf: identity (deterministic order for tests)
printf '#!/bin/bash\ncat "$@"\n' > "$TMP/stubbin/shuf"
# fake curl: canned responses driven by FAKE_* env files; logs calls
cat > "$TMP/stubbin/curl" << 'FAKECURL'
#!/bin/bash
[ -n "${FAKE_CURL_LOG:-}" ] && printf '%s\n' "curl $*" >> "$FAKE_CURL_LOG"
url=""; outfile=""; hdrfile=""; curves=""; prev=""
for a in "$@"; do
  case "$prev" in
    -o) outfile="$a" ;;
    -D) hdrfile="$a" ;;
    --curves) curves="$a" ;;
  esac
  case "$a" in http*) url="$a" ;; esac
  prev="$a"
done
if [ "$1" = "--version" ]; then
  sslv="${FAKE_CURL_OPENSSL_VER:-3.0.2}"
  if [ "${FAKE_CURL_VERSION_H2:-1}" = "0" ]; then
    printf 'curl 7.81.0 (x86_64-pc-linux-gnu) libcurl/7.81.0 OpenSSL/%s zlib/1.2.11\nRelease-Date: 2022-01-05\nProtocols: dict file ftp ftps gopher gophers http https imap imaps ldap ldaps mqtt pop3 pop3s rtsp scp sftp smb smbs smtp smtps telnet tftp\nFeatures: alt-svc AsynchDNS HSTS HTTPS-proxy IPv6 Largefile libz NTLM NTLM_WB PSL SSL UnixSockets\n' "$sslv"
  else
    printf 'curl 7.81.0 (x86_64-pc-linux-gnu) libcurl/7.81.0 OpenSSL/%s zlib/1.2.11 nghttp2/1.43.0\nRelease-Date: 2022-01-05\nProtocols: dict file ftp ftps gopher gophers http https imap imaps ldap ldaps mqtt pop3 pop3s rtsp scp sftp smb smbs smtp smtps telnet tftp\nFeatures: alt-svc AsynchDNS brotli HSTS HTTP2 HTTPS-proxy IPv6 Largefile libz NTLM NTLM_WB PSL SSL UnixSockets\n' "$sslv"
  fi
  exit 0
fi
case "$url" in
  *ipinfo.io/json*)
    cat "${FAKE_GEO_FILE:-/dev/null}"; exit 0 ;;
  *university-domains-list*)
    cat "${FAKE_UNIV_FILE:-/dev/null}" > "$outfile"; exit 0 ;;
  *v2ray-rules-dat*|*gfw.txt*)
    cat "${FAKE_GFW_FILE:-/dev/null}" > "$outfile"; exit 0 ;;
  *cloudflare-dns.com*|*dns.google/resolve*)
    printf '{"Status":0,"Question":[{"name":"x","type":5}],"Answer":[]}'; exit 0 ;;
  https://*)
    domain="${url#https://}"; domain="${domain%%/*}"
    if [ -n "${FAKE_FAIL_FILE:-}" ] && grep -qx "$domain" "$FAKE_FAIL_FILE" 2>/dev/null; then exit 1; fi
    if [ "$curves" = "X25519MLKEM768:X25519" ] && [ -n "${FAKE_PQ_FAIL_FILE:-}" ] && grep -qx "$domain" "$FAKE_PQ_FAIL_FILE" 2>/dev/null; then exit 35; fi
    lat="0.100"
    if [ -n "${FAKE_LATENCY_FILE:-}" ]; then
      lat=$(awk -v d="$domain" '$1==d {print $2; exit}' "$FAKE_LATENCY_FILE" 2>/dev/null || true)
      [ -n "$lat" ] || lat="0.100"
    fi
    code="200"
    if [ -n "${FAKE_HTTP_CODE_FILE:-}" ]; then
      code=$(awk -v d="$domain" '$1==d {print $2; exit}' "$FAKE_HTTP_CODE_FILE" 2>/dev/null || true)
      [ -n "$code" ] || code="200"
    fi
    if [ -n "${FAKE_H2_FILE:-}" ] && grep -qx "$domain" "$FAKE_H2_FILE" 2>/dev/null; then
      [ -n "$hdrfile" ] && printf 'HTTP/2 %s\r\ncontent-type: text/html\r\n\r\n' "$code" > "$hdrfile"
    else
      [ -n "$hdrfile" ] && printf 'HTTP/1.1 %s\r\ncontent-type: text/html\r\n\r\n' "$code" > "$hdrfile"
    fi
    printf '%s|0.010|%s|93.184.216.34' "$code" "$lat"
    exit 0 ;;
esac
echo "fake-curl: unexpected URL: $url" >&2
exit 1
FAKECURL
chmod +x "$TMP/stubbin/curl" "$TMP/stubbin/dig" "$TMP/stubbin/host" "$TMP/stubbin/shuf"

# fixtures: mit.edu FIRST in the JSON (the mawk bug used to return it
# for cc=GB); the GB pick must come from the country/state match.
cat > "$TMP/univ.json" << 'EOF'
[
  {
    "web_pages": ["http://www.mit.edu/"],
    "name": "Massachusetts Institute of Technology",
    "alpha_two_code": "US",
    "state-province": "Massachusetts",
    "domains": ["mit.edu"],
    "country": "United States"
  },
  {
    "web_pages": ["http://www.example.ac.uk/"],
    "name": "University of Example",
    "alpha_two_code": "GB",
    "state-province": "England",
    "domains": ["example.ac.uk"],
    "country": "United Kingdom"
  },
  {
    "web_pages": ["http://www.cam.ac.uk/"],
    "name": "University of Cambridge",
    "alpha_two_code": "GB",
    "state-province": null,
    "domains": ["cam.ac.uk"],
    "country": "United Kingdom"
  },
  {
    "web_pages": ["http://www.ed.ac.uk/"],
    "name": "University of Edinburgh",
    "alpha_two_code": "GB",
    "state-province": "Scotland",
    "domains": ["ed.ac.uk"],
    "country": "United Kingdom"
  }
]
EOF
printf '%s\n' '{"ip": "1.2.3.4", "city": "London", "region": "England", "country": "GB", "org": "AS1234 Example ISP"}' > "$TMP/geo-gb-eng.json"
printf '%s\n' '{"ip": "1.2.3.4", "city": "London", "country": "GB", "org": "AS1234 Example ISP"}' > "$TMP/geo-gb-noregion.json"
: > "$TMP/geo-empty.json"
: > "$TMP/gfw-empty.txt"
printf '%s\n' 'example.ac.uk' > "$TMP/gfw-block-example.txt"

# runner: sources the module, calls auto_sni_resolve (direct mode) or
# the extracted ins() guard (guard mode), prints rc/reym/ym_vl_re.
cat > "$TMP/run_sni.sh" << 'RUN'
#!/bin/bash
# $1 = direct|guard, $2 = guard file (guard mode only)
ROOT="$1"; shift
MODE="$1"; shift
. "$ROOT/modules/auto-sni.sh"
ym_vl_re=""; reym=""
if [ "$MODE" = "guard" ]; then
  vlp=yes
  . "$1"
else
  auto_sni_resolve
fi
echo "rc=$? reym=${reym:-} ym_vl_re=${ym_vl_re:-}"
RUN
chmod +x "$TMP/run_sni.sh"

# run one module scenario; env vars FAKE_GEO_FILE/FAKE_H2_FILE/
# FAKE_LATENCY_FILE/FAKE_GFW_FILE/FAKE_UNIV_FILE must be set by caller.
# $1 = expected rc, $2 = expected reym (empty = none), $3 = label
run_case() {
  local want_rc="$1" want_reym="$2" label="$3"
  local out rc reym
  out=$(FAKE_GEO_FILE="$FAKE_GEO_FILE" FAKE_UNIV_FILE="$TMP/univ.json" \
    FAKE_GFW_FILE="${FAKE_GFW_FILE:-$TMP/gfw-empty.txt}" \
    FAKE_H2_FILE="$FAKE_H2_FILE" FAKE_LATENCY_FILE="$FAKE_LATENCY_FILE" \
    FAKE_HTTP_CODE_FILE="${FAKE_HTTP_CODE_FILE:-}" \
    FAKE_CNAME_FILE="${FAKE_CNAME_FILE:-}" \
    FAKE_CN_CNAME_FILE="${FAKE_CN_CNAME_FILE:-}" \
    FAKE_PQ_FAIL_FILE="${FAKE_PQ_FAIL_FILE:-}" \
    FAKE_CURL_OPENSSL_VER="${FAKE_CURL_OPENSSL_VER:-3.0.2}" \
    FAKE_CURL_VERSION_H2="${FAKE_CURL_VERSION_H2:-1}" \
    FAKE_FAIL_FILE="${FAKE_FAIL_FILE:-}" FAKE_CURL_LOG="${FAKE_CURL_LOG:-}" \
    reym_tier="${reym_tier:-}" \
    PATH="$TMP/stubbin:$PATH" \
    bash "$TMP/run_sni.sh" "$ROOT" direct) || true
  rc=$(printf '%s' "$out" | grep -oE 'rc=[0-9]+' | cut -d= -f2)
  reym=$(printf '%s' "$out" | grep -oE 'reym=[^ ]*' | cut -d= -f2)
  [ "$rc" = "$want_rc" ] || fail "$label: rc=$rc want $want_rc (out: $out)"
  [ "$reym" = "$want_reym" ] || fail "$label: reym=$reym want $want_reym (out: $out)"
  echo "ok: $label -> reym=${reym:-<none>} rc=$rc"
}

mk_h2() { if [ $# = 0 ]; then : > "$TMP/h2.txt"; else printf '%s\n' "$@" > "$TMP/h2.txt"; fi; FAKE_H2_FILE="$TMP/h2.txt"; }
mk_lat() { if [ $# = 0 ]; then : > "$TMP/lat.txt"; else printf '%s\n' "$@" > "$TMP/lat.txt"; fi; FAKE_LATENCY_FILE="$TMP/lat.txt"; }

# 1. tier 1 curated local institutions (sub=1) beat Hipo universities (sub=2/3)
FAKE_GEO_FILE="$TMP/geo-gb-eng.json"
mk_h2 www.example.ac.uk www.cam.ac.uk www.ed.ac.uk www.ox.ac.uk
mk_lat "www.example.ac.uk 0.010" "www.cam.ac.uk 0.050" "www.ed.ac.uk 0.040" "www.ox.ac.uk 0.060"
run_case 0 www.ed.ac.uk "tier1 curated institution beats faster Hipo uni"
# 1b. when curated institutions fail, Hipo same-state (sub=2) beats faster Hipo same-country (sub=3)
# (also proves the mawk extraction fix: mit.edu is first in the JSON, must not be picked)
mk_h2 www.example.ac.uk cam.ac.uk ed.ac.uk
mk_lat "www.example.ac.uk 0.080" "cam.ac.uk 0.050" "ed.ac.uk 0.040"
run_case 0 www.example.ac.uk "tier1 Hipo same-state beats faster Hipo same-country"
# 2. no region: curated/same-country fastest wins
FAKE_GEO_FILE="$TMP/geo-gb-noregion.json"
mk_h2 www.example.ac.uk www.cam.ac.uk www.ed.ac.uk www.ox.ac.uk
mk_lat "www.example.ac.uk 0.080" "www.cam.ac.uk 0.050" "www.ed.ac.uk 0.040" "www.ox.ac.uk 0.060"
run_case 0 www.ed.ac.uk "tier1 same-country fastest wins"
# 3. tier 1 has no H2 -> tier 2 (de-popularized direct origin beats tier 3)
FAKE_GEO_FILE="$TMP/geo-gb-eng.json"
mk_h2 git.kernel.org learn.microsoft.com swscan.apple.com
mk_lat "git.kernel.org 0.070" "learn.microsoft.com 0.050" "swscan.apple.com 0.040"
run_case 0 git.kernel.org "tier2 fallback beats tier3 tutorial domains"
# 4. tiers 1-2 have no H2 -> tier 3 (swscan/learn.microsoft.com, last resort)
mk_h2 swscan.apple.com
mk_lat "swscan.apple.com 0.090"
run_case 0 swscan.apple.com "tier3 swscan last resort"
# 4b. root university domain works when www.<univ> fails/is on CDN
mk_h2 example.ac.uk
mk_lat "example.ac.uk 0.065"
run_case 0 example.ac.uk "tier1 root university domain fallback when www fails"
# 5. nothing passes -> fail (install must stop)
mk_h2
mk_lat
run_case 1 "" "all fail -> exit 1"
# 6. H2 is a hard requirement: same-state domain without H2 loses to a
# slower H2 domain (and would win if H2 were ignored)
mk_h2 www.cam.ac.uk
mk_lat "www.example.ac.uk 0.010" "www.cam.ac.uk 0.200"
run_case 0 www.cam.ac.uk "H2 hard requirement (non-H2 same-state rejected)"
# 7. curl without HTTP/2 support -> fail loudly, no silent downgrade
FAKE_CURL_VERSION_H2=0
mk_h2 www.example.ac.uk
out=$(FAKE_GEO_FILE="$TMP/geo-gb-eng.json" FAKE_UNIV_FILE="$TMP/univ.json" \
  FAKE_GFW_FILE="$TMP/gfw-empty.txt" FAKE_H2_FILE="$FAKE_H2_FILE" \
  FAKE_LATENCY_FILE="$FAKE_LATENCY_FILE" FAKE_CURL_VERSION_H2=0 \
  PATH="$TMP/stubbin:$PATH" bash "$TMP/run_sni.sh" "$ROOT" direct 2>&1) || true
printf '%s' "$out" | grep -q 'rc=1' || fail "no-H2 curl: rc not 1 (out: $out)"
printf '%s' "$out" | grep -q 'HTTP/2' || fail "no-H2 curl: message must name HTTP/2 (out: $out)"
echo "ok: no-H2 curl fails loudly"
FAKE_CURL_VERSION_H2=1
# 8. GFW list blocks the would-be winner -> next best picked
FAKE_GEO_FILE="$TMP/geo-gb-eng.json"
FAKE_GFW_FILE="$TMP/gfw-block-example.txt"
mk_h2 www.example.ac.uk www.cam.ac.uk www.ed.ac.uk www.ox.ac.uk
mk_lat "www.example.ac.uk 0.010" "www.cam.ac.uk 0.050" "www.ed.ac.uk 0.040" "www.ox.ac.uk 0.060"
run_case 0 www.ed.ac.uk "GFW-blocked winner excluded"
FAKE_GFW_FILE="$TMP/gfw-empty.txt"
# 9. geo lookup fails -> country lists skipped, tier 2 still works
FAKE_GEO_FILE="$TMP/geo-empty.json"
mk_h2 git.kernel.org swscan.apple.com
mk_lat "git.kernel.org 0.070" "swscan.apple.com 0.090"
run_case 0 git.kernel.org "geo failure falls back to tier 2"
# 10. idempotent: reym already set -> no curl calls at all
FAKE_GEO_FILE="$TMP/geo-gb-eng.json"
FAKE_CURL_LOG="$TMP/curl.log"; : > "$FAKE_CURL_LOG"
cat > "$TMP/run_idem.sh" << 'RUNIDEM'
#!/bin/bash
. "$1/modules/auto-sni.sh"
ym_vl_re="www.ox.ac.uk"; reym="www.ox.ac.uk"
auto_sni_resolve
echo "rc=$? reym=${reym:-} ym_vl_re=${ym_vl_re:-}"
RUNIDEM
out=$(FAKE_CURL_LOG="$FAKE_CURL_LOG" PATH="$TMP/stubbin:$PATH" bash "$TMP/run_idem.sh" "$ROOT") || fail "idempotent run failed: $out"
printf '%s' "$out" | grep -q 'rc=0' || fail "idempotent: rc not 0 (out: $out)"
[ ! -s "$FAKE_CURL_LOG" ] || fail "idempotent: curl was called: $(cat "$FAKE_CURL_LOG")"
echo "ok: idempotent (reym set -> no probe)"
FAKE_CURL_LOG=""
# 11. ym set, reym empty -> still probes (new rule: detect even with ym)
FAKE_GEO_FILE="$TMP/geo-gb-eng.json"
FAKE_GFW_FILE="$TMP/gfw-empty.txt"
mk_h2 www.example.ac.uk www.cam.ac.uk www.ed.ac.uk www.ox.ac.uk
mk_lat "www.example.ac.uk 0.080" "www.cam.ac.uk 0.050" "www.ed.ac.uk 0.040" "www.ox.ac.uk 0.060"
cat > "$TMP/run_ym.sh" << 'RUNYM'
#!/bin/bash
. "$1/modules/auto-sni.sh"
ym_vl_re="111.222.333.com"; reym=""
auto_sni_resolve
echo "rc=$? reym=${reym:-} ym_vl_re=${ym_vl_re:-}"
RUNYM
out=$(FAKE_GEO_FILE="$FAKE_GEO_FILE" FAKE_UNIV_FILE="$TMP/univ.json" \
  FAKE_GFW_FILE="$FAKE_GFW_FILE" FAKE_H2_FILE="$FAKE_H2_FILE" \
  FAKE_LATENCY_FILE="$FAKE_LATENCY_FILE" FAKE_CURL_VERSION_H2=1 \
  PATH="$TMP/stubbin:$PATH" bash "$TMP/run_ym.sh" "$ROOT") || fail "ym-set probe run failed: $out"
printf '%s' "$out" | grep -q 'rc=0 reym=www.ed.ac.uk ym_vl_re=www.ed.ac.uk' \
  || fail "ym-set probe wrong: $out"
echo "ok: ym set, reym empty -> probes (reym=www.ed.ac.uk)"

# ---------- 3. trigger guard (extracted from the built script) ----------
call_line=$(grep -n 'auto_sni_resolve || exit 1' "$BUILT" | cut -d: -f1)
sed -n "$((call_line-1)),$((call_line+1))p" "$BUILT" > "$TMP/guard.sh"
cat > "$TMP/run_guard.sh" << 'RUNG'
#!/bin/bash
# $1 = guard file, $2 = scenario, $3 = trace file
GUARD="$1"; SCEN="$2"; TRACE="$3"
: > "$TRACE"
unset vlp xhp vxp vwp xup xcp arp ym_vl_re reym ym
auto_sni_resolve() { echo "called" >> "$TRACE"; return "${STUB_RC:-0}"; }
case "$SCEN" in
  reym-set) reym="www.ox.ac.uk"; vlp=yes ;;
  ym-set) ym="111.222.333.com"; vlp=yes ;;
  no-flag) : ;;
  vlp) vlp=yes ;;
  xhp) xhp=yes ;;
  vlp-fail) vlp=yes; STUB_RC=1 ;;
esac
. "$GUARD"
echo "guard-returned" >> "$TRACE"
RUNG
chmod +x "$TMP/run_guard.sh"
guard_case() {
  local scen="$1" want_called="$2" label="$3"
  local trace="$TMP/trace-$scen"
  bash "$TMP/run_guard.sh" "$TMP/guard.sh" "$scen" "$trace" || fail "$label: guard runner exited non-zero"
  local called=0
  grep -q '^called$' "$trace" && called=1
  [ "$called" = "$want_called" ] || fail "$label: called=$called want $want_called (trace: $(cat "$trace"))"
  grep -q '^guard-returned$' "$trace" || fail "$label: guard did not return"
  echo "ok: guard $label (called=$called)"
}
guard_case reym-set 0 "reym set -> no probe"
guard_case ym-set 1 "ym set, reym empty -> probe"
guard_case no-flag 0 "no Reality flag -> no probe"
guard_case vlp 1 "vlp set -> probe"
guard_case xhp 1 "xhp set -> probe"
# failure propagates: stub returns 1 -> guard exits 1 (install stops)
trace="$TMP/trace-vlp-fail"; rm -f "$trace"
if bash "$TMP/run_guard.sh" "$TMP/guard.sh" vlp-fail "$trace"; then
  fail "guard vlp-fail: should exit 1"
fi
grep -q '^called$' "$trace" || fail "guard vlp-fail: probe not called"
grep -q '^guard-returned$' "$trace" && fail "guard vlp-fail: should not return after exit 1"
echo "ok: guard failure -> exit 1"
# integration: guard + real module + stubbed network -> reym set
FAKE_GEO_FILE="$TMP/geo-gb-eng.json"
mk_h2 www.example.ac.uk www.cam.ac.uk www.ed.ac.uk www.ox.ac.uk
mk_lat "www.example.ac.uk 0.080" "www.cam.ac.uk 0.050" "www.ed.ac.uk 0.040" "www.ox.ac.uk 0.060"
out=$(FAKE_GEO_FILE="$FAKE_GEO_FILE" FAKE_UNIV_FILE="$TMP/univ.json" \
  FAKE_GFW_FILE="$TMP/gfw-empty.txt" FAKE_H2_FILE="$FAKE_H2_FILE" \
  FAKE_LATENCY_FILE="$FAKE_LATENCY_FILE" \
  PATH="$TMP/stubbin:$PATH" bash "$TMP/run_sni.sh" "$ROOT" guard "$TMP/guard.sh") || fail "guard+module integration failed: $out"
printf '%s' "$out" | grep -q 'rc=0 reym=www.ed.ac.uk ym_vl_re=www.ed.ac.uk' \
  || fail "guard+module integration wrong: $out"
echo "ok: guard + real module integration"

# ---------- 4. standalone script: best domain on stdout only ----------
err_log="$TMP/standalone.err"
out=$(FAKE_GEO_FILE="$TMP/geo-gb-eng.json" FAKE_UNIV_FILE="$TMP/univ.json" \
  FAKE_GFW_FILE="$TMP/gfw-empty.txt" FAKE_H2_FILE="$FAKE_H2_FILE" \
  FAKE_LATENCY_FILE="$FAKE_LATENCY_FILE" \
  PATH="$TMP/stubbin:$PATH" bash "$STANDALONE" 2>"$err_log") || fail "standalone success run failed"
[ "$out" = "www.ed.ac.uk" ] || fail "standalone stdout=[$out] want www.ed.ac.uk"
grep -q '本档 Top 候选：' "$err_log" || fail "standalone stderr missing Top candidates list: $(cat "$err_log")"
echo "ok: standalone prints best domain on stdout and Top candidates on stderr"
mk_h2
if out=$(FAKE_GEO_FILE="$TMP/geo-gb-eng.json" FAKE_UNIV_FILE="$TMP/univ.json" \
  FAKE_GFW_FILE="$TMP/gfw-empty.txt" FAKE_H2_FILE="$FAKE_H2_FILE" \
  FAKE_LATENCY_FILE="$FAKE_LATENCY_FILE" \
  PATH="$TMP/stubbin:$PATH" bash "$STANDALONE" 2>/dev/null); then
  fail "standalone all-fail should exit 1"
fi
[ -z "$out" ] || fail "standalone all-fail stdout must be empty, got [$out]"
echo "ok: standalone failure -> exit 1, empty stdout"

# ---------- 5. X25519 hard requirement check ----------
# Verify probe invokes curl with --curves X25519 (rejecting P-521/HRR-only targets like uvh.nl)
CURL_LOG_X25519="$TMP/curl_x25519.log"
: > "$CURL_LOG_X25519"
mk_h2 www.example.ac.uk
FAKE_CURL_LOG="$CURL_LOG_X25519" FAKE_GEO_FILE="$TMP/geo-gb-eng.json" FAKE_UNIV_FILE="$TMP/univ.json" \
  FAKE_GFW_FILE="$TMP/gfw-empty.txt" FAKE_H2_FILE="$FAKE_H2_FILE" \
  FAKE_LATENCY_FILE="$FAKE_LATENCY_FILE" \
  PATH="$TMP/stubbin:$PATH" bash "$STANDALONE" >/dev/null 2>&1
grep -q -- "--curves X25519" "$CURL_LOG_X25519" || fail "probe did not enforce --curves X25519 in curl call"
echo "ok: X25519 curve enforced (--curves X25519)"

# ---------- 6. hardening: HTTP 200 filter, PQ ClientHello, reym_tier=2 ----------
# 6a. Tier 1 rejects 301/403 redirectors/WAF blocks, picks 200 site
FAKE_GEO_FILE="$TMP/geo-gb-eng.json"
mk_h2 www.ed.ac.uk www.cam.ac.uk www.ox.ac.uk
mk_lat "www.ed.ac.uk 0.010" "www.cam.ac.uk 0.020" "www.ox.ac.uk 0.090"
printf 'www.ed.ac.uk 301\nwww.cam.ac.uk 403\nwww.ox.ac.uk 200\n' > "$TMP/codes.txt"
FAKE_HTTP_CODE_FILE="$TMP/codes.txt" run_case 0 www.ox.ac.uk "tier1 rejects 301/403 and picks 200"

# 6b. Tier 3 fallback allows 302 (e.g. learn.microsoft.com) while still rejecting 500/403
mk_h2 learn.microsoft.com swscan.apple.com
mk_lat "swscan.apple.com 0.010" "learn.microsoft.com 0.050"
printf 'swscan.apple.com 500\nlearn.microsoft.com 302\n' > "$TMP/codes.txt"
FAKE_HTTP_CODE_FILE="$TMP/codes.txt" run_case 0 learn.microsoft.com "tier3 fallback allows 302 and rejects 500"
FAKE_HTTP_CODE_FILE=""

# 6c. OpenSSL >= 3.5 triggers X25519MLKEM768:X25519 compatibility check and rejects failing targets
CURL_LOG_PQ="$TMP/curl_pq.log"
: > "$CURL_LOG_PQ"
mk_h2 www.ed.ac.uk www.ox.ac.uk
mk_lat "www.ed.ac.uk 0.010" "www.ox.ac.uk 0.050"
printf 'www.ed.ac.uk\n' > "$TMP/pq_fail.txt"
FAKE_CURL_OPENSSL_VER="3.5.0" FAKE_PQ_FAIL_FILE="$TMP/pq_fail.txt" FAKE_CURL_LOG="$CURL_LOG_PQ" \
  run_case 0 www.ox.ac.uk "PQ X25519MLKEM768:X25519 probe rejects incompatible target"
grep -q -- "--curves X25519MLKEM768:X25519" "$CURL_LOG_PQ" || fail "PQ probe did not invoke --curves X25519MLKEM768:X25519"
FAKE_CURL_OPENSSL_VER="3.0.2" FAKE_PQ_FAIL_FILE="" FAKE_CURL_LOG=""

# 6d. reym_tier=2 skips Tier 1 even when Tier 1 passes, selects directly from Tier 2
mk_h2 www.ed.ac.uk git.kernel.org www.debian.org
mk_lat "www.ed.ac.uk 0.010" "git.kernel.org 0.040" "www.debian.org 0.080"
reym_tier=2 run_case 0 git.kernel.org "reym_tier=2 skips tier1 and picks tier2"

# 6e. Geo-DNS split-horizon CDN: clean local CNAME, but CN ECS (+subnet=223.5.5.0/24) returns CDN -> rejected
mk_h2 www.ed.ac.uk www.ox.ac.uk
mk_lat "www.ed.ac.uk 0.010" "www.ox.ac.uk 0.050"
printf 'www.ed.ac.uk origin-www.ed.ac.uk.\n' > "$TMP/local_cname.txt"
printf 'www.ed.ac.uk cdn.webflow.com.\n' > "$TMP/cn_cname.txt"
FAKE_CNAME_FILE="$TMP/local_cname.txt" FAKE_CN_CNAME_FILE="$TMP/cn_cname.txt" \
  run_case 0 www.ox.ac.uk "Geo-DNS split-horizon CDN (CN ECS) rejected"
FAKE_CNAME_FILE="" FAKE_CN_CNAME_FILE=""

# 6f. Tier 1 latency >= 80ms also probes Tier 2 and switches only if Tier 2 is faster,
#     and merges Tier 1 + Tier 2 results in Top candidates with T1/T2 tags
mk_h2 www.ed.ac.uk git.kernel.org
mk_lat "www.ed.ac.uk 0.080" "git.kernel.org 0.030"
err_merge="$TMP/merge.err"
out=$(FAKE_GEO_FILE="$TMP/geo-gb-eng.json" FAKE_UNIV_FILE="$TMP/univ.json" \
  FAKE_GFW_FILE="$TMP/gfw-empty.txt" FAKE_H2_FILE="$FAKE_H2_FILE" \
  FAKE_LATENCY_FILE="$FAKE_LATENCY_FILE" \
  PATH="$TMP/stubbin:$PATH" bash "$STANDALONE" 2>"$err_merge") || fail "tier1>=80ms merge run failed"
[ "$out" = "git.kernel.org" ] || fail "tier1>=80ms stdout=[$out] want git.kernel.org"
grep -q '第 1 档最优 www.ed.ac.uk（80.0 ms >= 80 ms）' "$err_merge" || fail "missing clean Tier1 trigger log: $(cat "$err_merge")"
grep -q 'Top 候选（第 1/2 档合并）：git.kernel.org(T2/30ms/200) www.ed.ac.uk(T1/80ms/200)' "$err_merge" || fail "missing merged T1/T2 Top list: $(cat "$err_merge")"
echo "ok: tier1 >= 80ms switches to faster tier2 and merges T1/T2 Top list"

mk_h2 www.ed.ac.uk git.kernel.org
mk_lat "www.ed.ac.uk 0.090" "git.kernel.org 0.120"
run_case 0 www.ed.ac.uk "tier1 >= 80ms keeps tier1 when tier2 is slower"

mk_h2 www.ed.ac.uk git.kernel.org
mk_lat "www.ed.ac.uk 0.079" "git.kernel.org 0.020"
run_case 0 www.ed.ac.uk "tier1 < 80ms early stops and ignores faster tier2"

echo "PASS: auto-sni"
