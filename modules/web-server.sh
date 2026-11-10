# web-server.sh: ensure a web server listens on 443 when ym (own domain) is set.
# Background: ym enables Reality camouflage with fallback to 127.0.0.1:443.
# If neither Caddy nor nginx listens on 443, the camouflage is broken.
# This module auto-installs nginx (lightweight, suitable for low-memory
# machines where the user chose acme.sh to avoid Caddy) AND configures
# the vhost to serve the camouflage blog.

# ensure_web_proxy_backend: 启动本机 127.0.0.1 伪装站服务，自动分配未占用随机端口
# 供 Caddy / Nginx 反代调用，无需外部 UFW 放行，无需用户在页面填写
ensure_web_proxy_backend(){
  local webroot="${1:-/var/www/html}"
  mkdir -p "$webroot" 2>/dev/null || true
  if [ ! -f "$webroot/index.html" ]; then
    echo "<h1>Welcome</h1>" > "$webroot/index.html" 2>/dev/null || true
  fi

  local port=""
  if command -v port_resolve >/dev/null 2>&1; then
    port=$(port_resolve "webproxy" "")
  fi
  if [ -z "$port" ] || case "$port" in *[!0-9]*) true;; *) false;; esac; then
    local candidate
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      candidate=$(shuf -i 10000-65535 -n 1 2>/dev/null || echo "$(( (RANDOM % 55535) + 10000 ))")
      if ! ss -tln 2>/dev/null | grep -qE ":${candidate}\s" && ! netstat -tln 2>/dev/null | grep -qE ":${candidate}\s"; then
        port="$candidate"
        break
      fi
    done
    port="${port:-18088}"
    if command -v port_set >/dev/null 2>&1; then
      port_set "webproxy" "$port"
    fi
  fi

  local is_listening=0
  if command -v ss >/dev/null 2>&1; then
    ss -tln 2>/dev/null | grep -qE "127\.0\.0\.1:${port}\s" && is_listening=1
  elif command -v netstat >/dev/null 2>&1; then
    netstat -tln 2>/dev/null | grep -qE "127\.0\.0\.1:${port}\s" && is_listening=1
  fi

  if [ "$is_listening" -eq 0 ]; then
    if command -v busybox >/dev/null 2>&1; then
      busybox httpd -p "127.0.0.1:${port}" -h "$webroot" >/dev/null 2>&1 || \
      busybox httpd -f -p "127.0.0.1:${port}" -h "$webroot" >/dev/null 2>&1 &
    elif command -v busybox-extras >/dev/null 2>&1; then
      busybox-extras httpd -p "127.0.0.1:${port}" -h "$webroot" >/dev/null 2>&1 || \
      busybox-extras httpd -f -p "127.0.0.1:${port}" -h "$webroot" >/dev/null 2>&1 &
    elif command -v python3 >/dev/null 2>&1; then
      nohup python3 -m http.server "$port" --bind 127.0.0.1 --directory "$webroot" >/dev/null 2>&1 &
    fi

    if command -v crontab >/dev/null 2>&1; then
      local crontmp
      crontmp=$(mktemp 2>/dev/null || echo "/tmp/crontab.webproxy.$$")
      crontab -l 2>/dev/null | grep -v "webproxy" > "$crontmp" || true
      echo '@reboot sleep 8 && /bin/bash -c "if command -v busybox >/dev/null 2>&1; then busybox httpd -p 127.0.0.1:'"$port"' -h '"$webroot"' >/dev/null 2>&1; elif command -v python3 >/dev/null 2>&1; then nohup python3 -m http.server '"$port"' --bind 127.0.0.1 --directory '"$webroot"' >/dev/null 2>&1 &; fi" # webproxy' >> "$crontmp"
      crontab "$crontmp" 2>/dev/null || true
      rm -f "$crontmp"
    fi
  fi

  echo "127.0.0.1:${port}"
}

