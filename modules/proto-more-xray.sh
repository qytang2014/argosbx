# Other protocols more instances on Xray (private module, loop).
# Inserted into installxray() after the vlpt-more block, before it ends.
# Each *_more list installs instances 2, 3, ... in order, sharing the
# first instance's uuid, keys, SNI, flow and encryption seed, with
# their own port and inbound tag <base>-N, and port file <base>N.
# Parsing is a while loop (not for over IFS) so trailing empty items
# are preserved: "10001," creates instance 2 with a random port.
# Empty or "random" reuses the existing port file for that index if
# present, so rep keeps the same random port; non-numeric items are
# skipped with a warning and the instance number still advances.
# Xray-only protocols: xhpt, vxpt, vwpt, xupt, xcpt.
if [ -n "${xhpt_more:-}" ]; then
  _pm_idx=2; _pm_rest="$xhpt_more"
  while :; do
    case "$_pm_rest" in *,*) _pm_p="${_pm_rest%%,*}"; _pm_rest="${_pm_rest#*,}";; *) _pm_p="$_pm_rest"; _pm_rest="__DONE__";; esac
    _pm_p=$(printf '%s' "$_pm_p" | xargs 2>/dev/null || printf '%s' "$_pm_p")
    case "$_pm_p" in ''|random)
      if [ -s "$HOME/agsbx/port_xh$_pm_idx" ]; then _pm_p=$(cat "$HOME/agsbx/port_xh$_pm_idx"); else _pm_p=$(shuf -i 10000-65535 -n 1); fi
      case "$_pm_p" in ''|*[!0-9]*) echo "xhpt 更多实例随机端口失败，已跳过第 $_pm_idx 个实例"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac ;;
    *[!0-9]*) echo "xhpt 更多实例端口格式错误，已跳过：$_pm_p"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac
    echo "$_pm_p" > "$HOME/agsbx/port_xh$_pm_idx"
    echo "Vless-xhttp-reality-enc$_pm_idx端口：$_pm_p"
    cat >> "$HOME/agsbx/xr.json" <<EOF
    {
      "tag":"xhttp-reality-$_pm_idx",
      "listen": "::",
      "port": ${_pm_p},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "${dekey}"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "chrome",
          "target": "${ym_vl_re}:443",
          "serverNames": [
            "${ym_vl_re}"
          ],
          "privateKey": "$private_key_x",
          "shortIds": ["$short_id_x"]
        },
        "xhttpSettings": {
          "host": "",
          "path": "${uuid}-xh",
          "mode": "auto"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    },
EOF
    _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break
  done
fi
if [ -n "${vxpt_more:-}" ]; then
  _pm_idx=2; _pm_rest="$vxpt_more"
  while :; do
    case "$_pm_rest" in *,*) _pm_p="${_pm_rest%%,*}"; _pm_rest="${_pm_rest#*,}";; *) _pm_p="$_pm_rest"; _pm_rest="__DONE__";; esac
    _pm_p=$(printf '%s' "$_pm_p" | xargs 2>/dev/null || printf '%s' "$_pm_p")
    case "$_pm_p" in ''|random)
      if [ -s "$HOME/agsbx/port_vx$_pm_idx" ]; then _pm_p=$(cat "$HOME/agsbx/port_vx$_pm_idx"); else _pm_p=$(shuf -i 10000-65535 -n 1); fi
      case "$_pm_p" in ''|*[!0-9]*) echo "vxpt 更多实例随机端口失败，已跳过第 $_pm_idx 个实例"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac ;;
    *[!0-9]*) echo "vxpt 更多实例端口格式错误，已跳过：$_pm_p"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac
    echo "$_pm_p" > "$HOME/agsbx/port_vx$_pm_idx"
    echo "Vless-xhttp-enc$_pm_idx端口：$_pm_p"
    cat >> "$HOME/agsbx/xr.json" <<EOF
    {
      "tag":"vless-xhttp-$_pm_idx",
      "listen": "::",
      "port": ${_pm_p},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "${dekey}"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "host": "",
          "path": "${uuid}-vx",
          "mode": "auto"
        }
      },
        "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    },
EOF
    _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break
  done
