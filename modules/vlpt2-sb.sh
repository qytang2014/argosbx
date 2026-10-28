# vlpt2 on Sing-box (private module, second vlpt instance).
# Inserted into installsb() after the vlpt-sb block, before sspt.
# Only runs when vlpt2 is selected AND vlpt_on=sb (shared with vlpt).
# Shares vlpt's Sing-box Reality keypair (sbk, also shared with arpt),
# so pbk/sid are the same as vlpt's; only port, tag and display
# name differ. If vlpt2 is not selected, vlp2 becomes vlpt2argo.
if [ -n "$vlp2" ] && [ "$vlpt_on" = "sb" ]; then
vlp2=vlpt2
if [ -z "$ym_vl_re" ]; then ym_vl_re=apple.com; fi
echo "$ym_vl_re" > "$HOME/agsbx/ym_vl_re"
echo "Reality域名：$ym_vl_re"
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
if [ -z "$port_vl_re2" ] && [ ! -e "$HOME/agsbx/port_vl_re2" ]; then
port_vl_re2=$(shuf -i 10000-65535 -n 1)
echo "$port_vl_re2" > "$HOME/agsbx/port_vl_re2"
elif [ -n "$port_vl_re2" ]; then
echo "$port_vl_re2" > "$HOME/agsbx/port_vl_re2"
fi
port_vl_re2=$(cat "$HOME/agsbx/port_vl_re2")
echo "Vless-tcp-reality-v2端口（Sing-box）：$port_vl_re2"
cat >> "$HOME/agsbx/sb.json" <<EOF
    {
        "type": "vless",
        "tag": "vl-reality-sb-2",
        "listen": "::",
        "listen_port": ${port_vl_re2},
        "users": [
            {
                "uuid": "${uuid}",
                "flow": "xtls-rprx-vision"
            }
        ],
        "tls": {
            "enabled": true,
            "server_name": "${ym_vl_re}",
            "reality": {
                "enabled": true,
                "handshake": {
                    "server": "${ym_vl_re}",
                    "server_port": 443
                },
                "private_key": "$private_key_s",
                "short_id": ["$short_id_s"]
            }
        }
    },
EOF
else
[ -n "$vlp2" ] || vlp2=vlpt2argo
fi

