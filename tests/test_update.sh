#!/usr/bin/env bash
# test_update.sh: 验证主脚本自我更新 (agsbx up / update) 与只读/安装流程判定 (_is_install_run)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d /tmp/test_update.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== Test 1: _is_install_run 逻辑验证 ==="
(
  # 载入 modules/vars.sh
  source "$ROOT/modules/vars.sh"

  # 模拟未安装状态
  agsbx_is_installed() { return 1; }
  _is_install_run "" || { echo "FAIL: fresh install should return 0"; exit 1; }
  _is_install_run "help" && { echo "FAIL: help should return 1 even if not installed"; exit 1; }
  _is_install_run "-h" && { echo "FAIL: -h should return 1"; exit 1; }
  _is_install_run "--help" && { echo "FAIL: --help should return 1"; exit 1; }
  _is_install_run "up" && { echo "FAIL: up should return 1"; exit 1; }
  _is_install_run "update" && { echo "FAIL: update should return 1"; exit 1; }

  # 模拟已安装状态
  agsbx_is_installed() { return 0; }
  xcp="" xup="" nvp="" vwp="" sop="" vxp="" ssp="" vlp="" vmp="" vmt="" hyp="" tup="" xhp="" anp="" arp=""
  _is_install_run "" && { echo "FAIL: installed without args should return 1 (showmode)"; exit 1; }
  _is_install_run "rep" || { echo "FAIL: rep should return 0"; exit 1; }
  _is_install_run "add" || { echo "FAIL: add should return 0"; exit 1; }
  _is_install_run "list" && { echo "FAIL: list should return 1"; exit 1; }
  _is_install_run "check" && { echo "FAIL: check should return 1"; exit 1; }
  _is_install_run "audit" && { echo "FAIL: audit should return 1"; exit 1; }
  _is_install_run "backup" && { echo "FAIL: backup should return 1"; exit 1; }
  _is_install_run "res" && { echo "FAIL: res should return 1"; exit 1; }

  # 安装模式下带协议变量
  vlp=yes
  _is_install_run "" || { echo "FAIL: protocol flag set should return 0"; exit 1; }
)
echo "PASS: Test 1"

echo "=== Test 2: agsbx_update 成功更新逻辑、版本号提取与旧路径迁移 ==="
(
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME/bin"

  # 创建一个旧路径 ($HOME/bin/agsbx) 的旧版本脚本
  cat > "$HOME/bin/agsbx" <<'EOF'
#!/bin/bash
# agsbx
echo "当前版本：V26.7.15"
EOF
  chmod +x "$HOME/bin/agsbx"

  # 创建模拟的新版本远端脚本
  local_remote="$TMPDIR/new_argosbx.sh"
  cat > "$local_remote" <<'EOF'
#!/bin/bash
# agsbx
echo "当前版本：V26.7.16"
EOF

  source "$ROOT/modules/proxy-script.sh"
  source "$ROOT/modules/update.sh"

  # 用 file:// 模拟远程下载
  export agsbxurl="file://$local_remote"
  out=$(agsbx_update)
  echo "$out" | grep -q "Argosbx 脚本更新成功" || {
    echo "FAIL: expected success message, got: $out"; exit 1;
  }
  echo "$out" | grep -q "最新版本: V26.7.16 (原版本: V26.7.15)" || {
    echo "FAIL: expected version string not matched, got: $out"; exit 1;
  }

  grep -q "V26.7.16" "$HOME/.local/bin/agsbx" || {
    echo "FAIL: target binary was not updated in $HOME/.local/bin/agsbx"; exit 1;
  }
  [ ! -e "$HOME/bin/agsbx" ] || {
    echo "FAIL: legacy $HOME/bin/agsbx should be removed after migration"; exit 1;
  }

  # 确认当前测试文件本身没有被意外覆盖
  grep -q "=== Test 1:" "$0" || {
    echo "FAIL: caller script was overwritten!"; exit 1;
  }
)
echo "PASS: Test 2"

echo "=== Test 3: agsbx_update 语法错误或非法文件校验拦截 ==="
(
  export HOME="$TMPDIR/home3"
  mkdir -p "$HOME/.local/bin"
  echo -e '#!/bin/bash\n# 当前版本：V26.7.15\necho "old agsbx"' > "$HOME/.local/bin/agsbx"

  source "$ROOT/modules/proxy-script.sh"
  source "$ROOT/modules/update.sh"

  # 1. 缺少 agsbx 标识的文件（例如 404 HTML）
  invalid_remote="$TMPDIR/invalid.sh"
  echo "<html>404 Not Found</html>" > "$invalid_remote"
  export agsbxurl="file://$invalid_remote"
  out=$(agsbx_update 2>&1 || true)
  echo "$out" | grep -q "文件格式无效或内容损坏" || {
    echo "FAIL: expected format invalid rejection, got: $out"; exit 1;
  }

  # 2. 语法错误的 bash 文件
  syntax_err="$TMPDIR/syntax_err.sh"
  echo -e '#!/bin/bash\n# agsbx\nif [ a == b ]; then' > "$syntax_err"
  export agsbxurl="file://$syntax_err"
  out=$(agsbx_update 2>&1 || true)
  echo "$out" | grep -q "语法校验未通过" || {
    echo "FAIL: expected syntax error rejection, got: $out"; exit 1;
  }

  # 确认原文件未被篡改
  grep -q "old agsbx" "$HOME/.local/bin/agsbx" || {
    echo "FAIL: old binary was modified on error"; exit 1;
  }
)
echo "PASS: Test 3"

echo "=== Test 4: 检查 built 脚本中包含 update 子命令、~/.local/bin 路径且无 sbx_update 生成 ==="
(
  built="$ROOT/argosbx.sh"
  grep -Fq 'agsbx_update' "$built" || {
    echo "FAIL: agsbx_update missing in built script"; exit 1;
  }
  grep -Fq 'if [ "$1" = "up" ] || [ "$1" = "update" ]; then' "$built" || {
    echo "FAIL: up/update dispatch missing in built script"; exit 1;
  }
  grep -Fq 'case "${*##* }" in list|del|upx|ups|upa|res|up|update|' "$built" || {
    echo "FAIL: up/update missing in top-case-exclusion"; exit 1;
  }
  grep -Fq 'if _is_install_run "$1"; then vlpt_coexistence_check || exit 1; fi' "$built" || {
    echo "FAIL: vlpt_coexistence_check not gated by _is_install_run in built script"; exit 1;
  }
  grep -Fq 'SCRIPT_PATH="$HOME/.local/bin/agsbx"' "$built" || {
    echo "FAIL: SCRIPT_PATH should be $HOME/.local/bin/agsbx in built script"; exit 1;
  }
  grep -Fq 'ensure_local_bin_in_path' "$built" || {
    echo "FAIL: ensure_local_bin_in_path missing in built script"; exit 1;
  }
  if grep -qE 'touch sbx_update|\[ ! -f sbx_update \]' "$built"; then
    echo "FAIL: built script must not generate sbx_update"; exit 1
  fi
)
echo "PASS: Test 4"

echo "ALL TESTS PASSED!"
