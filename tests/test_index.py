#!/usr/bin/env python3
"""Test: built index.html contains all private UI/JS, and upstream files are pristine."""
import pathlib, re, sys
root = pathlib.Path(__file__).resolve().parent.parent
html = (root / "index.html").read_text()
for needle in ["ArgoSBX一键SSH命令生成器-Vincent", "github.com/qytang2014/argosbx",
               'id="ym"', 'id="certmode"', 'id="certsrc"',
               'id="egress_nodes"', 'id="egress_bind"', 'id="egress_rules"', 'id="egress_add"',
               'data-command="add"', "egress_add",
               "egress_nodes", "egress_bind", "egress_rules"]:
    assert needle in html, f"FAIL: index.html missing {needle}"
# CURL/WGET must point to the private repo, not upstream
assert "raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh" in html
assert "raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh" not in html, "FAIL: index.html still points to upstream script URL"
# Layout (user clarified 2026-10-27, independent columns):
# left protocols, right global/Argo/subscription, egress full width
# second row. Right cards must stack tightly under global, not wait
# for protocols to end: that is why the two columns are flex
# wrappers, not shared grid rows. Cards do not stretch, mobile
# truly stacks.
assert 'class="card egress-card"' in html, "FAIL: egress-card missing"
proto_start = html.index('class="card protocol-port"')
global_start = html.index('class="card outbound-warp"')
argo_start = html.index('class="card argo-tunnel"')
sub_start = html.index('class="card subscription-links"')
egress_start = html.index('class="card egress-card"')
assert proto_start < global_start < argo_start < sub_start < egress_start, "FAIL: DOM order should be protocols, global, Argo, subscription, egress"
out_end = html.index('</section>', global_start)
assert out_end < egress_start, "FAIL: egress should be outside outbound-warp"
assert html.index('id="ippz"') < egress_start, "FAIL: ippz should stay in the global card"
# Independent columns: a grid-col wrapper before protocols, and one
# before global, closed after subscription (global, Argo, sub are
# consecutive inside the right wrapper, with no egress in between).
left_col = html.index('class="grid-col"')
assert left_col < proto_start, "FAIL: left column wrapper should precede protocols"
right_col = html.index('class="grid-col"', left_col + 1)
assert proto_start < right_col < global_start, "FAIL: right column wrapper should precede global"
right_close = html.index('</div>', sub_start)
assert sub_start < right_close < egress_start, "FAIL: right column wrapper should close after subscription, before egress"
assert "display: flex" in html and "flex-direction: column" in html, "FAIL: grid-col should be a flex column"
# Bottom alignment (user-chosen): grid stretches both columns to
# the taller column's height, and the protocol card flex-grows to
# fill the left column, so its bottom aligns with subscription's.
assert "align-items: stretch" in html, "FAIL: grid should stretch columns for bottom alignment"
m_proto = re.search(r"(?m)^    \.grid-col > \.protocol-port \{[^}]+\}", html)
assert m_proto and "flex: 1;" in m_proto.group(0), "FAIL: protocol card should flex-grow to align bottom"
# No per-card grid rows any more: only the full-width cards span.
for cls in [".egress-card", ".shortcut-commands-card", ".out"]:
    m = re.search(rf"(?m)^    {re.escape(cls)} \{{[^}}]+\}}", html)
    assert m, f"FAIL: CSS for {cls} missing"
    assert "grid-column: 1 / 3;" in m.group(0), f"FAIL: {cls} should span full width"
assert "grid-row: 1 / 4" not in html, "FAIL: protocol card should no longer span 3 rows"
assert ".grid-col, .egress-card, .shortcut-commands-card, .out" in html, "FAIL: mobile reset missing"
# Cert wording: cert source is auto (acme on low memory, else
# Caddy), so certmode/alns/footer must not assume Caddy only.
assert "HTTP 验证（需 80 端口空闲）" in html, "FAIL: certmode http wording missing"
assert "DNS 验证（需 Cloudflare API Token）" in html, "FAIL: certmode dns wording missing"
assert "Caddy 监听 80/443" not in html, "FAIL: certmode should not assume Caddy"
assert "DNS 插件 Caddy" not in html, "FAIL: certmode dns should not assume Caddy plugin"
assert "为域名证书TLS，需配合节点域名 ym" in html, "FAIL: alns enabled wording missing"
assert "Caddy 域名证书TLS" not in html, "FAIL: alns should not assume Caddy cert"
assert "默认 关闭 (HY2/TUIC/Naive/Anytls/Xhttp-tls为自签证书TLS)" in html, "FAIL: alns closed should include Naive"
assert "由证书来源申请" in html, "FAIL: footer should say cert source, not Caddy only"
assert "由 Caddy 申请" not in html, "FAIL: footer should not assume Caddy only"
# Every optId must have a matching element id in the page
m = re.search(r"const optIds = \[([^\]]+)\]", html)
assert m, "FAIL: optIds not found"
ids = re.findall(r"'([^']+)'", m.group(1))
missing = [i for i in ids if f'id="{i}"' not in html]
assert not missing, f"FAIL: optIds without element: {missing}"
# Upstream files must NOT contain private markers (they are pristine)
for f, markers in [("upstream/argosbx.sh", ["egress_nodes", "certsrc", "EGRESS MODULE"]),
                   ("upstream/index.html", ["egress_nodes", "certsrc", "Vincent"])]:
    t = (root / f).read_text(errors="ignore")
    for mk in markers:
        assert mk not in t, f"FAIL: {f} contains private marker {mk} (upstream file was edited)"
print("PASS: index.html + upstream pristine")
