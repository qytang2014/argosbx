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
# Layout (user clarified 2026-10-27): left protocols, right
# global/Argo/subscription, egress full width second row, cards do
# not stretch, mobile truly stacks.
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
assert "align-items: start" in html, "FAIL: grid should align start, not stretch cards"
for cls, col, row in [(".protocol-port", "1", "1"), (".outbound-warp", "2", "1"),
                      (".argo-tunnel", "2", "2"), (".subscription-links", "2", "3"),
                      (".egress-card", "1 / 3", "4"), (".shortcut-commands-card", "1 / 3", "5"),
                      (".out", "1 / 3", "6")]:
    # Main placement only: it starts at line start with 4 spaces.
    # The mobile reset line lists several cards ending in ".out {",
    # which a plain search would match first for .out.
    m = re.search(rf"(?m)^    {re.escape(cls)} \{{[^}}]+\}}", html)
    assert m, f"FAIL: CSS for {cls} missing"
    assert f"grid-column: {col};" in m.group(0), f"FAIL: {cls} column should be {col}"
    assert f"grid-row: {row};" in m.group(0), f"FAIL: {cls} row should be {row}"
assert "grid-row: 1 / 4" not in html, "FAIL: protocol card should no longer span 3 rows"
assert ".protocol-port, .outbound-warp, .egress-card, .subscription-links" in html, "FAIL: mobile reset missing"
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
