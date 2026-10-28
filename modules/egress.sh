# ===== EGRESS MODULE BEGIN (private, modular) =====
# Dynamic egress: external proxy nodes (unlimited), local multi-IP bind
# outbounds, and per-domain/IP/source/inbound/geoip/geosite/port/protocol
# routing rules. Design for upstream alignment: all egress code lives in
# this one block. Upstream argosbx.sh only gets 4 hook insertions (see
# xrsbout) + 3 exported variables + egress_init call at the start of
# xrsbout. When egress_nodes, egress_bind and egress_rules are all empty,
# every generated variable is empty, so the generated sb.json/xr.json are
# byte-identical to before.
# Extensibility: to add a protocol, add one case in egress_parse_link
# (parser) + one sing-box fragment + one xray fragment; to add a rule
# type, add one case in egress_parse_rules. Routing/outbound generation
# never needs to change for a new protocol/rule type.
# Variables (env, set by the generator page, ';' separated, no cap):
#   egress_nodes: socks5://user:pass@host:port#tag
#     vless://uuid@host:port?security=reality|tls|none&pbk=..&sid=..&sni=..&fp=..&flow=..&type=tcp|ws|grpc|xhttp&path=..&host=..&serviceName=..&mode=auto#tag
#     trojan://password@host:port?security=tls|none&sni=..&type=tcp|ws|grpc|xhttp&path=..&host=..&serviceName=..&mode=auto#tag
#     vmess://uuid@host:port?security=tls|none&sni=..&type=ws|tcp|grpc|xhttp&path=..&host=..&serviceName=..&mode=auto&alterId=0&scy=auto#tag
#       (URL form only; the standard vmess base64-JSON link form is NOT
#       supported here, it is skipped with a warning)
#     ss://method:password@host:port#tag  (also ss://base64(method:password)@host:port
#       and ss://base64(method:password@host:port)#tag ; 2022-* methods get uot/udp_over_tcp)
#   egress_bind:  1.2.3.4,2001:db8::2   (each becomes bind1, bind2, ...)
#   egress_rules: domain:example.com=>tag ; ip:1.2.3.0/24=>tag ; source:10.0.0.0/8=>tag ; inbound:vlpt=>tag
#     geoip:CN,US=>tag ; geosite:google,youtube=>tag ; port:80,443=>tag ; port:1000-2000=>tag ; protocol:http,tls=>tag
#   Rule targets (right of =>): an egress_nodes #tag, a bind tag
#   (bind1, bind2, ...), or a built-in (direct, warp-out, x-warp-out).
#   Never an IP literal: =>1.2.3.4 is not a tag and the rule is skipped.
#   AND rules: join conditions with '&' in one rule, e.g.
#   inbound:vlpt&domain:google.com=>tag (vlpt AND google.com, one
#   routing object, both kernels treat multiple fields in one rule as
#   AND). Comma lists inside one condition are OR, rules in order are
#   first-match-wins. A rule with an unknown condition or no valid
#   port is skipped whole, never weakened to a partial AND.
#   inbound: values may be a protocol variable name (vlpt, xhpt, hypt,
#   ...) instead of the server inbound tag: egress_inbound_tags expands
#   it to the real tag(s) for that protocol, so users do not have to
#   remember that vlpt is reality-vision on Xray but vl-reality-sb on
#   Sing-box, or that hypt is hy2-xr on Xray but hy2-sb on Sing-box.
#   Protocols served by either kernel expand to both tags, so the rule
#   matches whichever kernel actually installed that protocol. Old
#   rules that already use a real tag pass through unchanged.
#   Limits to know: geoip/geosite rules need the kernel's geoip/geosite
#   database files, otherwise they may not match; protocol rules need
#   sniffing enabled on the inbound, otherwise they may not match.
#   Geo databases (egress_geo_setup, called from xrsbout after egress_init):
#   only when egress_rules contains a geoip:/geosite: rule, and only for
#   files that do not already exist, split by kernel: sing-box geoip.db
#   (SagerNet sing-geoip) + geosite.db (SagerNet sing-geosite) in
#   $HOME/agsbx/geo/sing-box/, xray geoip.dat + geosite.dat
#   (Loyalsoldier v2ray-rules-dat) in $HOME/agsbx/geo/xray/; sing-box
#   route gets geoip/geosite path blocks via egress_sb_geo_cfg, xray
#   gets XRAY_LOCATION_ASSET=$HOME/agsbx/geo/xray. A download failure
#   only warns and keeps the rules (never silently drops a rule).
#   Filling geo rules: geoip codes are lowercase country codes as in
#   the database (cn, us, jp, ...; private = private/LAN IPs), geosite
#   codes are category names as in the database (google, youtube,
#   netflix, cn, ...); if a code is not in the database it simply
#   never matches, so check the database's code list first.
egress_json_escape(){ printf '%s' "$1" | tr -d '\n\r' | sed 's/\\/\\\\/g; s/"/\\"/g'; }
# Protocol variable -> server inbound tag(s), comma-separated.
# Unknown values pass through unchanged, so a real tag (reality-vision,
# vm-ws, ...) and a future protocol name are never broken by this map.
egress_inbound_tags(){
  local item="$1" low=""
  low=$(printf '%s' "$item" | tr 'A-Z' 'a-z')
  case "$low" in
    vlpt) echo "reality-vision,vl-reality-sb";;
    xhpt) echo "xhttp-reality";;
    vxpt) echo "vless-xhttp";;
    vwpt) echo "vless-ws";;
    xupt) echo "xhttp-h3";;
    xcpt) echo "xhttp-h23";;
    nvpt) echo "naive-sb";;
    tupt) echo "tuic5-sb";;
    anpt) echo "anytls-sb";;
    arpt) echo "anyreality-sb";;
    sspt) echo "ss-2022";;
    hypt) echo "hy2-xr,hy2-sb";;
    vmpt) echo "vmess-xr,vmess-sb";;
    vmtls) echo "vmess-tls-xr,vmess-tls-sb";;
    sopt) echo "socks5-xr,socks5-sb";;
    *) echo "$item";;
  esac
}
egress_url_decode(){ local s="$1"; s=$(printf '%s' "$s" | sed 's/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g'); printf '%b' "$s"; }
egress_query_param(){ local q="&$1&" k="$2" v=""; case "$q" in *"&${k}="*) v="${q#*&${k}=}"; v="${v%%&*}"; egress_url_decode "$v";; *) printf '';; esac; }
egress_json_array(){ local list="$1" out="" item="" oldifs="$IFS"; IFS=','; for item in $list; do item=$(printf '%s' "$item" | xargs 2>/dev/null || printf '%s' "$item"); [ -n "$item" ] || continue; [ -n "$out" ] && out="${out}, "; out="${out}\"$(egress_json_escape "$item")\""; done; IFS="$oldifs"; printf '%s' "$out"; }
egress_b64_decode(){ local s="$1"; s=$(printf '%s' "$s" | tr '_-' '+/'); local pad=$(( (4 - ${#s} % 4) % 4 )) i=0; while [ $i -lt $pad ]; do s="${s}="; i=$((i + 1)); done; printf '%s' "$s" | base64 -d 2>/dev/null; }
egress_add_tag(){ case " $egress_tags " in *" $1 "*) ;; *) egress_tags="${egress_tags:+$egress_tags }$1";; esac; }
egress_parse_link(){
  local link="$1" scheme="" rest="" frag="" tag="" query="" userinfo="" hostport="" host="" port="" user="" pass="" uuid=""
  scheme="${link%%://*}"; rest="${link#*://}"
  case "$rest" in *'#'*) frag="${rest##*#}"; rest="${rest%%#*}";; esac
  case "$rest" in *'?'*) query="${rest#*\?}"; rest="${rest%%\?*}";; esac
  case "$rest" in *'@'*) userinfo="${rest%%@*}"; hostport="${rest#*@}";; *) hostport="$rest";; esac
  case "$hostport" in '['*) host="${hostport%%\]*}"; host="${host#[}"; port="${hostport##*:}";; *':'*) host="${hostport%:*}"; port="${hostport##*:}";; *) host="$hostport"; port="";; esac
  tag=$(egress_url_decode "$frag" | tr -d '"\\' | sed 's/ /-/g')
  case "$scheme" in
    socks5)
      egress_socks_count=$((egress_socks_count + 1)); [ -n "$tag" ] || tag="socks${egress_socks_count}"; [ -z "$port" ] && port=1080
      case "$userinfo" in *':'*) user="${userinfo%%:*}"; pass="${userinfo#*:}";; *) user="$userinfo"; pass="";; esac
      user=$(egress_url_decode "$user"); pass=$(egress_url_decode "$pass")
      local sb_auth="" xr_users=""
      [ -n "$user" ] && sb_auth=", \"username\": \"$(egress_json_escape "$user")\", \"password\": \"$(egress_json_escape "$pass")\""
      [ -n "$user" ] && xr_users=", \"users\": [{\"user\": \"$(egress_json_escape "$user")\", \"pass\": \"$(egress_json_escape "$pass")\"}]"
      egress_sb_outbounds="${egress_sb_outbounds}    {\"type\": \"socks\", \"tag\": \"$(egress_json_escape "$tag")\", \"server\": \"$(egress_json_escape "$host")\", \"server_port\": $port$sb_auth},
