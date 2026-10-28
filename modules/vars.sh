# Incremental update state (private module).
# vars.env records the full variable set of the last successful install/rep,
# one shell-escaped assignment per line, chmod 600. It is NOT a substitute
# for sh.txt (which is display only); it is the merge source for `add`.
# vars_merge: only for `add`, called at the very top of the script, before
# the sh.txt save loop and before protocol selection, so the merged set is
# what gets saved and what gets installed. It loads vars.env only for
# variables NOT already set on the command line, so explicit values win
# and unset values inherit. It fails (exit 1) if vars.env is missing or
# the merged set selects no protocol, because proceeding would silently
# drop the old installation. Deleting a protocol is NOT done via `add`
# (unset means inherit); use `rep` for a full reset, as before.
# vars_save: called after ins() in the main install flow only, so a failed
# install never overwrites the last good state, and list/upx/ups/res/del
# (which exit before ins) never touch it. Values are single-line (the
# generator already converts egress textareas to ';' separated lines),
# and are written with %q so special characters survive a round trip.
vars_merge(){
  if [ "$1" != "add" ]; then return 0; fi
  if [ ! -s "$HOME/agsbx/vars.env" ]; then
    echo "增量更新失败：未找到上次安装的变量记录 $HOME/agsbx/vars.env，请先用完整命令安装，或用 rep 全量重置"
    exit 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue;; esac
    name="${line%%=*}"
    case "$name" in *[!A-Za-z0-9_]*|'') continue;; esac
    if [ -z "${!name+x}" ]; then eval "$line"; fi
  done < "$HOME/agsbx/vars.env"
  for v in vlpt vlpt2 vlpt_more vmpt vmtls vwpt hypt tupt xhpt vxpt anpt arpt sspt sopt nvpt xupt xcpt; do
    [ -n "${!v+x}" ] && return 0
  done
  echo "增量更新失败：合并后没有任何协议变量，请在 add 命令前至少设置一个新增或修改的协议变量"
  exit 1
}
vars_save(){
  local f="$HOME/agsbx/vars.env" tmp
  tmp="$f.tmp.$$"
  : > "$tmp" 2>/dev/null || return 1
  for v in uuid vlpt vlpt2 vlpt_more vmpt vmpt_more vmtls vmtls_more vwpt vwpt_more hypt hypt_more tupt tupt_more xhpt xhpt_more vxpt vxpt_more anpt anpt_more arpt arpt_more sspt sspt_more sopt sopt_more nvpt nvpt_more xupt xupt_more xcpt xcpt_more reym cdnym argo agn agk warp name oap ym alns certmode certsrc vlpt_kernel egress_nodes egress_bind egress_rules cfip hyjpt ippz sub subid subpt; do
    if [ -n "${!v+x}" ]; then printf '%s=%q\n' "$v" "${!v}" >> "$tmp"; fi
  done
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$f" 2>/dev/null || return 1
}
