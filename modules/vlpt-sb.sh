# vlpt on Sing-box (private module, vlpt dual-support).
# Inserted into installsb() before the sspt block. Only runs when vlpt is
# selected AND vlpt_on=sb (computed at the top of ins() from vlpt_kernel
# and the other selected protocols). Otherwise it leaves vlp untouched:
# if vlpt is selected but vlpt_on=xray, installxray() will install it;
# if vlpt is not selected at all, the else branch sets vlp=vlptargo
# (the recovery dummy, same as every other protocol block).
# Reality keypair: generated exactly like the arpt block (sbk dir, reuse
# if it already exists, so arpt + vlpt-sb share one keypair and one
# pbk/sid pair). ym_vl_re defaults to apple.com, same as arpt/xray.
if [ -n "$vlp" ] && [ "$vlpt_on" = "sb" ]; then
vlp=vlpt
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
if [ -z "$port_vl_re" ] && [ ! -e "$HOME/agsbx/port_vl_re" ]; then
port_vl_re=$(shuf -i 10000-65535 -n 1)
echo "$port_vl_re" > "$HOME/agsbx/port_vl_re"
elif [ -n "$port_vl_re" ]; then
echo "$port_vl_re" > "$HOME/agsbx/port_vl_re"
fi
port_vl_re=$(cat "$HOME/agsbx/port_vl_re")
echo "Vless-tcp-reality-v端口（Sing-box）：$port_vl_re"
cat >> "$HOME/agsbx/sb.json" <<EOF
    {
        "type": "vless",
        "tag": "vl-reality-sb",
        "listen": "::",
        "listen_port": ${port_vl_re},
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
[ -n "$vlp" ] || vlp=vlptargo
fi
