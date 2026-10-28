# vlpt more instances on Xray (private module, loop, not per-instance copies).
# vlpt_more="10002,10003" installs instances 2, 3, ... in order, sharing
# vlpt's uuid, Reality keypair (xrk), SNI and flow, with their own port
# and inbound tag reality-vision-2, reality-vision-3, ... Only runs when
# vlpt_on=xray (shared with vlpt). If the old vlpt2 variable is also
# set, vlpt_more starts at 3, so it never overwrites instance 2.
# Parsing is a while loop, not a for loop over IFS: a for loop drops
# trailing empty items ("10001," would lose instance 2), while the
# while loop preserves every item, including trailing empties. An
# empty item or "random" means a random port (reusing the port file
# if it already exists, so rep keeps the same random port); a
# non-numeric, non-empty item is skipped with a warning, and the
# instance number still advances, so later instances keep their tag.
if [ -n "$vlpt_more" ] && [ "$vlpt_on" = "xray" ]; then
if [ -z "$ym_vl_re" ]; then ym_vl_re=apple.com; fi
if [ "$vlp2" = yes ] || [ -n "$vlpt2" ]; then _vlpt_more_idx=3; else _vlpt_more_idx=2; fi
_vlpt_more_rest="$vlpt_more"
while :; do
  case "$_vlpt_more_rest" in *,*) _vlpt_more_p="${_vlpt_more_rest%%,*}"; _vlpt_more_rest="${_vlpt_more_rest#*,}";; *) _vlpt_more_p="$_vlpt_more_rest"; _vlpt_more_rest="__DONE__";; esac
  _vlpt_more_p=$(printf '%s' "$_vlpt_more_p" | xargs 2>/dev/null || printf '%s' "$_vlpt_more_p")
  case "$_vlpt_more_p" in ''|random)
    if [ -s "$HOME/agsbx/port_vl_re$_vlpt_more_idx" ]; then _vlpt_more_p=$(cat "$HOME/agsbx/port_vl_re$_vlpt_more_idx"); else _vlpt_more_p=$(shuf -i 10000-65535 -n 1); fi
    case "$_vlpt_more_p" in ''|*[!0-9]*) echo "vlpt 更多实例随机端口失败，已跳过第 $_vlpt_more_idx 个实例"; _vlpt_more_idx=$((_vlpt_more_idx + 1)); [ "$_vlpt_more_rest" = "__DONE__" ] && break || continue;; esac
    ;;
  *[!0-9]*) echo "vlpt 更多实例端口格式错误，已跳过：$_vlpt_more_p"; _vlpt_more_idx=$((_vlpt_more_idx + 1)); [ "$_vlpt_more_rest" = "__DONE__" ] && break || continue;; esac
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
  [ "$_vlpt_more_rest" = "__DONE__" ] && break
done
fi

