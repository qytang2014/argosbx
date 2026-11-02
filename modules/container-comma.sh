# container-comma.sh: 容器版逗号多实例解析
# 与主脚本 modules/proto-comma.sh 同语义：逗号数+1=实例数，空项=随机端口。
# 每个协议变量拆分为 itself（首项）+ <proto>_more（剩余项）。
# 容器内暂仅 vlpt 生成多 inbound，其余协议取首项（后续扩展）。

for _cc_var in vlpt xhpt vxpt vwpt xupt xcpt nvpt tupt anpt arpt sspt hypt vmpt vmtls sopt; do
  eval "${_cc_var}_more=\"\""
done
for _cc_var in vlpt xhpt vxpt vwpt xupt xcpt nvpt tupt anpt arpt sspt hypt vmpt vmtls sopt; do
  _cc_val=$(eval "printf '%s' \"\${$_cc_var:-}\"") 2>/dev/null || _cc_val=""
  case "$_cc_val" in *,*)
    _cc_rest="${_cc_val#*,}"
    _cc_first="${_cc_val%%,*}"
    if [ -z "$_cc_rest" ]; then _cc_rest="random"; fi
    # 空首项 → 随机端口
    if [ -z "$_cc_first" ]; then _cc_first=$(shuf -i 10000-65535 -n 1 2>/dev/null || echo 10001); fi
    eval "$_cc_var=\"\$_cc_first\""
    eval "${_cc_var}_more=\"\$_cc_rest\""
    ;;
  esac
done
unset _cc_var _cc_val _cc_rest _cc_first
