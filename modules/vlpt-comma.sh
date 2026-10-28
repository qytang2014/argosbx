# vlpt comma list (private module, runs at top level, before exports).
# The generator now has only one vlpt field: its value is a comma list.
# Comma count + 1 = instance count, an empty item = a random port.
#   ""            -> 1 instance, random
#   "10001"       -> 1 instance, port 10001
#   ","           -> 2 instances, both random
#   "10001,"      -> instance 1 = 10001, instance 2 = random
#   ",10002"      -> instance 1 = random, instance 2 = 10002
#   "10001,10002" -> 2 instances, fixed ports
#   ",,"          -> 3 instances, all random
# This expansion turns a comma list into vlpt (first item) + vlpt_more
# (rest items) for the existing loop, so install/display/ufw/egress
# need no other change, and sh.txt (saved before this runs) still
# shows the original comma command. A trailing comma would otherwise
# vanish in vlpt_more ("" means "no extra instance"), so it becomes
# the sentinel "random", which the loop treats as a random port.
# Legacy vlpt2/vlpt_more are kept when vlpt has no comma; if vlpt has
# a comma AND legacy variables are also set, the comma list wins and
# legacy is cleared (with a warning), because instance 2 would
# otherwise be defined twice. The vlp2 flag is cleared too, so the
# old vlpt2 block cannot create a duplicate instance 2.
case "$vlpt" in *,*)
  if [ -n "$vlpt2" ] || [ -n "$vlpt_more" ]; then echo "vlpt 已用逗号分隔多实例，忽略旧的 vlpt2/vlpt_more"; vlpt2=""; vlpt_more=""; vlp2=""; fi
  _vlpt_comma_rest="${vlpt#*,}"
  vlpt="${vlpt%%,*}"
  if [ -z "$_vlpt_comma_rest" ]; then vlpt_more="random"; else vlpt_more="$_vlpt_comma_rest"; fi
  ;;
esac
