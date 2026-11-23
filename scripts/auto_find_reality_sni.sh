#!/usr/bin/env bash
set -euo pipefail
# auto_find_reality_sni.sh — Reality 伪装域名自动探测（独立可手动跑版本）
# 镜像：modules/auto-sni.sh（内嵌进生成脚本的版本）。
# 两处筛查逻辑保持一致，改一处要同步另一处。
#
# 用法：bash scripts/auto_find_reality_sni.sh [域名|域名文件 ...]
#   不传参数：按本机 geo 自动筛。传域名/文件：作二档候选并入。
# 输出：进度走 stderr；最优域名（仅一行）走 stdout，可直接捕获：
#   reym=$(bash scripts/auto_find_reality_sni.sh)
# 失败（未筛出符合条件的域名，或本机 curl 不支持 HTTP/2）时 stdout
# 为空且 exit 1。
#
# 筛选：geo 定位 → 候选（三档，按当地国家/州精细化加载）→ GFW 列表过滤 →
#   在线 TLS 1.3 + X25519 + H2 探测（防 DNS 污染/回环 IP + 排除主流 CDN + 过滤非 200 跳转/拦截页 + PQ 大包兼容）→ 档内按优先级与握手延迟排序。
#   一档：当地精选高校/开源镜像站/博物馆（sub=1）> Hipo 同州高校（sub=2）> Hipo 同国高校（sub=3）
#   二档：第三方高带宽冷门大厂与开源基础设施直连源站（剔除教程泛滥域名）
#   三档：经典大厂高可用兜底池（learn.microsoft.com / configuration.apple.com / swscan.apple.com，一、二档筛空才用）
#   可选环境变量 reym_tier=2（跳过一档直选开源基础设施，适合企业网/严格代理环境）或 reym_tier=3。
# 硬要求：TLS 1.3 + X25519 + HTTP/2 + 合法证书（一/二档要求 200）。本机 curl 无 HTTP/2 支持时
#   直接报错停止，不降级、不静默跳过。

_AUTO_SNI_MAX_TEST_DOMAINS=15
_AUTO_SNI_MAX_UNIV=8
_AUTO_SNI_TIER1_SLOW_MS=60
_AUTO_SNI_IPINFO_URL="https://ipinfo.io/json"
_AUTO_SNI_UNIV_URL="https://raw.githubusercontent.com/Hipo/university-domains-list/master/world_universities_and_domains.json"
_AUTO_SNI_GFW_URL="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt"
_AUTO_SNI_TMP=""
_AUTO_SNI_RESULTS=""
_AUTO_SNI_SELF_IP=""

# 通用 CNAME 查询（本机视角 + 中国大陆 ECS 视角，防 Geo-DNS 双面解析套 CDN，如美西直连但国内分流至 cdn.webflow.com/Cloudflare）
_auto_sni_lookup_cname() {
  local domain="$1" local_cname="" cn_cname=""
  if command -v dig >/dev/null 2>&1; then
    local_cname=$(dig +short +time=2 +tries=1 CNAME "$domain" 2>/dev/null | grep -v '^;' | tr '[:upper:]' '[:lower:]' || true)
    if ! cn_cname=$(dig @8.8.8.8 +subnet=223.5.5.0/24 +short +time=2 +tries=1 CNAME "$domain" 2>/dev/null); then
      cn_cname=$(curl -4 -s --max-time 3 "https://dns.google/resolve?name=${domain}&type=CNAME&edns_client_subnet=223.5.5.0/24" 2>/dev/null \
        | grep -oE '"type":5,"TTL":[0-9]+,"data":"[^"]+"' \
        | sed -E 's/.*"data":"([^"]+)"/\1/' || true)
    fi
    cn_cname=$(printf '%s\n' "$cn_cname" | grep -v '^;' | tr '[:upper:]' '[:lower:]' || true)
  elif command -v host >/dev/null 2>&1; then
    local_cname=$(host -W 2 -t CNAME "$domain" 2>/dev/null | awk '/is an alias for/ {print tolower($NF)}' || true)
    cn_cname=$(curl -4 -s --max-time 3 "https://dns.google/resolve?name=${domain}&type=CNAME&edns_client_subnet=223.5.5.0/24" 2>/dev/null \
      | grep -oE '"type":5,"TTL":[0-9]+,"data":"[^"]+"' \
      | sed -E 's/.*"data":"([^"]+)"/\1/' | tr '[:upper:]' '[:lower:]' || true)
  else
    local_cname=$(curl -4 -s --max-time 3 -H 'accept: application/dns-json' \
      "https://cloudflare-dns.com/dns-query?name=${domain}&type=CNAME" 2>/dev/null \
      | grep -oE '"type":5,"TTL":[0-9]+,"data":"[^"]+"' \
      | sed -E 's/.*"data":"([^"]+)"/\1/' | tr '[:upper:]' '[:lower:]' || true)
    cn_cname=$(curl -4 -s --max-time 3 "https://dns.google/resolve?name=${domain}&type=CNAME&edns_client_subnet=223.5.5.0/24" 2>/dev/null \
      | grep -oE '"type":5,"TTL":[0-9]+,"data":"[^"]+"' \
      | sed -E 's/.*"data":"([^"]+)"/\1/' | tr '[:upper:]' '[:lower:]' || true)
  fi
  printf '%s\n%s\n' "$local_cname" "$cn_cname"
}

