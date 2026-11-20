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
  grep -Fq 'case "$1" in del|list|upx|ups|upa|res) ;; *) vlpt_coexistence_check ;; esac' "$built_script" || {
    echo "FAIL: vlpt_coexistence_check invocation missing in built script"; exit 1;
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

echo "ALL TESTS PASSED!"