fi
if [ -n "${vwpt_more:-}" ]; then
  _pm_idx=2; _pm_rest="$vwpt_more"
  while :; do
    case "$_pm_rest" in *,*) _pm_p="${_pm_rest%%,*}"; _pm_rest="${_pm_rest#*,}";; *) _pm_p="$_pm_rest"; _pm_rest="__DONE__";; esac
    _pm_p=$(printf '%s' "$_pm_p" | xargs 2>/dev/null || printf '%s' "$_pm_p")
    case "$_pm_p" in ''|random)
      if [ -s "$HOME/agsbx/port_vw$_pm_idx" ]; then _pm_p=$(cat "$HOME/agsbx/port_vw$_pm_idx"); else _pm_p=$(shuf -i 10000-65535 -n 1); fi
      case "$_pm_p" in ''|*[!0-9]*) echo "vwpt 更多实例随机端口失败，已跳过第 $_pm_idx 个实例"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac ;;
    *[!0-9]*) echo "vwpt 更多实例端口格式错误，已跳过：$_pm_p"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac
    echo "$_pm_p" > "$HOME/agsbx/port_vw$_pm_idx"
    echo "Vless-ws-enc$_pm_idx端口：$_pm_p"
    cat >> "$HOME/agsbx/xr.json" <<EOF
    {
      "tag":"vless-ws-$_pm_idx",
      "listen": "::",
      "port": ${_pm_p},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "${dekey}"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${uuid}-vw"
        }
      },
        "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    },
EOF
    _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break
  done
fi
if [ -n "${xupt_more:-}" ]; then
  _pm_idx=2; _pm_rest="$xupt_more"
  while :; do
    case "$_pm_rest" in *,*) _pm_p="${_pm_rest%%,*}"; _pm_rest="${_pm_rest#*,}";; *) _pm_p="$_pm_rest"; _pm_rest="__DONE__";; esac
    _pm_p=$(printf '%s' "$_pm_p" | xargs 2>/dev/null || printf '%s' "$_pm_p")
    case "$_pm_p" in ''|random)
      if [ -s "$HOME/agsbx/port_xu$_pm_idx" ]; then _pm_p=$(cat "$HOME/agsbx/port_xu$_pm_idx"); else _pm_p=$(shuf -i 10000-65535 -n 1); fi
      case "$_pm_p" in ''|*[!0-9]*) echo "xupt 更多实例随机端口失败，已跳过第 $_pm_idx 个实例"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac ;;
    *[!0-9]*) echo "xupt 更多实例端口格式错误，已跳过：$_pm_p"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac
    echo "$_pm_p" > "$HOME/agsbx/port_xu$_pm_idx"
    echo "Vless-xhttp-tls-UDP$_pm_idx端口：$_pm_p"
    cat >> "$HOME/agsbx/xr.json" <<EOF
{
  "tag": "xhttp-h3-$_pm_idx",
  "listen": "::",
  "port": ${_pm_p},
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id": "${uuid}",
        "flow": ""
      }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "xhttp",
    "security": "tls",
    "xhttpSettings": {
    "mode": "auto",
    "path": "${uuid}-xu"
    },
    "tlsSettings": {
      "alpn": [
        "h3"
      ],
      "certificates": [
        {
          "certificateFile": "$certificateHTA",
          "keyFile": "$keyHTA"
        }
      ]
    }
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls", "quic"],
   "metadataOnly": false
  }
},
EOF
    _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break
  done
fi
if [ -n "${xcpt_more:-}" ]; then
  _pm_idx=2; _pm_rest="$xcpt_more"
  while :; do
    case "$_pm_rest" in *,*) _pm_p="${_pm_rest%%,*}"; _pm_rest="${_pm_rest#*,}";; *) _pm_p="$_pm_rest"; _pm_rest="__DONE__";; esac
    _pm_p=$(printf '%s' "$_pm_p" | xargs 2>/dev/null || printf '%s' "$_pm_p")
    case "$_pm_p" in ''|random)
      if [ -s "$HOME/agsbx/port_xc$_pm_idx" ]; then _pm_p=$(cat "$HOME/agsbx/port_xc$_pm_idx"); else _pm_p=$(shuf -i 10000-65535 -n 1); fi
      case "$_pm_p" in ''|*[!0-9]*) echo "xcpt 更多实例随机端口失败，已跳过第 $_pm_idx 个实例"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac ;;
    *[!0-9]*) echo "xcpt 更多实例端口格式错误，已跳过：$_pm_p"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac
    echo "$_pm_p" > "$HOME/agsbx/port_xc$_pm_idx"
    echo "Vless-xhttp-tls-TCP/UDP$_pm_idx端口：$_pm_p"
    cat >> "$HOME/agsbx/xr.json" <<EOF
{
  "tag": "xhttp-h23-$_pm_idx",
  "listen": "::",
  "port": ${_pm_p},
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id": "${uuid}",
        "flow": ""
      }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "xhttp",
    "security": "tls",
    "xhttpSettings": {
    "mode": "auto",
    "path": "${uuid}-xc"
    },
    "tlsSettings": {
     "alpn": [
      "h2","http/1.1"
       ],
      "certificates": [
        {
          "certificateFile": "$certificateHTA",
          "keyFile": "$keyHTA"
        }
      ]
    }
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls", "quic"],
   "metadataOnly": false
  }
},
EOF
    _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break
  done
fi