# 校验解析出的目标 IP 是否为有效公网 IP（排除回环、内网保留地址及本机自身 IP，防 DNS 污染与自环握手）
_auto_sni_valid_remote_ip() {
  local ip="$1"
  [ -n "$ip" ] || return 1
  if [ -n "${_AUTO_SNI_SELF_IP:-}" ] && [ "$ip" = "$_AUTO_SNI_SELF_IP" ]; then
    return 1
  fi
  case "$ip" in
    0.*|127.*|10.*|192.168.*|169.254.*|224.*|240.*|255.*) return 1 ;;
    172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) return 1 ;;
    100.6[4-9].*|100.[7-9][0-9].*|100.1[0-1][0-9].*|100.12[0-7].*) return 1 ;;
  esac
  return 0
}

# Check whether local curl supports --curves (introduced in curl 7.73.0).
_auto_sni_curl_supports_curves() {
  local ver major minor
  ver=$(curl --version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+' | head -n 1 || true)
  [ -n "$ver" ] || return 1
  major="${ver%%.*}"
  minor="${ver#*.}"
  [ "$major" -gt 7 ] 2>/dev/null || { [ "$major" -eq 7 ] 2>/dev/null && [ "$minor" -ge 73 ] 2>/dev/null; }
}

# Check whether local curl uses OpenSSL >= 3.5 (supports --curves X25519MLKEM768:X25519).
_auto_sni_curl_supports_pq() {
  _auto_sni_curl_supports_curves || return 1
  local ssl_ver major minor
  ssl_ver=$(curl --version 2>/dev/null | head -n 1 | grep -oE 'OpenSSL/[0-9]+\.[0-9]+' | head -n 1 | cut -d/ -f2 || true)
  [ -n "$ssl_ver" ] || return 1
  major="${ssl_ver%%.*}"
  minor="${ssl_ver#*.}"
  [ "$major" -gt 3 ] 2>/dev/null || { [ "$major" -eq 3 ] 2>/dev/null && [ "$minor" -ge 5 ] 2>/dev/null; }
}

# 单域名探测（由 xargs -P 并行调用）：通过则写一行
# "tier|sub|TCP_ms|域名|IP|状态码" 到 $_AUTO_SNI_RESULTS，不通过则静默跳过。
# 一/二档硬要求 HTTP/2 200（剔除 301/302 裸域空跳转及 403/5xx 拦截页）；三档兜底池允许 2xx/3xx/404。
_auto_sni_probe_one() {
  local tier="$1" sub="$2" domain="$3"
  local hdr_file cname metrics http_code t_dns t_conn remote_ip total_ms
  hdr_file=$(mktemp "$_AUTO_SNI_TMP/hdr.XXXXXX") || return 0
  # 1. CNAME CDN 过滤（同时覆盖本机视角与中国大陆 ECS 视角）
  cname=$(_auto_sni_lookup_cname "$domain")
  if printf '%s' "$cname" | grep -Eq "(cloudflare|cloudfront|akamai|fastly|edgekey|edgesuite|incapsula|sucuri|azureedge|afd\.azure|edgecast|bunnycdn|gcore|cdn77|azion|webflow|cdn)"; then
    rm -f "$hdr_file"; return 0
  fi
  # 2. 强制 IPv4 + TLS 1.3 + X25519 + HTTP/2 握手探测（默认严格验证证书链，不加 -k）
  # REALITY 硬性要求目标站支持 X25519 密钥交换（不触发 HelloRetryRequest 强制 P-521/P-384），
  # 否则服务端 REALITY 握手必定报 "REALITY: processed invalid connection"。
  local -a curve_args=()
  if _auto_sni_curl_supports_curves; then
    curve_args=(--curves X25519)
  fi
  metrics=$(curl -4 -sS -I -o /dev/null \
    --tlsv1.3 --tls-max 1.3 \
    "${curve_args[@]}" \
    --http2 \
    --connect-timeout 3 \
    --max-time 5 \
    -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" \
    -D "$hdr_file" \
    -w "%{http_code}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{remote_ip}" \
    "https://${domain}" 2>/dev/null) || { rm -f "$hdr_file"; return 0; }
  # 老版本 curl (<7.73) 无 --curves 参数时，用 openssl 兜底验证目标站是否支持 X25519
  if [ "${#curve_args[@]}" -eq 0 ] && command -v openssl >/dev/null 2>&1; then
    if ! timeout 4 openssl s_client -connect "${domain}:443" -servername "$domain" -tls1_3 -groups X25519 -brief </dev/null 2>&1 | grep -qi "X25519"; then
      rm -f "$hdr_file"; return 0
    fi
  fi
  http_code=$(printf '%s' "$metrics" | cut -d'|' -f1)
  t_dns=$(printf '%s' "$metrics" | cut -d'|' -f2)
  t_conn=$(printf '%s' "$metrics" | cut -d'|' -f3)
  remote_ip=$(printf '%s' "$metrics" | cut -d'|' -f5)
  # 3. 校验远端 IP 合法性（防 DNS 污染与本机回环假阳性）
  if ! _auto_sni_valid_remote_ip "$remote_ip"; then
    rm -f "$hdr_file"; return 0
  fi
  # 4. 确认 H2（硬要求）及状态码健康性（一/二档要求 200；三档兜底池允许 2xx/3xx/404，剔除 403/5xx/000）
  if ! head -n 1 "$hdr_file" | grep -q "^HTTP/2"; then
    rm -f "$hdr_file"; return 0
  fi
  if [ "$tier" = "3" ]; then
    case "$http_code" in
      2[0-9][0-9]|3[0-9][0-9]|404) ;;
      *) rm -f "$hdr_file"; return 0 ;;
    esac
  else
    [ "$http_code" = "200" ] || { rm -f "$hdr_file"; return 0; }
  fi
  # 5. 排除主流 CDN 响应头
  if grep -Eiq "^(server:.*(cloudflare|akamaighost|cloudfront|fastly|bunnycdn|gcore)|cf-ray:|cf-cache-status:|x-amz-cf-id:|x-akamai-|x-fastly-request-id:|x-served-by:.*cache|x-azure-ref:|x-iinfo:|via:.*1\.1 google)" "$hdr_file"; then
    rm -f "$hdr_file"; return 0
  fi
  # 6. 若本机 curl/OpenSSL 支持后量子曲线，加测 X25519MLKEM768:X25519 大包 ClientHello 兼容性，
  #    剔除收到现代浏览器大包握手直接报 alert/handshake_failure 的老旧站或中间设备。
  if _auto_sni_curl_supports_pq; then
    if ! curl -4 -sS -I -o /dev/null \
      --tlsv1.3 --tls-max 1.3 \
      --curves X25519MLKEM768:X25519 \
      --http2 \
      --connect-timeout 3 \
      --max-time 4 \
      -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" \
      "https://${domain}" 2>/dev/null; then
      rm -f "$hdr_file"; return 0
    fi
  fi
  # 仅计纯 TCP RTT（time_connect - time_namelookup），扣除本地 DNS 与 curl 冷加载 CA 证书的 CPU 伪耗时
  total_ms=$(awk -v c="$t_conn" -v d="$t_dns" 'BEGIN { v = (c - d) * 1000; if (v < 0) v = c * 1000; printf "%.1f", v }')
  printf "%s|%s|%08.1f|%s|%s|%s\n" "$tier" "$sub" "$total_ms" "$domain" "$remote_ip" "$http_code" >> "$_AUTO_SNI_RESULTS"
  rm -f "$hdr_file"
}

