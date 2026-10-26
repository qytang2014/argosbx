#!/usr/bin/env python3
"""Build the distributable argosbx.sh from upstream + private modules.

Usage (from repo root):
    python3 build/build.py
Output: argosbx.sh (generated, do NOT edit by hand)

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

def main():
    t = read("upstream/argosbx.sh")
    cert = read("modules/cert.sh")
    egress = read("modules/egress.sh")
    cert_main = read("modules/cert-main.sh")

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

if __name__ == "__main__":
    main()
