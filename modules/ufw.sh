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
#   tcp only: vlpt, vlpt2, xhpt, vxpt, vwpt, xcpt, nvpt, anpt, arpt, vmpt, vmtls
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
  local _f _n _p
  _ufw_emit "$vlp" vlpt "$port_vl_re" "$HOME/agsbx/port_vl_re" "tcp"
  _ufw_emit "$vlp2" vlpt2 "$port_vl_re2" "$HOME/agsbx/port_vl_re2" "tcp"
  if [ -n "$vlpt_more" ]; then
    local _mp="" _moldifs="$IFS"; IFS=','; for _mp in $vlpt_more; do _mp=$(printf '%s' "$_mp" | xargs 2>/dev/null || printf '%s' "$_mp"); case "$_mp" in ''|*[!0-9]*) ;; *) echo "$_mp/tcp";; esac; done; IFS="$_moldifs"
  fi
  # vlpt instances from a comma list may be random (empty item or
  # "random"): their ports are only in port files, not in vlpt_more,
  # so also emit every vlpt tag actually present in xr/sb.json
  # (N >= 2, including instance 2 when it came from vlpt_more).
  # sort -u in the callers dedupes against the emits above.
  for _f in "$HOME/agsbx"/port_vl_re[0-9]*; do
    [ -f "$_f" ] || continue
    case "$_f" in *port_vl_re) continue;; esac
    _n="${_f##*port_vl_re}"
    if grep -q "\"tag\":\"reality-vision-$_n\"" "$HOME/agsbx/xr.json" 2>/dev/null || grep -q "\"tag\": \"vl-reality-sb-$_n\"" "$HOME/agsbx/sb.json" 2>/dev/null; then
      _p=$(_ufw_port "" "$_f"); [ -n "$_p" ] && echo "$_p/tcp"
    fi
  done
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
  for spec in "port_vl_re:tcp" "port_vl_re2:tcp" "port_xh:tcp" "port_vx:tcp" "port_vw:tcp" "port_xu:udp" "port_xc:tcp" "port_nv:tcp" "port_tu:udp" "port_an:tcp" "port_ar:tcp" "port_ss:tcp udp" "port_hy2:udp" "port_vm_ws:tcp" "port_vm_tls:tcp" "port_so:tcp udp"; do
    f="${spec%%:*}"; protos="${spec#*:}"
    p=$(_ufw_port "" "$HOME/agsbx/$f")
    if [ -z "$p" ]; then continue; fi
    for pr in $protos; do echo "$p/$pr"; done
  done
  # vlpt more instances: port files port_vl_re3, port_vl_re4, ... are
  # not in the spec list above, so scan them here (callers sort -u).
  for f in "$HOME/agsbx"/port_vl_re[0-9]*; do
    [ -f "$f" ] || continue
    case "$f" in *port_vl_re|*port_vl_re2) continue;; esac
    p=$(_ufw_port "" "$f")
    [ -n "$p" ] && echo "$p/tcp"
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
# --- Layered firewall: ufw + firewalld auto, raw iptables/nft prompt ---
# Why layered: ufw and firewalld both have a clear active state and a
# safe per-port API, so they can be managed automatically. Raw
# iptables/nft have no single on/off switch (see fw_raw_blocking):
# the ruleset is the firewall, and inserting into it can break the
# user's ordering (APPEND after a final DROP never matches) and
# persistence (Debian netfilter-persistent, RHEL iptables service,
# Alpine rc-service all differ), plus Docker/fail2ban chains. So raw
# rules are detected and printed, never auto-inserted. Cloud security
# groups and panel firewalls (BT/CSF) live outside this VM and cannot
# be seen or changed from here at all, so they get a checklist only.
# Safety rules from the ufw module still hold for every backend:
# never turn a firewall on, never open 22/Argo-local ports, never
# delete a rule that is not in our own state file, failures warn only.
fw_firewalld_active(){
  command -v firewall-cmd >/dev/null 2>&1 || return 1
  # Exact match on purpose: firewall-cmd --state prints "not running"
  # when stopped, and that string contains "running", so grep -q
  # "running" would wrongly report an inactive firewalld as active.
  [ "$(firewall-cmd --state 2>/dev/null)" = "running" ]
}
fw_firewalld_zone(){
  local z=""; z=$(firewall-cmd --get-default-zone 2>/dev/null | tr -d ' \t\r\n'); [ -n "$z" ] || z="public"; echo "$z"
}
# Prints one active backend per line: ufw, firewalld, or both.
# Both active is unusual (they fight over the same nft/iptables
# backend); we apply to both so the node works either way, and warn.
fw_active_backends(){
  if ufw_is_active; then echo "ufw"; fi
  if fw_firewalld_active; then echo "firewalld"; fi
}
fw_allow_rule(){
  local backend="$1" rule="$2"
  case "$backend" in
    ufw) ufw allow "$rule" >/dev/null 2>&1;;
    firewalld) firewall-cmd --permanent --zone="$(fw_firewalld_zone)" --add-port="$rule" >/dev/null 2>&1;;
  esac
}
fw_delete_rule(){
  local backend="$1" rule="$2"
  case "$backend" in
    ufw) ufw --force delete allow "$rule" >/dev/null 2>&1;;
    firewalld) firewall-cmd --permanent --zone="$(fw_firewalld_zone)" --remove-port="$rule" >/dev/null 2>&1;;
  esac
}
fw_reload_backend(){
  case "$1" in firewalld) firewall-cmd --reload >/dev/null 2>&1 || true;; esac
}
# firewalld mirror of ufw_sync, same diff semantics, state file
# $HOME/agsbx/firewalld.rules. Reload once at the end, not per port.
firewalld_sync(){
  local state="$HOME/agsbx/firewalld.rules" tmp added deleted r
  mkdir -p "$HOME/agsbx" 2>/dev/null || true
  tmp="$state.tmp.$$"
  ufw_desired_rules | sort -u > "$tmp" 2>/dev/null || true
  if ! fw_firewalld_active; then
    mv "$tmp" "$state" 2>/dev/null || true
    echo "firewalld 未运行，已记录节点端口规则，启动 firewalld 后运行 agsbx fwsync 重新同步"
    return 0
  fi
  added=0; deleted=0
  if [ -f "$state" ]; then
    while IFS= read -r r || [ -n "$r" ]; do
      case "$r" in '') continue;; esac
      if ! grep -qx "$r" "$tmp" 2>/dev/null; then
        if fw_delete_rule firewalld "$r"; then deleted=$((deleted + 1)); else echo "firewalld 删除规则失败（已忽略）：$r"; fi
      fi
    done < "$state"
  fi
  while IFS= read -r r || [ -n "$r" ]; do
    case "$r" in '') continue;; esac
    if [ ! -f "$state" ] || ! grep -qx "$r" "$state" 2>/dev/null; then
      if fw_allow_rule firewalld "$r"; then added=$((added + 1)); else echo "firewalld 放行失败（已忽略）：$r"; fi
    fi
  done < "$tmp"
  fw_reload_backend firewalld
  mv "$tmp" "$state" 2>/dev/null || true
  echo "firewalld 已同步节点端口规则（新增 $added 条，删除 $deleted 条）"
  return 0
}
firewalld_apply_saved(){
  local state="$HOME/agsbx/firewalld.rules" n=0 r
  if [ ! -s "$state" ]; then echo "没有记录的 firewalld 规则，请先安装一次"; return 0; fi
  if ! fw_firewalld_active; then echo "firewalld 未运行，已记录的规则未放行，启动后再次运行 agsbx fwsync"; return 0; fi
  while IFS= read -r r || [ -n "$r" ]; do
    case "$r" in '') continue;; esac
    if fw_allow_rule firewalld "$r"; then n=$((n + 1)); else echo "firewalld 放行失败（已忽略）：$r"; fi
  done < "$state"
  fw_reload_backend firewalld
  if type subhttps_manage_subport >/dev/null 2>&1 || type subhttps_manage_443 >/dev/null 2>&1; then
    local submode=""; submode=$(tr -d ' \t\r\n' < "$HOME/agsbx/subhttps.mode" 2>/dev/null); [ -n "$submode" ] || submode="http-ip"
    if type subhttps_manage_subport >/dev/null 2>&1; then subhttps_manage_subport "$submode"; fi
    if type subhttps_manage_443 >/dev/null 2>&1; then subhttps_manage_443 "$submode"; fi
  fi
  echo "firewalld 已按记录放行 $n 条规则"
  return 0
}
firewalld_cleanup(){
  local state="$HOME/agsbx/firewalld.rules" r
  if [ -f "$state" ]; then
    if command -v firewall-cmd >/dev/null 2>&1; then
      while IFS= read -r r || [ -n "$r" ]; do
        case "$r" in '') continue;; esac
        fw_delete_rule firewalld "$r" || true
      done < "$state"
      fw_reload_backend firewalld
    fi
    rm -f "$state"
    return 0
  fi
  if command -v firewall-cmd >/dev/null 2>&1; then
    _ufw_fallback_rules | sort -u | while IFS= read -r r || [ -n "$r" ]; do
      case "$r" in '') continue;; esac
      fw_delete_rule firewalld "$r" || true
    done
    fw_reload_backend firewalld
  fi
  return 0
}
# Raw iptables/nft blocking detection. Returns 0 when a blocking
# ruleset is present. It is per-chain, not "is iptables installed":
# an empty ruleset with policy ACCEPT is not blocking, and Docker /
# fail2ban chains outside INPUT do not count, because only INPUT
# decides whether a node port is reachable from outside.
fw_raw_blocking(){
  local out=""
  if command -v iptables >/dev/null 2>&1; then
    out=$(iptables -S INPUT 2>/dev/null)
    case "$out" in
      "-P INPUT DROP"*|"-P INPUT REJECT"*) return 0;;
    esac
    if echo "$out" | grep -Eq -- "-j (DROP|REJECT)( |$)"; then return 0; fi
  fi
  if command -v nft >/dev/null 2>&1; then
    out=$(nft list ruleset 2>/dev/null)
    if echo "$out" | grep -Eq "hook input.*policy drop|hook input.*policy reject"; then return 0; fi
  fi
  return 1
}
# Ready-to-paste raw rules, for the prompt path only. INSERT, not
# APPEND: a rule appended after a final DROP never matches.
fw_print_raw_prompt(){
  local r=""
  echo "检测到裸 iptables/nft 在拦 INPUT（无 ufw/firewalld 在跑），脚本未自动插规则，请手动放行："
  if [ -f "$HOME/agsbx/ufw.rules" ]; then
    while IFS= read -r r || [ -n "$r" ]; do
      case "$r" in '') continue;; esac
      echo "  iptables -I INPUT -p ${r#*/} --dport ${r%/*} -j ACCEPT"
    done < "$HOME/agsbx/ufw.rules"
  else
    ufw_desired_rules | sort -u | while IFS= read -r r || [ -n "$r" ]; do
      case "$r" in '') continue;; esac
      echo "  iptables -I INPUT -p ${r#*/} --dport ${r%/*} -j ACCEPT"
    done
  fi
  echo "  持久化（按发行版二选一）：Debian/Ubuntu 用 netfilter-persistent save；RHEL 系用 service iptables save；Alpine 用 rc-service iptables save；nft 用 nft list ruleset > /etc/nftables.conf"
  return 0
}
fw_print_cloud_checklist(){
  echo "云厂商安全组 / 面板防火墙（宝塔、CSF 等）脚本无法自动放行，请在控制台手动放行以下节点端口："
  if [ -f "$HOME/agsbx/ufw.rules" ]; then
    while IFS= read -r r || [ -n "$r" ]; do case "$r" in '') continue;; esac; echo "  $r"; done < "$HOME/agsbx/ufw.rules"
  else
    ufw_desired_rules | sort -u | while IFS= read -r r || [ -n "$r" ]; do case "$r" in '') continue;; esac; echo "  $r"; done
  fi
  return 0
}
# Unified sync, called from the install flow instead of ufw_sync.
# ufw_sync itself is kept unchanged for backward compat and for the
# ufw-only tests; fw_sync is the layered entry point.
fw_sync(){
  local backends="" n=0 b=""
  backends=$(fw_active_backends)
  if [ -z "$backends" ]; then
    ufw_sync
    if fw_raw_blocking; then fw_print_raw_prompt; fi
    fw_print_cloud_checklist
    return 0
  fi
  for b in $backends; do n=$((n + 1)); done
  if [ "$n" -gt 1 ]; then echo "警告：ufw 与 firewalld 同时在运行，已对两者都同步，长期建议只留一个管理器"; fi
  if ufw_is_active; then ufw_sync; fi
  if fw_firewalld_active; then firewalld_sync; fi
  fw_print_cloud_checklist
  return 0
}
fw_apply_saved(){
  if ufw_is_active; then ufw_apply_saved; fi
  if fw_firewalld_active; then firewalld_apply_saved; fi
  if ! ufw_is_active && ! fw_firewalld_active; then
    echo "没有在运行的防火墙后端（ufw/firewalld），已记录的规则未放行"
    if fw_raw_blocking; then fw_print_raw_prompt; fi
    return 0
  fi
  return 0
}
fw_cleanup(){
  ufw_cleanup
  firewalld_cleanup
  return 0
}
fw_status(){
  local b=""
  echo "防火墙后端："
  if [ -z "$(fw_active_backends)" ]; then echo "  （无 ufw/firewalld 在运行）"; else for b in $(fw_active_backends); do echo "  $b 在运行"; done; fi
  echo "已记录节点端口："
  if [ -f "$HOME/agsbx/ufw.rules" ]; then while IFS= read -r b || [ -n "$b" ]; do case "$b" in '') continue;; esac; echo "  ufw: $b"; done < "$HOME/agsbx/ufw.rules"; fi
  if [ -f "$HOME/agsbx/firewalld.rules" ]; then while IFS= read -r b || [ -n "$b" ]; do case "$b" in '') continue;; esac; echo "  firewalld: $b"; done < "$HOME/agsbx/firewalld.rules"; fi
  if fw_raw_blocking; then echo "裸 iptables/nft：检测到 INPUT 在拦（见上文手动命令）"; else echo "裸 iptables/nft：未检测到 INPUT 拦截"; fi
  fw_print_cloud_checklist
  return 0
}
