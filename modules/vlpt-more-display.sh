# vlpt more instances display (private module, loop).
# Instance numbers come from the inbound tags actually present in
# xr.json / sb.json (reality-vision-N, vl-reality-sb-N, N >= 3), never
# from port files alone, so a stale port file from a removed instance
# cannot resurrect a link. Instance 2 is always displayed by the
# vlpt2 block (even when it came from vlpt_more), so this loop only
# handles N >= 3 and never duplicates it. Native links are printed
# here; subscription nodes are produced by sbvlpt_more / clvlpt_more
# below, which loop over the same tag list at subscription-build time.
vlpt_more_idx_list(){
{ grep -o '"tag":"reality-vision-[0-9][0-9]*"' "$HOME/agsbx/xr.json" 2>/dev/null; grep -o '"tag": "vl-reality-sb-[0-9][0-9]*"' "$HOME/agsbx/sb.json" 2>/dev/null;} | sed -E 's/.*-([0-9]+)".*/\1/' | sort -nu | while read -r _n; do case "$_n" in ''|1|2);; *) echo "$_n";; esac; done
}
for _vlpt_more_i in $(vlpt_more_idx_list); do
if grep -q "\"tag\": \"vl-reality-sb-$_vlpt_more_i\"" "$HOME/agsbx/sb.json" 2>/dev/null; then _vlpt_more_pbk="$public_key_s"; _vlpt_more_sid="$short_id_s"; else _vlpt_more_pbk="$public_key_x"; _vlpt_more_sid="$short_id_x"; fi
_vlpt_more_port=$(cat "$HOME/agsbx/port_vl_re$_vlpt_more_i" 2>/dev/null)
[ -n "$_vlpt_more_port" ] || continue
echo "💣节点信息如下："
_vlpt_more_link="vless://$uuid@$reality_addr:$_vlpt_more_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$ym_vl_re&fp=chrome&pbk=$_vlpt_more_pbk&sid=$_vlpt_more_sid&type=tcp&headerType=none#${sxname}vl-reality-vision-$_vlpt_more_i-$hostname"
echo "$_vlpt_more_link" >> "$HOME/agsbx/jhsub.txt"
echo "$_vlpt_more_link"
echo
done
sbvlpt_more(){
for _vlpt_more_i in $(vlpt_more_idx_list); do
if grep -q "\"tag\": \"vl-reality-sb-$_vlpt_more_i\"" "$HOME/agsbx/sb.json" 2>/dev/null; then _vlpt_more_pbk="$public_key_s"; _vlpt_more_sid="$short_id_s"; else _vlpt_more_pbk="$public_key_x"; _vlpt_more_sid="$short_id_x"; fi
_vlpt_more_port=$(cat "$HOME/agsbx/port_vl_re$_vlpt_more_i" 2>/dev/null)
[ -n "$_vlpt_more_port" ] || continue
cat <<EOF
{
"type": "vless",
"tag": "${sxname}vless-$_vlpt_more_i-$hostname",
"server": "$reality_addr",
"server_port": $_vlpt_more_port,
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
"public_key": "$_vlpt_more_pbk",
"short_id": "$_vlpt_more_sid"
}
}
},
EOF
done
}
sbvlpt_more_1(){
for _vlpt_more_i in $(vlpt_more_idx_list); do
echo "\"${sxname}vless-$_vlpt_more_i-$hostname\","
done
}
clvlpt_more(){
for _vlpt_more_i in $(vlpt_more_idx_list); do
if grep -q "\"tag\": \"vl-reality-sb-$_vlpt_more_i\"" "$HOME/agsbx/sb.json" 2>/dev/null; then _vlpt_more_pbk="$public_key_s"; _vlpt_more_sid="$short_id_s"; else _vlpt_more_pbk="$public_key_x"; _vlpt_more_sid="$short_id_x"; fi
_vlpt_more_port=$(cat "$HOME/agsbx/port_vl_re$_vlpt_more_i" 2>/dev/null)
[ -n "$_vlpt_more_port" ] || continue
cat <<EOF
- name: ${sxname}vless-reality-vision-$_vlpt_more_i-$hostname
type: vless
server: $reality_addr
port: $_vlpt_more_port
uuid: $uuid
network: tcp
udp: true
tls: true
flow: xtls-rprx-vision
servername: $ym_vl_re
reality-opts:
public-key: $_vlpt_more_pbk
short-id: $_vlpt_more_sid
client-fingerprint: chrome
EOF
done
}
clvlpt_more_1(){
for _vlpt_more_i in $(vlpt_more_idx_list); do
echo "- ${sxname}vless-reality-vision-$_vlpt_more_i-$hostname"
done
}
