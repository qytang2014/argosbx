# rep-inherit.sh: rep 未带协议变量时，从 vars.env 继承当前协议
# 场景：用户只想更新脚本或改非协议变量（如 ym），不想重输所有协议。
# 显式传入了任一协议变量时不触发（保持 rep 的重置语义）。

if [ "$1" = "rep" ]; then
if [ -z "${vlpt+x}" ] && [ -z "${hypt+x}" ] && [ -z "${tupt+x}" ] && \
   [ -z "${xhpt+x}" ] && [ -z "${vxpt+x}" ] && [ -z "${vwpt+x}" ] && \
   [ -z "${xupt+x}" ] && [ -z "${xcpt+x}" ] && [ -z "${nvpt+x}" ] && \
   [ -z "${anpt+x}" ] && [ -z "${arpt+x}" ] && [ -z "${sspt+x}" ] && \
   [ -z "${vmpt+x}" ] && [ -z "${vmtls+x}" ] && [ -z "${sopt+x}" ]; then
  if [ -f "$HOME/agsbx/vars.env" ]; then
    while IFS= read -r _rl || [ -n "$_rl" ]; do
      case "$_rl" in ''|\#*) continue;; esac
      _rn="${_rl%%=*}"
      case "$_rn" in
        vlpt|hypt|tupt|xhpt|vxpt|vwpt|xupt|xcpt|nvpt|anpt|arpt|sspt|vmpt|vmtls|sopt)
          if [ -z "${!_rn+x}" ]; then eval "export $_rl" 2>/dev/null || true; fi;;
      esac
    done < "$HOME/agsbx/vars.env"
    unset _rl _rn
    echo "rep 未指定协议，已从现有配置继承"
  fi
fi
fi
