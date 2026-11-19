# vlpt-coexistence.sh: VLESS-Reality 443 port coexistence with local Web servers (Caddy / Nginx)
# Handles:
# 1. Automatic probing for available local Web port (starting at 8443, sequential 9443, 10443...)
# 2. Interactive prompt when vlpt=443 is configured; safe exit if user declines; auto-agree in unattended mode
# 3. Delegating Web configuration and port migration to caddy_proxy.sh and nginx_proxy.sh (set-port)
# 4. Smooth reload and verification that 443 is freed before Xray/Sing-box takes over 443
# 5. Restoring initial environment (reverting Caddy/Nginx to 443, removing web_port) on uninstall

web_port_is_available_or_self(){
  local port="$1"
  [ -n "$port" ] || return 1
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
  [ "$port" != "443" ] || return 1

  local out=""
  if command -v ss >/dev/null 2>&1; then
    out=$(ss -tlnp 2>/dev/null | grep -E ":${port}\s" || true)
  elif command -v netstat >/dev/null 2>&1; then
    out=$(netstat -tlnp 2>/dev/null | grep -E ":${port}\s" || true)
  elif command -v lsof >/dev/null 2>&1; then
    out=$(lsof -iTCP:${port} -sTCP:LISTEN 2>/dev/null || true)
  fi

  # 1. 未被任何进程占用 -> 可用
  if [ -z "$out" ]; then
    return 0
  fi

  # 2. 已被占用：判断占用者是否为自身受纳管 Web 服务 (caddy 或 nginx)
  if [ -n "$out" ] && ! echo "$out" | grep -qvE '("caddy"|"nginx"|caddy:|nginx:|/caddy|/nginx)'; then
    return 0
  fi

  # 3. 若输出未包含进程信息（如普通用户权限），但该端口确实与已有记录一致，且 caddy/nginx 服务正在运行
  local known_wp=""
  [ -f "$HOME/agsbx/web_port" ] && known_wp=$(cat "$HOME/agsbx/web_port" 2>/dev/null | tr -d '[:space:]')
  [ -z "$known_wp" ] && [ -f "${CADDY_PORT_FILE:-/etc/caddy/web_port}" ] && known_wp=$(cat "${CADDY_PORT_FILE:-/etc/caddy/web_port}" 2>/dev/null | tr -d '[:space:]')
  [ -z "$known_wp" ] && [ -f "${NGINX_PORT_FILE:-/etc/nginx/web_port}" ] && known_wp=$(cat "${NGINX_PORT_FILE:-/etc/nginx/web_port}" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$known_wp" ] && [ "$known_wp" = "$port" ]; then
    if (command -v systemctl >/dev/null 2>&1 && (systemctl is-active --quiet caddy 2>/dev/null || systemctl is-active --quiet nginx 2>/dev/null)) || \
       pgrep -x caddy >/dev/null 2>&1 || pgrep -x nginx >/dev/null 2>&1; then
      return 0
    fi
  fi

  return 1 # 被其他外部进程占用
}

web_port_find_available(){
  local preferred="${1:-}"
  if [ -n "$preferred" ] && web_port_is_available_or_self "$preferred"; then
    printf '%s' "$preferred"
    return 0
  fi

  local port=8443
  local step=1000
  local max_tries=10
  local i=0
  while [ $i -lt $max_tries ]; do
    if web_port_is_available_or_self "$port"; then
      printf '%s' "$port"
      return 0
    fi
    port=$((port + step))
    i=$((i + 1))
  done
  # Fallback if all 10 candidates were busy: random port between 10000-65535
  shuf -i 10000-65535 -n 1
}

web_server_migrate_to_port(){
  local target_port="$1"
  [ -n "$target_port" ] || return 0

  # 委托 caddy_proxy.sh / nginx_proxy.sh 执行 set-port
  local caddy_bin="$HOME/.local/bin/caddy_proxy.sh"
  local nginx_bin="$HOME/.local/bin/nginx_proxy.sh"
  if command -v ensure_proxy_script >/dev/null 2>&1; then
    ensure_proxy_script "caddy_proxy.sh" || true
    ensure_proxy_script "nginx_proxy.sh" || true
  fi

  if [ -x "$caddy_bin" ]; then
    "$caddy_bin" set-port "$target_port" || echo "警告: caddy_proxy.sh set-port 失败"
  fi

  if [ -x "$nginx_bin" ]; then
    "$nginx_bin" set-port "$target_port" || echo "警告: nginx_proxy.sh set-port 失败"
  fi

  # 等待 443 释放（仅在迁移至非 443 端口时需要等待 443 端口腾空）
  if [ "$target_port" != "443" ]; then
    local waited=0
    while [ $waited -lt 5 ]; do
      local occupied=0
      if command -v ss >/dev/null 2>&1; then
        if ss -tlnp 2>/dev/null | grep -qE ':443\s'; then occupied=1; fi
      elif command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp 2>/dev/null | grep -qE ':443\s'; then occupied=1; fi
      fi
      if [ "$occupied" = "0" ]; then break; fi
      sleep 1
      waited=$((waited + 1))
    done
  fi
  return 0
}

vlpt_coexistence_check(){
  local p="${port_vl_re:-${vlpt:-}}"
  if [ -z "$p" ] && command -v port_get >/dev/null 2>&1; then
    p=$(port_get "vl_re" 2>/dev/null || true)
  fi
  [ "$p" = "443" ] || return 0

  # 检测是否已存在先前配置的有效 web_port
  local existing_wp=""
  if command -v port_get >/dev/null 2>&1; then
    existing_wp=$(port_get "web_port" 2>/dev/null || true)
  fi
  if [ -z "$existing_wp" ] && [ -f "$HOME/agsbx/web_port" ]; then
    existing_wp=$(cat "$HOME/agsbx/web_port" 2>/dev/null | tr -d '[:space:]')
  fi
  local cport_file="${CADDY_PORT_FILE:-/etc/caddy/web_port}"
  if [ -z "$existing_wp" ] && [ -f "$cport_file" ]; then
    existing_wp=$(cat "$cport_file" 2>/dev/null | tr -d '[:space:]')
  fi
  local nport_file="${NGINX_PORT_FILE:-/etc/nginx/web_port}"
  if [ -z "$existing_wp" ] && [ -f "$nport_file" ]; then
    existing_wp=$(cat "$nport_file" 2>/dev/null | tr -d '[:space:]')
  fi
  case "$existing_wp" in
    443|''|*[!0-9]*) existing_wp="" ;;
  esac

  local is_already_coexisting=0
  if [ -n "$existing_wp" ] && web_port_is_available_or_self "$existing_wp"; then
    is_already_coexisting=1
  fi

  if [ "$is_already_coexisting" = "1" ]; then
    echo "检测到现有 Web 服务已处于 443 共存状态 (监听本地端口: $existing_wp)，继续保持该端口。"
  elif [ -t 0 ] && [ "${FORCE_NONINTERACTIVE:-0}" != "1" ]; then
    echo "------------------------------------------------------------"
    echo "⚠️  【端口冲突提示】检测到 VLESS-Reality (vlpt) 配置了 443 端口。"
    echo "系统 Web 服务 (Caddy/Nginx) 默认亦监听 443 端口。"
    echo "继续操作需要将现有及后续 Web 服务迁移至本地回环高位端口 (如 8443)，"
    echo "由 Reality 统一接管 443 入口并进行透明内部流量回落 (Fallback)。"
    echo "------------------------------------------------------------"
    local ans="y"
    printf "是否允许调整 Web 服务端口并继续安装？[Y/n]: "
    read -r ans || ans="y"
    case "$ans" in
      [nN][oO]|[nN])
        echo "已取消配置：请勿在 vlpt 中填入 443，请保持默认留空（使用随机高位端口）或使用其他非 443 端口。"
        exit 0
        ;;
      *)
        echo "已确认同意，正在执行 443 端口共存迁移..."
        ;;
    esac
  else
    echo "检测到 vlpt=443 且处于非交互/无人值守模式，默认同意 Web 服务端口迁移并启用 Reality 443 共存。"
  fi

  local wp=""
  wp=$(web_port_find_available "$existing_wp")
  export web_port="$wp"
  mkdir -p "$HOME/agsbx" 2>/dev/null || true
  echo "$wp" > "$HOME/agsbx/web_port" 2>/dev/null || true
  command -v port_set >/dev/null 2>&1 && port_set "web_port" "$wp"

  web_server_migrate_to_port "$wp"
  export ym_vl_fb_port="$wp"
  return 0
}

