# ufw firewall sync (private module, main script only).
# Rule: only when ufw is already active. This module NEVER turns
# ufw on by itself, never opens SSH (22), cert ports (80/443) for
# nodes, or the Argo local port. Only node inbound ports are opened
# here, and only with the transport the inbound actually uses,
# so nothing is over-opened. The subscription port and the HTTPS
# 443 port are NOT node ports: they are managed separately by the
# sub-https module (subhttps.subport / subhttps.443 markers), because
# the subscription port is only known after the sub block runs and
# it changes with the subscription mode (HTTP: open the websbx port;
# HTTPS: close it, open 443 instead). ufw_apply_saved calls those
# managers (guarded, so this module alone still works) so that
# enabling ufw later and running ufwsync opens everything, not just
# the node ports:
#   tcp only: vlpt, xhpt, vxpt, vwpt, xcpt, nvpt, anpt, arpt, vmpt, vmtls
#   udp only: xupt, tupt, hypt
#   tcp+udp:  sspt, sopt
# Why xcpt is tcp only even though its display name says TCP/UDP:
# the direct inbound uses alpn h2/http/1.1 (TCP); the UDP variants in
# the display are CDN links, not the direct port. Opening UDP for it
# would be over-opening. Why xupt is udp only: its direct inbound
# uses alpn h3 only (QUIC/HTTP3). Why sspt/sopt are both: their
# inbounds listen on both (Xray socks has udp:true, sing-box
# shadowsocks/socks inbounds default to both when no network is set).
# State: $HOME/agsbx/ufw.rules, one "port/proto" per line, written
# by ufw_sync even when ufw is inactive, so a later `agsbx ufwsync`
# can apply it after the user enables ufw, and so `del` can delete
# exactly the rules this script opened, never the user's own rules.
# All failures are warnings only: a ufw failure must never abort
# an install or an uninstall.
ufw_is_active(){
  command -v ufw >/dev/null 2>&1 || return 1
  ufw status 2>/dev/null | grep -q "Status: active"
}
_ufw_port(){
  local v="$1" f="$2" p
  p="$v"
  case "$p" in ''|*[!0-9]*) p="";; esac
  if [ -z "$p" ] && [ -n "$f" ] && [ -f "$f" ]; then
    p=$(tr -d ' \t\r\n' < "$f" 2>/dev/null)
    case "$p" in ''|*[!0-9]*) p="";; esac
  fi
  if [ -n "$p" ] && [ "$p" -ge 1 ] 2>/dev/null && [ "$p" -le 65535 ] 2>/dev/null; then
    echo "$p"
  fi
}
_ufw_emit(){
  local proto_var="$1" proto_name="$2" port_var="$3" port_file="$4" protos="$5" p pr
  if [ "$proto_var" != "$proto_name" ]; then return 0; fi
  p=$(_ufw_port "$port_var" "$port_file")
  if [ -z "$p" ]; then return 0; fi
  for pr in $protos; do echo "$p/$pr"; done
}
ufw_desired_rules(){
  _ufw_emit "$vlp" vlpt "$port_vl_re" "$HOME/agsbx/port_vl_re" "tcp"
  _ufw_emit "$xhp" xhpt "$port_xh" "$HOME/agsbx/port_xh" "tcp"
  _ufw_emit "$vxp" vxpt "$port_vx" "$HOME/agsbx/port_vx" "tcp"
  _ufw_emit "$vwp" vwpt "$port_vw" "$HOME/agsbx/port_vw" "tcp"
  _ufw_emit "$xup" xupt "$port_xu" "$HOME/agsbx/port_xu" "udp"
  _ufw_emit "$xcp" xcpt "$port_xc" "$HOME/agsbx/port_xc" "tcp"
  _ufw_emit "$nvp" nvpt "$port_nv" "$HOME/agsbx/port_nv" "tcp"
  _ufw_emit "$tup" tupt "$port_tu" "$HOME/agsbx/port_tu" "udp"
  _ufw_emit "$anp" anpt "$port_an" "$HOME/agsbx/port_an" "tcp"
  _ufw_emit "$arp" arpt "$port_ar" "$HOME/agsbx/port_ar" "tcp"
  _ufw_emit "$ssp" sspt "$port_ss" "$HOME/agsbx/port_ss" "tcp udp"
  _ufw_emit "$hyp" hypt "$port_hy2" "$HOME/agsbx/port_hy2" "udp"
  _ufw_emit "$vmp" vmpt "$port_vm_ws" "$HOME/agsbx/port_vm_ws" "tcp"
  _ufw_emit "$vmt" vmtls "$port_vm_tls" "$HOME/agsbx/port_vm_tls" "tcp"
  _ufw_emit "$sop" sopt "$port_so" "$HOME/agsbx/port_so" "tcp udp"
}
_ufw_fallback_rules(){
  local spec f protos p pr
  for spec in "port_vl_re:tcp" "port_xh:tcp" "port_vx:tcp" "port_vw:tcp" "port_xu:udp" "port_xc:tcp" "port_nv:tcp" "port_tu:udp" "port_an:tcp" "port_ar:tcp" "port_ss:tcp udp" "port_hy2:udp" "port_vm_ws:tcp" "port_vm_tls:tcp" "port_so:tcp udp"; do
    f="${spec%%:*}"; protos="${spec#*:}"
    p=$(_ufw_port "" "$HOME/agsbx/$f")
    if [ -z "$p" ]; then continue; fi
    for pr in $protos; do echo "$p/$pr"; done
  done
}
ufw_sync(){
  local state="$HOME/agsbx/ufw.rules" tmp added deleted r
  mkdir -p "$HOME/agsbx" 2>/dev/null || true
  tmp="$state.tmp.$$"
  ufw_desired_rules | sort -u > "$tmp" 2>/dev/null || true
  if ! ufw_is_active; then
    mv "$tmp" "$state" 2>/dev/null || true
    echo "ufw 未开启，已记录节点端口规则，开启 ufw 后运行 agsbx ufwsync 重新同步"
    return 0
  fi
  added=0; deleted=0
  if [ -f "$state" ]; then
    while IFS= read -r r || [ -n "$r" ]; do
      case "$r" in '') continue;; esac
      if ! grep -qx "$r" "$tmp" 2>/dev/null; then
        if ufw --force delete allow "$r" >/dev/null 2>&1; then deleted=$((deleted + 1)); else echo "ufw 删除规则失败（已忽略）：$r"; fi
      fi
    done < "$state"
  fi
  while IFS= read -r r || [ -n "$r" ]; do
    case "$r" in '') continue;; esac
    if [ ! -f "$state" ] || ! grep -qx "$r" "$state" 2>/dev/null; then
      if ufw allow "$r" >/dev/null 2>&1; then added=$((added + 1)); else echo "ufw 放行失败（已忽略）：$r"; fi
    fi
  done < "$tmp"
  mv "$tmp" "$state" 2>/dev/null || true
  echo "ufw 已同步节点端口规则（新增 $added 条，删除 $deleted 条）"
  return 0
}
ufw_apply_saved(){
  local state="$HOME/agsbx/ufw.rules" n=0 r
  if [ ! -s "$state" ]; then
    echo "没有记录的 ufw 规则，请先安装一次"
    return 0
  fi
  if ! ufw_is_active; then
    echo "ufw 未开启，已记录的规则未放行，开启 ufw 后再次运行 agsbx ufwsync"
    return 0
  fi
  while IFS= read -r r || [ -n "$r" ]; do
    case "$r" in '') continue;; esac
    if ufw allow "$r" >/dev/null 2>&1; then n=$((n + 1)); else echo "ufw 放行失败（已忽略）：$r"; fi
  done < "$state"
  # Subscription ports, by current mode (guarded: this module is
  # also tested alone, without the sub-https module loaded).
  if type subhttps_manage_subport >/dev/null 2>&1 || type subhttps_manage_443 >/dev/null 2>&1; then
    local submode=""; submode=$(tr -d ' \t\r\n' < "$HOME/agsbx/subhttps.mode" 2>/dev/null); [ -n "$submode" ] || submode="http-ip"
    if type subhttps_manage_subport >/dev/null 2>&1; then subhttps_manage_subport "$submode"; fi
    if type subhttps_manage_443 >/dev/null 2>&1; then subhttps_manage_443 "$submode"; fi
  fi
  echo "ufw 已按记录放行 $n 条规则"
  return 0
}
ufw_cleanup(){
  local state="$HOME/agsbx/ufw.rules" r
  if [ -f "$state" ]; then
    if command -v ufw >/dev/null 2>&1; then
      while IFS= read -r r || [ -n "$r" ]; do
        case "$r" in '') continue;; esac
        ufw --force delete allow "$r" >/dev/null 2>&1 || true
      done < "$state"
    fi
    rm -f "$state"
    return 0
  fi
  if command -v ufw >/dev/null 2>&1; then
    _ufw_fallback_rules | sort -u | while IFS= read -r r || [ -n "$r" ]; do
      case "$r" in '') continue;; esac
      ufw --force delete allow "$r" >/dev/null 2>&1 || true
    done
  fi
  return 0
}