# 大学 JSON 提取：$1=json 文件，$2=国家码，$3=州/省（可空）。
# 输出 "sub|域名" 行，sub=1 同州/同省，sub=2 同国。
# python3 优先精确解析；无 python3 时用不依赖多字符 RS 的 awk
#（RS="}" 单字符，mawk 可用；原脚本的多字符 RS 在 mawk 下整文件
# 成一条记录，永远取第一个域名）。
_auto_sni_univ_extract() {
  local json="$1" cc="$2" region="$3"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$json" "$cc" "$region" <<'PYEOF'
import json, sys
path, cc, region = sys.argv[1], sys.argv[2].upper(), sys.argv[3]
try:
    data = json.load(open(path))
except Exception:
    sys.exit(0)
for u in data:
    if not isinstance(u, dict):
        continue
    if (u.get("alpha_two_code") or "").upper() != cc:
        continue
    doms = u.get("domains") or []
    if not doms:
        continue
    st = u.get("state-province") or ""
    sub = "1" if (region and st and st.lower() == region.lower()) else "2"
    print(sub + "|" + doms[0])
PYEOF
    return 0
  fi
  awk -v cc="$cc" -v region="$region" '
    BEGIN { RS = "}" }
    tolower($0) ~ "\"alpha_two_code\"[[:space:]]*:[[:space:]]*\"" tolower(cc) "\"" {
      state_ok = 0
      if (region != "" && match($0, /"state-province"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
        s = substr($0, RSTART, RLENGTH)
        sub(/.*"state-province"[[:space:]]*:[[:space:]]*"/, "", s)
        sub(/".*/, "", s)
        if (tolower(s) == tolower(region)) state_ok = 1
      }
      if (match($0, /"domains"[[:space:]]*:[[:space:]]*\["[^"]+"/)) {
        s = substr($0, RSTART, RLENGTH)
        sub(/.*"domains"[[:space:]]*:[[:space:]]*\["/, "", s)
        sub(/".*/, "", s)
        if (s != "") print (state_ok ? 1 : 2) "|" s
      }
    }
  ' "$json"
}

# 当地精选大学/博物馆/开源镜像站候选（按具体国家码 $1 与州/地区 $2 精细化加载，拒绝跨国大区盲测）：
# 输出 "1|1|域名" 行（sub=1 最高优先级，高于 Hipo 随机抽取高校）。
_auto_sni_institutions() {
  local cc="$1" region="${2:-}"
  case "$cc" in
    US)
      case "$region" in
        California|Washington|Oregon|Nevada|Arizona|Utah|Colorado)
          printf '1|1|%s\n' ftp.osuosl.org mirrors.ocf.berkeley.edu www.ucla.edu www.usc.edu www.caltech.edu www.stanford.edu www.berkeley.edu www.washington.edu www.getty.edu
          ;;
        Texas|Illinois|Michigan|Minnesota|Ohio|Wisconsin|Indiana|Missouri)
          printf '1|1|%s\n' www.umich.edu www.utexas.edu www.uchicago.edu www.purdue.edu www.wisc.edu ftp.osuosl.org
          ;;
        *)
          printf '1|1|%s\n' mirrors.mit.edu mirror.umd.edu mirrors.rit.edu ftp.osuosl.org www.si.edu www.loc.gov www.nist.gov www.nyu.edu www.columbia.edu www.metmuseum.org www.moma.org www.stanford.edu www.berkeley.edu www.umich.edu
          ;;
      esac
      ;;
    CA)
      printf '1|1|%s\n' www.utoronto.ca www.ubc.ca www.mcgill.ca www.uwaterloo.ca mirror.its.dal.ca www.rom.on.ca
      ;;
    JP)
      printf '1|1|%s\n' ftp.jaist.ac.jp ftp.riken.jp linux.yz.yamagata-u.ac.jp ftp.kddilabs.jp ftp.iij.ad.jp www.u-tokyo.ac.jp www.kyoto-u.ac.jp www.osaka-u.ac.jp www.tohoku.ac.jp www.titech.ac.jp www.waseda.jp www.keio.ac.jp www.tnm.jp www.kahaku.go.jp
      ;;
    SG)
      printf '1|1|%s\n' download.nus.edu.sg www.nus.edu.sg www.ntu.edu.sg www.smu.edu.sg mirror.xtom.com.hk
      ;;
    HK)
      printf '1|1|%s\n' mirror.xtom.com.hk www.hku.hk www.cuhk.edu.hk www.ust.hk www.polyu.edu.hk www.cityu.edu.hk
      ;;
    TW)
      printf '1|1|%s\n' ftp.twaren.net opensource.nchc.org.tw www.ntu.edu.tw www.sinica.edu.tw www.nycu.edu.tw www.nthu.edu.tw www.npm.gov.tw
      ;;
    KR)
      printf '1|1|%s\n' ftp.kaist.ac.kr www.snu.ac.kr www.kaist.ac.kr www.yonsei.ac.kr www.korea.ac.kr www.museum.go.kr
      ;;
    DE)
      printf '1|1|%s\n' ftp.fau.de ftp.halifax.rwth-aachen.de ftp.gwdg.de www.tum.de www.lmu.de www.mpg.de www.uni-heidelberg.de www.kit.edu
      ;;
    NL)
      printf '1|1|%s\n' ftp.nluug.nl mirror.nl.leaseweb.net ftp.snt.utwente.nl www.uva.nl www.tudelft.nl www.uu.nl www.rug.nl www.leidenuniv.nl www.rijksmuseum.nl
      ;;
    GB)
      printf '1|1|%s\n' www.ox.ac.uk www.cam.ac.uk www.ed.ac.uk www.imperial.ac.uk www.ucl.ac.uk www.manchester.ac.uk www.britishmuseum.org
      ;;
    FR)
      printf '1|1|%s\n' mirrors.ircam.fr ftp.lip6.fr www.polytechnique.edu www.sorbonne-universite.fr www.inria.fr www.cnrs.fr
      ;;
    CH)
      printf '1|1|%s\n' mirror.init7.net ethz.ch www.epfl.ch www.uzh.ch www.cern.ch
      ;;
    SE|NO|FI|DK)
      printf '1|1|%s\n' ftp.acc.umu.se www.kth.se www.uu.se www.lu.se www.ntnu.no www.uio.no www.helsinki.fi www.aalto.fi www.ku.dk
      ;;
    AT|BE|PL|ES|IT|IE)
      printf '1|1|%s\n' www.univie.ac.at www.tuwien.ac.at www.kuleuven.be www.ugent.be ftp.icm.edu.pl www.uw.edu.pl www.ucm.es www.polimi.it ftp.heanet.ie www.tcd.ie
      ;;
    AU|NZ)
      printf '1|1|%s\n' mirror.aarnet.edu.au ftp.swin.edu.au www.unimelb.edu.au www.sydney.edu.au www.anu.edu.au www.uq.edu.au www.auckland.ac.nz
      ;;
  esac
}

