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
      "$HOME/.acme.sh/acme.sh" --install-cert -d "$ym" --key-file "$HOME/agsbx/cert/private.key" --fullchain-file "$HOME/agsbx/cert/cert.crt" --reloadcmd "bash $HOME/.local/bin/agsbx certrestart" >/dev/null 2>&1 || true
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

# cert_setup_caddy_proxy: Initialize Caddy environment and configure primary domain site via caddy_proxy.sh.
# Returns 0 on success; returns 1 on script missing or execution failure (fail loudly, no legacy bypass).
cert_setup_caddy_proxy(){
  local ym="$1"
  local certmode="$2"
  local email="$3"
  local webroot_dir="${4:-/var/www/html}"
  local camouflage_flag="$5"
  local proxy_backend="$6"

  local caddy_proxy_bin="$HOME/.local/bin/caddy_proxy.sh"
  ensure_proxy_script "caddy_proxy.sh" || true

  if [ ! -x "$caddy_proxy_bin" ]; then
    echo "错误：未找到可执行脚本 $caddy_proxy_bin，无法配置 Caddy（所有 Caddy 配置必须由 caddy_proxy.sh 托管）。" >&2
    return 1
  fi

  local force_flag=""
  force_flag=$(check_and_prompt_force_email "$caddy_proxy_bin" "$email")
  if ! "$caddy_proxy_bin" init ${email:+--email "$email"} $force_flag; then
    echo "错误：caddy_proxy.sh init 执行失败。" >&2
    return 1
  fi

  # Determine site mode:
  # 1. web_proxy starts with '/' -> user's local static root
  # 2. web_proxy non-empty       -> user's reverse proxy backend
  # 3. should_deploy_camouflage_blog -> deploy camouflage blog & serve webroot_dir
  # 4. otherwise                 -> --no-default (404 fallback, no /var/www/html mapping)
  local site_mode="no-default"
  local site_target=""
  if [[ "$proxy_backend" == /* ]]; then
    site_mode="root"
    site_target="$proxy_backend"
  elif [ -n "$proxy_backend" ]; then
    site_mode="proxy"
    site_target="$proxy_backend"
  elif command -v should_deploy_camouflage_blog >/dev/null 2>&1 && camouflage="$camouflage_flag" web_proxy="$proxy_backend" should_deploy_camouflage_blog; then
    if [ "$camouflage_flag" = "1" ] || [ ! -f "$webroot_dir/index.html" ]; then
      if command -v deploy_camouflage_blog >/dev/null 2>&1; then
        camouflage="$camouflage_flag" web_proxy="$proxy_backend" deploy_camouflage_blog "$webroot_dir" || echo "伪装博客部署失败，请手动检查 $webroot_dir"
      fi
    fi
    site_mode="root"
    site_target="$webroot_dir"
  else
    if command -v deploy_camouflage_blog >/dev/null 2>&1; then
      # Emit clear skip reason without writing files
      camouflage="$camouflage_flag" web_proxy="$proxy_backend" deploy_camouflage_blog "$webroot_dir" >/dev/null 2>&1 || true
    fi
    echo "站点默认路由：未触发伪装博客条件且未设置 web_proxy，${ym} 仅启用 --no-default（根路径返回 404，不映射 /var/www/html）"
    site_mode="no-default"
  fi

  local dns_arg=""
  [ "$certmode" = "dns" ] && dns_arg="--dns cloudflare"

  local site_rc=0
  if [ "$site_mode" = "proxy" ]; then
    "$caddy_proxy_bin" site --domain "$ym" --proxy "$site_target" ${email:+--email "$email"} $force_flag $dns_arg --force || site_rc=$?
  elif [ "$site_mode" = "root" ]; then
    "$caddy_proxy_bin" site --domain "$ym" --root "$site_target" ${email:+--email "$email"} $force_flag $dns_arg --force || site_rc=$?
  else
    "$caddy_proxy_bin" site --domain "$ym" --no-default ${email:+--email "$email"} $force_flag $dns_arg --force || site_rc=$?
  fi
  if [ "$site_rc" != "0" ]; then
    echo "错误：caddy_proxy.sh site 配置域名 ${ym} 失败。" >&2
    return 1
  fi

  caddyfile_path="/etc/caddy/Caddyfile"
  echo "$caddyfile_path" > "$HOME/agsbx/caddyfile_path" 2>/dev/null || true
  return 0
}

export certmode=${certmode:-''}
export certsrc=${certsrc:-''}
# certsrc：证书来源，空=自动，caddy=Caddy，acme=acme.sh。
# 自动逻辑：显式选择优先；否则总内存小于 256MB 时用 acme（低内存机器不常驻 Caddy）；否则用 Caddy（未安装时自动下载）。
# acme 分支不自动安装 acme.sh，需预先安装在 $HOME/.acme.sh/acme.sh，否则等待超时后回落自签。
detect_certsrc(){
  if [ "$certsrc" = "caddy" ]; then echo "caddy"; return; fi
  if [ "$certsrc" = "acme" ]; then echo "acme"; return; fi
  local mem_kb=""
  mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null)
  # 低内存（<256MB）走 acme.sh；其他情况走 Caddy（未安装时后面会自动下载）
  if [ -n "$mem_kb" ] && [ "$mem_kb" -lt 262144 ]; then echo "acme"; return; fi
  echo "caddy"
}
# certmode：证书验证方式，空=自动，http=强制 HTTP，dns=强制 DNS。
# 自动逻辑：显式选择优先；否则 Argo 开启时按已代理处理；否则查 ym 的 DNS，若解析 IP 已知且不等于本机 IP 则按已代理处理，否则 HTTP。
# 注意：本机 IP 以 $HOME/agsbx/server_ip.log 为准，若该文件不存在则不做 DNS 对比，避免误判为已代理。
detect_certmode(){
  if [ "$certmode" = "webroot" ]; then echo "webroot"; return; fi
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
# prompt_cf_token：DNS 验证需要 Cloudflare API Token。已设置则直接用；
# 未设置且是交互终端则提示输入（不回显），存到 $HOME/agsbx/cf_token.env（600）并 export。
# 返回 0 表示有 token 可用，1 表示没有。
prompt_cf_token(){
  if [ -n "$CLOUDFLARE_API_TOKEN" ] || [ -n "$CF_API_TOKEN" ]; then return 0; fi
  # 尝试从保存的文件恢复
  if [ -f "$HOME/agsbx/cf_token.env" ]; then
    # shellcheck disable=SC1090
    . "$HOME/agsbx/cf_token.env" 2>/dev/null
    if [ -n "$CLOUDFLARE_API_TOKEN" ] || [ -n "$CF_API_TOKEN" ]; then return 0; fi
  fi
  # 非交互终端无法提示
  if [ ! -t 0 ] && [ ! -r /dev/tty ]; then return 1; fi
  printf "请输入 Cloudflare API Token（输入时不显示，DNS 验证需要）: " > /dev/tty 2>/dev/null || printf "请输入 Cloudflare API Token（输入时不显示，DNS 验证需要）: "
  local _cft=""
  if [ -r /dev/tty ]; then
    read -s _cft < /dev/tty
    echo > /dev/tty 2>/dev/null || echo
  else
    read -s _cft
    echo
  fi
  if [ -n "$_cft" ]; then
    export CLOUDFLARE_API_TOKEN="$_cft"
    mkdir -p "$HOME/agsbx" 2>/dev/null || true
    printf 'export CLOUDFLARE_API_TOKEN=%q\n' "$_cft" > "$HOME/agsbx/cf_token.env" 2>/dev/null || true
    chmod 600 "$HOME/agsbx/cf_token.env" 2>/dev/null || true
  fi
  unset _cft
  [ -n "$CLOUDFLARE_API_TOKEN" ] || [ -n "$CF_API_TOKEN" ]
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
# 域名证书：固定目录 $HOME/agsbx/cert（Caddy 时由 caddy_fetch_cert 从 Caddy 证书存储同步，acme 时直接安装到该目录）。
# domain_cert_valid：检查是否已有 $ym 的有效证书（两文件存在非空、可解析、域名匹配、剩余有效期 >7 天）。
# 有则返回 0，调用方跳过 --issue 直接复用，避免"已有证书还报发证失败"的误导。
domain_cert_valid(){
  [ -n "$ym" ] || return 1
  [ -s "$CERT_CRT" ] && [ -s "$CERT_KEY" ] || return 1
  command -v openssl >/dev/null 2>&1 || return 1
  local cert_text=""
  cert_text=$(openssl x509 -in "$CERT_CRT" -noout -subject -ext subjectAltName 2>/dev/null || openssl x509 -in "$CERT_CRT" -noout -subject 2>/dev/null) || return 1
  case "$cert_text" in *"$ym"*) ;; *) return 1;; esac
  openssl x509 -in "$CERT_CRT" -noout -checkend 604800 >/dev/null 2>&1 || return 1
  return 0
}
# caddy_fetch_cert：从 Caddy 证书存储中找到 $ym 的证书并同步到 $CERT_DIR，成功返回 0。
# 背景：Caddy 模式下证书由 Caddy 自己申请，存在它自己的存储里；代理内核用的是脚本
# 固定目录，需要一份拷贝。存储位置因 Caddy 运行用户而异，逐个尝试；CA 目录兼容
# Let's Encrypt 与 ZeroSSL（Caddy 会自动回落）。只同步可解析、域名匹配、剩余有效期
# >7 天的证书。CADDY_STORAGE_CANDIDATES 可覆盖候选目录（空格分隔，主要给测试用）。
caddy_fetch_cert(){
  local _ym="${ym:-$(cat "$HOME/agsbx/ym" 2>/dev/null)}"
  [ -n "$_ym" ] || return 1
  command -v openssl >/dev/null 2>&1 || return 1
  local dirs="${CADDY_STORAGE_CANDIDATES:-/var/lib/caddy/.local/share/caddy /root/.local/share/caddy $HOME/.local/share/caddy}"
  local s d f k cert_text
  for s in $dirs; do
    for d in acme-v02.api.letsencrypt.org-directory acme.zerossl.com-v2-DV90; do
      f="$s/certificates/$d/$_ym/$_ym.crt"; k="$s/certificates/$d/$_ym/$_ym.key"
      [ -s "$f" ] && [ -s "$k" ] || continue
      cert_text=$(openssl x509 -in "$f" -noout -subject -ext subjectAltName 2>/dev/null || openssl x509 -in "$f" -noout -subject 2>/dev/null) || continue
      case "$cert_text" in *"$_ym"*) ;; *) continue;; esac
      openssl x509 -in "$f" -noout -checkend 604800 2>/dev/null || continue
      mkdir -p "$CERT_DIR" 2>/dev/null || return 1
      cp -f "$f" "$CERT_CRT" && cp -f "$k" "$CERT_KEY" && chmod 600 "$CERT_KEY" 2>/dev/null || continue
      return 0
    done
  done
  return 1
}
# wait_domain_cert：等待最长 300 秒，每 15 秒检查一次；校验两文件存在且非空、非断链、证书可解析且域名匹配 ym。返回 0=就绪，1=未就绪（调用方超时回落自签）。
wait_domain_cert(){
  [ -n "$ym" ] || return 1
  local waited=0 cert_text=""
  while [ "$waited" -lt 300 ]; do
    # Caddy 模式：证书在 Caddy 自己的存储里，先同步到固定目录再检查（acme 模式由 --install-cert 直接写入，无需同步）
    if [ "${certsrc_selected:-}" = "caddy" ]; then caddy_fetch_cert 2>/dev/null || true; fi
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