"
      egress_xr_outbounds="${egress_xr_outbounds}    {\"protocol\": \"socks\", \"tag\": \"$(egress_json_escape "$tag")\", \"settings\": {\"servers\": [{\"address\": \"$(egress_json_escape "$host")\", \"port\": $port$xr_users}]}},
"
      egress_add_tag "$tag";;
    vless)
      egress_vless_count=$((egress_vless_count + 1)); [ -n "$tag" ] || tag="vless${egress_vless_count}"; [ -z "$port" ] && port=443
      uuid="$userinfo"
      local sec="" typ="" sni="" pth="" hdr="" pbk="" sid="" fp="" flow="" svc="" mode=""
      sec=$(egress_query_param "$query" security); typ=$(egress_query_param "$query" type); sni=$(egress_query_param "$query" sni); pth=$(egress_query_param "$query" path); hdr=$(egress_query_param "$query" host); pbk=$(egress_query_param "$query" pbk); sid=$(egress_query_param "$query" sid); fp=$(egress_query_param "$query" fp); flow=$(egress_query_param "$query" flow); svc=$(egress_query_param "$query" serviceName); mode=$(egress_query_param "$query" mode)
      [ -n "$sni" ] || sni="$host"; [ -n "$typ" ] || typ="tcp"; [ -n "$pth" ] || pth="/"; [ -n "$hdr" ] || hdr="$sni"; [ -n "$fp" ] || fp="chrome"; [ -n "$mode" ] || mode="auto"
      local sb_tls="" sb_tr="" xr_sec="none" xr_tls="" xr_tr=""
      case "$sec" in
        tls) sb_tls=", \"tls\": {\"enabled\": true, \"server_name\": \"$(egress_json_escape "$sni")\", \"insecure\": false}"; xr_sec="tls"; xr_tls=", \"tlsSettings\": {\"serverName\": \"$(egress_json_escape "$sni")\", \"fingerprint\": \"$(egress_json_escape "$fp")\"}";;
        reality)
          [ -n "$pbk" ] || { echo "vless reality 节点 $tag 缺少 pbk，已跳过"; return 0; }
          sb_tls=", \"tls\": {\"enabled\": true, \"server_name\": \"$(egress_json_escape "$sni")\", \"utls\": {\"enabled\": true, \"fingerprint\": \"$(egress_json_escape "$fp")\"}, \"reality\": {\"enabled\": true, \"public_key\": \"$(egress_json_escape "$pbk")\", \"short_id\": \"$(egress_json_escape "$sid")\"}}"
          xr_sec="reality"; xr_tls=", \"realitySettings\": {\"publicKey\": \"$(egress_json_escape "$pbk")\", \"shortId\": \"$(egress_json_escape "$sid")\", \"fingerprint\": \"$(egress_json_escape "$fp")\", \"serverName\": \"$(egress_json_escape "$sni")\"}";;
        *) sb_tls=""; xr_sec="none"; xr_tls="";;
      esac
      local sb_flow=""; [ -n "$flow" ] && sb_flow=", \"flow\": \"$(egress_json_escape "$flow")\""
      case "$typ" in
        tcp) sb_tr=""; xr_tr=", \"tcpSettings\": {}";;
        ws) sb_tr=", \"transport\": {\"type\": \"ws\", \"path\": \"$(egress_json_escape "$pth")\", \"headers\": {\"Host\": \"$(egress_json_escape "$hdr")\"}}"; xr_tr=", \"wsSettings\": {\"path\": \"$(egress_json_escape "$pth")\", \"headers\": {\"Host\": \"$(egress_json_escape "$hdr")\"}}";;
        grpc) sb_tr=", \"transport\": {\"type\": \"grpc\", \"service_name\": \"$(egress_json_escape "$svc")\"}"; xr_tr=", \"grpcSettings\": {\"serviceName\": \"$(egress_json_escape "$svc")\"}";;
        xhttp) sb_tr=", \"transport\": {\"type\": \"xhttp\", \"path\": \"$(egress_json_escape "$pth")\", \"headers\": {\"Host\": \"$(egress_json_escape "$hdr")\"}, \"mode\": \"$(egress_json_escape "$mode")\"}"; xr_tr=", \"xhttpSettings\": {\"path\": \"$(egress_json_escape "$pth")\", \"host\": \"$(egress_json_escape "$hdr")\", \"mode\": \"$(egress_json_escape "$mode")\"}";;
        *) echo "vless 节点 $tag 的传输方式 $typ 暂不支持，已跳过"; return 0;;
      esac
      local xr_flow=""; [ -n "$flow" ] && xr_flow=", \"flow\": \"$(egress_json_escape "$flow")\""
      egress_sb_outbounds="${egress_sb_outbounds}    {\"type\": \"vless\", \"tag\": \"$(egress_json_escape "$tag")\", \"server\": \"$(egress_json_escape "$host")\", \"server_port\": $port, \"uuid\": \"$(egress_json_escape "$uuid")\"$sb_flow$sb_tls$sb_tr},
