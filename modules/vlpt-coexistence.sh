# vlpt-coexistence.sh: Reality 443 port coexistence with local Web servers (Caddy / Nginx)
# Handles any Reality protocol on 443 (vlpt/xhpt/vxpt/vwpt/xupt/xcpt/arpt -- they share
# one decoy SNI, so at most one of them can be on 443 at a time; see reality_443_proto).
# Handles:
# 1. Automatic probing for available local Web port (starting at 8443, sequential 9443, 10443...)
# 2. Interactive prompt when a Reality protocol is configured on 443; safe exit if user declines; auto-agree in unattended mode
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

reality_port_is_available_or_self(){
  local port="$1"
  local avoid="${2:-8443}"
  [ -n "$port" ] || return 1
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
  [ "$port" != "443" ] && [ "$port" != "$avoid" ] || return 1

  local out=""
  if command -v ss >/dev/null 2>&1; then
    out=$(ss -tlnp 2>/dev/null | grep -E ":${port}\s" || true)
  elif command -v netstat >/dev/null 2>&1; then
    out=$(netstat -tlnp 2>/dev/null | grep -E ":${port}\s" || true)
  elif command -v lsof >/dev/null 2>&1; then
    out=$(lsof -iTCP:${port} -sTCP:LISTEN 2>/dev/null || true)
  fi

  if [ -z "$out" ]; then
    return 0
  fi
  if echo "$out" | grep -qE '("xray"|"sing-box"|agsbx/x|agsbx/s)'; then
    return 0
  fi
  local known_rp=""
  [ -f "$HOME/agsbx/reality_port" ] && known_rp=$(cat "$HOME/agsbx/reality_port" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$known_rp" ] && [ "$known_rp" = "$port" ]; then
    return 0
  fi
  return 1
}

reality_port_find_available(){
  local preferred="${1:-}"
  local wp="${2:-8443}"
  if [ -n "$preferred" ] && reality_port_is_available_or_self "$preferred" "$wp"; then
    printf '%s' "$preferred"
    return 0
  fi
  local port=$((wp + 1))
  local i=0
  while [ $i -lt 20 ]; do
    if reality_port_is_available_or_self "$port" "$wp"; then
      printf '%s' "$port"
      return 0
    fi
    port=$((port + 1))
    i=$((i + 1))
  done
  shuf -i 10000-65535 -n 1
}

# _reality_proto_port PROTO: 取某一 Reality 协议的有效端口（实例 1）。
# 与 vlpt 原逻辑一致：端口变量 > 用户变量 > ports.env 持久化；逗号列表只取首项
# （其余协议没有 vlpt-comma.sh 那样的导出前拆分，port_xh 等在 check 时仍是原始逗号列表，
# 所以这里统一用 ${p%%,*} 取首项；vlpt 已被提前拆分，对它是空操作）。
_reality_proto_port(){
  local proto="$1" p="" key=""
  case "$proto" in
    vlpt) p="${port_vl_re:-${vlpt:-}}"; key="vl_re" ;;
    xhpt) p="${port_xh:-${xhpt:-}}"; key="xh" ;;
    vxpt) p="${port_vx:-${vxpt:-}}"; key="vx" ;;
    vwpt) p="${port_vw:-${vwpt:-}}"; key="vw" ;;
    xupt) p="${port_xu:-${xupt:-}}"; key="xu" ;;
    xcpt) p="${port_xc:-${xcpt:-}}"; key="xc" ;;
    arpt) p="${port_ar:-${arpt:-}}"; key="ar" ;;
    *) return 1 ;;
  esac
  if [ -z "$p" ] && command -v port_get >/dev/null 2>&1; then
    p=$(port_get "$key" 2>/dev/null || true)
  fi
  p="${p%%,*}"
  printf '%s' "$p"
}

# reality_443_proto: 找出端口为 443 的 Reality 协议（最多只能有一个）。
# 输出协议名（vlpt/xhpt/vxpt/vwpt/xupt/xcpt/arpt），无则输出空串。
# 返回值：0=恰一个为 443；1=无；2=两个及以上同时为 443（端口冲突，调用方应 exit 1 停装——
# 两个入站共用同一个伪装 SNI，路由器无法按 SNI 区分它们，也不能静默挑一个）。
reality_443_proto(){
  local found="" count=0 names="" proto p
  for proto in vlpt xhpt vxpt vwpt xupt xcpt arpt; do
    p=$(_reality_proto_port "$proto")
    if [ "$p" = "443" ]; then
      found="$proto"; count=$((count + 1))
      if [ -z "$names" ]; then names="$proto"; else names="$names、$proto"; fi
    fi
  done
  if [ "$count" -ge 2 ]; then
    echo "错误：多个 Reality 协议同时配置了 443 端口（$names），端口冲突，无法安装。" >&2
    echo "443 端口同一时间只能由一个 Reality 入站占用，且 SNI 路由器无法按 SNI 区分它们（它们共用同一个伪装 SNI）。" >&2
    echo "请只保留一个 Reality 协议为 443，其余改用其他端口或留空（随机高位端口）。" >&2
    return 2
  fi
  printf '%s' "$found"
  [ "$count" = "1" ]
}

