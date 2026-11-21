"""vmtls inbound insert, vlpt dual-support, vlpt loop, vlpt comma. Moved verbatim from main() in build/build.py."""
import sys
from ..util import read, replace


def apply(t, ctx):
    # --- vmess-ws-tls inbound (main): insert xrsbvmtls after xrsbvm ---
    vmtls_mod = read("modules/vmtls.sh")
    t = replace(t, "xrsbso(){\nif [ -n \"$sop\" ]; then",
                vmtls_mod + "xrsbso(){\nif [ -n \"$sop\" ]; then", "vmtls-inbound", 1)
    # Call it after xrsbvm in all three ins() branches (xrsbvm line
    # appears exactly 3 times there; xrsbvm is also defined once, but
    # the definition line is "xrsbvm(){" not "xrsbvm\n", so this is safe).
    n = t.count("xrsbvm\nxrsbso")
    if n != 3:
        print(f"BUILD FAIL: vmtls-call: expected 3 occurrence(s), found {n}", file=sys.stderr); sys.exit(1)
    t = t.replace("xrsbvm\nxrsbso", "xrsbvm\nxrsbvmtls\nxrsbso")
    t = replace(t, 'export agqc=\\"${agqc}\\" alns=\\"${alns}\\" ',
                'export agqc=\\"${agqc}\\" alns=\\"${alns}\\" ym=\\"${ym}\\" certmode=\\"${certmode}\\" certsrc=\\"${certsrc}\\" vlpt_kernel=\\"${vlpt_kernel}\\" egress_nodes=\\"${egress_nodes}\\" egress_bind=\\"${egress_bind}\\" egress_rules=\\"${egress_rules}\\" ', "recovery-line", 1)

    # --- vlpt dual-support (private): vlpt_kernel=auto/xray/sb ---
    # vlpt_on is computed at the top of ins(), before the kernel branches:
    #  explicit xray -> xray (old link kept, even if that forces dual kernels);
    #  explicit sb   -> sb;
    #  auto (default, incl. unset/invalid): xray if any xray-only protocol is
    #  selected (xray is installed anyway, so moving vlpt would save nothing
    #  and would break the link for no gain); sb if only sing-box protocols
    #  are selected (the migration case: old vlpt-on-xray + sing-box install
    #  becomes single sing-box, pbk/sid change, old link breaks by design);
    #  otherwise (vlpt alone or vlpt + auto protocols only) xray, preserving
    #  the current single-xray default. No backward-compat keep: unless
    #  vlpt_kernel=xray is explicitly set, an old install is migrated.
    vlpt_on = '''# vlpt dual-support: vlpt_kernel=auto (default) / xray / sb
# vlpt instances share vlpt_on (and vlpt_kernel): all instances land
# on the same kernel, distinguished by port and inbound tag only.
vlpt_on=""
if [ -n "$vlp" ]; then
  case "${vlpt_kernel:-auto}" in
    xray) vlpt_on="xray" ;;
    sb|singbox|sing-box) vlpt_on="sb" ;;
    *)
      if [ "$xhp" = yes ] || [ "$vxp" = yes ] || [ "$vwp" = yes ] || [ "$xup" = yes ] || [ "$xcp" = yes ]; then vlpt_on="xray";
      elif [ "$nvp" = yes ] || [ "$tup" = yes ] || [ "$anp" = yes ] || [ "$arp" = yes ] || [ "$ssp" = yes ]; then vlpt_on="sb";
      else vlpt_on="xray"; fi ;;
  esac
fi
'''
    t = replace(t, "ins(){\nif [ \"$nvp\" != yes ]",
                "ins(){\n" + vlpt_on + "if [ \"$nvp\" != yes ]", "vlpt-on-compute", 1)
    # --- auto-sni call (private): resolve the Reality SNI when neither
    # reym nor ym is set and a Reality protocol is being installed. Runs
    # once at the top of ins(), after vlpt_on is computed and before any
    # installxray/installsb branch. The guard is the trigger (reym/ym
    # empty + any Reality flag); auto_sni_resolve itself is idempotent
    # (returns 0 at once if ym_vl_re is already set), so rep/add never
    # re-detect. Failure aborts the install (exit 1).
    # This is a call insertion inside ins(), an upstream function, so it
    # is a new anchor (A); there is no hook point inside ins() to hang
    # it on (see build/ANCHORS.md).
    t = replace(t, 'if [ "$nvp" != yes ] && [ "$tup" != yes ] && [ "$anp" != yes ] && [ "$arp" != yes ] && [ "$ssp" != yes ] && [ "$snp" != yes ]; then',
                '# Reality 伪装域名自动探测：reym/ym 都未指定且装 Reality 协议时才探测，失败即停装（见 modules/auto-sni.sh）\n'
                'if [ -z "${ym_vl_re:-}" ] && { [ "$vlp" = yes ] || [ "$xhp" = yes ] || [ "$vxp" = yes ] || [ "$vwp" = yes ] || [ "$xup" = yes ] || [ "$xcp" = yes ] || [ "$arp" = yes ]; }; then\n'
                '  auto_sni_resolve || exit 1\n'
                'fi\n'
                'if [ "$nvp" != yes ] && [ "$tup" != yes ] && [ "$anp" != yes ] && [ "$arp" != yes ] && [ "$ssp" != yes ] && [ "$snp" != yes ]; then', "auto-sni-call", 1)
    t = replace(t, 'if [ "$nvp" != yes ] && [ "$tup" != yes ] && [ "$anp" != yes ] && [ "$arp" != yes ] && [ "$ssp" != yes ] && [ "$snp" != yes ]; then',
                'if [ "$nvp" != yes ] && [ "$tup" != yes ] && [ "$anp" != yes ] && [ "$arp" != yes ] && [ "$ssp" != yes ] && [ "$vlpt_on" != "sb" ]; then', "vlpt-ins-xray-only", 1)
    t = replace(t, 'elif [ "$xhp" != yes ] && [ "$vlp" != yes ] && [ "$vxp" != yes ] && [ "$vwp" != yes ] && [ "$xup" != yes ] && [ "$xcp" != yes ]; then',
                'elif [ "$xhp" != yes ] && [ "$vxp" != yes ] && [ "$vwp" != yes ] && [ "$xup" != yes ] && [ "$xcp" != yes ] && [ "$vlpt_on" != "xray" ]; then', "vlpt-ins-sb-only", 1)
    t = replace(t, 'xhp="xhptargo"; vlp="vlptargo"; vxp="vxptargo"; vwp="vwptargo"; xup="xuptargo"; xcp="xcptargo"',
                'xhp="xhptargo"; [ "$vlpt_on" = "sb" ] || vlp="vlptargo"; vxp="vxptargo"; vwp="vwptargo"; xup="xuptargo"; xcp="xcptargo"', "vlpt-sb-only-targo", 1)
    # installxray vlpt block: only install on xray when vlpt_on=xray; if vlpt
    # is selected but on sb, leave vlp alone (installsb already set it to
    # vlpt); if vlpt is not selected, set the recovery dummy as before.
    t = replace(t, 'if [ -n "$vlp" ]; then\nvlp=vlpt\n',
                'if [ -n "$vlp" ] && [ "$vlpt_on" = "xray" ]; then\nvlp=vlpt\n', "vlpt-xray-guard", 1)
    t = replace(t, 'else\nvlp=vlptargo\nfi\n}\n\ninstallsb(){',
                'else\n[ -n "$vlp" ] || vlp=vlptargo\nfi\n}\n\ninstallsb(){', "vlpt-xray-else", 1)
    # installsb vlpt block, before the sspt block.
    vlpt_sb = read("modules/vlpt-sb.sh")
    t = replace(t, 'if [ -n "$ssp" ]; then\nssp=sspt\n',
                vlpt_sb + 'if [ -n "$ssp" ]; then\nssp=sspt\n', "vlpt-sb-block", 1)
    # display: vlpt pbk/sid come from the kernel vlpt actually runs on.
    # sb.json with vl-reality-sb wins; otherwise fall back to xray keypair
    # (which is also the only case for old installs, where sb.json has no
    # vlpt inbound). This detection works for fresh installs and for
    # `list` (which re-reads the files from disk, with no vlpt_on in scope).
    # FIX (2026-10-28): vlpt_pbk/sid MUST be assigned OUTSIDE the
    # sing-box-binary check. Previously it was assigned inside that
    # block, so a pure-Xray install (no sing-box binary downloaded)
    # left vlpt_pbk/sid unset and printed pbk=&sid=, even though
    # xrk/ was fine and the server would have worked with the right
    # link. The container version already did it outside the block;
    # main script now matches it: default to Xray, override to
    # Sing-box only when sb.json actually contains vl-reality-sb.
    # The assignment is inserted after the sing-box block's fi,
    # before the xhttp-reality display block.
    t = replace(t, 'sskey=$(cat "$HOME/agsbx/sskey" 2>/dev/null)\nfi\nif grep xhttp-reality "$HOME/agsbx/xr.json"',
                'sskey=$(cat "$HOME/agsbx/sskey" 2>/dev/null)\nfi\nif grep -q "vl-reality-sb" "$HOME/agsbx/sb.json" 2>/dev/null; then vlpt_pbk="$public_key_s"; vlpt_sid="$short_id_s"; else vlpt_pbk="$public_key_x"; vlpt_sid="$short_id_x"; fi\nif grep xhttp-reality "$HOME/agsbx/xr.json"', "vlpt-display-pbk", 1)
    t = replace(t, 'if grep reality-vision "$HOME/agsbx/xr.json" >/dev/null 2>&1; then',
                'if grep reality-vision "$HOME/agsbx/xr.json" >/dev/null 2>&1 || grep vl-reality-sb "$HOME/agsbx/sb.json" >/dev/null 2>&1; then', "vlpt-display-guard", 1)
    t = replace(t, 'vl_link="vless://$uuid@$server_ip:$port_vl_re?encryption=$dekey&flow=xtls-rprx-vision&security=reality&sni=$ym_vl_re&fp=chrome&pbk=$public_key_x&sid=$short_id_x&type=tcp&headerType=none',
                'vl_link="vless://$uuid@$server_ip:$port_vl_re?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$ym_vl_re&fp=chrome&pbk=$vlpt_pbk&sid=$vlpt_sid&type=tcp&headerType=none', "vlpt-link-pbk", 1)
    # vlpt link name: upstream renamed the display to reality-enc when
    # it switched to ENC; we keep encryption=none, so the name must
    # stay vision (instance 1) to match instances 2+ and the truth.
    t = replace(t, 'vl-reality-enc-$hostname', 'vl-reality-vision-$hostname', "vlpt-link-name-vision", 1)
    # vlpt inbound: revert upstream ENC decryption to none (we do not
    # follow Reality ENC; the link stays encryption=none, so the
    # server must not require ENC or the node breaks).
    t = replace(t, '''            "tag":"reality-vision",
            "listen": "::",
            "port": $port_vl_re,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${uuid}",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "${dekey}"''',
                '''            "tag":"reality-vision",
            "listen": "::",
            "port": $port_vl_re,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${uuid}",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"''', "vlpt-inbound-decryption-none", 1)
    # sbvlpt() restored (upstream d4f4b91 deleted it; QUINN decided
    # 2026-11-19 to keep it): insert before sbsspt(). pbk/sid are
    # already kernel-aware in the module; server stays $server_ip so
    # the reality-sb-config patch below still finds one occurrence.
    sbvlpt_restore = read("modules/sbvlpt-restore.sh")
    t = replace(t, 'sbsspt(){',
                sbvlpt_restore + 'sbsspt(){', "sbvlpt-restore", 1)
    t = replace(t, '    public-key: $public_key_x    \n    short-id: $short_id_x',
                '    public-key: $vlpt_pbk    \n    short-id: $vlpt_sid', "vlpt-clash-pbk", 1)

    # vlpt2 REMOVED (2026-10-28): the old vlpt2= second-instance variable
    # is no longer recognised. Instance 2 now comes only from the vlpt
    # comma list (vlpt="10001,10002"). inbound:vlpt2 routing stays:
    # it is an egress alias for the -2 inbound tags, not a protocol
    # variable (see modules/egress.sh vlpt[0-9]* branch).
    # display: tighten the vlpt guard to exact tags, otherwise an
    # instance-2-only config would match reality-vision-2 /
    # vl-reality-sb-2 by substring and show a broken vlpt link.
    t = replace(t, 'if grep reality-vision "$HOME/agsbx/xr.json" >/dev/null 2>&1 || grep vl-reality-sb "$HOME/agsbx/sb.json" >/dev/null 2>&1; then',
                'if grep -q \'"tag":"reality-vision"\' "$HOME/agsbx/xr.json" 2>/dev/null || grep -q \'"tag": "vl-reality-sb"\' "$HOME/agsbx/sb.json" 2>/dev/null; then', "vlpt-display-guard-tighten", 1)

    # --- vlpt loop (private): vlpt_more is INTERNAL only, set by the
    # vlpt comma expansion below ("10002,10003" = instances 2, 3, ...
    # in order, no new variable per instance). vlpt stays as instance
    # 1; vlpt2/vlpt_more are NOT user inputs any more (cleared at
    # script start in vlpt-comma.sh, not in the top lists, vars.env
    # or recovery line). Checking vlpt alone creates exactly one
    # instance, extra instances come from the vlpt comma list.
    # Shared uuid/keypair/SNI/flow, own port and tag -N, shared vlpt_on.
    # --- vlpt comma list: vlpt itself is now the list (see
    # modules/vlpt-comma.sh). Inserted before the port exports, after
    # the rep/del guard block, so sh.txt (saved earlier) still shows
    # the original comma command and exports use the expanded first
    # item + vlpt_more rest.
    vlpt_comma = read("modules/vlpt-comma.sh")
    t = replace(t, 'fi\nexport uuid=${uuid:-\'\'}\n',
                'fi\n' + vlpt_comma + 'export uuid=${uuid:-\'\'}\n', "vlpt-comma-expand", 1)
    vlpt_more_xray = read("modules/vlpt-more-xray.sh")
    t = replace(t, 'else\n[ -n "$vlp" ] || vlp=vlptargo\nfi\n}\n\ninstallsb(){',
                'else\n[ -n "$vlp" ] || vlp=vlptargo\nfi\n' + vlpt_more_xray + '}\n\ninstallsb(){', "vlpt-more-xray-block", 1)
    vlpt_more_sb = read("modules/vlpt-more-sb.sh")
    t = replace(t, 'if [ -n "$ssp" ]; then\nssp=sspt\n',
                vlpt_more_sb + 'if [ -n "$ssp" ]; then\nssp=sspt\n', "vlpt-more-sb-block", 1)
    vlpt_more_display = read("modules/vlpt-more-display.sh")
    t = replace(t, 'clvlpt1(){\necho "- ${sxname}vless-reality-enc-$hostname"\n}\nfi\nif grep ss-2022',
                'clvlpt1(){\necho "- ${sxname}vless-reality-vision-$hostname"\n}\nfi\n' + vlpt_more_display + 'if grep ss-2022', "vlpt-more-display-block", 1)
    t = replace(t, 'sbxy="$(get_func sbsnpt; get_func sbsspt;',
                'sbxy="$(get_func sbvlpt; get_func sbvlpt_more; get_func sbsnpt; get_func sbsspt;', "vlpt-more-sbxy", 1)
    t = replace(t, 'clxy="$(get_func clsnpt; get_func clvlwsargoencpt; get_func clvlxhargoencpt; get_func clwsencpt; get_func clxhencpt; get_func clxhreaencpt; get_func cludpxcpt; get_func clxcpt; get_func clvlpt; get_func clsspt;',
                'clxy="$(get_func clsnpt; get_func clwsencpt; get_func clxhencpt; get_func clxhreaencpt; get_func cludpxcpt; get_func clxcpt; get_func clvlpt; get_func clvlpt_more; get_func clsspt;', "vlpt-more-clxy", 1)
    t = replace(t, 'sbgz="$(get_func sbsnpt1; get_func sbsspt1;',
                'sbgz="$(get_func sbvlpt1; get_func sbvlpt_more_1; get_func sbsnpt1; get_func sbsspt1;', "vlpt-more-sbgz", 1)
    t = replace(t, 'clgz="$({ get_func clsnpt1; get_func clvlwsargoencpt1; get_func clvlxhargoencpt1; get_func clwsencpt1; get_func clxhencpt1; get_func clxhreaencpt1; get_func cludpxcpt1; get_func clxcpt1; get_func clvlpt1; get_func clsspt1;',
                'clgz="$({ get_func clsnpt1; get_func clwsencpt1; get_func clxhencpt1; get_func clxhreaencpt1; get_func cludpxcpt1; get_func clxcpt1; get_func clvlpt1; get_func clvlpt_more_1; get_func clsspt1;', "vlpt-more-clgz", 1)
    ctx["vlpt_comma"] = vlpt_comma
    ctx["vlpt_more_xray"] = vlpt_more_xray
    return t
