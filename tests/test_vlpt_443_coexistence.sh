#!/bin/bash
# Test: VLESS-Reality 443 port coexistence with local Web servers (Caddy / Nginx)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR=$(mktemp -d /tmp/test_vlpt_coexistence.XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

export HOME="$WORK_DIR/home"
export CADDY_PORT_FILE="$WORK_DIR/caddy_port"
export NGINX_PORT_FILE="$WORK_DIR/nginx_port"
mkdir -p "$HOME/agsbx"

# Source the coexistence module
source "$ROOT/modules/vlpt-coexistence.sh"

echo "=== Test 1: Non-443 does not trigger migration ==="
(
  export port_vl_re="12345"
  vlpt_coexistence_check
  [ ! -f "$HOME/agsbx/web_port" ] || { echo "FAIL: web_port created for non-443"; exit 1; }
)
echo "PASS: Test 1"

echo "=== Test 2: Sequential port probing (8443 -> 9443) ==="
(
  # Mock ss to simulate 8443 occupied
  ss(){
    echo "LISTEN 0 128 0.0.0.0:8443 0.0.0.0:*"
  }
  p=$(web_port_find_available)
  [ "$p" = "9443" ] || { echo "FAIL: expected 9443 when 8443 occupied, got $p"; exit 1; }
)
echo "PASS: Test 2"

echo "=== Test 3: Unattended vlpt=443 triggers port resolution & persistence ==="
(
  export port_vl_re="443"
  export FORCE_NONINTERACTIVE=1
  # Mock migrate to prevent executing host scripts during unit test
  web_server_migrate_to_port() { return 0; }
  vlpt_coexistence_check
  [ -f "$HOME/agsbx/web_port" ] || { echo "FAIL: web_port file not created"; exit 1; }
  wp=$(cat "$HOME/agsbx/web_port")
  case "$wp" in
    8443|9443|10443) ;;
    *) echo "FAIL: unexpected web_port $wp"; exit 1 ;;
  esac
  [ "${ym_vl_fb_port:-}" = "$wp" ] || { echo "FAIL: ym_vl_fb_port ($ym_vl_fb_port) does not match web_port ($wp)"; exit 1; }
)
echo "PASS: Test 3"

echo "=== Test 4: caddy_proxy.sh set-port (https_port, -Alt-Svc, explicit 443 & revert) ==="
(
  caddy_dir="$WORK_DIR/caddy"
  mkdir -p "$caddy_dir"
  test_caddy="$caddy_dir/Caddyfile"
  cat > "$test_caddy" << 'EOF'
{
    email admin@example.com
}

(security) {
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        Server "Protected"
    }
}

example.com:443 {
    root * /var/www/html
    file_server
}
EOF

  CADDY_DIR="$caddy_dir" CADDYFILE="$test_caddy" bash "$ROOT/../software_config/caddy_proxy.sh" set-port 8443

  # 1. Check persistence in web_port
  [ -f "$caddy_dir/web_port" ] || { echo "FAIL: caddy web_port file not created"; exit 1; }
  [ "$(cat "$caddy_dir/web_port")" = "8443" ] || { echo "FAIL: caddy web_port mismatch"; exit 1; }

  # 2. Check https_port injected in global block
  grep -q 'https_port 8443' "$test_caddy" || { echo "FAIL: https_port 8443 missing from Caddyfile"; exit 1; }

  # 3. Check -Alt-Svc injected inside (security) block
  grep -q -- '-Alt-Svc' "$test_caddy" || { echo "FAIL: -Alt-Svc missing from Caddyfile"; exit 1; }

  # 4. Check explicit :443 replaced by :8443
  grep -q 'example.com:8443' "$test_caddy" || { echo "FAIL: example.com:443 not migrated to :8443"; exit 1; }
  ! grep -q 'example.com:443' "$test_caddy" || { echo "FAIL: example.com:443 still present"; exit 1; }

  # 5. Test idempotence: invoke set-port 8443 multiple times
  CADDY_DIR="$caddy_dir" CADDYFILE="$test_caddy" bash "$ROOT/../software_config/caddy_proxy.sh" set-port 8443
  CADDY_DIR="$caddy_dir" CADDYFILE="$test_caddy" bash "$ROOT/../software_config/caddy_proxy.sh" set-port 8443
  port_count=$(grep -c 'https_port' "$test_caddy")
  [ "$port_count" = "1" ] || { echo "FAIL: expected exactly 1 https_port line, got $port_count"; exit 1; }

  # 6. Revert back to 443
  CADDY_DIR="$caddy_dir" CADDYFILE="$test_caddy" bash "$ROOT/../software_config/caddy_proxy.sh" set-port 443
  [ ! -f "$caddy_dir/web_port" ] || { echo "FAIL: caddy web_port should be removed on 443"; exit 1; }
  ! grep -q 'https_port' "$test_caddy" || { echo "FAIL: https_port still present after revert"; exit 1; }
  ! grep -q -- '-Alt-Svc' "$test_caddy" || { echo "FAIL: -Alt-Svc still present after revert"; exit 1; }
  grep -q 'example.com:443' "$test_caddy" || { echo "FAIL: example.com:443 not restored"; exit 1; }
)
echo "PASS: Test 4"

echo "=== Test 5: nginx_proxy.sh set-port (listen 127.0.0.1:<port>, Alt-Svc & revert) ==="
(
  nginx_dir="$WORK_DIR/nginx"
  conf_dir="$nginx_dir/conf.d"
  mkdir -p "$conf_dir"
  test_nginx="$conf_dir/site.conf"
  cat > "$test_nginx" << 'EOF'
server {
    listen 80;
    server_name example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name example.com;
    add_header Alt-Svc 'h3=":443"; ma=86400';
    root /var/www/html;
}
EOF

  NGINX_DIR="$nginx_dir" NGINX_CONF_DIR="$conf_dir" bash "$ROOT/../software_config/nginx_proxy.sh" set-port 8443

  # 1. Check persistence in web_port
  [ -f "$nginx_dir/web_port" ] || { echo "FAIL: nginx web_port file not created"; exit 1; }
  [ "$(cat "$nginx_dir/web_port")" = "8443" ] || { echo "FAIL: nginx web_port mismatch"; exit 1; }

  # 2. Check listen 127.0.0.1:8443
  grep -q 'listen 127.0.0.1:8443 ssl http2;' "$test_nginx" || { echo "FAIL: listen 127.0.0.1:8443 missing"; exit 1; }

  # 3. Check ipv6 443 commented out
  grep -q '#listen \[::\]:8443 ssl;' "$test_nginx" || { echo "FAIL: ipv6 443 not commented out"; exit 1; }

  # 4. Check Alt-Svc commented out
  grep -q '# add_header Alt-Svc' "$test_nginx" || { echo "FAIL: Alt-Svc not commented out in nginx"; exit 1; }

  # 5. Switch from 8443 to 9443 (custom-to-custom port migration test)
  NGINX_DIR="$nginx_dir" NGINX_CONF_DIR="$conf_dir" bash "$ROOT/../software_config/nginx_proxy.sh" set-port 9443
  grep -q 'listen 127.0.0.1:9443 ssl http2;' "$test_nginx" || { echo "FAIL: listen 127.0.0.1:9443 missing after second migration"; exit 1; }
  ! grep -q 'listen 127.0.0.1:8443' "$test_nginx" || { echo "FAIL: old 8443 listen still remains"; exit 1; }

  # 6. Idempotence: calling set-port 9443 again does not corrupt config
  NGINX_DIR="$nginx_dir" NGINX_CONF_DIR="$conf_dir" bash "$ROOT/../software_config/nginx_proxy.sh" set-port 9443
  count=$(grep -c 'listen 127.0.0.1:9443 ssl http2;' "$test_nginx")
  [ "$count" = "1" ] || { echo "FAIL: expected exactly 1 listen 127.0.0.1:9443 line, got $count"; exit 1; }

  # 7. Revert back to 443
  NGINX_DIR="$nginx_dir" NGINX_CONF_DIR="$conf_dir" bash "$ROOT/../software_config/nginx_proxy.sh" set-port 443
  [ ! -f "$nginx_dir/web_port" ] || { echo "FAIL: nginx web_port should be removed on 443"; exit 1; }
  grep -q 'listen 443 ssl http2;' "$test_nginx" || { echo "FAIL: listen 443 not restored"; exit 1; }
  grep -q 'listen \[::\]:443 ssl' "$test_nginx" || { echo "FAIL: listen [::]:443 not restored"; exit 1; }
  grep -q "add_header Alt-Svc 'h3=\":443\"; ma=86400';" "$test_nginx" || { echo "FAIL: Alt-Svc not restored in nginx"; exit 1; }
)
echo "PASS: Test 5"

