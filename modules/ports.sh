# ports.sh: consolidated port storage in $HOME/agsbx/ports.env
# Replaces the old per-protocol port_* files (port_vl_re, port_xh, ...).
# Format: KEY=VALUE per line, e.g. vl_re=12345
# Migration: on first use, imports old port_* files then deletes them.

_ports_file="$HOME/agsbx/ports.env"

ports_migrate(){
  local f="$HOME/agsbx/ports.env" old key val
  [ -f "$f" ] && return 0
  : > "$f" 2>/dev/null || return 1
  for old in "$HOME"/agsbx/port_*; do
    [ -f "$old" ] || continue
    key="${old##*/port_}"
    # skip non-port files that happen to match (e.g. port_file, port_var temp names)
    case "$key" in *[!a-z0-9_]*|'') continue;; esac
    val=$(tr -d ' \t\r\n' < "$old" 2>/dev/null)
    case "$val" in ''|*[!0-9]*) continue;; esac
    printf '%s=%s\n' "$key" "$val" >> "$f"
    rm -f "$old"
  done
  chmod 600 "$f" 2>/dev/null || true
}

port_get(){
  local key="$1" f="$HOME/agsbx/ports.env" line
  ports_migrate
  [ -f "$f" ] || return 1
  line=$(grep -E "^${key}=" "$f" 2>/dev/null | tail -1)
  [ -n "$line" ] || return 1
  printf '%s' "${line#*=}"
}

port_set(){
  local key="$1" val="$2" f="$HOME/agsbx/ports.env" tmp
  ports_migrate
  tmp="$f.tmp.$$"
  grep -vE "^${key}=" "$f" 2>/dev/null > "$tmp" || : > "$tmp"
  printf '%s=%s\n' "$key" "$val" >> "$tmp"
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$f" 2>/dev/null || return 1
}

# port_resolve KEY VAL: returns the effective port.
# - If VAL non-empty: use it, save to ports.env, return it.
# - Elif KEY in ports.env: return saved value.
# - Else: generate random, save, return it.
port_resolve(){
  local key="$1" val="$2" saved
  case "$val" in ''|*[!0-9]*)
    if [ -n "$val" ]; then
      echo "端口格式错误，已跳过：$val" >&2
      return 1
    fi
    ;;
  esac
  if [ -n "$val" ]; then
    port_set "$key" "$val"
    printf '%s' "$val"
    return 0
  fi
  saved=$(port_get "$key" 2>/dev/null)
  if [ -n "$saved" ]; then
    printf '%s' "$saved"
    return 0
  fi
  val=$(shuf -i 10000-65535 -n 1)
  port_set "$key" "$val"
  printf '%s' "$val"
}
