# ===== EGRESS MODULE BEGIN (private, modular) =====
# Dynamic egress: external proxy nodes (socks5/vless, unlimited, reality in v1),
# local multi-IP bind outbounds, and per-domain/IP/source/inbound routing rules.
# Design for upstream alignment: all egress code lives in this one block.
# Upstream argosbx.sh only gets 4 hook insertions (see xrsbout) + 3 exported
# variables + egress_init call at the start of xrsbout. When egress_nodes,
# egress_bind and egress_rules are all empty, every generated variable is
# empty, so the generated sb.json/xr.json are byte-identical to before.
# Extensibility: to add a protocol, add one case in egress_parse_link
# (parser) + one sing-box fragment + one xray fragment; to add a rule
# type, add one case in egress_parse_rules. Routing/outbound generation
# never needs to change for a new protocol/rule type.
# Variables (env, set by the generator page, ';' separated, no cap):
#   egress_nodes: socks5://user:pass@host:port#tag ; vless://uuid@host:port?security=reality&pbk=..&sid=..&sni=..&fp=..&flow=..&type=tcp|ws|grpc#tag
#   egress_bind:  1.2.3.4,2001:db8::2   (each becomes bind1, bind2, ...)
#   egress_rules: domain:example.com=>tag ; ip:1.2.3.0/24=>tag ; source:10.0.0.0/8=>tag ; inbound:vm-ws=>tag
egress_json_escape(){ printf '%s' "$1" | tr -d '\n\r' | sed 's/\\/\\\\/g; s/"/\\"/g'; }
egress_url_decode(){ local s="$1"; s=$(printf '%s' "$s" | sed 's/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g'); printf '%b' "$s"; }
egress_query_param(){ local q="&$1&" k="$2" v=""; case "$q" in *"&${k}="*) v="${q#*&${k}=}"; v="${v%%&*}"; egress_url_decode "$v";; *) printf '';; esac; }
egress_json_array(){ local list="$1" out="" item="" oldifs="$IFS"; IFS=','; for item in $list; do item=$(printf '%s' "$item" | xargs 2>/dev/null || printf '%s' "$item"); [ -n "$item" ] || continue; [ -n "$out" ] && out="${out}, "; out="${out}\"$(egress_json_escape "$item")\""; done; IFS="$oldifs"; printf '%s' "$out"; }
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
      local sec="" typ="" sni="" pth="" hdr="" pbk="" sid="" fp="" flow="" svc=""
      sec=$(egress_query_param "$query" security); typ=$(egress_query_param "$query" type); sni=$(egress_query_param "$query" sni); pth=$(egress_query_param "$query" path); hdr=$(egress_query_param "$query" host); pbk=$(egress_query_param "$query" pbk); sid=$(egress_query_param "$query" sid); fp=$(egress_query_param "$query" fp); flow=$(egress_query_param "$query" flow); svc=$(egress_query_param "$query" serviceName)
      [ -n "$sni" ] || sni="$host"; [ -n "$typ" ] || typ="tcp"; [ -n "$pth" ] || pth="/"; [ -n "$hdr" ] || hdr="$sni"; [ -n "$fp" ] || fp="chrome"
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
        *) echo "vless 节点 $tag 的传输方式 $typ 暂不支持，已跳过"; return 0;;
      esac
      local xr_flow=""; [ -n "$flow" ] && xr_flow=", \"flow\": \"$(egress_json_escape "$flow")\""
      egress_sb_outbounds="${egress_sb_outbounds}    {\"type\": \"vless\", \"tag\": \"$(egress_json_escape "$tag")\", \"server\": \"$(egress_json_escape "$host")\", \"server_port\": $port, \"uuid\": \"$(egress_json_escape "$uuid")\"$sb_flow$sb_tls$sb_tr},
"
      egress_xr_outbounds="${egress_xr_outbounds}    {\"protocol\": \"vless\", \"tag\": \"$(egress_json_escape "$tag")\", \"settings\": {\"vnext\": [{\"address\": \"$(egress_json_escape "$host")\", \"port\": $port, \"users\": [{\"id\": \"$(egress_json_escape "$uuid")\"$xr_flow}]}]}, \"streamSettings\": {\"network\": \"$typ\", \"security\": \"$xr_sec\"$xr_tls$xr_tr}},
"
      egress_add_tag "$tag";;
    *) echo "出口节点协议 $scheme 暂不支持，已跳过：$tag";;
  esac
}
egress_parse_rules(){
  local rules="$1" rule="" mp="" tag="" typ="" val="" arr="" oldifs="$IFS"
  IFS=';'; for rule in $rules; do
    [ -n "$rule" ] || continue
    case "$rule" in *'=>'*) mp="${rule%%=>*}"; tag="${rule##*=>}";; *) echo "分流规则格式错误，已跳过：$rule"; continue;; esac
    case " $egress_tags direct warp-out x-warp-out " in *" $tag "*) ;; *) echo "分流规则目标出口不存在，已跳过：$rule"; continue;; esac
    typ="${mp%%:*}"; val="${mp#*:}"; arr=$(egress_json_array "$val")
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
      *) echo "分流规则类型 $typ 暂不支持，已跳过：$rule";;
    esac
  done; IFS="$oldifs"
}
egress_init(){
  egress_sb_outbounds=""; egress_xr_outbounds=""; egress_sb_rules=""; egress_xr_rules=""; egress_tags=""; egress_socks_count=0; egress_vless_count=0
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