"
      egress_xr_outbounds="${egress_xr_outbounds}    {\"protocol\": \"vless\", \"tag\": \"$(egress_json_escape "$tag")\", \"settings\": {\"vnext\": [{\"address\": \"$(egress_json_escape "$host")\", \"port\": $port, \"users\": [{\"id\": \"$(egress_json_escape "$uuid")\"$xr_flow}]}]}, \"streamSettings\": {\"network\": \"$typ\", \"security\": \"$xr_sec\"$xr_tls$xr_tr}},
"
      egress_add_tag "$tag";;
    trojan)
      egress_trojan_count=$((egress_trojan_count + 1)); [ -n "$tag" ] || tag="trojan${egress_trojan_count}"; [ -z "$port" ] && port=443
      local pass="" sec="" typ="" sni="" pth="" hdr="" fp="" svc="" mode="" sb_tls="" sb_tr="" xr_sec="none" xr_tls="" xr_tr=""
      pass=$(egress_url_decode "$userinfo")
      sec=$(egress_query_param "$query" security); typ=$(egress_query_param "$query" type); sni=$(egress_query_param "$query" sni); pth=$(egress_query_param "$query" path); hdr=$(egress_query_param "$query" host); fp=$(egress_query_param "$query" fp); svc=$(egress_query_param "$query" serviceName); mode=$(egress_query_param "$query" mode)
      [ -n "$sni" ] || sni="$host"; [ -n "$typ" ] || typ="tcp"; [ -n "$pth" ] || pth="/"; [ -n "$hdr" ] || hdr="$sni"; [ -n "$fp" ] || fp="chrome"; [ -n "$mode" ] || mode="auto"
      case "$sec" in
        none) sb_tls=""; xr_sec="none";;
        *) sb_tls=", \"tls\": {\"enabled\": true, \"server_name\": \"$(egress_json_escape "$sni")\", \"insecure\": false}"; xr_sec="tls"; xr_tls=", \"tlsSettings\": {\"serverName\": \"$(egress_json_escape "$sni")\", \"fingerprint\": \"$(egress_json_escape "$fp")\"}";;
      esac
      case "$typ" in
        tcp) sb_tr=""; xr_tr=", \"tcpSettings\": {}";;
        ws) sb_tr=", \"transport\": {\"type\": \"ws\", \"path\": \"$(egress_json_escape "$pth")\", \"headers\": {\"Host\": \"$(egress_json_escape "$hdr")\"}}"; xr_tr=", \"wsSettings\": {\"path\": \"$(egress_json_escape "$pth")\", \"headers\": {\"Host\": \"$(egress_json_escape "$hdr")\"}}";;
        grpc) sb_tr=", \"transport\": {\"type\": \"grpc\", \"service_name\": \"$(egress_json_escape "$svc")\"}"; xr_tr=", \"grpcSettings\": {\"serviceName\": \"$(egress_json_escape "$svc")\"}";;
        xhttp) sb_tr=", \"transport\": {\"type\": \"xhttp\", \"path\": \"$(egress_json_escape "$pth")\", \"headers\": {\"Host\": \"$(egress_json_escape "$hdr")\"}, \"mode\": \"$(egress_json_escape "$mode")\"}"; xr_tr=", \"xhttpSettings\": {\"path\": \"$(egress_json_escape "$pth")\", \"host\": \"$(egress_json_escape "$hdr")\", \"mode\": \"$(egress_json_escape "$mode")\"}";;
        *) echo "trojan 节点 $tag 的传输方式 $typ 暂不支持，已跳过"; return 0;;
      esac
      egress_sb_outbounds="${egress_sb_outbounds}    {\"type\": \"trojan\", \"tag\": \"$(egress_json_escape "$tag")\", \"server\": \"$(egress_json_escape "$host")\", \"server_port\": $port, \"password\": \"$(egress_json_escape "$pass")\"$sb_tls$sb_tr},
