#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Extract helper functions from built argosbx.sh
python3 - "$ROOT/argosbx.sh" "$TMP" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
helpers = ["run_with_timeout", "proxy_script_supports_cmd", "ensure_local_bin_in_path", "get_latest_github_vps_tag", "ensure_proxy_script", "check_and_prompt_force_email"]
for h in helpers:
    m = re.search(rf"{h}\(\)\{{.*?\n\}}\n", t, re.S)
    assert m, f"Helper {h} not found"
    open(f"{sys.argv[2]}/{h}.sh", "w").write(m.group(0))
PY

# Test 1: ensure_local_bin_in_path
export HOME="$TMP/home1"
mkdir -p "$HOME"
touch "$HOME/.bashrc"
export PATH="/usr/bin:/bin"
source "$TMP/ensure_local_bin_in_path.sh"
ensure_local_bin_in_path
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "FAIL: PATH does not contain .local/bin"; exit 1 ;;
esac
grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" || { echo "FAIL: .bashrc missing PATH export"; exit 1; }
# Idempotent call
ensure_local_bin_in_path
[ "$(grep -c 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc")" = "1" ] || { echo "FAIL: duplicate PATH export in .bashrc"; exit 1; }
echo "ensure_local_bin_in_path OK"

# Test 2: check_and_prompt_force_email
export HOME="$TMP/home2"
mkdir -p "$HOME/.local/bin"
source "$TMP/check_and_prompt_force_email.sh"

# Mock proxy script
cat > "$HOME/.local/bin/mock_proxy.sh" << 'EOF'
#!/bin/bash
if [ "$1" = "get-email" ]; then
  echo "old@example.com"
fi
EOF
chmod +x "$HOME/.local/bin/mock_proxy.sh"

# Test 2a: No new email -> empty
out=$(check_and_prompt_force_email "$HOME/.local/bin/mock_proxy.sh" "")
[ -z "$out" ] || { echo "FAIL: empty email should return empty"; exit 1; }

# Test 2b: Same email -> empty
out=$(check_and_prompt_force_email "$HOME/.local/bin/mock_proxy.sh" "old@example.com")
[ -z "$out" ] || { echo "FAIL: same email should return empty"; exit 1; }

# Test 2c: Different email, non-interactive (stdin from /dev/null) -> empty (default N)
out=$(check_and_prompt_force_email "$HOME/.local/bin/mock_proxy.sh" "new@example.com" < /dev/null)
[ -z "$out" ] || { echo "FAIL: non-interactive should default to no"; exit 1; }

# Test 2d: Different email, user answers 'y' with FORCE_INTERACTIVE -> "--force-email"
out=$(printf "y\n" | FORCE_INTERACTIVE=1 check_and_prompt_force_email "$HOME/.local/bin/mock_proxy.sh" "new@example.com")
[ "$out" = "--force-email" ] || { echo "FAIL: answering 'y' should return --force-email, got '$out'"; exit 1; }

# Test 2e: Different email, user answers 'n' with FORCE_INTERACTIVE -> empty
out=$(printf "n\n" | FORCE_INTERACTIVE=1 check_and_prompt_force_email "$HOME/.local/bin/mock_proxy.sh" "new@example.com")
[ -z "$out" ] || { echo "FAIL: answering 'n' should return empty, got '$out'"; exit 1; }

echo "check_and_prompt_force_email OK"

# Test 3: ensure_proxy_script existing file return 0
source "$TMP/ensure_proxy_script.sh"
source "$TMP/get_latest_github_vps_tag.sh"
ensure_proxy_script "mock_proxy.sh" || { echo "FAIL: existing mock_proxy should return 0"; exit 1; }
echo "ensure_proxy_script existing OK"

# Test 4: run_with_timeout + proxy_script_supports_cmd guard against legacy interactive scripts
source "$TMP/run_with_timeout.sh"
source "$TMP/proxy_script_supports_cmd.sh"
cat > "$TMP/legacy_caddy.sh" << 'EOF'
#!/bin/bash
while true; do
  read -p "请选择操作 [0-6]: " CHOICE
done
EOF
chmod +x "$TMP/legacy_caddy.sh"
if proxy_script_supports_cmd "$TMP/legacy_caddy.sh" "get-port"; then
  echo "FAIL: legacy interactive script should not be reported as supporting get-port"; exit 1
fi
if proxy_script_supports_cmd "$TMP/legacy_caddy.sh" "set-port"; then
  echo "FAIL: legacy interactive script should not be reported as supporting set-port"; exit 1
fi

# run_with_timeout kills hanging child within bounded time
if run_with_timeout 1 sleep 10; then
  echo "FAIL: run_with_timeout should fail when child times out"; exit 1
fi
echo "run_with_timeout & proxy_script_supports_cmd OK"

# Test 5: Real software_config proxy scripts reject unknown subcommands and non-TTY menu immediately
for pscript in "$ROOT/../software_config/caddy_proxy.sh" "$ROOT/../software_config/nginx_proxy.sh"; do
  [ -f "$pscript" ] || continue
  bash -n "$pscript" || { echo "FAIL: syntax error in $pscript"; exit 1; }
  proxy_script_supports_cmd "$pscript" "get-port" || { echo "FAIL: $pscript should support get-port"; exit 1; }
  proxy_script_supports_cmd "$pscript" "set-port" || { echo "FAIL: $pscript should support set-port"; exit 1; }
  proxy_script_supports_cmd "$pscript" "reload" || { echo "FAIL: $pscript should support reload"; exit 1; }
  proxy_script_supports_cmd "$pscript" "site-remove" || { echo "FAIL: $pscript should support site-remove"; exit 1; }
  if timeout 3 bash "$pscript" unknown-subcmd </dev/null >/dev/null 2>&1; then
    echo "FAIL: $pscript unknown-subcmd should exit non-zero"; exit 1
  fi
  if timeout 3 bash "$pscript" </dev/null >/dev/null 2>&1; then
    echo "FAIL: $pscript without TTY should exit non-zero instead of menu loop"; exit 1
  fi
done
echo "software_config CLI unknown-subcmd & non-TTY guards OK"

echo "PASS: proxy scripts integration"
