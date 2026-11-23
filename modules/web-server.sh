# web-server.sh: ensure a managed Web server (Nginx via nginx_proxy.sh) is configured when ym is set
# under the acme/low-memory path. Caddy path is handled by cert_setup_caddy_proxy() in cert-main.sh.
# All Nginx installation and vhost configuration are strictly delegated to nginx_proxy.sh.

ensure_web_server(){
  local ym_c="$1" src=""
  [ -n "$ym_c" ] || return 0

  # Select engine consistent with detect_certsrc() (low memory < 256MB -> acme/nginx, otherwise caddy)
  local mem_kb=""
  mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null)
  if [ "${certsrc:-}" = "caddy" ]; then
    src="caddy"
  elif [ "${certsrc:-}" = "acme" ] || [ "${certsrc:-}" = "nginx" ]; then
    src="acme"
  elif [ -n "$mem_kb" ] && [ "$mem_kb" -lt 262144 ]; then
    src="acme"
  else
    src="caddy"
  fi
  if [ "$src" = "caddy" ]; then
    # Caddy path is configured via cert_setup_caddy_proxy() in cert-main.sh
    return 0
  fi

  # Nginx path: strictly delegate to nginx_proxy.sh (no direct apt/yum/apk or manual vhost bypass)
  local nginx_proxy_bin="$HOME/.local/bin/nginx_proxy.sh"
  ensure_proxy_script "nginx_proxy.sh" || true
  if [ ! -x "$nginx_proxy_bin" ]; then
    echo "错误：未找到可执行脚本 $nginx_proxy_bin，无法配置 Nginx（所有 Nginx 配置必须由 nginx_proxy.sh 托管）。" >&2
    return 1
  fi

  local force_flag=""
  force_flag=$(check_and_prompt_force_email "$nginx_proxy_bin" "$caddy_email")
  if ! "$nginx_proxy_bin" init ${caddy_email:+--email "$caddy_email"} $force_flag; then
    echo "错误：nginx_proxy.sh init 执行失败。" >&2
    return 1
  fi

  local _webroot="${webroot:-/var/www/html}"
  local proxy_target="${web_proxy:-}"
  local site_mode="no-default"
  local site_target=""
  if [[ "$proxy_target" == /* ]]; then
    site_mode="root"
    site_target="$proxy_target"
  elif [ -n "$proxy_target" ]; then
    site_mode="proxy"
    site_target="$proxy_target"
  elif command -v should_deploy_camouflage_blog >/dev/null 2>&1 && should_deploy_camouflage_blog; then
    if [ "${camouflage:-}" = "1" ] || [ ! -f "$_webroot/index.html" ]; then
      if command -v deploy_camouflage_blog >/dev/null 2>&1; then
        deploy_camouflage_blog "$_webroot" || echo "伪装博客部署失败，请手动检查 $_webroot"
      fi
    fi
    site_mode="root"
    site_target="$_webroot"
  else
    echo "站点默认路由：未触发伪装博客条件且未设置 web_proxy，${ym_c} 仅启用 --no-default（根路径返回 404，不映射 /var/www/html）"
    site_mode="no-default"
  fi

  local dns_arg=""
  local cm=""
  cm="${certmode_selected:-${certmode:-}}"
  [ -z "$cm" ] && [ -f "$HOME/agsbx/certmode" ] && cm=$(cat "$HOME/agsbx/certmode" 2>/dev/null | tr -d '[:space:]')
  [ "$cm" = "dns" ] && dns_arg="--dns cloudflare"

  local site_rc=0
  if [ "$site_mode" = "proxy" ]; then
    "$nginx_proxy_bin" site --domain "$ym_c" --proxy "$site_target" ${caddy_email:+--email "$caddy_email"} $force_flag $dns_arg --force || site_rc=$?
  elif [ "$site_mode" = "root" ]; then
    "$nginx_proxy_bin" site --domain "$ym_c" --root "$site_target" ${caddy_email:+--email "$caddy_email"} $force_flag $dns_arg --force || site_rc=$?
  else
    "$nginx_proxy_bin" site --domain "$ym_c" --no-default ${caddy_email:+--email "$caddy_email"} $force_flag $dns_arg --force || site_rc=$?
  fi
  if [ "$site_rc" != "0" ]; then
    echo "错误：nginx_proxy.sh site 配置域名 ${ym_c} 失败。" >&2
    return 1
  fi

  if [ -f "/etc/nginx/certs/${ym_c}/fullchain.crt" ] && [ -f "/etc/nginx/certs/${ym_c}/private.key" ]; then
    mkdir -p "$CERT_DIR" 2>/dev/null || true
    cp -f "/etc/nginx/certs/${ym_c}/fullchain.crt" "$CERT_CRT" 2>/dev/null || true
    cp -f "/etc/nginx/certs/${ym_c}/private.key" "$CERT_KEY" 2>/dev/null || true
    chmod 600 "$CERT_KEY" 2>/dev/null || true
  fi
  return 0
}
