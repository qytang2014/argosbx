# vlpt more instances on Xray (private module, loop, not per-instance copies).
# vlpt_more="10003,10004" installs instances 3, 4, ... in order, sharing
# vlpt's uuid, Reality keypair (xrk), SNI and flow, with their own port
# and inbound tag reality-vision-3, reality-vision-4, ... Only runs when
# vlpt_on=xray (shared with vlpt/vlpt2). Ports must be explicit; empty
# or non-numeric items are skipped with a warning, never auto-filled,
# so a typo cannot silently claim a random port.
if [ -n "$vlpt_more" ] && [ "$vlpt_on" = "xray" ]; then
if [ -z "$ym_vl_re" ]; then ym_vl_re=apple.com; fi
_vlpt_more_idx=3; _vlpt_more_oldifs="$IFS"; IFS=','
for _vlpt_more_p in $vlpt_more; do
  _vlpt_more_p=$(printf '%s' "$_vlpt_more_p" | xargs 2>/dev/null || printf '%s' "$_vlpt_more_p")
  case "$_vlpt_more_p" in ''|*[!0-9]*) echo "vlpt 更多实例端口格式错误，已跳过：$_vlpt_more_p"; _vlpt_more_idx=$((_vlpt_more_idx + 1)); continue;; esac
  echo "$_vlpt_more_p" > "$HOME/agsbx/port_vl_re$_vlpt_more_idx"
  echo "Vless-tcp-reality-v$_vlpt_more_idx端口：$_vlpt_more_p"
  cat >> "$HOME/agsbx/xr.json" <<EOF
        {
            "tag":"reality-vision-$_vlpt_more_idx",
            "listen": "::",
            "port": $_vlpt_more_p,
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
  _vlpt_more_idx=$((_vlpt_more_idx + 1))
done; IFS="$_vlpt_more_oldifs"
fi

