#!/bin/bash
# agsbx check: PASS/FAIL/WARN logic with mocked environment.
# No real kernels, no real network, no real install.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail(){ echo "FAIL: $1"; exit 1; }

# --- built file checks ---
python3 build/build.py >/dev/null 2>&1 || fail "build failed"
grep -q "agsbx_check" argosbx.sh || fail "built script missing agsbx_check"
grep -q "check_kernels" argosbx.sh || fail "built script missing check_kernels"

# --- isolated HOME ---
TESTHOME="$(mktemp -d)"; export HOME="$TESTHOME"
mkdir -p "$HOME/agsbx"
source "modules/check.sh" || fail "cannot source modules/check.sh"

# --- 1. no kernels: WARN, not FAIL ---
out=$(agsbx_check 2>&1)
echo "$out" | grep -q "WARN.*未安装" || fail "no kernels should WARN"
echo "$out" | grep -q "结果：" || fail "missing summary line"
echo "no-kernel WARN OK"

# --- 2. kernel json exists but no process: FAIL ---
echo '{}' > "$HOME/agsbx/xr.json"
echo '{}' > "$HOME/agsbx/sb.json"
out=$(agsbx_check 2>&1)
echo "$out" | grep -q "FAIL.*xray.*未找到进程" || fail "missing xray should FAIL"
echo "$out" | grep -q "FAIL.*sing-box.*未找到进程" || fail "missing sing-box should FAIL"
echo "missing process FAIL OK"

# --- 3. fake processes: PASS ---
# mock pgrep to pretend kernels are running
MOCKBIN="$(mktemp -d)"; export PATH="$MOCKBIN:$PATH"
cat > "$MOCKBIN/pgrep" <<'EOF'
#!/bin/bash
# match anything containing agsbx/xray or agsbx/sing-box
case "$*" in *agsbx/xray*|*agsbx/sing-box*) exit 0;; *) exit 1;; esac
EOF
chmod +x "$MOCKBIN/pgrep"
out=$(agsbx_check 2>&1)
echo "$out" | grep -q "PASS.*xray 进程运行中" || fail "xray running should PASS"
echo "$out" | grep -q "PASS.*sing-box 进程运行中" || fail "sing-box running should PASS"
echo "process PASS OK"

# --- 4. ports: no port files -> WARN; with ss mock -> checked ---
rm -f "$HOME/agsbx/xr.json" "$HOME/agsbx/sb.json"
out=$(agsbx_check 2>&1)
echo "$out" | grep -q "WARN.*无 port" || fail "no port files should WARN"

# fake port file + mock ss showing it listening
echo "10001" > "$HOME/agsbx/port_vl_re"
cat > "$MOCKBIN/ss" <<'EOF'
#!/bin/bash
echo "LISTEN 0 0 *:10001 *:*"
EOF
chmod +x "$MOCKBIN/ss"
out=$(agsbx_check 2>&1)
echo "$out" | grep -q "PASS.*1 个端口有监听" || fail "listening port should PASS"
echo "port check OK"

# --- 5. cert: missing -> FAIL ---
echo "example.test" > "$HOME/agsbx/ym"
out=$(agsbx_check 2>&1)
echo "$out" | grep -q "FAIL.*证书文件缺失" || fail "missing cert should FAIL"
echo "cert missing FAIL OK"

# --- 6. summary counts ---
out=$(agsbx_check 2>&1)
echo "$out" | grep -Eq "结果：[0-9]+ 通过，[0-9]+ 警告，[0-9]+ 失败" || fail "summary format wrong"
echo "summary OK"

rm -rf "$TESTHOME" "$MOCKBIN"
echo "test_check PASS"
