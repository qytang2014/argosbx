# HTTPS domain subscription (private module, main script only).
# Current subscription is plain HTTP on a random port, served from
# $HOME/websbx/<token>/, protected only by the token in the URL.
# This module adds an HTTPS domain subscription on top, without
# breaking the HTTP fallback:
#   mode https:       ym + domain cert ready + (mem >= 256MB or our
#                     subscription Caddy already running) + caddy
#                     available + Caddy starts on 443. Caddy serves
#                     $HOME/websbx directly (file_server) with the
#                     domain cert in $HOME/agsbx/cert, so no separate
#                     subscription server is needed in this mode.
#   mode https-merged: https 决议后独立 Caddy 绑不上 443，但 443 正被我们自己的
#                     证书流程 Caddy（/etc/caddy/argosbx.caddyfile）占用时，把订阅
#                     handle_path 自动合并进系统 Caddyfile 并 reload，不新增进程。
#   mode http-domain: ym set, but cert not ready, or memory gate
#                     fails, or caddy missing / 443 busy. Plain HTTP
#                     on ym:port/token, via the existing websbx server.
#   mode http-ip:     no ym. Original plain HTTP on IP:port/token.
# Rules, all deliberate:
# - Never self-signed HTTPS: a cert that does not parse or does not
#   match ym is not HTTPS, it is http-domain. Most subscription
#   clients reject self-signed HTTPS on update, so faking it would
#   break updates, not secure them.
# - Never start a second Caddy on 443 if one already binds it: a
#   failed start falls back to http-domain with a warning, it never
#   kills an existing Caddy (which may be the user's own service).
# - Auto-merge: when the 443 holder is provably our own cert-flow Caddy
#   (/etc/caddy/argosbx.caddyfile, four eligibility checks below), the
#   subscription handle_path is merged into it automatically and the
#   service reloaded, instead of asking the user to paste snippets.
#   A user's own Caddy/Nginx is never touched (falls back to snippets).
# - Memory gate uses the same detection as detect_certsrc
#   (/proc/meminfo MemTotal, < 262144 KB = 256MB), with an override
#   SUBHTTPS_MEM_KB for tests. The exception is only our own
#   subscription Caddy already running (no new process cost), not
#   any Caddy process, and not a system Caddy (which we must not
#   reconfigure or kill).
# - When https is up, the external plain-HTTP websbx server is
#   stopped and its @reboot cron removed, otherwise the same token
#   and files would still be fetchable in plain text and HTTPS
#   would gain nothing. The subscription Caddy gets its own
#   @reboot cron (subhttpsync) instead. When https falls back to
#   HTTP, the subscription Caddy is stopped, its cron removed, and
#   websbx (already started by the sub block before display) keeps
#   serving, as before.
# - Port 443 is managed separately from node ports (ufw.rules):
#   subhttps.443 is a marker file, present only while 443 was opened
#   by this module. Node ufw_sync never touches 443, and this module
#   never touches node rules, so a standalone subhttpsync on reboot
#   cannot delete node rules (it has no protocol variables in scope).
# - The subscription port (subpt, else the random port in subport.log)
#   is managed the same way, but only for HTTP subscriptions: when
#   websbx actually serves externally (http IP or http domain), its
#   port must be open or the subscription is unreachable behind ufw.
#   It is tracked by subhttps.subport (content "port/tcp"), NOT by
#   ufw.rules, because the port is only known after the sub block
#   runs (ufw_sync runs before it, so a first install would record
#   a stale port, and a port change on rep would be missed). When
#   the mode switches to https, websbx is stopped, so the old
#   subscription port is deleted; when the port changes, the old
#   rule is deleted and the new one opened. ufw_apply_saved calls
#   this manager too, so enabling ufw later and running ufwsync
#   opens the subscription port as well as the node ports.
# - All failures fall back, never abort: sync returns 0 even when
#   HTTPS is unavailable, so install/display/list never break.
subhttps_trim(){
  tr -d ' \t\r\n' 2>/dev/null
}
subhttps_read(){
  cat "$1" 2>/dev/null | subhttps_trim
}
subhttps_mem_kb(){
  if [ -n "${SUBHTTPS_MEM_KB:-}" ]; then echo "$SUBHTTPS_MEM_KB"; return; fi
  awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null
}
subhttps_mem_ok(){
  local mem
  mem=$(subhttps_mem_kb)
  if [ -z "$mem" ]; then return 1; fi
  case "$mem" in ''|*[!0-9]*) return 1;; esac
  [ "$mem" -ge 262144 ]
}
subhttps_cert_ok(){
  local ym_c="$1" crt="$HOME/agsbx/cert/cert.crt" key="$HOME/agsbx/cert/private.key" txt=""
  [ -n "$ym_c" ] || return 1
  [ -s "$crt" ] && [ -s "$key" ] || return 1
  command -v openssl >/dev/null 2>&1 || return 1
  txt=$(openssl x509 -in "$crt" -noout -subject -ext subjectAltName 2>/dev/null || openssl x509 -in "$crt" -noout -subject 2>/dev/null)
  [ -n "$txt" ] || return 1
  case "$txt" in *"$ym_c"*) return 0;; *) return 1;; esac
}
subhttps_caddy_running(){
  local pid=""
  [ -f "$HOME/agsbx/subhttps.pid" ] || return 1
  pid=$(subhttps_read "$HOME/agsbx/subhttps.pid")
  case "$pid" in ''|*[!0-9]*) return 1;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  if [ -f "/proc/$pid/cmdline" ]; then
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "Caddyfile.sub" || return 1
  fi
  return 0
}
subhttps_decide_mode(){
  local token="" ym_c=""
  token=$(subhttps_read "$HOME/agsbx/subtoken.log")
  ym_c=$(subhttps_read "$HOME/agsbx/ym")
  if [ -z "$token" ]; then echo "http-ip"; return; fi
  if [ -z "$ym_c" ]; then echo "http-ip"; return; fi
  if ! subhttps_cert_ok "$ym_c"; then echo "http-domain"; return; fi
  # 自动合并模式不新增进程（系统 Caddy 已在运行）：内存门不拦截，可合并时直接走 https
  if subhttps_merge_eligible "$ym_c"; then echo "https"; return; fi
  if ! subhttps_mem_ok && ! subhttps_https_active; then echo "http-domain"; return; fi
  if ! command -v caddy >/dev/null 2>&1 && ! subhttps_https_active; then echo "http-domain"; return; fi
  echo "https"
}
subhttps_write_conf(){
  local ym_c="$1" token="" _webroot=""
  [ -n "$ym_c" ] || return 1
  token=$(subhttps_read "$HOME/agsbx/subtoken.log")
  _webroot="${webroot:-/var/www/html}"
  mkdir -p "$HOME/agsbx" 2>/dev/null || true
  {
    echo "{"
    echo "  admin off"
    echo "}"
    echo "https://$ym_c {"
    echo "  tls \"$HOME/agsbx/cert/cert.crt\" \"$HOME/agsbx/cert/private.key\""
    if [ -n "$token" ]; then
      echo "  handle_path /$token/* {"
      echo "    root * \"$HOME/websbx\""
      echo "    file_server"
      echo "  }"
    fi
    echo "  root * \"$_webroot\""
    echo "  file_server"
    echo "}"
  } > "$HOME/agsbx/Caddyfile.sub" 2>/dev/null || return 1
  return 0
}
# --- 自动合并到系统 Caddy ---
# 场景：证书流程（certsrc=caddy）把博客配到了系统 Caddy（/etc/caddy/argosbx.caddyfile）
# 并占用 443，订阅的独立 Caddy 绑不上 443。既然占 443 的是我们自己的配置，就把订阅
# 的 handle_path 自动合并进系统 Caddyfile 并 reload，不再需要手动贴片段。
# 红线：eligible 的四个条件缺一不可，绝不碰用户自己的 Caddy 配置；任何一步失败都
# 摘除合并块恢复原文件，并回退到原来的 http-domain + 片段流程。
# 路径用环境变量覆盖（SUBHTTPS_MERGE_SYSFILE/MAINFILE），主要给测试用。
subhttps_merge_sysfile(){ echo "${SUBHTTPS_MERGE_SYSFILE:-/etc/caddy/argosbx.caddyfile}"; }
subhttps_merge_mainfile(){ echo "${SUBHTTPS_MERGE_MAINFILE:-/etc/caddy/Caddyfile}"; }
subhttps_merge_eligible(){
  local ym_c="$1" sysfile="" mainfile=""
  [ -n "$ym_c" ] || return 1
  sysfile=$(subhttps_merge_sysfile); mainfile=$(subhttps_merge_mainfile)
  # 1) 证书流程记录过它写了系统 Caddyfile（非 root 回落到 $HOME/agsbx/Caddyfile 时这里就不等）
  [ "$(subhttps_read "$HOME/agsbx/caddyfile_path")" = "$sysfile" ] || return 1
  # 2) 文件存在，且主配置 import 了它
  [ -f "$sysfile" ] || return 1
  grep -q "argosbx\.caddyfile" "$mainfile" 2>/dev/null || return 1
  # 3) 文件里确实是我们的站点块（防用户换了内容）
  grep -qF "$ym_c {" "$sysfile" 2>/dev/null || return 1
  # 4) 系统 caddy 服务正在运行
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl is-active --quiet caddy 2>/dev/null || return 1
  return 0
}
subhttps_merge_active(){
  # 合并块在位且 token 是当前 token（token 变了算未激活，走重新合并）
  local ym_c="$1" token="" sysfile=""
  [ -n "$ym_c" ] || return 1
  token=$(subhttps_read "$HOME/agsbx/subtoken.log"); [ -n "$token" ] || return 1
  sysfile=$(subhttps_merge_sysfile)
  grep -q "# >>> argosbx-subscription" "$sysfile" 2>/dev/null || return 1
  grep -qF "handle_path /$token/" "$sysfile" 2>/dev/null
}
subhttps_merge_serving(){
  # display 用：块在位且系统 Caddy 在运行
  subhttps_merge_active "$1" || return 1
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl is-active --quiet caddy 2>/dev/null
}
subhttps_https_active(){
  # https 已生效：独立 Caddy 在跑，或已合并到系统 Caddy（内存门/缺 caddy 二进制时豁免）
  subhttps_caddy_running && return 0
  subhttps_merge_active "$(subhttps_read "$HOME/agsbx/ym")"
}
subhttps_strip_merge_block(){
  # 从系统 Caddyfile 里手术摘除合并块（保留用户其他手工修改）；摘掉了返回 0
  local sysfile="" before="" after=""
  sysfile=$(subhttps_merge_sysfile)
  [ -f "$sysfile" ] || return 1
  grep -q "# >>> argosbx-subscription" "$sysfile" 2>/dev/null || return 1
  before=$(sha256sum "$sysfile" 2>/dev/null | awk '{print $1}')
  awk '/# >>> argosbx-subscription/{skip=1} !skip{print} /# <<< argosbx-subscription/{skip=0}' "$sysfile" > "$sysfile.tmp" && mv -f "$sysfile.tmp" "$sysfile"
  after=$(sha256sum "$sysfile" 2>/dev/null | awk '{print $1}')
  [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]
}
subhttps_merge_insert(){
  # 摘除旧块后把新订阅块插到站点块首行之后；找不到站点块返回 1（原文件不动）
  local ym_c="$1" token="$2" sysfile="" websbx="" block_tmp=""
  [ -n "$ym_c" ] && [ -n "$token" ] || return 1
  sysfile=$(subhttps_merge_sysfile); websbx="$HOME/websbx"
  block_tmp=$(mktemp) || return 1
  {
    echo "  # >>> argosbx-subscription (argosbx 自动合并，勿手工改) >>>"
    echo "  handle_path /$token/* {"
    echo "    root * \"$websbx\""
    echo "    file_server"
    echo "  }"
    echo "  # <<< argosbx-subscription <<<"
  } > "$block_tmp"
  subhttps_strip_merge_block >/dev/null 2>&1 || true
  if awk -v ym="$ym_c" -v bf="$block_tmp" '
    BEGIN{ while((getline line < bf) > 0){ block = block line "\n" } }
    !done && index($0, ym " {") == 1 { print; printf "%s", block; done=1; next }
    { print }
    END{ if(!done) exit 1 }
  ' "$sysfile" > "$sysfile.new" 2>/dev/null; then
    mv -f "$sysfile.new" "$sysfile"; rm -f "$block_tmp"; return 0
  fi
  rm -f "$block_tmp" "$sysfile.new"; return 1
}
subhttps_merge_reload(){
  systemctl reload caddy >/dev/null 2>&1 || caddy reload --config "$(subhttps_merge_mainfile)" --adapter caddyfile >/dev/null 2>&1
}
subhttps_merge_verify(){
  # 本机回环验证订阅地址返回 200
  local ym_c="$1" token="$2" code=""
  command -v curl >/dev/null 2>&1 || return 1
  code=$(curl -sk --max-time 10 --resolve "$ym_c:443:127.0.0.1" -o /dev/null -w "%{http_code}" "https://$ym_c/$token/clmi.yaml" 2>/dev/null)
  [ "$code" = "200" ]
}
subhttps_merge_system_caddy(){
  # 编排：已合并（token 一致）直接成功；否则插入→全量校验→reload→回环验证；失败摘除恢复
  local ym_c="$1" token="" sysfile=""
  [ -n "$ym_c" ] || return 1
  token=$(subhttps_read "$HOME/agsbx/subtoken.log"); [ -n "$token" ] || return 1
  subhttps_merge_eligible "$ym_c" || return 1
  command -v caddy >/dev/null 2>&1 || return 1
  if subhttps_merge_active "$ym_c"; then return 0; fi
  sysfile=$(subhttps_merge_sysfile)
  [ -f "$sysfile.pre-sub" ] || cp -f "$sysfile" "$sysfile.pre-sub" 2>/dev/null || true
  subhttps_merge_insert "$ym_c" "$token" || return 1
  if ! caddy validate --config "$(subhttps_merge_mainfile)" --adapter caddyfile >/dev/null 2>&1; then
    subhttps_strip_merge_block >/dev/null 2>&1 || true; return 1
  fi
  if ! subhttps_merge_reload; then
    subhttps_strip_merge_block >/dev/null 2>&1 || true; return 1
  fi
  sleep 2
  if subhttps_merge_verify "$ym_c" "$token"; then return 0; fi
  subhttps_strip_merge_block >/dev/null 2>&1 || true
  subhttps_merge_reload >/dev/null 2>&1 || true
  return 1
}
subhttps_unmerge_system_caddy(){
  # 降级/del 时摘除合并块并 reload；没摘到东西就不 reload
  if subhttps_strip_merge_block; then subhttps_merge_reload || true; fi
  return 0
}
# subhttps_write_snippets: 为用户自有 Nginx/Caddy 生成配置片段（脚本不能绑 443 时手动加）
subhttps_write_snippets(){
  local ym_c="$1" token="" _webroot=""
  [ -n "$ym_c" ] || return 1
  token=$(subhttps_read "$HOME/agsbx/subtoken.log")
  _webroot="${webroot:-/var/www/html}"
  mkdir -p "$HOME/agsbx" 2>/dev/null || true
  # Caddy 片段
  {
    echo "# 加到你现有 Caddyfile 的 $ym_c 站点块内（handle 顺序：订阅优先，博客兜底）"
    if [ -n "$token" ]; then
      echo "handle_path /$token/* {"
      echo "  root * \"$HOME/websbx\""
      echo "  file_server"
      echo "}"
    fi
    echo "# 博客（已由 deploy_camouflage_blog 部署到 $_webroot）："
    echo "# root * $_webroot"
    echo "# file_server"
  } > "$HOME/agsbx/caddy-snippet.txt" 2>/dev/null || true
  # Nginx 片段
  {
    echo "# 加到你现有 nginx 的 server { listen 443 ssl; server_name $ym_c; } 块内"
    echo "# 注意：location 顺序 matters，订阅路径优先"
    if [ -n "$token" ]; then
      echo "location ^~ /$token/ {"
      echo "  alias $HOME/websbx/;"
      echo "  # 订阅文件：$token/clmi.yaml 等"
      echo "}"
    fi
    echo "# 博客根目录（已部署到 $_webroot）："
    echo "# location / {"
    echo "#   root $_webroot;"
    echo "#   index index.html;"
    echo "# }"
    echo "#"
    echo "# HTTP（80 端口）只保留 ACME 验证 + 跳转 HTTPS："
    echo "# server {"
    echo "#   listen 80; server_name $ym_c;"
    echo "#   location ^~ /.well-known/acme-challenge/ { root $_webroot; }"
    echo "#   location / { return 301 https://\$host\$request_uri; }"
    echo "# }"
  } > "$HOME/agsbx/nginx-snippet.txt" 2>/dev/null || true
  echo "配置片段已生成：$HOME/agsbx/caddy-snippet.txt / $HOME/agsbx/nginx-snippet.txt"
  return 0
}
subhttps_cert_hash(){
  sha256sum "$HOME/agsbx/cert/cert.crt" 2>/dev/null | awk '{print $1}'
}
subhttps_start_caddy(){
  local ym_c="$1" cur="" old=""
  if subhttps_caddy_running; then
    cur=$(subhttps_cert_hash)
    old=$(subhttps_read "$HOME/agsbx/subhttps.cert.hash")
    if [ -n "$cur" ] && [ "$cur" = "$old" ]; then return 0; fi
    subhttps_stop_caddy
  fi
  subhttps_write_conf "$ym_c" || return 1
  command -v caddy >/dev/null 2>&1 || return 1
  nohup caddy run --config "$HOME/agsbx/Caddyfile.sub" --adapter caddyfile > "$HOME/agsbx/subhttps.log" 2>&1 &
  echo $! > "$HOME/agsbx/subhttps.pid" 2>/dev/null || true
  sleep 2
  if subhttps_caddy_running; then
    cur=$(subhttps_cert_hash); [ -n "$cur" ] && echo "$cur" > "$HOME/agsbx/subhttps.cert.hash" 2>/dev/null || true
    return 0
  fi
  rm -f "$HOME/agsbx/subhttps.pid" 2>/dev/null || true
  return 1
}
subhttps_stop_caddy(){
  local pid=""
  if [ -f "$HOME/agsbx/subhttps.pid" ]; then
    pid=$(subhttps_read "$HOME/agsbx/subhttps.pid")
    case "$pid" in ''|*[!0-9]*) ;; *) kill "$pid" 2>/dev/null || true; sleep 1; kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true;; esac
    rm -f "$HOME/agsbx/subhttps.pid" "$HOME/agsbx/subhttps.cert.hash" 2>/dev/null || true
  fi
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -f "Caddyfile.sub" 2>/dev/null | while IFS= read -r p || [ -n "$p" ]; do
      case "$p" in ''|*[!0-9]*) continue;; esac
      kill "$p" 2>/dev/null || true
    done
  fi
  return 0
}
subhttps_stop_websbx(){
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -f "websbx" 2>/dev/null | while IFS= read -r p || [ -n "$p" ]; do
      case "$p" in ''|*[!0-9]*) continue;; esac
      kill "$p" 2>/dev/null || true
    done
  fi
  if command -v crontab >/dev/null 2>&1; then
    local tmp=""; tmp=$(mktemp 2>/dev/null) || return 0
    crontab -l 2>/dev/null | grep -v "websbx" > "$tmp" 2>/dev/null || true
    crontab "$tmp" 2>/dev/null || true
    rm -f "$tmp" 2>/dev/null || true
  fi
  return 0
}
subhttps_cron_install(){
  command -v crontab >/dev/null 2>&1 || return 0
  local tmp=""; tmp=$(mktemp 2>/dev/null) || return 0
  crontab -l 2>/dev/null | grep -v "argosbx-subhttps" > "$tmp" 2>/dev/null || true
  printf '@reboot sleep 10 && bash "$HOME/bin/agsbx" subhttpsync >/dev/null 2>&1  # argosbx-subhttps\n' >> "$tmp"
  crontab "$tmp" 2>/dev/null || true
  rm -f "$tmp" 2>/dev/null || true
  return 0
}
subhttps_cron_remove(){
  command -v crontab >/dev/null 2>&1 || return 0
  local tmp=""; tmp=$(mktemp 2>/dev/null) || return 0
  crontab -l 2>/dev/null | grep -v "argosbx-subhttps" > "$tmp" 2>/dev/null || true
  crontab "$tmp" 2>/dev/null || true
  rm -f "$tmp" 2>/dev/null || true
  return 0
}
subhttps_ufw_active(){
  if type ufw_is_active >/dev/null 2>&1; then ufw_is_active; return; fi
  command -v ufw >/dev/null 2>&1 || return 1
  ufw status 2>/dev/null | grep -q "Status: active"
}
# Multi-backend helpers for 443/subport. Markers are per backend:
# ufw keeps the old names (subhttps.443, subhttps.subport) for
# backward compat, firewalld uses subhttps.firewalld.*. When the
# firewall module is loaded, backends come from fw_active_backends;
# when this module is tested alone, fall back to the ufw check only,
# so the old sub-https tests (mock ufw, no firewall-cmd) still pass.
subhttps_fw_backends(){
  if type fw_active_backends >/dev/null 2>&1; then fw_active_backends; return; fi
  if subhttps_ufw_active; then echo "ufw"; fi
}
subhttps_fw_marker(){
  local kind="$1" backend="$2"
  case "$backend" in firewalld) echo "$HOME/agsbx/subhttps.firewalld.$kind";; *) echo "$HOME/agsbx/subhttps.$kind";; esac
}
subhttps_fw_zone(){
  local z=""; if type fw_firewalld_zone >/dev/null 2>&1; then fw_firewalld_zone; return; fi; z=$(firewall-cmd --get-default-zone 2>/dev/null | tr -d ' \t\r\n'); [ -n "$z" ] || z="public"; echo "$z"
}
subhttps_fw_allow(){
  local backend="$1" rule="$2"
  case "$backend" in
    ufw) ufw allow "$rule" >/dev/null 2>&1;;
    firewalld) firewall-cmd --permanent --zone="$(subhttps_fw_zone)" --add-port="$rule" >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1;;
  esac
}
subhttps_fw_delete(){
  local backend="$1" rule="$2"
  case "$backend" in
    ufw) ufw --force delete allow "$rule" >/dev/null 2>&1;;
    firewalld) firewall-cmd --permanent --zone="$(subhttps_fw_zone)" --remove-port="$rule" >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1;;
  esac
}
subhttps_fw_backend_cmd(){
  case "$1" in ufw) command -v ufw >/dev/null 2>&1;; firewalld) command -v firewall-cmd >/dev/null 2>&1;; esac
}
subhttps_manage_443(){
  local mode="$1" backend="" marker=""
  # https-merged 与 https 同等对待（443 保持放行）
  if [ "$mode" = "https-merged" ]; then mode="https"; fi
  if [ "$mode" = "https" ]; then
    if [ -z "$(subhttps_fw_backends)" ]; then
      echo "ufw/firewalld 未运行，https 订阅的 443/tcp 未自动放行，开启后运行 agsbx fwsync 或 subhttpsync 重新同步"
      return 0
    fi
    for backend in $(subhttps_fw_backends); do
      marker=$(subhttps_fw_marker 443 "$backend")
      if [ -f "$marker" ]; then continue; fi
      if subhttps_fw_allow "$backend" "443/tcp"; then echo "443/tcp" > "$marker" 2>/dev/null || true; else echo "$backend 放行 443/tcp 失败（已忽略）"; fi
    done
  else
    for backend in ufw firewalld; do
      marker=$(subhttps_fw_marker 443 "$backend")
      if [ ! -f "$marker" ]; then continue; fi
      if subhttps_fw_backend_cmd "$backend"; then
        if subhttps_fw_delete "$backend" "443/tcp"; then rm -f "$marker" 2>/dev/null || true; else echo "$backend 删除 443/tcp 失败（已忽略，下次同步重试）"; fi
      else
        rm -f "$marker" 2>/dev/null || true
      fi
    done
  fi
  return 0
}
subhttps_manage_subport(){
  local mode="$1" subport="" desired="" backend="" marker="" old=""
  # https-merged 与 https 同等对待（websbx 已停，订阅端口保持关闭）
  if [ "$mode" = "https-merged" ]; then mode="https"; fi
  # HTTPS or no subscription: websbx is stopped (or never started),
  # so any previously opened subscription port must go, not stay
  # open for a server that no longer listens. This branch runs
  # before the token check on purpose, so del also cleans it up.
  # Delete from both backends regardless of active status: a stored
  # rule would become active again when that backend is enabled.
  if [ "$mode" = "https" ] || [ -z "$(subhttps_read "$HOME/agsbx/subtoken.log")" ]; then
    for backend in ufw firewalld; do
      marker=$(subhttps_fw_marker subport "$backend")
      if [ ! -f "$marker" ]; then continue; fi
      old=$(subhttps_read "$marker")
      if [ -z "$old" ]; then rm -f "$marker" 2>/dev/null || true; continue; fi
      if subhttps_fw_backend_cmd "$backend"; then
        if subhttps_fw_delete "$backend" "$old"; then rm -f "$marker" 2>/dev/null || true; else echo "$backend 删除订阅端口失败（已忽略，下次同步重试）"; fi
      else
        rm -f "$marker" 2>/dev/null || true
      fi
    done
    return 0
  fi
  subport=$(subhttps_read "$HOME/agsbx/subport.log")
  case "$subport" in ''|*[!0-9]*) return 0;; esac
  if [ "$subport" -lt 1 ] 2>/dev/null || [ "$subport" -gt 65535 ] 2>/dev/null; then return 0; fi
  desired="$subport/tcp"
  if [ -z "$(subhttps_fw_backends)" ]; then
    echo "ufw/firewalld 未运行，订阅端口 $desired 未自动放行，开启后运行 agsbx fwsync 或 subhttpsync 重新同步"
    return 0
  fi
  for backend in $(subhttps_fw_backends); do
    marker=$(subhttps_fw_marker subport "$backend")
    old=""; if [ -f "$marker" ]; then old=$(subhttps_read "$marker"); fi
    if [ "$old" = "$desired" ]; then continue; fi
    if [ -n "$old" ] && subhttps_fw_backend_cmd "$backend"; then
      subhttps_fw_delete "$backend" "$old" >/dev/null 2>&1 || echo "$backend 删除旧订阅端口失败（已忽略）：$old"
      rm -f "$marker" 2>/dev/null || true
    fi
    if subhttps_fw_allow "$backend" "$desired"; then echo "$desired" > "$marker" 2>/dev/null || true; else echo "$backend 放行订阅端口失败（已忽略）"; fi
  done
  return 0
}
sub_https_sync(){
  local token="" ym_c="" mode=""
  token=$(subhttps_read "$HOME/agsbx/subtoken.log")
  if [ -z "$token" ]; then return 0; fi
  ym_c=$(subhttps_read "$HOME/agsbx/ym")
  mode=$(subhttps_decide_mode)
  if [ "$mode" = "https" ]; then
    # 443 被我们自己的证书流程 Caddy 占用时：自动合并订阅配置进系统 Caddyfile
    if subhttps_merge_system_caddy "$ym_c"; then
      subhttps_stop_websbx
      subhttps_cron_install
      subhttps_manage_443 "https"
      subhttps_manage_subport "https"
      echo "https-merged" > "$HOME/agsbx/subhttps.mode" 2>/dev/null || true
      echo "订阅已切换为 https 域名订阅（已自动合并到系统 Caddy）：https://$ym_c/$token/"
      return 0
    fi
    if subhttps_start_caddy "$ym_c"; then
      subhttps_stop_websbx
      subhttps_cron_install
      subhttps_manage_443 "https"
      subhttps_manage_subport "https"
      echo "https" > "$HOME/agsbx/subhttps.mode" 2>/dev/null || true
      echo "订阅已切换为 https 域名订阅：https://$ym_c/$token/"
      subhttps_write_snippets "$ym_c" || true
      return 0
    fi
    echo "Caddy 启动失败（可能 443 已被你自己的 Nginx/Caddy 占用），回退 http 域名订阅"
    subhttps_write_snippets "$ym_c" || true
    echo "如需在自有 Web 服务器上启用 https 订阅，请按 $HOME/agsbx/caddy-snippet.txt 或 nginx-snippet.txt 手动配置后重载"
    mode="http-domain"
  fi
  subhttps_unmerge_system_caddy
  subhttps_stop_caddy
  subhttps_cron_remove
  subhttps_manage_443 "$mode"
  subhttps_manage_subport "$mode"
  echo "$mode" > "$HOME/agsbx/subhttps.mode" 2>/dev/null || true
  if [ "$mode" = "http-domain" ]; then echo "订阅为 http 域名订阅（未满足 https 条件，见上文原因）"; else echo "订阅为 http IP 订阅"; fi
  return 0
}
sub_https_stop(){
  subhttps_unmerge_system_caddy
  subhttps_stop_caddy
  subhttps_cron_remove
  subhttps_manage_443 "http-ip"
  subhttps_manage_subport "https"
  rm -f "$HOME/agsbx/subhttps.mode" "$HOME/agsbx/Caddyfile.sub" "$HOME/agsbx/subhttps.pid" "$HOME/agsbx/subhttps.cert.hash" "$HOME/agsbx/subhttps.log" "$HOME/agsbx/subhttps.443" "$HOME/agsbx/subhttps.subport" "$HOME/agsbx/subhttps.firewalld.443" "$HOME/agsbx/subhttps.firewalld.subport" 2>/dev/null || true
  return 0
}
sub_https_display(){
  local mode="" token="" subport="" subip="" ym_c="" https_ok=0
  mode=$(subhttps_read "$HOME/agsbx/subhttps.mode")
  token=$(subhttps_read "$HOME/agsbx/subtoken.log")
  subport=$(subhttps_read "$HOME/agsbx/subport.log")
  subip=$(subhttps_read "$HOME/agsbx/server_ip.log")
  ym_c=$(subhttps_read "$HOME/agsbx/ym")
  if [ -z "$token" ]; then return 0; fi
  case "$mode" in https|https-merged) [ -n "$ym_c" ] && https_ok=1;; esac
  if [ "$https_ok" = "1" ]; then
    if [ "$mode" = "https" ]; then
      subhttps_caddy_running || https_ok=0
    else
      subhttps_merge_serving "$ym_c" || https_ok=0
    fi
    if [ "$https_ok" = "0" ]; then
      if [ -n "$subport" ]; then mode="http-domain"; else mode="http-ip"; fi
    fi
  fi
  if [ "$https_ok" = "1" ] && [ -n "$ym_c" ]; then
    echo "**********************************************************"
    echo "Clash/Mihomo https 域名订阅地址：https://$ym_c/$token/clmi.yaml"
    echo "Sing-box https 域名订阅地址：https://$ym_c/$token/sbox.json"
    echo "聚合协议 https 域名订阅地址：https://$ym_c/$token/jhsub.txt"
    echo "**********************************************************"
    return 0
  fi
  if [ "$mode" = "http-domain" ] && [ -n "$ym_c" ] && [ -n "$subport" ]; then
    echo "**********************************************************"
    echo "Clash/Mihomo域名订阅地址：http://$ym_c:$subport/$token/clmi.yaml"
    echo "Sing-box域名订阅地址：http://$ym_c:$subport/$token/sbox.json"
    echo "聚合协议域名订阅地址：http://$ym_c:$subport/$token/jhsub.txt"
    echo "**********************************************************"
    return 0
  fi
  if [ -s "$HOME/agsbx/subport.log" ] && [ -n "$subport" ] && [ -n "$subip" ]; then
    if ps -ef 2>/dev/null | grep "$subport" | grep -v grep >/dev/null; then
      echo "**********************************************************"
      echo "Clash/Mihomo本地IP订阅地址：http://$subip:$subport/$token/clmi.yaml"
      echo "Sing-box本地IP订阅地址：http://$subip:$subport/$token/sbox.json"
      echo "聚合协议本地IP订阅地址：http://$subip:$subport/$token/jhsub.txt"
      echo "**********************************************************"
    fi
  fi
  return 0
}
command -v register_hook >/dev/null 2>&1 && {
  register_hook post_start sub_https_sync
  register_hook on_uninstall sub_https_stop
}
