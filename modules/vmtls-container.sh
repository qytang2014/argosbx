# Vmess-ws-tls (private module, container only).
# Same direct vmess + ws + TLS inbound as modules/vmtls.sh, but in
# container form: variables are ports, not flags (container ins() checks
# [ -n "$var" ]), port file is $HOME/agsbx/vmtls, and the certificate
# is always $HOME/agsbx/selfsigned/cert.pem + private.key, which
# container_cert_setup already points at the domain cert (symlink) when
# one is ready, or at the self-signed pair otherwise. Path is
# ${uuid}-vmtls, distinct from vmpt's ${uuid}-vm.
xrsbvmtls(){
if [ -n "$vmtls" ]; then
if [ -z "$vmtls" ] && [ ! -e "$HOME/agsbx/vmtls" ]; then
vmtls=$(shuf -i 10000-65535 -n 1)
echo "$vmtls" > "$HOME/agsbx/vmtls"
elif [ -n "$vmtls" ]; then
echo "$vmtls" > "$HOME/agsbx/vmtls"
fi
vmtls=$(cat "$HOME/agsbx/vmtls")
echo "Vmess-ws-tls端口：$vmtls"
if [ -e "$HOME/agsbx/xr.json" ]; then
cat >> "$HOME/agsbx/xr.json" <<EOF
        {
            "tag": "vmess-tls-xr",
            "listen": "::",
            "port": ${vmtls},
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
                            "certificateFile": "$HOME/agsbx/selfsigned/cert.pem",
                            "keyFile": "$HOME/agsbx/selfsigned/private.key"
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
        "listen_port": ${vmtls},
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
            "certificate_path": "$HOME/agsbx/selfsigned/cert.pem",
            "key_path": "$HOME/agsbx/selfsigned/private.key"
        }
    },
EOF
fi
fi
}
