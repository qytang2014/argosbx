# vmpt more instances (private module, loop). Inserted into xrsbvm()
# after the first instance. Same rule as the first instance: xr.json
# when Xray is installed, otherwise sb.json. Shares uuid and the
# ws path ${uuid}-vm, own port and tag vmess-xr-N / vmess-sb-N.
if [ -n "${vmpt_more:-}" ]; then
  _pm_idx=2; _pm_rest="$vmpt_more"
  while :; do
    case "$_pm_rest" in *,*) _pm_p="${_pm_rest%%,*}"; _pm_rest="${_pm_rest#*,}";; *) _pm_p="$_pm_rest"; _pm_rest="__DONE__";; esac
    _pm_p=$(printf '%s' "$_pm_p" | xargs 2>/dev/null || printf '%s' "$_pm_p")
    case "$_pm_p" in ''|random)
      if [ -s "$HOME/agsbx/port_vm_ws$_pm_idx" ]; then _pm_p=$(cat "$HOME/agsbx/port_vm_ws$_pm_idx"); else _pm_p=$(shuf -i 10000-65535 -n 1); fi
      case "$_pm_p" in ''|*[!0-9]*) echo "vmpt 更多实例随机端口失败，已跳过第 $_pm_idx 个实例"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac ;;
    *[!0-9]*) echo "vmpt 更多实例端口格式错误，已跳过：$_pm_p"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac
    echo "$_pm_p" > "$HOME/agsbx/port_vm_ws$_pm_idx"
    echo "Vmess-ws$_pm_idx端口：$_pm_p"
    if [ -e "$HOME/agsbx/xr.json" ]; then
      cat >> "$HOME/agsbx/xr.json" <<EOF
        {
            "tag": "vmess-xr-$_pm_idx",
            "listen": "::",
            "port": ${_pm_p},
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
                "security": "none",
                "wsSettings": {
                  "path": "${uuid}-vm"
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
        "tag": "vmess-sb-$_pm_idx",
        "listen": "::",
        "listen_port": ${_pm_p},
        "users": [
            {
                "uuid": "${uuid}",
                "alterId": 0
            }
        ],
        "transport": {
            "type": "ws",
            "path": "${uuid}-vm",
            "max_early_data":2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"
        }
    },
EOF
    fi
    _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break
  done
fi
