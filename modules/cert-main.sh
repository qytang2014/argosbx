domain_cert_ready=0
if [ -n "$ym" ]; then
  mkdir -p "$CERT_DIR"
  echo "$ym" > "$HOME/agsbx/ym"
  certsrc_selected=$(detect_certsrc)
  certmode_selected=$(detect_certmode)
  echo "$certsrc_selected" > "$HOME/agsbx/certsrc"
  echo "$certmode_selected" > "$HOME/agsbx/certmode"
  if [ "$certsrc_selected" = "acme" ]; then
    echo "域名证书来源：acme.sh（验证方式：$certmode_selected，低内存机器不常驻 Caddy），固定目录 $CERT_DIR"
    ensure_acme || true
    if [ -x "$HOME/.acme.sh/acme.sh" ]; then
      if [ "$certmode_selected" = "dns" ]; then
        CF_Token="${CF_Token:-$CLOUDFLARE_API_TOKEN}" "$HOME/.acme.sh/acme.sh" --issue --dns dns_cf -d "$ym" >/dev/null 2>&1 || echo "acme.sh DNS 发证失败，脚本仍会继续等待证书，超时回落自签"
        "$HOME/.acme.sh/acme.sh" --install-cert -d "$ym" --key-file "$CERT_KEY" --fullchain-file "$CERT_CRT" >/dev/null 2>&1 || true
      else
        "$HOME/.acme.sh/acme.sh" --issue --standalone -d "$ym" >/dev/null 2>&1 || echo "acme.sh standalone 发证失败（需 80 端口空闲），脚本仍会继续等待证书，超时回落自签"
        "$HOME/.acme.sh/acme.sh" --install-cert -d "$ym" --key-file "$CERT_KEY" --fullchain-file "$CERT_CRT" >/dev/null 2>&1 || true
      fi
    else
      echo "未检测到 acme.sh（$HOME/.acme.sh/acme.sh），请先安装 acme.sh，脚本仍会继续等待证书，超时回落自签"
    fi
  else
    if [ "$certmode_selected" = "dns" ] && [ -z "$CLOUDFLARE_API_TOKEN" ] && [ -z "$CF_API_TOKEN" ]; then
      if [ "$certmode" = "dns" ]; then
        echo "已选 DNS 验证但未检测到 CLOUDFLARE_API_TOKEN 环境变量，仍按 DNS 写配置，Caddy 启动前请先设置该变量，否则等待超时后回落自签"
      else
        echo "自动判断为已代理、应走 DNS 验证，但未检测到 CLOUDFLARE_API_TOKEN 环境变量，回落 HTTP 验证试一次"
        certmode_selected="http"
      fi
    fi
    echo "$certmode_selected" > "$HOME/agsbx/certmode"
    echo "域名证书来源：Caddy（验证方式：$certmode_selected，Caddy 监听 80/443；DNS 时需 Cloudflare API），固定目录 $CERT_DIR"
    write_caddyfile
    if ! command -v caddy >/dev/null 2>&1; then
      ensure_caddy_download || echo "Caddy 预编译下载失败，脚本仍会继续等待证书，超时回落自签"
    fi
    if command -v caddy >/dev/null 2>&1; then
      if [ "$caddyfile_path" = "/etc/caddy/argosbx.caddyfile" ] && command -v systemctl >/dev/null 2>&1; then
        systemctl reload caddy >/dev/null 2>&1 || caddy reload --config "$caddyfile_path" --adapter caddyfile >/dev/null 2>&1 || echo "Caddy 未在运行或重载失败，请用系统服务启动 Caddy，脚本仍会继续等待证书"
      else
        caddy reload --config "$caddyfile_path" --adapter caddyfile >/dev/null 2>&1 || echo "Caddy 未在运行或重载失败，请用 $caddyfile_path 启动 Caddy，脚本仍会继续等待证书"
      fi
    else
      echo "未检测到 caddy 命令，脚本仍会继续等待证书，超时回落自签"
    fi
  fi
  if wait_domain_cert; then
    domain_cert_ready=1
  fi
elif [ -n "$alns" ]; then
  echo "已设置域名证书模式但未提供节点域名 ym，无法使用 Caddy 域名证书，回落自签证书"
fi
echo
if [ "$domain_cert_ready" = "1" ]; then
certificateHTA="$CERT_CRT"
keyHTA="$CERT_KEY"
echo "HY2/TUIC/Naive/Anytls/Xhttp-tls将使用 Caddy 域名证书的TLS"