echo "=== Test 6: Built argosbx.sh contains coexistence logic and fallback ports ==="
(
  built_script="$ROOT/argosbx.sh"
  grep -Fq 'if _is_install_run "$1"; then vlpt_coexistence_check || exit 1; fi' "$built_script" || {
    echo "FAIL: vlpt_coexistence_check invocation (with || exit 1) missing in built script"; exit 1;
  }
  grep -Fq 'export ym_vl_fb_port="${web_port:-443}"' "$built_script" || {
    echo "FAIL: ym_vl_fb_port export missing in built script"; exit 1;
  }
  grep -Fq '"dest": "${ym_vl_fb:-$ym_vl_re}:${ym_vl_fb_port:-443}"' "$built_script" || {
    echo "FAIL: reality-fb-dest with ym_vl_fb_port missing"; exit 1;
  }
  grep -Fq '"target": "${ym_vl_fb:-$ym_vl_re}:${ym_vl_fb_port:-443}"' "$built_script" || {
    echo "FAIL: reality-fb-target with ym_vl_fb_port missing"; exit 1;
  }
  grep -Fq '"server": "${ym_vl_fb:-$ym_vl_re}"' "$built_script" || {
    echo "FAIL: reality-fb-handshake server missing"; exit 1;
  }
  grep -Fq '"server_port": ${ym_vl_fb_port:-443}' "$built_script" || {
    echo "FAIL: reality-fb-handshake-port missing"; exit 1;
  }

  # Verify no legacy inline migration functions in built script
  ! grep -q '_caddy_migrate_file' "$built_script" || {
    echo "FAIL: legacy _caddy_migrate_file still found in built script"; exit 1;
  }
  ! grep -q '_nginx_migrate_file' "$built_script" || {
    echo "FAIL: legacy _nginx_migrate_file still found in built script"; exit 1;
  }
  # Verify delegation to proxy scripts
  grep -Fq '"$caddy_bin" set-port "$target_port"' "$built_script" || {
    echo "FAIL: delegation to caddy_proxy.sh set-port missing in built script"; exit 1;
  }
  grep -Fq '"$nginx_bin" set-port "$target_port"' "$built_script" || {
    echo "FAIL: delegation to nginx_proxy.sh set-port missing in built script"; exit 1;
  }
)
echo "PASS: Test 6"

echo "=== Test 7: caddy_proxy.sh and nginx_proxy.sh CLI set-port interface ==="
(
  # Verify set-port handles invalid ports properly
  ! bash "$ROOT/../software_config/caddy_proxy.sh" set-port "invalid" >/dev/null 2>&1 || {
    echo "FAIL: caddy_proxy.sh set-port did not reject invalid port"; exit 1;
  }
  ! bash "$ROOT/../software_config/nginx_proxy.sh" set-port "70000" >/dev/null 2>&1 || {
    echo "FAIL: nginx_proxy.sh set-port did not reject out of range port"; exit 1;
  }
)
echo "PASS: Test 7"

echo "=== Test 8: web_server_migrate_to_port delegates to proxy scripts ==="
(
  # Mock caddy_proxy.sh and nginx_proxy.sh in $HOME/.local/bin
  mkdir -p "$HOME/.local/bin"
  log_file="$WORK_DIR/mock_proxy_calls.log"
  cat > "$HOME/.local/bin/caddy_proxy.sh" << EOF
#!/bin/bash
echo "caddy:\$*" >> "$log_file"
EOF
  chmod +x "$HOME/.local/bin/caddy_proxy.sh"

  cat > "$HOME/.local/bin/nginx_proxy.sh" << EOF
#!/bin/bash
echo "nginx:\$*" >> "$log_file"
EOF
  chmod +x "$HOME/.local/bin/nginx_proxy.sh"

  # Stub ss to return 0 immediately so it doesn't wait
  ss() { echo ""; }

  web_server_migrate_to_port 8443

  grep -q "caddy:set-port 8443" "$log_file" || { echo "FAIL: caddy_proxy.sh set-port not invoked"; exit 1; }
  grep -q "nginx:set-port 8443" "$log_file" || { echo "FAIL: nginx_proxy.sh set-port not invoked"; exit 1; }
)
echo "PASS: Test 8"