# 候选组装：$1=输出文件，$2=国家码（可空），$3=州/省（可空）。
# 输出 "tier|sub|域名" 行，已归一化、去重（同一域名只留最优档位）。
# _AUTO_SNI_EXTRA_FILE 若设为已存在的文件，其 "tier|sub|域名" 行会
# 在去重前并入（独立脚本用它传用户自定义域名；模块内不设）。
_auto_sni_candidates() {
  local out="$1" cc="$2" region="$3"
  local univ_json tmp_univ
  : > "$out"
  # --- 一档：当地精选机构/镜像站（sub=1）+ Hipo 当地大学（同州 sub=2，同国 sub=3）；reym_tier=2/3 时跳过 ---
  if [ "${reym_tier:-1}" = "1" ] && [ -n "$cc" ]; then
    _auto_sni_institutions "$cc" "$region" >> "$out"
    univ_json="$_AUTO_SNI_TMP/univ.json"
    if curl -4 -sL --max-time 6 "$_AUTO_SNI_UNIV_URL" -o "$univ_json" 2>/dev/null && [ -s "$univ_json" ]; then
      tmp_univ="$_AUTO_SNI_TMP/univ.txt"
      _auto_sni_univ_extract "$univ_json" "$cc" "$region" > "$tmp_univ" 2>/dev/null || true
      if [ -s "$tmp_univ" ]; then
        # 同州/省优先（sub=2），不够再用同国（sub=3）补齐，最多 _AUTO_SNI_MAX_UNIV 所；
        # 同时输出 www.<domain> 与根域名 <domain>（防 www 挂 CDN 而根域在校园网自建被误杀）
        { grep '^1|' "$tmp_univ" 2>/dev/null | shuf; grep '^2|' "$tmp_univ" 2>/dev/null | shuf; } | head -n "$_AUTO_SNI_MAX_UNIV" | awk -F'|' '{
          d = $2
          sub_prio = $1 + 1
          if (d ~ /^www\./) {
            print "1|" sub_prio "|" d
          } else {
            print "1|" sub_prio "|www." d
            print "1|" sub_prio "|" d
          }
        }' >> "$out" || true
      fi
    else
      echo "自动探测：高校库拉取失败，使用内置当地机构与镜像站候选"
    fi
  fi
  # --- 二档：高带宽冷门大厂与开源基础设施直连源站（已剔除公开教程泛滥域名）---
  cat <<'EOF' | awk '{ print "2|1|" $0 }' >> "$out"
