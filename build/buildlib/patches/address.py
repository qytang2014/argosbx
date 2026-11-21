"""Install flow gate, Reality / non-TLS address resolution, self-signed pinning. Moved verbatim from main() in build/build.py."""
import sys
from ..util import read, replace


def apply(t, ctx):
    # --- install flow gate: only run install/wipe when not installed or explicit rep/add/protocol vars ---
    old_install_gate = """fi
if ! find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null | grep -Eq 'agsbx/(s|x)' && ! pgrep -f 'agsbx/(s|x)' >/dev/null 2>&1; then"""
    new_install_gate = """fi
if _is_install_run "$1"; then"""
    t = replace(t, old_install_gate, new_install_gate, "install-flow-gate", 1)

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
    t = replace(t, '- name: ${sxname}vless-reality-enc-$hostname               \n  type: vless\n  server: $server_ip',
                '- name: ${sxname}vless-reality-vision-$hostname               \n  type: vless\n  server: $reality_addr', "reality-clash-config", 1)
    # vlpt Clash entry must not carry ENC: server decryption stays
    # none (we do not follow upstream ENC), so drop the encryption
    # line upstream added to clvlpt (the flow+servername context
    # makes this unique among the enc Clash functions).
    t = replace(t, '  flow: xtls-rprx-vision\n  encryption: "$enkey"\n  servername: $ym_vl_re',
                '  flow: xtls-rprx-vision\n  servername: $ym_vl_re', "vlpt-clash-encryption-none", 1)
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
    t = replace(t, '- name: ${sxname}Shadowsocks-2022-$hostname\n  type: ss\n  server: $server_ip',
                '- name: ${sxname}Shadowsocks-2022-$hostname\n  type: ss\n  server: $domain_addr', "plain-ss-clash-config", 1)
    # Snell-V6 (upstream d4f4b91): same plain-addr rule as ss — links
    # and client configs use $domain_addr, not $server_ip.
    t = replace(t, 'sn1_link="snell://$uuid@$server_ip:$port_sn?version=6&reuse=true&mode=default#${sxname}Snell-V6-$hostname"',
                'sn1_link="snell://$uuid@$domain_addr:$port_sn?version=6&reuse=true&mode=default#${sxname}Snell-V6-$hostname"', "plain-sn-link", 1)
    t = replace(t, 'sn2_link="snell://$(echo -n "chacha20-ietf-poly1305:$uuid@$server_ip:$port_sn" | base64 -w0)?tfo=1&version=6&reuse=1&mode=default&udp=1#${sxname}Snell-V6-$hostname"',
                'sn2_link="snell://$(echo -n "chacha20-ietf-poly1305:$uuid@$domain_addr:$port_sn" | base64 -w0)?tfo=1&version=6&reuse=1&mode=default&udp=1#${sxname}Snell-V6-$hostname"', "plain-sn-link2", 1)
    t = replace(t, '  "tag": "${sxname}Snell-V6-$hostname",\n  "server": "$server_ip",',
                '  "tag": "${sxname}Snell-V6-$hostname",\n  "server": "$domain_addr",', "plain-sn-sb-config", 1)
    t = replace(t, '- name: ${sxname}Snell-V6-$hostname\n  type: snell\n  server: $server_ip',
                '- name: ${sxname}Snell-V6-$hostname\n  type: snell\n  server: $domain_addr', "plain-sn-clash-config", 1)
    t = replace(t, '            "server": "$server_ip",\n            "server_port": $port_vm_ws,',
                '            "server": "$domain_addr",\n            "server_port": $port_vm_ws,', "plain-vm-sb-config", 1)
    t = replace(t, '- name: ${sxname}vmess-ws-$hostname                         \n  type: vmess\n  server: $server_ip',
                '- name: ${sxname}vmess-ws-$hostname                         \n  type: vmess\n  server: $domain_addr', "plain-vm-clash-config", 1)

    # --- self-signed pinning (private, display only) ---
    # Inserted right after the msins/sni determination in the display
    # section, so every Clash / sing-box function defined later can use
    # cl_skip / cl_pin_line / sb_insecure / sb_pin_field. See the module
    # comment in the inserted code for the field semantics and the
    # domain-cert / missing-pin fallbacks.
    pin_code = '''# self-signed pinning: only when the self-signed cert is in use
# (msins=true). pin_sha is the DER SHA-256 hex from SHA256.txt, which
# is exactly Mihomo's fingerprint format (hex string, see
# mihomo/component/ca CalculateFingerprint). pin_spki is the base64
# SPKI hash for sing-box certificate_public_key_sha256 (since 1.13).
# When both are available, Clash uses skip-cert-verify:false +
# fingerprint, sing-box uses insecure:false +
# certificate_public_key_sha256, so a self-signed cert is verified
# (pinned) instead of skipped. When the domain cert is ready
# (msins=false) no pin is added: CA verification already works, and
# a pin would break on every 90-day renewal. When a pin cannot be
# computed, fall back to the old skip behaviour rather than breaking
# the node with an empty pin.
pin_sha=""; pin_spki=""; pin_on=0
if [ "$msins" = "true" ] && [ -f "$HOME/agsbx/selfsigned/cert.crt" ]; then
pin_sha=$(cat "$HOME/agsbx/SHA256.txt" 2>/dev/null)
pin_spki=$(openssl x509 -in "$HOME/agsbx/selfsigned/cert.crt" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform der 2>/dev/null | openssl dgst -sha256 -binary 2>/dev/null | openssl enc -base64 2>/dev/null | tr -d '\\n')
[ -n "$pin_sha" ] && [ -n "$pin_spki" ] && pin_on=1
fi
if [ "$pin_on" = "1" ]; then cl_skip=false; sb_insecure=false; else cl_skip="$msins"; sb_insecure="$msins"; fi
if [ "$pin_on" = "1" ]; then cl_pin_line="  fingerprint: $pin_sha"; else cl_pin_line=""; fi
if [ "$pin_on" = "1" ]; then sb_pin_field=$(printf ',\\n            "certificate_public_key_sha256": ["%s"]' "$pin_spki"); else sb_pin_field=""; fi
'''
    t = replace(t, 'else\nsni=$(cat "$HOME/agsbx/ym" 2>/dev/null)\nadd=$(cat "$HOME/agsbx/ym" 2>/dev/null)\njhins=0\nmsins=false\nfi',
                'else\nsni=$(cat "$HOME/agsbx/ym" 2>/dev/null)\nadd=$(cat "$HOME/agsbx/ym" 2>/dev/null)\njhins=0\nmsins=false\nfi\n' + pin_code, "pin-compute", 1)
    # Clash: all 7 subscription skip lines (xhttp-tls x4, anytls, hy2,
    # tuic) become skip:$cl_skip plus a fingerprint line when pinned.
    # An empty cl_pin_line leaves a blank YAML line, which is harmless.
    n = t.count("  skip-cert-verify: $msins")
    if n != 7:
        print(f"BUILD FAIL: pin-clash: expected 7 occurrence(s), found {n}", file=sys.stderr); sys.exit(1)
    t = t.replace("  skip-cert-verify: $msins", "  skip-cert-verify: $cl_skip\n$cl_pin_line")
    # sing-box: all 3 subscription insecure lines (anytls, hy2, tuic)
    # become insecure:$sb_insecure plus a SPKI pin field when pinned.
    # The template comma after $msins now follows the pin field, so
    # pinned JSON is "insecure": false, "certificate_public_key_sha256":
    # [...], <next field>, and unpinned JSON is unchanged.
    n = t.count('"insecure": $msins,')
    if n != 3:
        print(f"BUILD FAIL: pin-singbox: expected 3 occurrence(s), found {n}", file=sys.stderr); sys.exit(1)
    t = t.replace('"insecure": $msins,', '"insecure": $sb_insecure$sb_pin_field,')
    return t
