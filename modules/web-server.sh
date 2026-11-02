# web-server.sh: ensure a web server listens on 443 when ym (own domain) is set.
# Background: ym enables Reality camouflage with fallback to 127.0.0.1:443.
# If neither Caddy nor nginx listens on 443, the camouflage is broken.
# This module auto-installs nginx (lightweight, suitable for low-memory
# machines where the user chose acme.sh to avoid Caddy).

# ensure_web_server: called when ym is non-empty and camouflage is active.
# Returns 0 if 443 has a listener (or was successfully set up), 1 otherwise.
ensure_web_server(){
  local ym_c="$1"
  [ -n "$ym_c" ] || return 0
  # 443 已有监听？（Caddy、nginx 或其他）
  if command -v ss >/dev/null 2>&1; then
    if ss -tlnp 2>/dev/null | grep -qE ':443\s'; then
      return 0
    fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -tlnp 2>/dev/null | grep -qE ':443\s'; then
      return 0
    fi
  fi
  # Caddy 可用？（用户可能手动装了）
  if command -v caddy >/dev/null 2>&1; then
    # Caddy 已安装但未监听 443，尝试启动（write_caddyfile 已写好配置）
    return 0
  fi
  # nginx 可用？
  if command -v nginx >/dev/null 2>&1; then
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
    echo "nginx 安装成功"
    return 0
  else
    echo "nginx 自动安装失败。请手动安装 nginx 或 Caddy，否则 443 伪装不生效。"
    return 1
  fi
}
