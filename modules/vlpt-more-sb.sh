# vlpt more instances on Sing-box (private module, loop).
# Same vlpt_more list as the Xray block, instances 2, 3, ... in order
# (3, 4, ... if the old vlpt2 variable is also set), sharing vlpt's
# uuid and Sing-box Reality keypair (sbk), with their own port and
# inbound tag vl-reality-sb-2, vl-reality-sb-3, ...
# Only runs when vlpt_on=sb. Generates sbk if missing, like vlpt-sb.
if [ -n "$vlpt_more" ] && [ "$vlpt_on" = "sb" ]; then
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
  echo "Vless-tcp-reality-v$_vlpt_more_idx端口（Sing-box）：$_vlpt_more_p"
  cat >> "$HOME/agsbx/sb.json" <<EOF
    {
        "type": "vless",
        "tag": "vl-reality-sb-$_vlpt_more_idx",
        "listen": "::",
        "listen_port": ${_vlpt_more_p},
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
  _vlpt_more_idx=$((_vlpt_more_idx + 1))
  [ "$_vlpt_more_rest" = "__DONE__" ] && break
done
fi

