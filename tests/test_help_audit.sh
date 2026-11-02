#!/bin/bash
# help/audit: module presence, help output, audit logic with mocks.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail(){ echo "FAIL: $1"; exit 1; }

python3 build/build.py >/dev/null 2>&1 || fail "build failed"
grep -q "agsbx_help" argosbx.sh || fail "missing agsbx_help"
grep -q "agsbx_audit" argosbx.sh || fail "missing agsbx_audit"
grep -q '"--help"' argosbx.sh || fail "missing --help dispatch"
grep -q '"audit"' argosbx.sh || fail "missing audit dispatch"

TESTHOME="$(mktemp -d)"; export HOME="$TESTHOME"
mkdir -p "$HOME/agsbx"
source "modules/help.sh" || fail "cannot source help.sh"
source "modules/audit.sh" || fail "cannot source audit.sh"

# help output contains key sections
out=$(agsbx_help 2>&1)
echo "$out" | grep -q "agsbx check" || fail "help missing check"
echo "$out" | grep -q "agsbx backup" || fail "help missing backup"
echo "$out" | grep -q "agsbx audit" || fail "help missing audit"
echo "$out" | grep -q "fwsync" || fail "help missing fwsync"
echo "help output OK"

# audit with mocks: no sshd_config -> WARN, no firewall -> FAIL
out=$(agsbx_audit 2>&1)
echo "$out" | grep -q "结果：" || fail "audit missing summary"
echo "audit basic OK"

# audit_files: 600 ok, 644 warns
echo "x" > "$HOME/agsbx/vars.env"; chmod 600 "$HOME/agsbx/vars.env"
echo "x" > "$HOME/agsbx/webdav.env"; chmod 644 "$HOME/agsbx/webdav.env"
out=$(audit_files 2>&1)
echo "$out" | grep -q "WARN.*webdav.env.*644" || fail "audit_files should warn on 644"
echo "audit_files OK"

rm -rf "$TESTHOME"
echo "test_help_audit PASS"
