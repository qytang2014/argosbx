# Other protocols more instances on Sing-box (private module, loop).
# Inserted into installsb() after the vlpt-more block, before sspt is
# not applicable here: sspt itself is looped below, so this module is
# inserted at the end of installsb(), after the sspt block.
# Same while-loop parsing as proto-more-xray: trailing empty items
# are preserved, empty/random reuses the port file for that index,
# non-numeric items are skipped with a warning and the index advances.
# Sing-box protocols: nvpt, tupt, anpt, arpt, sspt.
# nvpt only installs when a domain certificate is ready, exactly like
# its first instance; arpt reuses the sbk Reality keypair (generating
# it if missing, like arpt/vlpt-sb); sspt reuses sskey (generating it
# if missing, like its first instance).
if [ -n "${nvpt_more:-}" ] && [ "${domain_cert_ready:-}" = "1" ]; then
  _pm_idx=2; _pm_rest="$nvpt_more"
  while :; do
    case "$_pm_rest" in *,*) _pm_p="${_pm_rest%%,*}"; _pm_rest="${_pm_rest#*,}";; *) _pm_p="$_pm_rest"; _pm_rest="__DONE__";; esac
    _pm_p=$(printf '%s' "$_pm_p" | xargs 2>/dev/null || printf '%s' "$_pm_p")
    case "$_pm_p" in ''|random)
      if [ -s "$HOME/agsbx/port_nv$_pm_idx" ]; then _pm_p=$(cat "$HOME/agsbx/port_nv$_pm_idx"); else _pm_p=$(shuf -i 10000-65535 -n 1); fi
      case "$_pm_p" in ''|*[!0-9]*) echo "nvpt 更多实例随机端口失败，已跳过第 $_pm_idx 个实例"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac ;;
    *[!0-9]*) echo "nvpt 更多实例端口格式错误，已跳过：$_pm_p"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac
    echo "$_pm_p" > "$HOME/agsbx/port_nv$_pm_idx"
    echo "Naiveproxy$_pm_idx端口：$_pm_p"
    cat >> "$HOME/agsbx/sb.json" <<EOF
    {
        "type": "naive",
        "tag": "naive-sb-$_pm_idx",
        "listen": "::",
        "listen_port": ${_pm_p},
        "users": [
            {
                "username": "${uuid}",
                "password": "${uuid}"
            }
        ],
        "tls": {
            "enabled": true,
            "certificate_path": "$CERT_CRT",
            "key_path": "$CERT_KEY"
        }
    },
EOF
    _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break
  done
fi
if [ -n "${tupt_more:-}" ]; then
  _pm_idx=2; _pm_rest="$tupt_more"
  while :; do
    case "$_pm_rest" in *,*) _pm_p="${_pm_rest%%,*}"; _pm_rest="${_pm_rest#*,}";; *) _pm_p="$_pm_rest"; _pm_rest="__DONE__";; esac
    _pm_p=$(printf '%s' "$_pm_p" | xargs 2>/dev/null || printf '%s' "$_pm_p")
    case "$_pm_p" in ''|random)
      if [ -s "$HOME/agsbx/port_tu$_pm_idx" ]; then _pm_p=$(cat "$HOME/agsbx/port_tu$_pm_idx"); else _pm_p=$(shuf -i 10000-65535 -n 1); fi
      case "$_pm_p" in ''|*[!0-9]*) echo "tupt 更多实例随机端口失败，已跳过第 $_pm_idx 个实例"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac ;;
    *[!0-9]*) echo "tupt 更多实例端口格式错误，已跳过：$_pm_p"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac
    echo "$_pm_p" > "$HOME/agsbx/port_tu$_pm_idx"
    echo "Tuic$_pm_idx端口：$_pm_p"
    cat >> "$HOME/agsbx/sb.json" <<EOF
        {
            "type":"tuic",
            "tag": "tuic5-sb-$_pm_idx",
            "listen": "::",
            "listen_port": ${_pm_p},
            "users": [
                {
                    "uuid": "${uuid}",
                    "password": "${uuid}"
                }
            ],
            "congestion_control": "bbr",
            "tls":{
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "$certificateHTA",
                "key_path": "$keyHTA"
            }
        },
EOF
    _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break
  done
