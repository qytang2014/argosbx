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
  [ -z "$known_wp" ] && known_wp=$(_proxy_get_port "caddy" 2>/dev/null || true)
  [ -z "$known_wp" ] && known_wp=$(_proxy_get_port "nginx" 2>/dev/null || true)
  if [ -n "$known_wp" ] && [ "$known_wp" = "$port" ]; then
    if (command -v systemctl >/dev/null 2>&1 && (systemctl is-active --quiet caddy 2>/dev/null || systemctl is-active --quiet nginx 2>/dev/null)) || \
       pgrep -x caddy >/dev/null 2>&1 || pgrep -x nginx >/dev/null 2>&1; then
      return 0
    fi
  fi

  return 1 # 被其他外部进程占用
}

# Safe non-interactive command execution with bounded timeout (works even when module is sourced standalone).
_vlpt_run_timeout(){
  local sec="$1"; shift
  if command -v run_with_timeout >/dev/null 2>&1; then
    run_with_timeout "$sec" "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "$sec" "$@" </dev/null
  else
    "$@" </dev/null
  fi
}

# Static capability check before invoking caddy_proxy.sh / nginx_proxy.sh subcommands.
_vlpt_proxy_supports(){
  local bin="$1" cmd="$2"
  if command -v proxy_script_supports_cmd >/dev/null 2>&1; then
    proxy_script_supports_cmd "$bin" "$cmd"
    return $?
  fi
  [ -f "$bin" ] && [ -r "$bin" ] || return 1
  case "$cmd" in
    get-port) grep -qE '^[[:space:]]*get-port\)' "$bin" 2>/dev/null && return 0 ;;
    set-port) grep -qE '^[[:space:]]*set-port\)' "$bin" 2>/dev/null && return 0 ;;
    reload)   grep -qE '^[[:space:]]*reload\)' "$bin" 2>/dev/null && return 0 ;;
    *) return 1 ;;
  esac
  if grep -qE 'read -p|while true' "$bin" 2>/dev/null; then
    return 1
  fi
  return 0
}

# Query current non-443 HTTPS port from caddy_proxy.sh / nginx_proxy.sh via CLI.
_proxy_get_port(){
  local eng="$1" bin="" p=""
  case "$eng" in
    caddy) bin="$HOME/.local/bin/caddy_proxy.sh" ;;
    nginx) bin="$HOME/.local/bin/nginx_proxy.sh" ;;
    *) return 1 ;;
  esac
  [ -x "$bin" ] || return 1
  _vlpt_proxy_supports "$bin" "get-port" || return 1
  p=$(_vlpt_run_timeout "${AGSBX_UNINSTALL_TIMEOUT:-15}" "$bin" get-port 2>/dev/null | tr -d '[:space:]' || true)
  case "$p" in
    443|''|*[!0-9]*) return 1 ;;
    *) printf '%s' "$p"; return 0 ;;
  esac
}

# Delegate safe config validation and service reload to caddy_proxy.sh / nginx_proxy.sh.
_proxy_reload(){
  local eng="$1" bin=""
  case "$eng" in
    caddy) bin="$HOME/.local/bin/caddy_proxy.sh" ;;
    nginx) bin="$HOME/.local/bin/nginx_proxy.sh" ;;
    *) return 0 ;;
  esac
  [ -x "$bin" ] || return 0
  _vlpt_proxy_supports "$bin" "reload" || return 0
  _vlpt_run_timeout "${AGSBX_UNINSTALL_TIMEOUT:-20}" "$bin" reload >/dev/null 2>&1 || true
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

# Check whether any protocol selection flag is active in the current run context.
_has_any_proto_flag(){
  [ -n "${vlp:-}" ] || [ -n "${xhp:-}" ] || [ -n "${vxp:-}" ] || [ -n "${vwp:-}" ] || \
  [ -n "${xup:-}" ] || [ -n "${xcp:-}" ] || [ -n "${arp:-}" ] || [ -n "${hyp:-}" ] || \
  [ -n "${tup:-}" ] || [ -n "${anp:-}" ] || [ -n "${nvp:-}" ] || [ -n "${vmp:-}" ] || \
  [ -n "${vmt:-}" ] || [ -n "${ssp:-}" ] || [ -n "${snp:-}" ] || [ -n "${sop:-}" ]
}