git.kernel.org
mirrors.kernel.org
www.debian.org
deb.debian.org
www.freebsd.org
download.freebsd.org
www.openbsd.org
www.archlinux.org
www.gentoo.org
www.postgresql.org
www.sqlite.org
www.gnu.org
ftp.gnu.org
www.nginx.org
hg.nginx.org
www.blender.org
download.blender.org
www.videolan.org
cran.r-project.org
ctan.org
www.wireshark.org
www.cmake.org
xp.apple.com
EOF
  # --- 三档：经典高可用大厂兜底池（最后手段，仅当一、二档全部筛空时才启用）---
  cat <<'EOF' | awk '{ print "3|1|" $0 }' >> "$out"
learn.microsoft.com
configuration.apple.com
gspe1-ssl.ls.apple.com
swscan.apple.com
EOF
  if [ -n "${_AUTO_SNI_EXTRA_FILE:-}" ] && [ -f "$_AUTO_SNI_EXTRA_FILE" ]; then
    cat "$_AUTO_SNI_EXTRA_FILE" >> "$out"
  fi
  # 归一化（小写、去 scheme/路径）+ 去重（同一域名只留最优档位）
  awk -F'|' 'NF >= 3 {
    d = tolower($3)
    gsub(/^https?:\/\//, "", d); gsub(/\/.*$/, "", d)
    if (d == "") next
    print $1 "|" $2 "|" d
  }' "$out" | sort -t'|' -k3,3 -k1,1n -k2,2n | awk -F'|' '!seen[$3]++' > "$out.tmp" && mv "$out.tmp" "$out"
}