# ensure_web_server: called when ym is non-empty and camouflage is active.
# Web server choice follows detect_certsrc(): caddy path -> ensure Caddy,
# acme path (low memory) -> install nginx.
# Returns 0 if 443 has a listener (or was successfully set up), 1 otherwise.
ensure_web_server(){
  local ym_c="$1" src=""
  [ -n "$ym_c" ] || return 0
  # 443 已有监听？（Caddy、nginx 或其他）直接返回
  if command -v ss >/dev/null 2>&1; then
    if ss -tlnp 2>/dev/null | grep -qE ':443\s'; then
      return 0
    fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -tlnp 2>/dev/null | grep -qE ':443\s'; then
      return 0
    fi
  fi
  # 按内存决策装哪个（跟 certsrc 的 auto 逻辑一致：低内存->acme->nginx，否则->caddy）
  # 注意：不用 detect_certsrc，因为它在 Caddy 未安装时会被误判为 acme
  local mem_kb=""
  mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null)
  # 显式指定 certsrc 时优先
  if [ "${certsrc:-}" = "caddy" ]; then
    src="caddy"
  elif [ "${certsrc:-}" = "acme" ]; then
    src="acme"
  elif [ -n "$mem_kb" ] && [ "$mem_kb" -lt 262144 ]; then
    src="acme"
  else
    src="caddy"
  fi
  if [ "$src" = "caddy" ]; then
    # Caddy 路径：证书阶段会调用 ensure_caddy_download 并写 Caddyfile，
    # 这里只需确认走 Caddy 路径，不提前下载（避免函数定义顺序问题）
    return 0
  fi
  # acme 路径（低内存）：优先调用 nginx_proxy.sh 进行环境初始化与站点/反代发布
  local nginx_proxy_bin="$HOME/.local/bin/nginx_proxy.sh"
  ensure_proxy_script "nginx_proxy.sh" || true
  if [ -x "$nginx_proxy_bin" ]; then
    local force_flag=""
    force_flag=$(check_and_prompt_force_email "$nginx_proxy_bin" "$caddy_email")
    "$nginx_proxy_bin" init ${caddy_email:+--email "$caddy_email"} $force_flag || true

    _webroot="${webroot:-/var/www/html}"
    if [ "$camouflage" = "1" ] || { [ -z "$camouflage" ] && [ ! -f "$_webroot/index.html" ]; }; then
      if command -v deploy_camouflage_blog >/dev/null 2>&1; then
        deploy_camouflage_blog "$_webroot" || echo "伪装博客部署失败，请手动检查 $_webroot"
      fi
    fi

    # 自动生成 127.0.0.1 未占用随机端口作为反代后端，无需页面手动填写，亦无需 UFW 放行
    local proxy_target="${web_proxy:-}"
    if [ -z "$proxy_target" ]; then
      proxy_target=$(ensure_web_proxy_backend "$_webroot")
    fi

    if [ -n "$proxy_target" ]; then
      "$nginx_proxy_bin" site --domain "$ym_c" --proxy "$proxy_target" ${caddy_email:+--email "$caddy_email"} $force_flag --force || true
    else
      "$nginx_proxy_bin" site --domain "$ym_c" --root "$_webroot" ${caddy_email:+--email "$caddy_email"} $force_flag --force || true
    fi

    if [ -f "/etc/nginx/certs/${ym_c}/fullchain.crt" ] && [ -f "/etc/nginx/certs/${ym_c}/private.key" ]; then
      mkdir -p "$CERT_DIR" 2>/dev/null || true
      cp -f "/etc/nginx/certs/${ym_c}/fullchain.crt" "$CERT_CRT" 2>/dev/null || true
      cp -f "/etc/nginx/certs/${ym_c}/private.key" "$CERT_KEY" 2>/dev/null || true
      chmod 600 "$CERT_KEY" 2>/dev/null || true
    fi
    return 0
  fi

  # nginx 已安装？写 vhost 并返回
  if command -v nginx >/dev/null 2>&1; then
    _webserver_write_nginx_conf "$ym_c" || true
    return 0
  fi
  # 都没有，尝试自动安装 nginx（轻量）
  echo "检测到 443 无 Web 服务监听（伪装博客需要），尝试自动安装 nginx..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq nginx >/dev/null 2>&1
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q nginx >/dev/null 2>&1
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache nginx >/dev/null 2>&1
  else
    echo "未找到包管理器，无法自动安装 nginx。请手动安装 nginx 或 Caddy，否则 443 伪装不生效。"
    return 1
  fi
  if command -v nginx >/dev/null 2>&1; then
    echo "nginx 安装成功，正在配置 vhost..."
    _webserver_write_nginx_conf "$ym_c" || true
    return 0
  else
    echo "nginx 自动安装失败。请手动安装 nginx 或 Caddy，否则 443 伪装不生效。"
    return 1
  fi
}

# _webserver_write_nginx_conf <ym>: 写 nginx vhost，root 指向 webroot（伪装博客目录）
_webserver_write_nginx_conf(){
  local ym_c="$1" _webroot="" _conf="" _cert="" _key=""
  [ -n "$ym_c" ] || return 1
  _webroot="${webroot:-/var/www/html}"
  _cert="$HOME/agsbx/cert/cert.crt"
  _key="$HOME/agsbx/cert/private.key"
  # 证书不存在？用自签占位（nginx 需要 cert 才能起 443）
  if [ ! -s "$_cert" ] || [ ! -s "$_key" ]; then
    echo "警告：$ym_c 的证书尚未就绪，nginx 443 暂用自签占位，证书就绪后需重载"
    _cert="$HOME/agsbx/selfsigned/cert.crt"
    _key="$HOME/agsbx/selfsigned/private.key"
    [ -s "$_cert" ] || return 1
  fi
  # 确定 conf 位置
  if [ -d /etc/nginx/conf.d ]; then
    _conf="/etc/nginx/conf.d/argosbx.conf"
  elif [ -d /etc/nginx/sites-enabled ]; then
    _conf="/etc/nginx/sites-enabled/argosbx"
  else
    echo "未找到 nginx conf 目录，跳过自动配置"
    return 1
  fi
  {
    echo "# argosbx auto-generated for $ym_c (camouflage blog)"
    echo "server {"
    echo "  listen 80;"
    echo "  server_name $ym_c;"
    echo "  location ^~ /.well-known/acme-challenge/ { root $_webroot; }"
    echo "  location / { return 301 https://\$host\$request_uri; }"
    echo "}"
    echo "server {"
    echo "  listen 443 ssl;"
    echo "  server_name $ym_c;"
    echo "  ssl_certificate $_cert;"
    echo "  ssl_certificate_key $_key;"
    echo "  root $_webroot;"
    echo "  index index.html;"
    # 订阅路径（https-manual 模式用）
    if [ -n "${token:-}" ]; then
      echo "  location ^~ /$token/ { root $HOME/websbx; }"
    fi
    echo "}"
  } > "$_conf" 2>/dev/null || { echo "写 nginx 配置失败：$_conf"; return 1; }
  nginx -t 2>/dev/null || { echo "nginx 配置测试失败，请检查 $_conf"; return 1; }
  if command -v systemctl >/dev/null 2>&1; then
    systemctl reload nginx 2>/dev/null || systemctl start nginx 2>/dev/null || true
  else
    nginx -s reload 2>/dev/null || nginx 2>/dev/null || true
  fi
  echo "nginx vhost 已配置：$_conf（root=$_webroot）"
  return 0
}
