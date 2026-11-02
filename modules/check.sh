# check.sh: 一键自检（只读，不修改系统）
#
# 用法：agsbx check
# 输出 [PASS]/[WARN]/[FAIL] 逐行 + 汇总计数，贴给维护者可直接定位。
#
# 检查项：
#   1. 内核进程（xray/sing-box 该跑的在跑）
#   2. 端口监听（协议端口有监听）
#   3. 域名证书（存在/未过期/域名匹配/剩余>7天）
#   4. DNS（ym 解析到本机，仅 WARN）
#   5. 订阅（https 模式回环 curl）
#   6. Caddy 配置 validate（仅 Caddy 模式）
#   7. 防火墙（后端状态 + 记录规则）
#   8. 系统信息（磁盘/内存，仅信息）

CHECK_PASS=0
CHECK_WARN=0
CHECK_FAIL=0

_check_ok(){ CHECK_PASS=$((CHECK_PASS+1)); echo "[PASS] $1"; }
_check_warn(){ CHECK_WARN=$((CHECK_WARN+1)); echo "[WARN] $1"; }
_check_fail(){ CHECK_FAIL=$((CHECK_FAIL+1)); echo "[FAIL] $1"; }

# check_kernels: 哪些内核该跑（按 json 文件存在判断），是否在跑
check_kernels(){
  local want_xr=0 want_sb=0 has_xr=0 has_sb=0
  [ -f "$HOME/agsbx/xr.json" ] && want_xr=1
  [ -f "$HOME/agsbx/sb.json" ] && want_sb=1
  if [ "$want_xr" = "0" ] && [ "$want_sb" = "0" ]; then
    _check_warn "无内核配置文件（未安装？）"
    return 0
  fi
  if [ "$want_xr" = "1" ]; then
    if pgrep -f "agsbx/xray" >/dev/null 2>&1 || pgrep -f "$HOME/agsbx/xray" >/dev/null 2>&1; then
      has_xr=1; _check_ok "xray 进程运行中"
    else
      _check_fail "xray 应运行但未找到进程"
    fi
  fi
  if [ "$want_sb" = "1" ]; then
    if pgrep -f "agsbx/sing-box" >/dev/null 2>&1 || pgrep -f "$HOME/agsbx/sing-box" >/dev/null 2>&1; then
      has_sb=1; _check_ok "sing-box 进程运行中"
    else
      _check_fail "sing-box 应运行但未找到进程"
    fi
  fi
  return 0
}

# check_ports: 每个 port_* 文件的端口是否有监听
check_ports(){
  local f="" p="" proto="" missing=0 total=0
  for f in "$HOME"/agsbx/port_*; do
    [ -f "$f" ] || continue
    p=$(tr -d ' \t\r\n' < "$f" 2>/dev/null)
    case "$p" in ''|*[!0-9]*) continue;; esac
    total=$((total+1))
    proto=$(basename "$f")
    if command -v ss >/dev/null 2>&1; then
      if ss -tlnp 2>/dev/null | grep -q ":$p " || ss -ulnp 2>/dev/null | grep -q ":$p "; then
        : # 有监听
      else
        _check_fail "端口 $p ($proto) 无监听"
        missing=$((missing+1))
      fi
    else
      _check_warn "无 ss 命令，跳过端口监听检查"
      return 0
    fi
  done
  if [ "$total" = "0" ]; then
    _check_warn "无 port_* 文件"
  elif [ "$missing" = "0" ]; then
    _check_ok "全部 $total 个端口有监听"
  fi
  return 0
}

# check_cert: 域名证书有效性（复用 domain_cert_valid 逻辑，输出细节）
check_cert(){
  local ym_c=""
  ym_c=$(tr -d ' \t\r\n' < "$HOME/agsbx/ym" 2>/dev/null)
  if [ -z "$ym_c" ]; then
    _check_warn "未设置 ym，跳过域名证书检查"
    return 0
  fi
  local crt="$HOME/agsbx/cert/cert.crt" key="$HOME/agsbx/cert/private.key"
  if [ ! -s "$crt" ] || [ ! -s "$key" ]; then
    _check_fail "域名证书文件缺失（$crt）"
    return 0
  fi
  if ! command -v openssl >/dev/null 2>&1; then
    _check_warn "无 openssl，跳过证书解析"
    return 0
  fi
  local subj=""
  subj=$(openssl x509 -in "$crt" -noout -subject -ext subjectAltName 2>/dev/null)
  if [ -z "$subj" ]; then
    _check_fail "证书无法解析"
    return 0
  fi
  if ! printf '%s' "$subj" | grep -q "$ym_c"; then
    _check_fail "证书域名不匹配 ym=$ym_c"
    return 0
  fi
  local enddate="" endepoch="" now=""
  enddate=$(openssl x509 -in "$crt" -noout -enddate 2>/dev/null | cut -d= -f2)
  if [ -n "$enddate" ]; then
    endepoch=$(date -d "$enddate" +%s 2>/dev/null || echo 0)
    now=$(date +%s)
    local days=$(( (endepoch - now) / 86400 ))
    if [ "$days" -lt 0 ]; then
      _check_fail "证书已过期"
    elif [ "$days" -lt 7 ]; then
      _check_warn "证书剩余 $days 天（<7 天）"
    else
      _check_ok "域名证书有效（$ym_c，剩余 $days 天）"
    fi
  else
    _check_ok "域名证书存在且域名匹配（$ym_c）"
  fi
  return 0
}

