# sopt more instances (private module, loop). Inserted into xrsbso()
# after the first instance. Same rule as the first instance: xr.json
# when Xray is installed, otherwise sb.json. Shares uuid as both
# username and password, own port and tag socks5-xr-N / socks5-sb-N.
if [ -n "${sopt_more:-}" ]; then
  _pm_idx=2; _pm_rest="$sopt_more"
  while :; do
    case "$_pm_rest" in *,*) _pm_p="${_pm_rest%%,*}"; _pm_rest="${_pm_rest#*,}";; *) _pm_p="$_pm_rest"; _pm_rest="__DONE__";; esac
    _pm_p=$(printf '%s' "$_pm_p" | xargs 2>/dev/null || printf '%s' "$_pm_p")
    case "$_pm_p" in ''|random)
      if [ -s "$HOME/agsbx/port_so$_pm_idx" ]; then _pm_p=$(cat "$HOME/agsbx/port_so$_pm_idx"); else _pm_p=$(shuf -i 10000-65535 -n 1); fi
      case "$_pm_p" in ''|*[!0-9]*) echo "sopt 更多实例随机端口失败，已跳过第 $_pm_idx 个实例"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac ;;
    *[!0-9]*) echo "sopt 更多实例端口格式错误，已跳过：$_pm_p"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac
    echo "$_pm_p" > "$HOME/agsbx/port_so$_pm_idx"
    echo "Socks5${_pm_idx}端口：$_pm_p"
    if [ -e "$HOME/agsbx/xr.json" ]; then
      cat >> "$HOME/agsbx/xr.json" <<EOF
        {
         "tag": "socks5-xr-$_pm_idx",
         "port": ${_pm_p},
         "listen": "::",
         "protocol": "socks",
         "settings": {
            "auth": "password",
             "accounts": [
               {
               "user": "${uuid}",
               "pass": "${uuid}"
               }
            ],
            "udp": true
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
      "tag": "socks5-sb-$_pm_idx",
      "type": "socks",
      "listen": "::",
      "listen_port": ${_pm_p},
      "users": [
      {
      "username": "${uuid}",
      "password": "${uuid}"
      }
     ]
    },
EOF
    fi
    _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break
  done
fi
