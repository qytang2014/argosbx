# backup.sh: 备份与恢复（含 WebDAV 云存储 + OpenSSL 加密）
#
# 设计原则：备份只存"配置"（vars.env），不存"身份"。
# 恢复时 uuid/Reality 密钥对/证书全部重新生成，避免多机共用密钥。
#
# 子命令（$1 之后的参数）：
#   backup [file]                  本地明文备份 (.tar.gz, 600)
#   backup --encrypt [file]        本地加密备份 (.enc)
#   backup --webdav [remote-path]  加密后上传 WebDAV（加密强制）
#   backup --webdav-init           交互配置 WebDAV（URL/用户/密码）
#   backup --webdav-ls [path]      列出 WebDAV 上的备份
#   restore <file> [--yes]         本地恢复（默认交互确认）
#   restore --webdav <remote-path> [--yes]  从 WebDAV 下载解密后恢复
#
# 口令：$BACKUP_PASSPHRASE 环境变量，或交互输入（backup 输两遍确认）。
# WebDAV 配置：$HOME/agsbx/webdav.env (600)，或 WEBDAV_URL/USER/PASS 环境变量。

# backup_read_passphrase <mode>: mode=backup(输两遍确认) / restore(输一遍)
# 回显：设置 BACKUP_PASSPHRASE_RESULT 变量
backup_read_passphrase(){
  local mode="$1" p1="" p2=""
  if [ -n "${BACKUP_PASSPHRASE:-}" ]; then
    BACKUP_PASSPHRASE_RESULT="$BACKUP_PASSPHRASE"
    return 0
  fi
  # 非交互终端且无环境变量：直接失败，不挂起等输入
  if [ ! -t 0 ]; then
    echo "需要备份口令：请设置 BACKUP_PASSPHRASE 环境变量或在终端交互运行"
    return 1
  fi
  printf "备份口令： " >&2; stty -echo 2>/dev/null || true
  IFS= read -r p1; stty echo 2>/dev/null || true; echo >&2
  [ -n "$p1" ] || { echo "口令不能为空"; return 1; }
  if [ "$mode" = "backup" ]; then
    printf "再输一遍确认： " >&2; stty -echo 2>/dev/null || true
    IFS= read -r p2; stty echo 2>/dev/null || true; echo >&2
    [ "$p1" = "$p2" ] || { echo "两次输入不一致"; return 1; }
  fi
  BACKUP_PASSPHRASE_RESULT="$p1"
  return 0
}

# backup_encrypt <in> <out>: OpenSSL AES-256-CBC + PBKDF2 加密
backup_encrypt(){
  local infile="$1" outfile="$2"
  command -v openssl >/dev/null 2>&1 || { echo "未找到 openssl，无法加密"; return 1; }
  [ -n "${BACKUP_PASSPHRASE_RESULT:-}" ] || { echo "未设置口令"; return 1; }
  openssl enc -aes-256-cbc -salt -pbkdf2 \
    -in "$infile" -out "$outfile" \
    -pass pass:"$BACKUP_PASSPHRASE_RESULT" 2>/dev/null || {
    echo "加密失败"; return 1
  }
  chmod 600 "$outfile" 2>/dev/null || true
  return 0
}

# backup_decrypt <in> <out>: 解密
backup_decrypt(){
  local infile="$1" outfile="$2"
  command -v openssl >/dev/null 2>&1 || { echo "未找到 openssl，无法解密"; return 1; }
  [ -n "${BACKUP_PASSPHRASE_RESULT:-}" ] || { echo "未设置口令"; return 1; }
  openssl enc -d -aes-256-cbc -pbkdf2 \
    -in "$infile" -out "$outfile" \
    -pass pass:"$BACKUP_PASSPHRASE_RESULT" 2>/dev/null || {
    echo "解密失败（口令错误或文件损坏）"; return 1
  }
  return 0
}

