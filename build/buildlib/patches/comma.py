"""Other protocols comma multi-instance. Moved verbatim from main() in build/build.py."""
from ..util import read, replace


def apply(t, ctx):
    vlpt_comma = ctx["vlpt_comma"]
    vlpt_more_xray = ctx["vlpt_more_xray"]
    # --- other protocols comma multi-instance (private): same comma
    # semantics as vlpt, for every other protocol. Comma expansion
    # runs with vlpt-comma, before the port exports, so sh.txt still
    # shows the original comma command. Install loops are inserted
    # at the end of installxray / installsb / each xrsb* function,
    # display loops before the subscription lists (which are extended
    # below with the *_more functions). vars.env still carries
    # the internally generated *_more lists for `add`; the top list
    # and bashrc recovery line do NOT (same as vlpt_more);
    # ufw/firewalld already cover extra instances via the tag scan in
    # modules/ufw.sh, and egress aliases gain protoN branches.
    # Top list deliberately does NOT gain *_more any more (same as
    # vlpt_more): *_more are internal only, set by proto-comma
    # expansion. The sh.txt save loop runs before that expansion,
    # so it only ever sees the original comma command anyway;
    # vars_save (modules/vars.sh) still carries the internally
    # generated *_more lists for `add`.
    proto_comma = read("modules/proto-comma.sh")
    t = replace(t, 'fi\n' + vlpt_comma + 'export uuid=${uuid:-\'\'}\n',
                'fi\n' + vlpt_comma + proto_comma + 'export uuid=${uuid:-\'\'}\n', "proto-comma-expand", 1)
    _bs3 = chr(92)
    # Recovery line: NO *_more any more (same as vlpt_more).
    # The bashrc recovery line carries only the first-instance port;
    # extra instances are restored from the original comma command
    # in sh.txt, and vars.env still carries the internal *_more
    # lists for `add`.
    # Install loops.
    proto_more_xray = read("modules/proto-more-xray.sh")
    t = replace(t, 'else\n[ -n "$vlp" ] || vlp=vlptargo\nfi\n' + vlpt_more_xray + '}\n\ninstallsb(){',
                'else\n[ -n "$vlp" ] || vlp=vlptargo\nfi\n' + vlpt_more_xray + proto_more_xray + '}\n\ninstallsb(){', "proto-more-xray-block", 1)
    proto_more_sb = read("modules/proto-more-sb.sh")
    # installsb ends with the snpt block; insert after it, before the
    # closing brace of installsb (the snpt else branch + fi + blank
    # line + closing brace, followed by xrsbhy2).
    t = replace(t, 'else\nsnp=snptargo\nfi\n}\n\nxrsbhy2(){',
                'else\nsnp=snptargo\nfi\n' + proto_more_sb + '}\n\nxrsbhy2(){', "proto-more-sb-block", 1)
    # Auto loops: insert each into its xrsb* function, after the first
    # instance, before the function's closing else/fi. The anchor is
    # the else branch that sets the recovery dummy for that protocol.
    proto_more_hy = read("modules/proto-more-hy.sh")
    t = replace(t, 'else\nhyp=hyptargo\nfi\n}',
                'else\nhyp=hyptargo\nfi\n' + proto_more_hy + '}', "proto-more-hy-block", 1)
    proto_more_vm = read("modules/proto-more-vm.sh")
    # xrsbvm's else branch is the first "else\nvmp=vmptargo" in the file
    # after xrsbvm definition; use the function-end pattern with the
    # following xrsbvmtls comment to anchor it uniquely.
    t = replace(t, 'else\nvmp=vmptargo\nfi\n}\n\n# Vmess-ws-tls',
                'else\nvmp=vmptargo\nfi\n' + proto_more_vm + '}\n\n# Vmess-ws-tls', "proto-more-vm-block", 1)
    proto_more_vmtls = read("modules/proto-more-vmtls.sh")
    t = replace(t, 'else\nvmt=vmtlsargo\nfi\n}',
                'else\nvmt=vmtlsargo\nfi\n' + proto_more_vmtls + '}', "proto-more-vmtls-block", 1)
    proto_more_so = read("modules/proto-more-so.sh")
    t = replace(t, 'else\nsop=soptargo\nfi\n}',
                'else\nsop=soptargo\nfi\n' + proto_more_so + '}', "proto-more-so-block", 1)
    # Display loops + subscription lists.
    proto_more_display = read("modules/proto-more-display.sh")
    t = replace(t, 'clvlpt_more_1(){\nfor _vlpt_more_i in $(vlpt_more_idx_list); do\necho "- ${sxname}vless-reality-vision-$_vlpt_more_i-$hostname"\ndone\n}\n',
                'clvlpt_more_1(){\nfor _vlpt_more_i in $(vlpt_more_idx_list); do\necho "- ${sxname}vless-reality-vision-$_vlpt_more_i-$hostname"\ndone\n}\n' + proto_more_display, "proto-more-display-block", 1)
    t = replace(t, 'sbxy="$(get_func sbvlpt; get_func sbvlpt_more; get_func sbsnpt; get_func sbsspt;',
                'sbxy="$(get_func sbvlpt; get_func sbvlpt_more; get_func sbsnpt; get_func sbsspt_more; get_func sbsspt; get_func sbanpt_more; get_func sbarpt_more; get_func sbvmpt_more; get_func sbvmtlspt_more; get_func sbhypt_more; get_func sbtupt_more; get_func sbnvpt_more;', "proto-more-sbxy", 1)
    t = replace(t, 'clxy="$(get_func clsnpt; get_func clwsencpt; get_func clxhencpt; get_func clxhreaencpt; get_func cludpxcpt; get_func clxcpt; get_func clvlpt; get_func clvlpt_more; get_func clsspt;',
                'clxy="$(get_func clsnpt; get_func clwsencpt; get_func clxhencpt; get_func clxhreaencpt; get_func cludpxcpt; get_func clxupt_more; get_func clxcpt_more; get_func clxcpt; get_func clvlpt; get_func clvlpt_more; get_func clsspt_more; get_func clsspt; get_func clanpt_more; get_func clvmpt_more; get_func clvmtlspt_more; get_func clhypt_more; get_func cltupt_more;', "proto-more-clxy", 1)
    t = replace(t, 'sbgz="$(get_func sbvlpt1; get_func sbvlpt_more_1; get_func sbsnpt1; get_func sbsspt1;',
                'sbgz="$(get_func sbvlpt1; get_func sbvlpt_more_1; get_func sbsnpt1; get_func sbsspt_more_1; get_func sbsspt1; get_func sbanpt_more_1; get_func sbarpt_more_1; get_func sbvmpt_more_1; get_func sbvmtlspt_more_1; get_func sbhypt_more_1; get_func sbtupt_more_1; get_func sbnvpt_more_1;', "proto-more-sbgz", 1)
    t = replace(t, 'clgz="$({ get_func clsnpt1; get_func clwsencpt1; get_func clxhencpt1; get_func clxhreaencpt1; get_func cludpxcpt1; get_func clxcpt1; get_func clvlpt1; get_func clvlpt_more_1; get_func clsspt1;',
                'clgz="$({ get_func clsnpt1; get_func clwsencpt1; get_func clxhencpt1; get_func clxhreaencpt1; get_func cludpxcpt1; get_func clxupt_more_1; get_func clxcpt_more_1; get_func clxcpt1; get_func clvlpt1; get_func clvlpt_more_1; get_func clsspt_more_1; get_func clsspt1; get_func clanpt_more_1; get_func clvmpt_more_1; get_func clvmtlspt_more_1; get_func clhypt_more_1; get_func cltupt_more_1;', "proto-more-clgz", 1)
    return t
