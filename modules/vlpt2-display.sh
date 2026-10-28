if grep -q '"tag":"reality-vision-2"' "$HOME/agsbx/xr.json" 2>/dev/null || grep -q '"tag": "vl-reality-sb-2"' "$HOME/agsbx/sb.json" 2>/dev/null; then
if grep -q '"tag": "vl-reality-sb-2"' "$HOME/agsbx/sb.json" 2>/dev/null; then vlpt2_pbk="$public_key_s"; vlpt2_sid="$short_id_s"; else vlpt2_pbk="$public_key_x"; vlpt2_sid="$short_id_x"; fi
echo "💣节点信息如下："
port_vl_re2=$(cat "$HOME/agsbx/port_vl_re2")
vl_link2="vless://$uuid@$reality_addr:$port_vl_re2?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$ym_vl_re&fp=chrome&pbk=$vlpt2_pbk&sid=$vlpt2_sid&type=tcp&headerType=none#${sxname}vl-reality-vision-2-$hostname"
echo "$vl_link2" >> "$HOME/agsbx/jhsub.txt"
echo "$vl_link2"
echo
sbvlpt2(){
cat <<EOF
{
"type": "vless",
"tag": "${sxname}vless-2-$hostname",
"server": "$reality_addr",
"server_port": $port_vl_re2,
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
"public_key": "$vlpt2_pbk",
"short_id": "$vlpt2_sid"
}
}
},
EOF
}
sbvlpt2_1(){
echo "\"${sxname}vless-2-$hostname\","
}
clvlpt2(){
cat <<EOF
- name: ${sxname}vless-reality-vision-2-$hostname
type: vless
server: $reality_addr
port: $port_vl_re2
uuid: $uuid
network: tcp
udp: true
tls: true
flow: xtls-rprx-vision
servername: $ym_vl_re
reality-opts:
public-key: $vlpt2_pbk
short-id: $vlpt2_sid
client-fingerprint: chrome
EOF
}
clvlpt2_1(){
echo "- ${sxname}vless-reality-vision-2-$hostname"
}
fi