# GFW 列表过滤：$1=候选文件（原地过滤）。拉取失败则跳过并告警。
_auto_sni_gfw_filter() {
  local cands="$1" gfw="$_AUTO_SNI_TMP/gfw.txt"
  if ! curl -4 -sL --max-time 6 "$_AUTO_SNI_GFW_URL" -o "$gfw" 2>/dev/null || [ ! -s "$gfw" ]; then
    echo "自动探测：GFW 规则库拉取失败，跳过阻断比对"
    return 0
  fi
  awk -F'|' '
    NR==FNR { gsub(/\r/, "", $1); if ($1 != "") blocked[tolower($1)] = 1; next }
    {
      dom = $3
      is_blocked = 0
      n = split(dom, parts, ".")
      cur = parts[n]
      for (i = n - 1; i >= 1; i--) {
        cur = parts[i] "." cur
        if (cur in blocked) { is_blocked = 1; break }
      }
      if (!is_blocked) print $0
      else print $0 > "'"$cands.blocked"'"
    }
  ' "$gfw" "$cands" > "$cands.tmp" && mv "$cands.tmp" "$cands"
  if [ -s "$cands.blocked" ]; then
    echo "自动探测：已剔除命中 GFW 列表的域名：$(cut -d'|' -f3 "$cands.blocked" | tr '\n' ' ')"
    rm -f "$cands.blocked"
  fi
}

# 按 CPU 核数自适应并发度（防 1~2 核低配 VPS 上多路 curl TLS 握手抢核导致延迟失真）
_auto_sni_probe_jobs() {
  local cpus=2
  if command -v nproc >/dev/null 2>&1; then
    cpus=$(nproc 2>/dev/null || echo 2)
  elif [ -r /proc/cpuinfo ]; then
    cpus=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 2)
  fi
  case "$cpus" in ''|*[!0-9]*) cpus=2 ;; esac
  if [ "$cpus" -le 1 ]; then
    echo 2
  elif [ "$cpus" -le 2 ]; then
    echo 3
  elif [ "$cpus" -le 4 ]; then
    echo 4
  else
    echo 6
  fi
}

# 单档探测：$1=档位，$2=候选文件，$3=本档测试文件。
# 同 sub 内随机、按 sub=1→2→3 优先级抽样，最多测 _AUTO_SNI_MAX_TEST_DOMAINS 个候选。
# 返回 0 且结果文件非空表示本档有通过者。
_auto_sni_probe_tier() {
  local tier="$1" cands="$2" test_file="$3" jobs
  : > "$_AUTO_SNI_RESULTS"
  {
    awk -F'|' -v t="$tier" '$1==t && $2==1' "$cands" | shuf
    awk -F'|' -v t="$tier" '$1==t && $2==2' "$cands" | shuf
    awk -F'|' -v t="$tier" '$1==t && $2==3' "$cands" | shuf
  } | head -n "$_AUTO_SNI_MAX_TEST_DOMAINS" > "$test_file" 2>/dev/null || true
  [ -s "$test_file" ] || return 1
  jobs=$(_auto_sni_probe_jobs)
  export _AUTO_SNI_TMP _AUTO_SNI_RESULTS _AUTO_SNI_SELF_IP
  export -f _auto_sni_probe_one _auto_sni_lookup_cname _auto_sni_valid_remote_ip _auto_sni_curl_supports_curves _auto_sni_curl_supports_pq
  xargs -P "$jobs" -I {} bash -c 'line="{}"; tier="${line%%|*}"; rest="${line#*|}"; sub="${rest%%|*}"; domain="${rest#*|}"; _auto_sni_probe_one "$tier" "$sub" "$domain"' < "$test_file" || true
  [ -s "$_AUTO_SNI_RESULTS" ]
}

