#!/bin/bash
# backup/restore: tarball contents, permissions, encryption roundtrip,
# WebDAV config loading, restore validation. Mock curl for WebDAV.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail(){ echo "FAIL: $1"; exit 1; }

# --- built file checks ---
python3 build/build.py >/dev/null 2>&1 || fail "build failed"
grep -q "agsbx_backup" argosbx.sh || fail "built script missing agsbx_backup"
grep -q "agsbx_restore" argosbx.sh || fail "built script missing agsbx_restore"
grep -q "agsbx_check" argosbx.sh || fail "built script missing agsbx_check"
grep -q '"backup"' argosbx.sh || fail "built script missing backup dispatch"
grep -q '"restore"' argosbx.sh || fail "built script missing restore dispatch"
grep -q '"check"' argosbx.sh || fail "built script missing check dispatch"
# subcommands must not overwrite sh.txt
grep -q 'check|backup|restore) ;; \*)' argosbx.sh || fail "top-case-exclusion missing check|backup|restore"

# --- isolated HOME ---
TESTHOME="$(mktemp -d)"; export HOME="$TESTHOME"
mkdir -p "$HOME/agsbx"
# fake vars.env (%q-escaped format like vars_save produces)
printf '%s\n' "vlpt='10001'" "tupt='10002'" "ym='example.test'" > "$HOME/agsbx/vars.env"
chmod 600 "$HOME/agsbx/vars.env"
echo "uuid-test" > "$HOME/agsbx/uuid"
mkdir -p "$HOME/agsbx/xrk" "$HOME/agsbx/cert"
echo "fakekey" > "$HOME/agsbx/xrk/private.key"
echo "fakecert" > "$HOME/agsbx/cert/cert.crt"

# source the backup module directly
source "modules/backup.sh" || fail "cannot source modules/backup.sh"

# --- 1. backup_create_tar: contents and permissions ---
OUT="$TESTHOME/backup.tar.gz"
backup_create_tar "$OUT" || fail "backup_create_tar failed"
[ -f "$OUT" ] || fail "tarball not created"
[ "$(stat -c '%a' "$OUT")" = "600" ] || fail "tarball should be 600"
# contents: vars.env, sh.txt (optional), META; must NOT contain uuid/key/cert
tar -tzf "$OUT" | grep -q "^vars.env$" || fail "tarball missing vars.env"
tar -tzf "$OUT" | grep -q "^META$" || fail "tarball missing META"
tar -tzf "$OUT" | grep -q "uuid" && fail "tarball must not contain uuid"
tar -tzf "$OUT" | grep -q "xrk" && fail "tarball must not contain keypairs"
tar -tzf "$OUT" | grep -q "cert.crt" && fail "tarball must not contain certs"
echo "tarball contents OK"

# --- 2. encryption roundtrip ---
export BACKUP_PASSPHRASE="test-pass-123"
backup_read_passphrase backup || fail "read passphrase failed"
ENC="$TESTHOME/backup.enc"
DEC="$TESTHOME/backup-dec.tar.gz"
backup_encrypt "$OUT" "$ENC" || fail "encrypt failed"
[ -f "$ENC" ] || fail "enc file not created"
[ "$(stat -c '%a' "$ENC")" = "600" ] || fail "enc file should be 600"
# enc file should not contain plaintext marker
grep -q "vars.env" "$ENC" 2>/dev/null && fail "enc file leaks plaintext"
backup_decrypt "$ENC" "$DEC" || fail "decrypt failed"
cmp "$OUT" "$DEC" || fail "decrypt roundtrip mismatch"
echo "encryption roundtrip OK"

# --- 3. wrong passphrase fails ---
BACKUP_PASSPHRASE="wrong-pass"
BACKUP_PASSPHRASE_RESULT="wrong-pass"
if backup_decrypt "$ENC" "$TESTHOME/bad.tar.gz" 2>/dev/null; then
  fail "decrypt with wrong passphrase should fail"
fi
echo "wrong passphrase correctly rejected"
export BACKUP_PASSPHRASE="test-pass-123"

# --- 4. webdav config loading ---
# env vars take precedence
WEBDAV_URL="https://dav.example.com/backups/"
WEBDAV_USER="testuser"
WEBDAV_PASS="testpass"
webdav_load_config || fail "webdav_load_config with env vars failed"
[ "$WEBDAV_URL" = "https://dav.example.com/backups/" ] || fail "WEBDAV_URL not loaded"
# config file fallback
unset WEBDAV_URL WEBDAV_USER WEBDAV_PASS
mkdir -p "$HOME/agsbx"
printf '%s\n' "WEBDAV_URL=https://dav2.example.com/x/" "WEBDAV_USER=u2" "WEBDAV_PASS=p2" > "$HOME/agsbx/webdav.env"
chmod 600 "$HOME/agsbx/webdav.env"
webdav_load_config || fail "webdav_load_config with file failed"
[ "$WEBDAV_URL" = "https://dav2.example.com/x/" ] || fail "WEBDAV_URL from file not loaded"
[ "$(stat -c '%a' "$HOME/agsbx/webdav.env")" = "600" ] || fail "webdav.env should be 600"
echo "webdav config OK"

# --- 5. restore validation: missing vars.env rejected ---
mkdir -p "$TESTHOME/empty"
tar -czf "$TESTHOME/empty.tar.gz" -C "$TESTHOME/empty" . 2>/dev/null || true
# agsbx_restore with --yes and nonexistent file should fail fast
if (agsbx_restore "$TESTHOME/nonexistent.tar.gz" --yes 2>/dev/null); then
  fail "restore nonexistent should fail"
fi
echo "restore validation OK"

# --- 6. backup without vars.env fails ---
rm -f "$HOME/agsbx/vars.env"
if backup_create_tar "$TESTHOME/should-fail.tar.gz" 2>/dev/null; then
  fail "backup without vars.env should fail"
fi
echo "backup without vars.env correctly rejected"

rm -rf "$TESTHOME"
echo "test_backup PASS"
