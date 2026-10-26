#!/usr/bin/env python3
"""Test: built index.html contains all private UI/JS, and upstream files are pristine."""
import pathlib, re, sys
root = pathlib.Path(__file__).resolve().parent.parent
html = (root / "index.html").read_text()
for needle in ["ArgoSBX一键SSH命令生成器-Vincent", "github.com/qytang2014/argosbx",
               'id="ym"', 'id="certmode"', 'id="certsrc"',
               'id="egress_nodes"', 'id="egress_bind"', 'id="egress_rules"',
               "egress_nodes", "egress_bind", "egress_rules"]:
    assert needle in html, f"FAIL: index.html missing {needle}"
# CURL/WGET must point to the private repo, not upstream
assert "raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh" in html
assert "raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh" not in html, "FAIL: index.html still points to upstream script URL"
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
