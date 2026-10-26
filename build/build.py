#!/usr/bin/env python3
"""Build the distributable argosbx.sh from upstream + private modules.

Usage (from repo root):
    python3 build/build.py
Output: argosbx.sh and index.html (generated, do NOT edit by hand)

Rules:
- upstream/argosbx.sh is pristine upstream, never edited by hand.
  To sync upstream: replace that file, rerun this script, and fix only
  the anchors it reports as missing.
- modules/*.sh are private features, edited here, never in argosbx.sh.
- Every patch below is an anchor replacement with an expected count.
  If an anchor is missing (upstream changed that line), the build
  FAILS with the anchor name, instead of silently producing a broken
  script. That is the whole point: upstream drift is reported, not
  silently merged.
- The generated file is byte-identical to the previous hand-edited
  private version except for the GENERATED header line after the
  shebang. Verify with: diff <(tail -n +3 argosbx.sh) <previous-private>
  (line 1 = shebang, line 2 = generated header).
"""
import pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

def read(p):
    return (ROOT / p).read_text()

def replace(t, old, new, name, expected=None):
    n = t.count(old)
    if expected is not None and n != expected:
        print(f"BUILD FAIL: {name}: expected {expected} occurrence(s), found {n}", file=sys.stderr)
        sys.exit(1)
    if n == 0:
        print(f"BUILD FAIL: anchor missing: {name}", file=sys.stderr)
        sys.exit(1)
    return t.replace(old, new)

def insert_after(t, anchor, text, name):
    if anchor not in t:
        print(f"BUILD FAIL: anchor missing: {name}", file=sys.stderr)
        sys.exit(1)
    return t.replace(anchor, anchor + text, 1)

