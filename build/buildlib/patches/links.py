"""vmtls display, cert main block, https subscription display, Reality fallback. Moved verbatim from main() in build/build.py."""
from ..util import insert_after, replace


def apply(t, ctx):
    cert_main = ctx["cert_main"]
    # --- vmess-ws-tls display (native link + sing-box + Clash) ---
    # Inserted between the vmess-ws block and the naive block. Native
    # link: tls:"tls", sni/host = $sni, add = $add (domain when the
    # domain cert is ready, otherwise IP + www.bing.com), hpkp pin only
    # when self-signed and pinned (same $pin_sha as Clash fingerprint).
    vmtls_display = '''if grep vmess-tls-xr "$HOME/agsbx/xr.json" >/dev/null 2>&1 || grep vmess-tls-sb "$HOME/agsbx/sb.json" >/dev/null 2>&1; then
echo "💣【 Vmess-ws-tls 】节点信息如下："
port_vm_tls=$(cat "$HOME/agsbx/port_vm_tls")
if [ "$pin_on" = "1" ]; then vmtls_hpkp=", \\"hpkp\\": \\"$pin_sha\\""; else vmtls_hpkp=""; fi
vmtls_link="vmess://$(echo "{ \\"v\\": \\"2\\", \\"ps\\": \\"${sxname}vm-ws-tls-$hostname\\", \\"add\\": \\"$add\\", \\"port\\": \\"$port_vm_tls\\", \\"id\\": \\"$uuid\\", \\"aid\\": \\"0\\", \\"scy\\": \\"auto\\", \\"net\\": \\"ws\\", \\"type\\": \\"none\\", \\"host\\": \\"$sni\\", \\"path\\": \\"/$uuid-vmtls\\", \\"tls\\": \\"tls\\", \\"sni\\": \\"$sni\\", \\"alpn\\": \\"\\", \\"fp\\": \\"chrome\\"$vmtls_hpkp}" | base64 -w0)"
echo "$vmtls_link" >> "$HOME/agsbx/jhsub.txt"
echo "$vmtls_link"
echo
sbvmtlspt(){
cat <<EOF
{
            "server": "$add",
            "server_port": $port_vm_tls,
            "tag": "${sxname}vmess-ws-tls-$hostname",
            "tls": {
                "enabled": true,
                "server_name": "$sni",
                "insecure": $sb_insecure$sb_pin_field,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "transport": {
                "headers": {
                    "Host": [
                        "$sni"
                    ]
                },
                "path": "$uuid-vmtls",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
EOF
}
sbvmtlspt1(){
echo "\\"${sxname}vmess-ws-tls-$hostname\\","
}
clvmtlspt(){
cat <<EOF
- name: ${sxname}vmess-ws-tls-$hostname
  type: vmess
  server: $add
  port: $port_vm_tls
  uuid: $uuid
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  network: ws
  servername: $sni
  client-fingerprint: chrome
  skip-cert-verify: $cl_skip
$cl_pin_line
  ws-opts:
    path: "$uuid-vmtls"
    headers:
      Host: $sni
EOF
}
clvmtlspt1(){
echo "- ${sxname}vmess-ws-tls-$hostname"
}
fi
'''
    t = replace(t, 'if grep naive-sb "$HOME/agsbx/sb.json" >/dev/null 2>&1; then',
                vmtls_display + 'if grep naive-sb "$HOME/agsbx/sb.json" >/dev/null 2>&1; then', "vmtls-display", 1)
    # Group lists: vmess-ws-tls joins both subscription groups, after
    # plain vmess-ws, so it is selected by load-balance / url-test /
    # selector exactly like the other nodes.
    t = replace(t, "get_func sbvmpt; get_func sbhypt",
                "get_func sbvmpt; get_func sbvmtlspt; get_func sbhypt", "vmtls-sb-group", 1)
    t = replace(t, "get_func clvmpt; get_func clhypt",
                "get_func clvmpt; get_func clvmtlspt; get_func clhypt", "vmtls-cl-group", 1)
    t = replace(t, "get_func sbvmpt1; get_func sbhypt1",
                "get_func sbvmpt1; get_func sbvmtlspt1; get_func sbhypt1", "vmtls-sb-group1", 1)
    t = replace(t, "get_func clvmpt1; get_func clhypt1",
                "get_func clvmpt1; get_func clvmtlspt1; get_func clhypt1", "vmtls-cl-group1", 1)

    # --- cert main block replacement (upstream acme-yg block -> private cert block) ---
    upstream_block = '''if [ -n "$alns" ] && [ ! -s "/root/ygkkkca/private.key" ]; then
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)
fi
echo
if [ -n "$alns" ] && [ -s "/root/ygkkkca/private.key" ]; then
certificateHTA="/root/ygkkkca/cert.crt"
keyHTA="/root/ygkkkca/private.key"
echo "HY2/TUIC/Naive/Anytls/Xhttp-tls将使用IP证书或域名证书的TLS"'''
    t = replace(t, upstream_block, cert_main.rstrip("\n"), "cert-main-block", 1)

    # --- https subscription display (private) ---
    # The original block printed only http IP URLs, and only when the
    # websbx process was running. It is replaced by a sync + display:
    # sync runs first, so the mode file is current for this run
    # (first install: the sub block just created the token; list:
    # a dead subscription Caddy is restarted, a stale https mode
    # falls back, so the printed URL is not dead by construction).
    # sub_https_display then prints https / http-domain / http-ip
    # URLs by mode, with the same asterisk framing as before.
    t = replace(t, 'if [ -s $HOME/agsbx/subport.log ]; then\nshowsubport=$(cat $HOME/agsbx/subport.log)\nif ps -ef 2>/dev/null | grep "$showsubport" | grep -v grep >/dev/null; then\nshowsubtoken=$(cat $HOME/agsbx/subtoken.log 2>/dev/null)\nsubip=$(cat $HOME/agsbx/server_ip.log 2>/dev/null)\nsuburl="$subip:$showsubport/$showsubtoken"\necho "**********************************************************"\necho "Clash/Mihomo本地IP订阅地址：http://$suburl/clmi.yaml"\necho "Sing-box本地IP订阅地址：http://$suburl/sbox.json"\necho "聚合协议本地IP订阅地址：http://$suburl/jhsub.txt"\necho "**********************************************************"\nfi\nfi',
                'sub_https_sync\nsub_https_display', "subhttps-display", 1)

    # --- Reality own-domain fallback (after all modules inserted) ---
    # When reym == ym, the SNI is the user's own domain: probes fall back to
    # the local web server (127.0.0.1:443) instead of the external domain.
    _rfb_old = 'export ym_vl_re=${reym:-' + chr(39)*2 + '}' + chr(10)
    _rfb_new = 'if _is_install_run "$1"; then vlpt_coexistence_check || exit 1; fi' + chr(10) + \
               'export ym_vl_re=${reym:-$ym}' + chr(10) + \
               'if [ -n "${ym_vl_re}" ] && [ "${ym_vl_re}" = "${ym}" ]; then export ym_vl_fb="127.0.0.1"; export ym_vl_fb_port="${web_port:-443}"; else export ym_vl_fb=""; export ym_vl_fb_port="443"; fi' + chr(10) + \
               'if _is_install_run "$1" && [ -n "$ym" ]; then ensure_web_server "$ym" || true; fi' + chr(10)
    t = replace(t, _rfb_old, _rfb_new, "reality-fb-var", 1)
    # hostname 允许用户自定义（节点名称后缀），不填用系统 hostname
    t = replace(t, "hostname=$(uname -a | awk '{print $2}')",
                "hostname=${hostname:-$(uname -a | awk '{print $2}')}", "hostname-override", 1)
    # 卸载时删除 /usr/local/bin/agsbx 软链
    t = replace(t, 'rm -rf  "$HOME/bin/agsbx"',
                'rm -rf  "$HOME/bin/agsbx"\nrm -f /usr/local/bin/agsbx 2>/dev/null || true', "del-symlink", 1)
    # agsbx 立即可用：root 时建 /usr/local/bin 软链
    t = insert_after(t, 'echo \'export PATH="$HOME/bin:$PATH"\' >> "$HOME/.bashrc"\n',
                     'if [ "$(id -u 2>/dev/null)" = "0" ] && [ -d /usr/local/bin ]; then ln -sf "$HOME/bin/agsbx" /usr/local/bin/agsbx 2>/dev/null || true; fi\n',
                     "agsbx-symlink")
    # 安装后提示：如果 agsbx 不在 PATH，提示 source
    t = insert_after(t, 'if [ "$(id -u 2>/dev/null)" = "0" ] && [ -d /usr/local/bin ]; then ln -sf "$HOME/bin/agsbx" /usr/local/bin/agsbx 2>/dev/null || true; fi\n',
                     'if ! command -v agsbx >/dev/null 2>&1; then echo "提示：agsbx 命令未在当前 PATH 中，请执行 \"source ~/.bashrc\" 或重新登录后再试"; fi\n',
                     "agsbx-path-hint")

    # 移除 iptables-persistent：它与 ufw 冲突会导致 ufw 被卸载，且脚本并不依赖它
    # （持久化走 ~/agsbx/ufw.rules + fwsync，netfilter-persistent save 只是清理时的 best-effort）
    t = replace(t, "printf 'iptables-persistent iptables-persistent/autosave_v4 boolean true\\niptables-persistent iptables-persistent/autosave_v6 boolean true\\n' | debconf-set-selections\n", "", "no-iptables-persistent-debconf", 1)
    t = replace(t, "apt install -y busybox coreutils util-linux iptables iptables-persistent cron openssl",
                "apt install -y busybox coreutils util-linux iptables cron openssl", "no-iptables-persistent", 1)
    # name 为空时清理残留的 ~/agsbx/name，避免旧前缀残留
    _name_old = 'if [ -n "$name" ]; then' + chr(10) + 'sxname=$name-' + chr(10) + 'echo "$sxname" > "$HOME/agsbx/name"'
    _name_new = _name_old + chr(10) + 'else' + chr(10) + 'rm -f "$HOME/agsbx/name" 2>/dev/null || true' + chr(10) + 'sxname=""'
    t = replace(t, _name_old, _name_new, "name-stale-cleanup", 1)
    t = replace(t, '"dest": "${ym_vl_re}:443"', '"dest": "${ym_vl_fb:-$ym_vl_re}:${ym_vl_fb_port:-443}"', "reality-fb-dest", 2)
    t = replace(t, '"target": "${ym_vl_re}:443"', '"target": "${ym_vl_fb:-$ym_vl_re}:${ym_vl_fb_port:-443}"', "reality-fb-target", 2)
    t = replace(t, '"server": "${ym_vl_re}"', '"server": "${ym_vl_fb:-$ym_vl_re}"', "reality-fb-handshake", 4)
    t = replace(t, '"server_port": 443\n', '"server_port": ${ym_vl_fb_port:-443}\n', "reality-fb-handshake-port", 4)
    return t
