# proxy-script.sh: Helper functions for managing caddy_proxy.sh and nginx_proxy.sh

# Run a command non-interactively (stdin from /dev/null) with an upper-bound timeout.
# Args: $1=timeout_seconds, $2...=command and arguments
run_with_timeout(){
  local sec="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$sec" "$@" </dev/null
  else
    "$@" </dev/null
  fi
}

# Static capability check before invoking a local proxy script subcommand.
# Rejects legacy interactive proxy scripts that lack the requested subcommand
# (which would otherwise fall through into `while true; read -p` and deadlock).
proxy_script_supports_cmd(){
  local bin="$1" cmd="$2"
  [ -f "$bin" ] && [ -r "$bin" ] || return 1
  case "$cmd" in
    get-port)    grep -qE '^[[:space:]]*get-port\)' "$bin" 2>/dev/null && return 0 ;;
    set-port)    grep -qE '^[[:space:]]*set-port\)' "$bin" 2>/dev/null && return 0 ;;
    reload)      grep -qE '^[[:space:]]*reload\)' "$bin" 2>/dev/null && return 0 ;;
    site-remove) grep -qE -- '--remove' "$bin" 2>/dev/null && grep -qE '^[[:space:]]*site\)' "$bin" 2>/dev/null && return 0 ;;
    *) return 1 ;;
  esac
  # If the script contains an interactive menu loop/prompt and missed the subcommand above,
  # treat it as a legacy script that would hang on stdin and refuse to invoke it.
  if grep -qE 'read -p|while true' "$bin" 2>/dev/null; then
    return 1
  fi
  return 0
}

# ensure_local_bin_in_path：确保 $HOME/.local/bin 存在并在当前 PATH 及 ~/.bashrc 中
ensure_local_bin_in_path(){
  local target_dir="$HOME/.local/bin"
  mkdir -p "$target_dir" 2>/dev/null || true
  case ":$PATH:" in
    *":$target_dir:"*) ;;
    *)
      export PATH="$target_dir:$PATH"
      if [ -f "$HOME/.bashrc" ] && ! grep -q 'export PATH="\$HOME/\.local/bin:\$PATH"' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
      fi
      ;;
  esac
}

# get_latest_github_vps_tag：动态探测 GitHub Release 中 vps- 前缀的最新 tag，默认保底 vps-v1.0.0
get_latest_github_vps_tag(){
  local repo="qytang2014/software"
  local fallback="vps-v1.0.0"
  local latest=""
  latest=$(curl -sL --connect-timeout 4 --max-time 6 "https://github.com/${repo}/tags" 2>/dev/null | grep -oE "vps-v[0-9.]+" | head -n 1)
  if [ -n "$latest" ]; then
    echo "$latest"
  else
    echo "$fallback"
  fi
}

