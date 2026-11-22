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
# 筛选：geo 定位 → 候选（三档）→ GFW 列表过滤 → 在线 TLS 1.3 + H2
#   探测（不看 HTTP 状态码，Reality 只看握手）→ 档内按握手延迟排序。
#   一档：大学/镜像/机构（最冷，优先；大学优先同州/同省，不够退同国）
#   二档：大厂冷门功能子域名
#   三档：swscan.apple.com（最后手段，一、二档筛空才用）
# 硬要求：TLS 1.3 + HTTP/2 + 合法证书。本机 curl 无 HTTP/2 支持时
#   直接报错停止，不降级、不静默跳过。

_AUTO_SNI_MAX_TEST_DOMAINS=45
_AUTO_SNI_MAX_UNIV=12
_AUTO_SNI_IPINFO_URL="https://ipinfo.io/json"
_AUTO_SNI_UNIV_URL="https://raw.githubusercontent.com/Hipo/university-domains-list/master/world_universities_and_domains.json"
_AUTO_SNI_GFW_URL="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt"
_AUTO_SNI_TMP=""
_AUTO_SNI_RESULTS=""

# 通用 CNAME 查询（dig / host / DoH 兜底）
_auto_sni_lookup_cname() {
  local domain="$1"
  if command -v dig >/dev/null 2>&1; then
    dig +short +time=2 +tries=1 CNAME "$domain" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true
  elif command -v host >/dev/null 2>&1; then
    host -W 2 -t CNAME "$domain" 2>/dev/null | awk '/is an alias for/ {print tolower($NF)}' || true
  else
    curl -4 -s --max-time 3 -H 'accept: application/dns-json' \
      "https://cloudflare-dns.com/dns-query?name=${domain}&type=CNAME" 2>/dev/null \
      | grep -oE '"type":5,"TTL":[0-9]+,"data":"[^"]+"' \
      | sed -E 's/.*"data":"([^"]+)"/\1/' | tr '[:upper:]' '[:lower:]' || true
  fi
}