"
      egress_xr_outbounds="${egress_xr_outbounds}    {\"protocol\": \"trojan\", \"tag\": \"$(egress_json_escape "$tag")\", \"settings\": {\"servers\": [{\"address\": \"$(egress_json_escape "$host")\", \"port\": $port, \"password\": \"$(egress_json_escape "$pass")\"}]}, \"streamSettings\": {\"network\": \"$typ\", \"security\": \"$xr_sec\"$xr_tls$xr_tr}},
"
      egress_add_tag "$tag";;
    vmess)
      if [ -z "$userinfo" ]; then echo "vmess base64 链接暂不支持，请用 vmess://uuid@host:port?... 形式，已跳过"; return 0; fi
      egress_vmess_count=$((egress_vmess_count + 1)); [ -n "$tag" ] || tag="vmess${egress_vmess_count}"; [ -z "$port" ] && port=443
      uuid="$userinfo"
      local sec="" typ="" sni="" pth="" hdr="" fp="" svc="" mode="" aid="" scy="" sb_tls="" sb_tr="" xr_sec="none" xr_tls="" xr_tr=""
      sec=$(egress_query_param "$query" security); typ=$(egress_query_param "$query" type); sni=$(egress_query_param "$query" sni); pth=$(egress_query_param "$query" path); hdr=$(egress_query_param "$query" host); fp=$(egress_query_param "$query" fp); svc=$(egress_query_param "$query" serviceName); mode=$(egress_query_param "$query" mode); aid=$(egress_query_param "$query" alterId); scy=$(egress_query_param "$query" scy)
      [ -n "$sni" ] || sni="$host"; [ -n "$typ" ] || typ="ws"; [ -n "$pth" ] || pth="/"; [ -n "$hdr" ] || hdr="$sni"; [ -n "$fp" ] || fp="chrome"; [ -n "$mode" ] || mode="auto"; [ -n "$aid" ] || aid=0; [ -n "$scy" ] || scy="auto"
      case "$sec" in
        tls) sb_tls=", \"tls\": {\"enabled\": true, \"server_name\": \"$(egress_json_escape "$sni")\", \"insecure\": false}"; xr_sec="tls"; xr_tls=", \"tlsSettings\": {\"serverName\": \"$(egress_json_escape "$sni")\", \"fingerprint\": \"$(egress_json_escape "$fp")\"}";;
        *) sb_tls=""; xr_sec="none"; xr_tls="";;
      esac
      case "$typ" in
        tcp) sb_tr=""; xr_tr=", \"tcpSettings\": {}";;
        ws) sb_tr=", \"transport\": {\"type\": \"ws\", \"path\": \"$(egress_json_escape "$pth")\", \"headers\": {\"Host\": \"$(egress_json_escape "$hdr")\"}}"; xr_tr=", \"wsSettings\": {\"path\": \"$(egress_json_escape "$pth")\", \"headers\": {\"Host\": \"$(egress_json_escape "$hdr")\"}}";;
        grpc) sb_tr=", \"transport\": {\"type\": \"grpc\", \"service_name\": \"$(egress_json_escape "$svc")\"}"; xr_tr=", \"grpcSettings\": {\"serviceName\": \"$(egress_json_escape "$svc")\"}";;
        xhttp) sb_tr=", \"transport\": {\"type\": \"xhttp\", \"path\": \"$(egress_json_escape "$pth")\", \"headers\": {\"Host\": \"$(egress_json_escape "$hdr")\"}, \"mode\": \"$(egress_json_escape "$mode")\"}"; xr_tr=", \"xhttpSettings\": {\"path\": \"$(egress_json_escape "$pth")\", \"host\": \"$(egress_json_escape "$hdr")\", \"mode\": \"$(egress_json_escape "$mode")\"}";;
        *) echo "vmess 节点 $tag 的传输方式 $typ 暂不支持，已跳过"; return 0;;
      esac
      egress_sb_outbounds="${egress_sb_outbounds}    {\"type\": \"vmess\", \"tag\": \"$(egress_json_escape "$tag")\", \"server\": \"$(egress_json_escape "$host")\", \"server_port\": $port, \"uuid\": \"$(egress_json_escape "$uuid")\", \"alter_id\": $aid, \"security\": \"$(egress_json_escape "$scy")\"$sb_tls$sb_tr},
"
      egress_xr_outbounds="${egress_xr_outbounds}    {\"protocol\": \"vmess\", \"tag\": \"$(egress_json_escape "$tag")\", \"settings\": {\"vnext\": [{\"address\": \"$(egress_json_escape "$host")\", \"port\": $port, \"users\": [{\"id\": \"$(egress_json_escape "$uuid")\", \"alterId\": $aid, \"security\": \"$(egress_json_escape "$scy")\"}]}]}, \"streamSettings\": {\"network\": \"$typ\", \"security\": \"$xr_sec\"$xr_tls$xr_tr}},
