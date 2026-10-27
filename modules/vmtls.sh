# Vmess-ws-tls (private module, main script only).
# A DIRECT vmess + ws + TLS inbound, distinct from the plain vmess-ws
# (vmpt, tls off) and from the Argo vmess-ws-tls links (which terminate
# TLS at Cloudflare, not at this server). New protocol flag `vmtls`
# (value = port, like vmpt); internal flag `vmt`.
# Auto-group, like vmpt: it does NOT change ins() kernel branches.
# xrsbvmtls writes to xr.json when Xray is installed, otherwise to
# sb.json, exactly like xrsbvm. The TLS certificate is $certificateHTA /
# $keyHTA (domain cert when ready, otherwise the self-signed pair), so
# no new cert logic is needed. Path is ${uuid}-vmtls, distinct from
# vmpt's ${uuid}-vm, so plain and TLS vmess can coexist.
# Server inbounds carry no server_name: the single certificate is
# presented regardless of the client's SNI, and the client side
# (display: native link, Clash, sing-box) is what pins / verifies it.
xrsbvmtls(){
if [ -n "$vmt" ]; then
vmt=vmtls
if [ -z "$port_vm_tls" ] && [ ! -e "$HOME/agsbx/port_vm_tls" ]; then
port_vm_tls=$(shuf -i 10000-65535 -n 1)
echo "$port_vm_tls" > "$HOME/agsbx/port_vm_tls"
elif [ -n "$port_vm_tls" ]; then
echo "$port_vm_tls" > "$HOME/agsbx/port_vm_tls"
fi
port_vm_tls=$(cat "$HOME/agsbx/port_vm_tls")
echo "Vmess-ws-tls端口：$port_vm_tls"
if [ -e "$HOME/agsbx/xr.json" ]; then
cat >> "$HOME/agsbx/xr.json" <<EOF
        {
            "tag": "vmess-tls-xr",
            "listen": "::",
            "port": ${port_vm_tls},
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "${uuid}"
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "security": "tls",
                "tlsSettings": {
                    "certificates": [
                        {
                            "certificateFile": "$certificateHTA",
                            "keyFile": "$keyHTA"
                        }
                    ]
                },
                "wsSettings": {
                  "path": "${uuid}-vmtls"
            }
        },
            "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"],
            "metadataOnly": false
            }
         },
EOF
else
cat >> "$HOME/agsbx/sb.json" <<EOF
{
        "type": "vmess",
        "tag": "vmess-tls-sb",
        "listen": "::",
        "listen_port": ${port_vm_tls},
        "users": [
            {
                "uuid": "${uuid}",
                "alterId": 0
            }
        ],
        "transport": {
            "type": "ws",
            "path": "${uuid}-vmtls",
            "max_early_data":2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"
        },
        "tls": {
            "enabled": true,
            "certificate_path": "$certificateHTA",
            "key_path": "$keyHTA"
        }
    },
EOF
fi
else
vmt=vmtlsargo
fi
}
