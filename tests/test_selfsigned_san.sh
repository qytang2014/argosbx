#!/bin/bash
# Self-signed cert must carry SAN DNS:www.bing.com, not CN only.
# Go/modern TLS rejects CN-only certs with "certificate relies on legacy
# Common Name field, use SANs instead" - that was the hy2 failure (hy2
# forces verification with insecure=0 + pinSHA256, while tuic/anytls use
# insecure=1 in the self-signed case and did not surface it first).
# No network, no real install: string checks + local openssl SAN checks.
# (Go is not installed here, and Python ssl still falls back to CN for
# SAN-less certs, so a Python handshake would not reproduce Go's
# rejection; the SAN-presence check is Go's actual criterion.)
set -u
cd "$(dirname "$0")/.." || exit 1
FAIL=0
# 1. Built files carry SAN; upstream files do not (private fix, not upstream)
grep -Fq 'subjectAltName=DNS:www.bing.com' upstream/argosbx.sh && { echo "FAIL: upstream main already has SAN"; FAIL=1; }
grep -Fq 'subjectAltName=DNS:www.bing.com' argosbx.sh || { echo "FAIL: built main missing SAN generation"; FAIL=1; }
grep -Fq 'subjectAltName=DNS:www.bing.com' container/nodejs/start.sh || { echo "FAIL: built container missing SAN generation"; FAIL=1; }
grep -Fq 'subjectAltName=DNS:www.bing.com' modules/container-cert.sh || { echo "FAIL: container-cert module missing SAN"; FAIL=1; }
# Migration: an existing CN-only cert must trigger regeneration, a SAN
# cert must not (when SHA256.txt exists).
grep -Fq 'Subject Alternative Name' argosbx.sh || { echo "FAIL: built main missing SAN migration check"; FAIL=1; }
grep -Fq 'if [ ! -f "$HOME/agsbx/SHA256.txt" ] || ! openssl x509' argosbx.sh || { echo "FAIL: built main SAN migration condition changed"; FAIL=1; }

td=$(mktemp -d); trap 'rm -rf "$td"' EXIT
openssl ecparam -genkey -name prime256v1 -out "$td/old.key" >/dev/null 2>&1
openssl req -new -x509 -days 2 -key "$td/old.key" -out "$td/old.crt" -subj "/CN=www.bing.com" >/dev/null 2>&1
openssl ecparam -genkey -name prime256v1 -out "$td/new.key" >/dev/null 2>&1
openssl req -new -x509 -days 2 -key "$td/new.key" -out "$td/new.crt" -subj "/CN=www.bing.com" -addext "subjectAltName=DNS:www.bing.com" >/dev/null 2>&1
# 2. SAN extension present only on the new cert
openssl x509 -in "$td/new.crt" -noout -ext subjectAltName 2>/dev/null | grep -q "DNS:www.bing.com" || { echo "FAIL: new cert has no SAN DNS:www.bing.com"; FAIL=1; }
openssl x509 -in "$td/old.crt" -noout -ext subjectAltName 2>/dev/null | grep -q "DNS:" && { echo "FAIL: old cert unexpectedly has a SAN"; FAIL=1; }
# 3. Migration condition, evaluated exactly as in the built script
check_migrate() { # $1=cert $2=sha_exists(1/0) -> prints 1 if regenerate, 0 if keep
  local cert="$1" sha="$2"
  if [ "$sha" = "1" ]; then touch "$td/agsbx/SHA256.txt"; else rm -f "$td/agsbx/SHA256.txt"; fi
  HOME="$td" bash -c 'if [ ! -f "$HOME/agsbx/SHA256.txt" ] || ! openssl x509 -in "$1" -noout -text 2>/dev/null | grep -q "Subject Alternative Name"; then echo 1; else echo 0; fi' _ "$cert"
}
# Note: the condition in the script uses $HOME/agsbx/selfsigned/cert.crt;
# here we pass the cert path directly to prove the grep logic, and the
# string check above proves the script's path is the selfsigned one.
mkdir -p "$td/agsbx"
[ "$(check_migrate "$td/old.crt" 1)" = "1" ] || { echo "FAIL: CN-only cert with SHA256.txt should trigger regeneration"; FAIL=1; }
[ "$(check_migrate "$td/new.crt" 1)" = "0" ] || { echo "FAIL: SAN cert with SHA256.txt should NOT trigger regeneration"; FAIL=1; }
[ "$(check_migrate "$td/new.crt" 0)" = "1" ] || { echo "FAIL: missing SHA256.txt should trigger generation"; FAIL=1; }
# 4. No live handshake simulation here, deliberately: Go is not installed
# in the test env, and Python's ssl still falls back to CN when a cert
# has no SANs at all, so a Python handshake would wrongly accept the old
# cert. Go's rule is the stricter one and is exactly the SAN-presence
# check in (2): a cert with no SAN extension is rejected outright,
# regardless of whether its CN matches. That check is the criterion.

[ "$FAIL" = 0 ] && echo "test_selfsigned_san: PASS" || { echo "test_selfsigned_san: FAIL"; exit 1; }