"
      egress_add_tag "$tag";;
    ss|shadowsocks)
      egress_ss_count=$((egress_ss_count + 1)); [ -n "$tag" ] || tag="ss${egress_ss_count}"; [ -z "$port" ] && port=8388
      local method="" pass="" decoded=""
      if [ -n "$userinfo" ]; then
        case "$userinfo" in *':'*) method="${userinfo%%:*}"; pass="${userinfo#*:}";; *) decoded=$(egress_b64_decode "$userinfo"); case "$decoded" in *':'*) method="${decoded%%:*}"; pass="${decoded#*:}";; *) method=""; pass="";; esac;; esac
      else
        decoded=$(egress_b64_decode "$hostport")
        case "$decoded" in *'@'*) local up="${decoded%%@*}"; local hp="${decoded#*@}"; method="${up%%:*}"; pass="${up#*:}"; host="${hp%:*}"; port="${hp##*:}";; *) method=""; pass="";; esac
      fi
      if [ -z "$method" ] || [ -z "$pass" ]; then echo "shadowsocks 节点 $tag 格式无法解析，已跳过"; return 0; fi
      method=$(egress_url_decode "$method"); pass=$(egress_url_decode "$pass")
      local sb_uot="" xr_uot=""
      case "$method" in 2022-*) sb_uot=", \"udp_over_tcp\": {\"enabled\": true, \"version\": 2}"; xr_uot=", \"uot\": true";; esac
      egress_sb_outbounds="${egress_sb_outbounds}    {\"type\": \"shadowsocks\", \"tag\": \"$(egress_json_escape "$tag")\", \"server\": \"$(egress_json_escape "$host")\", \"server_port\": $port, \"method\": \"$(egress_json_escape "$method")\", \"password\": \"$(egress_json_escape "$pass")\"$sb_uot},
"
      egress_xr_outbounds="${egress_xr_outbounds}    {\"protocol\": \"shadowsocks\", \"tag\": \"$(egress_json_escape "$tag")\", \"settings\": {\"servers\": [{\"address\": \"$(egress_json_escape "$host")\", \"port\": $port, \"method\": \"$(egress_json_escape "$method")\", \"password\": \"$(egress_json_escape "$pass")\"$xr_uot}]}},
