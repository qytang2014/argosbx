# Cert renewal auto-restart: Caddy has no post-renewal hook, and acme.sh
# renewal alone does not restart sing-box/xray, so both paths are covered:
#  - acme: --install-cert --reloadcmd "bash $HOME/bin/agsbx certrestart"
#    runs immediately on acme renewal (see modules/cert-main.sh).
#  - Caddy (and as a backstop for acme): a daily cron entry
#    "bash $HOME/bin/agsbx certwatch" checks the cert hash in the fixed
#    dir and restarts only the kernels whose config uses that cert.
# Rules: hash is sha256 of the cert file (following symlinks); a change
# is acted on only if the new cert parses and, when a domain is known,
# matches that domain; an invalid cert never updates the recorded hash
# and never triggers a restart, so the next run retries instead of
# losing the change. Restart uses the existing sbrestart/xrestart
# functions, which handle systemd / OpenRC / nohup the same way the
# rest of the script does. If a kernel was stopped, sbrestart/xrestart
# will start it again; that is intentional on renewal.
cert_cert_hash(){ sha256sum "$CERT_CRT" 2>/dev/null | awk '{print $1}'; }
cert_uses_domain_cert(){
  { [ -f "$HOME/agsbx/sb.json" ] && grep -q 'argosbx/cert' "$HOME/agsbx/sb.json" 2>/dev/null; } || \
  { [ -f "$HOME/agsbx/xr.json" ] && grep -q 'argosbx/cert' "$HOME/agsbx/xr.json" 2>/dev/null; }
}
cert_restart(){
  cert_uses_domain_cert || { echo "域名证书未被 sing-box/xray 配置使用，跳过重启"; return 0; }
  if [ -f "$HOME/agsbx/sb.json" ] && grep -q 'argosbx/cert' "$HOME/agsbx/sb.json" 2>/dev/null; then
    echo "证书已更新，重启 sing-box"; sbrestart
  fi
  if [ -f "$HOME/agsbx/xr.json" ] && grep -q 'argosbx/cert' "$HOME/agsbx/xr.json" 2>/dev/null; then
    echo "证书已更新，重启 xray"; xrestart
  fi
}
cert_watch(){
  [ -s "$CERT_CRT" ] || return 0
  local ym_watch="" cur="" old="" cert_text=""
  ym_watch="${ym:-$(cat "$HOME/agsbx/ym" 2>/dev/null)}"
  cur=$(cert_cert_hash); [ -n "$cur" ] || return 0
  if [ ! -f "$HOME/agsbx/cert.hash" ]; then echo "$cur" > "$HOME/agsbx/cert.hash"; return 0; fi
  old=$(cat "$HOME/agsbx/cert.hash" 2>/dev/null)
  [ "$cur" != "$old" ] || return 0
  if command -v openssl >/dev/null 2>&1; then
    cert_text=$(openssl x509 -in "$CERT_CRT" -noout -subject -ext subjectAltName 2>/dev/null || openssl x509 -in "$CERT_CRT" -noout -subject 2>/dev/null)
    [ -n "$cert_text" ] || { echo "新证书无法解析，跳过重启，下次再试"; return 0; }
    if [ -n "$ym_watch" ]; then case "$cert_text" in *"$ym_watch"*) ;; *) echo "新证书域名不匹配 $ym_watch，跳过重启，下次再试"; return 0;; esac; fi
  fi
  echo "$cur" > "$HOME/agsbx/cert.hash"
  echo "域名证书已变化（$ym_watch），重启相关内核"
  cert_restart
}
cert_install_watch(){
  local cur="" tmp=""
  cur=$(cert_cert_hash); [ -n "$cur" ] && echo "$cur" > "$HOME/agsbx/cert.hash"
  command -v crontab >/dev/null 2>&1 || { echo "未找到 crontab，证书续期 watcher 未安装，acme 续期仍可通过 reloadcmd 重启"; return 0; }
  tmp=$(mktemp 2>/dev/null) || return 0
  crontab -l 2>/dev/null | grep -v 'argosbx-certwatch' > "$tmp" || true
  printf '0 3 * * * bash "$HOME/bin/agsbx" certwatch >/dev/null 2>&1  # argosbx-certwatch\n' >> "$tmp"
  crontab "$tmp" 2>/dev/null || echo "证书续期 watcher cron 安装失败，请手动添加：0 3 * * * bash \$HOME/bin/agsbx certwatch"
  rm -f "$tmp"
  echo "证书续期 watcher 已安装：每天 03:00 检查证书变化并重启相关内核"
}
cert_remove_watch(){
  command -v crontab >/dev/null 2>&1 || return 0
  local tmp=""; tmp=$(mktemp 2>/dev/null) || return 0
  crontab -l 2>/dev/null | grep -v 'argosbx-certwatch' > "$tmp" || true
  crontab "$tmp" 2>/dev/null || true
  rm -f "$tmp"
}
