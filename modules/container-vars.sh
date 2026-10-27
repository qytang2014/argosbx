# Container incremental update state (private module, container build only).
# Same idea as the main script's vars.env, but for the container, whose
# start.sh is run on every container start (index.js runs `bash start.sh`,
# so this code runs under bash; if the file is ever run under dash
# directly, both functions no-op and the container falls back to the old
# env-only behaviour, instead of breaking on bash-only syntax).
# container_vars.env lives in $HOME/agsbx/ (container home), chmod 600,
# one %q-escaped assignment per line. It is saved after xrsbout in ins(),
# and loaded at the very top of start.sh, BEFORE the `export var=${var}`
# lines, because those lines turn every variable into a set (possibly
# empty) variable and would destroy the unset-vs-set distinction merge
# needs. So container_vars_merge must be called before the first export.
# Merge rule (same as main `add`, but without a subcommand, because the
# container has no subcommands): a variable already in the container env
# wins, a variable missing from the env inherits the saved value, and a
# variable in neither stays unset (then the export lines set it empty,
# which the container's `[ -n "$var" ]` protocol checks treat as off).
# Deleting a protocol in a container is done by restaging with a fresh
# env (or by removing the saved file), not by omitting a variable, since
# omission here means inherit, exactly like main `add`.
# egress_add is NOT saved (same reason as main): egress_init appends it
# to egress_nodes idempotently, and the save after xrsbout persists the
# merged egress_nodes, so the next start without egress_add keeps the
# appended nodes exactly once.
container_vars_merge(){
  [ -n "$BASH_VERSION" ] || return 0
  [ -s "$HOME/agsbx/container_vars.env" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue;; esac
    name="${line%%=*}"
    case "$name" in *[!A-Za-z0-9_]*|'') continue;; esac
    if [ -z "${!name+x}" ]; then eval "$line"; fi
  done < "$HOME/agsbx/container_vars.env"
}
container_vars_save(){
  [ -n "$BASH_VERSION" ] || return 0
  local f="$HOME/agsbx/container_vars.env" tmp
  tmp="$f.tmp.$$"
  : > "$tmp" 2>/dev/null || return 1
  for v in uuid vlpt vmpt vwpt hypt tupt xhpt vxpt anpt arpt sspt sopt reym cdnym argo agn agk ippz warp name ym egress_nodes egress_bind egress_rules; do
    if [ -n "${!v+x}" ]; then printf '%s=%q\n' "$v" "${!v}" >> "$tmp"; fi
  done
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$f" 2>/dev/null || return 1
}
