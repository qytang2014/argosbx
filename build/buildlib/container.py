"""Container builder — moved verbatim from build/build.py."""
import sys
from . import util
from .util import ROOT, insert_after, read, replace

def build_container():
    c = read("upstream/container/nodejs/start.sh")
    container_cert = read("modules/container-cert.sh")
    container_vars = read("modules/container-vars.sh")
    container_ufw = read("modules/container-ufw.sh")
    container_comma = read("modules/container-comma.sh")
    domain_addr = read("modules/reality-addr.sh")
    c = replace(c, "export LANG=en_US.UTF-8\n", "export LANG=en_US.UTF-8\n" + container_vars + "container_vars_merge\n", "container-vars-module", 1)
    # --- container host-ufw prompt (function only; called after
    # container_vars_save in ins, when all node ports are known) ---
    c = insert_after(c, "container_vars_merge\n", container_ufw, "container-ufw-module")
    # --- container comma multi-instance parsing ---
    c = insert_after(c, "container_vars_merge\n", container_comma, "container-comma-module")
    c = replace(c, 'echo "甬哥Github项目 ：github.com/yonggekkk"\necho "甬哥Blogger博客 ：ygkkk.blogspot.com"\necho "甬哥YouTube频道 ：www.youtube.com/@ygkkk"', 'echo "项目地址：github.com/qytang2014/argosbx"', "container-banner-project-url", 1)
    c = replace(c, 'echo "Argosbx脚本项目地址：https://github.com/yonggekkk/argosbx"',
                'echo "Argosbx脚本项目地址：https://github.com/qytang2014/argosbx"', "container-project-link", 1)
    # --- container default CDN addresses: upstream uses the author's
    # yg*.ygkkk.dpdns.org domains; ours use the same default CDN
    # domain as the main script (icook.tw). WARP detection domain
    # (ygkkk-warp.renky.eu.org) is left untouched. ---
    c = replace(c, 'yg$(cfip).ygkkk.dpdns.org', 'icook.tw', "container-dpdns-cfip", 5)
    for _i in range(1, 12):
        c = replace(c, f'yg{_i}.ygkkk.dpdns.org', 'icook.tw', f'container-dpdns-yg{_i}', 1)
    c = replace(c, '注：默认地址 yg数字.ygkkk.dpdns.org 可自行更换优选IP域名，如是回源端口需手动修改443或者80系端口',
                '注：默认地址 icook.tw 可自行更换优选IP域名，如是回源端口需手动修改443或者80系端口', "container-dpdns-note", 3)
    c = replace(c, "export name=${name}", "export name=${name}\nexport ym=${ym}\nexport vlpt_kernel=${vlpt_kernel}", "container-ym-export", 1)
    # --- vmess-ws-tls (container): export, inbound, call, display link ---
    c = replace(c, "export vmpt=${vmpt}", "export vmpt=${vmpt}\nexport vmtls=${vmtls}", "container-vmtls-export", 1)
    vmtls_c = read("modules/vmtls-container.sh")
    c = replace(c, "xrsbso(){\nif [ -n \"$sopt\" ]; then",
                vmtls_c + "xrsbso(){\nif [ -n \"$sopt\" ]; then", "container-vmtls-inbound", 1)
    n = c.count("xrsbvm\nxrsbso")
    if n == 0:
        print("BUILD FAIL: container-vmtls-call: expected at least 1 occurrence, found 0", file=sys.stderr); sys.exit(1)
    c = c.replace("xrsbvm\nxrsbso", "xrsbvm\nxrsbvmtls\nxrsbso")
    # Container display link: after the plain vmess block, before the
    # Argo vmess links. add/sni/tls_ins are already set by
    # container-display-addr; hpkp pin only when self-signed
    # (tls_ins=1) and the self-signed cert parses.
    vmtls_c_display = '''if grep vmess-tls-xr "$HOME/agsbx/xr.json" >/dev/null 2>&1 || grep vmess-tls-sb "$HOME/agsbx/sb.json" >/dev/null 2>&1; then
vmtls_c=$(cat "$HOME/agsbx/vmtls")
if [ "$tls_ins" = "1" ]; then vmtls_c_sha=$(openssl x509 -in "$HOME/agsbx/selfsigned/cert.pem" -outform DER 2>/dev/null | sha256sum 2>/dev/null | cut -d' ' -f1); else vmtls_c_sha=""; fi
if [ -n "$vmtls_c_sha" ]; then vmtls_c_hpkp=", \\"hpkp\\": \\"$vmtls_c_sha\\""; else vmtls_c_hpkp=""; fi
vmtls_c_link="vmess://$(echo "{ \\"v\\": \\"2\\", \\"ps\\": \\"${sxname}vm-ws-tls-$hostname\\", \\"add\\": \\"$add\\", \\"port\\": \\"$vmtls_c\\", \\"id\\": \\"$uuid\\", \\"aid\\": \\"0\\", \\"scy\\": \\"auto\\", \\"net\\": \\"ws\\", \\"type\\": \\"none\\", \\"host\\": \\"$sni\\", \\"path\\": \\"/$uuid-vmtls\\", \\"tls\\": \\"tls\\", \\"sni\\": \\"$sni\\", \\"alpn\\": \\"\\", \\"fp\\": \\"chrome\\"$vmtls_c_hpkp}" | base64 -w0)"
echo "$vmtls_c_link"
echo
fi
'''
    # Anchor: the container Argo vmess section starts with the first
    # vmatls_link assignment; insert the direct link just before it.
    if 'vmatls_link1=' not in c:
        print("BUILD FAIL: container-vmtls-display-anchor", file=sys.stderr); sys.exit(1)
    c = c.replace('vmatls_link1=', vmtls_c_display + 'vmatls_link1=', 1)
    # Container hy2 native link: pin when self-signed, matching main.
    # The pin variables are appended to display_tls below (that
    # assignment runs after this block, so a replacement here would
    # find nothing yet).
    # --- vlpt dual-support, container (same rules as main, ports not flags) ---
    vlpt_sb_c = read("modules/vlpt-sb-container.sh")
    vlpt_on_c = '''# vlpt dual-support: vlpt_kernel=auto (default) / xray / sb
vlpt_on=""
if [ -n "$vlpt" ]; then
  case "${vlpt_kernel:-auto}" in
    xray) vlpt_on="xray" ;;
    sb|singbox|sing-box) vlpt_on="sb" ;;
    *)
      if [ -n "$xhpt" ] || [ -n "$vxpt" ] || [ -n "$vwpt" ]; then vlpt_on="xray";
      elif [ -n "$hypt" ] || [ -n "$tupt" ] || [ -n "$anpt" ] || [ -n "$arpt" ] || [ -n "$sspt" ]; then vlpt_on="sb";
      else vlpt_on="xray"; fi ;;
  esac
fi
'''
    c = replace(c, 'ins(){\nif [ -z "$hypt" ]',
                'ins(){\n' + vlpt_on_c + 'if [ -z "$hypt" ]', "container-vlpt-on-compute", 1)
    c = replace(c, 'if [ -z "$hypt" ] && [ -z "$tupt" ] && [ -z "$anpt" ] && [ -z "$arpt" ] && [ -z "$sspt" ]; then',
                'if [ -z "$hypt" ] && [ -z "$tupt" ] && [ -z "$anpt" ] && [ -z "$arpt" ] && [ -z "$sspt" ] && [ "$vlpt_on" != "sb" ]; then', "container-vlpt-ins-xray-only", 1)
    c = replace(c, 'elif [ -z "$xhpt" ] && [ -z "$vlpt" ] && [ -z "$vxpt" ] && [ -z "$vwpt" ]; then',
                'elif [ -z "$xhpt" ] && [ -z "$vxpt" ] && [ -z "$vwpt" ] && [ "$vlpt_on" != "xray" ]; then', "container-vlpt-ins-sb-only", 1)
    c = replace(c, 'if [ -n "$vlpt" ]; then\nif [ -z "$vlpt" ] && [ ! -e "$HOME/agsbx/vlpt" ]; then',
                'if [ -n "$vlpt" ] && [ "$vlpt_on" = "xray" ]; then\nif [ -z "$vlpt" ] && [ ! -e "$HOME/agsbx/vlpt" ]; then', "container-vlpt-xray-guard", 1)
    c = replace(c, 'if [ -n "$sspt" ]; then\nif [ ! -e "$HOME/agsbx/sskey" ]; then',
                vlpt_sb_c + 'if [ -n "$sspt" ]; then\nif [ ! -e "$HOME/agsbx/sskey" ]; then', "container-vlpt-sb-block", 1)
    c = replace(c, 'sskey=$(cat "$HOME/agsbx/sskey" 2>/dev/null)\nfi\nif grep xhttp-reality "$HOME/agsbx/xr.json"',
                'sskey=$(cat "$HOME/agsbx/sskey" 2>/dev/null)\nfi\nif grep -q "vl-reality-sb" "$HOME/agsbx/sb.json" 2>/dev/null; then vlpt_pbk="$public_key_s"; vlpt_sid="$short_id_s"; else vlpt_pbk="$public_key_x"; vlpt_sid="$short_id_x"; fi\nif grep xhttp-reality "$HOME/agsbx/xr.json"', "container-vlpt-display-pbk", 1)
    c = replace(c, 'if grep reality-vision "$HOME/agsbx/xr.json" >/dev/null 2>&1; then\necho "💣【 Vless-tcp-reality-vision 】节点信息如下："',
                'if grep reality-vision "$HOME/agsbx/xr.json" >/dev/null 2>&1 || grep vl-reality-sb "$HOME/agsbx/sb.json" >/dev/null 2>&1; then\necho "💣【 Vless-tcp-reality-vision 】节点信息如下："', "container-vlpt-display-guard", 1)
    c = replace(c, 'vl_link="vless://$uuid@$server_ip:$vlpt?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$reym&fp=chrome&pbk=$public_key_x&sid=$short_id_x&type=tcp&headerType=none',
                'vl_link="vless://$uuid@$server_ip:$vlpt?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$reym&fp=chrome&pbk=$vlpt_pbk&sid=$vlpt_sid&type=tcp&headerType=none', "container-vlpt-link-pbk", 1)
    c = replace(c, "installsb(){", container_cert + "installsb(){", "container-cert-fn", 1)
    old_cert = """command -v openssl >/dev/null 2>&1 && openssl ecparam -genkey -name prime256v1 -out "$HOME/agsbx/private.key" >/dev/null 2>&1
command -v openssl >/dev/null 2>&1 && openssl req -new -x509 -days 36500 -key "$HOME/agsbx/private.key" -out "$HOME/agsbx/cert.pem" -subj "/CN=www.bing.com" >/dev/null 2>&1
if [ ! -f "$HOME/agsbx/private.key" ]; then
url="https://github.com/yonggekkk/argosbx/releases/download/argosbx/private.key"; out="$HOME/agsbx/private.key"; (command -v curl>/dev/null 2>&1 && curl -Ls -o "$out" --retry 2 "$url") || (command -v wget>/dev/null 2>&1 && timeout 3 wget -q -O "$out" --tries=2 "$url")
url="https://github.com/yonggekkk/argosbx/releases/download/argosbx/cert.pem"; out="$HOME/agsbx/cert.pem"; (command -v curl>/dev/null 2>&1 && curl -Ls -o "$out" --retry 2 "$url") || (command -v wget>/dev/null 2>&1 && timeout 3 wget -q -O "$out" --tries=2 "$url")
fi"""
    c = replace(c, old_cert, "container_cert_setup", "container-cert-block", 1)
    display_tls = """if [ "$(cat "$HOME/agsbx/domain_cert_ready" 2>/dev/null)" = "1" ] && [ -s "$HOME/agsbx/ym" ]; then add=$(cat "$HOME/agsbx/ym" 2>/dev/null); sni="$add"; tls_ins=0; else add="$server_ip"; sni="www.bing.com"; tls_ins=1; fi
if [ "$tls_ins" = "1" ]; then hy2_c_sha=$(openssl x509 -in "$HOME/agsbx/selfsigned/cert.pem" -outform DER 2>/dev/null | sha256sum 2>/dev/null | cut -d' ' -f1); else hy2_c_sha=""; fi
if [ -n "$hy2_c_sha" ]; then hy2_c_ins=0; hy2_c_pin="&pinSHA256=$hy2_c_sha"; else hy2_c_ins="$tls_ins"; hy2_c_pin=""; fi"""
    c = replace(c, 'server_ip=$(cat "$HOME/agsbx/server_ip.log")',
                'server_ip=$(cat "$HOME/agsbx/server_ip.log")\n' + domain_addr + display_tls,
                "container-display-addr", 1)
    c = replace(c, 'vl_xh_link="vless://$uuid@$server_ip:$xhpt?', 'vl_xh_link="vless://$uuid@$domain_addr:$xhpt?', "container-reality-xhttp", 1)
    c = replace(c, 'vl_link="vless://$uuid@$server_ip:$vlpt?', 'vl_link="vless://$uuid@$domain_addr:$vlpt?', "container-reality-tcp", 1)
    c = replace(c, 'ar_link="anytls://$uuid@$server_ip:$arpt?', 'ar_link="anytls://$uuid@$domain_addr:$arpt?', "container-reality-any", 1)
    c = replace(c, 'vl_vx_link="vless://$uuid@$server_ip:$vxpt?', 'vl_vx_link="vless://$uuid@$domain_addr:$vxpt?', "container-plain-xhttp", 1)
    c = replace(c, 'vl_vw_link="vless://$uuid@$server_ip:$vwpt?', 'vl_vw_link="vless://$uuid@$domain_addr:$vwpt?', "container-plain-ws", 1)
    c = replace(c, '2022-blake3-aes-128-gcm:$sskey@$server_ip:$sspt', '2022-blake3-aes-128-gcm:$sskey@$domain_addr:$sspt', "container-plain-ss", 1)
    c = replace(c, '\\"add\\": \\"$server_ip\\", \\"port\\": \\"$vmpt\\"', '\\"add\\": \\"$domain_addr\\", \\"port\\": \\"$vmpt\\"', "container-plain-vm", 1)
    c = replace(c, 'hy2_link="hysteria2://$uuid@$server_ip:$hypt?security=tls&alpn=h3&insecure=1&sni=www.bing.com',
                'hy2_link="hysteria2://$uuid@$add:$hypt?security=tls&alpn=h3&insecure=$hy2_c_ins&sni=$sni$hy2_c_pin', "container-tls-hy2", 1)
    c = replace(c, 'tuic5_link="tuic://$uuid:$uuid@$server_ip:$tupt?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1&allowInsecure=1',
                'tuic5_link="tuic://$uuid:$uuid@$add:$tupt?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$sni&allow_insecure=$tls_ins&allowInsecure=$tls_ins', "container-tls-tuic", 1)
    c = replace(c, 'an_link="anytls://$uuid@$server_ip:$anpt?insecure=1&allowInsecure=1',
                'an_link="anytls://$uuid@$add:$anpt?insecure=$tls_ins&allowInsecure=$tls_ins', "container-tls-any", 1)
    c = replace(c, 'echo "客户端地址：$server_ip"', 'echo "客户端地址：$domain_addr"', "container-socks5-addr", 1)
    # --- egress parity (final egress module, same as main script) ---
    egress_mod = read("modules/egress.sh")
    c = replace(c, "export ym=${ym}", "export ym=${ym}\nexport outip=${outip}\nexport egress_nodes=${egress_nodes}\nexport egress_bind=${egress_bind}\nexport egress_rules=${egress_rules}\nexport egress_add=${egress_add}", "container-egress-exports", 1)
    c = replace(c, '"certificate_path": "$HOME/agsbx/cert.pem",', '"certificate_path": "$HOME/agsbx/selfsigned/cert.pem",', "container-tls-cert-path", 3)
    c = replace(c, '"key_path": "$HOME/agsbx/private.key"', '"key_path": "$HOME/agsbx/selfsigned/private.key"', "container-tls-key-path", 3)
    c = replace(c, "xrsbout(){", egress_mod + "xrsbout(){", "container-egress-module", 1)
    c = replace(c, 'xrsbout(){\nif [ -e "$HOME/agsbx/xr.json" ]; then',
                'xrsbout(){\negress_init\negress_geo_setup\nif [ -e "$HOME/agsbx/xr.json" ]; then', "container-egress-init", 1)
    c = replace(c, '  "route": {\n    "rules": [\n       {\n          "action": "sniff"',
                '  "route": {\n${egress_sb_geo_cfg}    "rules": [\n       {\n          "action": "sniff"', "container-sb-geo-cfg-hook", 1)
    c = replace(c, '  "outbounds": [\n    {\n      "protocol": "freedom",\n      "tag": "direct",',
                '  "outbounds": [\n${egress_xr_outbounds}    {\n      "protocol": "freedom",\n      "tag": "direct",', "container-xr-outbounds-hook", 1)
    c = replace(c, '  "outbounds": [\n    {\n      "type": "direct",\n      "tag": "direct"\n    }\n  ],',
                '  "outbounds": [\n${egress_sb_outbounds}    {\n      "type": "direct",\n      "tag": "direct"\n    }\n  ],', "container-sb-outbounds-hook", 1)
    c = replace(c, '    "rules": [\n      {\n        "type": "field",\n        "ip": [ ${xip} ],',
                '    "rules": [\n${egress_xr_rules}      {\n        "type": "field",\n        "ip": [ ${xip} ],', "container-xr-routing-hook", 1)
    c = replace(c, '       {\n        "action": "resolve",\n         "strategy": "${sbyx}"\n       },\n      {',
                '${egress_sb_pre_rules}       {\n        "action": "resolve",\n         "strategy": "${sbyx}"\n       },\n${egress_sb_rules}      {', "container-sb-routing-hook", 1)
    c = replace(c, 'fi\nif [ -n "$argo" ]; then\necho\necho "=========启用Cloudflared-argo内核========="',
                'fi\ncontainer_vars_save\nif [ -n "$argo" ]; then\necho\necho "=========启用Cloudflared-argo内核========="', "container-vars-save", 1)
    c = replace(c, "container_vars_save\nif [ -n \"$argo\" ]",
                "container_vars_save\ncontainer_ufw_prompt\nif [ -n \"$argo\" ]", "container-ufw-prompt-call", 1)
    lines = c.split("\n", 1)
    assert lines[0] == "#!/bin/sh"
    out = lines[0] + "\n# GENERATED BY build/build.py - DO NOT EDIT BY HAND - sources: upstream/container/nodejs/start.sh + modules/container-cert.sh + modules/reality-addr.sh + modules/egress.sh + modules/container-ufw.sh\n" + lines[1]
    if util.WRITE:
        (ROOT / "container/nodejs/start.sh").write_text(out)
        print(f"Built container/nodejs/start.sh: {len(out)} bytes, {out.count(chr(10))} lines")
