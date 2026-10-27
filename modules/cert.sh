export ym=${ym:-''}
export alns=${alns:-''}
export CERT_DIR="$HOME/agsbx/cert"
export CERT_CRT="$CERT_DIR/cert.crt"
export CERT_KEY="$CERT_DIR/private.key"
# cert_migrate_paths: one-time move from the old $HOME/argosbx locations
# to the unified $HOME/agsbx tree. Copies only, never deletes the old
# files (old configs / acme renewals may still reference them until the
# next install regenerates json). Idempotent: a second call is a no-op
# except for the acme install-path update, which is itself idempotent.
cert_migrate_paths(){
  if [ -s "$HOME/argosbx/cert/cert.crt" ]; then
    mkdir -p "$HOME/agsbx/cert" 2>/dev/null || true
    [ -s "$HOME/agsbx/cert/cert.crt" ] || cp -P "$HOME/argosbx/cert/cert.crt" "$HOME/agsbx/cert/cert.crt" 2>/dev/null || true
    [ -s "$HOME/agsbx/cert/private.key" ] || { [ -s "$HOME/argosbx/cert/private.key" ] && cp -P "$HOME/argosbx/cert/private.key" "$HOME/agsbx/cert/private.key" 2>/dev/null || true; }
    if [ -x "$HOME/.acme.sh/acme.sh" ] && [ -n "$ym" ]; then
      "$HOME/.acme.sh/acme.sh" --install-cert -d "$ym" --key-file "$HOME/agsbx/cert/private.key" --fullchain-file "$HOME/agsbx/cert/cert.crt" --reloadcmd "bash $HOME/bin/agsbx certrestart" >/dev/null 2>&1 || true
    fi
  fi
  if [ -s "$HOME/agsbx/cert.crt" ] && [ ! -s "$HOME/agsbx/selfsigned/cert.crt" ]; then
    mkdir -p "$HOME/agsbx/selfsigned" 2>/dev/null || true
    cp -P "$HOME/agsbx/cert.crt" "$HOME/agsbx/selfsigned/cert.crt" 2>/dev/null || true
    [ -s "$HOME/agsbx/private.key" ] && cp -P "$HOME/agsbx/private.key" "$HOME/agsbx/selfsigned/private.key" 2>/dev/null || true
  fi
  if [ -s "$HOME/argosbx/Caddyfile" ] && [ ! -s "$HOME/agsbx/Caddyfile" ]; then
    cp "$HOME/argosbx/Caddyfile" "$HOME/agsbx/Caddyfile" 2>/dev/null || true
  fi
}
export certmode=${certmode:-''}
export certsrc=${certsrc:-''}
# certsrc：证书来源，空=自动，caddy=Caddy，acme=acme.sh。
# 自动逻辑：显式选择优先；否则总内存小于 256MB 时优先 acme（低内存机器不常驻 Caddy）；否则有 caddy 命令时用 Caddy，否则用 acme。
# acme 分支不自动安装 acme.sh，需预先安装在 $HOME/.acme.sh/acme.sh，否则等待超时后回落自签。
detect_certsrc(){
  if [ "$certsrc" = "caddy" ]; then echo "caddy"; return; fi
  if [ "$certsrc" = "acme" ]; then echo "acme"; return; fi
  local mem_kb=""
  mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null)
  if [ -n "$mem_kb" ] && [ "$mem_kb" -lt 262144 ]; then echo "acme"; return; fi
  if command -v caddy >/dev/null 2>&1; then echo "caddy"; return; fi
  echo "acme"
}
# certmode：证书验证方式，空=自动，http=强制 HTTP，dns=强制 DNS。
# 自动逻辑：显式选择优先；否则 Argo 开启时按已代理处理；否则查 ym 的 DNS，若解析 IP 已知且不等于本机 IP 则按已代理处理，否则 HTTP。
# 注意：本机 IP 以 $HOME/agsbx/server_ip.log 为准，若该文件不存在则不做 DNS 对比，避免误判为已代理。
detect_certmode(){
  if [ "$certmode" = "http" ]; then echo "http"; return; fi
  if [ "$certmode" = "dns" ]; then echo "dns"; return; fi
  if [ -n "$argo" ] || [ -n "$agn" ]; then echo "dns"; return; fi
  local dns_ip="" srv_ip=""
  srv_ip=$(cat "$HOME/agsbx/server_ip.log" 2>/dev/null | tr -d " \t\r\n")
  if [ -n "$srv_ip" ]; then
    dns_ip=$(getent hosts "$ym" 2>/dev/null | awk '{print $1}' | head -n1)
    if [ -z "$dns_ip" ] && command -v dig >/dev/null 2>&1; then dns_ip=$(dig +short "$ym" A 2>/dev/null | head -n1); fi
    if [ -n "$dns_ip" ] && [ "$dns_ip" != "$srv_ip" ]; then echo "dns"; return; fi
  fi
  echo "http"
}
# write_caddyfile：按验证方式写 Caddyfile。优先写系统位置 /etc/caddy/argosbx.caddyfile，并让主配置 import 它（先备份主配置，已有 import 行则不重复加）；无 root / /etc/caddy 不可写时回落到 $HOME/agsbx/Caddyfile（单个文件，不另建目录）。
# 本函数只写配置，不安装 Caddy；是否启动/重载由调用方尽力尝试，失败不中断后续等待与回落。生成路径保存在全局变量 caddyfile_path 和 $HOME/agsbx/caddyfile_path。
write_caddyfile(){
  local conf_file=""
  caddyfile_path=""
  if [ "$(id -u 2>/dev/null)" = "0" ]; then
    mkdir -p /etc/caddy 2>/dev/null || true
    if [ -w /etc/caddy ]; then
      conf_file="/etc/caddy/argosbx.caddyfile"
      if [ -f /etc/caddy/Caddyfile ]; then
        if ! grep -q "argosbx.caddyfile" /etc/caddy/Caddyfile 2>/dev/null; then
          cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
          printf "\nimport argosbx.caddyfile\n" >> /etc/caddy/Caddyfile
        fi
      else
        printf "import argosbx.caddyfile\n" > /etc/caddy/Caddyfile
      fi
    fi
  fi
  if [ -z "$conf_file" ]; then
    mkdir -p "$HOME/agsbx"
    conf_file="$HOME/agsbx/Caddyfile"
  fi
  if [ "$certmode_selected" = "dns" ]; then
    printf "%s {\n  tls {\n    dns cloudflare {env.CLOUDFLARE_API_TOKEN}\n  }\n  respond \"ok\"\n}\n" "$ym" > "$conf_file"
  else
    printf "%s {\n  respond \"ok\"\n}\n" "$ym" > "$conf_file"
  fi
  chmod 644 "$conf_file" 2>/dev/null || true
  caddyfile_path="$conf_file"
  echo "$conf_file" > "$HOME/agsbx/caddyfile_path" 2>/dev/null || true
  echo "Caddyfile 已生成：$conf_file（验证方式：$certmode_selected）"
}