# 主流程（由 auto_sni_resolve 包一层临时目录管理后调用）。
# 成功：写 reym + ym_vl_re，同步回落变量与 443 四层 SNI 分流，返回 0；失败：报错，返回 1。
_auto_sni_run() {
  local cc="" region="" city="" org="" ip_json=""
  local cands="$_AUTO_SNI_TMP/candidates.txt"
  local sorted_file="$_AUTO_SNI_TMP/sorted.txt"
  local t1_sorted="$_AUTO_SNI_TMP/sorted-t1.txt"
  local t2_sorted="$_AUTO_SNI_TMP/sorted-t2.txt"
  local tiers="1 2 3" tier test_file best best_ms best_ms_disp top_list
  local t1_best t1_ms t1_ms_disp t1_dom t2_best t2_ms merged_t12=0
  case "${reym_tier:-1}" in
    2) tiers="2 3" ;;
    3) tiers="3" ;;
    *) tiers="1 2 3" ;;
  esac
  ip_json=$(curl -4 -s --max-time 5 "$_AUTO_SNI_IPINFO_URL" 2>/dev/null || true)
  _AUTO_SNI_SELF_IP=$(printf '%s' "$ip_json" | grep -oE '"ip": *"[^"]+"' | cut -d'"' -f4 2>/dev/null || true)
  cc=$(printf '%s' "$ip_json" | grep -oE '"country": *"[^"]+"' | cut -d'"' -f4 2>/dev/null || true)
  region=$(printf '%s' "$ip_json" | grep -oE '"region": *"[^"]+"' | cut -d'"' -f4 2>/dev/null || true)
  city=$(printf '%s' "$ip_json" | grep -oE '"city": *"[^"]+"' | cut -d'"' -f4 2>/dev/null || true)
  org=$(printf '%s' "$ip_json" | grep -oE '"org": *"[^"]+"' | cut -d'"' -f4 2>/dev/null || true)
  cc=$(printf '%s' "$cc" | tr '[:lower:]' '[:upper:]')
  if [ -n "$cc" ]; then
    echo "自动探测：本机 ${city:-未知}, ${cc}${region:+（$region）}，${org:-未知}"
  else
    echo "自动探测：地理位置获取失败，跳过本国大学/机构候选，只筛大厂子域名"
  fi
  if [ "$tiers" != "1 2 3" ]; then
    echo "自动探测：已指定起始档位 reym_tier=${reym_tier}（跳过一档小众高校，优先高兼容源站）"
  fi
  _auto_sni_candidates "$cands" "$cc" "$region"
  [ -s "$cands" ] || { echo "自动探测失败：无候选域名" >&2; return 1; }
  echo "自动探测：候选域名 $(wc -l < "$cands" | tr -d ' ') 个"
  _auto_sni_gfw_filter "$cands"
  [ -s "$cands" ] || { echo "自动探测失败：候选域名全部命中 GFW 列表" >&2; return 1; }
  for tier in $tiers; do
    test_file="$_AUTO_SNI_TMP/test-t$tier.txt"
    if ! _auto_sni_probe_tier "$tier" "$cands" "$test_file"; then
      continue
    fi
    sort -t'|' -k2,2n -k3,3n "$_AUTO_SNI_RESULTS" > "$sorted_file"
    best=$(head -n 1 "$sorted_file")
    if [ -n "$best" ]; then
      best_ms=$(printf '%s' "$best" | cut -d'|' -f3)
      merged_t12=0
      # 第 1 档最优 TCP RTT >= _AUTO_SNI_TIER1_SLOW_MS (60ms) 时，顺手探测第 2 档对比延迟；仅当第 2 档更快时改用第 2 档
      if [ "$tier" = "1" ] && awk -v a="$best_ms" -v b="$_AUTO_SNI_TIER1_SLOW_MS" 'BEGIN { exit !(a + 0 >= b + 0) }'; then
        t1_best="$best"; t1_ms="$best_ms"; t1_dom=$(printf '%s' "$best" | cut -d'|' -f4); t2_best=""; t2_ms=""
        t1_ms_disp=$(awk -v a="$t1_ms" 'BEGIN { printf "%.1f", a + 0 }')
        cp "$sorted_file" "$t1_sorted"
        echo "自动探测：第 1 档最优 ${t1_dom}（TCP ${t1_ms_disp} ms >= ${_AUTO_SNI_TIER1_SLOW_MS} ms），顺手探测第 2 档对比延迟"
        if _auto_sni_probe_tier 2 "$cands" "$_AUTO_SNI_TMP/test-t2.txt"; then
          sort -t'|' -k2,2n -k3,3n "$_AUTO_SNI_RESULTS" > "$t2_sorted"
          t2_best=$(head -n 1 "$t2_sorted")
          t2_ms=$(printf '%s' "$t2_best" | cut -d'|' -f3)
          sort -t'|' -k3,3n "$t1_sorted" "$t2_sorted" > "$sorted_file"
          merged_t12=1
          if [ -n "$t2_best" ] && awk -v a="$t2_ms" -v b="$t1_ms" 'BEGIN { exit !(a + 0 < b + 0) }'; then
            tier=2; best="$t2_best"; best_ms="$t2_ms"
          else
            best="$t1_best"; best_ms="$t1_ms"
          fi
        else
          cp "$t1_sorted" "$sorted_file"
          best="$t1_best"; best_ms="$t1_ms"
        fi
      fi
      reym=$(printf '%s' "$best" | cut -d'|' -f4)
      export ym_vl_re="$reym"
      if [ -n "${ym_vl_re}" ] && [ "${ym_vl_re}" = "${ym:-}" ]; then
        export ym_vl_fb="127.0.0.1"; export ym_vl_fb_port="${web_port:-443}"
      else
        export ym_vl_fb=""; export ym_vl_fb_port="443"
      fi
      if command -v vlpt_coexistence_sync_sni >/dev/null 2>&1; then
        # set-port 失败必须停装：Reality 入站已移到内网端口，路由器没生效则 443 无人监听。
        # 返回 1 透传给 auto_sni_resolve，ins() 收到非零即停装。
        vlpt_coexistence_sync_sni "$reym" || return 1
      fi
      best_ms_disp=$(awk -v a="$best_ms" 'BEGIN { printf "%.1f", a + 0 }')
      echo "自动探测：Reality 伪装域名 $reym（第 $tier 档，TCP ${best_ms_disp} ms）"
      if [ "$merged_t12" = "1" ]; then
        top_list=$(head -n 5 "$sorted_file" | awk -F'|' '{ printf "%s(T%s/%.0fms/%s) ", $4, $1, $3+0, $6 }')
        echo "自动探测：Top 候选（第 1/2 档合并）：${top_list% }"
      else
        top_list=$(head -n 5 "$sorted_file" | awk -F'|' '{ printf "%s(%.0fms/%s) ", $4, $3+0, $6 }')
        echo "自动探测：本档 Top 候选：${top_list% }"
      fi
      return 0
    fi
  done
  echo "自动探测失败：未筛出符合条件的伪装域名（要求 TLS 1.3 + X25519 + HTTP/2 + 合法证书），安装停止；可手动指定 reym 后重试" >&2
  return 1
}

