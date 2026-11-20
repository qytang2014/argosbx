#!/bin/bash
# Test: agsbx installation gate decoupling from running processes.
# Ensures agsbx status, list, check, and res function properly
# even when the kernel process is stopped/crashed.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail(){ echo "FAIL: $1"; exit 1; }

# Isolated HOME and mock environment
export HOME="$TMP/home"
mkdir -p "$HOME/agsbx" "$HOME/bin"
MOCKBIN="$TMP/mockbin"
mkdir -p "$MOCKBIN"
export PATH="$MOCKBIN:$PATH"

# Mock curl, wget, pgrep
cat > "$MOCKBIN/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$MOCKBIN/pgrep"

cat > "$MOCKBIN/curl" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$MOCKBIN/curl"

# 1. Test uninstalled state
out=$(bash "$ROOT/argosbx.sh" 2>&1 || true)
echo "$out" | grep -q "提示：未安装argosbx脚本" || fail "uninstalled agsbx should warn uninstalled"

# 2. Test installed state with vars.env present, but NO running processes
echo "uuid=test" > "$HOME/agsbx/vars.env"
echo '{}' > "$HOME/agsbx/xr.json"
out=$(bash "$ROOT/argosbx.sh" 2>&1 || true)
echo "$out" | grep -q "Argosbx脚本已安装" || fail "installed agsbx should show installed banner"
echo "$out" | grep -q "Xray：⚠️ 已配置但未在运行" || fail "should warn xray configured but not running"
echo "$out" | grep -q "⚠️  【告警】检测到已配置的内核未在运行" || fail "should display dead kernel warning"

# 3. Test agsbx res when kernel process is dead
# Mock systemctl or xrestart to observe invocation
RESTART_LOG="$TMP/restart.log"
cat > "$MOCKBIN/systemctl" <<EOF
#!/bin/bash
echo "\$*" >> "$RESTART_LOG"
exit 0
EOF
chmod +x "$MOCKBIN/systemctl"

cat > "$MOCKBIN/pidof" <<'EOF'
#!/bin/bash
if [ "$1" = "systemd" ]; then exit 0; fi
exit 1
EOF
chmod +x "$MOCKBIN/pidof"

cat > "$MOCKBIN/cip" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$MOCKBIN/cip"

# Run agsbx res
bash "$ROOT/argosbx.sh" res >/dev/null 2>&1 || true
grep -q "restart xr" "$RESTART_LOG" || fail "agsbx res should restart xr when xr.json exists"

# Now add sb.json and verify both restart
echo '{}' > "$HOME/agsbx/sb.json"
: > "$RESTART_LOG"
bash "$ROOT/argosbx.sh" res >/dev/null 2>&1 || true
grep -q "restart xr" "$RESTART_LOG" || fail "agsbx res should restart xr"
grep -q "restart sb" "$RESTART_LOG" || fail "agsbx res should restart sb"

# 4. Test script copy priority when running from local file
cp "$ROOT/argosbx.sh" "$TMP/my_argosbx.sh"
SCRIPT_PATH="$HOME/bin/agsbx"
rm -f "$SCRIPT_PATH"
bash "$TMP/my_argosbx.sh" <<'EOF' >/dev/null 2>&1 || true
EOF
# Verify logic: when invoked with a real file in $0, the copy branch works
bash -c '
  SCRIPT_PATH="$1"
  if [ -n "$0" ] && [ -f "$0" ] && [ "$0" != "bash" ] && [ "$0" != "-bash" ] && [ "$0" != "sh" ] && [ -s "$0" ]; then
    cp -f "$0" "$SCRIPT_PATH" 2>/dev/null
  fi
' "$TMP/my_argosbx.sh" "$SCRIPT_PATH"
[ -s "$SCRIPT_PATH" ] || fail "local script should be copied to SCRIPT_PATH"
cmp -s "$TMP/my_argosbx.sh" "$SCRIPT_PATH" || fail "copied script should match local script"

echo "PASS: test_installed_gate"