def build_index():
    # Upstream index.html is CRLF; private built file is LF (browsers
    # accept both, and all private edits were made in LF). Normalize
    # first, then apply patches, so the built file matches private LF.
    h = read("upstream/index.html").replace("\r\n", "\n")
    cert_ui = read("modules/index-cert.html")
    egress_ui = read("modules/index-egress.html")
    h = replace(h, "<title>ArgoSBX一键SSH命令生成器-甬哥ygkkk</title>",
                "<title>ArgoSBX一键SSH命令生成器-Vincent</title>", "index-title", 1)
    upstream_header = """        甬哥Github项目：
        <a href="https://github.com/yonggekkk" target="_blank">github.com/yonggekkk</a><br>
        甬哥Blogger博客：
        <a href="https://ygkkk.blogspot.com" target="_blank">ygkkk.blogspot.com</a><br>
        甬哥YouTube频道：
        <a href="https://www.youtube.com/@ygkkk" target="_blank">www.youtube.com/@ygkkk</a><br>
        甬哥最新动态推特X：
        <a href="https://x.com/ygkkkg" target="_blank">x.com/ygkkkg</a><br>"""
    private_header = """        Vincent 的私人版本项目：
        <a href="https://github.com/qytang2014/argosbx" target="_blank">github.com/qytang2014/argosbx</a><br>"""
    h = replace(h, upstream_header, private_header, "index-header", 1)
    h = insert_after(h, '        <div class="row"><label>Reality 域名', cert_ui, "index-cert-ui") if False else h
    # Insert cert UI before reym row (anchor is the reym row start)
    if '        <div class="row"><label>Reality 域名' not in h:
        print("BUILD FAIL: anchor missing: index-cert-ui", file=sys.stderr); sys.exit(1)
    h = h.replace('        <div class="row"><label>Reality 域名', cert_ui + '        <div class="row"><label>Reality 域名', 1)
    h = replace(h, '<option value="y">开启 (HY2/TUIC/Naive/Anytls/Xhttp-tls为域名IP证书TLS)</option>',
                '<option value="y">开启 (HY2/TUIC/Naive/Anytls/Xhttp-tls为 Caddy 域名证书TLS，需配合节点域名 ym)</option>', "index-alns-text", 1)
    if '        <div class="row"><label>IPv4/IPv6 配置导出' not in h:
        print("BUILD FAIL: anchor missing: index-egress-ui", file=sys.stderr); sys.exit(1)
    h = h.replace('        <div class="row"><label>IPv4/IPv6 配置导出', egress_ui + '        <div class="row"><label>IPv4/IPv6 配置导出', 1)
    h = replace(h, '<p style="margin-top: 10px;">相关细节说明，请参考ArgoSBX小钢炮脚本项目💣：<a href="https://github.com/yonggekkk/argosbx" target="_blank">github.com/yonggekkk/argosbx</a></p>',
                '<p style="margin-top: 10px;">相关细节说明，请参考ArgoSBX小钢炮脚本项目💣：<a href="https://github.com/qytang2014/argosbx" target="_blank">github.com/qytang2014/argosbx</a></p>', "index-footer-link", 1)
    h = replace(h, 'Acme-yg域名IP证书脚本：bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)</a></p>',
                '        <p>域名证书：由 Caddy 申请（自动：未代理用 HTTP，已代理/Argo 用 DNS；可手动选 certmode），固定目录 $HOME/argosbx/cert（软链接指向 Caddy 证书存储），超时未就绪时回落自签证书。</p>', "index-footer-acme", 1)
    h = replace(h, "const CURL = 'bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh)'",
                "const CURL = 'bash <(curl -Ls https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh)'", "index-curl", 1)
    h = replace(h, "const WGET = 'bash <(wget -qO- https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh)'",
                "const WGET = 'bash <(wget -qO- https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh)'", "index-wget", 1)
    h = replace(h, "const optIds = ['warp','ippz','uuid','reym','cfip','alns','hyjpt','cdnym','name', 'oap', 'sub', 'subid', 'subpt'];",
                "const optIds = ['warp','ippz','uuid','ym','certsrc','certmode','reym','cfip','alns','hyjpt','cdnym','name', 'oap', 'sub', 'subid', 'subpt', 'egress_nodes', 'egress_bind', 'egress_rules'];", "index-optids", 1)
    h = replace(h, "    document.getElementById('uuid').value = '';",
                "    document.getElementById('uuid').value = '';\n    document.getElementById('ym').value = '';\n    document.getElementById('certmode').value = '';\n    document.getElementById('certsrc').value = '';", "index-reset-cert", 1)
    h = replace(h, "    document.getElementById('name').value = '';",
                "    document.getElementById('name').value = '';\n    document.getElementById('egress_nodes').value = '';\n    document.getElementById('egress_bind').value = '';\n    document.getElementById('egress_rules').value = '';", "index-reset-egress", 1)
    h = replace(h, """  generateUuidBtn.addEventListener('click', () => {
    uuidInput.value = crypto.randomUUID();
    render();
  });""",
                """  generateUuidBtn.addEventListener('click', () => {
    uuidInput.value = crypto.randomUUID();
    render();
  });
  ['egress_nodes', 'egress_bind', 'egress_rules'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.addEventListener('input', render);
  });""", "index-egress-listeners", 1)
    h = replace(h, """    optIds.forEach(id => {
      const el = document.getElementById(id);
      const v = (el.value || '').trim();""",
                """    optIds.forEach(id => {
      const el = document.getElementById(id);
      let v = (el.value || '').trim();
      if (id === 'egress_nodes' || id === 'egress_rules') {
        v = v.split(/\\r?\\n/).map(s => s.trim()).filter(Boolean).join(';');
      }""", "index-collect-egress", 1)
    h = replace(h, "    ['warp', 'uuid', 'reym', 'cfip', 'alns', 'hyjpt', 'cdnym', 'name', 'ippz', 'sub', 'subid', 'subpt'].forEach(k => { if (keys.includes(k)) ordered.push(k); });",
                "    ['warp', 'uuid', 'ym', 'certsrc', 'certmode', 'reym', 'cfip', 'alns', 'hyjpt', 'cdnym', 'name', 'ippz', 'sub', 'subid', 'subpt', 'egress_nodes', 'egress_bind', 'egress_rules'].forEach(k => { if (keys.includes(k)) ordered.push(k); });", "index-tobash-order", 1)
    lines = h.split("\n", 1)
    out = lines[0] + "\n<!-- GENERATED BY build/build.py - DO NOT EDIT BY HAND - sources: upstream/index.html + modules/index-*.html -->\n" + lines[1]
    (ROOT / "index.html").write_text(out)
    print(f"Built index.html: {len(out)} bytes, {out.count(chr(10))} lines")