"
      egress_add_tag "$tag";;
    *) echo "出口节点协议 $scheme 暂不支持，已跳过：$tag";;
  esac
}
egress_parse_and_rule(){
  # One combined rule: conditions joined by '&' are AND, comma lists
  # inside one condition are OR, rules in order are first-match-wins.
  # $1 = left side of => (e.g. inbound:vlpt&domain:google.com)
  # $2 = target tag, $3 = full rule text (for warnings only).
  local mp="$1" tag="$2" rule="$3"
  local cond="" ctyp="" cval="" carr="" sb_domain="" sb_ip="" sb_source="" sb_inbound="" sb_geoip="" sb_geosite="" sb_protocol="" sb_p="" sb_r="" xr_p=""
  local xr_domain="" xr_ip="" xr_source="" xr_inbound="" xr_geoip="" xr_protocol=""
  local port_seen=0 sb_obj="" xr_obj="" sep="" oldifs2="$IFS" pitem="" poldifs2="" gitem="" goldifs2=""
  local _exp="" _it="" _tg="" _goldifs2=""
  IFS='&'; for cond in $mp; do
    cond=$(printf '%s' "$cond" | xargs 2>/dev/null || printf '%s' "$cond")
    case "$cond" in *':'*) ctyp="${cond%%:*}"; cval="${cond#*:}";; *) echo "分流规则条件格式错误，已跳过整条：$rule"; IFS="$oldifs2"; return 0;; esac
    ctyp=$(printf '%s' "$ctyp" | xargs 2>/dev/null || printf '%s' "$ctyp"); cval=$(printf '%s' "$cval" | xargs 2>/dev/null || printf '%s' "$cval")
    if [ -z "$cval" ]; then echo "分流规则条件值为空，已跳过整条：$rule"; IFS="$oldifs2"; return 0; fi
    case "$ctyp" in
      domain) carr=$(egress_json_array "$cval"); [ -n "$sb_domain" ] && sb_domain="${sb_domain}, "; sb_domain="${sb_domain}${carr}"; [ -n "$xr_domain" ] && xr_domain="${xr_domain}, "; xr_domain="${xr_domain}${carr}";;
      ip) carr=$(egress_json_array "$cval"); [ -n "$sb_ip" ] && sb_ip="${sb_ip}, "; sb_ip="${sb_ip}${carr}"; [ -n "$xr_ip" ] && xr_ip="${xr_ip}, "; xr_ip="${xr_ip}${carr}";;
      source) carr=$(egress_json_array "$cval"); [ -n "$sb_source" ] && sb_source="${sb_source}, "; sb_source="${sb_source}${carr}"; [ -n "$xr_source" ] && xr_source="${xr_source}, "; xr_source="${xr_source}${carr}";;
      inbound) _exp=""; IFS=','; for _it in $cval; do _it=$(printf '%s' "$_it" | xargs 2>/dev/null || printf '%s' "$_it"); [ -n "$_it" ] || continue; IFS=','; for _tg in $(egress_inbound_tags "$_it"); do _tg=$(printf '%s' "$_tg" | xargs 2>/dev/null || printf '%s' "$_tg"); case ",$_exp," in *",$_tg,"*) ;; *) _exp="${_exp:+$_exp,}$_tg";; esac; done; IFS=','; done; IFS="$oldifs2"
        carr=$(egress_json_array "$_exp"); [ -n "$sb_inbound" ] && sb_inbound="${sb_inbound}, "; sb_inbound="${sb_inbound}${carr}"; [ -n "$xr_inbound" ] && xr_inbound="${xr_inbound}, "; xr_inbound="${xr_inbound}${carr}";;
      geoip) carr=$(egress_json_array "$cval"); [ -n "$sb_geoip" ] && sb_geoip="${sb_geoip}, "; sb_geoip="${sb_geoip}${carr}"; [ -n "$xr_geoip" ] && xr_geoip="${xr_geoip}, "; xr_geoip="${xr_geoip}${carr}";;
      geosite) carr=$(egress_json_array "$cval"); [ -n "$sb_geosite" ] && sb_geosite="${sb_geosite}, "; sb_geosite="${sb_geosite}${carr}"
        goldifs2="$IFS"; IFS=','; for gitem in $cval; do gitem=$(printf '%s' "$gitem" | xargs 2>/dev/null || printf '%s' "$gitem"); [ -n "$gitem" ] || continue; [ -n "$xr_domain" ] && xr_domain="${xr_domain}, "; xr_domain="${xr_domain}\"geosite:$(egress_json_escape "$gitem")\""; done; IFS="$goldifs2";;
      port) port_seen=1; poldifs2="$IFS"; IFS=','; for pitem in $cval; do pitem=$(printf '%s' "$pitem" | xargs 2>/dev/null || printf '%s' "$pitem"); case "$pitem" in *'-'*) case "$pitem" in [0-9]*-[0-9]*) sb_r="${sb_r:+$sb_r, }\"${pitem%-*}:${pitem#*-}\""; xr_p="${xr_p:+$xr_p,}$pitem";; *) echo "分流规则端口范围格式错误，已跳过该项：$pitem";; esac;; [0-9]*) sb_p="${sb_p:+$sb_p, }$pitem"; xr_p="${xr_p:+$xr_p,}$pitem";; *) echo "分流规则端口格式错误，已跳过该项：$pitem";; esac; done; IFS="$poldifs2";;
      protocol) carr=$(egress_json_array "$cval"); [ -n "$sb_protocol" ] && sb_protocol="${sb_protocol}, "; sb_protocol="${sb_protocol}${carr}"; [ -n "$xr_protocol" ] && xr_protocol="${xr_protocol}, "; xr_protocol="${xr_protocol}${carr}";;
      *) echo "分流规则类型 $ctyp 暂不支持，已跳过整条：$rule"; IFS="$oldifs2"; return 0;;
    esac
  done; IFS="$oldifs2"
  if [ "$port_seen" = "1" ] && [ -z "$sb_p" ] && [ -z "$sb_r" ]; then echo "分流规则无有效端口，已跳过整条：$rule"; return 0; fi
  sb_obj="      {"; sep=""
  if [ -n "$sb_domain" ]; then sb_obj="${sb_obj}${sep}\"domain_suffix\": [$sb_domain]"; sep=", "; fi
  if [ -n "$sb_ip" ]; then sb_obj="${sb_obj}${sep}\"ip_cidr\": [$sb_ip]"; sep=", "; fi
  if [ -n "$sb_source" ]; then sb_obj="${sb_obj}${sep}\"source_ip_cidr\": [$sb_source]"; sep=", "; fi
  if [ -n "$sb_inbound" ]; then sb_obj="${sb_obj}${sep}\"inbound\": [$sb_inbound]"; sep=", "; fi
  if [ -n "$sb_geoip" ]; then sb_obj="${sb_obj}${sep}\"geoip\": [$sb_geoip]"; sep=", "; fi
  if [ -n "$sb_geosite" ]; then sb_obj="${sb_obj}${sep}\"geosite\": [$sb_geosite]"; sep=", "; fi
  if [ -n "$sb_p" ]; then sb_obj="${sb_obj}${sep}\"port\": [$sb_p]"; sep=", "; fi
  if [ -n "$sb_r" ]; then sb_obj="${sb_obj}${sep}\"port_range\": [$sb_r]"; sep=", "; fi
  if [ -n "$sb_protocol" ]; then sb_obj="${sb_obj}${sep}\"protocol\": [$sb_protocol]"; sep=", "; fi
  sb_obj="${sb_obj}${sep}\"outbound\": \"$(egress_json_escape "$tag")\"},
"
  xr_obj="      {\"type\": \"field\", "; sep=""
  if [ -n "$xr_domain" ]; then xr_obj="${xr_obj}${sep}\"domain\": [$xr_domain]"; sep=", "; fi
  if [ -n "$xr_ip" ]; then xr_obj="${xr_obj}${sep}\"ip\": [$xr_ip]"; sep=", "; fi
  if [ -n "$xr_source" ]; then xr_obj="${xr_obj}${sep}\"source\": [$xr_source]"; sep=", "; fi
  if [ -n "$xr_inbound" ]; then xr_obj="${xr_obj}${sep}\"inboundTag\": [$xr_inbound]"; sep=", "; fi
  if [ -n "$xr_geoip" ]; then xr_obj="${xr_obj}${sep}\"geoip\": [$xr_geoip]"; sep=", "; fi
  if [ -n "$xr_p" ]; then xr_obj="${xr_obj}${sep}\"port\": \"$(egress_json_escape "$xr_p")\""; sep=", "; fi
  if [ -n "$xr_protocol" ]; then xr_obj="${xr_obj}${sep}\"protocol\": [$xr_protocol]"; sep=", "; fi
  xr_obj="${xr_obj}${sep}\"outboundTag\": \"$(egress_json_escape "$tag")\"},