_detect_coexistence_web_engine(){
  if [ "${certsrc:-}" = "caddy" ]; then echo "caddy"; return 0; fi
  if [ "${certsrc:-}" = "acme" ] || [ "${certsrc:-}" = "nginx" ]; then echo "nginx"; return 0; fi
  if [ -f "$HOME/agsbx/certsrc" ]; then
    local saved_cs
    saved_cs=$(cat "$HOME/agsbx/certsrc" 2>/dev/null | tr -d '[:space:]')
    [ "$saved_cs" = "caddy" ] && { echo "caddy"; return 0; }
    [ "$saved_cs" = "acme" ] && { echo "nginx"; return 0; }
  fi
  if [ -n "${ym:-}" ]; then
    local mem_kb=""
    mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || true)
    if [ -n "$mem_kb" ] && [ "$mem_kb" -lt 262144 ]; then
      echo "nginx"; return 0
    fi
    echo "caddy"; return 0
  fi
  if (command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet caddy 2>/dev/null) || pgrep -x caddy >/dev/null 2>&1 || [ -s "${CADDYFILE:-/etc/caddy/Caddyfile}" ]; then
    echo "caddy"; return 0
  fi
  if (command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nginx 2>/dev/null) || pgrep -x nginx >/dev/null 2>&1 || [ -d "${NGINX_CONF_DIR:-/etc/nginx/conf.d}" ]; then
    echo "nginx"; return 0
  fi
  echo ""
}

web_server_migrate_to_port(){
  local target_port="$1"
  local sni_dom="${2:-}"
  local sni_tgt="${3:-}"
  local engine="${4:-}"
  [ -n "$target_port" ] || return 0

  # 委托 caddy_proxy.sh / nginx_proxy.sh 执行 set-port
  local caddy_bin="$HOME/.local/bin/caddy_proxy.sh"
  local nginx_bin="$HOME/.local/bin/nginx_proxy.sh"
  if command -v ensure_proxy_script >/dev/null 2>&1; then
    [ -z "$engine" ] || [ "$engine" = "caddy" ] && { ensure_proxy_script "caddy_proxy.sh" || true; }
    [ -z "$engine" ] || [ "$engine" = "nginx" ] && { ensure_proxy_script "nginx_proxy.sh" || true; }
  fi

  if [ -x "$caddy_bin" ] && { [ -z "$engine" ] || [ "$engine" = "caddy" ]; }; then
    if [ -n "$sni_dom" ] && [ -n "$sni_tgt" ] && [ "$target_port" != "443" ]; then
      "$caddy_bin" set-port "$target_port" --sni "$sni_dom" --sni-target "$sni_tgt" || echo "警告: caddy_proxy.sh set-port 失败"
    else
      "$caddy_bin" set-port "$target_port" || echo "警告: caddy_proxy.sh set-port 失败"
    fi
  fi

  if [ -x "$nginx_bin" ] && { [ -z "$engine" ] || [ "$engine" = "nginx" ]; }; then
    if [ -n "$sni_dom" ] && [ -n "$sni_tgt" ] && [ "$target_port" != "443" ]; then
      "$nginx_bin" set-port "$target_port" --sni "$sni_dom" --sni-target "$sni_tgt" || echo "警告: nginx_proxy.sh set-port 失败"
    else
      "$nginx_bin" set-port "$target_port" || echo "警告: nginx_proxy.sh set-port 失败"
    fi
  fi

  # 等待 443 释放（仅在未启用 L4 SNI 分流且迁移至非 443 端口时需要等待 443 端口腾空）
  if [ "$target_port" != "443" ] && [ -z "$sni_dom" ]; then
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

# vlpt_coexistence_sync_sni: 当 reym (无论是显式指定还是 auto_sni_resolve 自动探测得出) 确定后，
# 同步配置 443 四层 SNI 分流（Caddy layer4 或 Nginx stream），并将 Reality 内部监听端口绑定到 reality_port
vlpt_coexistence_sync_sni(){
  local sni_dom="${1:-${ym_vl_re:-${reym:-}}}"
  local proto="" _rc=0
  proto=$(reality_443_proto) || _rc=$?
  if [ "$_rc" = "2" ]; then
    exit 1
  fi
  [ -n "$proto" ] || return 0
  [ -n "$sni_dom" ] || return 0

  local wp="${web_port:-}"
  [ -z "$wp" ] && [ -f "$HOME/agsbx/web_port" ] && wp=$(cat "$HOME/agsbx/web_port" 2>/dev/null | tr -d '[:space:]')
  [ -n "$wp" ] && [ "$wp" != "443" ] || return 0

  local engine
  engine=$(_detect_coexistence_web_engine)
  [ -n "$engine" ] || return 0

  local existing_rp=""
  if command -v port_get >/dev/null 2>&1; then
    existing_rp=$(port_get "reality_port" 2>/dev/null || true)
  fi
  [ -z "$existing_rp" ] && [ -f "$HOME/agsbx/reality_port" ] && existing_rp=$(cat "$HOME/agsbx/reality_port" 2>/dev/null | tr -d '[:space:]')

  local rp
  rp=$(reality_port_find_available "$existing_rp" "$wp")
  export reality_port="$rp"
  # 只移占 443 的那一个入站（每协议独立变量对；共用变量会把所有已装 Reality 入站
  # 都移到同一个内网端口，高端口入站会被错移并端口冲突）。其余协议的变量保持未设置，
  # 各自入站仍监听 ::。
  case "$proto" in
    vlpt) export vlpt_listen_addr="127.0.0.1"; export vlpt_listen_port="$rp" ;;
    xhpt) export xhpt_listen_addr="127.0.0.1"; export xhpt_listen_port="$rp" ;;
    vxpt) export vxpt_listen_addr="127.0.0.1"; export vxpt_listen_port="$rp" ;;
    vwpt) export vwpt_listen_addr="127.0.0.1"; export vwpt_listen_port="$rp" ;;
    xupt) export xupt_listen_addr="127.0.0.1"; export xupt_listen_port="$rp" ;;
    xcpt) export xcpt_listen_addr="127.0.0.1"; export xcpt_listen_port="$rp" ;;
    arpt) export arpt_listen_addr="127.0.0.1"; export arpt_listen_port="$rp" ;;
  esac
  mkdir -p "$HOME/agsbx" 2>/dev/null || true
  echo "$rp" > "$HOME/agsbx/reality_port" 2>/dev/null || true
  command -v port_set >/dev/null 2>&1 && port_set "reality_port" "$rp"

  web_server_migrate_to_port "$wp" "$sni_dom" "$rp" "$engine"
  return 0
}

