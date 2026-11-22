# Incremental update state (private module).
# vars.env records the full variable set of the last successful install/rep,
# one shell-escaped assignment per line, chmod 600. It is NOT a substitute
# for sh.txt (which is display only); it is the merge source for `add` and `rep`.
# vars_merge: for `add` and `rep`, called at the very top of the script, before
# the sh.txt save loop and before protocol selection, so the merged set is
# what gets saved and what gets installed. It loads vars.env only for
# variables NOT already set on the command line, so explicit values win
# and unset values inherit. For `add` it inherits everything (protocol +
# non-protocol); for `rep` it inherits only non-protocol variables, keeping
# the reset semantics for protocols (explicitly listed protocols are the new
# set). To clear a non-protocol variable on rep, set it empty explicitly
# (e.g. egress_rules=); unset means inherit. Deleting a protocol is done
# via `rep` by simply not listing it, as before.
# vars_save: called after ins() in the main install flow only, so a failed
# install never overwrites the last good state, and list/upx/ups/res/del
# (which exit before ins) never touch it. Values are single-line (the
# generator already converts egress textareas to ';' separated lines),
# and are written with %q so special characters survive a round trip.
vars_merge(){
  local line _vn _cli_reym_set=0
  case "$1" in add|rep) ;; *) return 0;; esac
  [ -n "${reym+x}" ] && _cli_reym_set=1
  if [ ! -s "$HOME/agsbx/vars.env" ]; then
    if [ "$1" = "add" ]; then
      echo "增量更新失败：未找到上次安装的变量记录 $HOME/agsbx/vars.env，请先用完整命令安装，或用 rep 全量重置"
      exit 1
    fi
    return 0
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue;; esac
    _vn="${line%%=*}"
    case "$_vn" in *[!A-Za-z0-9_]*|'') continue;; esac
    # vlpt2 / vlpt_more removed: an old vars.env that still lists them
    # must not resurrect them into a merge (they are cleared anyway in
    # vlpt-comma.sh, but skipping here keeps add from re-saving them).
    case "$_vn" in vlpt2|vlpt_more) continue;; esac
    # rep: 只继承非协议变量，协议变量保持重置语义（显式写了哪些就装哪些）
    if [ "$1" = "rep" ]; then
      case "$_vn" in vlpt|vmpt|vmtls|vwpt|hypt|tupt|xhpt|vxpt|anpt|arpt|sspt|snpt|sopt|nvpt|xupt|xcpt|*_more) continue;; esac
    fi
    if [ -z "${!_vn+x}" ]; then eval "$line"; fi
  done < "$HOME/agsbx/vars.env"
  # rep/add 未显式传 reym= 时，若 vars.env 中 reym 缺失或为空，兜底复用上次探测落盘的 ym_vl_re（除非是早期默认 apple.com）
  if [ "$_cli_reym_set" = "0" ] && [ -z "${reym:-}" ] && [ -s "$HOME/agsbx/ym_vl_re" ]; then
    local _prev_reym
    _prev_reym=$(tr -d ' \t\r\n' < "$HOME/agsbx/ym_vl_re" 2>/dev/null || true)
    if [ -n "$_prev_reym" ] && [ "$_prev_reym" != "apple.com" ]; then
      reym="$_prev_reym"
    fi
  fi
  if [ "$1" = "rep" ]; then return 0; fi
  for v in vlpt vmpt vmtls vwpt hypt tupt xhpt vxpt anpt arpt sspt snpt sopt nvpt xupt xcpt; do
    [ -n "${!v+x}" ] && return 0
  done
  echo "增量更新失败：合并后没有任何协议变量，请在 add 命令前至少设置一个新增或修改的协议变量"
  exit 1
}
vars_save(){
  local f="$HOME/agsbx/vars.env" tmp
  tmp="$f.tmp.$$"
  : > "$tmp" 2>/dev/null || return 1
  for v in uuid vlpt vmpt vmpt_more vmtls vmtls_more vwpt vwpt_more hypt hypt_more tupt tupt_more xhpt xhpt_more vxpt vxpt_more anpt anpt_more arpt arpt_more sspt sspt_more snpt sopt sopt_more nvpt nvpt_more xupt xupt_more xcpt xcpt_more reym cdnym argo agn agk agqc warp name oap ym alns certmode certsrc caddy_email web_proxy vlpt_kernel egress_nodes egress_bind egress_rules cfip hyjpt ippz hostname sub subid subpt; do
    if [ -n "${!v+x}" ]; then printf '%s=%q\n' "$v" "${!v}" >> "$tmp"; fi
  done
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$f" 2>/dev/null || return 1
}

# 判定 Argosbx 是否已安装在当前系统（基于落盘配置、服务单元或运行进程）
agsbx_is_installed(){
  [ -s "$HOME/agsbx/vars.env" ] || [ -s "$HOME/agsbx/sh.txt" ] || \
  [ -f "$HOME/agsbx/xr.json" ] || [ -f "$HOME/agsbx/sb.json" ] || \
  agsbx_is_running
}

# 判定是否有 Argosbx 相关内核进程（Xray / Sing-box / Cloudflared）在运行中
agsbx_is_running(){
  find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null | grep -Eq 'agsbx/(s|x|c)' || \
  pgrep -f 'agsbx/(s|x|c)' >/dev/null 2>&1
}

# 判定当前运行是否属于协议安装/重置/增量配置流程（非只读子命令、非纯菜单查看）
_is_install_run(){
  if [ "$1" = "rep" ] || [ "$1" = "add" ]; then return 0; fi
  case "$1" in del|list|upx|ups|upa|res|up|update|certwatch|certrestart|ufwsync|fwsync|fwstatus|subhttpsync|check|backup|restore|audit|help|-h|--help) return 1 ;; esac
  if ! agsbx_is_installed; then return 0; fi
  if [ "$xcp" = yes ] || [ "$xup" = yes ] || [ "$nvp" = yes ] || [ "$vwp" = yes ] || [ "$sop" = yes ] || [ "$vxp" = yes ] || [ "$ssp" = yes ] || [ "$vlp" = yes ] || [ "$vmp" = yes ] || [ "$vmt" = yes ] || [ "$hyp" = yes ] || [ "$tup" = yes ] || [ "$xhp" = yes ] || [ "$anp" = yes ] || [ "$arp" = yes ]; then
    return 0
  fi
  return 1
}
command -v register_hook >/dev/null 2>&1 && {
  register_hook on_init vars_merge
  register_hook on_complete vars_save
} || true
