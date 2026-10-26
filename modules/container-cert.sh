# Container certificate selection (no Caddy, no systemd here).
# A container does NOT issue certificates: if a domain certificate has
# been placed at $HOME/argosbx/cert/cert.crt + private.key (typically
# mounted from the host, where host Caddy/acme issued and renews it),
# use it; otherwise fall back to a local self-signed pair as before.
# The old fallback that downloaded the original public private.key /
# cert.pem from the upstream release is REMOVED: that key is public,
# so using it as a private key is not private at all.
# On success (domain cert): symlinks $HOME/agsbx/cert.pem ->
# $HOME/agsbx/cert/cert.crt and private.key -> $HOME/agsbx/cert/private.key
# (symlinks, not copies, so a host renewal is followed on container
# restart), and writes $HOME/agsbx/domain_cert_ready = 1 plus
# $HOME/agsbx/ym. On fallback: generates a self-signed pair with
# openssl (CN www.bing.com), removes the flag file, and the display
# section keeps sni=www.bing.com with insecure=1.
# Call from installsb(), after insuuid, replacing the old cert block.
container_cert_setup() {
  if [ -n "$ym" ]; then echo "$ym" > "$HOME/agsbx/ym"; elif [ -s "$HOME/agsbx/ym" ]; then ym=$(cat "$HOME/agsbx/ym" 2>/dev/null); fi
  domain_cert_ready=0
  if [ -s "$HOME/agsbx/cert/cert.crt" ] && [ -s "$HOME/agsbx/cert/private.key" ] && command -v openssl >/dev/null 2>&1; then
    if openssl x509 -in "$HOME/agsbx/cert/cert.crt" -noout -checkend 0 >/dev/null 2>&1; then
      cert_domain=$(openssl x509 -in "$HOME/agsbx/cert/cert.crt" -noout -ext subjectAltName 2>/dev/null | tr ',' '\n' | grep -o 'DNS:[^,]*' | head -1 | cut -d: -f2)
      if [ -z "$cert_domain" ]; then cert_domain=$(openssl x509 -in "$HOME/agsbx/cert/cert.crt" -noout -subject 2>/dev/null | sed -n 's/.*CN *= *//p' | cut -d/ -f1 | tr -d ' '); fi
      if [ -z "$ym" ]; then
        ym="$cert_domain"; [ -n "$ym" ] && echo "$ym" > "$HOME/agsbx/ym"
        domain_cert_ready=1
      elif [ "$cert_domain" = "$ym" ]; then
        domain_cert_ready=1
      else
        echo "警告：$HOME/agsbx/cert/ 证书域名 [$cert_domain] 与节点域名 [$ym] 不一致，已回落自签证书"
      fi
    else
      echo "警告：$HOME/agsbx/cert/cert.crt 无法解析或已过期，已回落自签证书"
    fi
  fi
  if [ "$domain_cert_ready" = "1" ]; then
    echo "1" > "$HOME/agsbx/domain_cert_ready"
    rm -f "$HOME/agsbx/cert.pem" "$HOME/agsbx/private.key"
    ln -s "$HOME/agsbx/cert/cert.crt" "$HOME/agsbx/cert.pem"
    ln -s "$HOME/agsbx/cert/private.key" "$HOME/agsbx/private.key"
    echo "域名证书已就绪：$ym（$HOME/agsbx/cert/，容器重启后跟随宿主续期）"
  else
    rm -f "$HOME/agsbx/domain_cert_ready"
    rm -f "$HOME/agsbx/cert.pem" "$HOME/agsbx/private.key"
    command -v openssl >/dev/null 2>&1 && openssl ecparam -genkey -name prime256v1 -out "$HOME/agsbx/private.key" >/dev/null 2>&1
    command -v openssl >/dev/null 2>&1 && openssl req -new -x509 -days 36500 -key "$HOME/agsbx/private.key" -out "$HOME/agsbx/cert.pem" -subj "/CN=www.bing.com" >/dev/null 2>&1
    if [ ! -f "$HOME/agsbx/private.key" ]; then echo "警告：openssl 不可用且无域名证书，HY2/TUIC/AnyTLS 将无证书可用（已不再下载原版公开密钥）"; fi
  fi
}
