# vlpt2 on Xray (private module, second vlpt instance).
# Inserted into installxray() after the vlpt block. Only runs when
# vlpt2 is selected AND vlpt_on=xray (vlpt_on is shared with vlpt:
# vlpt_kernel applies to both instances, so both instances always
# land on the same kernel; they are distinguished by port and by
# inbound tag, which is what egress inbound: routing needs).
# Shares vlpt's Xray Reality keypair (xrk) and uuid, so pbk/sid are
# the same as vlpt's; only the port, tag and display name differ.
# If vlpt2 is not selected, vlp2 becomes the recovery dummy
# (vlpt2argo), mirroring the vlpt block's vlptargo.
if [ -n "$vlp2" ] && [ "$vlpt_on" = "xray" ]; then
vlp2=vlpt2
if [ -z "$ym_vl_re" ]; then ym_vl_re=apple.com; fi
if [ -z "$port_vl_re2" ] && [ ! -e "$HOME/agsbx/port_vl_re2" ]; then
port_vl_re2=$(shuf -i 10000-65535 -n 1)
echo "$port_vl_re2" > "$HOME/agsbx/port_vl_re2"
elif [ -n "$port_vl_re2" ]; then
echo "$port_vl_re2" > "$HOME/agsbx/port_vl_re2"
fi
port_vl_re2=$(cat "$HOME/agsbx/port_vl_re2")
echo "Vless-tcp-reality-v2端口：$port_vl_re2"
cat >> "$HOME/agsbx/xr.json" <<EOF
        {
            "tag":"reality-vision-2",
            "listen": "::",
            "port": $port_vl_re2,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${uuid}",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "fingerprint": "chrome",
                    "dest": "${ym_vl_re}:443",
                    "serverNames": [
                      "${ym_vl_re}"
                    ],
                    "privateKey": "$private_key_x",
                    "shortIds": ["$short_id_x"]
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
[ -n "$vlp2" ] || vlp2=vlpt2argo
fi