# 入口：reym 已有时直接返回 0（幂等，rep/add 不重筛）。
auto_sni_resolve() {
  local rc
  if [ -n "${reym:-}" ]; then return 0; fi
  # H2 是硬要求：本机 curl 必须支持 HTTP/2，否则直接停装。
  if ! curl --version 2>/dev/null | grep -q 'HTTP2'; then
    echo "自动探测失败：本机 curl 不支持 HTTP/2（H2 是伪装域名的硬要求），无法验证；请安装带 HTTP/2 支持的 curl，或手动指定 reym" >&2
    return 1
  fi
  for cmd in curl awk grep sort xargs shuf tr mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "自动探测失败：缺少命令 $cmd" >&2
      return 1
    fi
  done
  _AUTO_SNI_TMP=$(mktemp -d) || return 1
  _AUTO_SNI_RESULTS="$_AUTO_SNI_TMP/results.txt"
  : > "$_AUTO_SNI_RESULTS"
  rc=0
  _auto_sni_run || rc=$?
  rm -rf "$_AUTO_SNI_TMP"
  _AUTO_SNI_TMP=""; _AUTO_SNI_RESULTS=""; _AUTO_SNI_SELF_IP=""
  return $rc
}

# --- 独立脚本主流程：参数作二档候选，进度走 stderr，最优域名走 stdout ---
main() {
  local extra_dir extra_file arg
  ym_vl_re=""; reym=""
  extra_dir=$(mktemp -d) || exit 1
  trap "rm -rf $extra_dir" EXIT
  extra_file="$extra_dir/extra.txt"
  : > "$extra_file"
  for arg in "$@"; do
    if [ -f "$arg" ]; then
      awk 'NF { print "2|1|" tolower($1) }' "$arg" >> "$extra_file"
    else
      printf '2|1|%s\n' "$(printf '%s' "$arg" | tr '[:upper:]' '[:lower:]')" >> "$extra_file"
    fi
  done
  export _AUTO_SNI_EXTRA_FILE="$extra_file"
  if ! auto_sni_resolve >&2; then
    exit 1
  fi
  printf '%s\n' "$reym"
}

main "$@"
