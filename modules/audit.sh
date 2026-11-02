# audit.sh: 安全审计（只读，不修改系统）
#
# 用法：agsbx audit
# 检查 SSH、防火墙、证书、暴露面等安全项，输出 [PASS]/[WARN]/[FAIL]。
# 与 check 的区别：check 是"功能是否正常"，audit 是"安全是否到位"。

AUDIT_PASS=0
AUDIT_WARN=0
AUDIT_FAIL=0

_audit_ok(){ AUDIT_PASS=$((AUDIT_PASS+1)); echo "[PASS] $1"; }
_audit_warn(){ AUDIT_WARN=$((AUDIT_WARN+1)); echo "[WARN] $1"; }
_audit_fail(){ AUDIT_FAIL=$((AUDIT_FAIL+1)); echo "[FAIL] $1"; }

# audit_ssh: SSH 安全配置
audit_ssh(){
  local cfg="/etc/ssh/sshd_config"
  [ -f "$cfg" ] || { _audit_warn "无 $cfg，跳过 SSH 检查"; return 0; }
  # PasswordAuthentication
  if grep -qE "^[[:space:]]*PasswordAuthentication[[:space:]]+no" "$cfg" 2>/dev/null; then
    _audit_ok "SSH 已禁密码登录"
  elif grep -qE "^[[:space:]]*PasswordAuthentication[[:space:]]+yes" "$cfg" 2>/dev/null; then
    _audit_fail "SSH 允许密码登录（建议改为 no）"
  else
    _audit_warn "SSH PasswordAuthentication 未显式设置（默认 yes）"
  fi
  # PermitRootLogin
  if grep -qE "^[[:space:]]*PermitRootLogin[[:space:]]+(no|prohibit-password|without-password)" "$cfg" 2>/dev/null; then
    _audit_ok "SSH root 登录已限制"
  else
    _audit_warn "SSH 允许 root 密码登录（建议 prohibit-password 或 no）"
  fi
  # fail2ban
  if command -v fail2ban-client >/dev/null 2>&1 && fail2ban-client ping >/dev/null 2>&1; then
    _audit_ok "fail2ban 运行中"
  else
    _audit_warn "未检测到 fail2ban（建议安装防护 SSH 爆破）"
  fi
  return 0
}

# audit_firewall: 防火墙状态
audit_firewall(){
  local active=0
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    _audit_ok "ufw 已启用"; active=1
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && [ "$(firewall-cmd --state 2>/dev/null)" = "running" ]; then
    _audit_ok "firewalld 运行中"; active=1
  fi
  if [ "$active" = "0" ]; then
    _audit_fail "无防火墙在运行（ufw/firewalld 均未启用）"
  fi
  return 0
}

# audit_cert: 证书有效期（<30天警告，<7天失败）
audit_cert(){
  local ym_c="" crt="" enddate="" endepoch="" now="" days=""
  ym_c=$(tr -d ' \t\r\n' < "$HOME/agsbx/ym" 2>/dev/null)
  [ -n "$ym_c" ] || { _audit_warn "未设置 ym，跳过证书检查"; return 0; }
  crt="$HOME/agsbx/cert/cert.crt"
  [ -s "$crt" ] || { _audit_fail "域名证书缺失"; return 0; }
  command -v openssl >/dev/null 2>&1 || return 0
  enddate=$(openssl x509 -in "$crt" -noout -enddate 2>/dev/null | cut -d= -f2)
  [ -n "$enddate" ] || return 0
  endepoch=$(date -d "$enddate" +%s 2>/dev/null || echo 0)
  now=$(date +%s)
  days=$(( (endepoch - now) / 86400 ))
  if [ "$days" -lt 0 ]; then
    _audit_fail "证书已过期"
  elif [ "$days" -lt 7 ]; then
    _audit_fail "证书剩余 $days 天（<7 天，立即处理）"
  elif [ "$days" -lt 30 ]; then
    _audit_warn "证书剩余 $days 天（<30 天）"
  else
    _audit_ok "证书有效期剩余 $days 天"
  fi
  return 0
}

# audit_exposed: 检查非预期暴露的端口
audit_exposed(){
  command -v ss >/dev/null 2>&1 || { _audit_warn "无 ss 命令，跳过端口暴露检查"; return 0; }
  local listening="" p="" known="" unexpected=""
  # 已知端口：从 port_* 文件收集
  known=$(for f in "$HOME"/agsbx/port_*; do [ -f "$f" ] && tr -d ' \t\r\n' < "$f" 2>/dev/null; echo; done | grep -E "^[0-9]+$" | sort -un | tr '\n' ' ')
  # 订阅端口
  if [ -f "$HOME/agsbx/subport.log" ]; then
    known="$known $(tr -d ' \t\r\n' < "$HOME/agsbx/subport.log" 2>/dev/null)"
  fi
  # 常见系统端口白名单（SSH 必留）
  known="$known 22"
  listening=$(ss -tlnp 2>/dev/null | awk 'NR>1{print $4}' | sed 's/.*://' | grep -E "^[0-9]+$" | sort -un)
  for p in $listening; do
    case " $known " in
      *" $p "*) ;;
      *) unexpected="$unexpected $p";;
    esac
  done
  if [ -n "$unexpected" ]; then
    _audit_warn "非预期监听端口：$unexpected（确认是否为你开的服务）"
  else
    _audit_ok "无非预期暴露的 TCP 端口"
  fi
  return 0
}

# audit_files: 敏感文件权限
audit_files(){
  local bad=0 f="" perm=""
  for f in "$HOME/agsbx/vars.env" "$HOME/agsbx/webdav.env" "$HOME/agsbx/cert/private.key"; do
    [ -f "$f" ] || continue
    perm=$(stat -c '%a' "$f" 2>/dev/null)
    case "$perm" in
      600|400) ;;
      *) _audit_warn "$f 权限为 $perm（建议 600）"; bad=1;;
    esac
  done
  [ "$bad" = "0" ] && _audit_ok "敏感文件权限正确"
  return 0
}

# agsbx_audit: 主入口
agsbx_audit(){
  AUDIT_PASS=0; AUDIT_WARN=0; AUDIT_FAIL=0
  echo "=== argosbx 安全审计 $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date) ==="
  echo "主机：$(hostname 2>/dev/null || echo unknown)"
  echo "--- SSH ---"
  audit_ssh
  echo "--- 防火墙 ---"
  audit_firewall
  echo "--- 证书 ---"
  audit_cert
  echo "--- 端口暴露 ---"
  audit_exposed
  echo "--- 文件权限 ---"
  audit_files
  echo "---"
  echo "结果：$AUDIT_PASS 通过，$AUDIT_WARN 警告，$AUDIT_FAIL 失败"
  [ "$AUDIT_FAIL" = "0" ]
}