echo "=== Test 9: Uninstallation cleanup restores Web port 443 and removes markers ==="
(
  # Setup mock hook system if not present
  source "$ROOT/modules/hook.sh"

  # Sandbox process controls so tests never stop real host services
  systemctl() { return 0; }
  kill() { return 0; }

  caddy_dir="$WORK_DIR/caddy_uninstall"
  mkdir -p "$caddy_dir"
  test_caddy="$caddy_dir/Caddyfile"
  cat > "$test_caddy" << 'EOF'
{
    https_port 8443
}

(security) {
    header {
        -Alt-Svc
    }
}

example.com:8443 {
    file_server
}
EOF
  echo "8443" > "$caddy_dir/web_port"

  nginx_dir="$WORK_DIR/nginx_uninstall"
  conf_dir="$nginx_dir/conf.d"
  mkdir -p "$conf_dir"
  test_nginx="$conf_dir/site.conf"
  cat > "$test_nginx" << 'EOF'
server {
    listen 127.0.0.1:8443 ssl http2;
    #listen [::]:8443 ssl;
    # add_header Alt-Svc 'h3=":443"; ma=86400';
    server_name example.com;
}
EOF
  echo "8443" > "$nginx_dir/web_port"

  # Setup agsbx web_port
  mkdir -p "$HOME/agsbx"
  echo "8443" > "$HOME/agsbx/web_port"

  # Setup proxy scripts in HOME/.local/bin
  mkdir -p "$HOME/.local/bin"
  cp "$ROOT/../software_config/caddy_proxy.sh" "$HOME/.local/bin/caddy_proxy.sh"
  cp "$ROOT/../software_config/nginx_proxy.sh" "$HOME/.local/bin/nginx_proxy.sh"
  chmod +x "$HOME/.local/bin/caddy_proxy.sh" "$HOME/.local/bin/nginx_proxy.sh"

  export CADDY_DIR="$caddy_dir"
  export CADDYFILE="$test_caddy"
  export CADDY_PORT_FILE="$caddy_dir/web_port"
  export NGINX_DIR="$nginx_dir"
  export NGINX_CONF_DIR="$conf_dir"
  export NGINX_PORT_FILE="$nginx_dir/web_port"

  # Register and run on_uninstall hook
  register_hook on_uninstall vlpt_coexistence_cleanup
  run_hook on_uninstall

  # Verify web_port files removed
  [ ! -f "$HOME/agsbx/web_port" ] || { echo "FAIL: $HOME/agsbx/web_port not removed"; exit 1; }
  [ ! -f "$caddy_dir/web_port" ] || { echo "FAIL: $caddy_dir/web_port not removed"; exit 1; }
  [ ! -f "$nginx_dir/web_port" ] || { echo "FAIL: $nginx_dir/web_port not removed"; exit 1; }

  # Verify Caddyfile restored
  ! grep -q 'https_port' "$test_caddy" || { echo "FAIL: https_port still present in Caddyfile after uninstall"; exit 1; }
  ! grep -q -- '-Alt-Svc' "$test_caddy" || { echo "FAIL: -Alt-Svc still present in Caddyfile after uninstall"; exit 1; }
  grep -q 'example.com:443' "$test_caddy" || { echo "FAIL: example.com:443 not restored in Caddyfile after uninstall"; exit 1; }

  # Verify Nginx restored
  grep -q 'listen 443 ssl http2;' "$test_nginx" || { echo "FAIL: listen 443 not restored in Nginx after uninstall"; exit 1; }
  grep -q 'listen \[::\]:443 ssl' "$test_nginx" || { echo "FAIL: ipv6 443 not restored in Nginx after uninstall"; exit 1; }
  grep -q "add_header Alt-Svc 'h3=\":443\"; ma=86400';" "$test_nginx" || { echo "FAIL: Alt-Svc not restored in Nginx after uninstall"; exit 1; }
)
echo "PASS: Test 9"

echo "=== Test 10: Existing domain handle {} block update & overwrite ==="
(
  caddy_dir="$WORK_DIR/caddy_handle"
  mkdir -p "$caddy_dir"
  test_caddy="$caddy_dir/Caddyfile"
  cat > "$test_caddy" << 'EOF'
{
    email admin@example.com
}

(security) {
    header {
        Server "Protected"
    }
}

example.com:8443 {
    import security
    encode zstd gzip
    handle {
        root * /var/www/old_html
        file_server
    }
}
EOF

  # 1. Test caddy_proxy.sh site --force overwrites domain even with :8443 port and nested handle {}
  CADDY_DIR="$caddy_dir" CADDYFILE="$test_caddy" bash "$ROOT/../software_config/caddy_proxy.sh" site --domain "example.com" --proxy "127.0.0.1:9090" --force

  # Verify old handle content is gone and new proxy is present
  ! grep -q '/var/www/old_html' "$test_caddy" || { echo "FAIL: old handle content still present after overwrite"; exit 1; }
  grep -q 'reverse_proxy 127.0.0.1:9090' "$test_caddy" || { echo "FAIL: new reverse_proxy missing from handle block"; exit 1; }

  # Verify valid configuration
  caddy validate --config "$test_caddy" --adapter caddyfile >/dev/null 2>&1 || { echo "FAIL: Caddyfile syntax invalid after overwrite"; exit 1; }

  # 2. Test append with --proxy updates default handle block
  CADDY_DIR="$caddy_dir" CADDYFILE="$test_caddy" bash "$ROOT/../software_config/caddy_proxy.sh" site --domain "example.com" --subpath "/api=127.0.0.1:3000" --proxy "127.0.0.1:8888" --append

  grep -q 'handle_path /api\*' "$test_caddy" || { echo "FAIL: subroute handle missing"; exit 1; }
  grep -q 'reverse_proxy 127.0.0.1:8888' "$test_caddy" || { echo "FAIL: default handle was not updated to 8888 on append"; exit 1; }
  ! grep -q 'reverse_proxy 127.0.0.1:9090' "$test_caddy" || { echo "FAIL: old reverse_proxy 9090 still present"; exit 1; }

  caddy validate --config "$test_caddy" --adapter caddyfile >/dev/null 2>&1 || { echo "FAIL: Caddyfile syntax invalid after append"; exit 1; }
)
echo "PASS: Test 10"

echo "=== Test 11: Idempotent repeat deployment with vlpt=443 maintains port (8443 does not jump to 9443) ==="
(
  export port_vl_re="443"
  export FORCE_NONINTERACTIVE=1

  # Round 1: fresh deployment
  web_server_migrate_to_port() { return 0; }
  vlpt_coexistence_check
  wp1=$(cat "$HOME/agsbx/web_port")
  [ "$wp1" = "8443" ] || { echo "FAIL: Round 1 expected 8443, got $wp1"; exit 1; }

  # Simulate Caddy listening on 8443 after round 1
  ss(){
    echo 'LISTEN 0 4096 127.0.0.1:8443 0.0.0.0:* users:(("caddy",pid=1234,fd=7))'
  }

  # Round 2: repeat deployment with vlpt=443
  vlpt_coexistence_check
  wp2=$(cat "$HOME/agsbx/web_port")
  [ "$wp2" = "8443" ] || { echo "FAIL: Round 2 jumped port to $wp2, expected to stay 8443"; exit 1; }

  # Simulate Nginx listening on 8443 after round 1
  ss(){
    echo 'LISTEN 0 511 127.0.0.1:8443 0.0.0.0:* users:(("nginx",pid=5678,fd=6))'
  }

  # Round 3: repeat deployment with Nginx
  vlpt_coexistence_check
  wp3=$(cat "$HOME/agsbx/web_port")
  [ "$wp3" = "8443" ] || { echo "FAIL: Round 3 jumped port to $wp3, expected to stay 8443"; exit 1; }
)
echo "PASS: Test 11"

