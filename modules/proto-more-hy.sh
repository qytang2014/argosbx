# hypt more instances (private module, loop). Inserted into xrsbhy2()
# after the first instance. Same rule as the first instance: writes to
# xr.json when Xray is installed, otherwise to sb.json. Shares uuid
# and the TLS certificate pair, own port and tag hy2-xr-N / hy2-sb-N.
if [ -n "${hypt_more:-}" ]; then
  _pm_idx=2; _pm_rest="$hypt_more"
  while :; do
    case "$_pm_rest" in *,*) _pm_p="${_pm_rest%%,*}"; _pm_rest="${_pm_rest#*,}";; *) _pm_p="$_pm_rest"; _pm_rest="__DONE__";; esac
    _pm_p=$(printf '%s' "$_pm_p" | xargs 2>/dev/null || printf '%s' "$_pm_p")
    case "$_pm_p" in ''|random)
      if [ -s "$HOME/agsbx/port_hy2$_pm_idx" ]; then _pm_p=$(cat "$HOME/agsbx/port_hy2$_pm_idx"); else _pm_p=$(shuf -i 10000-65535 -n 1); fi
      case "$_pm_p" in ''|*[!0-9]*) echo "hypt 更多实例随机端口失败，已跳过第 $_pm_idx 个实例"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac ;;
    *[!0-9]*) echo "hypt 更多实例端口格式错误，已跳过：$_pm_p"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac
    echo "$_pm_p" > "$HOME/agsbx/port_hy2$_pm_idx"
    echo "Hysteria2$_pm_idx端口：$_pm_p"
    if [ -e "$HOME/agsbx/xr.json" ]; then
      cat >> "$HOME/agsbx/xr.json" <<EOF
    {
      "tag": "hy2-xr-$_pm_idx",
      "protocol": "hysteria",
      "port": ${_pm_p},
      "settings": {
        "version": 2,
        "clients": [
          {
            "auth": "${uuid}"
          }
        ]
      },
      "streamSettings": {
        "network": "hysteria",
        "security": "tls",
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
    else
      cat >> "$HOME/agsbx/sb.json" <<EOF
    {
        "type": "hysteria2",
        "tag": "hy2-sb-$_pm_idx",
        "listen": "::",
        "listen_port": ${_pm_p},
        "users": [
            {
                "password": "${uuid}"
            }
        ],
        "ignore_client_bandwidth":false,
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "$certificateHTA",
            "key_path": "$keyHTA"
        }
    },
EOF
    fi
    _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break
  done
fi
