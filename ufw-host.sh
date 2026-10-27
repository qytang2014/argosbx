#!/bin/bash
# Host-side ufw helper for the argosbx container (NOT run inside a
# container, NOT part of the container image). Run it on the host:
#   bash ufw-host.sh apply [--container NAME] [--env FILE] [--state FILE]
#   bash ufw-host.sh delete [--state FILE]
#   bash ufw-host.sh print [--container NAME] [--env FILE]
# Rules:
# - Only when ufw is already active. This script NEVER turns ufw
#   on by itself, never opens SSH (22) or any port outside the node list.
# - State lives on the HOST (default $HOME/.agsbx-container-ufw.rules),
#   never inside the container, so `delete` still works after the
#   container is gone. Only rules in that state file are ever deleted.
# - --container NAME (preferred for bridge -p mapping): reads
#   `docker port NAME`, so the host port and its published proto win.
#   The container must be running for this to work.
# - Without --container: reads container env vars (from --env FILE or
#   the current shell) and assumes host port = container port (1:1,
#   host-network mode or identical -p mapping). A warning is printed
#   in that case; bridge users should prefer --container.
# - Transport mapping for the env path (same as modules/ufw.sh):
#   hy2/tuic udp only, ss/socks tcp+udp, xhttp-tls-UDP udp only,
#   everything else tcp only.
# - All ufw failures are warnings only, except a missing/empty
#   desired set or a missing container, which are errors.
set -u
STATE="${UFW_HOST_STATE:-$HOME/.agsbx-container-ufw.rules}"
CONTAINER=""
ENVFILE=""
CMD="${1:-}"
if [ -n "$CMD" ]; then shift; fi
while [ $# -gt 0 ]; do
  case "$1" in
    --container) CONTAINER="${2:-}"; shift 2;;
    --env) ENVFILE="${2:-}"; shift 2;;
    --state) STATE="${2:-}"; shift 2;;
    *) echo "未知参数：$1" >&2; exit 2;;
  esac
done
_is_active(){
  command -v ufw >/dev/null 2>&1 || return 1
  ufw status 2>/dev/null | grep -q "Status: active"
}
_num(){
  case "$1" in ''|*[!0-9]*) echo "";; *) if [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null; then echo "$1"; fi;; esac
}
_desired_from_docker(){
  local line hostport proto
  docker port "$CONTAINER" 2>/dev/null | while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in *' -> '*) ;;
      *) continue;;
    esac
    proto="${line%% *}"; proto="${proto##*/}"
    hostport="${line##*:}"
    hostport=$(_num "$hostport")
    if [ -n "$hostport" ] && [ "$proto" = "tcp" -o "$proto" = "udp" ]; then
      echo "$hostport/$proto"
    fi
  done | sort -u
}
_desired_from_env(){
  local p pr
  _add(){
    p=$(_num "$1"); if [ -z "$p" ]; then return; fi
    for pr in $2; do echo "$p/$pr"; done
  }
  _add "${vlpt:-}" "tcp"
  _add "${xhpt:-}" "tcp"
  _add "${vxpt:-}" "tcp"
  _add "${vwpt:-}" "tcp"
  _add "${xupt:-}" "udp"
  _add "${xcpt:-}" "tcp"
  _add "${nvpt:-}" "tcp"
  _add "${tupt:-}" "udp"
  _add "${anpt:-}" "tcp"
  _add "${arpt:-}" "tcp"
  _add "${sspt:-}" "tcp udp"
  _add "${hypt:-}" "udp"
  _add "${vmpt:-}" "tcp"
  _add "${vmtls:-}" "tcp"
  _add "${sopt:-}" "tcp udp"
}
_desired(){
  if [ -n "$CONTAINER" ]; then
    if ! command -v docker >/dev/null 2>&1; then echo "找不到 docker，无法读取容器 $CONTAINER 的发布端口" >&2; exit 1; fi
    _desired_from_docker
    return
  fi
  if [ -n "$ENVFILE" ]; then
    if [ ! -f "$ENVFILE" ]; then echo "找不到环境变量文件：$ENVFILE" >&2; exit 1; fi
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in ''|'#'*) continue;; esac
      name="${line%%=*}"; val="${line#*=}"
      case "$name" in *[!A-Za-z0-9_]*|'') continue;; esac
      eval "$name=\$val" 2>/dev/null || true
    done < "$ENVFILE"
    echo "注意：按 1:1 映射处理（宿主端口 = 容器内端口），桥接 -p 不一致时请用 --container" >&2
  fi
  _desired_from_env
}
case "$CMD" in
  print)
    _desired
    ;;
  apply)
    tmp="$STATE.tmp.$$"
    _desired | sort -u > "$tmp" || true
    if [ ! -s "$tmp" ]; then echo "没有可放行的节点端口，请检查容器名或环境变量" >&2; rm -f "$tmp"; exit 1; fi
    if ! _is_active; then
      mv "$tmp" "$STATE" 2>/dev/null || true
      echo "ufw 未开启，已记录节点端口规则，开启 ufw 后再次运行 bash ufw-host.sh apply"
      exit 0
    fi
    added=0; deleted=0
    if [ -f "$STATE" ]; then
      while IFS= read -r r || [ -n "$r" ]; do
        case "$r" in '') continue;; esac
        if ! grep -qx "$r" "$tmp" 2>/dev/null; then
          if ufw --force delete allow "$r" >/dev/null 2>&1; then deleted=$((deleted + 1)); else echo "ufw 删除规则失败（已忽略）：$r"; fi
        fi
      done < "$STATE"
    fi
    while IFS= read -r r || [ -n "$r" ]; do
      case "$r" in '') continue;; esac
      if [ ! -f "$STATE" ] || ! grep -qx "$r" "$STATE" 2>/dev/null; then
        if ufw allow "$r" >/dev/null 2>&1; then added=$((added + 1)); else echo "ufw 放行失败（已忽略）：$r"; fi
      fi
    done < "$tmp"
    mv "$tmp" "$STATE" 2>/dev/null || true
    echo "ufw 已同步容器节点端口规则（新增 $added 条，删除 $deleted 条）"
    ;;
  delete)
    if [ ! -f "$STATE" ]; then echo "没有记录的容器 ufw 规则，无需删除"; exit 0; fi
    if command -v ufw >/dev/null 2>&1; then
      while IFS= read -r r || [ -n "$r" ]; do
        case "$r" in '') continue;; esac
        ufw --force delete allow "$r" >/dev/null 2>&1 || true
      done < "$STATE"
    fi
    rm -f "$STATE"
    echo "已删除记录的容器 ufw 规则"
    ;;
  *)
    echo "用法：bash ufw-host.sh apply|delete|print [--container NAME] [--env FILE] [--state FILE]" >&2
    exit 2
    ;;
esac