# ensure_proxy_script：自动保障 caddy_proxy.sh / nginx_proxy.sh 存在于 $HOME/.local/bin 且为最新可用版本
ensure_proxy_script(){
  local script_name="$1"
  [ -n "$script_name" ] || return 1
  ensure_local_bin_in_path
  local target_path="$HOME/.local/bin/$script_name"
  local tag_file="$HOME/.local/bin/.${script_name}.tag"

  local repo="qytang2014/software"
  local tag="${VPS_TAG:-$(get_latest_github_vps_tag)}"

  local is_old=0
  if [ ! -s "$target_path" ] || [ ! -x "$target_path" ]; then
    is_old=1
  elif [ "$script_name" = "caddy_proxy.sh" ]; then
    if [ ! -f "$tag_file" ] || [ "$(cat "$tag_file" 2>/dev/null | tr -d '[:space:]')" != "$tag" ]; then
      is_old=1
    elif ! grep -q "caddy_apply_port_to_caddyfile" "$target_path" 2>/dev/null || ! grep -q "matches_domain" "$target_path" 2>/dev/null || ! grep -q "sni_router" "$target_path" 2>/dev/null || ! grep -q 'ENVIRON\["INJ_TEXT"\]' "$target_path" 2>/dev/null || ! grep -q "NO_DEFAULT" "$target_path" 2>/dev/null || ! grep -q "caddy_safe_reload" "$target_path" 2>/dev/null || ! grep -q "get-port)" "$target_path" 2>/dev/null; then
      is_old=1
    fi
  elif [ "$script_name" = "nginx_proxy.sh" ]; then
    if [ ! -f "$tag_file" ] || [ "$(cat "$tag_file" 2>/dev/null | tr -d '[:space:]')" != "$tag" ]; then
      is_old=1
    elif ! grep -q "cli_nginx_set_port" "$target_path" 2>/dev/null || ! grep -q "sni_router" "$target_path" 2>/dev/null || ! grep -q 'ENVIRON\["LOC_CONF"\]' "$target_path" 2>/dev/null || ! grep -q "NO_DEFAULT" "$target_path" 2>/dev/null || ! grep -q "nginx_safe_reload" "$target_path" 2>/dev/null || ! grep -q "get-port)" "$target_path" 2>/dev/null; then
      is_old=1
    fi
  fi

  if [ "$is_old" = "0" ]; then
    return 0
  fi

  echo "检测到 $script_name 为旧版本或缺失 (当前: $(cat "$tag_file" 2>/dev/null || echo "未记录")，最新: $tag)，正在拉取最新版本..."
  local raw_url="https://github.com/${repo}/releases/download/${tag}/${script_name}"
  local mirror_url="https://ghproxy.net/${raw_url}"

  mkdir -p "$HOME/.local/bin" 2>/dev/null || true
  local tmpfile
  tmpfile=$(mktemp 2>/dev/null || echo "/tmp/${script_name}.$$")

  local dl_ok=0
  if curl -fL --retry 1 --connect-timeout 4 --max-time 8 "$raw_url" -o "$tmpfile" 2>/dev/null; then
    dl_ok=1
  else
    echo "官方直链连接超时，尝试通过镜像拉取 $script_name..."
    if curl -fL --retry 1 --connect-timeout 4 --max-time 8 "$mirror_url" -o "$tmpfile" 2>/dev/null; then
      dl_ok=1
    fi
  fi

  if [ "$dl_ok" = "1" ] && [ -s "$tmpfile" ] && head -n 1 "$tmpfile" | grep -q "bash"; then
    rm -f "$target_path" 2>/dev/null || true
    mv -f "$tmpfile" "$target_path"
    chmod +x "$target_path" 2>/dev/null || true
    echo "$tag" > "$tag_file" 2>/dev/null || true
    echo "✅ 已成功更新 $script_name 至最新版 ($tag)"
    return 0
  else
    rm -f "$tmpfile" 2>/dev/null || true
    if [ -s "$target_path" ] && [ -x "$target_path" ]; then
      echo "⚠️ 下载最新 $script_name 失败，继续使用现有版本保底"
      return 0
    fi
    echo "下载 $script_name 失败，请检查网络"
    return 1
  fi
}

# check_and_prompt_force_email：检测是否已有旧全局邮箱，如有且不同，在交互模式下警告并询问用户是否全局覆盖（默认 n）
check_and_prompt_force_email(){
  local script_cmd="$1"
  local new_email="$2"
  [ -z "$new_email" ] && return 0
  [ -x "$script_cmd" ] || command -v "$script_cmd" >/dev/null 2>&1 || return 0

  local old_email=""
  old_email=$("$script_cmd" get-email 2>/dev/null | tr -d ' \r\n')
  if [ -n "$old_email" ] && [ "$old_email" != "$new_email" ]; then
    echo "------------------------------------------------------------" >&2
    echo "⚠️  【告警提示】检测到 Web 服务已配置全局 ACME 邮箱: [$old_email]" >&2
    echo "⚠️  注意: 替换该邮箱将进行【全局替换】，影响此服务器上所有的站点证书！" >&2
    echo "------------------------------------------------------------" >&2

    local replace_email="n"
    if [ -t 0 ] || [ "${FORCE_INTERACTIVE:-0}" = "1" ]; then
      printf "是否确认将全局邮箱替换为 [%s]? [y/N] (默认 n): " "$new_email" >&2
      read -r replace_email || replace_email="n"
    else
      echo "非交互环境，默认保持现有全局邮箱 [$old_email]，不覆盖。" >&2
    fi

    case "$replace_email" in
      [yY]|[yY][eE][sS])
        echo "--force-email"
        return 0
        ;;
      *)
        echo "保持现有全局邮箱 [$old_email]。" >&2
        return 0
        ;;
    esac
  fi
  return 0
}
