"""vmtls flag, top-level module insertions, variable lists. Moved verbatim from main() in build/build.py."""
from ..util import build_camouflage, insert_after, replace


def apply(t, ctx):
    audit_mod = ctx["audit_mod"]
    backup_mod = ctx["backup_mod"]
    check_mod = ctx["check_mod"]
    help_mod = ctx["help_mod"]
    hook_mod = ctx["hook_mod"]
    ports_mod = ctx["ports_mod"]
    proxy_script_mod = ctx["proxy_script_mod"]
    repinherit_mod = ctx["repinherit_mod"]
    subhttps_mod = ctx["subhttps_mod"]
    ufw_mod = ctx["ufw_mod"]
    update_mod = ctx["update_mod"]
    vars_mod = ctx["vars_mod"]
    vlpt_coexistence_mod = ctx["vlpt_coexistence_mod"]
    auto_sni_mod = ctx["auto_sni_mod"]
    webserver_mod = ctx["webserver_mod"]
    # --- vmess-ws-tls (private): new protocol flag vmtls, internal flag vmt ---
    # Top variable list, flag handling, rep/install guards, port export,
    # recovery line, and vars_save list all gain vmtls, following vmpt.
    t = replace(t, "for v in agqc sub subid subpt snpt uuid vlpt vmpt vwpt hypt tupt xhpt vxpt anpt arpt sspt sopt nvpt xupt xcpt reym cdnym argo agn agk warp name oap cfip alns hyjpt; do",
                "for v in agqc sub subid subpt snpt uuid vlpt vmpt vmtls vwpt hypt tupt xhpt vxpt anpt arpt sspt sopt nvpt xupt xcpt reym cdnym argo agn agk warp name oap cfip alns hyjpt; do", "vmtls-top-list", 1)
    # warp 逻辑修复（2026-11-04）：空值不再走 WARP；加显式 off/no/direct；WARP 检测改 WireGuard
    t = replace(t, '""|sx|xs) s1outtag=warp-out;',
                'sx|xs) s1outtag=warp-out;', "warp-no-empty", 1)
    t = replace(t, "xs6|s6x) s1outtag=warp-out; s2outtag=direct; x1outtag=warp-out; x2outtag=warp-out; xip='\"::/0\", \"0.0.0.0/0\"'; sip='\"::/0\"'; wap=warp ;;\n* ) s1outtag=direct;",
                "xs6|s6x) s1outtag=warp-out; s2outtag=direct; x1outtag=warp-out; x2outtag=warp-out; xip='\"::/0\", \"0.0.0.0/0\"'; sip='\"::/0\"'; wap=warp ;;\noff|no|direct) s1outtag=direct; s2outtag=direct; x1outtag=direct; x2outtag=direct; xip='\"::/0\", \"0.0.0.0/0\"'; sip='\"::/0\", \"0.0.0.0/0\"'; wap=warpargo ;;\n* ) s1outtag=direct;", "warp-off-branch", 1)
    t = replace(t, "if echo \"$v6\" | grep -q '^2a09' || echo \"$v4\" | grep -q '^104.28'; then",
                "if (command -v wg >/dev/null 2>&1 && wg show interfaces 2>/dev/null | grep -qi warp) || [ -f /etc/wireguard/warp.conf ] || ip link show 2>/dev/null | grep -qi warp; then", "warp-detect-wg", 1)
    t = replace(t, '[ -z "${vmpt+x}" ] || { vmp=yes; vmag=yes; }',
                '[ -z "${vmpt+x}" ] || { vmp=yes; vmag=yes; }\n[ -z "${vmtls+x}" ] || vmt=yes', "vmtls-flag", 1)
    t = replace(t, '[ "$xcp" = yes ] || [ "$xup" = yes ] || [ "$nvp" = yes ] || [ "$vwp" = yes ] || [ "$sop" = yes ] || [ "$vxp" = yes ] || [ "$ssp" = yes ] || [ "$vlp" = yes ] || [ "$vmp" = yes ] || [ "$hyp" = yes ] || [ "$tup" = yes ] || [ "$xhp" = yes ] || [ "$anp" = yes ] || [ "$arp" = yes ]',
                '[ "$xcp" = yes ] || [ "$xup" = yes ] || [ "$nvp" = yes ] || [ "$vwp" = yes ] || [ "$sop" = yes ] || [ "$vxp" = yes ] || [ "$ssp" = yes ] || [ "$vlp" = yes ] || [ "$vmp" = yes ] || [ "$vmt" = yes ] || [ "$hyp" = yes ] || [ "$tup" = yes ] || [ "$xhp" = yes ] || [ "$anp" = yes ] || [ "$arp" = yes ]', "vmtls-rep-guard", 2)
    t = replace(t, "export port_vm_ws=${vmpt:-''}",
                "export port_vm_ws=${vmpt:-''}\nexport port_vm_tls=${vmtls:-''}", "vmtls-port-export", 1)
    t = replace(t, '$vmp=\\"${port_vm_ws}\\"',
                '$vmp=\\"${port_vm_ws}\\" $vmt=\\"${port_vm_tls}\\"', "vmtls-recovery", 1)
    # --- incremental update module (top, before sh.txt save + protocol selection) ---
    t = insert_after(t, 'mkdir -p "$HOME/agsbx"\n',
                     hook_mod + vars_mod + proxy_script_mod + 'run_hook on_init "$1"\n', "vars-module-anchor")
    # --- ufw module (top level, functions only; called after ins) ---
    t = insert_after(t, 'run_hook on_init "$1"\n',
                     ufw_mod, "ufw-module-anchor")
    # --- https subscription module (top level, functions only; called
    # from the display block, after the sub block has created the token,
    # so first installs get the right mode, not the previous one) ---
    t = insert_after(t, 'run_hook on_init "$1"\n',
                     subhttps_mod, "subhttps-module-anchor")
    # --- backup/restore module (top level, functions only; subcommands) ---
    t = insert_after(t, 'run_hook on_init "$1"\n',
                     backup_mod, "backup-module-anchor")
    # --- check module (top level, functions only; subcommand) ---
    t = insert_after(t, 'run_hook on_init "$1"\n',
                     check_mod, "check-module-anchor")
    # --- help module (top level, functions only; subcommand) ---
    t = insert_after(t, 'run_hook on_init "$1"\n',
                     help_mod, "help-module-anchor")
    # --- audit module (top level, functions only; subcommand) ---
    t = insert_after(t, 'run_hook on_init "$1"\n',
                     audit_mod, "audit-module-anchor")
    # --- update module (top level, functions only; subcommand) ---
    t = insert_after(t, 'run_hook on_init "$1"\n',
                     update_mod, "update-module-anchor")
    # --- rep-inherit module (rep without protocols inherits from vars.env) ---
    t = insert_after(t, 'run_hook on_init "$1"\n',
                     repinherit_mod, "rep-inherit-anchor")
    # --- ports module (consolidated ports.env) ---
    t = insert_after(t, 'run_hook on_init "$1"\n',
                     ports_mod, "ports-module-anchor")
    # --- web-server module ---
    t = insert_after(t, 'run_hook on_init "$1"\n',
                     webserver_mod, "webserver-module-anchor")
    # --- vlpt-coexistence module ---
    t = insert_after(t, 'run_hook on_init "$1"\n',
                     vlpt_coexistence_mod, "vlpt-coexistence-module-anchor")
    # --- auto-sni module (Reality SNI auto-detect; called once from
    # ins(), see the auto-sni-call anchor in patches/vlpt.py) ---
    t = insert_after(t, 'run_hook on_init "$1"\n',
                     auto_sni_mod, "auto-sni-module-anchor")
    # --- camouflage blog module (functions only; called manually or from
    # own-domain setup, not on every install) ---
    t = insert_after(t, 'run_hook on_init "$1"\n',
                     build_camouflage(), "camouflage-module-anchor")
    # --- variable lists ---
    t = replace(t, "for v in agqc sub subid subpt snpt uuid vlpt vmpt vmtls vwpt hypt tupt xhpt vxpt anpt arpt sspt sopt nvpt xupt xcpt reym cdnym argo agn agk warp name oap cfip alns hyjpt; do",
                "for v in agqc sub subid subpt snpt uuid vlpt vmpt vmtls vwpt hypt tupt xhpt vxpt anpt arpt sspt sopt nvpt xupt xcpt reym cdnym argo agn agk warp name oap cfip alns hyjpt ym certmode certsrc web_proxy vlpt_kernel egress_nodes egress_bind egress_rules egress_add ippz web_port; do", "export-list", 1)
    return t