fi
if [ -n "${anpt_more:-}" ]; then
  _pm_idx=2; _pm_rest="$anpt_more"
  while :; do
    case "$_pm_rest" in *,*) _pm_p="${_pm_rest%%,*}"; _pm_rest="${_pm_rest#*,}";; *) _pm_p="$_pm_rest"; _pm_rest="__DONE__";; esac
    _pm_p=$(printf '%s' "$_pm_p" | xargs 2>/dev/null || printf '%s' "$_pm_p")
    case "$_pm_p" in ''|random)
      if [ -s "$HOME/agsbx/port_an$_pm_idx" ]; then _pm_p=$(cat "$HOME/agsbx/port_an$_pm_idx"); else _pm_p=$(shuf -i 10000-65535 -n 1); fi
      case "$_pm_p" in ''|*[!0-9]*) echo "anpt 更多实例随机端口失败，已跳过第 $_pm_idx 个实例"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac ;;
    *[!0-9]*) echo "anpt 更多实例端口格式错误，已跳过：$_pm_p"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac
    echo "$_pm_p" > "$HOME/agsbx/port_an$_pm_idx"
    echo "Anytls$_pm_idx端口：$_pm_p"
    cat >> "$HOME/agsbx/sb.json" <<EOF
        {
            "type":"anytls",
            "tag":"anytls-sb-$_pm_idx",
            "listen":"::",
            "listen_port":${_pm_p},
            "users":[
                {
                  "password":"${uuid}"
                }
            ],
            "padding_scheme":[],
            "tls":{
                "enabled": true,
                "certificate_path": "$certificateHTA",
                "key_path": "$keyHTA"
            }
        },
EOF
    _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break
  done
fi
if [ -n "${arpt_more:-}" ]; then
  if [ -z "$ym_vl_re" ]; then ym_vl_re=apple.com; fi
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
  _pm_idx=2; _pm_rest="$arpt_more"
  while :; do
    case "$_pm_rest" in *,*) _pm_p="${_pm_rest%%,*}"; _pm_rest="${_pm_rest#*,}";; *) _pm_p="$_pm_rest"; _pm_rest="__DONE__";; esac
    _pm_p=$(printf '%s' "$_pm_p" | xargs 2>/dev/null || printf '%s' "$_pm_p")
    case "$_pm_p" in ''|random)
      if [ -s "$HOME/agsbx/port_ar$_pm_idx" ]; then _pm_p=$(cat "$HOME/agsbx/port_ar$_pm_idx"); else _pm_p=$(shuf -i 10000-65535 -n 1); fi
      case "$_pm_p" in ''|*[!0-9]*) echo "arpt 更多实例随机端口失败，已跳过第 $_pm_idx 个实例"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac ;;
    *[!0-9]*) echo "arpt 更多实例端口格式错误，已跳过：$_pm_p"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac
    echo "$_pm_p" > "$HOME/agsbx/port_ar$_pm_idx"
    echo "Any-Reality$_pm_idx端口：$_pm_p"
    cat >> "$HOME/agsbx/sb.json" <<EOF
        {
            "type":"anytls",
            "tag":"anyreality-sb-$_pm_idx",
            "listen":"::",
            "listen_port":${_pm_p},
            "users":[
                {
                  "password":"${uuid}"
                }
            ],
            "padding_scheme":[],
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
    _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break
  done
fi
if [ -n "${sspt_more:-}" ]; then
  if [ ! -e "$HOME/agsbx/sskey" ]; then
    sskey=$("$HOME/agsbx/sing-box" generate rand 16 --base64)
    echo "$sskey" > "$HOME/agsbx/sskey"
  fi
  sskey=$(cat "$HOME/agsbx/sskey")
  _pm_idx=2; _pm_rest="$sspt_more"
  while :; do
    case "$_pm_rest" in *,*) _pm_p="${_pm_rest%%,*}"; _pm_rest="${_pm_rest#*,}";; *) _pm_p="$_pm_rest"; _pm_rest="__DONE__";; esac
    _pm_p=$(printf '%s' "$_pm_p" | xargs 2>/dev/null || printf '%s' "$_pm_p")
    case "$_pm_p" in ''|random)
      if [ -s "$HOME/agsbx/port_ss$_pm_idx" ]; then _pm_p=$(cat "$HOME/agsbx/port_ss$_pm_idx"); else _pm_p=$(shuf -i 10000-65535 -n 1); fi
      case "$_pm_p" in ''|*[!0-9]*) echo "sspt 更多实例随机端口失败，已跳过第 $_pm_idx 个实例"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac ;;
    *[!0-9]*) echo "sspt 更多实例端口格式错误，已跳过：$_pm_p"; _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break || continue;; esac
    echo "$_pm_p" > "$HOME/agsbx/port_ss$_pm_idx"
    echo "Shadowsocks-2022$_pm_idx端口：$_pm_p"
    cat >> "$HOME/agsbx/sb.json" <<EOF
        {
            "type": "shadowsocks",
            "tag":"ss-2022-$_pm_idx",
            "listen": "::",
            "listen_port": $_pm_p,
            "method": "2022-blake3-aes-128-gcm",
            "password": "$sskey"
    },
EOF
    _pm_idx=$((_pm_idx + 1)); [ "$_pm_rest" = "__DONE__" ] && break
  done
fi