"
  egress_sb_rules="${egress_sb_rules}${sb_obj}"
  egress_xr_rules="${egress_xr_rules}${xr_obj}"
  return 0
}
egress_parse_rules(){
  local rules="$1" rule="" mp="" tag="" typ="" val="" arr="" oldifs="$IFS"
  IFS=';'; for rule in $rules; do
    [ -n "$rule" ] || continue
    case "$rule" in *'=>'*) mp="${rule%%=>*}"; tag="${rule##*=>}";; *) echo "分流规则格式错误，已跳过：$rule"; continue;; esac
    case " $egress_tags direct warp-out x-warp-out " in *" $tag "*) ;; *) echo "分流规则目标出口不存在，已跳过：$rule"; continue;; esac
    case "$mp" in *'&'*) egress_parse_and_rule "$mp" "$tag" "$rule"; continue;; esac
    typ="${mp%%:*}"; val="${mp#*:}"
    if [ "$typ" = "inbound" ]; then
      # Expand protocol aliases to real inbound tags, deduping in order.
      # e.g. inbound:vlpt,hypt => reality-vision,vl-reality-sb,hy2-xr,hy2-sb
      local _exp="" _it="" _tg="" _goldifs="$IFS"
      IFS=','; for _it in $val; do _it=$(printf '%s' "$_it" | xargs 2>/dev/null || printf '%s' "$_it"); [ -n "$_it" ] || continue; IFS=','; for _tg in $(egress_inbound_tags "$_it"); do _tg=$(printf '%s' "$_tg" | xargs 2>/dev/null || printf '%s' "$_tg"); case ",$_exp," in *",$_tg,"*) ;; *) _exp="${_exp:+$_exp,}$_tg";; esac; done; IFS=','; done; IFS="$_goldifs"
      val="$_exp"
    fi
    arr=$(egress_json_array "$val")
    case "$typ" in
      domain) egress_sb_rules="${egress_sb_rules}      {\"domain_suffix\": [$arr], \"outbound\": \"$(egress_json_escape "$tag")\"},
"; egress_xr_rules="${egress_xr_rules}      {\"type\": \"field\", \"domain\": [$arr], \"outboundTag\": \"$(egress_json_escape "$tag")\"},
";;
      ip) egress_sb_rules="${egress_sb_rules}      {\"ip_cidr\": [$arr], \"outbound\": \"$(egress_json_escape "$tag")\"},
"; egress_xr_rules="${egress_xr_rules}      {\"type\": \"field\", \"ip\": [$arr], \"outboundTag\": \"$(egress_json_escape "$tag")\"},
";;
      source) egress_sb_rules="${egress_sb_rules}      {\"source_ip_cidr\": [$arr], \"outbound\": \"$(egress_json_escape "$tag")\"},
"; egress_xr_rules="${egress_xr_rules}      {\"type\": \"field\", \"source\": [$arr], \"outboundTag\": \"$(egress_json_escape "$tag")\"},
";;
      inbound) egress_sb_rules="${egress_sb_rules}      {\"inbound\": [$arr], \"outbound\": \"$(egress_json_escape "$tag")\"},
"; egress_xr_rules="${egress_xr_rules}      {\"type\": \"field\", \"inboundTag\": [$arr], \"outboundTag\": \"$(egress_json_escape "$tag")\"},
";;
      geoip) egress_sb_rules="${egress_sb_rules}      {\"geoip\": [$arr], \"outbound\": \"$(egress_json_escape "$tag")\"},
"; egress_xr_rules="${egress_xr_rules}      {\"type\": \"field\", \"geoip\": [$arr], \"outboundTag\": \"$(egress_json_escape "$tag")\"},
";;
      geosite) local garr="" gitem="" goldifs="$IFS"; IFS=','; for gitem in $val; do gitem=$(printf '%s' "$gitem" | xargs 2>/dev/null || printf '%s' "$gitem"); [ -n "$gitem" ] || continue; [ -n "$garr" ] && garr="${garr}, "; garr="${garr}\"geosite:$(egress_json_escape "$gitem")\""; done; IFS="$goldifs"
        egress_sb_rules="${egress_sb_rules}      {\"geosite\": [$arr], \"outbound\": \"$(egress_json_escape "$tag")\"},
"; egress_xr_rules="${egress_xr_rules}      {\"type\": \"field\", \"domain\": [$garr], \"outboundTag\": \"$(egress_json_escape "$tag")\"},
";;
      port) local sb_p="" sb_r="" xr_p="" pitem="" poldifs="$IFS"; IFS=','; for pitem in $val; do pitem=$(printf '%s' "$pitem" | xargs 2>/dev/null || printf '%s' "$pitem"); case "$pitem" in *'-'*) case "$pitem" in [0-9]*-[0-9]*) sb_r="${sb_r:+$sb_r, }\"${pitem%-*}:${pitem#*-}\""; xr_p="${xr_p:+$xr_p,}$pitem";; *) echo "分流规则端口范围格式错误，已跳过：$pitem";; esac;; [0-9]*) sb_p="${sb_p:+$sb_p, }$pitem"; xr_p="${xr_p:+$xr_p,}$pitem";; *) echo "分流规则端口格式错误，已跳过：$pitem";; esac; done; IFS="$poldifs"
        if [ -n "$sb_p" ] || [ -n "$sb_r" ]; then
          egress_sb_rules="${egress_sb_rules}      {"
          [ -n "$sb_p" ] && egress_sb_rules="${egress_sb_rules}\"port\": [$sb_p], "
          [ -n "$sb_r" ] && egress_sb_rules="${egress_sb_rules}\"port_range\": [$sb_r], "
          egress_sb_rules="${egress_sb_rules}\"outbound\": \"$(egress_json_escape "$tag")\"},