vlpt_coexistence_check(){
  local proto="" _rc=0
  proto=$(reality_443_proto) || _rc=$?
  if [ "$_rc" = "2" ]; then
    exit 1
  fi
  [ -n "$proto" ] || return 0

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
    echo "⚠️  【端口冲突提示】检测到 Reality 协议 ($proto) 配置了 443 端口。"
    echo "系统 Web 服务 (Caddy/Nginx) 默认亦监听 443 端口。"
    echo "继续操作需要将现有及后续 Web 服务迁移至本地回环高位端口 (如 8443)，"
    echo "由 Reality 统一接管 443 入口并进行透明内部流量回落 (Fallback)。"
    echo "------------------------------------------------------------"
    local ans="y"
    printf "是否允许调整 Web 服务端口并继续安装？[Y/n]: "
    read -r ans || ans="y"
    case "$ans" in
      [nN][oO]|[nN])
        echo "已取消配置：请勿在 $proto 中填入 443，请保持默认留空（使用随机高位端口）或使用其他非 443 端口。"
        exit 0
        ;;
      *)
        echo "已确认同意，正在执行 443 端口共存迁移..."
        ;;
    esac
  else
    echo "检测到 $proto=443 且处于非交互/无人值守模式，默认同意 Web 服务端口迁移并启用 Reality 443 共存。"
  fi

  local wp=""
  wp=$(web_port_find_available "$existing_wp")
  export web_port="$wp"
  mkdir -p "$HOME/agsbx" 2>/dev/null || true
  echo "$wp" > "$HOME/agsbx/web_port" 2>/dev/null || true
  command -v port_set >/dev/null 2>&1 && port_set "web_port" "$wp"

  local engine
  engine=$(_detect_coexistence_web_engine)
  if [ -n "${reym:-}" ] && [ -n "$engine" ]; then
    vlpt_coexistence_sync_sni "$reym"
  else
    web_server_migrate_to_port "$wp" "" "" "$engine"
  fi
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
  rm -f "$HOME/agsbx/web_port" "$HOME/agsbx/reality_port" "$cport_file" "$nport_file" 2>/dev/null || true
  return 0
}

vlpt_coexistence_post_start(){
  local proto="" _rc=0
  proto=$(reality_443_proto) || _rc=$?
  if [ "$_rc" = "2" ]; then
    exit 1
  fi
  if [ -n "$proto" ]; then
    local sni_dom="${ym_vl_re:-${reym:-}}"
    [ -z "$sni_dom" ] && [ -f "$HOME/agsbx/reym" ] && sni_dom=$(cat "$HOME/agsbx/reym" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$sni_dom" ]; then
      vlpt_coexistence_sync_sni "$sni_dom"
    fi
  fi
  [ -f "$HOME/agsbx/reality_port" ] || return 0
  local engine
  engine=$(_detect_coexistence_web_engine)
  if [ "$engine" = "caddy" ] && command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet caddy 2>/dev/null; then
      systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true
    else
      systemctl start caddy >/dev/null 2>&1 || true
    fi
  elif [ "$engine" = "nginx" ] && command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet nginx 2>/dev/null; then
      systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
    else
      systemctl start nginx >/dev/null 2>&1 || true
    fi
  fi
}

if command -v register_hook >/dev/null 2>&1; then
  register_hook post_start vlpt_coexistence_post_start
  register_hook on_uninstall vlpt_coexistence_cleanup
fi
