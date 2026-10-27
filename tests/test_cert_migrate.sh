#!/bin/bash
# Test: cert path migration (unified agsbx tree) - copies only, never
# deletes old files, idempotent, acme update skipped without acme/ym.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
python3 - "$ROOT/argosbx.sh" "$TMP/migrate.sh" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"cert_migrate_paths\(\)\{.*?\n\}\n", t, re.S)
assert m, "cert_migrate_paths not found"
open(sys.argv[2], "w").write(m.group(0))
PY
cat > "$TMP/run.sh" << 'RUN'
#!/bin/bash
source "$1"
export HOME="$2"
ym=""
mkdir -p "$HOME/argosbx/cert" "$HOME/agsbx"
printf 'OLD-CERT' > "$HOME/argosbx/cert/cert.crt"
printf 'OLD-KEY' > "$HOME/argosbx/cert/private.key"
printf 'OLD-SELF-CERT' > "$HOME/agsbx/cert.crt"
printf 'OLD-SELF-KEY' > "$HOME/agsbx/private.key"
printf 'OLD-CADDYFILE' > "$HOME/argosbx/Caddyfile"
cert_migrate_paths
[ "$(cat "$HOME/agsbx/cert/cert.crt")" = "OLD-CERT" ] || { echo "FAIL: domain cert not copied"; exit 1; }
[ "$(cat "$HOME/agsbx/cert/private.key")" = "OLD-KEY" ] || { echo "FAIL: domain key not copied"; exit 1; }
[ "$(cat "$HOME/agsbx/selfsigned/cert.crt")" = "OLD-SELF-CERT" ] || { echo "FAIL: self-signed cert not copied"; exit 1; }
[ "$(cat "$HOME/agsbx/selfsigned/private.key")" = "OLD-SELF-KEY" ] || { echo "FAIL: self-signed key not copied"; exit 1; }
[ "$(cat "$HOME/agsbx/Caddyfile")" = "OLD-CADDYFILE" ] || { echo "FAIL: Caddyfile not copied"; exit 1; }
# Old files still exist (copy, not move)
[ -f "$HOME/argosbx/cert/cert.crt" ] && [ -f "$HOME/agsbx/cert.crt" ] || { echo "FAIL: old files were deleted"; exit 1; }
# Idempotent second run
cert_migrate_paths
[ "$(cat "$HOME/agsbx/cert/cert.crt")" = "OLD-CERT" ] || { echo "FAIL: second run changed cert"; exit 1; }
RUN
bash "$TMP/run.sh" "$TMP/migrate.sh" "$TMP/home"
echo "PASS: cert migrate (domain + self-signed + Caddyfile, copy-only, idempotent)"
