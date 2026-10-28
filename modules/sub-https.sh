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
  if ! subhttps_mem_ok && ! subhttps_caddy_running; then echo "http-domain"; return; fi
  if ! command -v caddy >/dev/null 2>&1 && ! subhttps_caddy_running; then echo "http-domain"; return; fi
  echo "https"
}
subhttps_write_conf(){
  local ym_c="$1"
  [ -n "$ym_c" ] || return 1
  mkdir -p "$HOME/agsbx" 2>/dev/null || true
  {
    echo "{"
    echo "  admin off"
    echo "}"
    echo "https://$ym_c {"
    echo "  tls \"$HOME/agsbx/cert/cert.crt\" \"$HOME/agsbx/cert/private.key\""
    echo "  root * \"$HOME/websbx\""
    echo "  file_server"
    echo "}"
  } > "$HOME/agsbx/Caddyfile.sub" 2>/dev/null || return 1
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
    if subhttps_start_caddy "$ym_c"; then
      subhttps_stop_websbx
      subhttps_cron_install
      subhttps_manage_443 "https"
      subhttps_manage_subport "https"
      echo "https" > "$HOME/agsbx/subhttps.mode" 2>/dev/null || true
      echo "订阅已切换为 https 域名订阅：https://$ym_c/$token/"
      return 0
    fi
    echo "Caddy 启动失败（可能 443 已被占用），回退 http 域名订阅"
    mode="http-domain"
  fi
  subhttps_stop_caddy
  subhttps_cron_remove
  subhttps_manage_443 "$mode"
  subhttps_manage_subport "$mode"
  echo "$mode" > "$HOME/agsbx/subhttps.mode" 2>/dev/null || true
  if [ "$mode" = "http-domain" ]; then echo "订阅为 http 域名订阅（未满足 https 条件，见上文原因）"; else echo "订阅为 http IP 订阅"; fi
  return 0
}
sub_https_stop(){
  subhttps_stop_caddy
  subhttps_cron_remove
  subhttps_manage_443 "http-ip"
  subhttps_manage_subport "https"
  rm -f "$HOME/agsbx/subhttps.mode" "$HOME/agsbx/Caddyfile.sub" "$HOME/agsbx/subhttps.pid" "$HOME/agsbx/subhttps.cert.hash" "$HOME/agsbx/subhttps.log" "$HOME/agsbx/subhttps.443" "$HOME/agsbx/subhttps.subport" "$HOME/agsbx/subhttps.firewalld.443" "$HOME/agsbx/subhttps.firewalld.subport" 2>/dev/null || true
  return 0
}
sub_https_display(){
  local mode="" token="" subport="" subip="" ym_c=""
  mode=$(subhttps_read "$HOME/agsbx/subhttps.mode")
  token=$(subhttps_read "$HOME/agsbx/subtoken.log")
  subport=$(subhttps_read "$HOME/agsbx/subport.log")
  subip=$(subhttps_read "$HOME/agsbx/server_ip.log")
  ym_c=$(subhttps_read "$HOME/agsbx/ym")
  if [ -z "$token" ]; then return 0; fi
  if [ "$mode" = "https" ] && [ -n "$ym_c" ]; then
    if ! subhttps_caddy_running; then
      if [ -n "$ym_c" ] && [ -n "$subport" ]; then mode="http-domain"; else mode="http-ip"; fi
    fi
  fi
  if [ "$mode" = "https" ] && [ -n "$ym_c" ]; then
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
