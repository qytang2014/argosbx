"""Generator builder — moved verbatim from build/build.py."""
import sys
from . import util
from .util import ROOT, insert_after, read, replace

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
    h = replace(h, '<input id="reym" type="text" placeholder="选择Reality相关协议后可用，留空默认apple.com" disabled/>', '<input id="reym" type="text" placeholder="选择Reality相关协议后可用，留空自动探测；填自有域名且与 ym 相同→探测回落本机443" disabled/>', "index-reym-hint", 1)
    h = replace(h, '<option value="y">开启 (HY2/TUIC/Naive/Anytls/Xhttp-tls为域名IP证书TLS)</option>',
                '<option value="y">开启 (HY2/TUIC/Naive/Anytls/Xhttp-tls为域名证书TLS，需配合节点域名 ym)</option>', "index-alns-text", 1)
    # alns closed option in upstream omits Naive while the enabled
    # option includes it; align both, and drop the Caddy-only wording
    # from the enabled option above (the cert may be Caddy-issued
    # or acme-issued, both land in the same cert dir).
    h = replace(h, '<option value="">默认 关闭 (HY2/TUIC/Anytls/Xhttp-tls为自签证书TLS)</option>',
                '<option value="">默认 关闭 (HY2/TUIC/Naive/Anytls/Xhttp-tls为自签证书TLS)</option>', "index-alns-closed-naive", 1)
    # --- layout (user clarified 2026-10-27): left protocols, right
    # global/Argo/subscription, egress full width second row ---
    # Previously egress was inside outbound-warp, which made that
    # card the tallest and forced the left protocol card (spanning
    # 3 rows) to stretch, leaving a large blank inside it. The first
    # fix moved egress to the left, which left the right column
    # short; the user then specified this layout, which they judge
    # least empty on their screen: protocols alone on the left,
    # global, Argo, then subscription stacked on the right, and
    # egress as a full-width row below both. Upstream DOM order is
    # protocols, global, subscription, Argo, shortcut, out, so swap
    # subscription and Argo, then put egress after subscription, so
    # the DOM order (and the mobile stack order) is: protocols,
    # global, Argo, subscription, egress, commands, output.
    # Subscription is still before egress in reading order, but it
    # sits at the bottom of the right column, directly above the
    # full-width egress row, so the jump is short. Field ids are
    # unchanged, so collect/reset/dynamic disabling (all by id)
    # keep working.
    if '      <section class="card subscription-links">' not in h or '      <section class="card argo-tunnel">' not in h:
        print("BUILD FAIL: anchor missing: index-layout-swap", file=sys.stderr); sys.exit(1)
    _sub_start = h.index('      <section class="card subscription-links">')
    _sub_end = h.index('</section>', _sub_start) + len('</section>')
    _argo_start = h.index('      <section class="card argo-tunnel">')
    _argo_end = h.index('</section>', _argo_start) + len('</section>')
    if not (_sub_start < _sub_end < _argo_start < _argo_end):
        print("BUILD FAIL: anchor order: index-layout-swap", file=sys.stderr); sys.exit(1)
    _sub_text = h[_sub_start:_sub_end]
    _argo_text = h[_argo_start:_argo_end]
    _egress_section = '      <section class="card egress-card">\n        <h2>外部出口与分流：</h2>\n' + egress_ui.rstrip("\n") + '\n      </section>'
    h = h[:_sub_start] + _argo_text + '\n\n' + _sub_text + '\n\n' + _egress_section + h[_argo_end:]
    # --- independent columns: right cards must move up, not wait ---
    # Explicit grid rows share their height across both columns:
    # row 1 is as tall as the taller of protocols/global, so Argo
    # in row 2 cannot start until protocols ends, leaving exactly
    # the blank the user pointed at between global and Argo, even
    # though Argo's own height is small. The fix is two column
    # wrappers, each a flex column: left = protocols alone, right =
    # global + Argo + subscription stacked tightly, so the right
    # cards start immediately below global, regardless of how tall
    # protocols is. Egress, commands and output stay direct grid
    # children, full width below both columns. Mobile stack order
    # is unchanged (left column, then right column, then the rest),
    # because the wrappers themselves stack in DOM order.
    _proto_start = h.index('      <section class="card protocol-port">')
    _proto_end = h.index('</section>', _proto_start) + len('</section>')
    _glob_start = h.index('      <section class="card outbound-warp">')
    _glob_end = h.index('</section>', _glob_start) + len('</section>')
    _argo2_start = h.index('      <section class="card argo-tunnel">')
    _argo2_end = h.index('</section>', _argo2_start) + len('</section>')
    _sub2_start = h.index('      <section class="card subscription-links">')
    _sub2_end = h.index('</section>', _sub2_start) + len('</section>')
    if not (_proto_start < _proto_end < _glob_start < _glob_end < _argo2_start < _argo2_end < _sub2_start < _sub2_end):
        print("BUILD FAIL: anchor order: index-layout-columns", file=sys.stderr); sys.exit(1)
    _proto_text = h[_proto_start:_proto_end]
    _glob_text = h[_glob_start:_glob_end]
    _argo2_text = h[_argo2_start:_argo2_end]
    _sub2_text = h[_sub2_start:_sub2_end]
    _rest = h[_sub2_end:]
    h = (h[:_proto_start]
         + '      <div class="grid-col">\n' + _proto_text + '\n      </div>\n\n'
         + '      <div class="grid-col">\n' + _glob_text + '\n\n' + _argo2_text + '\n\n' + _sub2_text + '\n      </div>'
         + _rest)
    # --- layout CSS: independent columns, no shared rows ---
    # With explicit grid rows, a row's height is shared across
    # columns, so Argo in row 2 waited for protocols in row 1 to
    # end, leaving a blank between global and Argo. With two flex
    # columns, each column stacks its own cards tightly, so Argo
    # starts immediately below global and subscription immediately
    # below Argo, whatever protocols' height is. Only the full-width
    # cards below both columns (egress, commands, output) use
    # grid-column 1 / 3. Mobile: the grid becomes one column, so
    # the left column wrapper stacks above the right column
    # wrapper, and each wrapper's cards stack inside it.
    h = replace(h, """    .grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      grid-template-rows: auto auto auto auto;
      gap: 20px;
    }""",
                """    .grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 20px;
      align-items: stretch;
    }
    .grid-col {
      display: flex;
      flex-direction: column;
      gap: 20px;
      min-width: 0;
    }
    /* Bottom alignment, user-chosen 2026-10-27: the left column
       has only the protocol card, the right column has three
       cards, so the grid row height is the right column's height.
       flex:1 makes the protocol card grow to that height, so its
       bottom aligns with the subscription card's bottom. This
       deliberately brings back blank inside the protocol card
       (its content is shorter than the right column); the user
       chose outer bottom alignment over no internal blank.
       On mobile the grid is one column, each column's height is
       content-driven, so flex:1 adds no extra height there. */
    .grid-col > .protocol-port {
      flex: 1;
    }""", "index-grid", 1)
    h = replace(h, """    @media (max-width: 1100px) {
      .grid {
        grid-template-columns: 1fr;
        grid-template-rows: auto auto auto auto auto;
      }
    }""",
                """    @media (max-width: 1100px) {
      .grid {
        grid-template-columns: 1fr;
      }
      .grid-col, .egress-card, .shortcut-commands-card, .out {
        grid-column: 1;
      }
    }""", "index-grid-mobile", 1)
    h = replace(h, """    .protocol-port {
      grid-column: 1;
      grid-row: 1 / 4;
    }
    .outbound-warp {
      grid-column: 2;
      grid-row: 1;
    }
    .subscription-links {
      grid-column: 2;
      grid-row: 2;
    }
    .argo-tunnel {
      grid-column: 2;
      grid-row: 3;
    }
    .shortcut-commands-card {
      grid-column: 1 / 3;
      grid-row: 4;
    }
    .out {
      grid-column: 1 / 3;
      grid-row: 5;
    }""",
                """    .egress-card {
      grid-column: 1 / 3;
    }
    .shortcut-commands-card {
      grid-column: 1 / 3;
    }
    .out {
      grid-column: 1 / 3;
    }""", "index-card-placement", 1)
    h = replace(h, '<p style="margin-top: 10px;">相关细节说明，请参考ArgoSBX小钢炮脚本项目💣：<a href="https://github.com/yonggekkk/argosbx" target="_blank">github.com/yonggekkk/argosbx</a></p>',
                '<p style="margin-top: 10px;">相关细节说明，请参考ArgoSBX小钢炮脚本项目💣：<a href="https://github.com/qytang2014/argosbx" target="_blank">github.com/qytang2014/argosbx</a></p>', "index-footer-link", 1)
    h = replace(h, 'Acme-yg域名IP证书脚本：bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)</a></p>',
                '        <p>域名证书：由证书来源申请（自动：低内存走 acme，否则走 Caddy；验证方式自动：未代理用 HTTP，已代理/Argo 用 DNS；可手动选 certmode/certsrc），固定目录 $HOME/agsbx/cert（Caddy 时从 Caddy 证书存储同步，acme 时直接安装到该目录），超时未就绪时回落自签证书。</p>', "index-footer-acme", 1)
    h = replace(h, "const CURL = 'bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh)'",
                "const CURL = 'bash <(curl -Ls https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh)'", "index-curl", 1)
    h = replace(h, "const WGET = 'bash <(wget -qO- https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh)'",
                "const WGET = 'bash <(wget -qO- https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh)'", "index-wget", 1)
    h = replace(h, "const optIds = ['warp','ippz','uuid','reym','cfip','alns','hyjpt','cdnym','name', 'oap', 'sub', 'subid', 'subpt'];",
                "const optIds = ['warp','ippz','uuid','ym','certsrc','certmode','reym','cfip','alns','hyjpt','cdnym','name', 'oap', 'sub', 'subid', 'subpt', 'egress_nodes', 'egress_bind', 'egress_rules', 'egress_add', 'vlpt_kernel', 'camouflage', 'caddy_email', 'hostname', 'web_proxy'];", "index-optids", 1)
    # index-agqc-field REMOVED: upstream d4f4b91 ships its own
    # id="agqc" select in the Argo card; ours would duplicate the id.
    # warp 修复（2026-11-04）：生成器"默认本地IP"选项 value 从 "" 改 "no"，否则空值进 WARP 分支
    h = replace(h, '<option value="">默认 服务器本地IP出站</option>',
                '<option value="no">默认 服务器本地IP出站</option>', "warp-default-no", 1)
    h = replace(h, '<div class="row"><label>导出节点名称前缀 <span class="pill">name</span></label><input id="name" type="text" placeholder="留空则默认协议名前缀"/></div>',
                '<div class="row"><label>导出节点名称前缀 <span class="pill">name</span></label><input id="name" type="text" placeholder="留空则默认协议名前缀"/></div>\n        <div class="row"><label>节点名称后缀 <span class="pill">hostname</span></label><input id="hostname" type="text" placeholder="留空则用系统 hostname"/></div>', "index-hostname-field", 1)
    h = replace(h, "    document.getElementById('uuid').value = '';",
                "    document.getElementById('uuid').value = '';\n    document.getElementById('ym').value = '';\n    document.getElementById('certmode').value = '';\n    document.getElementById('certsrc').value = '';\n    document.getElementById('camouflage').value = '';\n    document.getElementById('vlpt_kernel').value = '';", "index-reset-cert", 1)
    # --- vlpt UI: out of the Xray group, into its own dual-kernel group ---
    # Listing vlpt under "Xray可选协议" was misleading once vlpt became
    # dual-support: it is not Xray-only any more. The new first group holds
    # vlpt + its kernel select side by side (grid label + select, same as
    # the label + port rows), so the change is visible where the user
    # actually picks protocols. The select keeps id vlpt_kernel, so optIds,
    # reset, dynamic disabling and paste-back all keep working unchanged,
    # and there is exactly one such element (it is NOT also in the global
    # config card any more).
    h = replace(h, '            <label><input type="checkbox" data-proto="vlpt"> Vless-tcp-reality-enc <span class="pill">vlpt</span></label><input type="text" placeholder="留空则随机端口" data-port="vlpt">\n',
                '', "index-vlpt-out-of-xray", 1)
    h = replace(h, '        <div class="protocol-group separator">\n          <h3>Xray可选协议：</h3>',
                '''        <div class="protocol-group separator">
          <h3>双内核可选协议（Xray 与 Sing-box 都支持，默认自动单内核）：</h3>
          <div class="protocol-grid">
            <label><input type="checkbox" data-proto="vlpt"> Vless-tcp-reality-vision <span class="pill">vlpt</span></label><input type="text" placeholder="留空随机；逗号分隔多实例，如 10001, 或 ," data-port="vlpt">
            <label for="vlpt_kernel">Vless-tcp-reality 内核 <span class="pill">vlpt_kernel</span></label>
            <select id="vlpt_kernel">
              <option value="">默认 自动（只剩 Sing-box 时走 Sing-box，否则 Xray；旧安装下次更新即迁移，链接会变）</option>
              <option value="xray">强制 Xray（明确选 Xray 时不迁移，旧链接保留）</option>
              <option value="sb">强制 Sing-box</option>
            </select>
            <div class="field-note">所有 vlpt 实例共用此内核；同 uuid、同密钥对、不同端口，可分流到不同出口。</div>
          </div>
        </div>
        <div class="protocol-group separator">
          <h3>Xray可选协议：</h3>''', "index-vlpt-dual-group", 1)
    # field-note: spans the whole protocol-grid row, small and grey, so
    # a long explanation never widens the label column or squeezes the
    # input / select on its right.
    h = replace(h, "    .protocol-grid {\n      display: grid;",
                "    .field-note {\n      grid-column: 1 / -1;\n      font-size: 12px;\n      color: var(--sub);\n      margin-top: -4px;\n    }\n    .section-note {\n      font-size: 12px;\n      color: var(--sub);\n      line-height: 1.6;\n      margin: 4px 0 12px;\n    }\n    .protocol-grid {\n      display: grid;", "index-field-note-css", 1)
    # Section note under "必选内核协议端口：": comma = multiple
    # instances, empty = random, for every protocol in this card.
    # It lives under the card title, not inside any label, so it
    # never squeezes an input. Routing for extra instances is
    # inbound:<proto>2, inbound:<proto>3, ... (e.g. inbound:xhpt2,
    # inbound:sspt2, inbound:hypt2), same as vlpt2/vlpt3.
    h = replace(h, '        <h2>必选内核协议端口：</h2>',
                '        <h2>必选内核协议端口：</h2>\n        <p class="section-note">端口用逗号分隔可创建多个实例，全部协议都支持：逗号个数 + 1 = 实例数，空位表示随机端口。例如：留空 = 1 个随机；10001 = 1 个固定；, = 2 个随机；10001, = 第 1 个固定 10001、第 2 个随机；10001,10002 = 2 个固定；,, = 3 个随机。多个实例同 uuid、同密钥对、不同端口，可用 inbound:vlpt、inbound:vlpt2、inbound:vlpt3… 分流到不同出口，其他协议同理，如 inbound:xhpt2、inbound:sspt2、inbound:hypt2。防火墙（ufw/firewalld）会同步放行全部实例的端口，随机端口也不例外。</p>', "index-comma-section-note", 1)
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
    # No paste-back migration for vlpt2 / vlpt_more: those old
    # commands are no longer recognised (see vlpt-comma module:
    # vlpt2/vlpt_more are cleared at script start), and QUINN
    # confirmed they were never used on another machine, so there
    # is nothing to migrate. A pasted old command simply loses its
    # vlpt2/vlpt_more parts; the user re-enters them as a vlpt
    # comma list.
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
                "    ['warp', 'uuid', 'ym', 'certsrc', 'certmode', 'vlpt_kernel', 'reym', 'cfip', 'alns', 'hyjpt', 'cdnym', 'name', 'ippz', 'sub', 'subid', 'subpt', 'egress_nodes', 'egress_bind', 'egress_rules', 'egress_add', 'camouflage', 'web_proxy'].forEach(k => { if (keys.includes(k)) ordered.push(k); });", "index-tobash-order", 1)
    h = replace(h, '<button class="command-button" data-command="rep">调整并更新脚本（注:所有变量设置完成后再点击）：rep</button>',
                '<button class="command-button" data-command="rep">调整并更新脚本（注:所有变量设置完成后再点击）：rep</button>\n          <button class="command-button" data-command="add">增量更新（只传本次新增/修改，未传的沿用上次安装）：add</button>', "index-add-button", 1)
    # --- vmess-ws-tls generator: checkbox in the auto group, after vmpt ---
    h = replace(h, '            <label><input type="checkbox" data-proto="vmpt"> Vmess-ws <span class="pill">vmpt</span></label><input type="text" placeholder="留空则随机端口（Argo固定隧道的URL端口相同）" data-port="vmpt">\n',
                '            <label><input type="checkbox" data-proto="vmpt"> Vmess-ws <span class="pill">vmpt</span></label><input type="text" placeholder="留空则随机端口（Argo固定隧道的URL端口相同）" data-port="vmpt">\n            <label><input type="checkbox" data-proto="vmtls"> Vmess-ws-tls <span class="pill">vmtls</span></label><input type="text" placeholder="留空则随机端口" data-port="vmtls">\n', "index-vmtls-checkbox", 1)
    h = replace(h, "  const protoKeys = ['sopt','vmpt','vlpt','xhpt','vxpt','vwpt','xupt','xcpt','hypt','tupt','nvpt','anpt','arpt','sspt','snpt'];",
                "  const protoKeys = ['sopt','vmpt','vmtls','vlpt','xhpt','vxpt','vwpt','xupt','xcpt','hypt','tupt','nvpt','anpt','arpt','sspt','snpt'];", "index-vmtls-protokeys", 1)
    h = replace(h, "      if (command === 'rep') {",
                "      if (command === 'rep' || command === 'add') {", "index-add-handler", 1)
    h = replace(h, "output.value = (vars ? vars + ' ' : '') + selectedCommand + ' rep';",
                "output.value = (vars ? vars + ' ' : '') + selectedCommand + ' ' + command;", "index-add-output", 1)
    # upstream d4f4b91 stray line + quote-escape typo: drop the stray
    # ```[cite: 1] line after </html>, and restore the correct " -> \"
    # escaping upstream broke (it now writes " as \\ instead).
    h = replace(h, '</html>\n```[cite: 1]\n', '</html>\n', "index-stray-cite-line", 1)
    h = replace(h, "val.replace(/\"/g, '" + chr(92)*4 + "')",
                "val.replace(/\"/g, '" + chr(92)*2 + "\"')", "index-quote-escape-fix", 1)
    lines = h.split("\n", 1)
    out = lines[0] + "\n<!-- GENERATED BY build/build.py - DO NOT EDIT BY HAND - sources: upstream/index.html + modules/index-*.html -->\n" + lines[1]
    if util.WRITE:
        (ROOT / "index.html").write_text(out)
        print(f"Built index.html: {len(out)} bytes, {out.count(chr(10))} lines")