# ensure_acme：acme.sh 不存在时自动安装（官方安装脚本，装到 $HOME/.acme.sh，写续期 cron）。不自动安装则返回 1，调用方继续等待、超时回落自签，不中断主脚本。
ensure_acme(){
  [ -x "$HOME/.acme.sh/acme.sh" ] && return 0
  local tmpdir=""
  tmpdir=$(mktemp -d 2>/dev/null) || return 1
  if ! curl -fsSL https://get.acme.sh -o "$tmpdir/acme-install.sh" 2>/dev/null; then rm -rf "$tmpdir"; echo "acme.sh 安装脚本下载失败"; return 1; fi
  if ! sh "$tmpdir/acme-install.sh" >/dev/null 2>&1; then rm -rf "$tmpdir"; echo "acme.sh 安装失败"; return 1; fi
  rm -rf "$tmpdir"
  [ -x "$HOME/.acme.sh/acme.sh" ] || { echo "acme.sh 安装后仍未找到可执行文件"; return 1; }
  echo "acme.sh 已自动安装：$HOME/.acme.sh/acme.sh"
  return 0
}
# ensure_caddy_download：Caddy 不存在时下载用户预编译版（Coraza + Cloudflare），非交互、带备份与校验，失败返回 1 不中断主脚本。
# 配置来源（优先级）：密码文件 /etc/caddy/.files_auth_pass（已确认路径，600 权限），否则环境变量 CADDY_DOWNLOAD_PASS；URL 默认 https://files.quinn.de5.net/，可用 CADDY_DOWNLOAD_URL 覆盖；用户名默认 tom，可用 CADDY_DOWNLOAD_USER 覆盖。
# 不再先装官方版再覆盖；只在需要时停掉已有服务，验过新二进制（版本 + Cloudflare + Coraza 模块）才替换，验不过用备份恢复。
ensure_caddy_download(){
  [ "$(id -u 2>/dev/null)" = "0" ] || { echo "下载 Caddy 需要 root 权限（写 /usr/bin 与 /etc/caddy）"; return 1; }
  local base_url="${CADDY_DOWNLOAD_URL:-https://files.quinn.de5.net/}"
  local web_user="${CADDY_DOWNLOAD_USER:-tom}"
  local pass_file="/etc/caddy/.files_auth_pass"
  local web_pass=""
  mkdir -p /etc/caddy 2>/dev/null || true
  if [ -s "$pass_file" ]; then web_pass=$(cat "$pass_file"); elif [ -n "$CADDY_DOWNLOAD_PASS" ]; then web_pass="$CADDY_DOWNLOAD_PASS"; else echo "Caddy 预编译下载缺少密码：请先将密码写入 $pass_file（600 权限）或设置 CADDY_DOWNLOAD_PASS"; return 1; fi
  local caddy_bin=""
  case "$cpu" in amd64) caddy_bin="caddy_x86_64";; arm64) caddy_bin="caddy_arm";; *) echo "不支持的架构：$cpu"; return 1;; esac
  [[ "$base_url" != */ ]] && base_url="${base_url}/"
  local final_url="${base_url}caddy/${caddy_bin}"
  local tmpdir="" netrc=""
  tmpdir=$(mktemp -d 2>/dev/null) || return 1
  netrc="$tmpdir/netrc"
  printf "machine %s\nlogin %s\npassword %s\n" "$(printf "%s" "$final_url" | awk -F/ '{print $3}')" "$web_user" "$web_pass" > "$netrc"
  chmod 600 "$netrc"
  echo "正在拉取预编译 Caddy：$final_url"
  if ! curl --netrc-file "$netrc" -fL --retry 3 --connect-timeout 15 -o "$tmpdir/caddy" "$final_url" 2>/dev/null; then rm -rf "$tmpdir"; echo "Caddy 下载失败，请检查 URL、用户名、密码或网络"; return 1; fi
  rm -f "$netrc"
  chmod +x "$tmpdir/caddy"
  if ! "$tmpdir/caddy" version >/dev/null 2>&1; then rm -rf "$tmpdir"; echo "下载的 Caddy 无法运行（架构或文件损坏）"; return 1; fi
  if ! "$tmpdir/caddy" list-modules 2>/dev/null | grep -q "cloudflare"; then rm -rf "$tmpdir"; echo "下载的 Caddy 缺少 Cloudflare 模块，拒绝替换"; return 1; fi
  if ! "$tmpdir/caddy" list-modules 2>/dev/null | grep -q "coraza"; then rm -rf "$tmpdir"; echo "下载的 Caddy 缺少 Coraza 模块，拒绝替换"; return 1; fi
  if command -v systemctl >/dev/null 2>&1; then systemctl stop caddy 2>/dev/null || true; fi
  if [ -f /usr/bin/caddy ]; then cp /usr/bin/caddy /usr/bin/caddy.bak 2>/dev/null || true; fi
  if ! mv -f "$tmpdir/caddy" /usr/bin/caddy; then rm -rf "$tmpdir"; echo "替换 /usr/bin/caddy 失败"; return 1; fi
  chmod 755 /usr/bin/caddy 2>/dev/null || true
  setcap cap_net_bind_service=+ep /usr/bin/caddy 2>/dev/null || true
  if ! /usr/bin/caddy version >/dev/null 2>&1; then [ -f /usr/bin/caddy.bak ] && mv -f /usr/bin/caddy.bak /usr/bin/caddy; rm -rf "$tmpdir"; echo "新 Caddy 校验失败，已恢复备份"; return 1; fi
  rm -rf "$tmpdir"
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files caddy.service >/dev/null 2>&1; then systemctl start caddy 2>/dev/null || echo "Caddy 服务启动失败，请手动检查 systemctl status caddy"; fi
  echo "预编译 Caddy 下载并替换成功"
  return 0
}
# 域名证书：固定目录 $HOME/agsbx/cert（Caddy 时内为指向 Caddy 证书存储的软链接，acme 时直接安装到该目录）。
# wait_domain_cert：等待最长 300 秒，每 15 秒检查一次；校验两文件存在且非空、非断链、证书可解析且域名匹配 ym。返回 0=就绪，1=未就绪（调用方超时回落自签）。
wait_domain_cert(){
  [ -n "$ym" ] || return 1
  local waited=0 cert_text=""
  while [ "$waited" -lt 300 ]; do
    if [ -s "$CERT_CRT" ] && [ -s "$CERT_KEY" ] && [ -e "$CERT_CRT" ] && [ -e "$CERT_KEY" ]; then
      if command -v openssl >/dev/null 2>&1; then
        cert_text=$(openssl x509 -in "$CERT_CRT" -noout -subject -ext subjectAltName 2>/dev/null || openssl x509 -in "$CERT_CRT" -noout -subject 2>/dev/null)
        case "$cert_text" in *"$ym"*) echo "域名证书已就绪：$ym（$CERT_DIR）"; return 0;; esac
      fi
    fi
    [ "$waited" -eq 0 ] && echo "等待域名证书就绪：$ym（最长 300 秒，每 15 秒检查一次，目录 $CERT_DIR）"
    sleep 15
    waited=$((waited + 15))
  done
  echo "域名证书超时未就绪：$ym，300 秒后回落自签证书"
  return 1
}
