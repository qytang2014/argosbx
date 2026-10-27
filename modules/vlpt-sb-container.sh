# vlpt on Sing-box, container build only (private module).
# Container protocol variables are ports (vlpt is the port), not flags,
# and reym is the Reality SNI. Same vlpt_on rules as the main script,
# computed at the top of ins() from vlpt_kernel and the other ports.
# Only runs when vlpt is set AND vlpt_on=sb; otherwise it does nothing
# (the xray vlpt block, guarded by vlpt_on=xray, installs it instead).
# sbk keypair is generated exactly like the container arpt block.
if [ -n "$vlpt" ] && [ "$vlpt_on" = "sb" ]; then
if [ -z "$reym" ]; then reym=apple.com; fi
echo "$reym" > "$HOME/agsbx/reym"
echo "Reality域名：$reym"
mkdir -p "$HOME/agsbx/sbk"
if [ ! -e "$HOME/agsbx/sbk/private_key" ]; then
key_pair=$("$HOME/agsbx/sing-box" generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
short_id=$("$HOME/agsbx/sing-box" generate rand --hex 4)
echo "$private_key" > "$HOME/agsbx/sbk/private_key"
echo "$public_key" > "$HOME/agsbx/sbk/public_key"
echo "$short_id" > "$HOME/agsbx/sbk/short_id"
fi
private_key_s=$(cat "$HOME/agsbx/sbk/private_key")
public_key_s=$(cat "$HOME/agsbx/sbk/public_key")
short_id_s=$(cat "$HOME/agsbx/sbk/short_id")
if [ -z "$vlpt" ] && [ ! -e "$HOME/agsbx/vlpt" ]; then
vlpt=$(shuf -i 10000-65535 -n 1)
echo "$vlpt" > "$HOME/agsbx/vlpt"
elif [ -n "$vlpt" ]; then
echo "$vlpt" > "$HOME/agsbx/vlpt"
fi
vlpt=$(cat "$HOME/agsbx/vlpt")
echo "Vless-tcp-reality-v端口（Sing-box）：$vlpt"
cat >> "$HOME/agsbx/sb.json" <<EOF
        {
            "type": "vless",
            "tag": "vl-reality-sb",
            "listen": "::",
            "listen_port": ${vlpt},
            "users": [
                {
                    "uuid": "${uuid}",
                    "flow": "xtls-rprx-vision"
                }
            ],
            "tls": {
                "enabled": true,
                "server_name": "${reym}",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "${reym}",
                        "server_port": 443
                    },
                    "private_key": "$private_key_s",
                    "short_id": ["$short_id_s"]
                }
            }
        },
EOF
fi