# check_dns: ym 是否解析到本机（仅 WARN，CDN 场景不判 FAIL）
check_dns(){
  local ym_c="" rip="" lip=""
  ym_c=$(tr -d ' \t\r\n' < "$HOME/agsbx/ym" 2>/dev/null)
  [ -n "$ym_c" ] || return 0
  if ! command -v getent >/dev/null 2>&1 && ! command -v nslookup >/dev/null 2>&1; then
    return 0
  fi
  if command -v getent >/dev/null 2>&1; then
    rip=$(getent ahosts "$ym_c" 2>/dev/null | awk '{print $1}' | head -1)
  else
    rip=$(nslookup "$ym_c" 2>/dev/null | awk '/^Address: /{print $2}' | tail -1)
  fi
  [ -n "$rip" ] || { _check_warn "ym=$ym_c DNS 无解析"; return 0; }
  # 本机 IP（取第一个非回环）
  lip=$(ip -4 route get 8.8.8.8 2>/dev/null | awk '{print $7}' | head -1)
  if [ -z "$lip" ]; then
    lip=$(hostname -I 2>/dev/null | awk '{print $1}')
  fi
  if [ -n "$lip" ] && [ "$rip" = "$lip" ]; then
    _check_ok "DNS：$ym_c 解析到本机 ($rip)"
  else
    _check_warn "DNS：$ym_c 解析到 $rip，本机 $lip（CDN 或未指向本机）"
  fi
  return 0
}

# check_subscription: https 订阅回环可达性
check_subscription(){
  local mode="" ym_c="" token="" code=""
  mode=$(tr -d ' \t\r\n' < "$HOME/agsbx/subhttps.mode" 2>/dev/null)
  [ -n "$mode" ] || { _check_warn "未启用订阅"; return 0; }
  case "$mode" in
    https|https-merged)
      ym_c=$(tr -d ' \t\r\n' < "$HOME/agsbx/ym" 2>/dev/null)
      token=$(tr -d ' \t\r\n' < "$HOME/agsbx/subtoken.log" 2>/dev/null)
      if [ -z "$ym_c" ] || [ -z "$token" ]; then
        _check_fail "https 订阅缺少 ym/token"
        return 0
      fi
      if ! command -v curl >/dev/null 2>&1; then
        _check_warn "无 curl，跳过订阅检查"; return 0
      fi
      code=$(curl -sk --noproxy '*' --max-time 10 --resolve "$ym_c:443:127.0.0.1" \
        -o /dev/null -w "%{http_code}" "https://$ym_c/$token/clmi.yaml" 2>/dev/null)
      if [ "$code" = "200" ]; then
        _check_ok "https 订阅可达（$mode）"
      else
        _check_fail "https 订阅回环验证非 200（HTTP $code）"
      fi
      ;;
    *)
      _check_ok "订阅模式：$mode"
      ;;
  esac
  return 0
}

# check_caddy: Caddy 配置 validate（仅当 caddyfile_path 存在）
check_caddy(){
  local sysfile=""
  [ -f "$HOME/agsbx/caddyfile_path" ] || return 0
  sysfile=$(tr -d ' \t\r\n' < "$HOME/agsbx/caddyfile_path" 2>/dev/null)
  [ -n "$sysfile" ] && [ -f "$sysfile" ] || { _check_warn "caddyfile_path 记录无效"; return 0; }
  if ! command -v caddy >/dev/null 2>&1; then
    _check_warn "caddyfile 存在但无 caddy 命令"; return 0
  fi
  # 主 Caddyfile（import 上游）
  local mainfile="/etc/caddy/Caddyfile"
  [ -f "$mainfile" ] || mainfile="$sysfile"
  if caddy validate --config "$mainfile" --adapter caddyfile >/dev/null 2>&1; then
    _check_ok "Caddy 配置校验通过"
  else
    _check_fail "Caddy 配置校验未通过"
  fi
  return 0
}

# check_firewall: 后端状态 + 记录规则数
check_firewall(){
  local backends="" n=0
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    backends="$backends ufw"; n=$((n+1))
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && [ "$(firewall-cmd --state 2>/dev/null)" = "running" ]; then
    backends="$backends firewalld"; n=$((n+1))
  fi
  if [ "$n" = "0" ]; then
    _check_warn "无 ufw/firewalld 在运行"
  else
    _check_ok "防火墙后端：$backends"
  fi
  if [ -f "$HOME/agsbx/ufw.rules" ]; then
    local rc=0; rc=$(grep -c . "$HOME/agsbx/ufw.rules" 2>/dev/null || echo 0)
    _check_ok "已记录 $rc 条节点端口规则"
  fi
  return 0
}

# check_system: 磁盘/内存信息（仅信息，不判分）
check_system(){
  local mem="" disk=""
  mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2"M total, "$7"M avail"}')
  disk=$(df -h "$HOME" 2>/dev/null | awk 'NR==2{print $4" avail"}')
  [ -n "$mem" ] && echo "[INFO] 内存：$mem"
  [ -n "$disk" ] && echo "[INFO] 磁盘：$disk"
  return 0
}

# agsbx_check: 主入口
agsbx_check(){
  CHECK_PASS=0; CHECK_WARN=0; CHECK_FAIL=0
  echo "=== argosbx 自检 $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date) ==="
  echo "主机：$(hostname 2>/dev/null || echo unknown)"
  echo "---"
  check_kernels
  check_ports
  check_cert
  check_dns
  check_subscription
  check_caddy
  check_firewall
  check_system
  echo "---"
  echo "结果：$CHECK_PASS 通过，$CHECK_WARN 警告，$CHECK_FAIL 失败"
  [ "$CHECK_FAIL" = "0" ]
}
