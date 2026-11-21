"""Cert module, cert-watch, egress exports, cert path rewrites, ufw sync, ym autosub, SAN. Moved verbatim from main() in build/build.py."""
import sys
from ..util import insert_after, replace


def apply(t, ctx):
    cert = ctx["cert"]
    cert_watch = ctx["cert_watch"]
    # --- cert module insertion (after cdnym export, before argo export) ---
    t = insert_after(t, "export cdnym=${cdnym:-''}\n", cert, "cert-module-anchor")
    # --- cert-watch module (right after cert module) ---
    t = t.replace(cert, cert + cert_watch, 1)
    t = replace(t, 'echo "更新脚本命令：原已安装的自定义各种协议变量组 主脚本 rep"',
                'echo "更新主脚本命令：agsbx update 或 agsbx up 【或者】 主脚本 update"\n'
                'echo "更新配置变量命令：原已安装的自定义各种协议变量组 主脚本 rep"\n'
                'echo "增量更新命令：只传新增/修改的协议变量组 主脚本 add（未传的变量沿用上次安装，删协议仍用 rep）"\n'
                'echo "防火墙同步命令：开启防火墙后运行 agsbx fwsync 重新同步节点端口（ufwsync 为旧别名），运行 agsbx fwstatus 查看防火墙状态"\n'
                'echo "订阅同步命令：https 订阅状态异常时运行 agsbx subhttpsync 重新同步（ym 已设、域名证书就绪，且内存大于等于 256M / 订阅 Caddy 已在运行 / 能自动合并到系统 Caddy 时走 https，否则回退 http）"', "showmode-add-line", 1)
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
    # --- ufw sync (after ins + vars_save, before display; also covers
    # rep/add, which flow through the same ins call; list/upx/ups/del
    # exit before ins and are unaffected) ---
    t = replace(t, 'ins\nvars_save\nif [ -n "$sub" ]; then',
                'ins\nrun_hook post_start\nrun_hook on_complete\nif [ -n "$sub" ]; then', "ufw-sync-call", 1)
    # --- ym auto-enables subscription (https by default, no need for sub=1) ---
    t = replace(t, 'if [ -n "$sub" ]; then\nsubtokenipsub(){',
                'if [ -n "$sub" ] || [ -n "$ym" ]; then\nsubtokenipsub(){', "ym-autosub", 1)
    t = replace(t, 'if [ ! -f "$HOME/agsbx/SHA256.txt" ]; then',
                'cert_migrate_paths\nif [ ! -f "$HOME/agsbx/SHA256.txt" ]; then', "selfsigned-migrate-call", 1)
    t = replace(t, 'command -v openssl >/dev/null 2>&1 && openssl ecparam -genkey -name prime256v1 -out "$HOME/agsbx/private.key"',
                'mkdir -p "$HOME/agsbx/selfsigned" 2>/dev/null || true\ncommand -v openssl >/dev/null 2>&1 && openssl ecparam -genkey -name prime256v1 -out "$HOME/agsbx/selfsigned/private.key"', "selfsigned-gen-key", 1)
    t = replace(t, 'openssl req -new -x509 -days 36500 -key "$HOME/agsbx/private.key" -out "$HOME/agsbx/cert.crt"',
                'openssl req -new -x509 -days 36500 -key "$HOME/agsbx/selfsigned/private.key" -out "$HOME/agsbx/selfsigned/cert.crt"', "selfsigned-gen-cert", 1)
    # --- self-signed cert must carry a SAN, not CN only ---
    # Go (and modern TLS stacks) reject CN-only certs with "certificate
    # relies on legacy Common Name field, use SANs instead". That is
    # exactly the hy2 error: hy2 is the only TLS protocol that forces
    # verification (insecure=0) on a self-signed cert, relying on
    # pinSHA256, and a standard verifier rejects the CN-only cert before
    # any pin check. tuic/anytls use insecure=1 in the self-signed case,
    # which is why they did not surface this first. Fix: SAN
    # DNS:www.bing.com, matching the self-signed sni=www.bing.com in the
    # links. The || fallback keeps old OpenSSL (pre-1.1.1, no -addext)
    # working with the old CN-only cert instead of generating nothing.
    # Migration: an existing CN-only cert is regenerated on the next run,
    # not just when SHA256.txt is missing, otherwise old installs would
    # keep the broken cert forever (new key + cert + SHA256 pin, so old
    # hy2/tuic/anytls/xhttp-tls links change - they were already broken
    # for hy2, and the pin is recomputed in the same block).
    t = replace(t, 'openssl req -new -x509 -days 36500 -key "$HOME/agsbx/selfsigned/private.key" -out "$HOME/agsbx/selfsigned/cert.crt" -subj "/CN=www.bing.com" >/dev/null 2>&1',
                'openssl req -new -x509 -days 36500 -key "$HOME/agsbx/selfsigned/private.key" -out "$HOME/agsbx/selfsigned/cert.crt" -subj "/CN=www.bing.com" -addext "subjectAltName=DNS:www.bing.com" >/dev/null 2>&1 || openssl req -new -x509 -days 36500 -key "$HOME/agsbx/selfsigned/private.key" -out "$HOME/agsbx/selfsigned/cert.crt" -subj "/CN=www.bing.com" >/dev/null 2>&1', "selfsigned-san", 1)
    t = replace(t, 'if [ ! -f "$HOME/agsbx/SHA256.txt" ]; then',
                'if [ ! -f "$HOME/agsbx/SHA256.txt" ] || ! openssl x509 -in "$HOME/agsbx/selfsigned/cert.crt" -noout -text 2>/dev/null | grep -q "Subject Alternative Name"; then', "selfsigned-san-migrate", 1)
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
    return t