# backup_create_tar <outfile>: 打包 vars.env + sh.txt + META
# 回显：成功返回 0
backup_create_tar(){
  local outfile="$1" tmp="" files=""
  [ -f "$HOME/agsbx/vars.env" ] || { echo "未找到 $HOME/agsbx/vars.env，请先安装一次"; return 1; }
  tmp=$(mktemp -d) || return 1
  cp -f "$HOME/agsbx/vars.env" "$tmp/vars.env" 2>/dev/null || { rm -rf "$tmp"; echo "复制 vars.env 失败"; return 1; }
  files="vars.env"
  if [ -f "$HOME/agsbx/sh.txt" ]; then
    cp -f "$HOME/agsbx/sh.txt" "$tmp/sh.txt" 2>/dev/null && files="$files sh.txt"
  fi
  {
    echo "hostname=$(hostname 2>/dev/null || echo unknown)"
    echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
    echo "note=uuid/密钥/证书不在备份中，恢复时自动重新生成"
  } > "$tmp/META" 2>/dev/null || true
  files="$files META"
  # shellcheck disable=SC2086
  tar -czf "$outfile" -C "$tmp" $files 2>/dev/null || {
    rm -rf "$tmp"; echo "打包失败"; return 1
  }
  rm -rf "$tmp"
  chmod 600 "$outfile" 2>/dev/null || true
  return 0
}

# ---- WebDAV ----
# webdav_load_config: 从 webdav.env 或环境变量加载，设置 WEBDAV_URL/USER/PASS
webdav_load_config(){
  local envfile="$HOME/agsbx/webdav.env"
  # 环境变量优先
  if [ -n "${WEBDAV_URL:-}" ] && [ -n "${WEBDAV_USER:-}" ]; then
    # WEBDAV_PASS 可为空（匿名 WebDAV）
    return 0
  fi
  [ -f "$envfile" ] || return 1
  # 只读需要的三行，避免执行任意内容
  WEBDAV_URL=$(grep -m1 '^WEBDAV_URL=' "$envfile" 2>/dev/null | cut -d= -f2-)
  WEBDAV_USER=$(grep -m1 '^WEBDAV_USER=' "$envfile" 2>/dev/null | cut -d= -f2-)
  WEBDAV_PASS=$(grep -m1 '^WEBDAV_PASS=' "$envfile" 2>/dev/null | cut -d= -f2-)
  [ -n "$WEBDAV_URL" ] || return 1
  return 0
}

# webdav_curl_args: 输出 curl 认证参数（basic auth）
webdav_curl_args(){
  if [ -n "${WEBDAV_USER:-}" ]; then
    printf '%s' "-u"
    printf '%s' "${WEBDAV_USER}:${WEBDAV_PASS:-}"
  fi
}

# webdav_mkdir_p <remote-dir>: 逐级 MKCOL（WebDAV 不支持递归）
webdav_mkdir_p(){
  local dir="$1" cur="" part=""
  # 去掉首尾斜杠，按 / 切分逐级创建
  dir=$(printf '%s' "$dir" | sed 's|^/||; s|/$||')
  [ -z "$dir" ] && return 0
  local oldifs="$IFS"; IFS='/'
  # shellcheck disable=SC2086
  set -- $dir
  IFS="$oldifs"
  for part in "$@"; do
    [ -n "$part" ] || continue
    cur="$cur/$part"
    # shellcheck disable=SC2046
    curl -s -o /dev/null -w "%{http_code}" $(webdav_curl_args) \
      -X MKCOL "${WEBDAV_URL}${cur}/" 2>/dev/null | grep -qE "^(201|405|409)$" || true
  done
  return 0
}

