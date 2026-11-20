# sbvlpt-restore.sh: restore upstream-deleted sbvlpt()/sbvlpt1()
# (upstream d4f4b91 deleted the sing-box subscription entry for vlpt;
# QUINN decided 2026-11-19 to keep it). Inserted by build.py before
# sbsspt(). pbk/sid are kernel-aware ($vlpt_pbk/$vlpt_sid, set by
# vlpt-display-pbk); server is $server_ip here so the reality-sb-config
# patch (which rewrites it to $reality_addr) still finds exactly one
# occurrence. encryption stays none: sing-box has no VLESS Encryption.
sbvlpt(){
cat <<EOF
    {
      "type": "vless",
      "tag": "${sxname}vless-$hostname",
      "server": "$server_ip",
      "server_port": $port_vl_re,
      "uuid": "$uuid",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$ym_vl_re",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
      "reality": {
          "enabled": true,
          "public_key": "$vlpt_pbk",
          "short_id": "$vlpt_sid"
        }
      }
    },
EOF
}
sbvlpt1(){
echo "\"${sxname}vless-$hostname\","
}