# 单域名探测（由 xargs -P 并行调用）：通过则写一行
# "tier|sub|握手ms|域名|IP|状态码" 到 $_AUTO_SNI_RESULTS，不通过则静默跳过。
# 状态码只记录、不过滤（Reality 只看握手）。
_auto_sni_probe_one() {
  local tier="$1" sub="$2" domain="$3"
  local hdr_file cname metrics http_code t_app remote_ip total_ms
  hdr_file=$(mktemp "$_AUTO_SNI_TMP/hdr.XXXXXX") || return 0
  # 1. CNAME CDN 过滤
  cname=$(_auto_sni_lookup_cname "$domain")
  if printf '%s' "$cname" | grep -Eq "(cloudflare|cloudfront|akamai|fastly|edgekey|edgesuite|incapsula|sucuri|azureedge|afd\.azure|cdn)"; then
    rm -f "$hdr_file"; return 0
  fi
  # 2. 强制 IPv4 + TLS 1.3 + HTTP/2 握手探测
  metrics=$(curl -4 -sS -I -o /dev/null \
    --tlsv1.3 --tls-max 1.3 \
    --http2 \
    --connect-timeout 3 \
    --max-time 5 \
    -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" \
    -D "$hdr_file" \
    -w "%{http_code}|%{time_connect}|%{time_appconnect}|%{remote_ip}" \
    "https://${domain}" 2>/dev/null) || { rm -f "$hdr_file"; return 0; }
  http_code=$(printf '%s' "$metrics" | cut -d'|' -f1)
  t_app=$(printf '%s' "$metrics" | cut -d'|' -f3)
  remote_ip=$(printf '%s' "$metrics" | cut -d'|' -f4)
  # 3. 确认 H2（硬要求）
  if ! head -n 1 "$hdr_file" | grep -q "^HTTP/2"; then
    rm -f "$hdr_file"; return 0
  fi
  # 4. 排除主流 CDN 响应头
  if grep -Eiq "^(server:.*cloudflare|cf-ray:|cf-cache-status:|x-amz-cf-id:|x-akamai-|x-fastly-request-id:|x-served-by:.*cache|x-azure-ref:|x-iinfo:|via:.*1\.1 google)" "$hdr_file"; then
    rm -f "$hdr_file"; return 0
  fi
  total_ms=$(awk -v a="$t_app" 'BEGIN { printf "%.1f", a * 1000 }')
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

# 机构候选（国家级补充）：$1=国家码，输出 "1|2|域名" 行。
_auto_sni_institutions() {
  case "$1" in
    US|CA)
      printf '%s\n' ftp.osuosl.org mirrors.mit.edu mirrors.ocf.berkeley.edu mirror.umd.edu mirrors.rit.edu www.si.edu www.getty.edu www.loc.gov www.nist.gov www.ucla.edu www.usc.edu www.caltech.edu www.stanford.edu www.berkeley.edu www.washington.edu www.umich.edu www.utexas.edu www.nyu.edu www.columbia.edu www.metmuseum.org www.moma.org www.utoronto.ca www.ubc.ca
      ;;
    NL|DE|BE|FR|GB|CH|SE|AT|DK|NO|FI|PL|ES|IT)
      printf '%s\n' ftp.nluug.nl mirror.nl.leaseweb.net ftp.snt.utwente.nl ftp.fau.de ftp.halifax.rwth-aachen.de mirror.init7.net www.uva.nl www.tudelft.nl www.uu.nl www.rug.nl www.leidenuniv.nl www.rijksmuseum.nl www.tum.de www.lmu.de www.mpg.de www.ox.ac.uk www.cam.ac.uk www.britishmuseum.org ethz.ch www.kth.se
      ;;
    JP)
      printf '%s\n' ftp.jaist.ac.jp ftp.riken.jp linux.yz.yamagata-u.ac.jp ftp.kddilabs.jp ftp.iij.ad.jp www.u-tokyo.ac.jp www.kyoto-u.ac.jp www.osaka-u.ac.jp www.tohoku.ac.jp www.titech.ac.jp www.waseda.jp www.keio.ac.jp www.tnm.jp www.kahaku.go.jp
      ;;
    SG|HK|TW|KR)
      printf '%s\n' download.nus.edu.sg mirror.xtom.com.hk ftp.twaren.net ftp.kaist.ac.kr www.nus.edu.sg www.ntu.edu.sg www.hku.hk www.cuhk.edu.hk www.ust.hk www.ntu.edu.tw www.sinica.edu.tw www.snu.ac.kr www.kaist.ac.kr
      ;;
    AU|NZ)
      printf '%s\n' mirror.aarnet.edu.au ftp.swin.edu.au www.unimelb.edu.au www.sydney.edu.au www.anu.edu.au www.uq.edu.au www.auckland.ac.nz
      ;;
  esac | awk '{ print "1|2|" $0 }'
}

