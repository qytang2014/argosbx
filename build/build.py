#!/usr/bin/env python3
"""Build the distributable argosbx.sh from upstream + private modules.

Usage (from repo root):
    python3 build/build.py
Output: argosbx.sh, index.html and container/nodejs/start.sh (generated, do NOT edit by hand)

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
    fork_header = """        Vincent 修改版项目：
        <a href="https://github.com/qytang2014/argosbx" target="_blank">github.com/qytang2014/argosbx</a><br>"""
    h = replace(h, upstream_header, fork_header, "index-header", 1)
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
                '        <p>域名证书：由 Caddy 申请（自动：未代理用 HTTP，已代理/Argo 用 DNS；可手动选 certmode），固定目录 $HOME/agsbx/cert（软链接指向 Caddy 证书存储），超时未就绪时回落自签证书。</p>', "index-footer-acme", 1)
    h = replace(h, "const CURL = 'bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh)'",
                "const CURL = 'bash <(curl -Ls https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh)'", "index-curl", 1)
    h = replace(h, "const WGET = 'bash <(wget -qO- https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh)'",
                "const WGET = 'bash <(wget -qO- https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh)'", "index-wget", 1)
    h = replace(h, "const optIds = ['warp','ippz','uuid','reym','cfip','alns','hyjpt','cdnym','name', 'oap', 'sub', 'subid', 'subpt'];",
                "const optIds = ['warp','ippz','uuid','ym','certsrc','certmode','reym','cfip','alns','hyjpt','cdnym','name', 'oap', 'sub', 'subid', 'subpt', 'egress_nodes', 'egress_bind', 'egress_rules', 'egress_add', 'vlpt_kernel'];", "index-optids", 1)
    h = replace(h, "    document.getElementById('uuid').value = '';",
                "    document.getElementById('uuid').value = '';\n    document.getElementById('ym').value = '';\n    document.getElementById('certmode').value = '';\n    document.getElementById('certsrc').value = '';\n    document.getElementById('vlpt_kernel').value = '';", "index-reset-cert", 1)
    # --- vlpt UI: out of the Xray group, into its own dual-kernel group ---
    # Listing vlpt under "Xray可选协议" was misleading once vlpt became
    # dual-support: it is not Xray-only any more. The new first group holds
    # vlpt + its kernel select side by side (grid label + select, same as
    # the label + port rows), so the change is visible where the user
    # actually picks protocols. The select keeps id vlpt_kernel, so optIds,
    # reset, dynamic disabling and paste-back all keep working unchanged,
    # and there is exactly one such element (it is NOT also in the global
    # config card any more).
    h = replace(h, '            <label><input type="checkbox" data-proto="vlpt"> Vless-tcp-reality-vision <span class="pill">vlpt</span></label><input type="text" placeholder="留空则随机端口" data-port="vlpt">\n',
                '', "index-vlpt-out-of-xray", 1)
    h = replace(h, '        <div class="protocol-group separator">\n          <h3>Xray可选协议：</h3>',
                '''        <div class="protocol-group separator">
          <h3>双内核可选协议（Xray 与 Sing-box 都支持，默认自动单内核）：</h3>
          <div class="protocol-grid">
            <label><input type="checkbox" data-proto="vlpt"> Vless-tcp-reality-vision <span class="pill">vlpt</span></label><input type="text" placeholder="留空则随机端口" data-port="vlpt">
            <label for="vlpt_kernel">Vless-tcp-reality 内核 <span class="pill">vlpt_kernel</span></label>
            <select id="vlpt_kernel">
              <option value="">默认 自动（只剩 Sing-box 时走 Sing-box，否则 Xray；旧安装下次更新即迁移，链接会变）</option>
              <option value="xray">强制 Xray（明确选 Xray 时不迁移，旧链接保留）</option>
              <option value="sb">强制 Sing-box</option>
            </select>
          </div>
        </div>
        <div class="protocol-group separator">
          <h3>Xray可选协议：</h3>''', "index-vlpt-dual-group", 1)
    h = replace(h, """      const isRealityEnabled = vlessTcpRealityCheckbox.checked || vlessXhttpRealityCheckbox.checked || anyRealityCheckbox.checked;
      reymInput.disabled = !isRealityEnabled;
      if (!isRealityEnabled) reymInput.value = '';""",
                """      const isRealityEnabled = vlessTcpRealityCheckbox.checked || vlessXhttpRealityCheckbox.checked || anyRealityCheckbox.checked;
      reymInput.disabled = !isRealityEnabled;
      if (!isRealityEnabled) reymInput.value = '';
      const vlptKernelSelect = document.getElementById('vlpt_kernel');
      if (vlptKernelSelect) {
        vlptKernelSelect.disabled = !vlessTcpRealityCheckbox.checked;
        if (!vlessTcpRealityCheckbox.checked) vlptKernelSelect.value = '';
      }""", "index-vlpt-kernel-dynamic", 1)
    h = replace(h, "    document.getElementById('name').value = '';",
                "    document.getElementById('name').value = '';\n    document.getElementById('egress_nodes').value = '';\n    document.getElementById('egress_bind').value = '';\n    document.getElementById('egress_rules').value = '';\n    document.getElementById('egress_add').value = '';", "index-reset-egress", 1)
    h = replace(h, """  generateUuidBtn.addEventListener('click', () => {
    uuidInput.value = crypto.randomUUID();
    render();
  });""",
                """  generateUuidBtn.addEventListener('click', () => {
    uuidInput.value = crypto.randomUUID();
    render();
  });
  ['egress_nodes', 'egress_bind', 'egress_rules', 'egress_add'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.addEventListener('input', render);
  });""", "index-egress-listeners", 1)
    h = replace(h, """    optIds.forEach(id => {
      const el = document.getElementById(id);
      const v = (el.value || '').trim();""",
                """    optIds.forEach(id => {
      const el = document.getElementById(id);
      let v = (el.value || '').trim();
      if (id === 'egress_nodes' || id === 'egress_rules' || id === 'egress_add') {
        v = v.split(/\\r?\\n/).map(s => s.trim()).filter(Boolean).join(';');
      }""", "index-collect-egress", 1)
    h = replace(h, "    ['warp', 'uuid', 'reym', 'cfip', 'alns', 'hyjpt', 'cdnym', 'name', 'ippz', 'sub', 'subid', 'subpt'].forEach(k => { if (keys.includes(k)) ordered.push(k); });",
                "    ['warp', 'uuid', 'ym', 'certsrc', 'certmode', 'vlpt_kernel', 'reym', 'cfip', 'alns', 'hyjpt', 'cdnym', 'name', 'ippz', 'sub', 'subid', 'subpt', 'egress_nodes', 'egress_bind', 'egress_rules', 'egress_add'].forEach(k => { if (keys.includes(k)) ordered.push(k); });", "index-tobash-order", 1)
    h = replace(h, '<button class="command-button" data-command="rep">调整并更新脚本（注:所有变量设置完成后再点击）：rep</button>',
                '<button class="command-button" data-command="rep">调整并更新脚本（注:所有变量设置完成后再点击）：rep</button>\n          <button class="command-button" data-command="add">增量更新（只传本次新增/修改，未传的沿用上次安装）：add</button>', "index-add-button", 1)
    h = replace(h, "      if (command === 'rep') {",
                "      if (command === 'rep' || command === 'add') {", "index-add-handler", 1)
    h = replace(h, "output.value = (vars ? vars + ' ' : '') + selectedCommand + ' rep';",
                "output.value = (vars ? vars + ' ' : '') + selectedCommand + ' ' + command;", "index-add-output", 1)
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
    vars_mod = read("modules/vars.sh")

    # --- identity: script URL only (binary download URLs stay upstream) ---
    t = replace(t, "url='https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh'",
                "url='https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh'", "script-url", 1)
    t = replace(t, 'agsbxurl="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"',
                'agsbxurl="https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh"', "agsbxurl", 1)
    t = replace(t, "echo \"主脚本：bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh) 或 bash <(wget -qO- https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh)\"",
                "echo \"主脚本：bash <(curl -Ls https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh) 或 bash <(wget -qO- https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh)\"", "showmode-main-url", 1)
    t = replace(t, "https://yonggekkk.github.io/argosbx/", "https://qytang2014.github.io/argosbx/", "generator-url", 1)
    t = replace(t, 'echo "甬哥Github项目 ：github.com/yonggekkk"\necho "甬哥Blogger博客 ：ygkkk.blogspot.com"\necho "甬哥YouTube频道 ：www.youtube.com/@ygkkk"', 'echo "项目地址：github.com/qytang2014/argosbx"', "banner-project-url", 1)
    t = replace(t, 'echo "欢迎继续使用甬哥侃侃侃ygkkk的Argosbx一键无交互小钢炮脚本💣" && sleep 2', 'echo "欢迎继续使用Argosbx一键无交互小钢炮脚本💣" && sleep 2', "farewell-line", 1)
    t = replace(t, "echo \"申请本地IP域名证书脚本：bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)\"",
                "echo \"域名证书：由 Caddy 或 acme.sh 申请（certsrc 自动：低内存走 acme，否则走 Caddy；certmode 自动：未代理用 HTTP，已代理/Argo 用 DNS），固定目录 $HOME/agsbx/cert\"", "showmode-acme-line", 1)

    # --- incremental update module (top, before sh.txt save + protocol selection) ---
    t = insert_after(t, 'mkdir -p "$HOME/agsbx"\n',
                     vars_mod + 'vars_merge "$1"\n', "vars-module-anchor")
    # --- variable lists ---
    t = replace(t, "for v in uuid vlpt vmpt vwpt hypt tupt xhpt vxpt anpt arpt sspt sopt nvpt xupt xcpt reym cdnym argo agn agk warp name oap; do",
                "for v in uuid vlpt vmpt vwpt hypt tupt xhpt vxpt anpt arpt sspt sopt nvpt xupt xcpt reym cdnym argo agn agk warp name oap ym alns certmode certsrc vlpt_kernel egress_nodes egress_bind egress_rules egress_add cfip hyjpt ippz sub subid subpt; do", "export-list", 1)
    t = replace(t, 'export alns=\\"${alns}\\" ',
                'export alns=\\"${alns}\\" ym=\\"${ym}\\" certmode=\\"${certmode}\\" certsrc=\\"${certsrc}\\" vlpt_kernel=\\"${vlpt_kernel}\\" egress_nodes=\\"${egress_nodes}\\" egress_bind=\\"${egress_bind}\\" egress_rules=\\"${egress_rules}\\" ', "recovery-line", 1)

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
    t = replace(t, 'if [ "$nvp" != yes ] && [ "$tup" != yes ] && [ "$anp" != yes ] && [ "$arp" != yes ] && [ "$ssp" != yes ]; then',
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
    t = replace(t, 'short_id_s=$(cat "$HOME/agsbx/sbk/short_id" 2>/dev/null)\nsskey=$(cat "$HOME/agsbx/sskey" 2>/dev/null)',
                'short_id_s=$(cat "$HOME/agsbx/sbk/short_id" 2>/dev/null)\nsskey=$(cat "$HOME/agsbx/sskey" 2>/dev/null)\nif grep -q "vl-reality-sb" "$HOME/agsbx/sb.json" 2>/dev/null; then vlpt_pbk="$public_key_s"; vlpt_sid="$short_id_s"; else vlpt_pbk="$public_key_x"; vlpt_sid="$short_id_x"; fi', "vlpt-display-pbk", 1)
    t = replace(t, 'if grep reality-vision "$HOME/agsbx/xr.json" >/dev/null 2>&1; then',
                'if grep reality-vision "$HOME/agsbx/xr.json" >/dev/null 2>&1 || grep vl-reality-sb "$HOME/agsbx/sb.json" >/dev/null 2>&1; then', "vlpt-display-guard", 1)
    t = replace(t, 'vl_link="vless://$uuid@$server_ip:$port_vl_re?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$ym_vl_re&fp=chrome&pbk=$public_key_x&sid=$short_id_x&type=tcp&headerType=none',
                'vl_link="vless://$uuid@$server_ip:$port_vl_re?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$ym_vl_re&fp=chrome&pbk=$vlpt_pbk&sid=$vlpt_sid&type=tcp&headerType=none', "vlpt-link-pbk", 1)
    t = replace(t, '          "public_key": "$public_key_x",\n          "short_id": "$short_id_x"',
                '          "public_key": "$vlpt_pbk",\n          "short_id": "$vlpt_sid"', "vlpt-sb-config-pbk", 1)
    t = replace(t, '    public-key: $public_key_x    \n    short-id: $short_id_x',
                '    public-key: $vlpt_pbk    \n    short-id: $vlpt_sid', "vlpt-clash-pbk", 1)

    # --- cert module insertion (after cdnym export, before argo export) ---
    t = insert_after(t, "export cdnym=${cdnym:-''}\n", cert, "cert-module-anchor")
    # --- cert-watch module (right after cert module) ---
    t = t.replace(cert, cert + cert_watch, 1)
    t = replace(t, 'echo "更新脚本命令：原已安装的自定义各种协议变量组 主脚本 rep"', 'echo "更新脚本命令：原已安装的自定义各种协议变量组 主脚本 rep"\necho "增量更新命令：只传新增/修改的协议变量组 主脚本 add（未传的变量沿用上次安装，删协议仍用 rep）"', "showmode-add-line", 1)
    # --- egress exports (after warp export) ---
    t = insert_after(t, "export warp=${warp:-''}\n",
                     "export egress_nodes=${egress_nodes:-''}\nexport egress_bind=${egress_bind:-''}\nexport egress_rules=${egress_rules:-''}\nexport egress_add=${egress_add:-''}\n", "egress-exports-anchor")

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
    # grep ygkkkca -> agsbx/cert
    # --- unified cert paths: self-signed -> agsbx/selfsigned ---
    t = replace(t, 'ins\nif [ -n "$sub" ]; then',
                'ins\nvars_save\nif [ -n "$sub" ]; then', "vars-save-call", 1)
    t = replace(t, 'if [ ! -f "$HOME/agsbx/SHA256.txt" ]; then',
                'cert_migrate_paths\nif [ ! -f "$HOME/agsbx/SHA256.txt" ]; then', "selfsigned-migrate-call", 1)
    t = replace(t, 'command -v openssl >/dev/null 2>&1 && openssl ecparam -genkey -name prime256v1 -out "$HOME/agsbx/private.key"',
                'mkdir -p "$HOME/agsbx/selfsigned" 2>/dev/null || true\ncommand -v openssl >/dev/null 2>&1 && openssl ecparam -genkey -name prime256v1 -out "$HOME/agsbx/selfsigned/private.key"', "selfsigned-gen-key", 1)
    t = replace(t, 'openssl req -new -x509 -days 36500 -key "$HOME/agsbx/private.key" -out "$HOME/agsbx/cert.crt"',
                'openssl req -new -x509 -days 36500 -key "$HOME/agsbx/selfsigned/private.key" -out "$HOME/agsbx/selfsigned/cert.crt"', "selfsigned-gen-cert", 1)
    t = replace(t, 'openssl x509 -in $HOME/agsbx/cert.crt -outform DER',
                'openssl x509 -in $HOME/agsbx/selfsigned/cert.crt -outform DER', "selfsigned-sha256", 1)
    t = replace(t, 'certificateHTA="$HOME/agsbx/cert.crt"', 'certificateHTA="$HOME/agsbx/selfsigned/cert.crt"', "selfsigned-hta-cert", 1)
    t = replace(t, 'keyHTA="$HOME/agsbx/private.key"', 'keyHTA="$HOME/agsbx/selfsigned/private.key"', "selfsigned-hta-key", 1)
    t = replace(t, "if grep -q 'agsbx/private.key' \"$HOME/agsbx/sb.json\" >/dev/null 2>&1 || grep -q 'agsbx/private.key' \"$HOME/agsbx/xr.json\" >/dev/null 2>&1; then",
                "if grep -q 'agsbx/selfsigned/private.key' \"$HOME/agsbx/sb.json\" >/dev/null 2>&1 || grep -q 'agsbx/selfsigned/private.key' \"$HOME/agsbx/xr.json\" >/dev/null 2>&1; then", "selfsigned-display-grep", 1)

    n2 = t.count("'ygkkkca'")
    t = t.replace("'ygkkkca'", "'agsbx/cert'")
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
                'xrsbout(){\negress_init\negress_geo_setup\nif [ -e "$HOME/agsbx/xr.json" ]; then', "egress-init-call", 1)
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
    build_container()

def build_container():
    c = read("upstream/container/nodejs/start.sh")
    container_cert = read("modules/container-cert.sh")
    container_vars = read("modules/container-vars.sh")
    domain_addr = read("modules/reality-addr.sh")
    c = replace(c, "export LANG=en_US.UTF-8\n", "export LANG=en_US.UTF-8\n" + container_vars + "container_vars_merge\n", "container-vars-module", 1)
    c = replace(c, 'echo "甬哥Github项目 ：github.com/yonggekkk"\necho "甬哥Blogger博客 ：ygkkk.blogspot.com"\necho "甬哥YouTube频道 ：www.youtube.com/@ygkkk"', 'echo "项目地址：github.com/qytang2014/argosbx"', "container-banner-project-url", 1)
    c = replace(c, 'echo "Argosbx脚本项目地址：https://github.com/yonggekkk/argosbx"',
                'echo "Argosbx脚本项目地址：https://github.com/qytang2014/argosbx"', "container-project-link", 1)
    c = replace(c, "export name=${name}", "export name=${name}\nexport ym=${ym}\nexport vlpt_kernel=${vlpt_kernel}", "container-ym-export", 1)
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
    display_tls = """if [ "$(cat "$HOME/agsbx/domain_cert_ready" 2>/dev/null)" = "1" ] && [ -s "$HOME/agsbx/ym" ]; then add=$(cat "$HOME/agsbx/ym" 2>/dev/null); sni="$add"; tls_ins=0; else add="$server_ip"; sni="www.bing.com"; tls_ins=1; fi"""
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
                'hy2_link="hysteria2://$uuid@$add:$hypt?security=tls&alpn=h3&insecure=$tls_ins&sni=$sni', "container-tls-hy2", 1)
    c = replace(c, 'tuic5_link="tuic://$uuid:$uuid@$server_ip:$tupt?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1&allowInsecure=1',
                'tuic5_link="tuic://$uuid:$uuid@$add:$tupt?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$sni&allow_insecure=$tls_ins&allowInsecure=$tls_ins', "container-tls-tuic", 1)
    c = replace(c, 'an_link="anytls://$uuid@$server_ip:$anpt?insecure=1&allowInsecure=1',
                'an_link="anytls://$uuid@$add:$anpt?insecure=$tls_ins&allowInsecure=$tls_ins', "container-tls-any", 1)
    c = replace(c, 'echo "客户端地址：$server_ip"', 'echo "客户端地址：$domain_addr"', "container-socks5-addr", 1)
    # --- egress parity (final egress module, same as main script) ---
    egress_mod = read("modules/egress.sh")
    c = replace(c, "export ym=${ym}", "export ym=${ym}\nexport egress_nodes=${egress_nodes}\nexport egress_bind=${egress_bind}\nexport egress_rules=${egress_rules}\nexport egress_add=${egress_add}", "container-egress-exports", 1)
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
                '       {\n        "action": "resolve",\n         "strategy": "${sbyx}"\n       },\n${egress_sb_rules}      {', "container-sb-routing-hook", 1)
    c = replace(c, 'fi\nif [ -n "$argo" ]; then\necho\necho "=========启用Cloudflared-argo内核========="',
                'fi\ncontainer_vars_save\nif [ -n "$argo" ]; then\necho\necho "=========启用Cloudflared-argo内核========="', "container-vars-save", 1)
    lines = c.split("\n", 1)
    assert lines[0] == "#!/bin/sh"
    out = lines[0] + "\n# GENERATED BY build/build.py - DO NOT EDIT BY HAND - sources: upstream/container/nodejs/start.sh + modules/container-cert.sh + modules/reality-addr.sh + modules/egress.sh\n" + lines[1]
    (ROOT / "container/nodejs/start.sh").write_text(out)
    print(f"Built container/nodejs/start.sh: {len(out)} bytes, {out.count(chr(10))} lines")


if __name__ == "__main__":
    main()