# webdav_upload <localfile> <remote-path>
webdav_upload(){
  local localfile="$1" remotepath="$2" remotedir="" code=""
  [ -f "$localfile" ] || { echo "本地文件不存在：$localfile"; return 1; }
  # 远程目录部分自动创建
  case "$remotepath" in */*) remotedir="${remotepath%/*}"; webdav_mkdir_p "$remotedir";; esac
  # shellcheck disable=SC2046
  code=$(curl -s -o /dev/null -w "%{http_code}" $(webdav_curl_args) \
    -T "$localfile" "${WEBDAV_URL}/${remotepath}" 2>/dev/null)
  case "$code" in 200|201|204) return 0;; *)
    echo "WebDAV 上传失败（HTTP $code），请检查 URL/账号/权限"; return 1;;
  esac
}

# webdav_download <remote-path> <localfile>
webdav_download(){
  local remotepath="$1" localfile="$2" code=""
  # shellcheck disable=SC2046
  code=$(curl -s -o "$localfile" -w "%{http_code}" $(webdav_curl_args) \
    "${WEBDAV_URL}/${remotepath}" 2>/dev/null)
  case "$code" in 200) return 0;; *)
    rm -f "$localfile" 2>/dev/null || true
    echo "WebDAV 下载失败（HTTP $code）"; return 1;;
  esac
}

# webdav_list [path]: 列出 .enc 备份文件（PROPFIND 解析 href）
webdav_list(){
  local path="${1:-}" xml=""
  # shellcheck disable=SC2046
  xml=$(curl -s $(webdav_curl_args) -X PROPFIND \
    -H "Depth: 1" "${WEBDAV_URL}/${path}" 2>/dev/null) || {
    echo "WebDAV 列表失败"; return 1
  }
  printf '%s' "$xml" | grep -o "<d:href>[^<]*</d:href>" 2>/dev/null \
    | sed 's|<d:href>||; s|</d:href>||' \
    | grep "\.enc$" || echo "（无 .enc 备份文件）"
  return 0
}

# agsbx_webdav_init: 交互配置 WebDAV
agsbx_webdav_init(){
  local url="" user="" pass="" envfile="$HOME/agsbx/webdav.env" code=""
  if [ ! -t 0 ]; then
    echo "webdav-init 需要交互终端，或用 WEBDAV_URL/USER/PASS 环境变量"
    return 1
  fi
  printf "WebDAV URL（可带路径，如 https://dav.example.com/backups/argosbx/）： "
  IFS= read -r url
  [ -n "$url" ] || { echo "URL 不能为空"; return 1; }
  # 去掉末尾斜杠，统一拼接时加
  url=$(printf '%s' "$url" | sed 's|/$||')
  printf "用户名（匿名留空）： "
  IFS= read -r user
  if [ -n "$user" ]; then
    printf "密码： " >&2; stty -echo 2>/dev/null || true
    IFS= read -r pass; stty echo 2>/dev/null || true; echo >&2
  fi
  # 测试连通性
  if [ -n "$user" ]; then
    code=$(curl -s -o /dev/null -w "%{http_code}" -u "$user:$pass" \
      -X PROPFIND -H "Depth: 0" "$url/" 2>/dev/null)
  else
    code=$(curl -s -o /dev/null -w "%{http_code}" \
      -X PROPFIND -H "Depth: 0" "$url/" 2>/dev/null)
  fi
  case "$code" in 200|201|207) ;;
    *) echo "连接测试失败（HTTP $code），请检查 URL/账号"; return 1;;
  esac
  mkdir -p "$HOME/agsbx" 2>/dev/null || true
  {
    echo "WEBDAV_URL=$url"
    echo "WEBDAV_USER=$user"
    echo "WEBDAV_PASS=$pass"
  } > "$envfile" 2>/dev/null || { echo "写入配置失败"; return 1; }
  chmod 600 "$envfile" 2>/dev/null || true
  echo "WebDAV 配置已保存（$envfile，600 权限），连通性 OK"
  return 0
}

# ---- 主入口 ----
# agsbx_backup: backup 子命令分发。参数：$@（去掉 $1=backup 之后的部分）
agsbx_backup(){
  local arg1="${1:-}" arg2="${2:-}" outfile="" tmpenc="" remotename=""
  case "$arg1" in
    --webdav-init)
      agsbx_webdav_init; return $?
      ;;
    --webdav-ls)
      webdav_load_config || { echo "未配置 WebDAV，先运行 agsbx backup --webdav-init"; return 1; }
      webdav_list "$arg2"; return $?
      ;;
    --webdav)
      webdav_load_config || {
        echo "未配置 WebDAV。"
        echo "交互配置：agsbx backup --webdav-init"
        echo "或环境变量：WEBDAV_URL/WEBDAV_USER/WEBDAV_PASS"
        return 1
      }
      # 远程文件名：默认 hostname+时间戳；可带子目录（a/b/name.enc）
      remotename="$arg2"
      if [ -z "$remotename" ]; then
        remotename="argosbx-backup-$(hostname 2>/dev/null || echo host)-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo notime).enc"
      fi
      case "$remotename" in *.enc) ;; *) remotename="$remotename.enc";; esac
      # 口令（云端强制加密）
      backup_read_passphrase backup || return 1
      tmpenc=$(mktemp) || return 1
      local tmptar=$(mktemp) || { rm -f "$tmpenc"; return 1; }
      backup_create_tar "$tmptar" || { rm -f "$tmpenc" "$tmptar"; return 1; }
      backup_encrypt "$tmptar" "$tmpenc" || { rm -f "$tmpenc" "$tmptar"; return 1; }
      rm -f "$tmptar"
      if webdav_upload "$tmpenc" "$remotename"; then
        echo "已上传到 WebDAV：$remotename"
        echo "请保存好备份口令，丢口令=备份作废"
      fi
      rm -f "$tmpenc"
      return 0
      ;;
    --encrypt)
      outfile="$arg2"
      [ -n "$outfile" ] || outfile="$HOME/argosbx-backup-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo notime).enc"
      backup_read_passphrase backup || return 1
      local tmptar2=$(mktemp) || return 1
      backup_create_tar "$tmptar2" || { rm -f "$tmptar2"; return 1; }
      if backup_encrypt "$tmptar2" "$outfile"; then
        echo "加密备份已生成：$outfile"
        echo "请保存好备份口令，丢口令=备份作废"
      fi
      rm -f "$tmptar2"
      return 0
      ;;
    --help|-h|"")
      echo "用法："
      echo "  agsbx backup [file]              本地明文备份"
      echo "  agsbx backup --encrypt [file]    本地加密备份"
      echo "  agsbx backup --webdav [远端路径]  加密上传 WebDAV（自动建子目录）"
      echo "  agsbx backup --webdav-init       配置 WebDAV"
      echo "  agsbx backup --webdav-ls [路径]  列出 WebDAV 备份"
      echo "口令：交互输入，或 BACKUP_PASSPHRASE 环境变量"
      return 0
      ;;
    *)
      # 本地明文备份，arg1 为输出文件名
      outfile="$arg1"
      [ -n "$outfile" ] || outfile="$HOME/agsbx-backup-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo notime).tar.gz"
      if backup_create_tar "$outfile"; then
        echo "备份已生成：$outfile"
        echo "注意：uuid/密钥/证书不在备份中；含 egress 密码，请妥善保管"
      fi
      return 0
      ;;
  esac
}

# agsbx_restore: restore 子命令分发。参数：$@（去掉 $1=restore 之后的部分）
# 成功准备后设置 AGSBX_RESTORE_READY=1，由分发处清参数后落入主安装流程。
AGSBX_RESTORE_READY=0
agsbx_restore(){
  local target="" yesflag=0 webdavmode=0 a=""
  AGSBX_RESTORE_READY=0
  for a in "$@"; do
    case "$a" in
      --yes) yesflag=1;;
      --webdav) webdavmode=1;;
      --help|-h) echo "用法："; echo "  agsbx restore <备份文件> [--yes]"; echo "  agsbx restore --webdav <远端路径> [--yes]"; echo "恢复会清空当前安装并重装，uuid/密钥/证书重新生成"; return 0;;
      *) [ -z "$target" ] && target="$a";;
    esac
  done
  [ -n "$target" ] || { echo "请指定备份文件：agsbx restore <备份文件> [--yes]"; return 1; }

  local tmpdir="" tarfile=""
  tmpdir=$(mktemp -d) || return 1
  if [ "$webdavmode" = "1" ]; then
    webdav_load_config || { echo "未配置 WebDAV，先运行 agsbx backup --webdav-init"; rm -rf "$tmpdir"; return 1; }
    local dlfile="$tmpdir/download.enc"
    webdav_download "$target" "$dlfile" || { rm -rf "$tmpdir"; return 1; }
    tarfile="$dlfile"
  else
    [ -f "$target" ] || { echo "备份文件不存在：$target"; rm -rf "$tmpdir"; return 1; }
    tarfile="$target"
  fi

  # 按扩展名判断是否加密
  local plaintar="$tmpdir/backup.tar.gz" isenc=0
  case "$tarfile" in
    *.enc) isenc=1;;
  esac
  if [ "$isenc" = "1" ]; then
    backup_read_passphrase restore || { rm -rf "$tmpdir"; return 1; }
    backup_decrypt "$tarfile" "$plaintar" || { rm -rf "$tmpdir"; return 1; }
  else
    plaintar="$tarfile"
  fi

  # 解包校验
  tar -tzf "$plaintar" >/dev/null 2>&1 || { echo "备份文件损坏或格式错误"; rm -rf "$tmpdir"; return 1; }
  tar -xzf "$plaintar" -C "$tmpdir" 2>/dev/null || { echo "解包失败"; rm -rf "$tmpdir"; return 1; }
  [ -f "$tmpdir/vars.env" ] || { echo "备份中无 vars.env，无法恢复"; rm -rf "$tmpdir"; return 1; }

  echo "=== 备份信息 ==="
  cat "$tmpdir/META" 2>/dev/null || echo "（无 META 信息）"
  echo "=== 将用备份中的变量重新安装 ==="
  echo "注意：当前 $HOME/agsbx 将被清空；uuid/密钥/证书重新生成；端口沿用备份"
  echo "提示：如需改域名/端口，恢复前用环境变量覆盖，如 ym=新域名 agsbx restore ..."

  # 交互确认（--yes 跳过；非交互终端无 --yes 则中止）
  if [ "$yesflag" != "1" ]; then
    if [ ! -t 0 ]; then
      echo "非交互终端且未加 --yes，为安全起见中止。如确认请加 --yes"
      rm -rf "$tmpdir"; return 1
    fi
    printf "确认清空并恢复？输入 yes 继续： "
    local confirm=""
    IFS= read -r confirm
    [ "$confirm" = "yes" ] || { echo "已取消"; rm -rf "$tmpdir"; return 1; }
  fi

  # 导出备份变量：已存在的环境变量（显式覆盖）优先，不被覆盖
  local restore_vars="$tmpdir/vars.env" _line="" _vn=""
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in ''|\#*) continue;; esac
    _vn="${_line%%=*}"
    case "$_vn" in *[!a-zA-Z0-9_]*|'') continue;; esac
    if [ -z "${!_vn+x}" ]; then
      eval "export $_line" 2>/dev/null || true
    fi
  done < "$restore_vars"
  rm -rf "$tmpdir"

  echo "清空 $HOME/agsbx ..."
  rm -rf "$HOME/agsbx"
  mkdir -p "$HOME/agsbx"
  echo "变量已载入，开始重新安装..."
  AGSBX_RESTORE_READY=1
  return 0
}