# 候选组装：$1=输出文件，$2=国家码（可空），$3=州/省（可空）。
# 输出 "tier|sub|域名" 行，已归一化、去重（同一域名只留最优档位）。
# _AUTO_SNI_EXTRA_FILE 若设为已存在的文件，其 "tier|sub|域名" 行会
# 在去重前并入（独立脚本用它传用户自定义域名；模块内不设）。
_auto_sni_candidates() {
  local out="$1" cc="$2" region="$3"
  local univ_json tmp_univ
  : > "$out"
  # --- 一档：大学（Hipo 库，同州/省优先）+ 机构（国家级列表）---
  if [ -n "$cc" ]; then
    univ_json="$_AUTO_SNI_TMP/univ.json"
    if curl -4 -sL --max-time 8 "$_AUTO_SNI_UNIV_URL" -o "$univ_json" 2>/dev/null && [ -s "$univ_json" ]; then
      tmp_univ="$_AUTO_SNI_TMP/univ.txt"
      _auto_sni_univ_extract "$univ_json" "$cc" "$region" > "$tmp_univ" 2>/dev/null || true
      if [ -s "$tmp_univ" ]; then
        # 同州/省优先：先取 sub=1 的随机顺序，不够再用 sub=2 补齐，最多 12 所
        { grep '^1|' "$tmp_univ" 2>/dev/null | shuf; grep '^2|' "$tmp_univ" 2>/dev/null | shuf; } | head -n "$_AUTO_SNI_MAX_UNIV" | awk -F'|' '{ print "1|" $1 "|www." $2 }' >> "$out" || true
      fi
    else
      echo "自动探测：高校库拉取失败，跳过大学候选"
    fi
    _auto_sni_institutions "$cc" >> "$out"
  fi
  # --- 二档：大厂冷门功能子域名（不含 swscan.apple.com）---
  cat <<'EOF' | awk '{ print "2|1|" $0 }' >> "$out"
configuration.apple.com
gspe1-ssl.ls.apple.com
xp.apple.com
learn.microsoft.com
visualstudio.microsoft.com
dotnet.microsoft.com
shop.tesla.com
git.kernel.org
www.debian.org
www.freebsd.org
www.openbsd.org
www.archlinux.org
www.gentoo.org
www.postgresql.org
www.sqlite.org
www.gnu.org
www.nginx.org
www.blender.org
www.videolan.org
cran.r-project.org
ctan.org
EOF
  # --- 三档：swscan.apple.com（最后手段）---
  echo "3|1|swscan.apple.com" >> "$out"
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
  if ! curl -4 -sL --max-time 8 "$_AUTO_SNI_GFW_URL" -o "$gfw" 2>/dev/null || [ ! -s "$gfw" ]; then
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

# 单档探测：$1=档位，$2=候选文件，$3=本档测试文件。
# 同 sub 内随机、sub=1 优先，最多测 _AUTO_SNI_MAX_TEST_DOMAINS 个。
# 返回 0 且结果文件非空表示本档有通过者。
_auto_sni_probe_tier() {
  local tier="$1" cands="$2" test_file="$3"
  : > "$_AUTO_SNI_RESULTS"
  { awk -F'|' -v t="$tier" '$1==t && $2==1' "$cands" | shuf; awk -F'|' -v t="$tier" '$1==t && $2==2' "$cands" | shuf; } | head -n "$_AUTO_SNI_MAX_TEST_DOMAINS" > "$test_file" 2>/dev/null || true
  [ -s "$test_file" ] || return 1
  export _AUTO_SNI_TMP _AUTO_SNI_RESULTS
  export -f _auto_sni_probe_one _auto_sni_lookup_cname
  xargs -P 5 -I {} bash -c 'line="{}"; tier="${line%%|*}"; rest="${line#*|}"; sub="${rest%%|*}"; domain="${rest#*|}"; sleep 0.$((RANDOM % 4 + 1)); _auto_sni_probe_one "$tier" "$sub" "$domain"' < "$test_file" || true
  [ -s "$_AUTO_SNI_RESULTS" ]
}

# 主流程（由 auto_sni_resolve 包一层临时目录管理后调用）。
# 成功：写 reym + ym_vl_re，返回 0；失败：报错，返回 1。
_auto_sni_run() {
  local cc="" region="" city="" org="" ip_json=""
  local cands="$_AUTO_SNI_TMP/candidates.txt"
  local tier test_file best best_ms
  ip_json=$(curl -4 -s --max-time 5 "$_AUTO_SNI_IPINFO_URL" 2>/dev/null || true)
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
  _auto_sni_candidates "$cands" "$cc" "$region"
  [ -s "$cands" ] || { echo "自动探测失败：无候选域名" >&2; return 1; }
  echo "自动探测：候选域名 $(wc -l < "$cands" | tr -d ' ') 个"
  _auto_sni_gfw_filter "$cands"
  [ -s "$cands" ] || { echo "自动探测失败：候选域名全部命中 GFW 列表" >&2; return 1; }
  for tier in 1 2 3; do
    test_file="$_AUTO_SNI_TMP/test-t$tier.txt"
    if ! _auto_sni_probe_tier "$tier" "$cands" "$test_file"; then
      continue
    fi
    best=$(sort -t'|' -k2,2n -k3,3n "$_AUTO_SNI_RESULTS" | head -n 1)
    if [ -n "$best" ]; then
      best_ms=$(printf '%s' "$best" | cut -d'|' -f3)
      reym=$(printf '%s' "$best" | cut -d'|' -f4)
      export ym_vl_re="$reym"
      echo "自动探测：Reality 伪装域名 $reym（第 $tier 档，握手 ${best_ms} ms）"
      return 0
    fi
  done
  echo "自动探测失败：未筛出符合条件的伪装域名（要求 TLS 1.3 + HTTP/2 + 合法证书），安装停止；可手动指定 reym 后重试" >&2
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
  _AUTO_SNI_TMP=""; _AUTO_SNI_RESULTS=""
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