echo "=== Test 12: Subpath removal in caddy_proxy.sh and nginx_proxy.sh ==="
(
  # 1. Test Caddy subpath removal
  c_dir="$WORK_DIR/caddy_subrm"
  mkdir -p "$c_dir"
  c_file="$c_dir/Caddyfile"
  cat > "$c_file" << 'EOF'
(security) {
    header {
        Server "Protected"
    }
}

example.com {
    handle /api* {
        reverse_proxy 127.0.0.1:3000
    }
    handle /subtoken* {
        root * "/var/www/sub"
        file_server
    }
    handle {
        root * /var/www/html
        file_server
    }
}
EOF
  # Remove /subtoken* via site --remove
  CADDY_DIR="$c_dir" CADDYFILE="$c_file" bash "$ROOT/../software_config/caddy_proxy.sh" site --domain "example.com" --subpath "/subtoken*" --remove

  ! grep -q '/subtoken' "$c_file" || { echo "FAIL: /subtoken* still present in Caddyfile after site --remove"; exit 1; }
  grep -F 'handle /api*' "$c_file" >/dev/null 2>&1 || { echo "FAIL: /api* was accidentally removed from Caddyfile"; exit 1; }
  grep -q '/var/www/html' "$c_file" || { echo "FAIL: default handle /var/www/html was removed from Caddyfile"; exit 1; }

  # Remove /api* via remove --subpath
  CADDY_DIR="$c_dir" CADDYFILE="$c_file" bash "$ROOT/../software_config/caddy_proxy.sh" remove --domain "example.com" --subpath "/api*"

  ! grep -F 'handle /api' "$c_file" || { echo "FAIL: handle /api* still present in Caddyfile after remove --subpath"; exit 1; }
  grep -q '/var/www/html' "$c_file" || { echo "FAIL: default handle /var/www/html was removed from Caddyfile"; exit 1; }

  # 2. Test Nginx subpath removal
  n_dir="$WORK_DIR/nginx_subrm"
  conf_d="$n_dir/conf.d"
  mkdir -p "$conf_d"
  n_file="$conf_d/example.com.conf"
  cat > "$n_file" << 'EOF'
server {
    listen 443 ssl http2;
    server_name example.com;

    # ================= 核心路由块 =================
    location ^~ /api/ {
        proxy_pass http://127.0.0.1:3000/;
    }
    location ^~ /subtoken/ {
        root /var/www/sub;
        index index.html;
    }
    location / {
        root /var/www/html;
        index index.html;
    }
    # ==============================================
}
EOF
  # Remove /subtoken/ via site --remove
  NGINX_DIR="$n_dir" NGINX_CONF_DIR="$conf_d" bash "$ROOT/../software_config/nginx_proxy.sh" site --domain "example.com" --subpath "/subtoken" --remove

  ! grep -F 'location ^~ /subtoken' "$n_file" || { echo "FAIL: /subtoken/ still present in Nginx after site --remove"; exit 1; }
  grep -F 'location ^~ /api' "$n_file" || { echo "FAIL: /api/ was accidentally removed from Nginx"; exit 1; }
  grep -q '/var/www/html' "$n_file" || { echo "FAIL: default location was removed from Nginx"; exit 1; }

  # Remove /api/ via remove --subpath
  NGINX_DIR="$n_dir" NGINX_CONF_DIR="$conf_d" bash "$ROOT/../software_config/nginx_proxy.sh" remove --domain "example.com" --subpath "/api"

  ! grep -F 'location ^~ /api' "$n_file" || { echo "FAIL: /api/ still present in Nginx after remove --subpath"; exit 1; }
  grep -q '/var/www/html' "$n_file" || { echo "FAIL: default location was removed from Nginx"; exit 1; }
)
echo "PASS: Test 12"

echo "=== Test 13: caddy_proxy.sh set-port with 443 L4 SNI routing (--sni & --sni-target) ==="
(
  caddy_dir="$WORK_DIR/caddy_l4"
  mkdir -p "$caddy_dir"
  test_caddy="$caddy_dir/Caddyfile"
  cat > "$test_caddy" << 'EOF'
{
    email admin@example.com
}

(security) {
    header {
        Server "Protected"
    }
}

example.com {
    root * /var/www/html
    file_server
}
EOF

  CADDY_DIR="$caddy_dir" CADDYFILE="$test_caddy" bash "$ROOT/../software_config/caddy_proxy.sh" set-port 8443 --sni www.stanford.edu --sni-target 8444

  [ -f "$caddy_dir/sni_router" ] || { echo "FAIL: caddy sni_router file not created"; exit 1; }
  [ "$(cat "$caddy_dir/sni_router")" = "www.stanford.edu|127.0.0.1:8444" ] || { echo "FAIL: sni_router content mismatch"; exit 1; }
  grep -q 'https_port 8443' "$test_caddy" || { echo "FAIL: https_port 8443 missing"; exit 1; }
  grep -q 'layer4 {' "$test_caddy" || { echo "FAIL: layer4 block missing"; exit 1; }
  grep -q '@reality_sni tls sni www.stanford.edu' "$test_caddy" || { echo "FAIL: @reality_sni matcher missing"; exit 1; }
  grep -q 'proxy 127.0.0.1:8444' "$test_caddy" || { echo "FAIL: proxy 127.0.0.1:8444 missing"; exit 1; }
  grep -q 'proxy 127.0.0.1:8443' "$test_caddy" || { echo "FAIL: default proxy 127.0.0.1:8443 missing"; exit 1; }

  # Idempotent re-run without --sni retains persisted sni_router and does not duplicate layer4
  CADDY_DIR="$caddy_dir" CADDYFILE="$test_caddy" bash "$ROOT/../software_config/caddy_proxy.sh" set-port 8443
  [ "$(grep -c 'layer4 {' "$test_caddy")" = "1" ] || { echo "FAIL: duplicate layer4 block"; exit 1; }

  # Revert to 443 removes layer4 and sni_router
  CADDY_DIR="$caddy_dir" CADDYFILE="$test_caddy" bash "$ROOT/../software_config/caddy_proxy.sh" set-port 443
  [ ! -f "$caddy_dir/sni_router" ] || { echo "FAIL: sni_router not removed on 443 revert"; exit 1; }
  ! grep -q 'layer4' "$test_caddy" || { echo "FAIL: layer4 block not removed on 443 revert"; exit 1; }
)
echo "PASS: Test 13"

