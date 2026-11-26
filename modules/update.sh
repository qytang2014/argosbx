# update.sh: 一键更新 Argosbx 主脚本（agsbx up / update）
# 从项目仓库拉取最新 argosbx.sh，执行语法校验与完整性检查后热替换 CLI

agsbx_update(){
  echo "正在检查并更新 Argosbx 脚本至最新版本..."
  local tmp_file
  tmp_file=$(mktemp) 2>/dev/null || tmp_file="/tmp/agsbx_update.$$"
  local dl_ok=0
  local target_url="${agsbxurl:-https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh}"

  if command -v curl >/dev/null 2>&1; then
    curl -sL "$target_url" -o "$tmp_file" && dl_ok=1
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp_file" "$target_url" && dl_ok=1
  fi

  if [ "$dl_ok" != "1" ] || [ ! -s "$tmp_file" ]; then
    echo "❌ 脚本下载失败，请检查网络连接！"
    rm -f "$tmp_file" 2>/dev/null || true
    return 1
  fi

  # 语法与完整性校验：必须包含主标识且语法检测无报错
  if ! head -n 30 "$tmp_file" | grep -q "agsbx"; then
    echo "❌ 下载的文件格式无效或内容损坏，更新中止！"
    rm -f "$tmp_file" 2>/dev/null || true
    return 1
  fi
  if ! bash -n "$tmp_file" 2>/dev/null; then
    echo "❌ 下载的脚本语法校验未通过，更新中止！"
    rm -f "$tmp_file" 2>/dev/null || true
    return 1
  fi

  # 获取版本信息（兼容旧路径 $HOME/bin/agsbx 平滑迁移）
  local target_bin="$HOME/.local/bin/agsbx"
  local legacy_bin="$HOME/bin/agsbx"
  local cur_bin="${SCRIPT_PATH:-$target_bin}"
  if [ ! -s "$cur_bin" ] && [ -s "$legacy_bin" ]; then
    cur_bin="$legacy_bin"
  fi
  if [ ! -s "$cur_bin" ] && [ -n "$0" ] && [ -f "$0" ]; then
    cur_bin="$0"
  fi
  local old_ver new_ver
  old_ver=$(grep -E '^[[:space:]]*(echo|#)[[:space:]]+.*[当]前版本' "$cur_bin" 2>/dev/null | grep -oE '[vV]?[0-9]+(\.[0-9]+)+' | head -n 1 || echo "")
  new_ver=$(grep -E '^[[:space:]]*(echo|#)[[:space:]]+.*[当]前版本' "$tmp_file" 2>/dev/null | grep -oE '[vV]?[0-9]+(\.[0-9]+)+' | head -n 1 || echo "")

  local canon_0="" canon_legacy=""
  if [ -n "$0" ] && [ -f "$0" ]; then
    canon_0=$(readlink -f "$0" 2>/dev/null || echo "$0")
  fi
  canon_legacy=$(readlink -f "$legacy_bin" 2>/dev/null || echo "$legacy_bin")

  chmod +x "$tmp_file"
  local updated=0
  mkdir -p "$HOME/.local/bin" 2>/dev/null || true
  if cp -f "$tmp_file" "$target_bin" 2>/dev/null; then
    chmod +x "$target_bin" 2>/dev/null || true
    updated=1
    rm -f "$legacy_bin" 2>/dev/null || true
    command -v ensure_local_bin_in_path >/dev/null 2>&1 && ensure_local_bin_in_path
    if [ "$(id -u 2>/dev/null)" = "0" ] && [ -d /usr/local/bin ]; then
      ln -sf "$target_bin" /usr/local/bin/agsbx 2>/dev/null || true
    fi
  fi

  # 如果当前执行脚本本身是本地 argosbx.sh 且非 $target_bin / 旧 $legacy_bin，也同步更新
  if [ -n "$0" ] && [ -f "$0" ]; then
    local b0
    b0=$(basename "$0" 2>/dev/null || echo "")
    case "$b0" in
      argosbx.sh|agsbx)
        local canon_bin
        canon_bin=$(readlink -f "$target_bin" 2>/dev/null || echo "$target_bin")
        if [ "$canon_0" != "$canon_bin" ] && [ "$canon_0" != "$canon_legacy" ] && [ "$0" != "$legacy_bin" ]; then
          cp -f "$tmp_file" "$0" 2>/dev/null || true
          chmod +x "$0" 2>/dev/null || true
        fi
        ;;
    esac
  fi
  rm -f "$tmp_file" 2>/dev/null || true

  if [ "$updated" = "1" ]; then
    echo "🎉 Argosbx 脚本更新成功！"
    [ -n "$new_ver" ] && echo "最新版本: $new_ver (原版本: ${old_ver:-未知})"
    echo "可直接在终端使用 agsbx 体验最新功能。"
    return 0
  else
    echo "❌ 写入脚本失败，请检查文件写入权限！"
    return 1
  fi
}

# dispatch handler (step 3): up / update subcommand.
# Verbatim move of the old build.py dispatch block.
dispatch_update(){
  if [ "$1" = "up" ] || [ "$1" = "update" ]; then agsbx_update; exit; fi
}
command -v register_hook >/dev/null 2>&1 && {
  register_hook dispatch dispatch_update
} || true