def main():
    t = read("upstream/argosbx.sh")
    cert = read("modules/cert.sh")
    egress = read("modules/egress.sh")
    cert_main = read("modules/cert-main.sh")
    cert_watch = read("modules/cert-watch.sh")

    # --- identity: script URL only (binary download URLs stay upstream) ---
    t = replace(t, "url='https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh'",
                "url='https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh'", "script-url", 1)
    t = replace(t, 'agsbxurl="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"',
                'agsbxurl="https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh"', "agsbxurl", 1)
    t = replace(t, "echo \"主脚本：bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh) 或 bash <(wget -qO- https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh)\"",
                "echo \"主脚本：bash <(curl -Ls https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh) 或 bash <(wget -qO- https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh)\"", "showmode-main-url", 1)
    t = replace(t, "echo \"申请本地IP域名证书脚本：bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)\"",
                "echo \"域名证书：由 Caddy 或 acme.sh 申请（certsrc 自动：低内存走 acme，否则走 Caddy；certmode 自动：未代理用 HTTP，已代理/Argo 用 DNS），固定目录 $HOME/argosbx/cert\"", "showmode-acme-line", 1)

    # --- variable lists ---
    t = replace(t, "for v in uuid vlpt vmpt vwpt hypt tupt xhpt vxpt anpt arpt sspt sopt nvpt xupt xcpt reym cdnym argo agn agk warp name oap; do",
                "for v in uuid vlpt vmpt vwpt hypt tupt xhpt vxpt anpt arpt sspt sopt nvpt xupt xcpt reym cdnym argo agn agk warp name oap ym alns certmode certsrc egress_nodes egress_bind egress_rules; do", "export-list", 1)
    t = replace(t, 'export alns=\\"${alns}\\" ',
                'export alns=\\"${alns}\\" ym=\\"${ym}\\" certmode=\\"${certmode}\\" certsrc=\\"${certsrc}\\" egress_nodes=\\"${egress_nodes}\\" egress_bind=\\"${egress_bind}\\" egress_rules=\\"${egress_rules}\\" ', "recovery-line", 1)

    # --- cert module insertion (after cdnym export, before argo export) ---
    t = insert_after(t, "export cdnym=${cdnym:-''}\n", cert, "cert-module-anchor")
    # --- cert-watch module (right after cert module) ---
    t = t.replace(cert, cert + cert_watch, 1)
    # --- egress exports (after warp export) ---
    t = insert_after(t, "export warp=${warp:-''}\n",
                     "export egress_nodes=${egress_nodes:-''}\nexport egress_bind=${egress_bind:-''}\nexport egress_rules=${egress_rules:-''}\n", "egress-exports-anchor")

    # --- cert usage replacements (upstream ygkkkca -> private cert dir / ym) ---
    t = replace(t, 'if [ -s "/root/ygkkkca/private.key" ] && [ -n "$nvp" ]; then',
                'if [ "$domain_cert_ready" = "1" ] && [ -n "$nvp" ]; then', "naive-condition", 1)
    t = replace(t, '"certificate_path": "/root/ygkkkca/cert.crt",', '"certificate_path": "$CERT_CRT",', "cert-path", 1)
    t = replace(t, '"key_path": "/root/ygkkkca/private.key"', '"key_path": "$CERT_KEY"', "key-path", 1)
    # ca.log (domain) -> ym file, all occurrences (path replaced with quoted path)
    n = t.count("/root/ygkkkca/ca.log")
    t = t.replace("/root/ygkkkca/ca.log", '"$HOME/agsbx/ym"')
    if n == 0:
        print("BUILD FAIL: anchor missing: ca.log", file=sys.stderr); sys.exit(1)
    print(f"ca.log replacements: {n}")
    # Quoted replacement is correct for both upstream forms:
    #   $(cat /root/ygkkkca/ca.log ...) -> $(cat "$HOME/agsbx/ym" ...)
    #   "$(cat /root/ygkkkca/ca.log ...)" -> "$(cat "$HOME/agsbx/ym" ...)"
    # Do NOT strip outer quotes: the naive sb.json server/server_name fields
    # need them to stay valid JSON at runtime.
    # grep ygkkkca -> argosbx/cert
    n2 = t.count("'ygkkkca'")
    t = t.replace("'ygkkkca'", "'argosbx/cert'")
    if n2 == 0:
        print("BUILD FAIL: anchor missing: grep-ygkkkca", file=sys.stderr); sys.exit(1)
    print(f"grep ygkkkca replacements: {n2}")

    # --- egress module insertion (before xrsbout) + hooks ---
    t = insert_after(t, "\nxrsbout(){", "\n" + egress + "\nxrsbout(){", "egress-module-anchor") if False else t
    # The above line is intentionally not used; do the insertion properly:
    if "\n" + egress + "\nxrsbout(){" not in t:
        t = t.replace("\nxrsbout(){", "\n" + egress + "\nxrsbout(){", 1)
    # --- top command-save exclusion: certwatch/certrestart must not overwrite sh.txt ---
    t = replace(t, 'case "${*##* }" in list|del|upx|ups|upa|res) ;; *)',
                'case "${*##* }" in list|del|upx|ups|upa|res|certwatch|certrestart) ;; *)', "top-case-exclusion", 1)
    # --- certwatch/certrestart subcommands + del cleanup ---
    t = replace(t, 'if [ "$1" = "del" ]; then\ncleandel',
                'if [ "$1" = "certwatch" ]; then\ncert_watch\nexit\nfi\nif [ "$1" = "certrestart" ]; then\ncert_restart\nexit\nfi\nif [ "$1" = "del" ]; then\ncert_remove_watch\ncleandel', "certwatch-dispatch", 1)
    t = replace(t, 'xrsbout(){\nif [ -e "$HOME/agsbx/xr.json" ]; then',
                'xrsbout(){\negress_init\nif [ -e "$HOME/agsbx/xr.json" ]; then', "egress-init-call", 1)
    t = replace(t, '  "outbounds": [\n    {\n      "protocol": "freedom",\n      "tag": "direct",',
                '  "outbounds": [\n${egress_xr_outbounds}    {\n      "protocol": "freedom",\n      "tag": "direct",', "xr-outbounds-hook", 1)
    t = replace(t, '  "outbounds": [\n    {\n      "type": "direct",\n      "tag": "direct"\n    }\n  ],',
                '  "outbounds": [\n${egress_sb_outbounds}    {\n      "type": "direct",\n      "tag": "direct"\n    }\n  ],', "sb-outbounds-hook", 1)
    t = replace(t, '    "rules": [\n      {\n        "type": "field",\n        "ip": [ ${xip} ],',
                '    "rules": [\n${egress_xr_rules}      {\n        "type": "field",\n        "ip": [ ${xip} ],', "xr-routing-hook", 1)
    t = replace(t, '       {\n        "action": "resolve",\n         "strategy": "${sbyx}"\n       },\n      {\n        "ip_cidr": [ ${sip} ],',
                '       {\n        "action": "resolve",\n         "strategy": "${sbyx}"\n       },\n${egress_sb_rules}      {\n        "ip_cidr": [ ${sip} ],', "sb-routing-hook", 1)

    # --- Reality address: domain (ym) when set, IP otherwise; SNI stays reym ---
    reality_addr = read("modules/reality-addr.sh")
    t = replace(t, 'ym_vl_re=$(cat "$HOME/agsbx/ym_vl_re" 2>/dev/null)\nif [ -e "$HOME/agsbx/xray" ]; then',
                'ym_vl_re=$(cat "$HOME/agsbx/ym_vl_re" 2>/dev/null)\n' + reality_addr + 'if [ -e "$HOME/agsbx/xray" ]; then', "reality-addr-insert", 1)
    t = replace(t, 'vl_xh_link="vless://$uuid@$server_ip:$port_xh?',
                'vl_xh_link="vless://$uuid@$reality_addr:$port_xh?', "reality-xhttp-link", 1)
    t = replace(t, 'vl_link="vless://$uuid@$server_ip:$port_vl_re?',
                'vl_link="vless://$uuid@$reality_addr:$port_vl_re?', "reality-tcp-link", 1)
    t = replace(t, 'ar_link="anytls://$uuid@$server_ip:$port_ar?',
                'ar_link="anytls://$uuid@$reality_addr:$port_ar?', "reality-any-link", 1)
    # sing-box client config for vless-reality (sbvlpt): server field only in that function
    t = replace(t, '      "tag": "${sxname}vless-$hostname",\n      "server": "$server_ip",',
                '      "tag": "${sxname}vless-$hostname",\n      "server": "$reality_addr",', "reality-sb-config", 1)
    # clash client config for vless-reality (clvlpt)
    t = replace(t, '- name: ${sxname}vless-reality-vision-$hostname               \n  type: vless\n  server: $server_ip',
                '- name: ${sxname}vless-reality-vision-$hostname               \n  type: vless\n  server: $reality_addr', "reality-clash-config", 1)
    # sing-box client config for any-reality (sbarpt)
    t = replace(t, '        "tag": "${sxname}any-reality-$hostname",\n        "server": "$server_ip",',
                '        "tag": "${sxname}any-reality-$hostname",\n        "server": "$reality_addr",', "reality-any-sb-config", 1)

    # --- non-TLS protocols: domain address (ym) when set, IP otherwise ---
    t = replace(t, 'vl_vx_link="vless://$uuid@$server_ip:$port_vx?',
                'vl_vx_link="vless://$uuid@$domain_addr:$port_vx?', "plain-xhttp-enc-link", 1)
    t = replace(t, 'vl_vw_link="vless://$uuid@$server_ip:$port_vw?',
                'vl_vw_link="vless://$uuid@$domain_addr:$port_vw?', "plain-ws-enc-link", 1)
    t = replace(t, '2022-blake3-aes-128-gcm:$sskey@$server_ip:$port_ss',
                '2022-blake3-aes-128-gcm:$sskey@$domain_addr:$port_ss', "plain-ss-link", 1)
    t = replace(t, '\\\"add\\\": \\\"$server_ip\\\", \\\"port\\\": \\\"$port_vm_ws\\\"',
                '\\\"add\\\": \\\"$domain_addr\\\", \\\"port\\\": \\\"$port_vm_ws\\\"', "plain-vm-link", 1)
    t = replace(t, '      "tag": "${sxname}Shadowsocks-2022-$hostname",\n       "server": "$server_ip",',
                '      "tag": "${sxname}Shadowsocks-2022-$hostname",\n       "server": "$domain_addr",', "plain-ss-sb-config", 1)
    t = replace(t, '- name: "${sxname}Shadowsocks-2022-$hostname"\n  type: ss\n  server: $server_ip',
                '- name: "${sxname}Shadowsocks-2022-$hostname"\n  type: ss\n  server: $domain_addr', "plain-ss-clash-config", 1)
    t = replace(t, '            "server": "$server_ip",\n            "server_port": $port_vm_ws,',
                '            "server": "$domain_addr",\n            "server_port": $port_vm_ws,', "plain-vm-sb-config", 1)
    t = replace(t, '- name: ${sxname}vmess-ws-$hostname                         \n  type: vmess\n  server: $server_ip',
                '- name: ${sxname}vmess-ws-$hostname                         \n  type: vmess\n  server: $domain_addr', "plain-vm-clash-config", 1)

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

    # --- generated header (after shebang) ---
    lines = t.split("\n", 1)
    assert lines[0] == "#!/bin/bash"
    out = lines[0] + "\n# GENERATED BY build/build.py - DO NOT EDIT BY HAND - sources: upstream/argosbx.sh + modules/*.sh\n" + lines[1]
    (ROOT / "argosbx.sh").write_text(out)
    print(f"Built argosbx.sh: {len(out)} bytes, {out.count(chr(10))} lines")
    build_index()

if __name__ == "__main__":
    main()