echo "=== Test 14: nginx_proxy.sh set-port with 443 stream SNI routing (--sni & --sni-target) ==="
(
  nginx_dir="$WORK_DIR/nginx_l4"
  conf_dir="$nginx_dir/conf.d"
  mkdir -p "$conf_dir"
  cat > "$nginx_dir/nginx.conf" << 'EOF'
events { worker_connections 128; }
http {
    include conf.d/*.conf;
}
EOF
  cat > "$conf_dir/site.conf" << 'EOF'
server {
    listen 443 ssl http2;
    server_name example.com;
}
EOF

  NGINX_DIR="$nginx_dir" NGINX_CONF_DIR="$conf_dir" bash "$ROOT/../software_config/nginx_proxy.sh" set-port 8443 --sni www.stanford.edu --sni-target 8444

  [ -f "$nginx_dir/sni_router" ] || { echo "FAIL: nginx sni_router file not created"; exit 1; }
  [ -f "$nginx_dir/stream.d/reality_sni.conf" ] || { echo "FAIL: stream.d/reality_sni.conf not created"; exit 1; }
  grep -q 'www.stanford.edu  127.0.0.1:8444;' "$nginx_dir/stream.d/reality_sni.conf" || { echo "FAIL: SNI map entry missing"; exit 1; }
  grep -q 'default     127.0.0.1:8443;' "$nginx_dir/stream.d/reality_sni.conf" || { echo "FAIL: default map entry missing"; exit 1; }
  grep -q 'stream {' "$nginx_dir/nginx.conf" || { echo "FAIL: stream block not injected into nginx.conf"; exit 1; }

  # Revert to 443 removes stream.d/reality_sni.conf and sni_router
  NGINX_DIR="$nginx_dir" NGINX_CONF_DIR="$conf_dir" bash "$ROOT/../software_config/nginx_proxy.sh" set-port 443
  [ ! -f "$nginx_dir/sni_router" ] || { echo "FAIL: nginx sni_router not removed on 443 revert"; exit 1; }
  [ ! -f "$nginx_dir/stream.d/reality_sni.conf" ] || { echo "FAIL: reality_sni.conf not removed on 443 revert"; exit 1; }
)
echo "PASS: Test 14"

echo "=== Test 15: vlpt_coexistence_sync_sni homogeneous engine selection & reality_port allocation ==="
(
  export HOME="$WORK_DIR/home_sync"
  mkdir -p "$HOME/agsbx" "$HOME/.local/bin"
  log_file="$WORK_DIR/sync_sni_calls.log"
  : > "$log_file"
  cat > "$HOME/.local/bin/caddy_proxy.sh" << EOF
#!/bin/bash
echo "caddy:\$*" >> "$log_file"
EOF
  cat > "$HOME/.local/bin/nginx_proxy.sh" << EOF
#!/bin/bash
echo "nginx:\$*" >> "$log_file"
EOF
  chmod +x "$HOME/.local/bin/caddy_proxy.sh" "$HOME/.local/bin/nginx_proxy.sh"

  ss() { echo ""; }
  ensure_proxy_script() { return 0; }

  export port_vl_re="443"
  export web_port="8443"
  echo "8443" > "$HOME/agsbx/web_port"
  export certsrc="caddy"
  export ym="my.example.com"

  vlpt_coexistence_sync_sni "www.stanford.edu"

  [ "${vlpt_listen_addr:-}" = "127.0.0.1" ] || { echo "FAIL: vlpt_listen_addr should be 127.0.0.1, got ${vlpt_listen_addr:-}"; exit 1; }
  [ "${vlpt_listen_port:-}" = "8444" ] || { echo "FAIL: vlpt_listen_port should be 8444, got ${vlpt_listen_port:-}"; exit 1; }
  grep -q "caddy:set-port 8443 --sni www.stanford.edu --sni-target 8444" "$log_file" || { echo "FAIL: expected caddy set-port with --sni, got $(cat "$log_file")"; exit 1; }
  ! grep -q "nginx:" "$log_file" || { echo "FAIL: nginx_proxy.sh should not be called when engine is caddy"; exit 1; }
)
echo "PASS: Test 15"

echo "=== Test 16: xhpt=443 moves only xhpt (vlpt on a high port stays) ==="
(
  export HOME="$WORK_DIR/home_xhpt"
  mkdir -p "$HOME/agsbx" "$HOME/.local/bin"
  log_file="$WORK_DIR/xhpt_calls.log"
  : > "$log_file"
  cat > "$HOME/.local/bin/caddy_proxy.sh" << EOF
#!/bin/bash
echo "caddy:\$*" >> "$log_file"
EOF
  cat > "$HOME/.local/bin/nginx_proxy.sh" << EOF
#!/bin/bash
echo "nginx:\$*" >> "$log_file"
EOF
  chmod +x "$HOME/.local/bin/caddy_proxy.sh" "$HOME/.local/bin/nginx_proxy.sh"

  ss() { echo ""; }
  ensure_proxy_script() { return 0; }

  export port_xh="443"
  export port_vl_re="12345"
  export web_port="8443"
  echo "8443" > "$HOME/agsbx/web_port"
  export certsrc="caddy"
  export ym="my.example.com"

  vlpt_coexistence_sync_sni "www.stanford.edu"

  [ "${xhpt_listen_addr:-}" = "127.0.0.1" ] || { echo "FAIL: xhpt_listen_addr should be 127.0.0.1, got ${xhpt_listen_addr:-}"; exit 1; }
  [ "${xhpt_listen_port:-}" = "8444" ] || { echo "FAIL: xhpt_listen_port should be 8444, got ${xhpt_listen_port:-}"; exit 1; }
  [ -z "${vlpt_listen_addr:-}" ] || { echo "FAIL: vlpt_listen_addr should stay unset (vlpt is on a high port), got ${vlpt_listen_addr:-}"; exit 1; }
  [ -z "${vlpt_listen_port:-}" ] || { echo "FAIL: vlpt_listen_port should stay unset (vlpt is on a high port), got ${vlpt_listen_port:-}"; exit 1; }
  grep -q "caddy:set-port 8443 --sni www.stanford.edu --sni-target 8444" "$log_file" || { echo "FAIL: expected caddy set-port with --sni, got $(cat "$log_file")"; exit 1; }
  ! grep -q "nginx:" "$log_file" || { echo "FAIL: nginx_proxy.sh should not be called when engine is caddy"; exit 1; }
)
echo "PASS: Test 16"

echo "=== Test 17: arpt=443 (sing-box) moves only arpt ==="
(
  export HOME="$WORK_DIR/home_arpt"
  mkdir -p "$HOME/agsbx" "$HOME/.local/bin"
  log_file="$WORK_DIR/arpt_calls.log"
  : > "$log_file"
  cat > "$HOME/.local/bin/caddy_proxy.sh" << EOF
#!/bin/bash
echo "caddy:\$*" >> "$log_file"
EOF
  cat > "$HOME/.local/bin/nginx_proxy.sh" << EOF
#!/bin/bash
echo "nginx:\$*" >> "$log_file"
EOF
  chmod +x "$HOME/.local/bin/caddy_proxy.sh" "$HOME/.local/bin/nginx_proxy.sh"

  ss() { echo ""; }
  ensure_proxy_script() { return 0; }

  export port_ar="443"
  export port_vl_re="12345"
  export web_port="8443"
  echo "8443" > "$HOME/agsbx/web_port"
  export certsrc="caddy"
  export ym="my.example.com"

  vlpt_coexistence_sync_sni "www.stanford.edu"

  [ "${arpt_listen_addr:-}" = "127.0.0.1" ] || { echo "FAIL: arpt_listen_addr should be 127.0.0.1, got ${arpt_listen_addr:-}"; exit 1; }
  [ "${arpt_listen_port:-}" = "8444" ] || { echo "FAIL: arpt_listen_port should be 8444, got ${arpt_listen_port:-}"; exit 1; }
  [ -z "${vlpt_listen_addr:-}" ] || { echo "FAIL: vlpt_listen_addr should stay unset (vlpt is on a high port), got ${vlpt_listen_addr:-}"; exit 1; }
  [ -z "${vlpt_listen_port:-}" ] || { echo "FAIL: vlpt_listen_port should stay unset (vlpt is on a high port), got ${vlpt_listen_port:-}"; exit 1; }
  grep -q "caddy:set-port 8443 --sni www.stanford.edu --sni-target 8444" "$log_file" || { echo "FAIL: expected caddy set-port with --sni, got $(cat "$log_file")"; exit 1; }
)
echo "PASS: Test 17"

echo "=== Test 18: Two Reality protocols on 443 = loud error, no silent pick ==="
(
  export port_vl_re="443" port_xh="443"
  rc=0
  out=$(reality_443_proto 2>&1) || rc=$?
  [ "$rc" = "2" ] || { echo "FAIL: reality_443_proto should return 2 on conflict, got $rc (out: $out)"; exit 1; }
  echo "$out" | grep -q "vlpt" || { echo "FAIL: conflict error should name vlpt, got: $out"; exit 1; }
  echo "$out" | grep -q "xhpt" || { echo "FAIL: conflict error should name xhpt, got: $out"; exit 1; }
)
echo "PASS: Test 18a"
(
  # vlpt_coexistence_check must exit 1 (stop the install) on conflict
  export port_vl_re="443" port_xh="443" FORCE_NONINTERACTIVE=1
  if ( vlpt_coexistence_check ); then
    echo "FAIL: vlpt_coexistence_check should exit 1 on conflict"; exit 1
  fi
)
echo "PASS: Test 18b"

echo "=== Test 19: vlpt=443 regression (vlpt moves, xhpt on a high port stays) ==="
(
  export HOME="$WORK_DIR/home_vlpt_reg"
  mkdir -p "$HOME/agsbx" "$HOME/.local/bin"
  log_file="$WORK_DIR/vlpt_reg_calls.log"
  : > "$log_file"
  cat > "$HOME/.local/bin/caddy_proxy.sh" << EOF
#!/bin/bash
echo "caddy:\$*" >> "$log_file"
EOF
  cat > "$HOME/.local/bin/nginx_proxy.sh" << EOF
#!/bin/bash
echo "nginx:\$*" >> "$log_file"
EOF
  chmod +x "$HOME/.local/bin/caddy_proxy.sh" "$HOME/.local/bin/nginx_proxy.sh"

  ss() { echo ""; }
  ensure_proxy_script() { return 0; }

  export port_vl_re="443"
  export port_xh="12345"
  export web_port="8443"
  echo "8443" > "$HOME/agsbx/web_port"
  export certsrc="caddy"
  export ym="my.example.com"

  vlpt_coexistence_sync_sni "www.stanford.edu"

  [ "${vlpt_listen_addr:-}" = "127.0.0.1" ] || { echo "FAIL: vlpt_listen_addr should be 127.0.0.1, got ${vlpt_listen_addr:-}"; exit 1; }
  [ "${vlpt_listen_port:-}" = "8444" ] || { echo "FAIL: vlpt_listen_port should be 8444, got ${vlpt_listen_port:-}"; exit 1; }
  [ -z "${xhpt_listen_addr:-}" ] || { echo "FAIL: xhpt_listen_addr should stay unset (xhpt is on a high port), got ${xhpt_listen_addr:-}"; exit 1; }
  [ -z "${xhpt_listen_port:-}" ] || { echo "FAIL: xhpt_listen_port should stay unset (xhpt is on a high port), got ${xhpt_listen_port:-}"; exit 1; }
  grep -q "caddy:set-port 8443 --sni www.stanford.edu --sni-target 8444" "$log_file" || { echo "FAIL: expected caddy set-port with --sni, got $(cat "$log_file")"; exit 1; }
)
echo "PASS: Test 19"

echo "=== Test 20: Built argosbx.sh has conditional listen/port for all 7 Reality inbounds ==="
(
  built_script="$ROOT/argosbx.sh"
  # Xray: xhpt / vxpt / xupt / xcpt / vwpt (vlpt regression below)
  grep -Fq '"listen": "${xhpt_listen_addr:-::}",' "$built_script" || { echo "FAIL: xhpt conditional listen missing"; exit 1; }
  grep -Fq '"port": ${xhpt_listen_port:-$port_xh},' "$built_script" || { echo "FAIL: xhpt conditional port missing"; exit 1; }
  grep -Fq '"listen": "${vxpt_listen_addr:-::}",' "$built_script" || { echo "FAIL: vxpt conditional listen missing"; exit 1; }
  grep -Fq '"port": ${vxpt_listen_port:-$port_vx},' "$built_script" || { echo "FAIL: vxpt conditional port missing"; exit 1; }
  grep -Fq '"listen": "${xupt_listen_addr:-::}",' "$built_script" || { echo "FAIL: xupt conditional listen missing"; exit 1; }
  grep -Fq '"port": ${xupt_listen_port:-$port_xu},' "$built_script" || { echo "FAIL: xupt conditional port missing"; exit 1; }
  grep -Fq '"listen": "${xcpt_listen_addr:-::}",' "$built_script" || { echo "FAIL: xcpt conditional listen missing"; exit 1; }
  grep -Fq '"port": ${xcpt_listen_port:-$port_xc},' "$built_script" || { echo "FAIL: xcpt conditional port missing"; exit 1; }
  grep -Fq '"listen": "${vwpt_listen_addr:-::}",' "$built_script" || { echo "FAIL: vwpt conditional listen missing"; exit 1; }
  grep -Fq '"port": ${vwpt_listen_port:-$port_vw},' "$built_script" || { echo "FAIL: vwpt conditional port missing"; exit 1; }
  # sing-box: arpt
  grep -Fq '"listen":"${arpt_listen_addr:-::}",' "$built_script" || { echo "FAIL: arpt conditional listen missing"; exit 1; }
  grep -Fq '"listen_port":${arpt_listen_port:-$port_ar},' "$built_script" || { echo "FAIL: arpt conditional port missing"; exit 1; }
  # vlpt regression (Xray + sing-box, unchanged)
  grep -Fq '"listen": "${vlpt_listen_addr:-::}",' "$built_script" || { echo "FAIL: vlpt Xray conditional listen missing"; exit 1; }
  grep -Fq '"port": ${vlpt_listen_port:-$port_vl_re},' "$built_script" || { echo "FAIL: vlpt Xray conditional port missing"; exit 1; }
  grep -Fq '"listen_port": ${vlpt_listen_port:-$port_vl_re},' "$built_script" || { echo "FAIL: vlpt sing-box conditional port missing"; exit 1; }
)
echo "PASS: Test 20"

echo "=== Test 21: set-port failure makes web_server_migrate_to_port return 1 ==="
(
  export HOME="$WORK_DIR/home_migrate_fail"
  mkdir -p "$HOME/agsbx" "$HOME/.local/bin"
  cat > "$HOME/.local/bin/caddy_proxy.sh" << 'EOF'
#!/bin/bash
exit 1
EOF
  cat > "$HOME/.local/bin/nginx_proxy.sh" << 'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$HOME/.local/bin/caddy_proxy.sh" "$HOME/.local/bin/nginx_proxy.sh"
  ss() { echo ""; }
  ensure_proxy_script() { return 0; }

  # Caddy engine: set-port fails -> return 1
  if web_server_migrate_to_port 8443 "" "" "caddy" 2>/dev/null; then
    echo "FAIL: web_server_migrate_to_port should return 1 when caddy set-port fails"; exit 1
  fi
  # Nginx engine: set-port fails -> return 1
  if web_server_migrate_to_port 8443 "" "" "nginx" 2>/dev/null; then
    echo "FAIL: web_server_migrate_to_port should return 1 when nginx set-port fails"; exit 1
  fi
  # SNI variant (the sync_sni path): set-port --sni fails -> return 1
  if web_server_migrate_to_port 8443 "www.stanford.edu" "8444" "caddy" 2>/dev/null; then
    echo "FAIL: web_server_migrate_to_port should return 1 when caddy set-port --sni fails"; exit 1
  fi
)
echo "PASS: Test 21"

echo "=== Test 22: vlpt_coexistence_sync_sni propagates set-port failure ==="
(
  export HOME="$WORK_DIR/home_sync_fail"
  mkdir -p "$HOME/agsbx" "$HOME/.local/bin"
  log_file="$WORK_DIR/sync_fail_calls.log"
  : > "$log_file"
  cat > "$HOME/.local/bin/caddy_proxy.sh" << EOF
#!/bin/bash
echo "caddy:\$*" >> "$log_file"
exit 1
EOF
  chmod +x "$HOME/.local/bin/caddy_proxy.sh"
  # No nginx_proxy.sh: engine is caddy, so only caddy runs
  ss() { echo ""; }
  ensure_proxy_script() { return 0; }

  export port_vl_re="443"
  export port_xh="12345"
  export web_port="8443"
  echo "8443" > "$HOME/agsbx/web_port"
  export certsrc="caddy"
  export ym="my.example.com"

  if vlpt_coexistence_sync_sni "www.stanford.edu" 2>/dev/null; then
    echo "FAIL: vlpt_coexistence_sync_sni should return 1 when set-port fails"; exit 1
  fi
  # The Reality inbound was already moved to the internal port before set-port
  # ran; sync_sni must not silently claim success in that state.
  [ "${vlpt_listen_addr:-}" = "127.0.0.1" ] || { echo "FAIL: vlpt_listen_addr should be 127.0.0.1 (moved before set-port)"; exit 1; }
  grep -q "caddy:set-port 8443 --sni www.stanford.edu --sni-target 8444" "$log_file" || { echo "FAIL: expected caddy set-port with --sni, got $(cat "$log_file")"; exit 1; }
)
echo "PASS: Test 22a"
(
  # Regression: set-port succeeds -> sync_sni returns 0
  export HOME="$WORK_DIR/home_sync_ok"
  mkdir -p "$HOME/agsbx" "$HOME/.local/bin"
  cat > "$HOME/.local/bin/caddy_proxy.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$HOME/.local/bin/caddy_proxy.sh"
  ss() { echo ""; }
  ensure_proxy_script() { return 0; }

  export port_vl_re="443"
  export web_port="8443"
  echo "8443" > "$HOME/agsbx/web_port"
  export certsrc="caddy"
  export ym="my.example.com"

  vlpt_coexistence_sync_sni "www.stanford.edu" || { echo "FAIL: vlpt_coexistence_sync_sni should return 0 when set-port succeeds"; exit 1; }
)
echo "PASS: Test 22b"

echo "=== Test 23: vlpt_coexistence_check propagates set-port failure ==="
(
  export HOME="$WORK_DIR/home_check_fail"
  mkdir -p "$HOME/agsbx" "$HOME/.local/bin"
  cat > "$HOME/.local/bin/caddy_proxy.sh" << 'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$HOME/.local/bin/caddy_proxy.sh"
  ss() { echo ""; }
  ensure_proxy_script() { return 0; }

  export port_vl_re="443"
  export FORCE_NONINTERACTIVE=1
  export reym="www.stanford.edu"
  export certsrc="caddy"
  export ym="my.example.com"

  if vlpt_coexistence_check 2>/dev/null; then
    echo "FAIL: vlpt_coexistence_check should return 1 when set-port fails"; exit 1
  fi
)
echo "PASS: Test 23a"
(
  # Built script: the top-level check call must stop the install on failure,
  # and _auto_sni_run must not swallow a sync_sni failure with || true.
  grep -Fq 'if _is_install_run "$1"; then vlpt_coexistence_check || exit 1; fi' "$ROOT/argosbx.sh" || { echo "FAIL: built script check call lacks || exit 1"; exit 1; }
  ! grep -Fq 'vlpt_coexistence_sync_sni "$reym" || true' "$ROOT/argosbx.sh" || { echo "FAIL: built script still swallows sync_sni failure in _auto_sni_run"; exit 1; }
  grep -Fq 'vlpt_coexistence_sync_sni "$reym" || return 1' "$ROOT/argosbx.sh" || { echo "FAIL: built script _auto_sni_run lacks || return 1"; exit 1; }
)
echo "PASS: Test 23b"

echo "=== Test 24: caddy_proxy.sh & nginx_proxy.sh --no-default (404), get-port, reload ==="
(
  # 1. Caddy --no-default + subpath append + default handle replacement + get-port
  c_dir="$WORK_DIR/caddy_nodef"
  mkdir -p "$c_dir"
  c_file="$c_dir/Caddyfile"
  old_blog="$WORK_DIR/old_blog_dir"
  mkdir -p "$old_blog"
  echo "old blog content" > "$old_blog/index.html"

  cat > "$c_file" << EOF
{
    email admin@example.com
}
(security) {
    header {
        Server "Protected"
    }
}
example.com {
    import security
    handle /subtok* {
        root * "/tmp/websbx"
        file_server
    }
    handle {
        root * ${old_blog}
        file_server
    }
}
EOF

  # Replace default blog handle with --no-default via --append: preserves /subtok* and keeps disk files untouched
  CADDY_DIR="$c_dir" CADDYFILE="$c_file" bash "$ROOT/../software_config/caddy_proxy.sh" site --domain "example.com" --no-default --append
  grep -q 'handle /subtok\*' "$c_file" || { echo "FAIL: Caddy subroute lost after --no-default --append"; exit 1; }
  grep -q 'respond 404' "$c_file" || { echo "FAIL: Caddy default handle missing respond 404"; exit 1; }
  ! grep -q "$old_blog" "$c_file" || { echo "FAIL: Caddy old blog mapping still present"; exit 1; }
  [ -f "$old_blog/index.html" ] || { echo "FAIL: disk blog file should NOT be deleted"; exit 1; }

  # Fresh site creation with --no-default --force (no /var/www/html mapping)
  CADDY_DIR="$c_dir" CADDYFILE="$c_file" bash "$ROOT/../software_config/caddy_proxy.sh" site --domain "fresh.example.com" --no-default --force
  grep -q 'fresh.example.com' "$c_file" || { echo "FAIL: fresh.example.com block missing"; exit 1; }
  ! grep -q '/var/www/html' "$c_file" || { echo "FAIL: --no-default should not reference /var/www/html"; exit 1; }

  # get-port & reload CLI
  echo "8443" > "$c_dir/web_port"
  gp=$(CADDY_DIR="$c_dir" CADDYFILE="$c_file" bash "$ROOT/../software_config/caddy_proxy.sh" get-port)
  [ "$gp" = "8443" ] || { echo "FAIL: caddy get-port expected 8443, got $gp"; exit 1; }
  CADDY_DIR="$c_dir" CADDYFILE="$c_file" bash "$ROOT/../software_config/caddy_proxy.sh" reload

  # 2. Nginx --no-default + subpath append + default location replacement + get-port
  n_dir="$WORK_DIR/nginx_nodef"
  mkdir -p "$n_dir/conf.d" "$n_dir/certs"
  NGINX_DIR="$n_dir" NGINX_CONF_DIR="$n_dir/conf.d" CERT_DIR="$n_dir/certs" NGINX_SKIP_CERT_ISSUE=1 \
    bash "$ROOT/../software_config/nginx_proxy.sh" site --domain "example.com" --no-default --force
  n_conf="$n_dir/conf.d/example.com.conf"
  [ -f "$n_conf" ] || { echo "FAIL: Nginx conf not created"; exit 1; }
  grep -q 'return 404;' "$n_conf" || { echo "FAIL: Nginx --no-default missing return 404"; exit 1; }
  ! grep -q '/var/www/html' "$n_conf" || { echo "FAIL: Nginx --no-default should not reference /var/www/html"; exit 1; }

  # Mount subscription subpath via --append and verify both /subtok/ and return 404 coexist
  NGINX_DIR="$n_dir" NGINX_CONF_DIR="$n_dir/conf.d" CERT_DIR="$n_dir/certs" NGINX_SKIP_CERT_ISSUE=1 \
    bash "$ROOT/../software_config/nginx_proxy.sh" site --domain "example.com" --subpath "/subtok*=/tmp/websbx:nostrip:static" --append
  grep -q 'location \^~ /subtok/' "$n_conf" || { echo "FAIL: Nginx subroute missing"; exit 1; }
  grep -q 'return 404;' "$n_conf" || { echo "FAIL: Nginx default 404 lost after subpath append"; exit 1; }

  # get-port & reload CLI
  echo "9443" > "$n_dir/web_port"
  ngp=$(NGINX_DIR="$n_dir" NGINX_CONF_DIR="$n_dir/conf.d" bash "$ROOT/../software_config/nginx_proxy.sh" get-port)
  [ "$ngp" = "9443" ] || { echo "FAIL: nginx get-port expected 9443, got $ngp"; exit 1; }
  NGINX_DIR="$n_dir" NGINX_CONF_DIR="$n_dir/conf.d" bash "$ROOT/../software_config/nginx_proxy.sh" reload
)
echo "PASS: Test 24"

echo "=== Test 25: vlpt_coexistence_sync_sni deduplicates repeated set-port & _reality_proto_port ignores stale inactive ports ==="
(
  # 25a: Calling vlpt_coexistence_sync_sni twice with identical tuple invokes set-port only once
  export HOME="$WORK_DIR/home_dedup"
  mkdir -p "$HOME/agsbx" "$HOME/.local/bin"
  c_dir="$WORK_DIR/caddy_dedup"
  mkdir -p "$c_dir"
  export CADDYFILE="$c_dir/Caddyfile"
  cat > "$CADDYFILE" << 'EOF'
{
    https_port 8443
    layer4 {
        :443 {
            @reality_sni tls sni www.stanford.edu
            route @reality_sni {
                proxy 127.0.0.1:8444
            }
            route {
                proxy 127.0.0.1:8443
            }
        }
    }
}
EOF
  log_file="$WORK_DIR/dedup_calls.log"
  : > "$log_file"
  cat > "$HOME/.local/bin/caddy_proxy.sh" << EOF
#!/bin/bash
echo "\$@" >> "$log_file"
exit 0
EOF
  chmod +x "$HOME/.local/bin/caddy_proxy.sh"
  ss() { echo ""; }
  ensure_proxy_script() { return 0; }

  export port_vl_re="443"
  export web_port="8443"
  echo "8443" > "$HOME/agsbx/web_port"
  export certsrc="caddy"
  export ym="my.example.com"
  unset _VLPT_SNI_SYNCED_KEY

  vlpt_coexistence_sync_sni "www.stanford.edu" || { echo "FAIL: first sync_sni failed"; exit 1; }
  vlpt_coexistence_sync_sni "www.stanford.edu" || { echo "FAIL: second sync_sni failed"; exit 1; }
  cnt=$(wc -l < "$log_file" | tr -d ' ')
  [ "$cnt" = "1" ] || { echo "FAIL: expected set-port called once, got $cnt calls: $(cat "$log_file")"; exit 1; }

  # 25b: _reality_proto_port ignores stale vl_re=443 in ports.env when rep only enables arpt=443
  port_get() { [ "$1" = "vl_re" ] && echo "443"; }
  unset port_vl_re vlpt port_xh xhpt port_vx vxpt port_vw vwpt port_xu xupt port_xc xcpt
  vlp=""; xhp=""; vxp=""; vwp=""; xup=""; xcp=""
  arp="yes"; port_ar="443"; arpt="443"
  p_found=$(reality_443_proto) || { echo "FAIL: reality_443_proto should not conflict with inactive stale vl_re=443"; exit 1; }
  [ "$p_found" = "arpt" ] || { echo "FAIL: expected arpt, got $p_found"; exit 1; }
)
echo "PASS: Test 25"

echo "=== Test 26: vlpt_coexistence_cleanup never hangs on legacy interactive or stuck proxy scripts ==="
(
  # 26a: Legacy caddy_proxy.sh without get-port/set-port falls into interactive `while true; read -p`
  export HOME="$WORK_DIR/home_del_hang"
  mkdir -p "$HOME/agsbx" "$HOME/.local/bin"
  cat > "$HOME/.local/bin/caddy_proxy.sh" << 'EOF'
#!/bin/bash
while true; do
  read -p "请选择操作 [0-6]: " CHOICE
  sleep 1
done
EOF
  chmod +x "$HOME/.local/bin/caddy_proxy.sh"
  ensure_proxy_script() { return 0; }
  systemctl() { return 0; }

  # Must NOT hang and must clean up cleanly
  t0=$(date +%s)
  out=$(vlpt_coexistence_cleanup 2>&1)
  t1=$(date +%s)
  elapsed=$((t1 - t0))
  [ "$elapsed" -lt 5 ] || { echo "FAIL: Test 26a took ${elapsed}s (legacy script hung)"; exit 1; }
  echo "$out" | grep -q '\[卸载 1/4\]' || { echo "FAIL: missing uninstall progress log: $out"; exit 1; }

  # 26b: Proxy script that supports set-port but hangs internally (sleep 60) must be bounded by timeout
  echo "8443" > "$HOME/agsbx/web_port"
  export certsrc="caddy"
  cat > "$HOME/.local/bin/caddy_proxy.sh" << 'EOF'
#!/bin/bash
case "$1" in
  get-port) echo "8443"; exit 0 ;;
  set-port) sleep 60; exit 0 ;;
esac
EOF
  chmod +x "$HOME/.local/bin/caddy_proxy.sh"
  t0=$(date +%s)
  AGSBX_UNINSTALL_TIMEOUT=2 vlpt_coexistence_cleanup >/dev/null 2>&1 || true
  t1=$(date +%s)
  elapsed=$((t1 - t0))
  [ "$elapsed" -lt 6 ] || { echo "FAIL: Test 26b took ${elapsed}s (timeout guard failed)"; exit 1; }
  [ ! -f "$HOME/agsbx/web_port" ] || { echo "FAIL: web_port not removed after bounded timeout cleanup"; exit 1; }
)
echo "PASS: Test 26"

echo "ALL TESTS PASSED!"
