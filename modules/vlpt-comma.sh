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
# vlpt2 / vlpt_more are NO LONGER user inputs (removed 2026-10-28:
# QUINN confirmed they were never used on another machine). They are
# cleared here unconditionally, before the comma expansion, so a
# command that still passes vlpt2= / vlpt_more= simply does nothing
# with them -- no second instance, no warning, no compatibility path.
# vlpt_more below is INTERNAL only, set by this expansion.
vlpt2=""; vlpt_more=""; vlp2=""
case "$vlpt" in *,*)
  _vlpt_comma_rest="${vlpt#*,}"
  vlpt="${vlpt%%,*}"
  if [ -z "$_vlpt_comma_rest" ]; then vlpt_more="random"; else vlpt_more="$_vlpt_comma_rest"; fi
  ;;
esac