# _reality_proto_port PROTO: 取某一 Reality 协议的有效端口（实例 1）。
# 仅在当前运行启用了该协议（或孤立无协议标志的测试/查询上下文）时才允许回退读取
# ports.env，避免 rep 切换协议时被历史残留的 443 端口干扰。
_reality_proto_port(){
  local proto="$1" p="" key="" flag="" active=0
  case "$proto" in
    vlpt) p="${port_vl_re:-${vlpt:-}}"; key="vl_re"; flag="${vlp:-}" ;;
    xhpt) p="${port_xh:-${xhpt:-}}"; key="xh"; flag="${xhp:-}" ;;
    vxpt) p="${port_vx:-${vxpt:-}}"; key="vx"; flag="${vxp:-}" ;;
    vwpt) p="${port_vw:-${vwpt:-}}"; key="vw"; flag="${vwp:-}" ;;
    xupt) p="${port_xu:-${xupt:-}}"; key="xu"; flag="${xup:-}" ;;
    xcpt) p="${port_xc:-${xcpt:-}}"; key="xc"; flag="${xcp:-}" ;;
    arpt) p="${port_ar:-${arpt:-}}"; key="ar"; flag="${arp:-}" ;;
    *) return 1 ;;
  esac
  if [ "$flag" = "yes" ] || [ "$flag" = "$proto" ]; then
    active=1
  elif ! _has_any_proto_flag; then
    active=1
  fi
  if [ -z "$p" ] && [ "$active" = "1" ] && command -v port_get >/dev/null 2>&1; then
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

  # 任一实际执行的 set-port 失败都记下（Caddy 与 Nginx 两路同等处理）；
  # 失败时不再静默继续：Reality 入站已移到内网端口，路由器没生效则 443 无人监听，
  # 代理+订阅同时断，必须停装。
  local _rc=0 _t="${AGSBX_UNINSTALL_TIMEOUT:-20}"
  if [ -x "$caddy_bin" ] && { [ -z "$engine" ] || [ "$engine" = "caddy" ]; }; then
    if ! _vlpt_proxy_supports "$caddy_bin" "set-port"; then
      echo "警告: 本地 caddy_proxy.sh 版本过旧且不支持 set-port，跳过执行以避免阻塞" >&2
      _rc=1
    elif [ -n "$sni_dom" ] && [ -n "$sni_tgt" ] && [ "$target_port" != "443" ]; then
      _vlpt_run_timeout "$_t" "$caddy_bin" set-port "$target_port" --sni "$sni_dom" --sni-target "$sni_tgt" || { echo "警告: caddy_proxy.sh set-port 失败"; _rc=1; }
    else
      _vlpt_run_timeout "$_t" "$caddy_bin" set-port "$target_port" || { echo "警告: caddy_proxy.sh set-port 失败"; _rc=1; }
    fi
  fi

  if [ -x "$nginx_bin" ] && { [ -z "$engine" ] || [ "$engine" = "nginx" ]; }; then
    if ! _vlpt_proxy_supports "$nginx_bin" "set-port"; then
      echo "警告: 本地 nginx_proxy.sh 版本过旧且不支持 set-port，跳过执行以避免阻塞" >&2
      _rc=1
    elif [ -n "$sni_dom" ] && [ -n "$sni_tgt" ] && [ "$target_port" != "443" ]; then
      _vlpt_run_timeout "$_t" "$nginx_bin" set-port "$target_port" --sni "$sni_dom" --sni-target "$sni_tgt" || { echo "警告: nginx_proxy.sh set-port 失败"; _rc=1; }
    else
      _vlpt_run_timeout "$_t" "$nginx_bin" set-port "$target_port" || { echo "警告: nginx_proxy.sh set-port 失败"; _rc=1; }
    fi
  fi

  if [ "$_rc" != "0" ]; then
    echo "错误：Web 服务 set-port 失败，443 SNI 分流未生效；Reality 入站已移到内网端口，443 无人监听，安装停止。" >&2
    return 1
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

  local sync_key="${engine}|${wp}|${sni_dom}|${rp}"
  if [ "${_VLPT_SNI_SYNCED_KEY:-}" = "$sync_key" ]; then
    # Verify on-disk router config is still intact before skipping redundant set-port
    local intact=1
    if [ "$engine" = "caddy" ]; then
      local cf="${CADDYFILE:-/etc/caddy/Caddyfile}"
      if [ -f "$cf" ] && ! grep -qE '^[[:space:]]*layer4[[:space:]]*\{' "$cf" 2>/dev/null; then
        intact=0
      fi
    elif [ "$engine" = "nginx" ]; then
      local sc="${NGINX_DIR:-/etc/nginx}/stream.d/reality_sni.conf"
      if [ -d "${NGINX_DIR:-/etc/nginx}" ] && [ ! -f "$sc" ]; then
        intact=0
      fi
    fi
    if [ "$intact" = "1" ]; then
      return 0
    fi
  fi

  web_server_migrate_to_port "$wp" "$sni_dom" "$rp" "$engine" || return 1
  export _VLPT_SNI_SYNCED_KEY="$sync_key"
  return 0
}