"
          egress_xr_rules="${egress_xr_rules}      {\"type\": \"field\", \"port\": \"$(egress_json_escape "$xr_p")\", \"outboundTag\": \"$(egress_json_escape "$tag")\"},
"
        else
          echo "分流规则无有效端口，已跳过整条：$rule"
        fi;;
      protocol) egress_sb_rules="${egress_sb_rules}      {\"protocol\": [$arr], \"outbound\": \"$(egress_json_escape "$tag")\"},
"; egress_xr_rules="${egress_xr_rules}      {\"type\": \"field\", \"protocol\": [$arr], \"outboundTag\": \"$(egress_json_escape "$tag")\"},
";;
      *) echo "分流规则类型 $typ 暂不支持，已跳过：$rule";;
    esac
  done; IFS="$oldifs"
}
egress_geo_needed(){
  egress_geo_needed=0; egress_sb_geo_cfg=""
  local r="" typ="" part="" left="" oldifs="$IFS" goldifs2=""
  IFS=';'; for r in $egress_rules; do left="${r%%=>*}"; goldifs2="$IFS"; IFS='&'; for part in $left; do typ="${part%%:*}"; case "$typ" in geoip|geosite) egress_geo_needed=1;; esac; done; IFS="$goldifs2"; done; IFS="$oldifs"
  if [ "$egress_geo_needed" = 1 ]; then
    egress_sb_geo_cfg="    \"geoip\": {\"path\": \"$HOME/agsbx/geo/sing-box/geoip.db\"},
    \"geosite\": {\"path\": \"$HOME/agsbx/geo/sing-box/geosite.db\"},
"
  fi
}
egress_geo_download(){ # $1=url $2=file ; skip existing non-empty files
  local url="$1" file="$2"
  [ -s "$file" ] && return 0
  if command -v curl >/dev/null 2>&1; then
    curl -L --connect-timeout 15 -o "$file" "$url" >/dev/null 2>&1 || { rm -f "$file"; echo "geo 数据库下载失败：$url，请手动下载到 $file"; return 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$file" "$url" >/dev/null 2>&1 || { rm -f "$file"; echo "geo 数据库下载失败：$url，请手动下载到 $file"; return 1; }
  else
    echo "geo 数据库需要下载但本机没有 curl/wget，请手动下载到 $file"; return 1
  fi
  [ -s "$file" ] || { rm -f "$file"; echo "geo 数据库下载后文件为空：$file"; return 1; }
  return 0
}
egress_geo_setup(){
  [ "$egress_geo_needed" = 1 ] || return 0
  mkdir -p "$HOME/agsbx/geo/sing-box" "$HOME/agsbx/geo/xray" 2>/dev/null || true
  egress_geo_download "https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip.db" "$HOME/agsbx/geo/sing-box/geoip.db"
  egress_geo_download "https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite.db" "$HOME/agsbx/geo/sing-box/geosite.db"
  egress_geo_download "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" "$HOME/agsbx/geo/xray/geoip.dat"
  egress_geo_download "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" "$HOME/agsbx/geo/xray/geosite.dat"
  export XRAY_LOCATION_ASSET="$HOME/agsbx/geo/xray"
}
egress_init(){
  egress_sb_outbounds=""; egress_xr_outbounds=""; egress_sb_rules=""; egress_xr_rules=""; egress_tags=""; egress_socks_count=0; egress_vless_count=0; egress_trojan_count=0; egress_vmess_count=0; egress_ss_count=0
  # egress_add: one-time append to egress_nodes, idempotent. If a node
  # (exact ';' delimited string) is already in egress_nodes it is skipped,
  # so calling xrsbout twice (or restarting a container that still has
  # egress_add in its env) never duplicates a node. egress_add itself is
  # NEVER saved to vars.env / container_vars.env: vars_save runs after
  # ins()/xrsbout, so it saves the merged egress_nodes, and the next
  # update without egress_add inherits the appended nodes exactly once.
  # Fixed-string grep (-F) is used on purpose: node URLs contain ?, &, =
  # and # which would be glob characters in a case pattern.
  if [ -n "$egress_add" ]; then
    _eg_oldifs="$IFS"; IFS=';'
    for _eg_item in $egress_add; do
      [ -n "$_eg_item" ] || continue
      if ! printf ';%s;' "$egress_nodes" | grep -Fq ";$_eg_item;"; then
        if [ -n "$egress_nodes" ]; then egress_nodes="$egress_nodes;$_eg_item"; else egress_nodes="$_eg_item"; fi
      fi
    done
    IFS="$_eg_oldifs"
  fi
  egress_geo_needed
  [ -n "$egress_nodes" ] || [ -n "$egress_bind" ] || [ -n "$egress_rules" ] || return 0
  local oldifs="$IFS" item="" n=0
  IFS=';'; for item in $egress_nodes; do [ -n "$item" ] && egress_parse_link "$item"; done; IFS="$oldifs"
  IFS=','; for item in $egress_bind; do item=$(printf '%s' "$item" | xargs 2>/dev/null || printf '%s' "$item"); [ -n "$item" ] || continue; n=$((n + 1))
    egress_sb_outbounds="${egress_sb_outbounds}    {\"type\": \"direct\", \"tag\": \"bind${n}\", \"bind_address\": \"$(egress_json_escape "$item")\"},
"
    egress_xr_outbounds="${egress_xr_outbounds}    {\"protocol\": \"freedom\", \"tag\": \"bind${n}\", \"sendThrough\": \"$(egress_json_escape "$item")\"},
"
    egress_add_tag "bind${n}"; done; IFS="$oldifs"
  egress_parse_rules "$egress_rules"
}
# ===== EGRESS MODULE END =====
