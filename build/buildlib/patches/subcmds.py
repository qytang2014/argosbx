"""Subcommand insertions (gate, certwatch, ufwsync, backup/check, help, audit, update). Moved verbatim from main() in build/build.py."""
from ..util import replace


def apply(t, ctx):
    # --- top command-save exclusion: certwatch/certrestart must not overwrite sh.txt ---
    t = replace(t, 'case "${*##* }" in list|del|upx|ups|upa|res) ;; *)',
                'case "${*##* }" in list|del|upx|ups|upa|res|up|update|certwatch|certrestart|ufwsync|fwsync|fwstatus|subhttpsync|audit|help|-h|--help|check|backup|restore) ;; *)', "top-case-exclusion", 1)
    # --- installed state gate check: decouple installation state from currently running process ---
    t = replace(t, "if find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null | grep -Eq 'agsbx/(s|x)' || pgrep -f 'agsbx/(s|x)' >/dev/null 2>&1; then",
                "if agsbx_is_installed; then", "installed-gate-check", 1)
    # --- certwatch/certrestart subcommands + del cleanup ---
    t = replace(t, 'if [ "$1" = "del" ]; then\ncleandel',
                'if [ "$1" = "certwatch" ]; then\ncert_watch\nexit\nfi\nif [ "$1" = "certrestart" ]; then\ncert_restart\nexit\nfi\nif [ "$1" = "del" ]; then\ncert_remove_watch\ncleandel', "certwatch-dispatch", 1)
    # --- ufwsync subcommand + ufw cleanup on del (before rm -rf, so
    # the state file and port files still exist when cleanup runs) ---
    t = replace(t, 'if [ "$1" = "certrestart" ]; then\ncert_restart\nexit\nfi\nif [ "$1" = "del" ]; then\ncert_remove_watch\ncleandel',
                'if [ "$1" = "certrestart" ]; then\ncert_restart\nexit\nfi\nif [ "$1" = "ufwsync" ]; then\nfw_apply_saved\nexit\nfi\nif [ "$1" = "fwsync" ]; then\nfw_apply_saved\nexit\nfi\nif [ "$1" = "fwstatus" ]; then\nfw_status\nexit\nfi\nif [ "$1" = "del" ]; then\ncert_remove_watch\ncleandel', "ufwsync-dispatch", 1)
    t = replace(t, 'if [ "$1" = "ufwsync" ]; then\nfw_apply_saved\nexit\nfi\nif [ "$1" = "fwsync" ]; then\nfw_apply_saved\nexit\nfi\nif [ "$1" = "fwstatus" ]; then\nfw_status\nexit\nfi\nif [ "$1" = "del" ]; then\ncert_remove_watch\ncleandel',
                'if [ "$1" = "ufwsync" ]; then\nfw_apply_saved\nexit\nfi\nif [ "$1" = "fwsync" ]; then\nfw_apply_saved\nexit\nfi\nif [ "$1" = "fwstatus" ]; then\nfw_status\nexit\nfi\nif [ "$1" = "subhttpsync" ]; then\nsub_https_sync\nexit\nfi\nif [ "$1" = "del" ]; then\ncert_remove_watch\ncleandel', "subhttpsync-dispatch", 1)
    # --- backup/restore/check subcommands ---
    # backup/restore take extra args: shift $1 off so "$@" is the subcommand args.
    # restore: on AGSBX_RESTORE_READY=1 clear args and fall through to install flow.
    t = replace(t, 'if [ "$1" = "subhttpsync" ]; then\nsub_https_sync\nexit\nfi\nif [ "$1" = "del" ]; then',
                'if [ "$1" = "subhttpsync" ]; then\nsub_https_sync\nexit\nfi\nif [ "$1" = "check" ]; then\nagsbx_check\nexit\nfi\nif [ "$1" = "backup" ]; then\nshift\nagsbx_backup "$@"\nexit\nfi\nif [ "$1" = "restore" ]; then\nAGSBX_RESTORE_READY=0\nshift\nagsbx_restore "$@"\nrc=$?\nif [ "$rc" -ne 0 ] || [ "$AGSBX_RESTORE_READY" != "1" ]; then exit $rc; fi\nset --\nfi\nif [ "$1" = "del" ]; then', "backup-check-dispatch", 1)
    # --- help subcommand ---
    t = replace(t, 'agsbx_check\nexit\nfi',
                'agsbx_check\nexit\nfi\nif [ "$1" = "--help" ] || [ "$1" = "-h" ] || [ "$1" = "help" ]; then\nagsbx_help\nexit\nfi', "help-dispatch", 1)
    # --- audit subcommand ---
    t = replace(t, 'agsbx_help\nexit\nfi',
                'agsbx_help\nexit\nfi\nif [ "$1" = "audit" ]; then\nagsbx_audit\nexit\nfi', "audit-dispatch", 1)
    # --- update subcommand ---
    t = replace(t, 'agsbx_audit\nexit\nfi',
                'agsbx_audit\nexit\nfi\nif [ "$1" = "up" ] || [ "$1" = "update" ]; then\nagsbx_update\nexit\nfi', "update-dispatch", 1)
    t = replace(t, 'if [ "$1" = "del" ]; then\ncert_remove_watch\ncleandel\nrm -rf sbx_update "$HOME/agsbx" "$HOME/websbx"',
                'if [ "$1" = "del" ]; then\nrun_hook on_uninstall\ncleandel\nrm -rf sbx_update "$HOME/agsbx" "$HOME/websbx"', "ufw-del-cleanup", 1)
    t = replace(t, '[ \"$1\" = \"del\" ] || [ \"$snp\" = yes ] || [ \"$xcp\" = yes ]',
                '[ \"$1\" = \"del\" ] || [ \"$1\" = \"backup\" ] || [ \"$1\" = \"check\" ] || [ \"$1\" = \"restore\" ] || [ \"$1\" = \"audit\" ] || [ \"$1\" = \"help\" ] || [ \"$1\" = \"-h\" ] || [ \"$1\" = \"--help\" ] || [ \"$1\" = \"up\" ] || [ \"$1\" = \"update\" ] || [ \"$1\" = \"list\" ] || [ \"$snp\" = yes ] || [ \"$xcp\" = yes ]', "backup-check-bypass", 1)
    t = replace(t, 'xrsbout(){\nif [ -e "$HOME/agsbx/xr.json" ]; then',
                'xrsbout(){\nrun_hook pre_xrsbout\nif [ -e "$HOME/agsbx/xr.json" ]; then', "egress-init-call", 1)
    t = replace(t, '  "route": {\n    "rules": [\n       {\n          "action": "sniff"',
                '  "route": {\n${egress_sb_geo_cfg}    "rules": [\n       {\n          "action": "sniff"', "sb-geo-cfg-hook", 1)
    # xray geo files must survive restarts, not just the first xrsbout
    # start: systemd unit, OpenRC script and xrestart nohup all launch
    # xray without the asset env otherwise.
    t = replace(t, 'ExecStart=/root/agsbx/xray run -c /root/agsbx/xr.json',
                'Environment=XRAY_LOCATION_ASSET=/root/agsbx/geo/xray\nExecStart=/root/agsbx/xray run -c /root/agsbx/xr.json', "xr-systemd-asset", 1)
    t = replace(t, 'command_args="run -c /root/agsbx/xr.json"',
                'command_args="run -c /root/agsbx/xr.json"\ncommand_env="XRAY_LOCATION_ASSET=/root/agsbx/geo/xray"', "xr-openrc-asset", 1)
    t = replace(t, 'nohup $HOME/agsbx/xray run -c $HOME/agsbx/xr.json',
                'nohup env XRAY_LOCATION_ASSET=$HOME/agsbx/geo/xray $HOME/agsbx/xray run -c $HOME/agsbx/xr.json', "xr-restart-asset", 2)
    t = replace(t, '  "outbounds": [\n    {\n      "protocol": "freedom",\n      "tag": "direct",',
                '  "outbounds": [\n${egress_xr_outbounds}    {\n      "protocol": "freedom",\n      "tag": "direct",', "xr-outbounds-hook", 1)
    t = replace(t, '  "outbounds": [\n    {\n      "type": "direct",\n      "tag": "direct"\n    }\n  ],',
                '  "outbounds": [\n${egress_sb_outbounds}    {\n      "type": "direct",\n      "tag": "direct"\n    }\n  ],', "sb-outbounds-hook", 1)
    t = replace(t, '    "rules": [\n      {\n        "type": "field",\n        "ip": [ ${xip} ],',
                '    "rules": [\n${egress_xr_rules}      {\n        "type": "field",\n        "ip": [ ${xip} ],', "xr-routing-hook", 1)
    t = replace(t, '       {\n        "action": "resolve",\n         "strategy": "${sbyx}"\n       },\n      {\n        "ip_cidr": [ ${sip} ],',
                '       {\n        "action": "resolve",\n         "strategy": "${sbyx}"\n       },\n${egress_sb_rules}      {\n        "ip_cidr": [ ${sip} ],', "sb-routing-hook", 1)
    return t
