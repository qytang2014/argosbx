# Argosbx Lifecycle Hook Engine (modules/hook.sh)
# Clean event dispatching so modules register handlers instead of
# requiring fragile string replacements inside upstream logic.

# register_hook <event_name> <handler_function>
register_hook(){
  local event="$1" handler="$2"
  [ -n "$event" ] && [ -n "$handler" ] || return 0
  local current=""
  eval "current=\"\${_AGS_HOOK_${event}:-}\""
  case " $current " in
    *" $handler "*) ;;
    *) eval "_AGS_HOOK_${event}=\"\${current:+\$current }\$handler\"" ;;
  esac
}

# run_hook <event_name> [args...]
run_hook(){
  local event="$1"
  shift || return 0
  local handlers=""
  eval "handlers=\"\${_AGS_HOOK_${event}:-}\""
  for handler in $handlers; do
    if command -v "$handler" >/dev/null 2>&1; then
      "$handler" "$@" || true
    fi
  done
}