vlpt_coexistence_cleanup(){
  local wp=""
  [ -f "$HOME/agsbx/web_port" ] && wp=$(cat "$HOME/agsbx/web_port" 2>/dev/null | tr -d '[:space:]')
  local caddy_wp="" nginx_wp=""
  local cport_file="${CADDY_PORT_FILE:-/etc/caddy/web_port}"
  local nport_file="${NGINX_PORT_FILE:-/etc/nginx/web_port}"
  [ -f "$cport_file" ] && caddy_wp=$(cat "$cport_file" 2>/dev/null | tr -d '[:space:]')
  [ -f "$nport_file" ] && nginx_wp=$(cat "$nport_file" 2>/dev/null | tr -d '[:space:]')

  if [ -n "$wp" ] || [ -n "$caddy_wp" ] || [ -n "$nginx_wp" ]; then
    echo "检测到 Web 服务曾配置高位端口共存，正在恢复 Caddy / Nginx 默认 443 端口与初始配置..."
    # 提前停止占有 443 端口的节点内核服务，确保 443 端口释放给 Web 服务接管
    if command -v systemctl >/dev/null 2>&1; then
      systemctl stop xr sb >/dev/null 2>&1 || true
    elif command -v rc-service >/dev/null 2>&1; then
      rc-service xray stop >/dev/null 2>&1 || true
      rc-service sing-box stop >/dev/null 2>&1 || true
    fi
    kill -15 $(pgrep -f 'agsbx/s' 2>/dev/null) $(pgrep -f 'agsbx/x' 2>/dev/null) >/dev/null 2>&1 || true
    web_server_migrate_to_port 443
  fi
  rm -f "$HOME/agsbx/web_port" "$cport_file" "$nport_file" 2>/dev/null || true
  return 0
}

if command -v register_hook >/dev/null 2>&1; then
  register_hook on_uninstall vlpt_coexistence_cleanup
fi