vlpt_coexistence_check(){
  local proto="" _rc=0
  proto=$(reality_443_proto) || _rc=$?
  if [ "$_rc" = "2" ]; then
    exit 1
  fi
  [ -n "$proto" ] || return 0

  # 检测是否已存在先前配置的有效 web_port（仅通过端口记录或 proxy 脚本 CLI 查询）
  local existing_wp=""
  if command -v port_get >/dev/null 2>&1; then
    existing_wp=$(port_get "web_port" 2>/dev/null || true)
  fi
  if [ -z "$existing_wp" ] && [ -f "$HOME/agsbx/web_port" ]; then
    existing_wp=$(cat "$HOME/agsbx/web_port" 2>/dev/null | tr -d '[:space:]')
  fi
  if [ -z "$existing_wp" ]; then
    existing_wp=$(_proxy_get_port "caddy" 2>/dev/null || _proxy_get_port "nginx" 2>/dev/null || true)
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
    vlpt_coexistence_sync_sni "$reym" || return 1
  else
    web_server_migrate_to_port "$wp" "" "" "$engine" || return 1
  fi
  export ym_vl_fb_port="$wp"
  return 0
}

vlpt_coexistence_cleanup(){
  echo "[卸载 1/4] 检查并恢复 Web 服务 443 共存配置..."
  local wp=""
  [ -f "$HOME/agsbx/web_port" ] && wp=$(cat "$HOME/agsbx/web_port" 2>/dev/null | tr -d '[:space:]')
  local caddy_bin="$HOME/.local/bin/caddy_proxy.sh"
  local nginx_bin="$HOME/.local/bin/nginx_proxy.sh"

  # Scheme B: attempt a short-timeout update only for installed proxy scripts before querying ports
  # so legacy scripts without get-port/set-port can upgrade when online without hanging when offline.
  if [ -n "$wp" ] || [ -x "$caddy_bin" ] || [ -x "$nginx_bin" ]; then
    if command -v ensure_proxy_script >/dev/null 2>&1; then
      [ -x "$caddy_bin" ] && { ensure_proxy_script "caddy_proxy.sh" || true; }
      [ -x "$nginx_bin" ] && { ensure_proxy_script "nginx_proxy.sh" || true; }
    fi
  fi

  local caddy_wp="" nginx_wp=""
  caddy_wp=$(_proxy_get_port "caddy" 2>/dev/null || true)
  nginx_wp=$(_proxy_get_port "nginx" 2>/dev/null || true)

  if [ -n "$wp" ] || [ -n "$caddy_wp" ] || [ -n "$nginx_wp" ]; then
    echo "检测到 Web 服务曾配置高位端口共存，正在恢复 Caddy / Nginx 默认 443 端口与初始配置..."
    # Stop node kernels with a bounded timeout so 443 is released before reverting the Web server.
    if command -v systemctl >/dev/null 2>&1; then
      _vlpt_run_timeout 15 systemctl stop xr sb argo >/dev/null 2>&1 || true
    elif command -v rc-service >/dev/null 2>&1; then
      _vlpt_run_timeout 15 rc-service xray stop >/dev/null 2>&1 || true
      _vlpt_run_timeout 15 rc-service sing-box stop >/dev/null 2>&1 || true
      _vlpt_run_timeout 15 rc-service argo stop >/dev/null 2>&1 || true
    fi
    kill -15 $(pgrep -f 'agsbx/s' 2>/dev/null) $(pgrep -f 'agsbx/x' 2>/dev/null) $(pgrep -f 'agsbx/c' 2>/dev/null) >/dev/null 2>&1 || true

    # Revert only the engine(s) that actually hold a non-443 port or match the recorded coexistence engine.
    local revert_engines="" det_eng="" eng=""
    [ -n "$caddy_wp" ] && revert_engines="${revert_engines:+$revert_engines }caddy"
    [ -n "$nginx_wp" ] && revert_engines="${revert_engines:+$revert_engines }nginx"
    if [ -z "$revert_engines" ] && [ -n "$wp" ]; then
      det_eng=$(_detect_coexistence_web_engine)
      [ -n "$det_eng" ] && revert_engines="$det_eng"
    fi
    for eng in $revert_engines; do
      web_server_migrate_to_port 443 "" "" "$eng" || echo "错误：卸载回滚失败，${eng} 未恢复到 443 端口；请手动执行 ${eng}_proxy.sh set-port 443 恢复。" >&2
    done
  fi
  rm -f "$HOME/agsbx/web_port" "$HOME/agsbx/reality_port" 2>/dev/null || true
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
      # post_start 是 hook（run_hook 会吞掉返回值），这里至少要明确报错，不能静默：
      # 此时 Reality 入站已在内网端口，路由器没生效则 443 无人监听。
      vlpt_coexistence_sync_sni "$sni_dom" || { echo "错误：post_start 阶段 443 SNI 分流配置失败（set-port 未生效），Reality 入站已在内网端口，443 无人监听；请手动检查 caddy_proxy.sh / nginx_proxy.sh 的 set-port，或重新安装。" >&2; return 1; }
    fi
  fi
  [ -f "$HOME/agsbx/reality_port" ] || return 0
  local engine
  engine=$(_detect_coexistence_web_engine)
  [ -n "$engine" ] && _proxy_reload "$engine"
}

if command -v register_hook >/dev/null 2>&1; then
  register_hook post_start vlpt_coexistence_post_start
  register_hook on_uninstall vlpt_coexistence_cleanup
fi
