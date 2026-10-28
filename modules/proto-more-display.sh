# Other protocols more instances display (private module, loop).
# Instance numbers come from the inbound tags actually present in
# xr.json / sb.json (base-N, N >= 2), never from port files alone,
# so a stale port file from a removed instance cannot resurrect a
# link. Native links are printed here; subscription nodes are
# produced by the sb*_more / cl*_more functions below, which loop
# over the same tag list at subscription-build time.
# Extra instances use the direct (non-CDN) variant, like the first
# instance's direct link; CDN variants for extra instances are not
# generated, the first instance's CDN link remains usable.
# Protocols with no SB/Clash node in the first instance (xhpt, vxpt,
# vwpt, sopt) get native links only, exactly like the first instance.
_pm_idx_list() {
_pm_base="$1"; _pm_file="$2"
grep -o "\"tag\"[^,]*\"$_pm_base-[0-9][0-9]*\"" "$_pm_file" 2>/dev/null | sed -E 's/.*-([0-9]+)"/\1/' | sort -nu
}
# xhpt
for _pm_i in $(_pm_idx_list "xhttp-reality" "$HOME/agsbx/xr.json"); do
_pm_p=$(cat "$HOME/agsbx/port_xh$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
echo "💣支持ENC加密，节点信息如下："
_pm_link="vless://$uuid@$reality_addr:$_pm_p?encryption=$enkey&flow=xtls-rprx-vision&security=reality&sni=$ym_vl_re&fp=chrome&pbk=$public_key_x&sid=$short_id_x&type=xhttp&path=$uuid-xh&mode=auto#${sxname}vl-xhttp-reality-enc-$_pm_i-$hostname"
echo "$_pm_link" >> "$HOME/agsbx/jhsub.txt"; echo "$_pm_link"; echo
done
# vxpt
for _pm_i in $(_pm_idx_list "vless-xhttp" "$HOME/agsbx/xr.json"); do
_pm_p=$(cat "$HOME/agsbx/port_vx$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
echo "💣支持ENC加密，节点信息如下："
_pm_link="vless://$uuid@$domain_addr:$_pm_p?encryption=$enkey&flow=xtls-rprx-vision&type=xhttp&path=$uuid-vx&mode=auto#${sxname}vl-xhttp-enc-$_pm_i-$hostname"
echo "$_pm_link" >> "$HOME/agsbx/jhsub.txt"; echo "$_pm_link"; echo
done
# vwpt
for _pm_i in $(_pm_idx_list "vless-ws" "$HOME/agsbx/xr.json"); do
_pm_p=$(cat "$HOME/agsbx/port_vw$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
echo "💣支持ENC加密，节点信息如下："
_pm_link="vless://$uuid@$domain_addr:$_pm_p?encryption=$enkey&flow=xtls-rprx-vision&type=ws&path=$uuid-vw#${sxname}vl-ws-enc-$_pm_i-$hostname"
echo "$_pm_link" >> "$HOME/agsbx/jhsub.txt"; echo "$_pm_link"; echo
done
# xupt
for _pm_i in $(_pm_idx_list "xhttp-h3" "$HOME/agsbx/xr.json"); do
_pm_p=$(cat "$HOME/agsbx/port_xu$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
echo "💣节点信息如下："
if [ "$pin_on" = "1" ]; then _pm_sha=$(cat "$HOME/agsbx/SHA256.txt" 2>/dev/null); else _pm_sha=""; fi
_pm_link="vless://$uuid@$add:$_pm_p?encryption=none&security=tls&sni=$sni&alpn=h3&insecure=0&allowInsecure=0&hpkp=$_pm_sha&pcs=$_pm_sha&type=xhttp&path=$uuid-xu&mode=auto#${sxname}Vless-xhttp-tls-UDP-$_pm_i-$hostname"
echo "$_pm_link" >> "$HOME/agsbx/jhsub.txt"; echo "$_pm_link"; echo
done
clxupt_more() {
for _pm_i in $(_pm_idx_list "xhttp-h3" "$HOME/agsbx/xr.json"); do
_pm_p=$(cat "$HOME/agsbx/port_xu$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
cat <<EOF
- name: ${sxname}Xhttp-UDP-$_pm_i-$hostname
type: vless
server: $add
port: $_pm_p
uuid: $uuid
udp: true
tls: true
network: xhttp
alpn:
- h3
servername: $sni
client-fingerprint: chrome
skip-cert-verify: $cl_skip
$cl_pin_line
xhttp-opts:
path: "$uuid-xu"
mode: auto
EOF
done
}
clxupt_more_1() {
for _pm_i in $(_pm_idx_list "xhttp-h3" "$HOME/agsbx/xr.json"); do echo "- ${sxname}Xhttp-UDP-$_pm_i-$hostname"; done
}
# xcpt
for _pm_i in $(_pm_idx_list "xhttp-h23" "$HOME/agsbx/xr.json"); do
_pm_p=$(cat "$HOME/agsbx/port_xc$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
echo "💣节点信息如下："
_pm_link="vless://$uuid@$add:$_pm_p?encryption=none&security=tls&sni=$sni&insecure=0&allowInsecure=0&type=xhttp&path=$uuid-xc&mode=auto#${sxname}Vless-xhttp-tls-TCP-$_pm_i-$hostname"
echo "$_pm_link" >> "$HOME/agsbx/jhsub.txt"; echo "$_pm_link"; echo
done
clxcpt_more() {
for _pm_i in $(_pm_idx_list "xhttp-h23" "$HOME/agsbx/xr.json"); do
_pm_p=$(cat "$HOME/agsbx/port_xc$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
cat <<EOF
- name: ${sxname}Xhttp-TCP-$_pm_i-$hostname
type: vless
server: $add
port: $_pm_p
uuid: $uuid
udp: true
tls: true
network: xhttp
servername: $sni
client-fingerprint: chrome
skip-cert-verify: $cl_skip
$cl_pin_line
xhttp-opts:
path: "$uuid-xc"
mode: auto
EOF
done
}
clxcpt_more_1() {
for _pm_i in $(_pm_idx_list "xhttp-h23" "$HOME/agsbx/xr.json"); do echo "- ${sxname}Xhttp-TCP-$_pm_i-$hostname"; done
}
# sspt
for _pm_i in $(_pm_idx_list "ss-2022" "$HOME/agsbx/sb.json"); do
_pm_p=$(cat "$HOME/agsbx/port_ss$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
echo "💣节点信息如下："
_pm_link="ss://$(echo -n "2022-blake3-aes-128-gcm:$sskey@$domain_addr:$_pm_p" | base64 -w0)#${sxname}Shadowsocks-2022-$_pm_i-$hostname"
echo "$_pm_link" >> "$HOME/agsbx/jhsub.txt"; echo "$_pm_link"; echo
done
sbsspt_more() {
for _pm_i in $(_pm_idx_list "ss-2022" "$HOME/agsbx/sb.json"); do
_pm_p=$(cat "$HOME/agsbx/port_ss$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
cat <<EOF
{
"type": "shadowsocks",
"tag": "${sxname}Shadowsocks-2022-$_pm_i-$hostname",
"server": "$domain_addr",
"server_port": $_pm_p,
"method": "2022-blake3-aes-128-gcm",
"password": "$sskey"
},
EOF
done
}
sbsspt_more_1() {
for _pm_i in $(_pm_idx_list "ss-2022" "$HOME/agsbx/sb.json"); do echo "\"${sxname}Shadowsocks-2022-$_pm_i-$hostname\","; done
}
clsspt_more() {
for _pm_i in $(_pm_idx_list "ss-2022" "$HOME/agsbx/sb.json"); do
_pm_p=$(cat "$HOME/agsbx/port_ss$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
cat <<EOF
- name: "${sxname}Shadowsocks-2022-$_pm_i-$hostname"
type: ss
server: $domain_addr
port: $_pm_p
cipher: 2022-blake3-aes-128-gcm
password: "$sskey"
udp: true
EOF
done
}
clsspt_more_1() {
for _pm_i in $(_pm_idx_list "ss-2022" "$HOME/agsbx/sb.json"); do echo "- ${sxname}Shadowsocks-2022-$_pm_i-$hostname"; done
}
# nvpt
for _pm_i in $(_pm_idx_list "naive-sb" "$HOME/agsbx/sb.json"); do
_pm_p=$(cat "$HOME/agsbx/port_nv$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
_pm_ym=$(cat "$HOME/agsbx/ym" 2>/dev/null)
echo "💣节点信息如下："
_pm_link="naive+https://$uuid:$uuid@$_pm_ym:$_pm_p?security=tls&sni=$_pm_ym&insecure=0&allowInsecure=0#${sxname}naive-h2-$_pm_i-$hostname"
echo "$_pm_link" >> "$HOME/agsbx/jhsub.txt"; echo "$_pm_link"
_pm_link="naive+quic://$uuid:$uuid@$_pm_ym:$_pm_p?congestion_control=bbr&security=tls&sni=$_pm_ym&insecure=0&allowInsecure=0#${sxname}naive-h3-$_pm_i-$hostname"
echo "$_pm_link" >> "$HOME/agsbx/jhsub.txt"; echo "$_pm_link"; echo
done
sbnvpt_more() {
for _pm_i in $(_pm_idx_list "naive-sb" "$HOME/agsbx/sb.json"); do
_pm_p=$(cat "$HOME/agsbx/port_nv$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
_pm_ym=$(cat "$HOME/agsbx/ym" 2>/dev/null)
cat <<EOF
{
"type": "naive",
"tag": "${sxname}naive-h3-$_pm_i-$hostname",
"server": "$_pm_ym",
"server_port": $_pm_p,
"username": "$uuid",
"password": "$uuid",
"udp_over_tcp": false,
"quic": true,
"quic_congestion_control": "bbr",
"tls": {
"enabled": true,
"insecure": false,
"server_name": "$_pm_ym"
}
},
{
"type": "naive",
"tag": "${sxname}naive-h2-$_pm_i-$hostname",
"server": "$_pm_ym",
"server_port": $_pm_p,
"username": "$uuid",
"password": "$uuid",
"udp_over_tcp": true,
"quic": false,
"tls": {
"enabled": true,
"insecure": false,
"server_name": "$_pm_ym"
}
},
EOF
done
}
sbnvpt_more_1() {
for _pm_i in $(_pm_idx_list "naive-sb" "$HOME/agsbx/sb.json"); do echo "\"${sxname}naive-h3-$_pm_i-$hostname\","; echo "\"${sxname}naive-h2-$_pm_i-$hostname\","; done
}
# tupt
for _pm_i in $(_pm_idx_list "tuic5-sb" "$HOME/agsbx/sb.json"); do
_pm_p=$(cat "$HOME/agsbx/port_tu$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
echo "💣节点信息如下："
_pm_link="tuic://$uuid:$uuid@$add:$_pm_p?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$sni&insecure=$jhins&allowInsecure=$jhins&allow_insecure=$jhins#${sxname}tuic-$_pm_i-$hostname"
echo "$_pm_link" >> "$HOME/agsbx/jhsub.txt"; echo "$_pm_link"; echo
done
sbtupt_more() {
for _pm_i in $(_pm_idx_list "tuic5-sb" "$HOME/agsbx/sb.json"); do
_pm_p=$(cat "$HOME/agsbx/port_tu$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
cat <<EOF
{
"type":"tuic",
"tag": "${sxname}tuic5-$_pm_i-$hostname",
"server": "$add",
"server_port": $_pm_p,
"uuid": "$uuid",
"password": "$uuid",
"congestion_control": "bbr",
"udp_relay_mode": "native",
"udp_over_stream": false,
"zero_rtt_handshake": false,
"heartbeat": "10s",
"tls":{
"enabled": true,
"server_name": "$sni",
"insecure": $sb_insecure$sb_pin_field,
"alpn": [
"h3"
]
}
},
EOF
done
}
sbtupt_more_1() {
for _pm_i in $(_pm_idx_list "tuic5-sb" "$HOME/agsbx/sb.json"); do echo "\"${sxname}tuic5-$_pm_i-$hostname\","; done
}
cltupt_more() {
for _pm_i in $(_pm_idx_list "tuic5-sb" "$HOME/agsbx/sb.json"); do
_pm_p=$(cat "$HOME/agsbx/port_tu$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
cat <<EOF
- name: ${sxname}tuic5-$_pm_i-$hostname
server: $add
port: $_pm_p
type: tuic
uuid: $uuid
password: "$uuid"
alpn: [h3]
disable-sni: true
reduce-rtt: true
udp-relay-mode: native
congestion-controller: bbr
sni: $sni
skip-cert-verify: $cl_skip
$cl_pin_line
EOF
done
}
cltupt_more_1() {
for _pm_i in $(_pm_idx_list "tuic5-sb" "$HOME/agsbx/sb.json"); do echo "- ${sxname}tuic5-$_pm_i-$hostname"; done
}
# anpt
for _pm_i in $(_pm_idx_list "anytls-sb" "$HOME/agsbx/sb.json"); do
_pm_p=$(cat "$HOME/agsbx/port_an$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
echo "💣节点信息如下："
_pm_link="anytls://$uuid@$add:$_pm_p?sni=$sni&insecure=$jhins&allowInsecure=$jhins#${sxname}anytls-$_pm_i-$hostname"
echo "$_pm_link" >> "$HOME/agsbx/jhsub.txt"; echo "$_pm_link"; echo
done
sbanpt_more() {
for _pm_i in $(_pm_idx_list "anytls-sb" "$HOME/agsbx/sb.json"); do
_pm_p=$(cat "$HOME/agsbx/port_an$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
cat <<EOF
{
"type": "anytls",
"tag": "${sxname}anytls-$_pm_i-$hostname",
"server": "$add",
"server_port": $_pm_p,
"password": "$uuid",
"idle_session_check_interval": "30s",
"idle_session_timeout": "30s",
"min_idle_session": 5,
"tls": {
"enabled": true,
"insecure": $sb_insecure$sb_pin_field,
"server_name": "$sni"
}
},
EOF
done
}
sbanpt_more_1() {
for _pm_i in $(_pm_idx_list "anytls-sb" "$HOME/agsbx/sb.json"); do echo "\"${sxname}anytls-$_pm_i-$hostname\","; done
}
clanpt_more() {
for _pm_i in $(_pm_idx_list "anytls-sb" "$HOME/agsbx/sb.json"); do
_pm_p=$(cat "$HOME/agsbx/port_an$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
cat <<EOF
- name: ${sxname}anytls-$_pm_i-$hostname
type: anytls
server: $add
port: $_pm_p
password: "$uuid"
client-fingerprint: chrome
udp: true
idle-session-check-interval: 30
idle-session-timeout: 30
sni: $sni
skip-cert-verify: $cl_skip
$cl_pin_line
EOF
done
}
clanpt_more_1() {
for _pm_i in $(_pm_idx_list "anytls-sb" "$HOME/agsbx/sb.json"); do echo "- ${sxname}anytls-$_pm_i-$hostname"; done
}
# arpt
for _pm_i in $(_pm_idx_list "anyreality-sb" "$HOME/agsbx/sb.json"); do
_pm_p=$(cat "$HOME/agsbx/port_ar$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
echo "💣节点信息如下："
_pm_link="anytls://$uuid@$reality_addr:$_pm_p?security=reality&sni=$ym_vl_re&fp=chrome&pbk=$public_key_s&sid=$short_id_s&type=tcp&headerType=none#${sxname}any-reality-$_pm_i-$hostname"
echo "$_pm_link" >> "$HOME/agsbx/jhsub.txt"; echo "$_pm_link"; echo
done
sbarpt_more() {
for _pm_i in $(_pm_idx_list "anyreality-sb" "$HOME/agsbx/sb.json"); do
_pm_p=$(cat "$HOME/agsbx/port_ar$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
cat <<EOF
{
"type": "anytls",
"tag": "${sxname}any-reality-$_pm_i-$hostname",
"server": "$reality_addr",
"server_port": $_pm_p,
"password": "$uuid",
"tls": {
"enabled": true,
"server_name": "$ym_vl_re",
"reality": {
"enabled": true,
"handshake": {
"server": "$ym_vl_re",
"server_port": 443
},
"private_key": "$private_key_s",
"short_id": ["$short_id_s"]
}
}
},
EOF
done
}
sbarpt_more_1() {
for _pm_i in $(_pm_idx_list "anyreality-sb" "$HOME/agsbx/sb.json"); do echo "\"${sxname}any-reality-$_pm_i-$hostname\","; done
}
# hypt (xr or sb, same display template; single-port variant, no port hopping)
_pm_hy_idx() {
{ grep -o '"tag": "hy2-sb-[0-9][0-9]*"' "$HOME/agsbx/sb.json" 2>/dev/null; grep -o '"tag": "hy2-xr-[0-9][0-9]*"' "$HOME/agsbx/xr.json" 2>/dev/null;} | sed -E 's/.*-([0-9]+)"/\1/' | sort -nu
}
for _pm_i in $(_pm_hy_idx); do
_pm_p=$(cat "$HOME/agsbx/port_hy2$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
if [ "$pin_on" = "1" ]; then _pm_hyps="&pinSHA256=$pin_sha"; else _pm_hyps=""; fi
echo "💣节点信息如下："
_pm_link="hysteria2://$uuid@$add:$_pm_p?security=tls&alpn=h3&insecure=0&allowInsecure=0$_pm_hyps&sni=$sni#${sxname}hy2-$_pm_i-$hostname"
echo "$_pm_link" >> "$HOME/agsbx/jhsub.txt"; echo "$_pm_link"; echo
done
sbhypt_more() {
for _pm_i in $(_pm_hy_idx); do
_pm_p=$(cat "$HOME/agsbx/port_hy2$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
cat <<EOF
{
"type": "hysteria2",
"tag": "${sxname}hy2-$_pm_i-$hostname",
"server": "$add",
"server_port": $_pm_p,
"password": "$uuid",
"tls": {
"enabled": true,
"server_name": "$sni",
"insecure": $sb_insecure$sb_pin_field,
"alpn": [
"h3"
]
}
},
EOF
done
}
sbhypt_more_1() {
for _pm_i in $(_pm_hy_idx); do echo "\"${sxname}hy2-$_pm_i-$hostname\","; done
}
clhypt_more() {
for _pm_i in $(_pm_hy_idx); do
_pm_p=$(cat "$HOME/agsbx/port_hy2$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
cat <<EOF
- name: ${sxname}hysteria2-$_pm_i-$hostname
type: hysteria2
server: $add
port: $_pm_p
password: "$uuid"
alpn:
- h3
sni: $sni
skip-cert-verify: $cl_skip
$cl_pin_line
fast-open: true
EOF
done
}
clhypt_more_1() {
for _pm_i in $(_pm_hy_idx); do echo "- ${sxname}hysteria2-$_pm_i-$hostname"; done
}
# vmpt
_pm_vm_idx() {
{ grep -o '"tag": "vmess-sb-[0-9][0-9]*"' "$HOME/agsbx/sb.json" 2>/dev/null; grep -o '"tag": "vmess-xr-[0-9][0-9]*"' "$HOME/agsbx/xr.json" 2>/dev/null;} | sed -E 's/.*-([0-9]+)"/\1/' | sort -nu
}
for _pm_i in $(_pm_vm_idx); do
_pm_p=$(cat "$HOME/agsbx/port_vm_ws$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
echo "💣节点信息如下："
_pm_link="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vm-ws-$_pm_i-$hostname\", \"add\": \"$domain_addr\", \"port\": \"$_pm_p\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"www.bing.com\", \"path\": \"/$uuid-vm\", \"tls\": \"\"}" | base64 -w0)"
echo "$_pm_link" >> "$HOME/agsbx/jhsub.txt"; echo "$_pm_link"; echo
done
sbvmpt_more() {
for _pm_i in $(_pm_vm_idx); do
_pm_p=$(cat "$HOME/agsbx/port_vm_ws$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
cat <<EOF
{
"server": "$domain_addr",
"server_port": $_pm_p,
"tag": "${sxname}vmess-$_pm_i-$hostname",
"tls": {
"enabled": false,
"server_name": "www.bing.com",
"insecure": false,
"utls": {
"enabled": true,
"fingerprint": "chrome"
}
},
"transport": {
"headers": {
"Host": [
"www.bing.com"
]
},
"path": "$uuid-vm",
"type": "ws"
},
"type": "vmess",
"security": "auto",
"uuid": "$uuid"
},
EOF
done
}
sbvmpt_more_1() {
for _pm_i in $(_pm_vm_idx); do echo "\"${sxname}vmess-$_pm_i-$hostname\","; done
}
clvmpt_more() {
for _pm_i in $(_pm_vm_idx); do
_pm_p=$(cat "$HOME/agsbx/port_vm_ws$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
cat <<EOF
- name: ${sxname}vmess-ws-$_pm_i-$hostname
type: vmess
server: $domain_addr
port: $_pm_p
uuid: $uuid
alterId: 0
cipher: auto
udp: true
tls: false
network: ws
servername: www.bing.com
ws-opts:
path: "$uuid-vm"
headers:
Host: www.bing.com
EOF
done
}
clvmpt_more_1() {
for _pm_i in $(_pm_vm_idx); do echo "- ${sxname}vmess-ws-$_pm_i-$hostname"; done
}
# vmtls
_pm_vmtls_idx() {
{ grep -o '"tag": "vmess-tls-sb-[0-9][0-9]*"' "$HOME/agsbx/sb.json" 2>/dev/null; grep -o '"tag": "vmess-tls-xr-[0-9][0-9]*"' "$HOME/agsbx/xr.json" 2>/dev/null;} | sed -E 's/.*-([0-9]+)"/\1/' | sort -nu
}
for _pm_i in $(_pm_vmtls_idx); do
_pm_p=$(cat "$HOME/agsbx/port_vm_tls$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
if [ "$pin_on" = "1" ]; then _pm_hpkp=", \"hpkp\": \"$pin_sha\""; else _pm_hpkp=""; fi
echo "💣节点信息如下："
_pm_link="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vm-ws-tls-$_pm_i-$hostname\", \"add\": \"$add\", \"port\": \"$_pm_p\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$sni\", \"path\": \"/$uuid-vmtls\", \"tls\": \"tls\", \"sni\": \"$sni\", \"alpn\": \"\", \"fp\": \"chrome\"$_pm_hpkp}" | base64 -w0)"
echo "$_pm_link" >> "$HOME/agsbx/jhsub.txt"; echo "$_pm_link"; echo
done
sbvmtlspt_more() {
for _pm_i in $(_pm_vmtls_idx); do
_pm_p=$(cat "$HOME/agsbx/port_vm_tls$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
cat <<EOF
{
"server": "$add",
"server_port": $_pm_p,
"tag": "${sxname}vmess-ws-tls-$_pm_i-$hostname",
"tls": {
"enabled": true,
"server_name": "$sni",
"insecure": $sb_insecure$sb_pin_field,
"utls": {
"enabled": true,
"fingerprint": "chrome"
}
},
"transport": {
"headers": {
"Host": [
"$sni"
]
},
"path": "$uuid-vmtls",
"type": "ws"
},
"type": "vmess",
"security": "auto",
"uuid": "$uuid"
},
EOF
done
}
sbvmtlspt_more_1() {
for _pm_i in $(_pm_vmtls_idx); do echo "\"${sxname}vmess-ws-tls-$_pm_i-$hostname\","; done
}
clvmtlspt_more() {
for _pm_i in $(_pm_vmtls_idx); do
_pm_p=$(cat "$HOME/agsbx/port_vm_tls$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
cat <<EOF
- name: ${sxname}vmess-ws-tls-$_pm_i-$hostname
type: vmess
server: $add
port: $_pm_p
uuid: $uuid
alterId: 0
cipher: auto
udp: true
tls: true
network: ws
servername: $sni
client-fingerprint: chrome
skip-cert-verify: $cl_skip
$cl_pin_line
ws-opts:
path: "$uuid-vmtls"
headers:
Host: $sni
EOF
done
}
clvmtlspt_more_1() {
for _pm_i in $(_pm_vmtls_idx); do echo "- ${sxname}vmess-ws-tls-$_pm_i-$hostname"; done
}
# sopt: no subscription node in the first instance, only client info
_pm_so_idx() {
{ grep -o '"tag": "socks5-sb-[0-9][0-9]*"' "$HOME/agsbx/sb.json" 2>/dev/null; grep -o '"tag": "socks5-xr-[0-9][0-9]*"' "$HOME/agsbx/xr.json" 2>/dev/null;} | sed -E 's/.*-([0-9]+)"/\1/' | sort -nu
}
for _pm_i in $(_pm_so_idx); do
_pm_p=$(cat "$HOME/agsbx/port_so$_pm_i" 2>/dev/null); [ -n "$_pm_p" ] || continue
echo "💣客户端信息如下："
echo "请配合其他应用内置代理使用，勿做节点直接使用"
echo "客户端地址：$server_ip"
echo "客户端端口：$_pm_p"
echo "客户端用户名：$uuid"
echo "客户端密码：$uuid"
echo
done
