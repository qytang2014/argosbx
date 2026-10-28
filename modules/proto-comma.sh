# Other protocols comma list (private module, runs at top level, before exports).
# Same semantics as vlpt comma: comma count + 1 = instance count, an
# empty item = a random port. Each protocol variable is split into
# itself (first item) + <proto>_more (rest items). A trailing comma
# becomes the sentinel "random", because an empty _more string would
# mean "no extra instance" downstream. The loop modules for each
# protocol (proto-more-xray/sb/auto) consume the _more list.
# sh.txt is saved before this runs, so it still shows the original
# comma command; vars.env saves the expanded _more lists.
for _pc_var in xhpt vxpt vwpt xupt xcpt nvpt tupt anpt arpt sspt hypt vmpt vmtls sopt; do
  _pc_val=$(eval "printf '%s' \"\${$_pc_var:-}\"") 2>/dev/null || _pc_val=""
  case "$_pc_val" in *,*)
    _pc_rest="${_pc_val#*,}"
    _pc_first="${_pc_val%%,*}"
    if [ -z "$_pc_rest" ]; then _pc_rest="random"; fi
    eval "$_pc_var=\"\$_pc_first\""
    eval "${_pc_var}_more=\"\$_pc_rest\""
    ;;
  esac
done
unset _pc_var _pc_val _pc_rest _pc_first
